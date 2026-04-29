/// SessionSelector — picks today's workout template from the library.
///
/// Decision flow (post-intent-layer):
///   1. Is it a rest day? → return null
///   2. Determine day role (structural fallback only)
///   3. Use plannedIntent as PRIMARY driver, role as fallback
///   4. Apply readiness gating as EXECUTION ADJUSTMENT (not replanning)
///   5. Query library for templates WITHIN intent boundaries
///   6. Pick best template (variety + phase fit)
///   7. Return selection with debug log
///
/// Intent boundaries are STRICT:
///   aerobicBase → easy/recovery templates ONLY
///   endurance   → long run templates ONLY
///   threshold   → tempo/cruise interval templates ONLY
///   vo2max      → interval templates ONLY
///   recovery    → recovery templates ONLY
///
/// Readiness gating:
///   GREEN  → run planned intent as-is
///   YELLOW → downgrade within intent family (vo2max→threshold, etc.)
///   RED    → override to recovery (only exception to intent primacy)
library;

import '../config/workout_template_library.dart';
import 'volume_calculator.dart';
import '../../models/training_phase.dart';

// ============================================================================
// SELECTION CONTEXT
// ============================================================================

enum SelectorReadiness { green, yellow, red }

class SelectionContext {
  final RaceDistance raceDistance;
  final TrainingPhase phase;
  final SelectorReadiness readiness;
  final int daysPerWeek;
  final List<int> trainingDayIndices;
  final int todayDayIndex;
  final int daysSinceLastQuality;
  final int daysSinceLastLongRun;
  final String? lastCompletedTemplateId;
  final WorkoutIntent? lastCompletedIntent;
  final WorkoutIntent? plannedIntent;
  final int weekNumber;
  final double? avgRpe;
  final double weeklyVolumeCompletedKm;
  final double weeklyTargetKm;
  final int qualitySessionsDoneThisWeek;
  final bool longRunDoneThisWeek;
  final String experienceLevel;

   const SelectionContext({
    required this.raceDistance,
    required this.phase,
    required this.readiness,
    required this.daysPerWeek,
    required this.trainingDayIndices,
    required this.todayDayIndex,
    this.daysSinceLastQuality = 999,
    this.daysSinceLastLongRun = 999,
    this.lastCompletedTemplateId,
    this.lastCompletedIntent,
    this.plannedIntent,
    this.weekNumber = 1,
    this.avgRpe,
    this.weeklyVolumeCompletedKm = 0,
    this.weeklyTargetKm = 30,
    this.qualitySessionsDoneThisWeek = 0,
    this.longRunDoneThisWeek = false,
    this.experienceLevel = 'intermediate',
  });
}

// ============================================================================
// SELECTION RESULT
// ============================================================================

class SessionSelection {
  final WorkoutTemplate template;
  final PhaseVariant? variant;
  final DayRole dayRole;
  final WorkoutIntent intent;
  final bool wasDowngraded;
  final String reason;

  /// The planned intent that was fed in (for debug comparison).
  final WorkoutIntent? originalPlannedIntent;

  const SessionSelection({
    required this.template,
    this.variant,
    required this.dayRole,
    required this.intent,
    this.wasDowngraded = false,
    this.reason = '',
    this.originalPlannedIntent,
  });
}

// ============================================================================
// SESSION SELECTOR
// ============================================================================

class SessionSelector {
  const SessionSelector();

  SessionSelection? select(SelectionContext context) {
    // ── Step 1: Is today a training day? ──────────────────────────────────
    if (!context.trainingDayIndices.contains(context.todayDayIndex)) {
      _log('REST DAY', {
        'todayDayIndex': context.todayDayIndex,
        'trainingDays': context.trainingDayIndices,
      });
      return null;
    }

    // ── Step 2: Determine day role (structural position) ─────────────────
    final dayRole = _determineDayRole(context);

    // ── Step 3: Resolve intent — plannedIntent is PRIMARY ────────────────
    //
    // Priority chain:
    //   1. plannedIntent (from intent layer — post-workout decision)
    //   2. _roleToIntent  (structural fallback — no intent stored yet)
    //
    // When plannedIntent exists, DayRole becomes informational only.
    // The intent layer has already decided what to train.
    final intentSource = context.plannedIntent != null
        ? 'plannedIntent'
        : 'roleToIntent (fallback)';
    var intent = context.plannedIntent ?? _roleToIntent(dayRole, context);

    _log('INTENT RESOLVED', {
      'source': intentSource,
      'plannedIntent': context.plannedIntent?.name,
      'roleIntent': _roleToIntent(dayRole, context).name,
      'resolvedIntent': intent.name,
      'dayRole': dayRole.name,
      'readiness': context.readiness.name,
    });

    // ── Step 4: Apply readiness gating (EXECUTION adjustment only) ───────
    //
    // KEY PRINCIPLE: Readiness does NOT change the training direction.
    // It only adjusts intensity WITHIN the intent boundary.
    //
    // GREEN  → run as planned
    // YELLOW → downgrade intensity within the intent family:
    //          vo2max/speed/raceSpecific → threshold (lighter quality)
    //          threshold stays threshold (already manageable)
    //          aerobicBase stays aerobicBase
    //          endurance stays endurance (just run slower)
    // RED    → override to recovery (safety override — only exception)
    //
    // IMPORTANT: aerobicBase + GREEN readiness → still aerobicBase.
    //            The intent layer said "easy day" and green readiness
    //            does NOT promote it to quality. That would break the
    //            contract between what the UI previewed and what runs.
    var wasDowngraded = false;
    final originalIntent = intent;

    if (context.readiness == SelectorReadiness.red) {
      // RED = safety override. Body isn't ready for anything.
      intent = WorkoutIntent.recovery;
      wasDowngraded = true;
      _log('READINESS GATE: RED → recovery override', {
        'originalIntent': originalIntent.name,
      });
    } else if (context.readiness == SelectorReadiness.yellow) {
      // YELLOW = reduce intensity, stay in the intent family.
      if (intent == WorkoutIntent.vo2max ||
          intent == WorkoutIntent.speed ||
          intent == WorkoutIntent.raceSpecific) {
        intent = WorkoutIntent.threshold;
        wasDowngraded = true;
        _log('READINESS GATE: YELLOW → downgraded to threshold', {
          'originalIntent': originalIntent.name,
        });
      }
      // threshold, aerobicBase, endurance, recovery → no change on yellow
    }

    // ── Step 5: Query library for templates (STRICT intent boundaries) ───
    final candidates = WorkoutLibrary.forSlot(
      intent: intent,
      raceDistance: context.raceDistance,
      phase: context.phase,
    );

    _log('TEMPLATE QUERY', {
      'intent': intent.name,
      'race': context.raceDistance.name,
      'phase': context.phase.name,
      'candidateCount': candidates.length,
      'candidateIds': candidates.map((c) => c.id).toList(),
    });

    if (candidates.isEmpty) {
      // Fallback: try aerobic base (always has templates for every context).
      final fallback = WorkoutLibrary.forSlot(
        intent: WorkoutIntent.aerobicBase,
        raceDistance: context.raceDistance,
        phase: context.phase,
      );
      if (fallback.isEmpty) {
        _log('FALLBACK: absolute last resort → easy_steady', {});
        return SessionSelection(
          template: WorkoutLibrary.byId('easy_steady')!,
          dayRole: DayRole.easyRun,
          intent: WorkoutIntent.aerobicBase,
          reason: 'Fallback: no templates matched',
          originalPlannedIntent: context.plannedIntent,
        );
      }
      final template = fallback.first;
      _log('FALLBACK: no templates for $intent → aerobicBase', {
        'templateId': template.id,
      });
      return SessionSelection(
        template: template,
        variant: WorkoutLibrary.getVariant(template, context.phase),
        dayRole: dayRole,
        intent: WorkoutIntent.aerobicBase,
        reason: 'Fallback: no templates for ${intent.name}',
        originalPlannedIntent: context.plannedIntent,
      );
    }

    // ── Step 6: Pick the best template (variety + phase fit) ─────────────
    final template = _pickBestTemplate(candidates, context);
    final variant = WorkoutLibrary.getVariant(template, context.phase);

    final reason = _buildReason(dayRole, intent, context, intentSource);

    _log('SELECTION COMPLETE', {
      'templateId': template.id,
      'templateName': template.name,
      'intent': intent.name,
      'wasDowngraded': wasDowngraded,
      'originalPlannedIntent': context.plannedIntent?.name,
      'reason': reason,
    });

    return SessionSelection(
      template: template,
      variant: variant,
      dayRole: dayRole,
      intent: intent,
      wasDowngraded: wasDowngraded,
      reason: reason,
      originalPlannedIntent: context.plannedIntent,
    );
  }

  // ========================================================================
  // DAY ROLE ASSIGNMENT
  // ========================================================================

  DayRole _determineDayRole(SelectionContext context) {
    final trainingDays = List<int>.from(context.trainingDayIndices)..sort();
    final todayPosition = trainingDays.indexOf(context.todayDayIndex);

    if (todayPosition == -1) return DayRole.easyRun;

    final totalDays = trainingDays.length;
    final isLastDay = todayPosition == totalDays - 1;
    final isSecondToLast = todayPosition == totalDays - 2;

    final qualityBudget = _qualityBudgetForWeek(totalDays, context.phase, context.experienceLevel);
    final qualityDone = context.qualitySessionsDoneThisWeek;
    final qualityRemaining = (qualityBudget - qualityDone).clamp(0, 2);

    final daysRemaining = totalDays - todayPosition;

    // ── Long run: last training day, unless already done ────────────────
    if (isLastDay && !context.longRunDoneThisWeek) {
      if (context.daysSinceLastLongRun < 3 &&
          context.daysSinceLastQuality > 4 &&
          qualityRemaining > 0) {
        return DayRole.primaryQuality;
      }
      return DayRole.longRun;
    }

    if (isLastDay && context.longRunDoneThisWeek) {
      return DayRole.easyRun;
    }

    // ── Recovery day: second to last in 6+ day weeks ────────────────────
    if (totalDays >= 6 && isSecondToLast) {
      return DayRole.recovery;
    }

    // ── Quality assignment: urgency-aware ────────────────────────────────
    if (qualityRemaining > 0 && context.daysSinceLastQuality >= 2) {
      final nonLongDaysRemaining =
          daysRemaining - (context.longRunDoneThisWeek ? 0 : 1);
      final mustDoQualityNow = qualityRemaining >= nonLongDaysRemaining;

      if (mustDoQualityNow) {
        return qualityDone == 0
            ? DayRole.primaryQuality
            : DayRole.secondaryQuality;
      }

      if (todayPosition == 0) {
        return DayRole.primaryQuality;
      }
      if (totalDays >= 5 && todayPosition == 2 && qualityDone < 2) {
        return DayRole.secondaryQuality;
      }
    }

    return DayRole.easyRun;
  }

  int _qualityBudgetForWeek(int daysPerWeek, TrainingPhase phase, String experienceLevel) {
  final isBeginner = experienceLevel == 'beginner';
  return switch (phase) {
    TrainingPhase.base  => daysPerWeek >= 4 ? 1 : (isBeginner ? 0 : 1),
    TrainingPhase.taper => 1,
    TrainingPhase.build => daysPerWeek >= 5 ? 2 : 1,
    TrainingPhase.peak  => daysPerWeek >= 4 ? 2 : 1,
  };
}

  // ========================================================================
  // INTENT MAPPING (fallback only — used when no plannedIntent exists)
  // ========================================================================

  WorkoutIntent _roleToIntent(DayRole role, SelectionContext context) {
    switch (role) {
      case DayRole.longRun:
        return WorkoutIntent.endurance;

      case DayRole.primaryQuality:
        if (context.phase == TrainingPhase.base) {
          return WorkoutIntent.threshold;
        }
        // Beginners do threshold in week 1 of build before graduating to VO2
        final isBeginnerEarlyBuild = context.phase == TrainingPhase.build &&
            context.weekNumber == 1 &&
            context.experienceLevel == 'beginner';
        if (isBeginnerEarlyBuild) return WorkoutIntent.threshold;
        return switch (context.raceDistance) {
          RaceDistance.fiveK        => WorkoutIntent.vo2max,
          RaceDistance.tenK         => WorkoutIntent.vo2max,
          RaceDistance.halfMarathon => WorkoutIntent.threshold,
          RaceDistance.marathon     => WorkoutIntent.threshold,
        };

      case DayRole.secondaryQuality:
        if (context.phase == TrainingPhase.base) {
          return WorkoutIntent.speed;
        }
        return switch (context.raceDistance) {
          RaceDistance.fiveK        => WorkoutIntent.threshold,
          RaceDistance.tenK         => WorkoutIntent.threshold,
          RaceDistance.halfMarathon => WorkoutIntent.vo2max,
          RaceDistance.marathon     => WorkoutIntent.vo2max,
        };

      case DayRole.easyRun:
        return WorkoutIntent.aerobicBase;

      case DayRole.recovery:
        return WorkoutIntent.recovery;
    }
  }

  // ========================================================================
  // TEMPLATE PICKER
  // ========================================================================

  WorkoutTemplate _pickBestTemplate(
    List<WorkoutTemplate> candidates,
    SelectionContext context,
  ) {
    if (candidates.length == 1) return candidates.first;

    final nonRepeat = candidates
        .where((t) => t.id != context.lastCompletedTemplateId)
        .toList();

    final pool = nonRepeat.isNotEmpty ? nonRepeat : candidates;

    List<WorkoutTemplate> refined = pool;
    if (context.lastCompletedIntent != null && pool.length > 1) {
      final differentFromLast = pool
          .where((t) => t.id != context.lastCompletedTemplateId)
          .toList();
      if (differentFromLast.isNotEmpty) {
        refined = differentFromLast;
      }
    }

    final rotationSeed = context.todayDayIndex + (context.weekNumber * 7);
    return refined[rotationSeed % refined.length];
  }

  // ========================================================================
  // DEBUG LOGGING
  // ========================================================================

  String _buildReason(
    DayRole role,
    WorkoutIntent intent,
    SelectionContext context,
    String intentSource,
  ) {
    final dayName = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ][context.todayDayIndex];
    final phaseName = context.phase.name;
    return '$dayName · ${role.name} · ${intent.name} '
        '[$phaseName W${context.weekNumber}] '
        'via $intentSource';
  }

  /// Debug log — prints to console in debug mode.
  /// In production, this becomes a no-op or feeds into analytics.
  void _log(String tag, Map<String, dynamic> data) {
    assert(() {
      final entries = data.entries
          .map((e) => '  ${e.key}: ${e.value}')
          .join('\n');
      // ignore: avoid_print
      print('[SessionSelector] $tag\n$entries');
      return true;
    }());
  }
}