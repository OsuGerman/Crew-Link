import { describe, expect, test } from 'vitest';

import type { Database } from '../../src/db/client.js';
import { convoys } from '../../src/db/schema/convoys.js';
import { users } from '../../src/db/schema/users.js';
import { deleteUserAccount } from '../../src/services/users.js';

describe('deleteUserAccount', () => {
  test('deletes owned convoys before the user row (FK has no cascade)', async () => {
    const deleted: string[] = [];
    const tx = {
      delete(table: unknown) {
        deleted.push(
          table === convoys
              ? 'convoys'
              : table === users
                  ? 'users'
                  : 'other',
        );
        return { where: async (_cond?: unknown) => undefined };
      },
    };
    const db = {
      transaction: async (cb: (t: unknown) => Promise<void>) => {
        await cb(tx);
      },
    };

    await deleteUserAccount(db as unknown as Database, 'user-1');

    // owned convoys MUST be removed before the user row, otherwise the
    // convoys.owner_user_id FK (no cascade) would reject the delete.
    expect(deleted).toEqual(['convoys', 'users']);
  });
});
