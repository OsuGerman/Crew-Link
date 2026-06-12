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

function hazardFrame(id: string, reporterId: string): InboundFrame {
  return {
    type: 'hazard',
    payload: {
      id,
      type: 'accident',
      latitude: 52.5,
      longitude: 13.4,
      reporterId,
      createdAt: new Date().toISOString(),
    },
  };
}

describe('convoy gateway snapshot (late joiner + reporter-only removal)', () => {
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

  function url(token: string, convoyId: string): string {
    return wsUrl(port, token, convoyId);
  }

  it('replays an existing hazard to a late joiner on connect', async () => {
    const lateConvoy = 'convoy-late';
    const wsA = await openSocket(url(MEMBER_A, lateConvoy));

    // A reports a hazard before B joins.
    wsA.send(JSON.stringify(hazardFrame('hz1', MEMBER_A)));
    await new Promise((r) => setTimeout(r, 50)); // let the gateway record it

    // B joins late → the gateway replays the recorded hazard on connect.
    const wsB = await openSocket(url(MEMBER_B, lateConvoy));
    const received = JSON.parse(await nextMessage(wsB)) as InboundFrame;
    expect(received.type).toBe('hazard');
    expect(received.payload).toMatchObject({ id: 'hz1', reporterId: MEMBER_A });

    wsA.close();
    wsB.close();
  });

  it('drops a hazard_remove from a member who is not the reporter', async () => {
    const convoy = 'convoy-hazremove';
    const wsA = await openSocket(url(MEMBER_A, convoy));
    const wsB = await openSocket(url(MEMBER_B, convoy));

    // A reports a hazard; B receives the broadcast.
    const inboundB = nextMessage(wsB);
    wsA.send(JSON.stringify(hazardFrame('hzX', MEMBER_A)));
    await inboundB;

    // B (not the reporter) tries to remove A's hazard → must be dropped, so A
    // never sees the removal.
    let removalSeen = false;
    wsA.addEventListener('message', (event) => {
      if ((JSON.parse(String(event.data)) as InboundFrame).type ===
          'hazard_remove') {
        removalSeen = true;
      }
    });
    wsB.send(
      JSON.stringify({
        type: 'hazard_remove',
        payload: { id: 'hzX' },
      } satisfies InboundFrame),
    );
    await new Promise((r) => setTimeout(r, 100));
    expect(removalSeen).toBe(false);

    wsA.close();
    wsB.close();
  });
});
