/// Weather vs performance maths: band edges, weighted pace, HR handling,
/// minimum sample sizes, heat impact and condition grouping.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/services/weather_service.dart';
import 'package:run_app/utils/weather_analytics.dart';

WeatherRun _run(
  double temp, {
  int humidity = 50,
  WeatherCondition condition = WeatherCondition.clear,
  double km = 10,
  int secs = 3300, // 330 s/km
  int? hr,
}) => WeatherRun(
  tempC: temp,
  humidityPercent: humidity,
  condition: condition,
  distanceKm: km,
  movingTimeSeconds: secs,
  avgHr: hr,
);

List<WeatherRun> _many(
  int n,
  double temp, {
  int secs = 3300,
  int humidity = 50,
  int? hr,
  WeatherCondition condition = WeatherCondition.clear,
}) => [
  for (var i = 0; i < n; i++)
    _run(temp, secs: secs, humidity: humidity, hr: hr, condition: condition),
];

WeatherBandStat _band(WeatherReport r, TempBand b) =>
    r.temperature.firstWhere((s) => s.key == b.name);

void main() {
  group('temperature bucketing', () {
    test('lower bound inclusive, upper bound exclusive', () {
      expect(TempBand.of(-5), TempBand.under15);
      expect(TempBand.of(14.99), TempBand.under15);
      expect(TempBand.of(15), TempBand.from15);
      expect(TempBand.of(19.99), TempBand.from15);
      expect(TempBand.of(20), TempBand.from20);
      expect(TempBand.of(24.99), TempBand.from20);
      expect(TempBand.of(25), TempBand.from25);
      expect(TempBand.of(29.99), TempBand.from25);
      expect(TempBand.of(30), TempBand.from30);
      expect(TempBand.of(41), TempBand.from30);
    });

    test('every band is reported, in order, even when empty', () {
      final r = WeatherAnalytics.analyze([_run(22)]);
      expect(r.temperature.map((s) => s.label), [
        '<15°',
        '15–20°',
        '20–25°',
        '25–30°',
        '30°+',
      ]);
      expect(_band(r, TempBand.from20).runCount, 1);
      expect(_band(r, TempBand.from30).runCount, 0);
      expect(_band(r, TempBand.from30).paceSecondsPerKm, isNull);
    });

    test('runs land in the right band', () {
      final r = WeatherAnalytics.analyze([
        _run(10),
        _run(15),
        _run(19.9),
        _run(20),
        _run(31),
      ]);
      expect([for (final s in r.temperature) s.runCount], [1, 2, 1, 0, 1]);
    });
  });

  group('humidity bucketing', () {
    test('band edges', () {
      expect(HumidityBand.of(0), HumidityBand.dry);
      expect(HumidityBand.of(39), HumidityBand.dry);
      expect(HumidityBand.of(40), HumidityBand.moderate);
      expect(HumidityBand.of(59), HumidityBand.moderate);
      expect(HumidityBand.of(60), HumidityBand.humid);
      expect(HumidityBand.of(79), HumidityBand.humid);
      expect(HumidityBand.of(80), HumidityBand.veryHumid);
      expect(HumidityBand.of(100), HumidityBand.veryHumid);
    });

    test('runs are grouped by humidity', () {
      final r = WeatherAnalytics.analyze([
        _run(20, humidity: 30),
        _run(20, humidity: 55),
        _run(20, humidity: 55),
        _run(20, humidity: 90),
      ]);
      expect([for (final s in r.humidity) s.runCount], [1, 2, 0, 1]);
      expect(r.humidity.map((s) => s.label), [
        '<40%',
        '40–60%',
        '60–80%',
        '80%+',
      ]);
    });
  });

  group('pace aggregation', () {
    test('is total moving time / total distance, not a mean of paces', () {
      final r = WeatherAnalytics.analyze([
        _run(22, km: 5, secs: 1500), // 300 s/km
        _run(22, km: 10, secs: 3300), // 330 s/km
      ]);
      expect(_band(r, TempBand.from20).paceSecondsPerKm, closeTo(320, 1e-9));
    });

    test('the same maths applies per humidity band and per condition', () {
      final r = WeatherAnalytics.analyze([
        _run(
          22,
          humidity: 85,
          km: 5,
          secs: 1500,
          condition: WeatherCondition.rain,
        ),
        _run(
          22,
          humidity: 85,
          km: 10,
          secs: 3300,
          condition: WeatherCondition.rain,
        ),
      ]);
      expect(
        r.humidity.firstWhere((s) => s.key == 'veryHumid').paceSecondsPerKm,
        closeTo(320, 1e-9),
      );
      expect(r.conditions.single.paceSecondsPerKm, closeTo(320, 1e-9));
    });

    test('distance and moving time are totalled per band', () {
      final r = WeatherAnalytics.analyze([
        _run(22, km: 5, secs: 1500),
        _run(22, km: 10, secs: 3300),
      ]);
      final s = _band(r, TempBand.from20);
      expect(s.distanceKm, 15);
      expect(s.movingSeconds, 4800);
    });
  });

  group('missing or unusable data', () {
    test('no runs, no report', () {
      final r = WeatherAnalytics.analyze(const []);
      expect(r.runCount, 0);
      expect(r.temperature, isEmpty);
      expect(r.heatImpact, isNull);
    });

    test('runs with no distance or time are not performance samples', () {
      final r = WeatherAnalytics.analyze([
        _run(22, km: 0),
        _run(22, secs: 0),
        _run(22),
      ]);
      expect(r.runCount, 1);
    });

    test('implausible temperature or humidity is excluded, not clamped', () {
      final r = WeatherAnalytics.analyze([
        _run(double.nan),
        _run(120),
        _run(-90),
        _run(22, humidity: 140),
        _run(22, humidity: -3),
        _run(22),
      ]);
      expect(r.runCount, 1);
    });
  });

  group('HR aggregation', () {
    test('is time-weighted over runs with valid HR only', () {
      final r = WeatherAnalytics.analyze([
        _run(22, secs: 3600, hr: 150),
        _run(22, secs: 1800, hr: 168),
        _run(22, secs: 9000), // no HR: must not drag the average down
      ]);
      final s = _band(r, TempBand.from20);
      expect(s.runCount, 3);
      expect(s.hrRuns, 2);
      expect(s.avgHr, closeTo((150 * 3600 + 168 * 1800) / 5400, 1e-9));
    });

    test('missing and out-of-range HR is never treated as zero', () {
      final r = WeatherAnalytics.analyze([
        _run(22, hr: 0),
        _run(22, hr: 25),
        _run(22, hr: 250),
        _run(22),
      ]);
      final s = _band(r, TempBand.from20);
      expect(s.hrRuns, 0);
      expect(s.avgHr, isNull);
    });

    test('a band with no HR has none, while another band keeps its own', () {
      final r = WeatherAnalytics.analyze([
        ..._many(3, 22, hr: 150),
        ..._many(3, 32),
      ]);
      expect(_band(r, TempBand.from20).avgHr, 150);
      expect(_band(r, TempBand.from30).avgHr, isNull);
      expect(_band(r, TempBand.from30).runCount, 3);
    });

    test('HR sample size is judged on runs with HR, not all runs', () {
      final r = WeatherAnalytics.analyze([
        ..._many(2, 22, hr: 150),
        ..._many(4, 22),
      ]);
      final s = _band(r, TempBand.from20);
      expect(s.hasEnoughRuns, isTrue);
      expect(s.hasEnoughHr, isFalse);
    });
  });

  group('minimum sample sizes', () {
    test('a band needs ${WeatherAnalytics.minBandRuns} runs', () {
      final r = WeatherAnalytics.analyze([..._many(2, 12), ..._many(3, 22)]);
      expect(_band(r, TempBand.under15).hasEnoughRuns, isFalse);
      expect(_band(r, TempBand.from20).hasEnoughRuns, isTrue);
    });

    test('a chart needs at least two comparable bands', () {
      final one = WeatherAnalytics.analyze([..._many(5, 22), ..._many(2, 32)]);
      expect(WeatherAnalytics.comparable(one.temperature), isEmpty);

      final two = WeatherAnalytics.analyze([..._many(3, 12), ..._many(3, 22)]);
      expect(WeatherAnalytics.comparable(two.temperature).map((s) => s.key), [
        'under15',
        'from20',
      ]);
    });

    test('under-sampled bands are left out of a comparable set', () {
      final r = WeatherAnalytics.analyze([
        ..._many(3, 12),
        ..._many(3, 22),
        ..._many(2, 32),
      ]);
      expect(WeatherAnalytics.comparable(r.temperature), hasLength(2));
    });

    test('HR comparison needs two bands with enough HR runs', () {
      final r = WeatherAnalytics.analyze([
        ..._many(3, 12, hr: 140),
        ..._many(3, 22), // plenty of runs, but no HR
      ]);
      expect(WeatherAnalytics.comparable(r.temperature, forHr: true), isEmpty);
      final r2 = WeatherAnalytics.analyze([
        ..._many(3, 12, hr: 140),
        ..._many(3, 22, hr: 150),
      ]);
      expect(
        WeatherAnalytics.comparable(r2.temperature, forHr: true),
        hasLength(2),
      );
    });
  });

  group('heat impact', () {
    test('compares 30°+ with 20–25° as a pace difference in s/km', () {
      final r = WeatherAnalytics.analyze([
        ..._many(6, 22, secs: 3300), // 330 s/km
        ..._many(5, 32, secs: 3450), // 345 s/km
      ]);
      final h = r.heatImpact!;
      expect(h.hotLabel, '30°+');
      expect(h.baselineLabel, '20–25°');
      expect(h.hotRuns, 5);
      expect(h.baselineRuns, 6);
      expect(h.deltaSecondsPerKm, closeTo(15, 1e-9));
      expect(h.isNegligible, isFalse);
    });

    test(
      'is absent with too few runs on either side — never from 1–2 runs',
      () {
        expect(
          WeatherAnalytics.analyze([
            ..._many(6, 22),
            ..._many(2, 32),
          ]).heatImpact,
          isNull,
        );
        expect(
          WeatherAnalytics.analyze([
            ..._many(4, 22),
            ..._many(6, 32),
          ]).heatImpact,
          isNull,
        );
        expect(
          WeatherAnalytics.analyze([_run(22), _run(32)]).heatImpact,
          isNull,
        );
      },
    );

    test('falls back to 25–30° when 30°+ has too few runs', () {
      final r = WeatherAnalytics.analyze([
        ..._many(5, 22, secs: 3300),
        ..._many(5, 27, secs: 3400),
        ..._many(2, 33),
      ]);
      final h = r.heatImpact!;
      expect(h.hotLabel, '25–30°');
      expect(h.deltaSecondsPerKm, closeTo(10, 1e-9));
    });

    test('prefers 30°+ when both warm bands qualify', () {
      final r = WeatherAnalytics.analyze([
        ..._many(5, 22),
        ..._many(5, 27),
        ..._many(5, 33),
      ]);
      expect(r.heatImpact!.hotLabel, '30°+');
    });

    test('a faster hot pace is reported as negative, not hidden', () {
      final r = WeatherAnalytics.analyze([
        ..._many(5, 22, secs: 3300),
        ..._many(5, 32, secs: 3250),
      ]);
      expect(r.heatImpact!.deltaSecondsPerKm, closeTo(-5, 1e-9));
    });

    test('a tiny difference is flagged as negligible', () {
      final r = WeatherAnalytics.analyze([
        ..._many(5, 22, secs: 3300),
        ..._many(5, 32, secs: 3320), // +2 s/km
      ]);
      expect(r.heatImpact!.isNegligible, isTrue);
    });

    test('with no 20–25° baseline there is no insight', () {
      final r = WeatherAnalytics.analyze([..._many(8, 12), ..._many(8, 33)]);
      expect(r.heatImpact, isNull);
    });
  });

  group('condition grouping', () {
    test('only conditions with data appear, in a stable order', () {
      final r = WeatherAnalytics.analyze([
        ..._many(2, 20, condition: WeatherCondition.rain),
        ..._many(4, 20, condition: WeatherCondition.clear),
      ]);
      expect(r.conditions.map((s) => s.key), ['clear', 'rain']);
      expect(r.conditions.map((s) => s.runCount), [4, 2]);
      expect(r.conditions.any((s) => s.key == 'snow'), isFalse);
    });

    test('a single condition still lists, with its own sample flag', () {
      final r = WeatherAnalytics.analyze([
        _run(10, condition: WeatherCondition.fog),
      ]);
      expect(r.conditions.single.key, 'fog');
      expect(r.conditions.single.hasEnoughRuns, isFalse);
    });

    test('all five conditions can be present', () {
      final r = WeatherAnalytics.analyze([
        for (final c in WeatherCondition.values) _run(15, condition: c),
      ]);
      expect(r.conditions.map((s) => s.key), [
        'clear',
        'cloudy',
        'rain',
        'snow',
        'fog',
      ]);
    });
  });
}
