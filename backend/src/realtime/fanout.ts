export interface LocalSender {
  memberId: string;
  send: (data: string) => void;
}

/**
 * Abstracts GPS-frame distribution across convoy members.
 *
 * InProcessFanout: single-instance, in-memory (dev / integration tests).
 * RedisFanout: pub/sub via Redis for multi-instance deployments.
 */
export interface FanoutAdapter {
  publish(convoyId: string, encodedFrame: string, originMemberId: string): Promise<void>;
  addLocalConnection(convoyId: string, conn: LocalSender): () => void;
  close(): Promise<void>;
}

export class InProcessFanout implements FanoutAdapter {
  private readonly registry = new Map<string, Set<LocalSender>>();

  async publish(convoyId: string, encodedFrame: string, originMemberId: string): Promise<void> {
    const pool = this.registry.get(convoyId);
    if (!pool) return;
    for (const conn of pool) {
      if (conn.memberId !== originMemberId) {
        conn.send(encodedFrame);
      }
    }
  }

  addLocalConnection(convoyId: string, conn: LocalSender): () => void {
    let pool = this.registry.get(convoyId);
    if (!pool) {
      pool = new Set();
      this.registry.set(convoyId, pool);
    }
    pool.add(conn);
    return () => {
      const set = this.registry.get(convoyId);
      if (!set) return;
      set.delete(conn);
      if (set.size === 0) this.registry.delete(convoyId);
    };
  }

  async close(): Promise<void> {
    this.registry.clear();
  }
}
