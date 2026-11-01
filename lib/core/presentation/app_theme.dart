import 'package:flutter/material.dart';

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: brightness,
        ).copyWith(
          primary: Color(dark ? 0xFFA8C7FA : 0xFF0B57D0),
          onPrimary: Color(dark ? 0xFF062E6F : 0xFFFFFFFF),
          primaryContainer: Color(dark ? 0xFF0842A0 : 0xFFD3E3FD),
          onPrimaryContainer: Color(dark ? 0xFFD3E3FD : 0xFF041E49),
          surface: Color(dark ? 0xFF131314 : 0xFFF8FAFD),
          surfaceContainerLowest: Color(dark ? 0xFF0E0E0F : 0xFFFFFFFF),
          surfaceContainerLow: Color(dark ? 0xFF1B1B1F : 0xFFF0F4F9),
          surfaceContainer: Color(dark ? 0xFF1F1F1F : 0xFFE9EEF6),
          surfaceContainerHigh: Color(dark ? 0xFF282A2C : 0xFFE3E9F3),
          surfaceContainerHighest: Color(dark ? 0xFF333537 : 0xFFDCE3EE),
          onSurface: Color(dark ? 0xFFE3E3E3 : 0xFF1F1F1F),
          onSurfaceVariant: Color(dark ? 0xFFC4C7C5 : 0xFF444746),
          outline: Color(dark ? 0xFF8E918F : 0xFF747775),
          outlineVariant: Color(dark ? 0xFF444746 : 0xFFC4C7C5),
          error: Color(dark ? 0xFFF2B8B5 : 0xFFB3261E),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: 'PaxFoxRoboto',
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.primaryContainer,
      ),
    );
  }
}
