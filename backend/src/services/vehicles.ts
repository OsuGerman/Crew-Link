import { eq, inArray } from 'drizzle-orm';

import type { Database } from '../db/client.js';
import { vehicleMods, vehicles } from '../db/schema/vehicles.js';

export interface VehicleModApiPayload {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
}

export interface VehicleApiPayload {
  id: string;
  make: string;
  model: string;
  year: number | null;
  color: string | null;
  mods: VehicleModApiPayload[];
}

export interface ModInput {
  name: string;
  description?: string;
  category?: string;
}

export interface SetVehicleInput {
  make: string;
  model: string;
  year?: number;
  color?: string;
  mods?: ModInput[];
}

// MVP single-vehicle policy: each user has at most one vehicle.
// PUT replaces both the vehicle and its mods (delete-then-insert)
// inside a transaction so the loadConvoyPayload query can safely
// assume one row per user.
export async function setUserVehicle(
  db: Database,
  userId: string,
  input: SetVehicleInput,
): Promise<VehicleApiPayload> {
  return db.transaction(async (tx) => {
    await tx.delete(vehicles).where(eq(vehicles.userId, userId));
    const [created] = await tx
      .insert(vehicles)
      .values({
        userId,
        make: input.make,
        model: input.model,
        year: input.year ?? null,
        color: input.color ?? null,
      })
      .returning();
    if (!created) {
      throw new Error('vehicle insert returned no row');
    }

    const insertedMods: VehicleModApiPayload[] = [];
    const mods = input.mods ?? [];
    if (mods.length > 0) {
      const rows = await tx
        .insert(vehicleMods)
        .values(mods.map((m) => ({
          vehicleId: created.id,
          name: m.name,
          description: m.description ?? null,
          category: m.category ?? null,
        })))
        .returning();
      for (const row of rows) {
        insertedMods.push({
          id: row.id,
          name: row.name,
          description: row.description,
          category: row.category,
        });
      }
    }

    return toApi(created, insertedMods);
  });
}

export async function getUserVehicle(
  db: Database,
  userId: string,
): Promise<VehicleApiPayload | null> {
  const [row] = await db
    .select()
    .from(vehicles)
    .where(eq(vehicles.userId, userId))
    .limit(1);
  if (!row) return null;
  const mods = await db
    .select()
    .from(vehicleMods)
    .where(eq(vehicleMods.vehicleId, row.id));
  return toApi(
    row,
    mods.map((m) => ({
      id: m.id,
      name: m.name,
      description: m.description,
      category: m.category,
    })),
  );
}

export async function deleteUserVehicle(
  db: Database,
  userId: string,
): Promise<void> {
  // vehicle_mods cascade-delete via FK when the parent vehicle row is removed.
  await db.delete(vehicles).where(eq(vehicles.userId, userId));
}

/// Batch-load mods for many vehicle ids in one query — used by the
/// convoy member list to avoid an N+1 trap.
export async function loadModsByVehicleId(
  db: Database,
  vehicleIds: string[],
): Promise<Map<string, VehicleModApiPayload[]>> {
  const grouped = new Map<string, VehicleModApiPayload[]>();
  if (vehicleIds.length === 0) return grouped;
  const rows = await db
    .select()
    .from(vehicleMods)
    .where(inArray(vehicleMods.vehicleId, vehicleIds));
  for (const row of rows) {
    const list = grouped.get(row.vehicleId) ?? [];
    list.push({
      id: row.id,
      name: row.name,
      description: row.description,
      category: row.category,
    });
    grouped.set(row.vehicleId, list);
  }
  return grouped;
}

function toApi(
  row: typeof vehicles.$inferSelect,
  mods: VehicleModApiPayload[],
): VehicleApiPayload {
  return {
    id: row.id,
    make: row.make,
    model: row.model,
    year: row.year,
    color: row.color,
    mods,
  };
}
