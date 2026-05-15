import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../core/theme/app_theme.dart';

class CrewLinkApp extends ConsumerWidget {
  const CrewLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlay);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Crew Link',
      debugShowCheckedModeBanner: false,
      // App ist Dark-only (siehe Design-PDF). Wir setzen explizit dark als
      // theme + darkTheme + themeMode, damit auch System-Light-User die
      // gleiche Marken-Erfahrung bekommen.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
