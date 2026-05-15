import type { FastifyInstance } from 'fastify';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';

import { loadEnv } from '../../src/config/env.js';
import { createDatabase, type DatabaseHandle } from '../../src/db/client.js';
import { applyMigrations } from '../../src/db/migrate.js';
import { convoys, users, vehicles } from '../../src/db/schema/index.js';
import { buildApp } from '../../src/server.js';
import type { VehicleApiPayload } from '../../src/services/vehicles.js';

const databaseUrl = process.env.DATABASE_URL;
const describeIfDb = databaseUrl ? describe : describe.skip;

function bearer(token: string): { authorization: string } {
  return { authorization: `Bearer ${token}` };
}

describeIfDb('vehicle routes', () => {
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
    await dbHandle.db.delete(vehicles);
    await dbHandle.db.delete(convoys);
    await dbHandle.db.delete(users);
  });

  it('rejects requests without bearer token', async () => {
    const res = await app.inject({ method: 'GET', url: '/vehicles/me' });
    expect(res.statusCode).toBe(401);
  });

  it('GET returns null when user has no vehicle', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/vehicles/me',
      headers: bearer('alice'),
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toBeNull();
  });

  it('PUT creates a vehicle and returns it', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: {
        make: 'Tesla',
        model: 'Model 3 Performance',
        year: 2024,
        color: 'Indigoblau',
      },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json() as VehicleApiPayload;
    expect(body.make).toBe('Tesla');
    expect(body.model).toBe('Model 3 Performance');
    expect(body.year).toBe(2024);
    expect(body.color).toBe('Indigoblau');
  });

  it('PUT replaces an existing vehicle (single-vehicle invariant)',
      async () => {
    await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: { make: 'BMW', model: 'M2', year: 2023 },
    });
    const second = await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: { make: 'Porsche', model: '911 GT3' },
    });
    expect(second.statusCode).toBe(200);
    expect((second.json() as VehicleApiPayload).make).toBe('Porsche');

    const get = await app.inject({
      method: 'GET',
      url: '/vehicles/me',
      headers: bearer('alice'),
    });
    const after = get.json() as VehicleApiPayload;
    expect(after.make).toBe('Porsche');
    expect(after.model).toBe('911 GT3');
  });

  it('PUT rejects invalid year', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: { make: 'Tesla', model: 'X', year: 1800 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('PUT with mods inserts them and GET returns them', async () => {
    const put = await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: {
        make: 'Tesla',
        model: 'Model 3 Performance',
        year: 2024,
        color: 'Indigoblau',
        mods: [
          { name: 'Performance-Wheels', category: 'wheels' },
          { name: 'Sport-Spoiler', description: 'Carbon', category: 'exterior' },
        ],
      },
    });
    expect(put.statusCode).toBe(200);
    const created = put.json() as VehicleApiPayload;
    expect(created.mods).toHaveLength(2);
    expect(created.mods[0]!.id).toMatch(/^[0-9a-f-]{36}$/i);
    expect(created.mods.map((m) => m.name)).toContain('Performance-Wheels');

    const get = await app.inject({
      method: 'GET',
      url: '/vehicles/me',
      headers: bearer('alice'),
    });
    const after = get.json() as VehicleApiPayload;
    expect(after.mods).toHaveLength(2);
  });

  it('PUT replaces mods on each call (no accumulation)', async () => {
    await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: {
        make: 'BMW',
        model: 'M2',
        mods: [{ name: 'Roll-Cage' }, { name: 'Track-Brakes' }],
      },
    });
    const second = await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: {
        make: 'BMW',
        model: 'M2',
        mods: [{ name: 'Lowered-Suspension' }],
      },
    });
    const body = second.json() as VehicleApiPayload;
    expect(body.mods).toHaveLength(1);
    expect(body.mods[0]!.name).toBe('Lowered-Suspension');
  });

  it('DELETE removes the vehicle', async () => {
    await app.inject({
      method: 'PUT',
      url: '/vehicles/me',
      headers: bearer('alice'),
      payload: { make: 'BMW', model: 'M2' },
    });
    const del = await app.inject({
      method: 'DELETE',
      url: '/vehicles/me',
      headers: bearer('alice'),
    });
    expect(del.statusCode).toBe(204);

    const get = await app.inject({
      method: 'GET',
      url: '/vehicles/me',
      headers: bearer('alice'),
    });
    expect(get.json()).toBeNull();
  });
});
