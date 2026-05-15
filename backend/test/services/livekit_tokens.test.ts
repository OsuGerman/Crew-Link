import { describe, expect, it } from 'vitest';

import {
  convoyRoomName,
  createPttToken,
} from '../../src/services/livekit_tokens.js';

describe('convoyRoomName', () => {
  it('prefixes convoy-', () => {
    expect(convoyRoomName('abc-123')).toBe('convoy-abc-123');
  });

  it('is stable for the same input', () => {
    expect(convoyRoomName('x')).toBe(convoyRoomName('x'));
  });
});

describe('createPttToken', () => {
  const opts = {
    apiKey: 'test-key',
    // livekit-server-sdk requires the secret to be at least 32 bytes for HMAC-SHA256
    apiSecret: 'test-secret-that-is-at-least-32chars!',
    roomName: 'convoy-test-room',
    participantIdentity: 'user-uuid-001',
    participantName: 'Dev User',
  };

  it('returns a JWT with three dot-separated segments', async () => {
    const token = await createPttToken(opts);
    expect(token.split('.').length).toBe(3);
  });

  it('produces different tokens for different identities', async () => {
    const a = await createPttToken({ ...opts, participantIdentity: 'user-a' });
    const b = await createPttToken({ ...opts, participantIdentity: 'user-b' });
    expect(a).not.toBe(b);
  });
});
