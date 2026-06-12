import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { HazardPayload } from '../../src/realtime/wire.js';

// ── ioredis mock ────────────────────────────────────────────────────────────
// In-memory hash semantics so no real Redis broker is needed in CI.
function makeRedisHashMock() {
  const hashes = new Map<string, Map<string, string>>();
  const mock = {
    connect: vi.fn().mockResolvedValue(undefined),
    quit: vi.fn().mockResolvedValue(undefined),
    on: vi.fn().mockImplementation(() => mock),
    expire: vi.fn().mockResolvedValue(1),
    hset: vi.fn().mockImplementation((key: string, field: string, value: string) => {
      if (!hashes.has(key)) hashes.set(key, new Map());
      hashes.get(key)!.set(field, value);
      return Promise.resolve(1);
    }),
    hdel: vi.fn().mockImplementation((key: string, field: string) => {
      hashes.get(key)?.delete(field);
      return Promise.resolve(1);
    }),
    hget: vi.fn().mockImplementation((key: string, field: string) =>
      Promise.resolve(hashes.get(key)?.get(field) ?? null),
    ),
    hgetall: vi.fn().mockImplementation((key: string) =>
      Promise.resolve(Object.fromEntries(hashes.get(key) ?? [])),
    ),
    del: vi.fn().mockImplementation((key: string) => {
      hashes.delete(key);
      return Promise.resolve(1);
    }),
    _hashes: hashes,
  };
  return mock;
}

let redisMock: ReturnType<typeof makeRedisHashMock>;

vi.mock('ioredis', () => ({
  Redis: vi.fn().mockImplementation(() => redisMock),
}));

// Import AFTER mock is set up
const { RedisSnapshotStore, SNAPSHOT_TTL_SECONDS } = await import(
  '../../src/realtime/redis_snapshot_store.js'
);

// ── helpers ─────────────────────────────────────────────────────────────────
const CONVOY = 'c1';
const REPORTER = 'm1';
const OTHER_MEMBER = 'm2';

function hazard(id: string, expiresAt?: string): HazardPayload {
  return {
    id,
    type: 'accident',
    latitude: 48,
    longitude: 11,
    reporterId: REPORTER,
    createdAt: '2026-06-06T12:00:00Z',
    ...(expiresAt !== undefined ? { expiresAt } : {}),
  };
}

function makeStore(now?: () => number) {
  const log = { error: vi.fn() };
  const store = new RedisSnapshotStore('redis://localhost:6379', log, now);
  return { store, log };
}

// ── tests ───────────────────────────────────────────────────────────────────
describe('RedisSnapshotStore', () => {
  beforeEach(() => {
    redisMock = makeRedisHashMock();
  });

  it('replays recorded hazards, tour and waypoint to a late joiner', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await store.record(CONVOY, {
      type: 'tour',
      payload: {
        stops: [
          { latitude: 48, longitude: 11.5, label: 'Stop', setBy: REPORTER, setAt: '2026-06-06T12:00:00Z' },
        ],
      },
    });
    await store.record(CONVOY, {
      type: 'waypoint',
      payload: { latitude: 48, longitude: 12, label: 'WP', setBy: REPORTER, setAt: '2026-06-06T12:00:00Z' },
    });

    const frames = await store.snapshot(CONVOY);
    expect(frames).toContainEqual({ type: 'hazard', payload: hazard('h1') });
    expect(frames.some((f) => f.type === 'tour')).toBe(true);
    expect(frames.some((f) => f.type === 'waypoint')).toBe(true);
    // Other convoys stay isolated.
    await expect(store.snapshot('other')).resolves.toEqual([]);
  });

  it('tracks the hazard reporter so the gateway can drop foreign removals', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });

    // The gateway drops hazard_remove when reporter !== sender.
    const reporter = await store.hazardReporter(CONVOY, 'h1');
    expect(reporter).toBe(REPORTER);
    expect(reporter).not.toBe(OTHER_MEMBER);

    // Unknown hazards have no reporter → removal passes through.
    await expect(store.hazardReporter(CONVOY, 'nope')).resolves.toBeUndefined();

    // Removal by the reporter drops the hazard from the snapshot.
    await store.record(CONVOY, { type: 'hazard_remove', payload: { id: 'h1' } });
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
    await expect(store.hazardReporter(CONVOY, 'h1')).resolves.toBeUndefined();
  });

  it('refreshes the 24h TTL on every recorded frame', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    expect(redisMock.expire).toHaveBeenCalledWith(
      expect.stringContaining(CONVOY),
      SNAPSHOT_TTL_SECONDS,
    );
  });

  it('ignores transient frames (no write, no TTL)', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, {
      type: 'status',
      payload: { memberId: REPORTER, kind: 'pause', at: '2026-06-06T12:00:00Z' },
    });
    expect(redisMock.hset).not.toHaveBeenCalled();
    expect(redisMock.expire).not.toHaveBeenCalled();
  });

  it('prunes expired hazards on snapshot', async () => {
    let nowMs = Date.parse('2026-06-06T12:00:00Z');
    const { store } = makeStore(() => nowMs);
    await store.record(CONVOY, {
      type: 'hazard',
      payload: hazard('h1', '2026-06-06T12:30:00Z'),
    });
    await expect(store.snapshot(CONVOY)).resolves.toHaveLength(1);

    nowMs = Date.parse('2026-06-06T13:00:00Z'); // past expiry
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
    expect(redisMock.hdel).toHaveBeenCalled(); // pruned from the hash too
  });

  it('empty tour and null waypoint clear their fields', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, {
      type: 'waypoint',
      payload: { latitude: 48, longitude: 12, label: 'WP', setBy: REPORTER, setAt: '2026-06-06T12:00:00Z' },
    });
    await store.record(CONVOY, { type: 'tour', payload: { stops: [] } });
    await store.record(CONVOY, { type: 'waypoint', payload: null });
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });

  it('clear() drops the convoy hash', async () => {
    const { store } = makeStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await store.clear(CONVOY);
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });

  it('skips and logs corrupt fields instead of failing the replay', async () => {
    const { store, log } = makeStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    redisMock._hashes.get('crewlink:snapshot:c1')!.set('hazard:bad', '{not json');

    const frames = await store.snapshot(CONVOY);
    expect(frames).toHaveLength(1);
    expect(log.error).toHaveBeenCalled();
  });

  it('connect/close manage the underlying redis connection', async () => {
    const { store } = makeStore();
    await store.connect();
    await store.close();
    expect(redisMock.connect).toHaveBeenCalledOnce();
    expect(redisMock.quit).toHaveBeenCalledOnce();
  });
});
