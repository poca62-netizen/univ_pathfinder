import 'package:flutter/material.dart';

class PathfinderTheme {
  static const ink = Color(0xFF193B37);
  static const accent = Color(0xFF187D6B);
  static const muted = Color(0xFF647571);
  static const canvas = Color(0xFFF4F7F6);
  static const line = Color(0xFFE1E9E6);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      textTheme: const TextTheme(
        labelSmall: TextStyle(fontSize: 12),
        headlineMedium: TextStyle(
          fontSize: 30,
          height: 1.25,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -1,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.7,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, space: 28),
      chipTheme: ChipThemeData(
        side: const BorderSide(color: line),
        backgroundColor: const Color(0xFFF0F5F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: const TextStyle(fontSize: 12, color: ink),
      ),
    );
  }
}
