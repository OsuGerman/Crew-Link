import { and, eq, isNull } from 'drizzle-orm';

import type { Database } from '../db/client.js';
import {
  convoyMembers,
  convoys,
  users,
  vehicles,
} from '../db/schema/index.js';
import { generateInviteCode } from '../util/invite_code.js';
import { loadModsByVehicleId, type VehicleApiPayload } from './vehicles.js';

export class ConvoyNotFoundError extends Error {
  constructor(public readonly convoyId: string) {
    super(`Convoy ${convoyId} not found`);
    this.name = 'ConvoyNotFoundError';
  }
}

export class NotConvoyOwnerError extends Error {
  constructor() {
    super('Only the convoy owner can perform this action');
    this.name = 'NotConvoyOwnerError';
  }
}

export class InviteCodeNotFoundError extends Error {
  constructor(public readonly inviteCode: string) {
    super(`Invite code ${inviteCode} not found`);
    this.name = 'InviteCodeNotFoundError';
  }
}

export interface ConvoyMemberApiPayload {
  id: string;
  displayName: string;
  vehicleProfileId: string | null;
  vehicle: VehicleApiPayload | null;
  isLeader: boolean;
}

export interface ConvoyApiPayload {
  id: string;
  name: string;
  inviteCode: string;
  members: ConvoyMemberApiPayload[];
  proximityWarningMeters: number;
  createdAt: string;
}

export interface CreateConvoyInput {
  ownerUserId: string;
  name: string;
  proximityWarningMeters: number;
}

export async function createConvoy(
  db: Database,
  input: CreateConvoyInput,
): Promise<ConvoyApiPayload> {
  const inviteCode = generateInviteCode();
  const convoyRow = await db.transaction(async (tx) => {
    const [convoy] = await tx
      .insert(convoys)
      .values({
        ownerUserId: input.ownerUserId,
        name: input.name,
        inviteCode,
        proximityThresholdM: input.proximityWarningMeters,
      })
      .returning();
    if (!convoy) {
      throw new Error('convoy insert returned no row');
    }
    await tx.insert(convoyMembers).values({
      convoyId: convoy.id,
      userId: input.ownerUserId,
      role: 'owner',
    });
    return convoy;
  });
  return loadConvoyPayload(db, convoyRow.id);
}

export interface JoinConvoyInput {
  userId: string;
  inviteCode: string;
}

export async function joinConvoy(
  db: Database,
  input: JoinConvoyInput,
): Promise<ConvoyApiPayload> {
  const [convoy] = await db
    .select()
    .from(convoys)
    .where(eq(convoys.inviteCode, input.inviteCode))
    .limit(1);
  if (!convoy) {
    throw new InviteCodeNotFoundError(input.inviteCode);
  }

  const [existing] = await db
    .select()
    .from(convoyMembers)
    .where(
      and(
        eq(convoyMembers.convoyId, convoy.id),
        eq(convoyMembers.userId, input.userId),
      ),
    )
    .limit(1);

  if (existing) {
    if (existing.leftAt !== null) {
      await db
        .update(convoyMembers)
        .set({ leftAt: null })
        .where(eq(convoyMembers.id, existing.id));
    }
  } else {
    await db.insert(convoyMembers).values({
      convoyId: convoy.id,
      userId: input.userId,
      role: 'member',
    });
  }

  return loadConvoyPayload(db, convoy.id);
}

export interface LeaveConvoyInput {
  userId: string;
  convoyId: string;
}

export async function leaveConvoy(
  db: Database,
  input: LeaveConvoyInput,
): Promise<void> {
  await db
    .update(convoyMembers)
    .set({ leftAt: new Date() })
    .where(
      and(
        eq(convoyMembers.convoyId, input.convoyId),
        eq(convoyMembers.userId, input.userId),
        isNull(convoyMembers.leftAt),
      ),
    );
}

export interface SetConvoyDestinationInput {
  userId: string;
  convoyId: string;
  destination: { lat: number; lng: number; label: string | null } | null;
}

export async function setConvoyDestination(
  db: Database,
  input: SetConvoyDestinationInput,
): Promise<ConvoyApiPayload> {
  const rows = await db
    .select()
    .from(convoys)
    .where(eq(convoys.id, input.convoyId))
    .limit(1);
  const convoy = rows[0];
  if (!convoy) {
    throw new ConvoyNotFoundError(input.convoyId);
  }
  if (convoy.ownerUserId !== input.userId) {
    throw new NotConvoyOwnerError();
  }
  await db
    .update(convoys)
    .set(
      input.destination === null
        ? { destinationLat: null, destinationLng: null, destinationLabel: null }
        : {
            destinationLat: input.destination.lat,
            destinationLng: input.destination.lng,
            destinationLabel: input.destination.label,
          },
    )
    .where(eq(convoys.id, input.convoyId));
  return loadConvoyPayload(db, input.convoyId);
}

async function loadConvoyPayload(
  db: Database,
  convoyId: string,
): Promise<ConvoyApiPayload> {
  const [convoy] = await db
    .select()
    .from(convoys)
    .where(eq(convoys.id, convoyId))
    .limit(1);
  if (!convoy) {
    throw new Error(`convoy ${convoyId} not found post-write`);
  }

  // LEFT JOIN vehicles via convoy_members.user_id assumes the single-
  // vehicle-per-user invariant enforced by PUT /vehicles/me. If multiple
  // vehicles ever exist for a user (legacy data, mods system), the
  // result will duplicate member rows — add an `is_primary` flag and
  // filter on it before relaxing the invariant.
  const memberRows = await db
    .select({
      userId: convoyMembers.userId,
      vehicleProfileId: convoyMembers.vehicleId,
      role: convoyMembers.role,
      displayName: users.displayName,
      vId: vehicles.id,
      vMake: vehicles.make,
      vModel: vehicles.model,
      vYear: vehicles.year,
      vColor: vehicles.color,
    })
    .from(convoyMembers)
    .innerJoin(users, eq(convoyMembers.userId, users.id))
    .leftJoin(vehicles, eq(vehicles.userId, convoyMembers.userId))
    .where(
      and(
        eq(convoyMembers.convoyId, convoyId),
        isNull(convoyMembers.leftAt),
      ),
    );

  // Batch-load mods for every vehicle present in this convoy.
  const vehicleIds = memberRows
    .map((m) => m.vId)
    .filter((id): id is string => id !== null);
  const modsByVehicleId = await loadModsByVehicleId(db, vehicleIds);

  return {
    id: convoy.id,
    name: convoy.name,
    inviteCode: convoy.inviteCode,
    proximityWarningMeters: convoy.proximityThresholdM,
    createdAt: convoy.createdAt.toISOString(),
    members: memberRows.map((m) => ({
      id: m.userId,
      displayName: m.displayName,
      vehicleProfileId: m.vehicleProfileId,
      vehicle: m.vId !== null
          ? {
              id: m.vId,
              make: m.vMake!,
              model: m.vModel!,
              year: m.vYear,
              color: m.vColor,
              mods: modsByVehicleId.get(m.vId) ?? [],
            }
          : null,
      isLeader: m.role === 'owner',
    })),
  };
}
