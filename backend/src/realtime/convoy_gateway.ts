import type { FastifyPluginAsync, FastifyRequest } from 'fastify';

import { InProcessFanout, type FanoutAdapter } from './fanout.js';
import { encodeFrame, inboundFrameSchema } from './wire.js';

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

        socket.on('message', (raw: Buffer | ArrayBuffer | Buffer[]) => {
          handleFrame(raw, memberId, convoyId, fanout, app.log);
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

  // Anti-impersonation: payload.memberId must match the authenticated
  // member of the originating connection. Drop the frame otherwise.
  if (result.data.payload.memberId !== originMemberId) {
    log.warn(
      { convoyId, claimed: result.data.payload.memberId, actual: originMemberId },
      'memberId mismatch — frame dropped',
    );
    return;
  }

  const encoded = encodeFrame(result.data);
  void fanout.publish(convoyId, encoded, originMemberId);
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
