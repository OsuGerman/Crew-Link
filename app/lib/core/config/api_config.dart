import 'package:flutter/foundation.dart' show kReleaseMode;

class ApiConfig {
  const ApiConfig({
    required this.restBaseUrl,
    required this.wsBaseUrl,
  });

  // Deployed backend baked into release builds when no --dart-define override
  // is passed. Repoint at a custom domain once one is set up.
  factory ApiConfig.production() => ApiConfig(
        restBaseUrl: Uri.parse('https://crew-link.onrender.com'),
        wsBaseUrl: Uri.parse('wss://crew-link.onrender.com'),
      );

  factory ApiConfig.local() => ApiConfig(
        restBaseUrl: Uri.parse('http://localhost:8080'),
        wsBaseUrl: Uri.parse('ws://localhost:8080'),
      );

  /// Targets the deployed backend when the app is built with
  /// `--dart-define=CREW_LINK_API_URL=https://… --dart-define=CREW_LINK_WS_URL=wss://…`.
  /// Falls back to [ApiConfig.local] for local development.
  factory ApiConfig.fromEnvironment() {
    const rest = String.fromEnvironment('CREW_LINK_API_URL');
    const ws = String.fromEnvironment('CREW_LINK_WS_URL');
    if (rest.isNotEmpty && ws.isNotEmpty) {
      return ApiConfig(
        restBaseUrl: Uri.parse(rest),
        wsBaseUrl: Uri.parse(ws),
      );
    }
    // A release build must never silently target localhost. Without the
    // dart-defines, ship the deployed backend; only debug/dev falls back local.
    return kReleaseMode ? ApiConfig.production() : ApiConfig.local();
  }

  final Uri restBaseUrl;
  final Uri wsBaseUrl;
}
