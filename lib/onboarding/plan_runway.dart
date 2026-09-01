/// How much runway the athlete has between today and race day, and what to
/// say about it.
///
/// Three regimes, one component. The funnel we tore down handles all three and
/// it is the most quietly impressive thing they do: too little time gets a
/// fast-track plan plus an honest warning, the right amount gets endorsed, and
/// too much gets absorbed into a foundation block rather than making an eager
/// athlete sit and wait.
///
/// ENGINE-TODO (deferred — see [[onboarding-deferred-engine-work]]):
///   There is no engine-side notion of a recommended plan length. RacePlanBuilder
///   only knows `weeksOut < 4 => minimal plan`. The tables below are onboarding
///   policy and should move into the planner so re-planning and mid-plan
///   rebuilds agree with what onboarding promised.
library;

enum RunwayRegime {
  /// Less time than the distance really wants — compress and say so.
  short,

  /// About right.
  matched,

  /// More time than needed; the surplus becomes a base-building block.
  surplus,
}

class PlanRunway {
  final RunwayRegime regime;
  final int weeksAvailable;

  /// Ideal build length for the distance.
  final int recommendedWeeks;

  /// Below this we intercept before the athlete invests in the funnel.
  final int minimumWeeks;

  /// Surplus only — weeks of base building ahead of the race block.
  final int foundationWeeks;

  const PlanRunway({
    required this.regime,
    required this.weeksAvailable,
    required this.recommendedWeeks,
    required this.minimumWeeks,
    required this.foundationWeeks,
  });

  /// True when the race is so close that a real build is not possible. Drives
  /// the interception sheet on race pick — a fork, never a dead end.
  bool get isShortNotice => weeksAvailable < minimumWeeks;

  /// Short label for the selected start option.
  String get verdict => switch (regime) {
    RunwayRegime.short => 'Fast-track training',
    RunwayRegime.matched => 'Recommended for optimal performance',
    RunwayRegime.surplus =>
      '$foundationWeeks week base phase, then the race block',
  };

  /// Amber note shown under the options. Null when the runway is fine.
  String? warningFor(String goal) {
    if (regime != RunwayRegime.short) return null;
    return 'Recommended: $recommendedWeeks+ weeks for a ${labelFor(goal)}. '
        'Your plan is $weeksAvailable weeks, so it will be compressed.';
  }

  static String labelFor(String goal) => switch (goal) {
    '10k' => '10K',
    'half_marathon' => 'half marathon',
    'marathon' => 'marathon',
    _ => '5K',
  };

  /// Ideal build length per distance.
  static int recommendedFor(String goal) => switch (goal) {
    '10k' => 10,
    'half_marathon' => 12,
    'marathon' => 16,
    _ => 8,
  };

  /// Below this, training cannot meaningfully build new fitness for the
  /// distance — only sharpen what is already there.
  static int minimumFor(String goal) => switch (goal) {
    '10k' => 5,
    'half_marathon' => 6,
    'marathon' => 8,
    _ => 4,
  };

  static PlanRunway resolve({
    required String goal,
    required int weeksAvailable,
  }) {
    final recommended = recommendedFor(goal);
    final minimum = minimumFor(goal);

    // A couple of weeks over the ideal is still "about right" — no point
    // inventing a one-week foundation block.
    const surplusThreshold = 2;

    final RunwayRegime regime;
    var foundation = 0;
    if (weeksAvailable < recommended) {
      regime = RunwayRegime.short;
    } else if (weeksAvailable <= recommended + surplusThreshold) {
      regime = RunwayRegime.matched;
    } else {
      regime = RunwayRegime.surplus;
      foundation = weeksAvailable - recommended;
    }

    return PlanRunway(
      regime: regime,
      weeksAvailable: weeksAvailable,
      recommendedWeeks: recommended,
      minimumWeeks: minimum,
      foundationWeeks: foundation,
    );
  }
}
