/** Ping cadence — comfortably below common NAT/load-balancer idle timeouts
 * so connections stay warm and a half-dead one is detected within two
 * intervals (~50 s). */
export const HEARTBEAT_INTERVAL_MS = 25_000;

/** Minimal slice of the `ws` socket the heartbeat needs (keeps it testable
 * with a plain fake — @fastify/websocket hands us the raw `ws` socket). */
export interface HeartbeatSocket {
  ping: () => void;
  terminate: () => void;
  on: (event: 'pong', listener: () => void) => void;
}

/**
 * Server-side WS keepalive: sends a protocol-level ping every [intervalMs].
 * If the previous ping was never answered, the TCP connection is half-dead
 * (LTE handover, NAT timeout, killed app) and terminate() tears it down so
 * the fanout registration is freed via the socket's close event. Clients
 * answer pings automatically at the protocol level (RFC 6455) — no app-side
 * support needed. Returns a stop() callback for the close handler.
 */
export function startHeartbeat(
  socket: HeartbeatSocket,
  intervalMs: number = HEARTBEAT_INTERVAL_MS,
): () => void {
  let alive = true;
  socket.on('pong', () => {
    alive = true;
  });
  const timer = setInterval(() => {
    if (!alive) {
      socket.terminate();
      return;
    }
    alive = false;
    socket.ping();
  }, intervalMs);
  return () => {
    clearInterval(timer);
  };
}
