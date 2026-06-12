import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  HEARTBEAT_INTERVAL_MS,
  startHeartbeat,
} from '../../src/realtime/heartbeat.js';

function makeFakeSocket() {
  const pongListeners: (() => void)[] = [];
  return {
    ping: vi.fn(),
    terminate: vi.fn(),
    on: (_event: 'pong', listener: () => void) => {
      pongListeners.push(listener);
    },
    emitPong() {
      for (const listener of pongListeners) listener();
    },
  };
}

describe('ws heartbeat', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('keeps pinging while pongs arrive and never terminates', () => {
    const socket = makeFakeSocket();
    startHeartbeat(socket);

    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS);
    expect(socket.ping).toHaveBeenCalledTimes(1);
    socket.emitPong();

    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS);
    expect(socket.ping).toHaveBeenCalledTimes(2);
    socket.emitPong();

    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS);
    expect(socket.ping).toHaveBeenCalledTimes(3);
    expect(socket.terminate).not.toHaveBeenCalled();
  });

  it('terminates a half-dead connection when a ping goes unanswered', () => {
    const socket = makeFakeSocket();
    startHeartbeat(socket);

    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // ping sent, no pong
    expect(socket.terminate).not.toHaveBeenCalled();

    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS); // missing pong detected
    expect(socket.terminate).toHaveBeenCalledTimes(1);
    // No further ping once the socket is terminated.
    expect(socket.ping).toHaveBeenCalledTimes(1);
  });

  it('stop() clears the interval (wired into the close handler)', () => {
    const socket = makeFakeSocket();
    const stop = startHeartbeat(socket);

    stop();
    vi.advanceTimersByTime(HEARTBEAT_INTERVAL_MS * 3);
    expect(socket.ping).not.toHaveBeenCalled();
    expect(socket.terminate).not.toHaveBeenCalled();
  });
});
