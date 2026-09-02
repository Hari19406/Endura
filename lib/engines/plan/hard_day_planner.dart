/// HardDayPlanner — decides how many quality sessions a week carries and which
/// of the athlete's real training weekdays become Q1 / Q2 / long run / easy.
///
/// Replaces WeekResolver._anchoredPattern's fixed "Easy/Q1/Easy/Q2 by cyclic
/// rank" assignment with a tiny constraint solver over the actual chosen days.
///
/// Guarantees (when a valid layout exists):
///   - no quality day calendar-adjacent to another quality day
///   - no quality day calendar-adjacent to the long-run day
///   - the training day immediately before the long run stays easy (buffer)
///   - hard days spread as evenly as the week allows (max–min-gap)
/// Deterministic: ties break to the lexicographically smallest day set.
///
/// Pure — no engine imports, fully unit-testable.
library;

import '../../models/training_phase.dart';

/// Structural role for a single training day. Mirrors WeekResolver.SlotType but
/// kept local so this file has zero engine dependencies.
enum HardDayRole { longRun, quality1, quality2, easy }

class HardDayPlacement {
  /// weekday index (0 = Mon … 6 = Sun) → role, for every training day.
  final Map<int, HardDayRole> roles;

  /// Quality sessions actually placed (may be below the requested count when the
  /// chosen weekdays are too clustered to separate two hard days).
  final int resolvedQualityCount;

  /// True when a requested Q2 had to be dropped for lack of a valid layout.
  final bool droppedQuality;

  const HardDayPlacement({
    required this.roles,
    required this.resolvedQualityCount,
    required this.droppedQuality,
  });

  int get longRunDay =>
      roles.entries.firstWhere((e) => e.value == HardDayRole.longRun).key;

  List<int> get qualityDays => (roles.entries
          .where((e) =>
              e.value == HardDayRole.quality1 ||
              e.value == HardDayRole.quality2)
          .map((e) => e.key)
          .toList())
    ..sort();

  List<int> get easyDays => (roles.entries
          .where((e) => e.value == HardDayRole.easy)
          .map((e) => e.key)
          .toList())
    ..sort();
}

class HardDayPlanner {
  const HardDayPlanner();

  /// Canonical quality-session count for a week. Single source of truth — feed
  /// the result to both [placeHardDays] and ArchetypeTable.allocate.
  static int qualityCountFor({
    required int trainingDays,
    required TrainingPhase phase,
    bool isCutback = false,
  }) {
    final base = switch (phase) {
      // One quality session every week, all experience levels — for a beginner
      // the intent layer keeps it to threshold work, never intervals.
      TrainingPhase.base => 1,
      TrainingPhase.build => trainingDays >= 5 ? 2 : 1,
      TrainingPhase.peak => trainingDays >= 4 ? 2 : 1,
      TrainingPhase.taper => 1,
      TrainingPhase.maintenance => 1,
    };
    if (isCutback) return base.clamp(0, 1);
    return base;
  }

  /// Place roles across [trainingDayIndices]. [longRunDayIndex], if a training
  /// day, is honoured; otherwise the last training day is used.
  HardDayPlacement placeHardDays({
    required List<int> trainingDayIndices,
    required int? longRunDayIndex,
    required int qualityCount,
    required TrainingPhase phase,
  }) {
    final days = trainingDayIndices.toSet().toList()..sort();
    if (days.isEmpty) {
      return const HardDayPlacement(
        roles: {},
        resolvedQualityCount: 0,
        droppedQuality: false,
      );
    }

    final lrDay = (longRunDayIndex != null && days.contains(longRunDayIndex))
        ? longRunDayIndex
        : days.last;

    final nonLr = days.where((d) => d != lrDay).toList();
    final trainsBothEnds = days.contains(0) && days.contains(6);

    final wanted = qualityCount.clamp(0, nonLr.length);
    var dropped = false;

    List<int>? chosen;
    for (var q = wanted; q >= 1 && chosen == null; q--) {
      chosen = _bestSubset(
        candidates: nonLr,
        size: q,
        lrDay: lrDay,
        phase: phase,
        trainsBothEnds: trainsBothEnds,
      );
      if (chosen == null && q == wanted && wanted == 2) dropped = true;
    }

    // Nothing valid even at size 1 → force Q1 onto the least-bad day.
    if (chosen == null && wanted >= 1) {
      chosen = [_leastBadQ1(nonLr, lrDay, trainsBothEnds)];
    }
    chosen ??= const [];

    // Q1 = first quality day after the long run (cyclically); Q2 = the other.
    final ordered = [...chosen]
      ..sort((a, b) => _cyclic(a, lrDay).compareTo(_cyclic(b, lrDay)));

    final roles = <int, HardDayRole>{lrDay: HardDayRole.longRun};
    for (var i = 0; i < ordered.length; i++) {
      roles[ordered[i]] =
          i == 0 ? HardDayRole.quality1 : HardDayRole.quality2;
    }
    for (final d in nonLr) {
      roles.putIfAbsent(d, () => HardDayRole.easy);
    }

    return HardDayPlacement(
      roles: roles,
      resolvedQualityCount: ordered.length,
      droppedQuality: dropped,
    );
  }

  // ── Subset search ──────────────────────────────────────────────────────────

  List<int>? _bestSubset({
    required List<int> candidates,
    required int size,
    required int lrDay,
    required TrainingPhase phase,
    required bool trainsBothEnds,
  }) {
    if (size <= 0) return const [];
    if (candidates.length < size) return null;

    List<int>? best;
    num bestScore = -1;

    for (final subset in _combinations(candidates, size)) {
      if (!_valid(subset, lrDay, trainsBothEnds)) continue;
      final score = _spacingScore([...subset, lrDay], phase);
      if (score > bestScore ||
          (score == bestScore &&
              best != null &&
              _lexLess(subset, best))) {
        bestScore = score;
        best = subset;
      }
    }
    return best;
  }

  bool _valid(List<int> qs, int lrDay, bool trainsBothEnds) {
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      // Adjacency to the long run also covers the pre-LR buffer day (gap 1).
      if (_adjacent(q, lrDay, trainsBothEnds)) return false;
      for (var j = i + 1; j < qs.length; j++) {
        if (_adjacent(q, qs[j], trainsBothEnds)) return false;
      }
    }
    return true;
  }

  /// Minimum cyclic gap between consecutive hard days — higher is better.
  /// Base phase rewards even spread a little more; peak tolerates tighter.
  num _spacingScore(List<int> hardDays, TrainingPhase phase) {
    final sorted = [...hardDays]..sort();
    var minGap = 7;
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[(i + 1) % sorted.length];
      final gap = i + 1 < sorted.length ? b - a : (b + 7 - a);
      if (gap < minGap) minGap = gap;
    }
    final weight = switch (phase) {
      TrainingPhase.base => 1.15,
      TrainingPhase.peak => 0.9,
      _ => 1.0,
    };
    return minGap * weight;
  }

  int _leastBadQ1(List<int> candidates, int lrDay, bool trainsBothEnds) {
    // Farthest-from-LR day that isn't the immediate pre-LR day if avoidable.
    final ranked = [...candidates]..sort((a, b) {
      final da = _minCyclicDist(a, lrDay);
      final db = _minCyclicDist(b, lrDay);
      if (da != db) return db.compareTo(da); // farther first
      return a.compareTo(b);
    });
    return ranked.first;
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  bool _adjacent(int a, int b, bool trainsBothEnds) {
    final d = (a - b).abs();
    if (d == 1) return true;
    if (d == 6 && trainsBothEnds) return true; // Sun↔Mon wrap
    return false;
  }

  int _cyclic(int day, int from) => (day - from + 7) % 7;

  int _minCyclicDist(int a, int b) {
    final d = (a - b).abs();
    return d > 3 ? 7 - d : d;
  }

  bool _lexLess(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.length < b.length;
  }

  Iterable<List<int>> _combinations(List<int> items, int k) sync* {
    if (k == 0) {
      yield const [];
      return;
    }
    if (k > items.length) return;
    for (var i = 0; i <= items.length - k; i++) {
      for (final rest in _combinations(items.sublist(i + 1), k - 1)) {
        yield [items[i], ...rest];
      }
    }
  }
}
