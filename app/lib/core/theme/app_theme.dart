import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0066FF)),
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}
