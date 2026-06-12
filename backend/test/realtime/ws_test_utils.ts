import type { GpsPayload } from '../../src/realtime/wire.js';

// Shared helpers for the convoy-gateway WebSocket test suites.

export const MEMBER_A = 'member-a';
export const MEMBER_B = 'member-b';

const DEFAULT_MESSAGE_TIMEOUT_MS = 1000;

export function makeGps(memberId: string, lng: number, lat: number): GpsPayload {
  return {
    memberId,
    latitude: lat,
    longitude: lng,
    heading: 0,
    speed: 0,
    timestamp: new Date().toISOString(),
  };
}

export function wsUrl(port: number, token: string, convoyId: string): string {
  return `ws://127.0.0.1:${port}/convoys/${convoyId}/stream?token=${token}`;
}

export function openSocket(url: string): Promise<WebSocket> {
  return new Promise((resolveOpen, rejectOpen) => {
    const ws = new WebSocket(url);
    ws.addEventListener('open', () => resolveOpen(ws), { once: true });
    ws.addEventListener('error', (event) => rejectOpen(event), { once: true });
  });
}

export function nextMessage(
  ws: WebSocket,
  timeoutMs = DEFAULT_MESSAGE_TIMEOUT_MS,
): Promise<string> {
  return new Promise((resolveMsg, rejectMsg) => {
    const timer = setTimeout(
      () => rejectMsg(new Error('timed out waiting for ws message')),
      timeoutMs,
    );
    ws.addEventListener(
      'message',
      (event) => {
        clearTimeout(timer);
        resolveMsg(String(event.data));
      },
      { once: true },
    );
  });
}
