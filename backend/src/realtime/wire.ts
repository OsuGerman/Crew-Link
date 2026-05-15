import { z } from 'zod';

// Wire-format between the Flutter client (`convoy_socket_client.dart`)
// and the gateway. Keep payload field names aligned with the Dart
// models — `heading`/`speed`/`timestamp` on GPS, `setBy`/`setAt` on
// waypoints. Anti-impersonation enforcement in convoy_gateway.ts.

export const gpsPayloadSchema = z.object({
  memberId: z.string().min(1),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  heading: z.number(),
  speed: z.number().min(0),
  timestamp: z.string().datetime({ offset: true }),
  accuracy: z.number().min(0).optional(),
});

export type GpsPayload = z.infer<typeof gpsPayloadSchema>;

export const waypointPayloadSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  label: z.string().min(1).max(80),
  setBy: z.string().min(1),
  setAt: z.string().datetime({ offset: true }),
});

export type WaypointPayload = z.infer<typeof waypointPayloadSchema>;

/// Hazard-Type matching `app/lib/core/models/hazard_report.dart`.
/// Bewusst KEIN speed_camera-Wert (StVO-konform, siehe Dart-Doc).
export const hazardTypeSchema = z.enum([
  'construction',
  'accident',
  'traffic_jam',
  'broken_down_vehicle',
  'obstacle',
  'poor_visibility',
  'slippery_road',
  'police_checkpoint',
  'other',
]);

export const hazardPayloadSchema = z.object({
  id: z.string().min(1),
  type: hazardTypeSchema,
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  reporterId: z.string().min(1),
  createdAt: z.string().datetime({ offset: true }),
  convoyId: z.string().min(1).optional(),
  description: z.string().max(280).optional(),
  expiresAt: z.string().datetime({ offset: true }).optional(),
});

export type HazardPayload = z.infer<typeof hazardPayloadSchema>;

export const hazardRemovePayloadSchema = z.object({
  id: z.string().min(1),
});

/// Routenplan-Snapshot — vollständige Liste aller Stopps in Reihenfolge.
/// Max 20 Stopps (ungefährer Sanity-Cap gegen pathologische Payloads).
export const tourPayloadSchema = z.object({
  stops: z.array(waypointPayloadSchema).max(20),
});

export type TourPayload = z.infer<typeof tourPayloadSchema>;

/// Check-In: ein Mitglied bestätigt dass es einen Tour-Stopp erreicht hat.
/// `stopSignature` identifiziert den konkreten Stopp; siehe
/// `app/lib/features/convoy/domain/waypoint_check_in.dart`.
export const checkInPayloadSchema = z.object({
  memberId: z.string().min(1),
  stopSignature: z.string().min(1),
  arrivedAt: z.string().datetime({ offset: true }),
});

export type CheckInPayload = z.infer<typeof checkInPayloadSchema>;

export const gpsFrameSchema = z.object({
  type: z.literal('gps'),
  payload: gpsPayloadSchema,
});

export const waypointFrameSchema = z.object({
  type: z.literal('waypoint'),
  // null = clear-waypoint signal from leader
  payload: waypointPayloadSchema.nullable(),
});

export const hazardFrameSchema = z.object({
  type: z.literal('hazard'),
  payload: hazardPayloadSchema,
});

export const hazardRemoveFrameSchema = z.object({
  type: z.literal('hazard_remove'),
  payload: hazardRemovePayloadSchema,
});

export const tourFrameSchema = z.object({
  type: z.literal('tour'),
  payload: tourPayloadSchema,
});

export const checkInFrameSchema = z.object({
  type: z.literal('checkin'),
  payload: checkInPayloadSchema,
});

export const inboundFrameSchema = z.discriminatedUnion('type', [
  gpsFrameSchema,
  waypointFrameSchema,
  hazardFrameSchema,
  hazardRemoveFrameSchema,
  tourFrameSchema,
  checkInFrameSchema,
]);

export type InboundFrame = z.infer<typeof inboundFrameSchema>;

export type OutboundFrame = InboundFrame;

export function encodeFrame(frame: OutboundFrame): string {
  return JSON.stringify(frame);
}

/// Returns the originator memberId carried in the frame payload, used for
/// the anti-impersonation check in the gateway. Waypoint-clear frames
/// (payload === null) have no originator and are accepted as-is from the
/// authenticated sender.
export function originatorOf(frame: InboundFrame): string | null {
  if (frame.type === 'gps') return frame.payload.memberId;
  if (frame.type === 'waypoint') return frame.payload?.setBy ?? null;
  if (frame.type === 'hazard') return frame.payload.reporterId;
  if (frame.type === 'checkin') return frame.payload.memberId;
  // hazard_remove + tour have no single originator field. Tour requires
  // leader-only DB lookup; hazard_remove must match the original reporter.
  // Both deferred to a follow-up iteration.
  return null;
}
