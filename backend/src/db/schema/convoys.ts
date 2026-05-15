import {
  doublePrecision,
  integer,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

import { geographyPoint } from './geo.js';
import { users } from './users.js';
import { vehicles } from './vehicles.js';

export const DEFAULT_PROXIMITY_THRESHOLD_M = 500;

export const convoyStatusValues = ['lobby', 'active', 'ended'] as const;
export type ConvoyStatus = (typeof convoyStatusValues)[number];

export const convoyMemberRoleValues = ['owner', 'member'] as const;
export type ConvoyMemberRole = (typeof convoyMemberRoleValues)[number];

export const convoys = pgTable('convoys', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerUserId: uuid('owner_user_id')
    .references(() => users.id)
    .notNull(),
  name: text('name').notNull(),
  inviteCode: text('invite_code').notNull().unique(),
  status: text('status', { enum: convoyStatusValues }).notNull().default('lobby'),
  proximityThresholdM: integer('proximity_threshold_m')
    .notNull()
    .default(DEFAULT_PROXIMITY_THRESHOLD_M),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }),
  endedAt: timestamp('ended_at', { withTimezone: true }),
  // Convoy destination — set by the owner via PATCH /convoys/:id.
  // All three fields are populated together (or all null). Plain
  // numeric columns instead of PostGIS because the clients compute
  // their own distance — no server-side geo queries needed.
  destinationLat: doublePrecision('destination_lat'),
  destinationLng: doublePrecision('destination_lng'),
  destinationLabel: text('destination_label'),
});

export const convoyMembers = pgTable(
  'convoy_members',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    convoyId: uuid('convoy_id')
      .references(() => convoys.id, { onDelete: 'cascade' })
      .notNull(),
    userId: uuid('user_id')
      .references(() => users.id, { onDelete: 'cascade' })
      .notNull(),
    vehicleId: uuid('vehicle_id').references(() => vehicles.id, {
      onDelete: 'set null',
    }),
    role: text('role', { enum: convoyMemberRoleValues }).notNull().default('member'),
    joinedAt: timestamp('joined_at', { withTimezone: true }).defaultNow().notNull(),
    leftAt: timestamp('left_at', { withTimezone: true }),
    lastKnownPosition: geographyPoint('last_known_position'),
    lastPositionAt: timestamp('last_position_at', { withTimezone: true }),
  },
  (table) => [
    uniqueIndex('convoy_members_convoy_user_unique').on(table.convoyId, table.userId),
  ],
);

export type Convoy = typeof convoys.$inferSelect;
export type NewConvoy = typeof convoys.$inferInsert;
export type ConvoyMember = typeof convoyMembers.$inferSelect;
export type NewConvoyMember = typeof convoyMembers.$inferInsert;
