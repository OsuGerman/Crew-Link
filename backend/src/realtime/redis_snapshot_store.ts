import { Redis } from 'ioredis';

import type { SnapshotStore } from './snapshot_store.js';
import type {
  HazardPayload,
  InboundFrame,
  OutboundFrame,
  TourPayload,
  WaypointPayload,
} from './wire.js';

// One hash per convoy, namespaced like the RedisFanout channels.
const KEY_PREFIX = 'crewlink:snapshot:';
const HAZARD_FIELD_PREFIX = 'hazard:';
const TOUR_FIELD = 'tour';
const WAYPOINT_FIELD = 'waypoint';

/** Snapshot lifetime — outlives any realistic drive, but abandoned convoys
 * never leak state in Redis. Refreshed on every recorded frame. */
export const SNAPSHOT_TTL_SECONDS = 24 * 60 * 60;

/** Pino-compatible logger slice (no console.error — see CLAUDE.md). */
interface SnapshotLogger {
  error: (obj: unknown, msg?: string) => void;
}

/**
 * Redis-backed [SnapshotStore] — required when the WS gateway runs as
 * multiple instances: every node folds broadcasts into the same per-convoy
 * hash, so late joiners get an identical replay regardless of which instance
 * they land on, and reporter-only hazard removal keeps working across nodes.
 *
 * Layout: one hash per convoy under `crewlink:snapshot:<convoyId>` with
 * fields `hazard:<id>` → [HazardPayload] JSON, `tour` → [TourPayload] JSON,
 * `waypoint` → [WaypointPayload] JSON.
 *
 * Same connection pattern as [RedisFanout]: lazyConnect + explicit connect(),
 * close() on shutdown, and an error listener so transient network blips never
 * crash the process (ioredis auto-reconnects).
 */
export class RedisSnapshotStore implements SnapshotStore {
  private readonly redis: Redis;
  private readonly now: () => number;

  constructor(
    redisUrl: string,
    private readonly log: SnapshotLogger,
    now: () => number = () => Date.now(),
  ) {
    this.now = now;
    this.redis = new Redis(redisUrl, { lazyConnect: true });
    this.redis.on('error', (err: unknown) => {
      this.log.error({ err }, 'redis snapshot store connection error');
    });
  }

  async connect(): Promise<void> {
    await this.redis.connect();
  }

  async close(): Promise<void> {
    await this.redis.quit();
  }

  async record(convoyId: string, frame: InboundFrame): Promise<void> {
    const key = keyFor(convoyId);
    switch (frame.type) {
      case 'hazard':
        await this.redis.hset(
          key,
          HAZARD_FIELD_PREFIX + frame.payload.id,
          JSON.stringify(frame.payload),
        );
        break;
      case 'hazard_remove':
        await this.redis.hdel(key, HAZARD_FIELD_PREFIX + frame.payload.id);
        break;
      case 'tour':
        // Empty stop list = cleared route.
        if (frame.payload.stops.length > 0) {
          await this.redis.hset(key, TOUR_FIELD, JSON.stringify(frame.payload));
        } else {
          await this.redis.hdel(key, TOUR_FIELD);
        }
        break;
      case 'waypoint':
        // null = leader cleared the active waypoint.
        if (frame.payload !== null) {
          await this.redis.hset(
            key,
            WAYPOINT_FIELD,
            JSON.stringify(frame.payload),
          );
        } else {
          await this.redis.hdel(key, WAYPOINT_FIELD);
        }
        break;
      default:
        // gps / checkin / status are transient — never snapshotted.
        return;
    }
    await this.redis.expire(key, SNAPSHOT_TTL_SECONDS);
  }

  async snapshot(convoyId: string): Promise<OutboundFrame[]> {
    const key = keyFor(convoyId);
    const fields = await this.redis.hgetall(key);
    const ts = this.now();
    const frames: OutboundFrame[] = [];
    for (const [field, value] of Object.entries(fields)) {
      const frame = this.decodeField(convoyId, field, value);
      if (frame === null) continue;
      if (
        frame.type === 'hazard' &&
        frame.payload.expiresAt !== undefined &&
        Date.parse(frame.payload.expiresAt) <= ts
      ) {
        await this.redis.hdel(key, field); // prune expired hazards
        continue;
      }
      frames.push(frame);
    }
    return frames;
  }

  async clear(convoyId: string): Promise<void> {
    await this.redis.del(keyFor(convoyId));
  }

  async hazardReporter(
    convoyId: string,
    hazardId: string,
  ): Promise<string | undefined> {
    const field = HAZARD_FIELD_PREFIX + hazardId;
    const value = await this.redis.hget(keyFor(convoyId), field);
    if (value === null) return undefined;
    const frame = this.decodeField(convoyId, field, value);
    return frame?.type === 'hazard' ? frame.payload.reporterId : undefined;
  }

  /** Parses a hash field back into a frame; corrupt JSON is logged + skipped
   * so a single bad entry can never break the whole replay. */
  private decodeField(
    convoyId: string,
    field: string,
    value: string,
  ): OutboundFrame | null {
    try {
      if (field.startsWith(HAZARD_FIELD_PREFIX)) {
        return { type: 'hazard', payload: JSON.parse(value) as HazardPayload };
      }
      if (field === TOUR_FIELD) {
        return { type: 'tour', payload: JSON.parse(value) as TourPayload };
      }
      if (field === WAYPOINT_FIELD) {
        return {
          type: 'waypoint',
          payload: JSON.parse(value) as WaypointPayload,
        };
      }
      return null;
    } catch (err) {
      this.log.error({ err, convoyId, field }, 'corrupt snapshot field skipped');
      return null;
    }
  }
}

function keyFor(convoyId: string): string {
  return KEY_PREFIX + convoyId;
}
