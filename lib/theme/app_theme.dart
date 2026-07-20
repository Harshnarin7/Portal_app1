// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  final Color bg;
  final Color bgGradTop;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color borderLight;
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  final Color purple;
  final Color purpleSoft;
  final Color grey;
  final Color greySoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  const AppColors({
    required this.bg,
    required this.bgGradTop,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderLight,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.purple,
    required this.purpleSoft,
    required this.grey,
    required this.greySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });
}

class AppTheme {
  AppTheme._();

  // ── Light (Warm Slate Blue) ───────────────────────────────────────────────
  static const AppColors light = AppColors(
    bg           : Color(0xFFEFF3FB),
    bgGradTop    : Color(0xFFDDE6F5),
    surface      : Color(0xFFFFFFFF),
    surfaceAlt   : Color(0xFFF4F7FC),
    border       : Color(0xFFD4DCF0),
    borderLight  : Color(0xFFE8EDF8),
    primary      : Color(0xFF3B6FE0),
    primaryDark  : Color(0xFF2554C7),
    primarySoft  : Color(0xFFDDE6F5),
    success      : Color(0xFF0F9D58),
    successSoft  : Color(0xFFE6F4EA),
    danger       : Color(0xFFE53935),
    dangerSoft   : Color(0xFFFDECEC),
    warning      : Color(0xFFF59E0B),
    warningSoft  : Color(0xFFFFF8E1),
    purple       : Color(0xFF7C3AED),
    purpleSoft   : Color(0xFFF3EEFF),
    grey         : Color(0xFF6B7280),
    greySoft     : Color(0xFFF3F4F6),
    textPrimary  : Color(0xFF1A2340),
    textSecondary: Color(0xFF4A5578),
    textTertiary : Color(0xFF8A95B0),
  );

  // ── Dark ──────────────────────────────────────────────────────────────────
  static const AppColors dark = AppColors(
    bg           : Color(0xFF0D1117),
    bgGradTop    : Color(0xFF101827),
    surface      : Color(0xFF161E2E),
    surfaceAlt   : Color(0xFF1C2637),
    border       : Color(0xFF253047),
    borderLight  : Color(0xFF1E2A3D),
    primary      : Color(0xFF5B8DEF),
    primaryDark  : Color(0xFF3B6FE0),
    primarySoft  : Color(0xFF1A2845),
    success      : Color(0xFF34D399),
    successSoft  : Color(0xFF0D2E22),
    danger       : Color(0xFFF87171),
    dangerSoft   : Color(0xFF2D1515),
    warning      : Color(0xFFFBBF24),
    warningSoft  : Color(0xFF2A2007),
    purple       : Color(0xFFA78BFA),
    purpleSoft   : Color(0xFF1E1340),
    grey         : Color(0xFF9CA3AF),
    greySoft     : Color(0xFF1C2637),
    textPrimary  : Color(0xFFF0F4FF),
    textSecondary: Color(0xFF94A3CC),
    textTertiary : Color(0xFF566380),
  );

  /// Returns the correct color set for the current theme brightness.
  static AppColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  // ── Flutter ThemeData ─────────────────────────────────────────────────────
  static ThemeData lightThemeData() => _build(light, Brightness.light);
  static ThemeData darkThemeData()  => _build(dark,  Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme(
        brightness : brightness,
        primary    : c.primary,
        onPrimary  : Colors.white,
        secondary  : c.success,
        onSecondary: Colors.white,
        error      : c.danger,
        onError    : Colors.white,
        background : c.bg,
        onBackground: c.textPrimary,
        surface    : c.surface,
        onSurface  : c.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor    : c.surface,
        foregroundColor    : c.textPrimary,
        elevation          : 0,
        surfaceTintColor   : Colors.transparent,
        systemOverlayStyle : isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardColor          : c.surface,
      dividerColor       : c.borderLight,
      dialogBackgroundColor: c.surface,
      useMaterial3       : true,
    );
  }
}