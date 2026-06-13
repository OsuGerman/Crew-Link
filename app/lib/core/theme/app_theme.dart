import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Crew Link Designsystem — abgeleitet aus `Design.pdf` (12 Frames).
///
/// Kernregeln:
/// - Dark-Mode-only auf MVP-Ebene (das PDF zeigt ausschließlich dunkle Frames)
/// - Orange als signal-/marken-Akzent; weiß als CTA-Kontrast (Apple-Login)
/// - Tiefes Schwarz als Hauptflächen-Hintergrund, dunkelgraue Karten
/// - System-Status-Bar transparent + light icons
abstract final class AppColors {
  // Bezels/Background — geschichtete Helligkeits-Elevation: jede Ebene ist
  // messbar heller (und minimal kühler) als die darunter, damit Karten/Sheets
  // als echte Schichten über dem Grund schweben statt im Schwarz zu verschwinden
  // (Apple-Maps-Nacht / Polestar-HMI-Logik — Tiefe über Helligkeit, nicht Schatten).
  static const background = Color(0xFF0C0D10);
  static const surface = Color(0xFF16181D);
  static const surfaceHigh = Color(0xFF1F222A);
  static const surfaceOutline = Color(0xFF262A33);

  // Brand
  static const orange = Color(0xFFFF6A2B);
  static const orangeDeep = Color(0xFFE05312);
  static const orangeGlow = Color(0x55FF6A2B);

  // Sekundärer Daten-Akzent (gedämpftes HMI-Blau): NUR für sekundäre Daten —
  // Route-Linie, fremde Member-Pins, Live-Dot-Ring. Hält Orange als echtes
  // Handlungssignal frei (PTT/SOS/Primär-CTA) statt monochrom-orange.
  static const accentBlue = Color(0xFF3A6EA5);

  // Status
  static const danger = Color(0xFFC6342B);
  static const dangerSurface = Color(0xFF3A1411);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFFFC53D);

  // Text
  static const textPrimary = Color(0xFFF4F5F7);
  static const textSecondary = Color(0xFF9DA2AD);
  static const textMuted = Color(0xFF6B6B73);
}

abstract final class AppRadii {
  static const card = 20.0;
  static const button = 16.0;
  static const pill = 999.0;
  static const sheet = 24.0;
}

/// Linienstärken für das ruhige, flache System: durchgängig Haarlinien auf
/// neutralen Flächen, statt kräftiger Orange-Rahmen. Eine etwas dickere Variante
/// nur für aktiv/ausgewählte Elemente.
abstract final class AppBorders {
  static const hairline = 0.8;
  static const selected = 1.4;
}

/// Dezenter Orange-Tint für kleine Akzent-Container (z. B. das Icon-Plättchen
/// in einer CTA). Bewusst sehr schwach — Orange bleibt das Signal, nicht die
/// Fläche.
abstract final class AppAccents {
  static const orangeTint = Color(0x1FFF6A2B); // ~12 % Orange

  /// Dezenter Verlauf für die Primär-Taste (~6 % Helligkeitsdelta, KEIN
  /// bunter Multi-Hue-Gradient) — liest sich als physische, leicht gewölbte
  /// Taste statt als flacher Sticker.
  static const primaryButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF7A3C), Color(0xFFED5A1C)],
  );

  /// 1px innerer Top-Highlight auf der Primär-Taste (weiß ~8 %).
  static const buttonTopHighlight = Color(0x14FFFFFF);

  /// Dezenter Blau-Tint für sekundäre Daten-Plättchen (analog [orangeTint]).
  static const blueTint = Color(0x1F3A6EA5);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppTheme {
  /// Bevorzugte System-UI-Settings — vor `runApp` einmal setzen.
  static const systemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.orange,
      onPrimary: Colors.white,
      secondary: AppColors.orange,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.surfaceOutline,
    );

    // tabular figures durchgängig: Werte (Distanz, Member-Count, ETA, Code)
    // springen beim Live-Update nicht mehr in der Breite — Instrument-Gefühl.
    const tab = [FontFeature.tabularFigures()];
    const textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 34,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.6,
        fontFeatures: tab,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
        fontFeatures: tab,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
        fontFeatures: tab,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontFeatures: tab,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.4,
        color: AppColors.textPrimary,
        fontFeatures: tab,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppColors.textSecondary,
        fontFeatures: tab,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontFeatures: tab,
      ),
      // Kleine Section-Labels (orange, all-caps + tracking) werden über
      // AppTextStyles.sectionLabel angesteuert, nicht via TextTheme.
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.surfaceOutline,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ).copyWith(backgroundBuilder: _primaryButtonBackground),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.orange,
          side: const BorderSide(color: AppColors.orange, width: 1.4),
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.orange),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.surfaceOutline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          borderSide: const BorderSide(
              color: AppColors.surfaceOutline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  /// Backwards-Compat: einige Tests/Code referenzieren noch `AppTheme.light`.
  /// Wir geben das gleiche Dark-Theme zurück — die App ist Dark-only.
  static ThemeData get light => dark;
}

/// Hintergrund der Primär-Taste: leicht gewölbter Orange-Verlauf mit innerem
/// Top-Highlight — liest sich als physische, drückbare Taste statt flacher
/// Fläche. Deaktiviert → ruhige neutrale Fläche (sonst wirkt der Verlauf aktiv).
Widget _primaryButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  if (states.contains(WidgetState.disabled)) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: child,
    );
  }
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: AppAccents.primaryButtonGradient,
      borderRadius: BorderRadius.circular(AppRadii.button),
      border: const Border(
        top: BorderSide(color: AppAccents.buttonTopHighlight),
      ),
    ),
    child: child,
  );
}

/// Frei wiederverwendbare Text-Stile außerhalb der TextTheme (z. B. orange
/// Section-Labels mit Tracking, die nicht zu einer Material-Rolle passen).
abstract final class AppTextStyles {
  static const sectionLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
    color: AppColors.orange,
  );

  static const statusBadge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: AppColors.orange,
  );
}
