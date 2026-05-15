import { eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createDatabase, type DatabaseHandle } from '../../src/db/client.js';
import { applyMigrations } from '../../src/db/migrate.js';
import { convoyMembers, convoys, users } from '../../src/db/schema/index.js';

const databaseUrl = process.env.DATABASE_URL;
const describeIfDb = databaseUrl ? describe : describe.skip;

describeIfDb('PostGIS schema integration', () => {
  let handle: DatabaseHandle;

  beforeAll(async () => {
    await applyMigrations(databaseUrl!);
    handle = createDatabase({ url: databaseUrl!, max: 1 });
  }, 30_000);

  afterAll(async () => {
    if (handle) {
      await handle.sql.end();
    }
  });

  it('round-trips a user', async () => {
    const appleUserId = `apple-test-${Date.now()}-${Math.random()}`;

    const [created] = await handle.db
      .insert(users)
      .values({ appleUserId, displayName: 'Schema Test' })
      .returning();
    expect(created).toBeDefined();
    expect(created!.id).toMatch(/^[0-9a-f-]{36}$/i);

    const [found] = await handle.db
      .select()
      .from(users)
      .where(eq(users.id, created!.id));
    expect(found?.appleUserId).toBe(appleUserId);

    await handle.db.delete(users).where(eq(users.id, created!.id));
  });

  it('enforces unique convoy invite codes', async () => {
    const ownerAppleId = `apple-owner-${Date.now()}-${Math.random()}`;
    const [owner] = await handle.db
      .insert(users)
      .values({ appleUserId: ownerAppleId, displayName: 'Owner' })
      .returning();

    const inviteCode = `TEST-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

    await handle.db.insert(convoys).values({
      ownerUserId: owner!.id,
      name: 'Test Convoy',
      inviteCode,
    });

    await expect(
      handle.db.insert(convoys).values({
        ownerUserId: owner!.id,
        name: 'Duplicate Convoy',
        inviteCode,
      }),
    ).rejects.toThrow();

    await handle.db.delete(users).where(eq(users.id, owner!.id));
  });

  it('stores and reads a PostGIS geography point on convoy_members', async () => {
    const appleId = `apple-geo-${Date.now()}-${Math.random()}`;
    const [user] = await handle.db
      .insert(users)
      .values({ appleUserId: appleId, displayName: 'Geo User' })
      .returning();

    const inviteCode = `GEO-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
    const [convoy] = await handle.db
      .insert(convoys)
      .values({
        ownerUserId: user!.id,
        name: 'Geo Convoy',
        inviteCode,
      })
      .returning();

    const lng = 13.4050;
    const lat = 52.5200;

    await handle.db.execute(sql`
      INSERT INTO convoy_members (convoy_id, user_id, role, last_known_position, last_position_at)
      VALUES (
        ${convoy!.id},
        ${user!.id},
        'owner',
        ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography,
        now()
      )
    `);

    const result = await handle.db.execute<{
      lng: number;
      lat: number;
      distance_m: number;
    }>(sql`
      SELECT
        ST_X(last_known_position::geometry) AS lng,
        ST_Y(last_known_position::geometry) AS lat,
        ST_Distance(
          last_known_position,
          ST_SetSRID(ST_MakePoint(13.4250, 52.5200), 4326)::geography
        ) AS distance_m
      FROM convoy_members
      WHERE user_id = ${user!.id}
    `);

    const row = result[0];
    expect(row).toBeDefined();
    expect(Number(row!.lng)).toBeCloseTo(lng, 4);
    expect(Number(row!.lat)).toBeCloseTo(lat, 4);
    expect(Number(row!.distance_m)).toBeGreaterThan(1000);
    expect(Number(row!.distance_m)).toBeLessThan(2000);

    await handle.db.delete(convoyMembers).where(eq(convoyMembers.userId, user!.id));
    await handle.db.delete(convoys).where(eq(convoys.id, convoy!.id));
    await handle.db.delete(users).where(eq(users.id, user!.id));
  });
});
