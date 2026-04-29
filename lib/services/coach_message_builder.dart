import '../engines/config/workout_template_library.dart';
import '../models/training_phase.dart';

// ── Enums (kept for engine use) ───────────────────────────────────────────────

enum ProgressionSignal { progressing, holding, steppingBack }

// ── Pace range ────────────────────────────────────────────────────────────────

class PaceRange {
  final int minSecondsPerKm;
  final int maxSecondsPerKm;

  const PaceRange({
    required this.minSecondsPerKm,
    required this.maxSecondsPerKm,
  });
}

// ── Flat input — only real signals ────────────────────────────────────────────

class CoachContext {
  final int totalRunsCompleted;
  final int daysSinceLastRun;
  final double? avgRpe;
  final bool highRpeRecently;       // memory.hasHighRpe()
  final bool easyRunFeltTooHard;
  final ProgressionSignal progression;
  final bool wasDowngraded;
  final List<String> scalingAdjustments;
  final bool paceTrending;          // from PaceTrendCalculator
  final bool paceInsufficientData;

  const CoachContext({
    required this.totalRunsCompleted,
    required this.daysSinceLastRun,
    this.avgRpe,
    this.highRpeRecently = false,
    this.easyRunFeltTooHard = false,
    this.progression = ProgressionSignal.holding,
    this.wasDowngraded = false,
    this.scalingAdjustments = const [],
    this.paceTrending = false,
    this.paceInsufficientData = true,
  });

  bool get isNewUser => totalRunsCompleted == 0;
  bool get hasBeenAway => daysSinceLastRun >= 4;
  bool get bodyFeelsTough => highRpeRecently || easyRunFeltTooHard;
}

// ── Coach message ─────────────────────────────────────────────────────────────

class CoachMessage {
  final String reflectionText;
  final String acknowledgementText;
  final String workoutTitle;
  final List<String> workoutSteps;
  final ResolvedWorkout resolvedWorkout;
  final String goalText;
  final String feelText;
  final String phaseLabel;
  final int weekNumber;
  final WorkoutIntent workoutIntent;
  final String? movedFromDay;

  String get phaseWeekLabel =>
      weekNumber > 0 ? '$phaseLabel · Week $weekNumber' : phaseLabel;

  bool get hasWarmupCooldown =>
      workoutIntent == WorkoutIntent.threshold ||
      workoutIntent == WorkoutIntent.vo2max ||
      workoutIntent == WorkoutIntent.speed ||
      workoutIntent == WorkoutIntent.raceSpecific;

  double get totalDistanceKm => resolvedWorkout.totalDistanceKm;
  Duration get estimatedDuration => resolvedWorkout.estimatedDuration;

  const CoachMessage({
    required this.reflectionText,
    required this.acknowledgementText,
    required this.workoutTitle,
    required this.workoutSteps,
    required this.resolvedWorkout,
    required this.workoutIntent,
    this.goalText = '',
    this.feelText = '',
    this.phaseLabel = '',
    this.weekNumber = 1,
    this.movedFromDay,
  });
}

// ── Builder ───────────────────────────────────────────────────────────────────

class CoachMessageBuilder {
  CoachMessage buildMessage({
    required CoachContext context,
    required ResolvedWorkout resolvedWorkout,
    TrainingPhase phase = TrainingPhase.base,
    int weekNumber = 1,
  }) {
    final intent = resolvedWorkout.intent;
    return CoachMessage(
      reflectionText: _buildReflectionText(context),
      acknowledgementText: _buildAcknowledgementText(context, intent),
      workoutTitle: resolvedWorkout.name,
      workoutSteps: _buildWorkoutSteps(resolvedWorkout),
      resolvedWorkout: resolvedWorkout,
      workoutIntent: intent,
      goalText: _buildGoalText(intent, phase),
      feelText: _buildFeelText(intent),
      phaseLabel: _phaseDisplayName(phase),
      weekNumber: weekNumber,
    );
  }

  // ── Reflection — what's the honest state of training ──────────────────────

  String _buildReflectionText(CoachContext ctx) {
    if (ctx.isNewUser) {
      return "You're just getting started — the coach will learn your "
          'rhythm as you log runs.';
    }

    if (ctx.hasBeenAway) {
      final days = ctx.daysSinceLastRun;
      if (days >= 14) {
        return "It's been a couple of weeks off — your body has had a "
            'good rest.';
      }
      if (days >= 7) {
        return "It's been about a week since your last run — "
            'your body has had a good rest.';
      }
      return 'You had a few days off since your last run.';
    }

    if (ctx.easyRunFeltTooHard) {
      return 'Your last easy run felt harder than it should — '
          "that's a signal worth listening to.";
    }

    if (ctx.highRpeRecently) {
      return 'Your recent runs have been feeling tough. '
          "That's okay — it means you've been working hard.";
    }

    if (!ctx.paceInsufficientData && ctx.paceTrending) {
      return 'Your pace has been improving — the base work is paying off.';
    }

    if (ctx.paceInsufficientData) {
      return 'The coach is still building a picture of your training — '
          'keep logging and it will get sharper.';
    }

    return 'Your training has been consistent — the work is adding up.';
  }

  // ── Acknowledgement — what the engine decided and why ─────────────────────

  String _buildAcknowledgementText(CoachContext ctx, WorkoutIntent intent) {
    if (ctx.isNewUser) {
      return "Starting gentle — building your aerobic base from the ground up.";
    }

    if (ctx.hasBeenAway) {
      final days = ctx.daysSinceLastRun;
      if (days >= 14) {
        return "Easing back in carefully — no rush to pick up where you left off.";
      }
      if (days >= 7) {
        return "Welcome back. Today is adjusted to ease you back into rhythm.";
      }
      return "Picking up right where you left off — no adjustment needed.";
    }

    if (ctx.wasDowngraded) {
      return ctx.bodyFeelsTough
          ? "Keeping today lighter — your body is telling you it needs a gentler session."
          : "Keeping today a touch lighter so the work has time to sink in.";
    }

    return switch (ctx.progression) {
      ProgressionSignal.progressing => _progressOpener(intent),
      ProgressionSignal.holding     => _holdOpener(intent),
      ProgressionSignal.steppingBack => "Easing back slightly — "
          "a lighter day now sets you up for a stronger one next.",
    };
  }

  String _progressOpener(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.endurance  => "You're ready for a bit more — "
          "nudging the long run forward.",
      WorkoutIntent.threshold  => "The base is solid — "
          "pushing the quality work a touch further today.",
      WorkoutIntent.vo2max     => "Good form lately — "
          "adding a little more to the interval set.",
      _                        => "Things are coming together — "
          "building on the progress.",
    };
  }

  String _holdOpener(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.recovery   => "Active recovery today — "
          "keeping the legs moving without adding stress.",
      WorkoutIntent.aerobicBase => "Steady aerobic work — "
          "consistent easy running is the engine of progress.",
      _                        => "Holding steady — "
          "today is about absorbing the work already done.",
    };
  }

  // ── Goal text ─────────────────────────────────────────────────────────────

  String _buildGoalText(WorkoutIntent intent, TrainingPhase phase) {
    return switch (intent) {
      WorkoutIntent.aerobicBase => phase == TrainingPhase.base
          ? 'Building your aerobic engine with low-stress mileage.'
          : 'Active recovery between harder sessions.',
      WorkoutIntent.endurance =>
        'Building endurance and fat-burning capacity — the cornerstone '
            'of any training week.',
      WorkoutIntent.threshold =>
        'Raising your lactate threshold so you can sustain faster paces '
            'for longer.',
      WorkoutIntent.vo2max =>
        'Developing VO₂ max and raw speed through controlled '
            'high-intensity work.',
      WorkoutIntent.speed =>
        'Improving running economy and turnover with short, fast efforts.',
      WorkoutIntent.raceSpecific =>
        'Rehearsing goal race pace — building confidence and rhythm.',
      WorkoutIntent.recovery =>
        'Flushing fatigue and promoting active recovery without '
            'adding stress.',
    };
  }

  // ── Feel text ─────────────────────────────────────────────────────────────

  String _buildFeelText(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase =>
        'Conversational — you should be able to chat the whole time. RPE 3–4.',
      WorkoutIntent.endurance =>
        'Easy and sustainable — slow enough to feel easy at km 1 and '
            'km 15. RPE 3–5.',
      WorkoutIntent.threshold =>
        'Comfortably hard — you can speak a word or two, but not a '
            'sentence. RPE 7–8.',
      WorkoutIntent.vo2max =>
        'Hard effort during reps, genuine recovery between. RPE 8–9 on reps.',
      WorkoutIntent.speed =>
        'Short controlled bursts that feel light and snappy, not '
            'maximal. RPE 7–9.',
      WorkoutIntent.raceSpecific =>
        'Race pace — controlled, rhythmic, sustainable. RPE 7–8.',
      WorkoutIntent.recovery =>
        'Slower than easy. Almost embarrassingly slow. RPE 2–3.',
    };
  }

  // ── Workout steps ─────────────────────────────────────────────────────────

  List<String> _buildWorkoutSteps(ResolvedWorkout workout) {
    if (workout.blocks.isEmpty) return ['Full rest day — no running.'];

    final steps = <String>[];
    for (final block in workout.blocks) {
      final step = _formatBlock(block);
      if (step.isNotEmpty) steps.add(step);
    }

    return steps.isEmpty ? _fallbackSteps(workout.intent) : steps;
  }

  String _formatBlock(ResolvedBlock block) {
    final buf = StringBuffer();
    final label = block.label ?? _blockTypeLabel(block.type);
    buf.write(label);

    if (block.reps != null && block.reps! > 1) {
      buf.write(': ${block.reps} × ${block.formattedDistance}');
    } else {
      buf.write(': ${block.formattedDistance}');
    }

    buf.write(' at ${block.formattedPace}');

    if (block.recovery != null && block.reps != null && block.reps! > 1) {
      buf.write(' (${block.recovery!.formattedDistance} jog recovery)');
    }

    return buf.toString();
  }

  String _blockTypeLabel(BlockType type) => switch (type) {
    BlockType.warmup   => 'Warmup',
    BlockType.main     => 'Run',
    BlockType.recovery => 'Recovery',
    BlockType.cooldown => 'Cooldown',
  };

  String _phaseDisplayName(TrainingPhase phase) => switch (phase) {
    TrainingPhase.base  => 'Base Phase',
    TrainingPhase.build => 'Build Phase',
    TrainingPhase.peak  => 'Peak Phase',
    TrainingPhase.taper => 'Taper Phase',
  };

  // ── Fallback steps ────────────────────────────────────────────────────────

  List<String> _fallbackSteps(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase => [
          'Warm up with 5 min of easy walking or slow jogging.',
          'Run at a comfortable, conversational pace for 20–30 min.',
          'Cool down with 5 min easy walk and light stretching.',
        ],
      WorkoutIntent.endurance => [
          'Start easy — slower than you think you need to.',
          'Keep a conversational pace for the full duration.',
          'Finish with 5 min easy walk. Drink before you feel thirsty.',
        ],
      WorkoutIntent.threshold => [
          'Warm up 10 min easy.',
          'Run at tempo pace (comfortably hard — RPE 7–8) for 20 min.',
          'Cool down 10 min easy.',
        ],
      WorkoutIntent.vo2max => [
          'Warm up 10 min easy.',
          'Run hard (RPE 8–9) then recover easy. Repeat as prescribed.',
          'Cool down 10 min easy.',
        ],
      WorkoutIntent.speed => [
          'Warm up 10 min easy with dynamic stretches.',
          'Run fast reps with full recovery between each.',
          'Cool down 10 min easy.',
        ],
      WorkoutIntent.raceSpecific => [
          'Warm up 10 min easy.',
          'Run at your goal race pace for the prescribed distance.',
          'Cool down 10 min easy.',
        ],
      WorkoutIntent.recovery => [
          'Run at a very easy, almost walking pace for 20–30 min.',
          'Keep effort at RPE 2–3 the whole time.',
          'This is active recovery — slow is the goal.',
        ],
    };
  }
}