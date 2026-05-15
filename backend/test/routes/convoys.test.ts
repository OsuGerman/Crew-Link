import type { FastifyInstance } from 'fastify';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import { loadEnv } from '../../src/config/env.js';
import { createDatabase, type DatabaseHandle } from '../../src/db/client.js';
import { applyMigrations } from '../../src/db/migrate.js';
import { convoys, users, vehicles } from '../../src/db/schema/index.js';
import { buildApp } from '../../src/server.js';
import type { ConvoyApiPayload } from '../../src/services/convoys.js';

const databaseUrl = process.env.DATABASE_URL;
const describeIfDb = databaseUrl ? describe : describe.skip;

function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}

describeIfDb('convoy lifecycle routes', () => {
  let app: FastifyInstance;
  let dbHandle: DatabaseHandle;

  beforeAll(async () => {
    await applyMigrations(databaseUrl!);
    const env = loadEnv({
      NODE_ENV: 'test',
      LOG_LEVEL: 'fatal',
      DATABASE_URL: databaseUrl!,
    });
    app = await buildApp({ env });
    dbHandle = createDatabase({ url: databaseUrl!, max: 1 });
  }, 30_000);

  afterAll(async () => {
    await app.close();
    await dbHandle.sql.end();
  });

  afterEach(async () => {
    // Order: convoys (cascade convoy_members) → vehicles (FK to users) → users.
    await dbHandle.db.delete(convoys);
    await dbHandle.db.delete(vehicles);
    await dbHandle.db.delete(users);
  });

  it('rejects POST /convoys without a bearer token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/convoys',
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    expect(res.statusCode).toBe(401);
  });

  it('rejects malformed bearer token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: { authorization: 'Bearer    ' },
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    expect(res.statusCode).toBe(401);
  });

  it('creates a convoy and lists the creator as owner member', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice-apple-id'),
      payload: { name: 'Saturday Cruise', proximityWarningMeters: 750 },
    });
    expect(res.statusCode).toBe(201);
    const body = res.json() as ConvoyApiPayload;
    expect(body.name).toBe('Saturday Cruise');
    expect(body.proximityWarningMeters).toBe(750);
    expect(body.inviteCode).toMatch(/^[A-Z2-9]{6}$/);
    expect(body.members).toHaveLength(1);
    expect(body.members[0]!.isLeader).toBe(true);
    expect(body.members[0]!.displayName).toContain('Dev');
    expect(body.members[0]!.vehicleProfileId).toBeNull();
    expect(body.members[0]!.vehicle).toBeNull();
  });

  it('inlines the member vehicle when one has been set via PUT /vehicles/me',
      async () => {
    await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: {
        make: 'Tesla',
        model: 'Model 3 Performance',
        year: 2024,
        mods: [{ name: 'Performance-Wheels', category: 'wheels' }],
      },
    });
    const res = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice'),
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    const body = res.json() as ConvoyApiPayload;
    expect(body.members).toHaveLength(1);
    expect(body.members[0]!.vehicle).not.toBeNull();
    expect(body.members[0]!.vehicle!.make).toBe('Tesla');
    expect(body.members[0]!.vehicle!.year).toBe(2024);
    expect(body.members[0]!.vehicle!.mods).toHaveLength(1);
    expect(body.members[0]!.vehicle!.mods[0]!.name).toBe('Performance-Wheels');
  });

  it('rejects empty name with 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice'),
      payload: { name: '', proximityWarningMeters: 500 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('joins a convoy via invite code and lists both members', async () => {
    const created = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice-apple-id'),
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    const { inviteCode } = created.json() as ConvoyApiPayload;

    const joined = await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('bob-apple-id'),
      payload: { inviteCode },
    });
    expect(joined.statusCode).toBe(200);
    const body = joined.json() as ConvoyApiPayload;
    expect(body.members).toHaveLength(2);
    const roles = body.members.map((m) => m.isLeader);
    expect(roles.filter(Boolean)).toHaveLength(1);
  });

  it('returns 404 for unknown invite code', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('alice'),
      payload: { inviteCode: 'NOPE99' },
    });
    expect(res.statusCode).toBe(404);
  });

  it('join is idempotent when already a member', async () => {
    const created = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice'),
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    const { inviteCode } = created.json() as ConvoyApiPayload;

    const first = await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('bob'),
      payload: { inviteCode },
    });
    const second = await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('bob'),
      payload: { inviteCode },
    });
    expect(first.statusCode).toBe(200);
    expect(second.statusCode).toBe(200);
    expect((second.json() as ConvoyApiPayload).members).toHaveLength(2);
  });

  it('leave removes member from listing and is idempotent', async () => {
    const created = await app.inject({
      method: 'POST',
      url: '/convoys',
      headers: bearer('alice'),
      payload: { name: 'Trip', proximityWarningMeters: 500 },
    });
    const { id, inviteCode } = created.json() as ConvoyApiPayload;

    await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('bob'),
      payload: { inviteCode },
    });

    const leave1 = await app.inject({
      method: 'DELETE',
      url: `/convoys/${id}/membership`,
      headers: bearer('bob'),
    });
    expect(leave1.statusCode).toBe(204);

    const leave2 = await app.inject({
      method: 'DELETE',
      url: `/convoys/${id}/membership`,
      headers: bearer('bob'),
    });
    expect(leave2.statusCode).toBe(204);

    const rejoin = await app.inject({
      method: 'POST',
      url: '/convoys/join',
      headers: bearer('bob'),
      payload: { inviteCode },
    });
    expect(rejoin.statusCode).toBe(200);
    expect((rejoin.json() as ConvoyApiPayload).members).toHaveLength(2);
  });
});
