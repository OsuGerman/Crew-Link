import type { FastifyPluginAsync, FastifyRequest } from 'fastify';

import { InProcessFanout, type FanoutAdapter } from './fanout.js';
import type { PositionStore } from './position_store.js';
import type { SnapshotStore } from './snapshot_store.js';
import { encodeFrame, inboundFrameSchema, originatorOf } from './wire.js';

declare module 'fastify' {
  interface FastifyRequest {
    // Set in preValidation, consumed in the upgrade handler. Module
    // augmentation gives TS types; runtime assignment is plain JS.
    resolvedMemberId?: string;
  }
}

interface ConnectParams {
  convoyId: string;
}

interface ConnectQuery {
  token?: string;
}

export interface ConvoyGatewayOptions {
  // Resolve the member ID from the connect query. In dev the token IS
  // the member ID; production will replace this with JWT verification +
  // a `convoy_members` membership lookup.
  resolveMember?: (token: string, convoyId: string) => Promise<string | null>;
  // Fan-out adapter for broadcasting frames. Defaults to InProcessFanout
  // (single-instance). Pass RedisFanout for multi-instance deployments.
  fanout?: FanoutAdapter;
  // Persists GPS positions and replays a snapshot to newly-connected sockets so
  // late joiners aren't staring at an empty radar. Omitted → no persistence.
  positionStore?: PositionStore;
  // Replays the convoy "world state" (hazards, route, waypoint) to newly-
  // connected sockets so late joiners see them immediately. Omitted → no replay.
  snapshotStore?: SnapshotStore;
}

const defaultResolveMember = async (
  token: string,
  _convoyId: string,
): Promise<string | null> => (token.length > 0 ? token : null);

const HTTP_UNAUTHORIZED = 401;

export function createConvoyGateway(
  options: ConvoyGatewayOptions = {},
): FastifyPluginAsync {
  const resolveMember = options.resolveMember ?? defaultResolveMember;
  const ownFanout = options.fanout === undefined;
  const fanout: FanoutAdapter = options.fanout ?? new InProcessFanout();
  const positionStore = options.positionStore;
  const snapshotStore = options.snapshotStore;

  return async (app) => {
    // Only close the fanout if we created it; externally-owned fanouts
    // (e.g. RedisFanout from the server) are closed by their owner.
    if (ownFanout) {
      app.addHook('onClose', async () => {
        await fanout.close();
      });
    }

    app.get<{ Params: ConnectParams; Querystring: ConnectQuery }>(
      '/convoys/:convoyId/stream',
      {
        websocket: true,
        preValidation: async (req, reply) => {
          const token = req.query.token ?? '';
          const memberId = await resolveMember(token, req.params.convoyId);
          if (memberId === null) {
            return reply.code(HTTP_UNAUTHORIZED).send({ error: 'unauthorized' });
          }
          req.resolvedMemberId = memberId;
        },
      },
      (socket, req: FastifyRequest<{ Params: ConnectParams }>) => {
        const memberId = req.resolvedMemberId;
        if (memberId === undefined) {
          // Defensive: should never happen given preValidation gates this.
          socket.close();
          return;
        }
        const { convoyId } = req.params;

        const unregister = fanout.addLocalConnection(convoyId, {
          memberId,
          send: (data) => {
            if (socket.readyState === socket.OPEN) {
              socket.send(data);
            }
          },
        });

        // Replay every other member's last-known position to the new socket so
        // its radar is populated immediately, not on the next 1 Hz tick.
        if (positionStore !== undefined) {
          void positionStore
            .loadSnapshot(convoyId, memberId)
            .then((positions) => {
              if (socket.readyState !== socket.OPEN) return;
              for (const payload of positions) {
                socket.send(encodeFrame({ type: 'gps', payload }));
              }
            })
            .catch((err: unknown) => {
              app.log.warn({ err, convoyId }, 'position snapshot failed');
            });
        }

        // Replay the current hazards / route / waypoint (synchronous, in-memory)
        // so a late joiner sees them without waiting for the next change.
        if (snapshotStore !== undefined) {
          for (const frame of snapshotStore.snapshot(convoyId)) {
            if (socket.readyState === socket.OPEN) {
              socket.send(encodeFrame(frame));
            }
          }
        }

        socket.on('message', (raw: Buffer | ArrayBuffer | Buffer[]) => {
          handleFrame(
            raw,
            memberId,
            convoyId,
            fanout,
            positionStore,
            snapshotStore,
            app.log,
          );
        });

        socket.on('close', () => {
          unregister();
        });
      },
    );
  };
}

function handleFrame(
  raw: Buffer | ArrayBuffer | Buffer[],
  originMemberId: string,
  convoyId: string,
  fanout: FanoutAdapter,
  positionStore: PositionStore | undefined,
  snapshotStore: SnapshotStore | undefined,
  log: { warn: (obj: unknown, msg?: string) => void },
): void {
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
