import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { InProcessFanout } from '../../src/realtime/fanout.js';

describe('InProcessFanout', () => {
  let fanout: InProcessFanout;

  beforeEach(() => {
    fanout = new InProcessFanout();
  });

  afterEach(async () => {
    await fanout.close();
  });

  it('delivers frame to other connection in the same convoy', async () => {
    const received: string[] = [];
    fanout.addLocalConnection('c1', { memberId: 'a', send: () => {} });
    fanout.addLocalConnection('c1', { memberId: 'b', send: (d) => received.push(d) });

    await fanout.publish('c1', 'hello', 'a');

    expect(received).toEqual(['hello']);
  });

  it('does not echo frame back to origin', async () => {
    const received: string[] = [];
    fanout.addLocalConnection('c1', { memberId: 'a', send: (d) => received.push(d) });

    await fanout.publish('c1', 'hello', 'a');

    expect(received).toHaveLength(0);
  });

  it('broadcasts to multiple receivers', async () => {
    const receivedB: string[] = [];
    const receivedC: string[] = [];
    fanout.addLocalConnection('c1', { memberId: 'a', send: () => {} });
    fanout.addLocalConnection('c1', { memberId: 'b', send: (d) => receivedB.push(d) });
    fanout.addLocalConnection('c1', { memberId: 'c', send: (d) => receivedC.push(d) });

    await fanout.publish('c1', 'hello', 'a');

    expect(receivedB).toEqual(['hello']);
    expect(receivedC).toEqual(['hello']);
  });

  it('does not cross-broadcast between convoy ids', async () => {
    const received: string[] = [];
    fanout.addLocalConnection('convoy-x', { memberId: 'a', send: () => {} });
    fanout.addLocalConnection('convoy-y', { memberId: 'b', send: (d) => received.push(d) });

    await fanout.publish('convoy-x', 'hello', 'a');

    expect(received).toHaveLength(0);
  });

  it('removes connection on unregister', async () => {
    const received: string[] = [];
    const unregister = fanout.addLocalConnection('c1', {
      memberId: 'b',
      send: (d) => received.push(d),
    });
    fanout.addLocalConnection('c1', { memberId: 'a', send: () => {} });

    unregister();
    await fanout.publish('c1', 'hello', 'a');

    expect(received).toHaveLength(0);
  });

  it('publishes nothing when no connections exist for convoy', async () => {
    await expect(fanout.publish('empty-convoy', 'hello', 'a')).resolves.toBeUndefined();
  });
});

describe.skipIf(process.env['REDIS_URL'] === undefined)('RedisFanout (integration)', () => {
  it('routes frame from instance A to instance B via Redis', async () => {
    const { RedisFanout } = await import('../../src/realtime/redis_fanout.js');
    const redisUrl = process.env['REDIS_URL']!;

    const instanceA = new RedisFanout(redisUrl);
    const instanceB = new RedisFanout(redisUrl);
    await instanceA.connect();
    await instanceB.connect();

    const received: string[] = [];
    instanceB.addLocalConnection('c1', { memberId: 'b', send: (d) => received.push(d) });

    // Give subscriber time to register
    await new Promise((r) => setTimeout(r, 50));

    instanceA.addLocalConnection('c1', { memberId: 'a', send: () => {} });
    await instanceA.publish('c1', 'hello', 'a');

    await new Promise((r) => setTimeout(r, 100));

    expect(received).toEqual(['hello']);

    await instanceA.close();
    await instanceB.close();
  });

  it('does not deliver frame to origin even via Redis round-trip', async () => {
    const { RedisFanout } = await import('../../src/realtime/redis_fanout.js');
    const redisUrl = process.env['REDIS_URL']!;

    const instance = new RedisFanout(redisUrl);
    await instance.connect();

    const received: string[] = [];
    instance.addLocalConnection('c1', { memberId: 'a', send: (d) => received.push(d) });

    await new Promise((r) => setTimeout(r, 50));
    await instance.publish('c1', 'hello', 'a');
    await new Promise((r) => setTimeout(r, 100));

    expect(received).toHaveLength(0);

    await instance.close();
  });
});
