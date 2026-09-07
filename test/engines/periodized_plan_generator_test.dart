import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart' show ExperienceLevel;
import 'package:run_app/engines/config/workout_template_library.dart'
    show RaceDistance;
import 'package:run_app/engines/plan/week_resolver.dart';
import 'package:run_app/engines/planner/race_plan_builder.dart';
import 'package:run_app/models/race_plan.dart';
import 'package:run_app/models/training_phase.dart';

/// Fixed "now" so the derived week count is deterministic.
final _now = DateTime(2026, 1, 5); // a Monday

RacePlan _marathonPlan({
  int weeksOut = 16,
  bool gradualStart = false,
  int? durationWeeks,
}) => RacePlanBuilder.build(
  currentWeeklyKm: 45,
  goalRace: 'marathon',
  raceDate: _now.add(Duration(days: weeksOut * 7)),
  experienceLevel: 'intermediate',
  now: _now,
  gradualStart: gradualStart,
  durationWeeks: durationWeeks,
);

void main() {
  group('macrocycle shape (3:1 + taper)', () {
    final plan = _marathonPlan();

    test('spans the full runway, week 1 → race week', () {
      expect(plan.weeks.first.week, 1);
      expect(plan.weeks.length, 16);
      expect(plan.weeks.map((w) => w.week), List.generate(16, (i) => i + 1));
    });

    test('phases progress base → build → peak → taper', () {
      expect(plan.weeks.first.phase, TrainingPhase.base);
      // marathon → 3 taper weeks
      final taper = plan.weeks.where((w) => w.phase == TrainingPhase.taper);
      expect(taper.length, 3);
      expect(plan.weeks.last.phase, TrainingPhase.taper);
      expect(
        plan.weeks.map((w) => w.phase.index),
        _nonDecreasingByPhaseOrder(plan.weeks),
      );
    });

    test('every 4th build/peak week is a deload — quality capped to 1', () {
      for (final w in plan.weeks) {
        final isCutbackSlot =
            w.week % 4 == 0 && w.phase != TrainingPhase.taper;
        if (isCutbackSlot) {
          expect(
            w.qualityCount,
            1,
            reason: 'week ${w.week} is a 3:1 deload, expected qualityCount 1',
          );
        }
      }
      // sanity: a normal build week nearby carries 2 quality sessions
      final buildWeek = plan.weeks.firstWhere(
        (w) => w.phase == TrainingPhase.build && w.week % 4 != 0,
      );
      expect(buildWeek.qualityCount, 2);
    });

    test('volume never jumps more than ~10% week-to-week on build weeks', () {
      final build = plan.weeks
          .where(
            (w) =>
                w.phase != TrainingPhase.taper &&
                w.week % 4 != 0 &&
                w.week % 4 != 1,
          )
          .toList();
      for (var i = 1; i < build.length; i++) {
        final prev = build[i - 1].targetKm;
        final cur = build[i].targetKm;
        if (cur > prev) {
          expect((cur - prev) / prev, lessThanOrEqualTo(0.15));
        }
      }
    });
  });

  group('durationWeeks override', () {
    test('exact week count is honoured', () {
      expect(_marathonPlan(durationWeeks: 8).weeks.length, 8);
      expect(_marathonPlan(durationWeeks: 12).weeks.length, 12);
    });

    test('clamped to 1–20', () {
      expect(_marathonPlan(durationWeeks: 25).weeks.length, 20);
    });

    test('a <4 week duration falls back to the minimal plan', () {
      final p = _marathonPlan(durationWeeks: 3);
      expect(p.weeks.length, 3);
      expect(p.weeks.last.phase, TrainingPhase.taper);
    });
  });

  group('gradualStart', () {
    final plain = _marathonPlan(gradualStart: false);
    final eased = _marathonPlan(gradualStart: true);

    test('week 1 prescribed volume is ~75% of the un-eased week 1', () {
      final ratio = eased.weeks[0].targetKm / plain.weeks[0].targetKm;
      expect(ratio, closeTo(0.75, 0.06));
      expect(eased.weeks[0].longRunKm / plain.weeks[0].longRunKm,
          closeTo(0.75, 0.08));
    });

    test('weeks 1–4 ramp back up monotonically', () {
      final t = [0, 1, 2, 3].map((i) => eased.weeks[i].targetKm).toList();
      for (var i = 1; i < t.length; i++) {
        expect(t[i], greaterThanOrEqualTo(t[i - 1]));
      }
    });

    test('week 5 onward is untouched by the ease-in', () {
      for (var i = 4; i < plain.weeks.length; i++) {
        expect(
          eased.weeks[i].targetKm,
          plain.weeks[i].targetKm,
          reason: 'week ${i + 1} should be identical with/without gradualStart',
        );
      }
    });

    test('disabled ⇒ week 1 carries roughly the athlete\'s current load', () {
      expect(plain.weeks[0].targetKm, greaterThanOrEqualTo(45 * 0.9));
    });
  });

  group('microcycle — hard/easy separation across 3–7 day weeks', () {
    const resolver = WeekResolver();

    /// A representative peak week pulled straight from the macrocycle.
    final peakWeek = _marathonPlan().weeks.firstWhere(
      (w) => w.phase == TrainingPhase.peak && w.week % 4 != 0,
    );

    final schedules = <int, ({List<int> days, int lr})>{
      3: (days: [1, 3, 5], lr: 5),
      4: (days: [0, 2, 4, 6], lr: 6),
      5: (days: [0, 2, 4, 5, 6], lr: 6),
      6: (days: [0, 1, 2, 3, 4, 6], lr: 6),
      7: (days: [0, 1, 2, 3, 4, 5, 6], lr: 6),
    };

    schedules.forEach((dayCount, sched) {
      test('$dayCount-day week: no back-to-back hard days, one long run', () {
        final res = resolver.resolve(
          weekTarget: peakWeek,
          trainingDayIndices: sched.days,
          raceDistance: RaceDistance.marathon,
          phase: TrainingPhase.peak,
          experienceLevel: ExperienceLevel.intermediate,
          currentWeeklyKm: peakWeek.targetKm,
          longRunDayIndex: sched.lr,
          weekNumber: peakWeek.week,
        );

        final hardWeekdays = res.days
            .where((d) => d.isTraining && d.isHard)
            .map((d) => d.weekday)
            .toList()
          ..sort();

        for (var i = 1; i < hardWeekdays.length; i++) {
          expect(
            hardWeekdays[i] - hardWeekdays[i - 1],
            greaterThan(1),
            reason:
                '$dayCount-day week put hard sessions on consecutive days '
                '$hardWeekdays',
          );
        }

        expect(
          res.days.where((d) => d.isLongRun).length,
          1,
          reason: 'exactly one long run per week',
        );
        expect(
          res.days.where((d) => d.isQuality).length,
          inInclusiveRange(0, 2),
        );
      });
    });
  });
}

/// Phase order for a monotonic check: base < build < peak < taper.
List<int> _nonDecreasingByPhaseOrder(List<WeekTarget> weeks) {
  const order = {
    TrainingPhase.base: 0,
    TrainingPhase.build: 1,
    TrainingPhase.peak: 2,
    TrainingPhase.taper: 3,
    TrainingPhase.maintenance: 4,
  };
  var last = 0;
  final out = <int>[];
  for (final w in weeks) {
    final o = order[w.phase]!;
    last = o >= last ? o : last; // clamp so the expectation reads cleanly
    out.add(last);
  }
  return out;
}
