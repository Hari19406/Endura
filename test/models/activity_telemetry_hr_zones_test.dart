import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/services/athlete_physiology.dart';
import 'package:run_app/utils/database_service.dart';

RunRecord _run(List<Map<String, dynamic>> samples) => RunRecord(
  date: DateTime(2026, 9, 20, 7),
  distanceKm: 1.0,
  averagePace: '5:00',
  durationSeconds: 300,
  routePolyline: '',
  workoutType: 'easy',
  trackSamples: samples,
);

Map<String, dynamic> _s(num t, num d, int? hr) => {'t': t, 'd': d, 'hr': hr};

void main() {
  final samples = [
    _s(0, 0, 150),
    _s(15, 50, 150),
    _s(30, 100, 170),
    _s(45, 150, 170),
  ];

  test('TelemetrySample.timeSeconds is parsed from the sample t field', () {
    final a = ActivityDetail.fromRunRecord(_run(samples), runnerName: 'x');
    expect(a.telemetrySeries.map((s) => s.timeSeconds), [0, 15, 30, 45]);
  });

  test('a sample with no t keeps timeSeconds null', () {
    final a = ActivityDetail.fromRunRecord(
      _run([
        {'d': 0, 'hr': 150},
      ]),
      runnerName: 'x',
    );
    expect(a.telemetrySeries.single.timeSeconds, isNull);
  });

  test('zones use the supplied max HR and are time-weighted', () {
    final a = ActivityDetail.fromRunRecord(
      _run(samples),
      runnerName: 'x',
      maxHr: const MaxHrResolution(200, MaxHrSource.userSet),
    );
    expect(a.hrZones, hasLength(5));
    expect(a.hrZones[2].durationSeconds, 30); // 150 bpm: Z3 at max 200
    expect(a.hrZones[3].durationSeconds, 30); // 170 bpm: Z4
    expect(a.hrZones[2].bpmLow, 140);
    expect(a.maxHr, const MaxHrResolution(200, MaxHrSource.userSet));
    expect(a.hasHrData, isTrue);
  });

  test('the same max HR gives the same zone bounds regardless of run peak', () {
    final hard = [...samples, _s(60, 200, 192)];
    const maxHr = MaxHrResolution(190, MaxHrSource.userSet);
    final a = ActivityDetail.fromRunRecord(
      _run(samples),
      runnerName: 'x',
      maxHr: maxHr,
    );
    final b = ActivityDetail.fromRunRecord(
      _run(hard),
      runnerName: 'x',
      maxHr: maxHr,
    );
    expect(
      a.hrZones.map((z) => [z.bpmLow, z.bpmHigh]).toList(),
      b.hrZones.map((z) => [z.bpmLow, z.bpmHigh]).toList(),
    );
  });

  test('defaults to the 190 fallback when no max HR is passed', () {
    final a = ActivityDetail.fromRunRecord(_run(samples), runnerName: 'x');
    expect(a.maxHr, MaxHrResolution.fallback);
    expect(a.maxHr!.caption, 'Max HR: 190 bpm · Default');
  });

  test('no HR samples: no zones and no max-HR caption', () {
    final a = ActivityDetail.fromRunRecord(
      _run([_s(0, 0, null), _s(15, 50, null)]),
      runnerName: 'x',
    );
    expect(a.hrZones, isEmpty);
    expect(a.maxHr, isNull);
    expect(a.hasHrData, isFalse);
  });
}
