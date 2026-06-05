import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import { createDatabase, type DatabaseHandle } from '../../src/db/client.js';
import { applyMigrations } from '../../src/db/migrate.js';
import { convoyMembers, convoys, users } from '../../src/db/schema/index.js';
import { createDbPositionStore } from '../../src/realtime/position_store.js';
import type { GpsPayload } from '../../src/realtime/wire.js';

const databaseUrl = process.env.DATABASE_URL;
const describeIfDb = databaseUrl ? describe : describe.skip;

function gps(memberId: string, lat: number, lng: number): GpsPayload {
  return {
    memberId,
    latitude: lat,
    longitude: lng,
    heading: 90,
    speed: 12,
    timestamp: '2026-06-05T12:00:00.000Z',
  };
}

describeIfDb('PositionStore', () => {
  let dbHandle: DatabaseHandle;
  const store = () => createDbPositionStore(dbHandle.db);

  beforeAll(async () => {
    await applyMigrations(databaseUrl!);
    dbHandle = createDatabase({ url: databaseUrl!, max: 1 });
  }, 30_000);

  afterAll(async () => {
    await dbHandle.sql.end();
  });

  afterEach(async () => {
    // convoy_members cascade-delete with their convoy.
    await dbHandle.db.delete(convoys);
    await dbHandle.db.delete(users);
  });

  async function seedMember(uid: string): Promise<string> {
    const [user] = await dbHandle.db
      .insert(users)
      .values({ appleUserId: uid, displayName: uid })
      .returning();
    const [convoy] = await dbHandle.db
      .insert(convoys)
      .values({ ownerUserId: user!.id, name: 'Trip', inviteCode: uid })
      .returning();
    await dbHandle.db
      .insert(convoyMembers)
      .values({ convoyId: convoy!.id, userId: user!.id, role: 'owner' });
    return convoy!.id;
  }

  it('save then loadSnapshot returns the persisted position', async () => {
    const convoyId = await seedMember('alice-uid');
    await store().save(convoyId, 'alice-uid', gps('alice-uid', 48.1374, 11.5755));

    const snap = await store().loadSnapshot(convoyId, 'bob-uid');
    expect(snap).toHaveLength(1);
    expect(snap[0]!.memberId).toBe('alice-uid');
    expect(snap[0]!.latitude).toBeCloseTo(48.1374, 3);
    expect(snap[0]!.longitude).toBeCloseTo(11.5755, 3);
  });

  it('loadSnapshot excludes the requesting member', async () => {
    const convoyId = await seedMember('alice-uid');
    await store().save(convoyId, 'alice-uid', gps('alice-uid', 48.1, 11.5));

    const snap = await store().loadSnapshot(convoyId, 'alice-uid');
    expect(snap).toHaveLength(0);
  });

  it('loadSnapshot omits members without a stored position', async () => {
    const convoyId = await seedMember('alice-uid');
    // No save() → last_known_position stays NULL.
    const snap = await store().loadSnapshot(convoyId, 'bob-uid');
    expect(snap).toHaveLength(0);
  });
});
