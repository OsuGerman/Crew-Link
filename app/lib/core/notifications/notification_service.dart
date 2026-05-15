import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Abstraction over the local-notification plugin so callers and tests are
/// decoupled from platform channels.
abstract class NotificationService {
  Future<void> init();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  Future<void> showSplit({
    required int id,
    required String memberName,
    required double distanceMeters,
  });

  Future<void> showConnectionLost({
    required int notificationId,
    required String memberName,
    required double thresholdMeters,
  });
}

/// Production implementation backed by [FlutterLocalNotificationsPlugin].
class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestBadgePermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'convoy_breach',
          'Konvoi-Abstandswarnung',
          channelDescription:
              'Benachrichtigung bei Abstandsverletzung im Konvoi',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> showConnectionLost({
    required int notificationId,
    required String memberName,
    required double thresholdMeters,
  }) async {
    final thresholdStr = thresholdMeters.toStringAsFixed(0);
    await _plugin.show(
      notificationId,
      'Anschluss verloren',
      '$memberName ist mehr als $thresholdStr m entfernt',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'convoy_connection',
          'Konvoi-Verbindung',
          channelDescription:
              'Benachrichtigung wenn ein Mitglied den Anschluss verliert',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> showSplit({
    required int id,
    required String memberName,
    required double distanceMeters,
  }) async {
    final distStr = distanceMeters.toStringAsFixed(0);
    await _plugin.show(
      id,
      'Konvoi getrennt!',
      '$memberName ist $distStr m entfernt – Konvoi gesplittet!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'convoy_split',
          'Konvoi-Split',
          channelDescription: 'Benachrichtigung bei dauerhafter Trennung vom Konvoi',
          importance: Importance.max,
          priority: Priority.max,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }
}
