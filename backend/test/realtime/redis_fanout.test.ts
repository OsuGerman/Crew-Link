import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// ── ioredis mock ────────────────────────────────────────────────────────────
// We stub Redis so no real broker is needed in CI.
type EventCallback = (...args: unknown[]) => void;

function makeRedisMock() {
  const listeners = new Map<string, EventCallback[]>();
  const subscribed = new Set<string>();

  const mock = {
    connect: vi.fn().mockResolvedValue(undefined),
    quit: vi.fn().mockResolvedValue(undefined),
    publish: vi.fn().mockResolvedValue(1),
    subscribe: vi.fn().mockImplementation((channel: string) => {
      subscribed.add(channel);
      return Promise.resolve();
    }),
    unsubscribe: vi.fn().mockImplementation((channel: string) => {
      subscribed.delete(channel);
      return Promise.resolve();
    }),
    on: vi.fn().mockImplementation((event: string, cb: EventCallback) => {
      if (!listeners.has(event)) listeners.set(event, []);
      listeners.get(event)!.push(cb);
      return mock;
    }),
    // test helpers
    _emit(event: string, ...args: unknown[]) {
      for (const cb of listeners.get(event) ?? []) cb(...args);
    },
    _subscribed: subscribed,
  };
  return mock;
}

type RedisMock = ReturnType<typeof makeRedisMock>;

let pubMock: RedisMock;
let subMock: RedisMock;
let callCount = 0;

vi.mock('ioredis', () => ({
  Redis: vi.fn().mockImplementation(() => {
    callCount += 1;
    // First construction = pub, second = sub
    return callCount % 2 === 1 ? pubMock : subMock;
  }),
}));

// Import AFTER mock is set up
const { RedisFanout } = await import('../../src/realtime/redis_fanout.js');

// ── helpers ─────────────────────────────────────────────────────────────────
function makeSender(memberId: string) {
  const frames: string[] = [];
  return { memberId, send: (f: string) => frames.push(f), frames };
}

// ── tests ────────────────────────────────────────────────────────────────────
describe('RedisFanout', () => {
  let fanout: InstanceType<typeof RedisFanout>;

  beforeEach(() => {
    callCount = 0;
    pubMock = makeRedisMock();
    subMock = makeRedisMock();
    fanout = new RedisFanout('redis://localhost:6379');
  });

  afterEach(async () => {
    await fanout.close();
    vi.clearAllMocks();
  });

  it('registers error listeners on both connections before connect()', () => {
    // error-Listener must be attached in constructor (before connect) so that
    // transient connection failures during connect() do not crash the process.
    const pubErrorListeners = pubMock.on.mock.calls.filter(([ev]) => ev === 'error');
    const subErrorListeners = subMock.on.mock.calls.filter(([ev]) => ev === 'error');
    expect(pubErrorListeners).toHaveLength(1);
    expect(subErrorListeners).toHaveLength(1);
  });

  it('error listener does not throw — swallows redis connection errors', () => {
    // Simulate a network blip; must not propagate / unhandled-rejection.
    expect(() => {
      subMock._emit('error', new Error('ECONNREFUSED'));
      pubMock._emit('error', new Error('ECONNREFUSED'));
    }).not.toThrow();
  });

  it('connect() calls connect on both pub and sub', async () => {
    await fanout.connect();
    expect(pubMock.connect).toHaveBeenCalledOnce();
    expect(subMock.connect).toHaveBeenCalledOnce();
  });

  it('publish delivers frame to local connections, skipping origin', async () => {
    await fanout.connect();
    const a = makeSender('alice');
    const b = makeSender('bob');
    fanout.addLocalConnection('convoy-1', a);
    fanout.addLocalConnection('convoy-1', b);

    await fanout.publish('convoy-1', 'frame-data', 'alice');

    expect(a.frames).toHaveLength(0); // origin must NOT receive own frame
    expect(b.frames).toEqual(['frame-data']);
  });

  it('publish broadcasts to Redis for remote instances', async () => {
    await fanout.connect();
    await fanout.publish('convoy-1', 'frame-data', 'alice');

    expect(pubMock.publish).toHaveBeenCalledOnce();
    const [channel, payload] = pubMock.publish.mock.calls[0] as [string, string];
    expect(channel).toBe('crewlink:convoy:convoy-1');
    const msg = JSON.parse(payload) as { frame: string; originMemberId: string; instanceId: string };
    expect(msg.frame).toBe('frame-data');
    expect(msg.originMemberId).toBe('alice');
    expect(typeof msg.instanceId).toBe('string');
  });

  it('message from remote instance is delivered, skipping origin member', async () => {
    await fanout.connect();
    const a = makeSender('alice');
    const b = makeSender('bob');
    fanout.addLocalConnection('convoy-1', a);
    fanout.addLocalConnection('convoy-1', b);

    // Simulate a message arriving from a DIFFERENT instance (different instanceId).
    const remoteMsg = JSON.stringify({
      frame: 'remote-frame',
      originMemberId: 'alice',
      instanceId: 'other-instance-uuid',
    });
    subMock._emit('message', 'crewlink:convoy:convoy-1', remoteMsg);

    expect(a.frames).toHaveLength(0); // originMemberId must be skipped
    expect(b.frames).toEqual(['remote-frame']);
  });

  it('message from own instance is ignored (no double delivery)', async () => {
    await fanout.connect();
    const b = makeSender('bob');
    fanout.addLocalConnection('convoy-1', b);

    // Peek at the instanceId assigned to this fanout instance.
    // We get it by capturing the publish payload.
    await fanout.publish('convoy-1', 'x', 'alice');
    const payload = pubMock.publish.mock.calls[0]![1] as string;
    const { instanceId } = JSON.parse(payload) as { instanceId: string };

    // Now simulate sub receiving that same message (as Redis would echo it).
    subMock._emit('message', 'crewlink:convoy:convoy-1', JSON.stringify({
      frame: 'x',
      originMemberId: 'alice',
      instanceId,
    }));

    // b already got the frame from the local delivery path above; reset
    b.frames.length = 0;
    // Emit again via sub — still no double delivery
    subMock._emit('message', 'crewlink:convoy:convoy-1', JSON.stringify({
      frame: 'x',
      originMemberId: 'alice',
      instanceId,
    }));
    expect(b.frames).toHaveLength(0);
  });

  it('subscribes to Redis channel when first local connection joins', async () => {
    await fanout.connect();
    fanout.addLocalConnection('convoy-1', makeSender('alice'));
    expect(subMock.subscribe).toHaveBeenCalledWith('crewlink:convoy:convoy-1');
  });

  it('unsubscribes from Redis channel when last local connection leaves', async () => {
    await fanout.connect();
    const remove = fanout.addLocalConnection('convoy-1', makeSender('alice'));
    remove();
    expect(subMock.unsubscribe).toHaveBeenCalledWith('crewlink:convoy:convoy-1');
  });

  it('close() calls quit on both connections', async () => {
    await fanout.connect();
    await fanout.close();
    expect(pubMock.quit).toHaveBeenCalledOnce();
    expect(subMock.quit).toHaveBeenCalledOnce();
  });
});
