import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/engines/config/archetype_table.dart';
import 'package:run_app/models/training_phase.dart';

void main() {
  group('ArchetypeTable — 7-day weeks', () {
    // Before this was supported, build() returned null above 6 days while the
    // onboarding slider still offered 7, so WeekResolver fell back to an empty
    // session list and every day came out with a null distance.
    test('builds for every phase and experience level', () {
      for (final exp in ExperienceLevel.values) {
        for (final phase in TrainingPhase.values) {
          final week = ArchetypeTable.build(
            weeklyKm: 80,
            days: 7,
            experience: exp,
            phase: phase,
          );
          expect(week, isNotNull, reason: '7d $exp/$phase returned null');
          expect(week!.sessionCount, 7, reason: '7d $exp/$phase session count');
          expect(week.hasLongRun, isTrue, reason: '7d $exp/$phase long run');
        }
      }
    });

    test('exactly one long run, and every session has a real distance', () {
      final week = ArchetypeTable.build(
        weeklyKm: 80,
        days: 7,
        experience: ExperienceLevel.advanced,
        phase: TrainingPhase.build,
      )!;

      final longRuns = week.sessions.where((s) => s.type.isLong);
      expect(longRuns.length, 1);

      for (final s in week.sessions) {
        expect(s.effectiveKm, greaterThan(0));
      }
    });

    test('two quality sessions outside taper, one inside it', () {
      final build = ArchetypeTable.build(
        weeklyKm: 80,
        days: 7,
        experience: ExperienceLevel.advanced,
        phase: TrainingPhase.build,
      )!;
      expect(build.qualityCount, 2);

      final taper = ArchetypeTable.build(
        weeklyKm: 80,
        days: 7,
        experience: ExperienceLevel.advanced,
        phase: TrainingPhase.taper,
      )!;
      expect(taper.qualityCount, 1);
    });

    test('total volume lands near the requested weekly km', () {
      final week = ArchetypeTable.build(
        weeklyKm: 80,
        days: 7,
        experience: ExperienceLevel.intermediate,
        phase: TrainingPhase.build,
      )!;
      // The long run absorbs the remainder, so the total should track the
      // request closely; floors can only push it up.
      expect(week.totalKm, greaterThanOrEqualTo(72.0));
      expect(week.totalKm, lessThanOrEqualTo(88.0));
    });

    test('still rejects 8 days and 2 days', () {
      expect(
        ArchetypeTable.build(
          weeklyKm: 80,
          days: 8,
          experience: ExperienceLevel.advanced,
          phase: TrainingPhase.build,
        ),
        isNull,
      );
      expect(
        ArchetypeTable.build(
          weeklyKm: 80,
          days: 2,
          experience: ExperienceLevel.advanced,
          phase: TrainingPhase.build,
        ),
        isNull,
      );
    });

    test('6-day composition is unchanged by the 7-day addition', () {
      final six = ArchetypeTable.build(
        weeklyKm: 70,
        days: 6,
        experience: ExperienceLevel.advanced,
        phase: TrainingPhase.build,
      )!;
      expect(six.sessionCount, 6);
      expect(six.qualityCount, 2);
      expect(six.hasLongRun, isTrue);
    });
  });
}
