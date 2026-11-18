import 'package:flutter/material.dart';

/// 앱 전체 디자인 기준. 색·모서리·글자 크기를 여기서만 정하고 화면은 이 값을 쓴다.
class PathfinderTheme {
  static const ink = Color(0xFF193B37);
  static const accent = Color(0xFF187D6B);
  static const muted = Color(0xFF647571);
  static const canvas = Color(0xFFF4F7F6);
  static const line = Color(0xFFE1E9E6);

  /// 안내 상자·선택된 칩 같은 연한 강조 바탕.
  static const tint = Color(0xFFEAF3F0);

  /// 카드·입력칸·버튼 모서리.
  static const radiusCard = 16.0;
  static const radiusControl = 12.0;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      surface: Colors.white,
    ).copyWith(primary: accent, outlineVariant: line);
    final control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );
    const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
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
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -.7,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: ink),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.5, color: muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: line)),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: line),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, height: 1.45, color: muted),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: accent,
        collapsedIconColor: muted,
        textColor: ink,
        collapsedTextColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFDDE4E2),
          disabledForegroundColor: const Color(0xFF8A9895),
          shape: control,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: accent,
          side: const BorderSide(color: Color(0xFFC9D8D3)),
          shape: control,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: control,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, space: 28),
      chipTheme: ChipThemeData(
        side: const BorderSide(color: line),
        backgroundColor: Colors.white,
        selectedColor: tint,
        checkmarkColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: Color(0xFF9DB0AB), width: 1.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: tint,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        actionTextColor: const Color(0xFF9FE3D2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
