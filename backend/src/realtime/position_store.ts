import { and, eq, inArray, isNull, sql } from 'drizzle-orm';

import type { Database } from '../db/client.js';
import { convoyMembers } from '../db/schema/convoys.js';
import { users } from '../db/schema/users.js';
import type { GpsPayload } from './wire.js';

/**
 * Persists + replays members' last-known GPS positions so a member who joins
 * or reconnects mid-drive sees the rest of the convoy immediately, instead of
 * an empty radar until each peer's next 1 Hz tick. The backend fan-out only
 * relays live frames and never echoes the sender, so without this there is no
 * way to recover a peer's position after a drop.
 */
export interface PositionStore {
  /** Stores `memberId`'s latest position for `convoyId`. */
  save(convoyId: string, memberId: string, gps: GpsPayload): Promise<void>;
  /**
   * Last-known position of every active member of `convoyId` except
   * `excludeMemberId` (the connecting member doesn't need its own back).
   */
  loadSnapshot(convoyId: string, excludeMemberId: string): Promise<GpsPayload[]>;
}

/** Drizzle/PostGIS-backed [PositionStore] writing `convoy_members`. */
export function createDbPositionStore(db: Database): PositionStore {
  return {
    async save(convoyId, memberId, gps) {
      // `memberId` is the external Firebase UID — resolve to the internal
      // users.id via apple_user_id. A geometry value assignment-casts into the
      // geography(Point,4326) column.
      const member = db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.appleUserId, memberId));
      await db
        .update(convoyMembers)
        .set({
          lastKnownPosition: sql`ST_SetSRID(ST_MakePoint(${gps.longitude}, ${gps.latitude}), 4326)`,
          lastPositionAt: new Date(gps.timestamp),
        })
        .where(
          and(
            eq(convoyMembers.convoyId, convoyId),
            inArray(convoyMembers.userId, member),
            isNull(convoyMembers.leftAt),
          ),
        );
    },
    async loadSnapshot(convoyId, excludeMemberId) {
      const rows = await db
        .select({
          memberId: users.appleUserId,
          lat: sql<number>`ST_Y(${convoyMembers.lastKnownPosition}::geometry)`,
          lng: sql<number>`ST_X(${convoyMembers.lastKnownPosition}::geometry)`,
          at: convoyMembers.lastPositionAt,
        })
        .from(convoyMembers)
        .innerJoin(users, eq(convoyMembers.userId, users.id))
        .where(
          and(
            eq(convoyMembers.convoyId, convoyId),
            isNull(convoyMembers.leftAt),
            sql`${convoyMembers.lastKnownPosition} IS NOT NULL`,
          ),
        );
      const snapshot: GpsPayload[] = [];
      for (const row of rows) {
        if (row.memberId === excludeMemberId) continue;
        if (row.lat === null || row.lng === null) continue;
        snapshot.push({
          // heading/speed aren't persisted; a stale snapshot point is enough —
          // the next live frame replaces it with full motion data.
          memberId: row.memberId,
          latitude: row.lat,
          longitude: row.lng,
          heading: 0,
          speed: 0,
          timestamp: (row.at ?? new Date()).toISOString(),
        });
      }
      return snapshot;
    },
  };
}
