// lib/theme/app_theme.dart
//
// Light and dark ThemeData for the app. Both register the AppColors extension
// so screens can read semantic tokens via `context.colors`, and both keep the
// Material-level theming (appBar, bottom nav, switches, buttons) in sync with
// the palette.

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData _build(AppColors c, Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: c.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accent,
        onSecondary: c.onAccent,
        surface: c.surface,
        onSurface: c.textPrimary,
        error: c.danger,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.textPrimary,
        unselectedItemColor: c.textTertiary,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (brightness == Brightness.dark
                    ? const Color(0xFF6E6E73)
                    : const Color(0xFF555555))
              : (brightness == Brightness.dark
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFFDDDDDD)),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (brightness == Brightness.dark
                    ? const Color(0xFF6E6E73)
                    : const Color(0xFF555555))
              : (brightness == Brightness.dark
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFFCCCCCC)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.textPrimary),
      ),
      extensions: [c],
    );
  }

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);
}
