import { pgTable, smallint, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { users } from './users.js';

export const vehicles = pgTable('vehicles', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id')
    .references(() => users.id, { onDelete: 'cascade' })
    .notNull(),
  make: text('make').notNull(),
  model: text('model').notNull(),
  year: smallint('year'),
  color: text('color'),
  photoUrl: text('photo_url'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

export const vehicleMods = pgTable('vehicle_mods', {
  id: uuid('id').primaryKey().defaultRandom(),
  vehicleId: uuid('vehicle_id')
    .references(() => vehicles.id, { onDelete: 'cascade' })
    .notNull(),
  name: text('name').notNull(),
  description: text('description'),
  category: text('category'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export type Vehicle = typeof vehicles.$inferSelect;
export type NewVehicle = typeof vehicles.$inferInsert;
export type VehicleMod = typeof vehicleMods.$inferSelect;
export type NewVehicleMod = typeof vehicleMods.$inferInsert;
