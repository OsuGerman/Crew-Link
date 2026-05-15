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

  final Uri restBaseUrl;
  final Uri wsBaseUrl;
}
