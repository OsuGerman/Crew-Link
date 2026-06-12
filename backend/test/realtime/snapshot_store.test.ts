import { describe, expect, it } from 'vitest';

import { createInMemorySnapshotStore } from '../../src/realtime/snapshot_store.js';
import type {
  HazardPayload,
  TourPayload,
  WaypointPayload,
} from '../../src/realtime/wire.js';

const CONVOY = 'c1';

function hazard(id: string, expiresAt?: string): HazardPayload {
  return {
    id,
    type: 'accident',
    latitude: 48,
    longitude: 11,
    reporterId: 'm1',
    createdAt: '2026-06-06T12:00:00Z',
    ...(expiresAt !== undefined ? { expiresAt } : {}),
  };
}

const tour: TourPayload = {
  stops: [
    {
      latitude: 48,
      longitude: 11.5,
      label: 'Stop',
      setBy: 'm1',
      setAt: '2026-06-06T12:00:00Z',
    },
  ],
};

const waypoint: WaypointPayload = {
  latitude: 48,
  longitude: 12,
  label: 'WP',
  setBy: 'm1',
  setAt: '2026-06-06T12:00:00Z',
};

describe('InMemorySnapshotStore', () => {
  it('replays recorded hazards, tour and waypoint', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await store.record(CONVOY, { type: 'tour', payload: tour });
    await store.record(CONVOY, { type: 'waypoint', payload: waypoint });

    const frames = await store.snapshot(CONVOY);
    expect(frames).toContainEqual({ type: 'hazard', payload: hazard('h1') });
    expect(frames.some((f) => f.type === 'tour')).toBe(true);
    expect(frames.some((f) => f.type === 'waypoint')).toBe(true);
  });

  it('hazard_remove drops the hazard from the snapshot', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await store.record(CONVOY, { type: 'hazard_remove', payload: { id: 'h1' } });
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });

  it('exposes the reporter of a tracked hazard', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await expect(store.hazardReporter(CONVOY, 'h1')).resolves.toBe('m1');
    await expect(store.hazardReporter(CONVOY, 'nope')).resolves.toBeUndefined();
  });

  it('empty tour and null waypoint clear them', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, { type: 'tour', payload: tour });
    await store.record(CONVOY, { type: 'waypoint', payload: waypoint });
    await store.record(CONVOY, { type: 'tour', payload: { stops: [] } });
    await store.record(CONVOY, { type: 'waypoint', payload: null });
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });

  it('prunes expired hazards on snapshot', async () => {
    let nowMs = Date.parse('2026-06-06T12:00:00Z');
    const store = createInMemorySnapshotStore(() => nowMs);
    await store.record(CONVOY, {
      type: 'hazard',
      payload: hazard('h1', '2026-06-06T12:30:00Z'),
    });
    await expect(store.snapshot(CONVOY)).resolves.toHaveLength(1);

    nowMs = Date.parse('2026-06-06T13:00:00Z'); // past expiry
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });

  it('ignores transient frames and isolates convoys', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, {
      type: 'gps',
      payload: {
        memberId: 'm1',
        latitude: 48,
        longitude: 11,
        heading: 0,
        speed: 0,
        timestamp: '2026-06-06T12:00:00Z',
      },
    });
    await store.record(CONVOY, {
      type: 'status',
      payload: { memberId: 'm1', kind: 'pause', at: '2026-06-06T12:00:00Z' },
    });
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
    await expect(store.snapshot('other-convoy')).resolves.toEqual([]);
  });

  it('clear() drops the snapshot', async () => {
    const store = createInMemorySnapshotStore();
    await store.record(CONVOY, { type: 'hazard', payload: hazard('h1') });
    await store.clear(CONVOY);
    await expect(store.snapshot(CONVOY)).resolves.toEqual([]);
  });
});
