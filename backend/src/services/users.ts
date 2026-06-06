import { eq } from 'drizzle-orm';

import type { Database } from '../db/client.js';
import { convoys } from '../db/schema/convoys.js';
import { users } from '../db/schema/users.js';

/// Deletes a user and all their data (GDPR / Play Store account deletion).
///
/// Order matters: convoys the user OWNS are deleted first because
/// `convoys.owner_user_id -> users.id` has no `onDelete` rule (a plain user
/// delete would hit a FK violation). Deleting a convoy cascade-removes its
/// members, so the remaining members simply return to the lobby. The user-row
/// delete then cascades the rest: their vehicle (+ mods) and their memberships
/// in convoys owned by other people. Runs in one transaction so a partial
/// delete can never leave an orphaned account.
export async function deleteUserAccount(
  db: Database,
  userId: string,
): Promise<void> {
  await db.transaction(async (tx) => {
    await tx.delete(convoys).where(eq(convoys.ownerUserId, userId));
    await tx.delete(users).where(eq(users.id, userId));
  });
}
