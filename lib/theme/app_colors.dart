// lib/theme/app_colors.dart
//
// Semantic colour tokens for the app, exposed as a ThemeExtension so they live
// inside ThemeData and switch automatically when the active brightness changes.
//
// Screens should never hardcode Color(0xFF...) / Colors.white. Instead read a
// semantic token via `context.colors.background`, `context.colors.textPrimary`
// etc. The light and dark palettes below are the single source of truth.

import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Page / scaffold background.
  final Color background;

  /// Card and elevated-surface background (was Colors.white).
  final Color surface;

  /// A slightly raised surface used for nav bars / sheets.
  final Color surfaceAlt;

  /// Primary text and icons (was 0xFF0A0A0A / 0xFF000000).
  final Color textPrimary;

  /// Secondary text (was 0xFF666666).
  final Color textSecondary;

  /// Muted / tertiary text and inactive icons (was 0xFF999999).
  final Color textTertiary;

  /// Very faint text, e.g. version label (was grey.shade400).
  final Color textFaint;

  /// Card / input borders (was 0xFFE8E8E8).
  final Color border;

  /// Hairline dividers (was grey.shade200).
  final Color divider;

  /// High-contrast accent used for primary buttons / selected states.
  /// Inverts between palettes (near-black on light, near-white on dark).
  final Color accent;

  /// Text/icon colour drawn on top of [accent].
  final Color onAccent;

  /// Destructive actions.
  final Color danger;

  /// Positive / success.
  final Color success;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textFaint,
    required this.border,
    required this.divider,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
  });

  static const AppColors light = AppColors(
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0A0A0A),
    textSecondary: Color(0xFF666666),
    textTertiary: Color(0xFF999999),
    textFaint: Color(0xFFBDBDBD),
    border: Color(0xFFE8E8E8),
    divider: Color(0xFFEEEEEE),
    accent: Color(0xFF0A0A0A),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFD32F2F),
    success: Color(0xFF388E3C),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0B0B0C),
    surface: Color(0xFF1A1A1C),
    surfaceAlt: Color(0xFF141416),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFFB4B4B8),
    textTertiary: Color(0xFF8A8A8F),
    textFaint: Color(0xFF5A5A5F),
    border: Color(0xFF2C2C2E),
    divider: Color(0xFF2C2C2E),
    accent: Color(0xFFF4F4F5),
    onAccent: Color(0xFF0B0B0C),
    danger: Color(0xFFEF5350),
    success: Color(0xFF66BB6A),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textFaint,
    Color? border,
    Color? divider,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? success,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textFaint: textFaint ?? this.textFaint,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

/// Convenience accessor: `context.colors.background`.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
