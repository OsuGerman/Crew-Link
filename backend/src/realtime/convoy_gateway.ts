import type { FastifyPluginAsync, FastifyRequest } from 'fastify';

import { InProcessFanout, type FanoutAdapter } from './fanout.js';
import { handleFrame } from './frame_handler.js';
import type { PositionStore } from './position_store.js';
import type { SnapshotStore } from './snapshot_store.js';
import { encodeFrame } from './wire.js';

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
  // True iff the member is the convoy owner — gates leader-only frames (tour).
  resolveLeader?: (memberId: string, convoyId: string) => Promise<boolean>;
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
  const resolveLeader = options.resolveLeader;

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
          void handleFrame(raw, {
            originMemberId: memberId,
            convoyId,
            fanout,
            positionStore,
            snapshotStore,
            resolveLeader,
            log: app.log,
          });
        });

        socket.on('close', () => {
          unregister();
        });
      },
    );
  };
}
