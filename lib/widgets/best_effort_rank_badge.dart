// lib/widgets/best_effort_rank_badge.dart
//
// The round rank marker for Best Efforts: gold / silver / bronze for the top
// three, a neutral circle after that. One widget shared by the Best Efforts
// leaderboard and the per-run card on Activity Detail so a rank always looks
// the same.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BestEffortRankBadge extends StatelessWidget {
  /// 1 = all-time best.
  final int rank;
  final double radius;

  const BestEffortRankBadge({super.key, required this.rank, this.radius = 14});

  // Medal ramp. A fixed data-viz palette (the same reason the HR zone hues are
  // fixed): AppColors has no gold/silver/bronze tokens, and the paywall's
  // `goldAccent` is reserved for monetisation, so it isn't reused here.
  static const _gold = (bg: Color(0xFFFAC775), fg: Color(0xFF412402));
  static const _silver = (bg: Color(0xFFD3D1C7), fg: Color(0xFF444441));
  static const _bronze = (bg: Color(0xFFF0997B), fg: Color(0xFF4A1B0C));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Color bg;
    final Color fg;
    final FontWeight weight;
    switch (rank) {
      case 1:
        (bg, fg, weight) = (_gold.bg, _gold.fg, FontWeight.w700);
      case 2:
        (bg, fg, weight) = (_silver.bg, _silver.fg, FontWeight.w700);
      case 3:
        (bg, fg, weight) = (_bronze.bg, _bronze.fg, FontWeight.w700);
      default:
        (bg, fg, weight) = (c.background, c.textSecondary, FontWeight.w600);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        '$rank',
        style: TextStyle(color: fg, fontWeight: weight, fontSize: 12),
      ),
    );
  }
}
