import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surfaceTint =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF7F8FF);
    final glassStroke = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.12);
    final backdropColor =
        isDark ? const Color(0xFF05070F) : const Color(0xFFEFF3FF);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: brightness,
      primary: isDark ? const Color(0xFF9BB8FF) : const Color(0xFF1A1C3A),
      onPrimary: isDark ? Colors.black : Colors.white,
      surface: surfaceTint,
      onSurface: isDark ? Colors.white : const Color(0xFF0E111D),
    );

    final textTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backdropColor,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: surfaceTint.withValues(alpha: isDark ? 0.65 : 0.8),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        foregroundColor: colorScheme.onSurface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceTint.withValues(alpha: isDark ? 0.95 : 0.98),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: glassStroke),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceTint.withValues(alpha: isDark ? 0.6 : 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: glassStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: glassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.6,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              colorScheme.onSurface.withValues(alpha: 0.8),
          side: BorderSide(color: glassStroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

