import { AccessToken } from 'livekit-server-sdk';

const DEFAULT_TTL_S = 3_600;

export interface PttTokenOptions {
  apiKey: string;
  apiSecret: string;
  roomName: string;
  participantIdentity: string;
  participantName?: string;
  ttlSeconds?: number;
}

export async function createPttToken(opts: PttTokenOptions): Promise<string> {
  const token = new AccessToken(opts.apiKey, opts.apiSecret, {
    identity: opts.participantIdentity,
    name: opts.participantName,
    ttl: opts.ttlSeconds ?? DEFAULT_TTL_S,
  });
  token.addGrant({
    roomJoin: true,
    room: opts.roomName,
    canPublish: true,
    canSubscribe: true,
  });
  return token.toJwt();
}

export function convoyRoomName(convoyId: string): string {
  return `convoy-${convoyId}`;
}
