import type { AddressInfo } from 'node:net';

import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { loadEnv } from '../../src/config/env.js';
import { buildApp } from '../../src/server.js';
import type { InboundFrame } from '../../src/realtime/wire.js';
import {
  MEMBER_A,
  MEMBER_B,
  nextMessage,
  openSocket,
  wsUrl,
} from './ws_test_utils.js';

function tourFrame(setBy: string): InboundFrame {
  return {
    type: 'tour',
    payload: {
      stops: [
        {
          latitude: 48,
          longitude: 11,
          label: 'Stop',
          setBy,
          setAt: new Date().toISOString(),
        },
      ],
    },
  };
}

function waypointFrame(setBy: string): InboundFrame {
  return {
    type: 'waypoint',
    payload: {
      latitude: 48,
      longitude: 11,
      label: 'Treffpunkt',
      setBy,
      setAt: new Date().toISOString(),
    },
  };
}

describe('convoy gateway leader gate (tour + waypoint)', () => {
  let app: FastifyInstance;
  let port: number;

  beforeAll(async () => {
    const env = loadEnv({ NODE_ENV: 'test', LOG_LEVEL: 'fatal' });
    app = await buildApp({
      env,
      gateway: {
        // MEMBER_A is the convoy owner/leader for the leader-only frame tests.
        resolveLeader: async (memberId) => memberId === MEMBER_A,
      },
    });
    await app.listen({ host: '127.0.0.1', port: 0 });
    port = (app.server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    await app.close();
  });

  function url(token: string, convoyId: string): string {
    return wsUrl(port, token, convoyId);
  }

  it('broadcasts a tour frame from the convoy leader', async () => {
    const convoy = 'convoy-tour-ok';
    const wsLeader = await openSocket(url(MEMBER_A, convoy)); // leader
    const wsB = await openSocket(url(MEMBER_B, convoy));

    const inbound = nextMessage(wsB);
    wsLeader.send(JSON.stringify(tourFrame(MEMBER_A)));

    const received = JSON.parse(await inbound) as InboundFrame;
    expect(received.type).toBe('tour');

    wsLeader.close();
    wsB.close();
  });

  it('drops a tour frame from a non-leader', async () => {
    const convoy = 'convoy-tour-deny';
    const wsLeader = await openSocket(url(MEMBER_A, convoy));
    const wsB = await openSocket(url(MEMBER_B, convoy));

    let seen = false;
    wsLeader.addEventListener('message', () => {
      seen = true;
    });
    wsB.send(JSON.stringify(tourFrame(MEMBER_B)));

    await new Promise((r) => setTimeout(r, 100));
    expect(seen).toBe(false);

    wsLeader.close();
    wsB.close();
  });

  it('broadcasts a waypoint frame from the convoy leader', async () => {
    const convoy = 'convoy-wp-ok';
    const wsLeader = await openSocket(url(MEMBER_A, convoy)); // leader
    const wsB = await openSocket(url(MEMBER_B, convoy));

    const inbound = nextMessage(wsB);
    wsLeader.send(JSON.stringify(waypointFrame(MEMBER_A)));

    const received = JSON.parse(await inbound) as InboundFrame;
    expect(received.type).toBe('waypoint');

    wsLeader.close();
    wsB.close();
  });

  it('drops a waypoint frame from a non-leader', async () => {
    const convoy = 'convoy-wp-deny';
    const wsLeader = await openSocket(url(MEMBER_A, convoy));
    const wsB = await openSocket(url(MEMBER_B, convoy));

    let seen = false;
    wsLeader.addEventListener('message', () => {
      seen = true;
    });
    // member-b is not the leader — its waypoint must never reach member-a.
    wsB.send(JSON.stringify(waypointFrame(MEMBER_B)));

    await new Promise((r) => setTimeout(r, 100));
    expect(seen).toBe(false);

    wsLeader.close();
    wsB.close();
  });
});
