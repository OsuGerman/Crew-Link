import type { FanoutAdapter } from './fanout.js';
import type { PositionStore } from './position_store.js';
import type { SnapshotStore } from './snapshot_store.js';
import { encodeFrame, inboundFrameSchema, originatorOf } from './wire.js';

/** Pino-compatible logger slice the frame pipeline needs. */
export interface GatewayLogger {
  warn: (obj: unknown, msg?: string) => void;
  error: (obj: unknown, msg?: string) => void;
}

/** Per-connection context the gateway hands to [handleFrame]. */
export interface FrameContext {
  originMemberId: string;
  convoyId: string;
  fanout: FanoutAdapter;
  positionStore?: PositionStore;
  snapshotStore?: SnapshotStore;
  resolveLeader?: (memberId: string, convoyId: string) => Promise<boolean>;
  log: GatewayLogger;
}

/** Validates, authorizes and fans out a single inbound WS frame. */
export async function handleFrame(
  raw: Buffer | ArrayBuffer | Buffer[],
  ctx: FrameContext,
): Promise<void> {
  const { originMemberId, convoyId, fanout, positionStore, snapshotStore, log } =
    ctx;
  const text = bufferToString(raw);
  if (text === null) {
    return;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    log.warn({ convoyId }, 'malformed JSON frame');
    return;
  }

  const result = inboundFrameSchema.safeParse(parsed);
  if (!result.success) {
    log.warn({ convoyId, issues: result.error.issues }, 'frame failed schema');
    return;
  }

  // Anti-impersonation: the originator field in the payload (memberId on
  // gps, setBy on waypoint) must match the authenticated member of the
  // originating connection. Waypoint-clear (payload === null) has no
  // originator and is accepted as-is from the authenticated sender.
  // TODO: leader-only enforcement for waypoint frames — requires a
  // `convoy_members` lookup of the originating member's isLeader flag.
  const claimedOriginator = originatorOf(result.data);
  if (claimedOriginator !== null && claimedOriginator !== originMemberId) {
    log.warn(
      { convoyId, claimed: claimedOriginator, actual: originMemberId },
      'originator mismatch — frame dropped',
    );
    return;
  }

  // hazard_remove carries no originator field, so enforce reporter-only removal
  // against the tracked snapshot. Unknown hazards (expired / never seen) pass
  // through — there is nothing left to protect.
  if (result.data.type === 'hazard_remove' && snapshotStore !== undefined) {
    const reporter = snapshotStore.hazardReporter(
      convoyId,
      result.data.payload.id,
    );
    if (reporter !== undefined && reporter !== originMemberId) {
      log.warn(
        { convoyId, hazardId: result.data.payload.id, actual: originMemberId },
        'hazard_remove by non-reporter — frame dropped',
      );
      return;
    }
  }

  // Leader-only: the route/tour may only be set by the convoy owner.
  if (result.data.type === 'tour' && ctx.resolveLeader !== undefined) {
    const isLeader = await ctx.resolveLeader(originMemberId, convoyId);
    if (!isLeader) {
      log.warn(
        { convoyId, memberId: originMemberId },
        'tour from non-leader — frame dropped',
      );
      return;
    }
  }

  const encoded = encodeFrame(result.data);
  void fanout.publish(convoyId, encoded, originMemberId);

  // Persist GPS so a late joiner / reconnect receives a snapshot on connect.
  if (positionStore !== undefined && result.data.type === 'gps') {
    void positionStore
      .save(convoyId, originMemberId, result.data.payload)
      .catch((err: unknown) => {
        log.warn({ err, convoyId }, 'position persist failed');
      });
  }

  // Fold hazards / route / waypoint into the convoy snapshot for late joiners.
  snapshotStore?.record(convoyId, result.data);
}

function bufferToString(
  raw: Buffer | ArrayBuffer | Buffer[],
): string | null {
  if (typeof raw === 'string') {
    return raw;
  }
  if (Buffer.isBuffer(raw)) {
    return raw.toString('utf8');
  }
  if (Array.isArray(raw)) {
    return Buffer.concat(raw).toString('utf8');
  }
  if (raw instanceof ArrayBuffer) {
    return Buffer.from(raw).toString('utf8');
  }
  return null;
}
