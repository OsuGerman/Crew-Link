import { pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  appleUserId: text('apple_user_id').notNull().unique(),
  displayName: text('display_name').notNull(),
  email: text('email'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
