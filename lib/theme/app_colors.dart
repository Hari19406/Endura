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

  /// Brand cyan used for data-viz highlights (charts, graphs). Same value as
  /// the paywall brand color — does not invert between palettes.
  final Color chartAccent;

  /// Pace-trend chart line (run detail). Does not invert between palettes.
  final Color paceAccent;

  /// Elevation-profile chart line (run detail) — warm/earthy, distinct from
  /// pace. Does not invert between palettes.
  final Color elevationAccent;

  /// Cadence chart line (run detail) — distinct from pace/elevation/HR.
  /// Does not invert between palettes. Heart rate intentionally reuses
  /// [danger] (red) rather than a dedicated token — it's already the
  /// correct semantic color for that chart.
  final Color cadenceAccent;

  /// Champagne gold — a second, deliberately rare accent reserved for
  /// "premium"/locked signifiers (paywall best-value badge, locked-workout
  /// padlock). Does not invert between palettes; [accent] stays the action
  /// color everywhere else so it never gets confused with this cue.
  final Color premiumGold;

  /// Hero/CTA gradient start and end stops, and the resulting gradient.
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final LinearGradient heroGradient;

  /// Faint chart grid/axis lines — distinct from [border]/[divider].
  final Color chartGrid;

  /// Heart-rate telemetry line. Previously reused [danger]; now dedicated
  /// so HR can diverge from the danger/error semantic.
  final Color hrAccent;

  /// Modal/backdrop overlay behind dialogs and bottom sheets.
  final Color scrim;

  /// Workout-type/day-circle colors. Single source of truth — replaces the
  /// duplicated hardcoded copies previously scattered across
  /// workout_type_style.dart, home_screen.dart, and run_screen_summary.dart.
  final Color workoutEasy;
  final Color workoutTempo;
  final Color workoutInterval;
  final Color workoutLong;

  /// Rest-day circle fill — pure white by design (a deliberate rest reads as
  /// a clean, empty slot, not another muted/gray status). Does not invert
  /// between palettes; day-circle widgets pair it with a [border] ring so it
  /// stays visible against a light-theme card background too.
  final Color workoutRest;

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
    required this.chartAccent,
    required this.paceAccent,
    required this.elevationAccent,
    required this.cadenceAccent,
    required this.premiumGold,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.heroGradient,
    required this.chartGrid,
    required this.hrAccent,
    required this.scrim,
    required this.workoutEasy,
    required this.workoutTempo,
    required this.workoutInterval,
    required this.workoutLong,
    required this.workoutRest,
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
    chartAccent: Color(0xFF00E5CC),
    paceAccent: Color(0xFF6A4FFF),
    elevationAccent: Color(0xFFC97B1D),
    cadenceAccent: Color(0xFF1FA97A),
    premiumGold: Color(0xFFE3C170),
    heroGradientStart: Color(0xFFC81865),
    heroGradientEnd: Color(0xFF6A1B9A),
    heroGradient: LinearGradient(
      colors: [Color(0xFFC81865), Color(0xFF6A1B9A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    chartGrid: Color(0x0F000000),
    hrAccent: Color(0xFFD6255F),
    scrim: Color(0x99000000),
    workoutEasy: Color(0xFF00B89A),
    workoutTempo: Color(0xFF7B2CBF),
    workoutInterval: Color(0xFFC81865),
    workoutLong: Color(0xFF0284C7),
    workoutRest: Color(0xFFFFFFFF),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0A0B0F),
    surface: Color(0xFF12131A),
    surfaceAlt: Color(0xFF181A24),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFFB4B4B8),
    textTertiary: Color(0xFF8A8A8F),
    textFaint: Color(0xFF5A5A5F),
    border: Color(0xFF202230),
    divider: Color(0xFF2C2C2E),
    accent: Color(0xFFF4F4F5),
    onAccent: Color(0xFF0B0B0C),
    danger: Color(0xFFEF5350),
    success: Color(0xFF66BB6A),
    chartAccent: Color(0xFF00E5CC),
    paceAccent: Color(0xFF8C6BFF),
    elevationAccent: Color(0xFFE8A33D),
    cadenceAccent: Color(0xFF3ADCA0),
    premiumGold: Color(0xFFE3C170),
    heroGradientStart: Color(0xFFE0247C),
    heroGradientEnd: Color(0xFF7B2CBF),
    heroGradient: LinearGradient(
      colors: [Color(0xFFE0247C), Color(0xFF7B2CBF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    chartGrid: Color(0x0FFFFFFF),
    hrAccent: Color(0xFFFF3366),
    scrim: Color(0x99000000),
    workoutEasy: Color(0xFF00E5CC),
    workoutTempo: Color(0xFF9D4EDD),
    workoutInterval: Color(0xFFE0247C),
    workoutLong: Color(0xFF38BDF8),
    workoutRest: Color(0xFFFFFFFF),
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
    Color? chartAccent,
    Color? paceAccent,
    Color? elevationAccent,
    Color? cadenceAccent,
    Color? premiumGold,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    LinearGradient? heroGradient,
    Color? chartGrid,
    Color? hrAccent,
    Color? scrim,
    Color? workoutEasy,
    Color? workoutTempo,
    Color? workoutInterval,
    Color? workoutLong,
    Color? workoutRest,
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
      chartAccent: chartAccent ?? this.chartAccent,
      paceAccent: paceAccent ?? this.paceAccent,
      elevationAccent: elevationAccent ?? this.elevationAccent,
      cadenceAccent: cadenceAccent ?? this.cadenceAccent,
      premiumGold: premiumGold ?? this.premiumGold,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      heroGradient: heroGradient ?? this.heroGradient,
      chartGrid: chartGrid ?? this.chartGrid,
      hrAccent: hrAccent ?? this.hrAccent,
      scrim: scrim ?? this.scrim,
      workoutEasy: workoutEasy ?? this.workoutEasy,
      workoutTempo: workoutTempo ?? this.workoutTempo,
      workoutInterval: workoutInterval ?? this.workoutInterval,
      workoutLong: workoutLong ?? this.workoutLong,
      workoutRest: workoutRest ?? this.workoutRest,
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
      chartAccent: Color.lerp(chartAccent, other.chartAccent, t)!,
      paceAccent: Color.lerp(paceAccent, other.paceAccent, t)!,
      elevationAccent: Color.lerp(elevationAccent, other.elevationAccent, t)!,
      cadenceAccent: Color.lerp(cadenceAccent, other.cadenceAccent, t)!,
      premiumGold: Color.lerp(premiumGold, other.premiumGold, t)!,
      heroGradientStart: Color.lerp(
        heroGradientStart,
        other.heroGradientStart,
        t,
      )!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      hrAccent: Color.lerp(hrAccent, other.hrAccent, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      workoutEasy: Color.lerp(workoutEasy, other.workoutEasy, t)!,
      workoutTempo: Color.lerp(workoutTempo, other.workoutTempo, t)!,
      workoutInterval: Color.lerp(workoutInterval, other.workoutInterval, t)!,
      workoutLong: Color.lerp(workoutLong, other.workoutLong, t)!,
      workoutRest: Color.lerp(workoutRest, other.workoutRest, t)!,
    );
  }
}

/// Convenience accessor: `context.colors.background`.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
