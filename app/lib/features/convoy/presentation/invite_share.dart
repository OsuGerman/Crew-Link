import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/convoy.dart';
import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';

/// Play-Store-Eintrag der App — Bestandteil jedes geteilten Einladungstexts.
const kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.crewlink.crew_link';

/// Signatur des System-Share-Sheets. Injizierbar über
/// [shareLauncherProvider], damit Widget-Tests nicht das echte
/// share_plus-Plugin (Platform-Channel) brauchen.
typedef ShareLauncher = Future<void> Function(String text);

/// Default: share_plus (natives Share-Sheet auf iOS/Android).
final shareLauncherProvider = Provider<ShareLauncher>((ref) {
  return (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  };
});

/// Einladungstext mit Konvoi-Name + Code + Store-Link.
String buildInviteMessage(Convoy convoy) =>
    'Fahr mit im Konvoi ${convoy.name} — Code ${convoy.inviteCode}. '
    'App: $kPlayStoreUrl';

/// Öffnet das System-Share-Sheet mit dem Einladungstext. Schlägt das Plugin
/// fehl (z. B. Headless-Test, Plattform ohne Share-Sheet), greift der
/// bisherige Fallback: [fallbackClipboardText] in die Zwischenablage +
/// [fallbackSnackbarText] als Snackbar.
Future<void> shareConvoyInvite(
  BuildContext context,
  WidgetRef ref, {
  required Convoy convoy,
  required String fallbackClipboardText,
  required String fallbackSnackbarText,
  Duration? fallbackSnackbarDuration,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final share = ref.read(shareLauncherProvider);
  try {
    await share(buildInviteMessage(convoy));
  } catch (e, st) {
    appLog.e('shareConvoyInvite', error: e, stackTrace: st);
    unawaited(ObservabilityBootstrap.build().reportError(e, st));
    await Clipboard.setData(ClipboardData(text: fallbackClipboardText));
    messenger.showSnackBar(
      fallbackSnackbarDuration == null
          ? SnackBar(content: Text(fallbackSnackbarText))
          : SnackBar(
              content: Text(fallbackSnackbarText),
              duration: fallbackSnackbarDuration,
            ),
    );
  }
}
