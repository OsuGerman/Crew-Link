import { z } from 'zod';

// Wire-format between the Flutter client (`convoy_socket_client.dart`)
// and the gateway. Keep payload field names aligned with the Dart
// model `GpsUpdate.toJson()` — `heading`/`speed`/`timestamp` etc.

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

export const inboundFrameSchema = z.object({
  type: z.literal('gps'),
  payload: gpsPayloadSchema,
});

export type InboundFrame = z.infer<typeof inboundFrameSchema>;

export type OutboundFrame = InboundFrame;

export function encodeFrame(frame: OutboundFrame): string {
  return JSON.stringify(frame);
}
