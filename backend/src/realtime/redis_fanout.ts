import { randomUUID } from 'node:crypto';

import { Redis } from 'ioredis';

import type { FanoutAdapter, LocalSender } from './fanout.js';

const CHANNEL_PREFIX = 'crewlink:convoy:';

interface RedisMessage {
  frame: string;
  originMemberId: string;
  instanceId: string;
}

/**
 * Redis pub/sub fanout — required when the WS gateway runs as multiple
 * instances. Each instance delivers frames directly to its own local
 * WebSocket connections (no round-trip) and publishes to Redis so remote
 * instances receive them. The instanceId prevents double-delivery on the
 * publishing instance.
 *
 * Lifecycle: call connect() after construction, close() on server shutdown.
 */
export class RedisFanout implements FanoutAdapter {
  private readonly instanceId = randomUUID();
  private readonly pub: Redis;
  private readonly sub: Redis;
  private readonly localConns = new Map<string, Set<LocalSender>>();

  constructor(redisUrl: string) {
    this.pub = new Redis(redisUrl, { lazyConnect: true });
    this.sub = new Redis(redisUrl, { lazyConnect: true });
    // Prevent unhandled 'error' events from crashing the process on transient
    // network blips. ioredis auto-reconnects; we just log and continue.
    this.pub.on('error', (err: unknown) => {
      console.error('[RedisFanout] pub connection error:', err);
    });
    this.sub.on('error', (err: unknown) => {
      console.error('[RedisFanout] sub connection error:', err);
    });
  }

  async connect(): Promise<void> {
    await Promise.all([this.pub.connect(), this.sub.connect()]);
    this.sub.on('message', (channel: string, message: string) => {
      if (!channel.startsWith(CHANNEL_PREFIX)) return;
      const convoyId = channel.slice(CHANNEL_PREFIX.length);
      let parsed: RedisMessage;
      try {
        parsed = JSON.parse(message) as RedisMessage;
      } catch {
        return;
      }
      // Skip messages we published ourselves — already delivered locally.
      if (parsed.instanceId === this.instanceId) return;
      const pool = this.localConns.get(convoyId);
      if (!pool) return;
      for (const conn of pool) {
        if (conn.memberId !== parsed.originMemberId) {
          conn.send(parsed.frame);
        }
      }
    });
  }

  async publish(convoyId: string, encodedFrame: string, originMemberId: string): Promise<void> {
    // Deliver directly to local connections — no Redis round-trip, no race.
    const pool = this.localConns.get(convoyId);
    if (pool) {
      for (const conn of pool) {
        if (conn.memberId !== originMemberId) {
          conn.send(encodedFrame);
        }
      }
    }
    // Broadcast to remote instances via Redis.
    const msg: RedisMessage = {
      frame: encodedFrame,
      originMemberId,
      instanceId: this.instanceId,
    };
    await this.pub.publish(`${CHANNEL_PREFIX}${convoyId}`, JSON.stringify(msg));
  }

  addLocalConnection(convoyId: string, conn: LocalSender): () => void {
    let pool = this.localConns.get(convoyId);
    const isFirst = !pool || pool.size === 0;
    if (!pool) {
      pool = new Set();
      this.localConns.set(convoyId, pool);
    }
    pool.add(conn);
    if (isFirst) {
      this.sub.subscribe(`${CHANNEL_PREFIX}${convoyId}`).catch((err: unknown) => {
        console.error(`[RedisFanout] subscribe failed for convoy ${convoyId}:`, err);
      });
    }
    return () => {
      const set = this.localConns.get(convoyId);
      if (!set) return;
      set.delete(conn);
      if (set.size === 0) {
        this.localConns.delete(convoyId);
        this.sub.unsubscribe(`${CHANNEL_PREFIX}${convoyId}`).catch((err: unknown) => {
          console.error(`[RedisFanout] unsubscribe failed for convoy ${convoyId}:`, err);
        });
      }
    };
  }

  async close(): Promise<void> {
    await Promise.all([this.sub.quit(), this.pub.quit()]);
    this.localConns.clear();
  }
}
