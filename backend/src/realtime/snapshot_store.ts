import {
  encodeFrame,
  type HazardPayload,
  type InboundFrame,
  type OutboundFrame,
  type TourPayload,
  type WaypointPayload,
} from './wire.js';

/**
 * Keeps the latest convoy "world state" — active hazards, the route/tour, and
 * the current waypoint — so a member who joins or reconnects mid-drive is
 * replayed it immediately, instead of only seeing hazards/route changes that
 * happen AFTER they connect. Complements [PositionStore] (which does the same
 * for GPS).
 *
 * In-memory + per-process: correct for the current single-instance deployment
 * (InProcessFanout). A multi-instance deployment (RedisFanout) would need this
 * state in Redis so every node replays the same snapshot — tracked as a
 * follow-up; until then run a single gateway instance.
 */
export interface SnapshotStore {
  /** Folds a broadcast frame into the convoy's snapshot (no-op for transient
   * frame types like gps/checkin/status). */
  record(convoyId: string, frame: InboundFrame): void;

  /** Frames to replay to a newly-connected socket (active hazards + tour +
   * waypoint), with expired hazards pruned. */
  snapshot(convoyId: string): OutboundFrame[];

  /** Drops a convoy's snapshot (e.g. when it is disbanded). */
  clear(convoyId: string): void;
}

interface ConvoySnapshot {
  hazards: Map<string, HazardPayload>;
  tour: TourPayload | null;
  waypoint: WaypointPayload | null;
}

export function createInMemorySnapshotStore(
  now: () => number = () => Date.now(),
): SnapshotStore {
  const convoys = new Map<string, ConvoySnapshot>();

  function stateFor(convoyId: string): ConvoySnapshot {
    let state = convoys.get(convoyId);
    if (state === undefined) {
      state = { hazards: new Map(), tour: null, waypoint: null };
      convoys.set(convoyId, state);
    }
    return state;
  }

  return {
    record(convoyId, frame) {
      const state = stateFor(convoyId);
      switch (frame.type) {
        case 'hazard':
          state.hazards.set(frame.payload.id, frame.payload);
          break;
        case 'hazard_remove':
          state.hazards.delete(frame.payload.id);
          break;
        case 'tour':
          // Empty stop list = cleared route.
          state.tour = frame.payload.stops.length > 0 ? frame.payload : null;
          break;
        case 'waypoint':
          // null = leader cleared the active waypoint.
          state.waypoint = frame.payload;
          break;
        default:
          // gps / checkin / status are transient — never snapshotted.
          break;
      }
    },

    snapshot(convoyId) {
      const state = convoys.get(convoyId);
      if (state === undefined) return [];
      const ts = now();
      const frames: OutboundFrame[] = [];
      for (const [id, hazard] of state.hazards) {
        if (hazard.expiresAt !== undefined && Date.parse(hazard.expiresAt) <= ts) {
          state.hazards.delete(id);
          continue;
        }
        frames.push({ type: 'hazard', payload: hazard });
      }
      if (state.tour !== null) {
        frames.push({ type: 'tour', payload: state.tour });
      }
      if (state.waypoint !== null) {
        frames.push({ type: 'waypoint', payload: state.waypoint });
      }
      return frames;
    },

    clear(convoyId) {
      convoys.delete(convoyId);
    },
  };
}

/** Encodes a snapshot to ready-to-send wire strings. */
export function encodeSnapshot(frames: OutboundFrame[]): string[] {
  return frames.map(encodeFrame);
}
