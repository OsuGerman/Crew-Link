class ApiConfig {
  const ApiConfig({
    required this.restBaseUrl,
    required this.wsBaseUrl,
  });

  factory ApiConfig.production() => ApiConfig(
        restBaseUrl: Uri.parse('https://api.crewlink.app'),
        wsBaseUrl: Uri.parse('wss://rt.crewlink.app'),
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
    return ApiConfig.local();
  }

  final Uri restBaseUrl;
  final Uri wsBaseUrl;
}
