// lib/utils/split_strategy.dart
//
// First-half vs second-half pacing for a single run. Pure maths over the
// run's full-kilometre splits — the trailing partial split is never used.
//
// Halves: with n full kilometres, the first half is the first n ~/ 2 km and
// the second half the last n ~/ 2 km; for an odd n the middle kilometre is
// left out so both halves cover the same distance. At least [minFullKm] full
// kilometres are needed, otherwise there is no analysis (null).
//
// This is an observation about the run only. It does not touch the training
// engine, the plan or any vDOT.
library;

import '../models/activity_telemetry.dart' show KmSplit;

enum SplitStrategy { negative, even, positive }

class SplitStrategyAnalysis {
  /// Average pace of each half, seconds per km.
  final double firstHalfPace;
  final double secondHalfPace;

  /// Second minus first, seconds per km. Negative = sped up.
  final double differenceSecPerKm;
  final SplitStrategy strategy;

  /// The second half was meaningfully slower (see [SplitStrategies.fadeFraction]).
  final bool fade;

  /// Full kilometres analysed (partial split excluded).
  final int fullKm;

  const SplitStrategyAnalysis({
    required this.firstHalfPace,
    required this.secondHalfPace,
    required this.differenceSecPerKm,
    required this.strategy,
    required this.fade,
    required this.fullKm,
  });
}

class SplitStrategies {
  SplitStrategies._();

  static const int minFullKm = 4;

  /// Within this fraction of the first-half pace (min [minEvenBandSeconds])
  /// a run counts as an even split.
  static const double evenFraction = 0.01;
  static const double minEvenBandSeconds = 3;

  /// A second half this much slower than the first (as a fraction of the
  /// first-half pace) is flagged as a fade.
  static const double fadeFraction = 0.03;

  static SplitStrategyAnalysis? analyze(List<KmSplit> splits) {
    final full = [
      for (final s in splits)
        if (!s.isPartial && s.paceSeconds > 0) s,
    ]..sort((a, b) => a.km.compareTo(b.km));
    if (full.length < minFullKm) return null;

    final half = full.length ~/ 2;
    double mean(Iterable<KmSplit> xs) =>
        xs.fold<double>(0, (sum, s) => sum + s.paceSeconds) / xs.length;

    final first = mean(full.take(half));
    final second = mean(full.skip(full.length - half));
    final diff = second - first;
    final band = (first * evenFraction) < minEvenBandSeconds
        ? minEvenBandSeconds
        : first * evenFraction;

    final strategy = diff <= -band
        ? SplitStrategy.negative
        : diff >= band
        ? SplitStrategy.positive
        : SplitStrategy.even;

    return SplitStrategyAnalysis(
      firstHalfPace: first,
      secondHalfPace: second,
      differenceSecPerKm: diff,
      strategy: strategy,
      fade: diff >= first * fadeFraction,
      fullKm: full.length,
    );
  }
}
