import type { AddressInfo } from 'node:net';

import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { loadEnv } from '../../src/config/env.js';
import { buildApp } from '../../src/server.js';
import type { InboundFrame } from '../../src/realtime/wire.js';
import {
  MEMBER_A,
  MEMBER_B,
  makeGps,
  nextMessage,
  openSocket,
  wsUrl,
} from './ws_test_utils.js';

const CONVOY_ID = 'test-convoy';

describe('convoy gateway', () => {
  let app: FastifyInstance;
  let port: number;

  beforeAll(async () => {
    const env = loadEnv({ NODE_ENV: 'test', LOG_LEVEL: 'fatal' });
    app = await buildApp({ env });
    await app.listen({ host: '127.0.0.1', port: 0 });
    port = (app.server.address() as AddressInfo).port;
  });

  afterAll(async () => {
    await app.close();
  });

  function url(token: string, convoyId = CONVOY_ID): string {
    return wsUrl(port, token, convoyId);
  }

  it('relays gps frames from one member to every other member in the convoy', async () => {
    const wsA = await openSocket(url(MEMBER_A));
    const wsB = await openSocket(url(MEMBER_B));

    const inbound = nextMessage(wsB);
    const frame: InboundFrame = {
      type: 'gps',
      payload: makeGps(MEMBER_A, 13.405, 52.52),
    };
    wsA.send(JSON.stringify(frame));

    const received = JSON.parse(await inbound) as InboundFrame;
    expect(received.type).toBe('gps');
    expect(received.payload.memberId).toBe(MEMBER_A);
    expect(received.payload.latitude).toBeCloseTo(52.52);

    wsA.close();
    wsB.close();
  });

  it('does not echo a frame back to its sender', async () => {
    const wsA = await openSocket(url(MEMBER_A));
    const wsB = await openSocket(url(MEMBER_B));

    let echoed = false;
    wsA.addEventListener('message', () => {
      echoed = true;
    });

    const inbound = nextMessage(wsB);
    wsA.send(
      JSON.stringify({
        type: 'gps',
        payload: makeGps(MEMBER_A, 13.405, 52.52),
      } satisfies InboundFrame),
    );
    await inbound;

    // Give A a moment in case it would receive an unwanted echo
    await new Promise((r) => setTimeout(r, 50));
    expect(echoed).toBe(false);

    wsA.close();
    wsB.close();
  });

  it('drops a frame whose payload.memberId does not match the connection token', async () => {
    const wsA = await openSocket(url(MEMBER_A));
    const wsB = await openSocket(url(MEMBER_B));

    let receivedAny = false;
    wsB.addEventListener('message', () => {
      receivedAny = true;
    });

    // member-a connects but claims to be member-b in the payload
    wsA.send(
      JSON.stringify({
        type: 'gps',
        payload: makeGps(MEMBER_B, 13.405, 52.52),
      } satisfies InboundFrame),
    );

    await new Promise((r) => setTimeout(r, 100));
    expect(receivedAny).toBe(false);

    wsA.close();
    wsB.close();
  });

  it('rejects connections with an empty token', async () => {
    await expect(openSocket(url(''))).rejects.toBeDefined();
  });

  it('does not cross-broadcast between different convoy ids', async () => {
    const wsA = await openSocket(url(MEMBER_A, 'convoy-x'));
    const wsB = await openSocket(url(MEMBER_B, 'convoy-y'));

    let crossed = false;
    wsB.addEventListener('message', () => {
      crossed = true;
    });

    wsA.send(
      JSON.stringify({
        type: 'gps',
        payload: makeGps(MEMBER_A, 13.405, 52.52),
      } satisfies InboundFrame),
    );

    await new Promise((r) => setTimeout(r, 100));
    expect(crossed).toBe(false);

    wsA.close();
    wsB.close();
  });

});
