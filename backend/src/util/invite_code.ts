import { randomInt } from 'node:crypto';

// 32-character alphabet with the ambiguous glyphs removed (no O/0/I/1).
// Six characters give ~10^9 combinations — collision risk at this scale
// is negligible, so we don't retry on unique-constraint violation. If
// the convoy table ever grows large enough for that to matter, switch
// to retry-with-new-code or widen the code length.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const DEFAULT_LENGTH = 6;

export function generateInviteCode(length: number = DEFAULT_LENGTH): string {
  const chars: string[] = [];
  for (let i = 0; i < length; i += 1) {
    chars.push(ALPHABET.charAt(randomInt(0, ALPHABET.length)));
  }
  return chars.join('');
}
