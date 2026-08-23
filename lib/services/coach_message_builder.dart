import '../engines/config/workout_template_library.dart';
import '../models/training_phase.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

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

// ── Coach context — only real signals ─────────────────────────────────────────

class CoachContext {
  final int totalRunsCompleted;
  final int daysSinceLastRun;
  final double? avgRpe;
  final bool highRpeRecently;
  final bool easyRunFeltTooHard;
  final ProgressionSignal progression;
  final bool wasDowngraded;
  final List<String> scalingAdjustments;
  final bool paceTrending;
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

  /// Retained for pre_run_briefing_screen.dart and pre_run_check.dart.
  /// The engine never sets this — it is always null at runtime.
  /// Safe to remove in a future cleanup once those screens no longer
  /// reference it.
  final String? movedFromDay;

  /// What the engine has planned for the next training session.
  /// Null when today is the last training day of the week.
  final WorkoutIntent? nextPlannedIntent;

  /// Human-readable label for the next session.
  /// e.g. "Tomorrow · Threshold Run" or "Thursday · Long Run"
  final String? nextPlannedLabel;

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
    this.nextPlannedIntent,
    this.nextPlannedLabel,
  });
}

// ── Builder ───────────────────────────────────────────────────────────────────

class CoachMessageBuilder {
  CoachMessage buildMessage({
    required CoachContext context,
    required ResolvedWorkout resolvedWorkout,
    TrainingPhase phase = TrainingPhase.base,
    int weekNumber = 1,
    WorkoutIntent? nextPlannedIntent,
    String? nextPlannedLabel,
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
      movedFromDay: null, // never set by the engine
      nextPlannedIntent: nextPlannedIntent,
      nextPlannedLabel: nextPlannedLabel,
    );
  }

  // ── Reflection — honest state of training ────────────────────────────────

  String _buildReflectionText(CoachContext ctx) {
    if (ctx.isNewUser) {
      return "First session. Max will start building a picture of your training as you log runs — the more you run, the sharper the coaching gets.";
    }

    if (ctx.hasBeenAway) {
      final days = ctx.daysSinceLastRun;
      if (days >= 14) {
        return "Two weeks away. Your body has had a genuine reset — treat today as a fresh start, not a catch-up.";
      }
      if (days >= 7) {
        return "About a week since your last run. You'll notice the rest in your legs today — use it.";
      }
      return 'A few days between sessions. You should be feeling fresher than last time.';
    }

    if (ctx.easyRunFeltTooHard) {
      return "Your easy run felt harder than it should. That's your body asking for space — today we honour that.";
    }

    if (ctx.highRpeRecently) {
      return "You've been pushing hard lately. The heavy-legs feeling is the work landing — that's a good sign.";
    }

    if (!ctx.paceInsufficientData && ctx.paceTrending) {
      return "Your pace is moving in the right direction. The base work is converting — keep trusting the process.";
    }

    if (ctx.paceInsufficientData) {
      return "Max is still reading your rhythm. A few more runs and the coaching will get a lot more specific to you.";
    }

    return "Consistent training is quietly compounding. You won't feel it day-to-day — but it's there.";
  }

  // ── Acknowledgement — why the engine picked this workout ─────────────────

  String _buildAcknowledgementText(CoachContext ctx, WorkoutIntent intent) {
    if (ctx.isNewUser) {
      return "Starting with the fundamentals — most runners go too hard too soon. Not you.";
    }

    if (ctx.hasBeenAway) {
      final days = ctx.daysSinceLastRun;
      if (days >= 14) {
        return "Easing back in properly. The goal today isn't fitness — it's re-establishing the habit.";
      }
      if (days >= 7) {
        return "Max has dialled today back to bring you in gently — no need to make up for lost time.";
      }
      return "Picking up right where you left off — the gap wasn't long enough to lose anything.";
    }

    if (ctx.wasDowngraded) {
      return ctx.bodyFeelsTough
          ? "Keeping today lighter — your body has been working hard and deserves space to recover."
          : "Scaling back slightly today — fitness doesn't improve during hard sessions, it improves after them.";
    }

    return switch (ctx.progression) {
      ProgressionSignal.progressing => _progressOpener(intent),
      ProgressionSignal.holding => _holdOpener(intent),
      ProgressionSignal.steppingBack =>
        "Pulling back intentionally today — a lighter session now means a much stronger one next time.",
    };
  }

  String _progressOpener(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.endurance =>
        "You've earned a longer run. Max is adding a little more distance today.",
      WorkoutIntent.threshold =>
        "Your aerobic base is holding up well — time to ask a bit more from your threshold work.",
      WorkoutIntent.vo2max =>
        "Intervals have been landing well. One more rep in the set today — you're ready for it.",
      _ => "The trend is positive — Max is nudging the load forward.",
    };
  }

  String _holdOpener(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase =>
        "Another easy day. Easy running is the engine of improvement — not just filler between hard sessions.",
      _ =>
        "Holding the load steady. Fitness is built in the rest between sessions as much as the sessions themselves.",
    };
  }

  // ── Goal text ─────────────────────────────────────────────────────────────

  String _buildGoalText(WorkoutIntent intent, TrainingPhase phase) {
    return switch (intent) {
      WorkoutIntent.aerobicBase =>
        phase == TrainingPhase.base
            ? "Easy runs don't feel like much — but they're quietly expanding your aerobic engine. Every kilometre at this effort counts."
            : "This easy run sits between your harder sessions. It keeps the legs moving without taking anything away from the next quality day.",
      WorkoutIntent.endurance =>
        "The long run teaches your body to burn fat as fuel and builds the durability that races actually demand. It's the most important run of your week.",
      WorkoutIntent.threshold =>
        "Threshold work makes your race pace feel more manageable. You're training your body to clear lactate faster — so harder feels easier over time.",
      WorkoutIntent.vo2max =>
        "These intervals develop your ceiling — the highest intensity your aerobic system can support. Short, deliberate, and hard.",
      WorkoutIntent.speed =>
        "Short fast efforts improve your form and leg turnover. You're training your legs to move quickly — not just far.",
      WorkoutIntent.raceSpecific =>
        "Race pace runs build the confidence that comes from knowing exactly what the pace feels like. Rehearsal, not a test.",
    };
  }

  // ── Feel text ─────────────────────────────────────────────────────────────

  String _buildFeelText(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase =>
        "Genuinely conversational. If someone spoke to you, you should answer in full sentences without effort. If you can't — you're running too fast.",
      WorkoutIntent.endurance =>
        "Start slower than feels necessary. The pace that feels almost too easy at km 1 should feel right at km 15. If it gets hard before halfway, you went out too fast.",
      WorkoutIntent.threshold =>
        "Comfortably hard — you can push out a word or two, but not a full sentence. Controlled and deliberate. Discomfort is expected; panic is not.",
      WorkoutIntent.vo2max =>
        "Push hard enough on each rep that you genuinely need the recovery. Then actually use it — don't cheat the rest between efforts.",
      WorkoutIntent.speed =>
        "Light and snappy, not a sprint. Fast enough to feel your legs turn over quickly, with full recovery between reps so each one feels fresh.",
      WorkoutIntent.raceSpecific =>
        "This should feel like a pace you could hold for the full race — controlled and rhythmic. Not comfortable, but not desperate either.",
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

    if (block.reps != null && block.reps! > 1) {
      if (block.recoverySeconds != null) {
        final m = block.recoverySeconds! ~/ 60;
        final s = block.recoverySeconds! % 60;
        final label = m > 0
            ? '$m:${s.toString().padLeft(2, '0')} recovery'
            : '${block.recoverySeconds}s recovery';
        buf.write(' ($label)');
      } else if (block.recoveryMeters != null) {
        buf.write(' (${_fmtMeters(block.recoveryMeters!)} jog recovery)');
      }
    }

    return buf.toString();
  }

  String _blockTypeLabel(BlockType type) => switch (type) {
    BlockType.warmup => 'Warmup',
    BlockType.main => 'Run',
    BlockType.recovery => 'Recovery',
    BlockType.cooldown => 'Cooldown',
  };

  String _phaseDisplayName(TrainingPhase phase) => switch (phase) {
    TrainingPhase.base => 'Base Phase',
    TrainingPhase.build => 'Build Phase',
    TrainingPhase.peak => 'Peak Phase',
    TrainingPhase.taper => 'Taper Phase',
    TrainingPhase.maintenance => 'Maintenance',
  };

  // ── Fallback steps ────────────────────────────────────────────────────────

  List<String> _fallbackSteps(WorkoutIntent intent) {
    return switch (intent) {
      WorkoutIntent.aerobicBase => [
        'Start with 5 minutes of easy walking or very slow jogging to warm up.',
        'Run easy for 20–30 minutes. Conversational pace — no effort, no heroics.',
        'Finish with 5 minutes of walking and some light stretching.',
      ],
      WorkoutIntent.endurance => [
        'Start slower than feels necessary — your body needs time to warm into a long effort.',
        'Hold a conversational pace throughout. If it gets hard before halfway, you went out too fast.',
        'Walk for 5 minutes to cool down. Drink before you feel thirsty, not after.',
      ],
      WorkoutIntent.threshold => [
        'Ease in for 10 minutes — this run earns its hardness only if you arrive at the tempo section fresh.',
        'Run at tempo pace for 20 minutes — comfortably hard, words but not sentences.',
        "Cool down with 10 easy minutes. Don't skip this — clearing lactate is part of the session.",
      ],
      WorkoutIntent.vo2max => [
        'Warm up for 10 minutes — you need to arrive at intervals ready, not already tired.',
        'Run each rep hard. Recover fully between efforts — the next rep should feel like a fresh start.',
        'Cool down 10 minutes easy. Resist the urge to skip it after a hard set.',
      ],
      WorkoutIntent.speed => [
        'Warm up 10 minutes easy, then some leg swings and dynamic stretches before the reps begin.',
        'Run each rep feeling light and quick — snappy, not sprinting. Full recovery between every rep.',
        'Cool down 10 minutes easy.',
      ],
      WorkoutIntent.raceSpecific => [
        'Warm up for 10 minutes easy — get the blood moving before asking for race pace.',
        'Hold race pace. Controlled and rhythmic — the feeling you want on race day.',
        'Cool down 10 minutes easy.',
      ],
    };
  }

  // ── Post-run message — Max reacts to what you just did ───────────────────

  String _pick(List<String> variants, int runCount) =>
      variants[runCount % variants.length];

  String buildPostRunMessage({
    required WorkoutIntent intent,
    required int rpe,
    required double distanceKm,
    int totalRunsCompleted = 0,
    bool? isOnTargetPace,
    bool ranTooFast = false,
    TrainingPhase phase = TrainingPhase.base,
    int weekNumber = 1,
    bool isLongestRun = false,
    int runsThisWeek = 1,
    int? daysUntilRace,
    bool isCutbackWeek = false,
  }) {
    // ── Milestone messages ──────────────────────────────────────────────────
    if (totalRunsCompleted == 1) {
      return "First one's in the bank. Max has what he needs — come back for the next session and watch the plan take shape.";
    }
    if (totalRunsCompleted == 5) {
      return "Five sessions done. You're past the point where most people quit. The habit is forming — protect it.";
    }
    if (totalRunsCompleted == 10) {
      return "Ten runs with Max. That's not motivation — that's discipline. The compound interest on this starts now.";
    }
    if (totalRunsCompleted == 25) {
      return "Twenty-five sessions. The consistency you've built here is worth more than any single workout in your plan.";
    }
    if (totalRunsCompleted == 50) {
      return "Fifty runs. You've built something real — and the data Max has collected on you backs that up completely.";
    }

    // ── Layer 3: Comparative signals ────────────────────────────────────────
    if (daysUntilRace != null && daysUntilRace <= 7) {
      return _pick([
        "Race week. Today was about staying sharp — not building fitness, just keeping the legs ticking. You're ready.",
        "${daysUntilRace == 0 ? 'Race day tomorrow' : '$daysUntilRace days out'}. The fitness is built. This run was maintenance — trust what you've already put in.",
        "Final stretch. Everything you needed to build is already in the bank — these last runs are just staying loose.",
      ], totalRunsCompleted);
    }

    if (daysUntilRace != null && daysUntilRace <= 21) {
      return _pick([
        "Less than three weeks out. Every session now is putting the finishing touches on your preparation.",
        "$daysUntilRace days to race day — you're in the window where every run matters. Today was part of that.",
        "Three weeks to go. The heavy lifting is behind you — now it's about arriving sharp and confident.",
      ], totalRunsCompleted);
    }

    if (isLongestRun && intent == WorkoutIntent.endurance) {
      final km = distanceKm.toStringAsFixed(1);
      return _pick([
        "Longest run you've ever done — $km km. That's not a small thing. Your body just found a new ceiling.",
        "$km km and a personal distance record. Whatever pace you ran it at, that distance is yours now.",
        "New longest run: $km km. Every long run from here builds on this one — that's a real foundation.",
      ], totalRunsCompleted);
    }

    if (isCutbackWeek) {
      return _pick([
        "Cutback week. Less volume isn't a setback — it's how you absorb the last three weeks and come back stronger.",
        "Reduced load this week is deliberate. The body adapts during recovery, not during effort — this is where the gains land.",
        "Cutback week done. Rest is part of the plan, not a break from it — you're exactly where you should be.",
      ], totalRunsCompleted);
    }

    // ── Layer 2: Phase awareness ────────────────────────────────────────────
    if (phase == TrainingPhase.taper) {
      return _pick([
        "Taper is working. Less volume, sharper legs — you're arriving at race day ready, not empty.",
        "Taper run done. The training is complete — trust what you've built. The rest now is just staying loose.",
        "Less is more right now. Your body is converting the last few weeks of work into race-ready fitness.",
      ], totalRunsCompleted);
    }

    if (phase == TrainingPhase.peak && rpe >= 7) {
      return _pick([
        "Peak week. These are the hardest sessions in your plan — you're almost through them. Hold the line.",
        "Peak training. You're doing the work most runners avoid — that's exactly why race day will go differently for you.",
        "Highest-load week of the plan. What you just did is the hardest part — hold on a little longer.",
      ], totalRunsCompleted);
    }

    // ── Layer 1: Base message pools (3 variants, rotated by run count) ──────
    return switch (intent) {
      WorkoutIntent.aerobicBase => _postRunEasy(rpe, totalRunsCompleted),
      WorkoutIntent.endurance => _postRunLong(
        rpe,
        distanceKm,
        totalRunsCompleted,
      ),
      WorkoutIntent.threshold => _postRunThreshold(rpe, totalRunsCompleted),
      WorkoutIntent.vo2max => _postRunIntervals(rpe, totalRunsCompleted),
      WorkoutIntent.speed => _postRunSpeed(rpe, totalRunsCompleted),
      WorkoutIntent.raceSpecific => _postRunRaceSpecific(
        rpe,
        isOnTargetPace,
        ranTooFast,
        totalRunsCompleted,
      ),
    };
  }

  String _postRunEasy(int rpe, int runs) {
    if (rpe <= 4) {
      return _pick([
        "That's what an easy run is supposed to feel like. The discipline to keep it easy is what makes the hard days possible.",
        "Paced well. Easy running is the engine under everything else — you're building it right.",
        "Kept it genuinely easy. That sounds simple, but most runners can't do it. You just did.",
      ], runs);
    }
    if (rpe <= 6) {
      return _pick([
        "A little more effort than needed today. On your next easy run, back off a touch — easier than you think is the right zone.",
        "Slightly harder than ideal for an easy day. You got the run in, which matters — just leave a bit more in reserve next time.",
        "A notch above easy today. The goal isn't just the distance — it's arriving at the next hard session fresh.",
      ], runs);
    }
    return _pick([
      "That easy run didn't feel easy. Max has noted the effort — if this keeps happening, the next session will reflect what your body is telling you.",
      "Harder than an easy run should be. Worth paying attention to — are you sleeping well? Eating enough between sessions?",
      "Your easy pace felt hard today. Could be fatigue, heat, or just a rough day. Max will adjust if the pattern continues.",
    ], runs);
  }

  String _postRunLong(int rpe, double distanceKm, int runs) {
    final km = distanceKm.toStringAsFixed(1);
    if (rpe <= 5) {
      return _pick([
        "$km km done — and paced beautifully. You saved something for the end, which means you went out at exactly the right speed.",
        "That's how a long run is supposed to go. $km km at a controlled effort — the pace discipline will pay off for weeks.",
        "$km km, still feeling strong at the finish. The conservative start paid off — that's the long game.",
      ], runs);
    }
    if (rpe <= 7) {
      return _pick([
        "$km km banked. Long runs don't have to feel perfect — they have to get done. You did that.",
        "Long run complete. The fatigue right now is adaptation happening — rest well and let today's work actually land.",
        "$km km. Each long run extends the ceiling on what your body can handle — today raised yours a little.",
      ], runs);
    }
    return _pick([
      "Tough long run. You ground through it — that's the kind of resilience that transfers directly to races.",
      "Hard long run. You finished when it wasn't easy — that's worth more than a comfortable run on a good day.",
      "That cost you something today. Rest well — the session will do its job while you recover.",
    ], runs);
  }

  String _postRunThreshold(int rpe, int runs) {
    if (rpe <= 6) {
      return _pick([
        "You had more in you today. Threshold needs to sit in the uncomfortable zone to do its job — push a little deeper next time.",
        "Felt manageable, which means you weren't quite in the zone. The target is 'comfortably hard' — edge toward the hard end next session.",
        "Solid effort, but room to push. Threshold only works when it sits right at the edge of what's sustainable.",
      ], runs);
    }
    if (rpe <= 8) {
      return _pick([
        "Right in the threshold zone — uncomfortable, controlled, exactly where it needs to be.",
        "Threshold work executed well. You stayed in the zone — that's what gradually lifts your race pace over time.",
        "That's the feeling. Controlled suffering — the kind that converts directly into speed.",
      ], runs);
    }
    return _pick([
      "You went past threshold today. The intensity was there — next time Max will hold the pace back to keep you in the right zone.",
      "That was harder than threshold needs to be. The zone is narrow — you pushed past it, but the work still counts.",
      "Maxed out on effort there. Threshold delivers at 7-8 RPE — more doesn't help, it just costs you the next session.",
    ], runs);
  }

  String _postRunIntervals(int rpe, int runs) {
    if (rpe <= 6) {
      return _pick([
        "Intervals felt manageable — which means there was more there. Max will nudge the intensity up next interval session.",
        "The reps felt controlled today. Push closer to your limit next time — the zone needs to be genuinely hard to get the adaptation.",
        "You had gas left at the end. Interval sessions should leave you with very little — next time, commit harder on each rep.",
      ], runs);
    }
    if (rpe <= 9) {
      return _pick([
        "Hard intervals done right. These sessions build your ceiling — you showed up for one of the most demanding in your plan.",
        "You went to the well on those reps. The gains from today won't show up tomorrow — but they're coming.",
        "Interval work banked. The discomfort you felt is your body being asked to do something it couldn't do before.",
      ], runs);
    }
    return _pick([
      "All-out effort. Recovery is the session now — protect the next easy run and let today's work actually land.",
      "You gave everything. Earn the rest that follows — easy days after a session like this aren't optional.",
      "Emptied the tank. The next 48 hours are where this session does its real work — rest like it matters.",
    ], runs);
  }

  String _postRunSpeed(int rpe, int runs) {
    if (rpe <= 5) {
      return _pick([
        "Speed reps felt light — next time, commit harder on the fast parts to push the adaptations further.",
        "The reps felt controlled. That's fine, but speed work needs to feel fast — push closer to your limit next session.",
        "Light and easy today. Speed work teaches your legs to move quickly — that means flirting with your limit on each rep.",
      ], runs);
    }
    return _pick([
      "Speed work banked. The gains from these sessions show up in your race pace months from now — they're building.",
      "Quick reps done. Speed work teaches your legs a gear they didn't know they had — it takes time, but it arrives.",
      "That's the effort speed sessions need. Your legs remember what fast feels like — and they'll want to do it again.",
    ], runs);
  }

  String _postRunRaceSpecific(
    int rpe,
    bool? isOnTargetPace,
    bool ranTooFast,
    int runs,
  ) {
    if (isOnTargetPace == true) {
      return _pick([
        "Race pace locked in. You know exactly what it feels like now — hold onto that feeling for race day.",
        "Hit the pace. That mental picture of controlled race effort is what you'll draw on when it gets hard in the race.",
        "Right on pace. You've made race pace feel familiar, not scary — that's a real psychological advantage.",
      ], runs);
    }
    if (ranTooFast) {
      return _pick([
        "You went out a bit hot today. In a race, that costs you late — make sure the next race-pace session starts at the target, not feel.",
        "Faster than target today. The goal is to make race pace feel controlled, not to race it — back off to the numbers next time.",
        "Over pace today. Race-specific work is about precision — practicing the exact effort, not a harder version of it.",
      ], runs);
    }
    if (rpe <= 6) {
      return _pick([
        "Race pace felt controlled today — hold onto that feeling. That's exactly what you want to replicate on race day.",
        "Comfortable at race pace, which is exactly where you want to be in preparation. The confidence is building.",
        "Race pace settling in. Each session at this effort makes it feel more natural — you're building the muscle memory.",
      ], runs);
    }
    return _pick([
      "Race pace felt hard today. That's okay — it'll feel more natural the more you run at it. These sessions are practice, not tests.",
      "Rough race-pace session. Some days the pace feels foreign — what matters is you showed up and did the work.",
      "Race pace wasn't there today. Don't read too much into one session — the pattern over several runs is what actually matters.",
    ], runs);
  }

  //HELPER FUNCTIONS
  String _fmtMeters(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()}m';
  }
}
