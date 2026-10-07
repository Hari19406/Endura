/// RunWeather: the persisted per-run weather payload, its tolerant parsing, and
/// the rules for which weather a finished run is given.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/run_weather.dart';
import 'package:run_app/services/weather_service.dart';

WeatherSnapshot _snapshot({
  DateTime? fetchedAt,
  WeatherCondition condition = WeatherCondition.cloudy,
}) => WeatherSnapshot(
  tempC: 24.5,
  apparentTempC: 26.1,
  humidityPercent: 63,
  dewPointC: 17.0,
  condition: condition,
  fetchedAt: fetchedAt ?? DateTime(2026, 10, 7, 6, 30),
);

Map<String, dynamic> _json() => RunWeather.fromSnapshot(_snapshot()).toJson();

void main() {
  final start = DateTime(2026, 10, 7, 7, 0);
  final end = DateTime(2026, 10, 7, 7, 45);

  group('serialisation', () {
    test('fromSnapshot keeps every field and the real observation time', () {
      final fetchedAt = DateTime(2026, 10, 7, 6, 12);
      final w = RunWeather.fromSnapshot(_snapshot(fetchedAt: fetchedAt));
      expect(w.tempC, 24.5);
      expect(w.apparentTempC, 26.1);
      expect(w.humidityPercent, 63);
      expect(w.dewPointC, 17.0);
      expect(w.condition, WeatherCondition.cloudy);
      expect(w.observedAt, fetchedAt);
      expect(w.source, RunWeather.sourceCurrent);
    });

    test('round-trips through a JSON string (SQLite) unchanged', () {
      final w = RunWeather.fromSnapshot(_snapshot());
      expect(RunWeather.tryParse(jsonEncode(w.toJson())), w);
    });

    test('round-trips through a decoded map (Supabase jsonb) unchanged', () {
      final w = RunWeather.fromSnapshot(_snapshot());
      expect(RunWeather.tryParse(w.toJson()), w);
    });

    test('the payload is versioned and tagged with its source', () {
      final json = _json();
      expect(json['v'], RunWeather.schemaVersion);
      expect(json['source'], 'current');
      expect(json.keys, containsAll(['tempC', 'apparentTempC', 'condition']));
    });

    test('a historical-backfill source survives the round trip', () {
      final w = RunWeather(
        tempC: 18,
        apparentTempC: 18,
        humidityPercent: 50,
        dewPointC: 8,
        condition: WeatherCondition.clear,
        observedAt: DateTime(2026, 5, 1, 7),
        source: RunWeather.sourceHistorical,
      );
      expect(RunWeather.tryParse(w.toJson())!.source, 'historical');
    });

    test('every condition round-trips', () {
      for (final c in WeatherCondition.values) {
        final w = RunWeather.fromSnapshot(_snapshot(condition: c));
        expect(RunWeather.tryParse(w.toJson())!.condition, c);
      }
    });
  });

  group('tolerant parsing never fabricates weather', () {
    test('null, empty and garbage give null', () {
      expect(RunWeather.tryParse(null), isNull);
      expect(RunWeather.tryParse(''), isNull);
      expect(RunWeather.tryParse('not json'), isNull);
      expect(RunWeather.tryParse('[1,2,3]'), isNull);
      expect(RunWeather.tryParse(42), isNull);
    });

    for (final field in [
      'tempC',
      'apparentTempC',
      'humidityPercent',
      'dewPointC',
      'condition',
      'observedAt',
    ]) {
      test('a payload missing $field gives null, not a default', () {
        final json = _json()..remove(field);
        expect(RunWeather.tryParse(json), isNull);
      });
    }

    test('an unknown condition is rejected, not turned into "clear"', () {
      final json = _json()..['condition'] = 'tornado';
      expect(RunWeather.tryParse(json), isNull);
    });

    test('implausible values are rejected', () {
      expect(RunWeather.tryParse(_json()..['humidityPercent'] = 140), isNull);
      expect(RunWeather.tryParse(_json()..['humidityPercent'] = -1), isNull);
      expect(RunWeather.tryParse(_json()..['tempC'] = 99), isNull);
      expect(RunWeather.tryParse(_json()..['tempC'] = -80), isNull);
    });

    test('wrong types give null instead of throwing', () {
      expect(RunWeather.tryParse(_json()..['tempC'] = 'warm'), isNull);
      expect(
        RunWeather.tryParse(_json()..['observedAt'] = 'yesterday'),
        isNull,
      );
    });
  });

  group('which weather a run gets', () {
    test('a reading from before the start (the pre-run cache) is accepted', () {
      final w = RunWeatherCapture.forRun(
        snapshot: _snapshot(
          fetchedAt: start.subtract(const Duration(minutes: 30)),
        ),
        startedAt: start,
        endedAt: end,
      );
      expect(w, isNotNull);
      expect(w!.observedAt, start.subtract(const Duration(minutes: 30)));
    });

    test('a reading during the run is accepted', () {
      expect(
        RunWeatherCapture.forRun(
          snapshot: _snapshot(
            fetchedAt: start.add(const Duration(minutes: 20)),
          ),
          startedAt: start,
          endedAt: end,
        ),
        isNotNull,
      );
    });

    test('an hour-plus-old reading (a stale cache) is rejected', () {
      expect(
        RunWeatherCapture.forRun(
          snapshot: _snapshot(
            fetchedAt: start.subtract(const Duration(minutes: 61)),
          ),
          startedAt: start,
          endedAt: end,
        ),
        isNull,
      );
    });

    test('a reading long after the run is rejected', () {
      expect(
        RunWeatherCapture.forRun(
          snapshot: _snapshot(fetchedAt: end.add(const Duration(minutes: 16))),
          startedAt: start,
          endedAt: end,
        ),
        isNull,
      );
      expect(
        RunWeatherCapture.forRun(
          snapshot: _snapshot(fetchedAt: end.add(const Duration(minutes: 10))),
          startedAt: start,
          endedAt: end,
        ),
        isNotNull,
      );
    });

    test('no snapshot means no weather', () {
      expect(
        RunWeatherCapture.forRun(
          snapshot: null,
          startedAt: start,
          endedAt: end,
        ),
        isNull,
      );
    });
  });

  group('resolve (save-time capture)', () {
    Future<WeatherSnapshot?> fresh() async =>
        _snapshot(fetchedAt: start.subtract(const Duration(minutes: 5)));

    test(
      'uses the lookup started with the run, with no second request',
      () async {
        var fallbackCalls = 0;
        final w = await RunWeatherCapture.resolve(
          startFetch: fresh(),
          fallbackFetch: () async {
            fallbackCalls++;
            return null;
          },
          startedAt: start,
          endedAt: end,
          hasRoute: true,
        );
        expect(w, isNotNull);
        expect(w!.tempC, 24.5);
        expect(fallbackCalls, 0);
      },
    );

    test(
      'a failed start lookup saves null without retrying the network',
      () async {
        var fallbackCalls = 0;
        final w = await RunWeatherCapture.resolve(
          startFetch: Future<WeatherSnapshot?>.value(null),
          fallbackFetch: () async {
            fallbackCalls++;
            return _snapshot();
          },
          startedAt: start,
          endedAt: end,
          hasRoute: true,
        );
        expect(w, isNull);
        expect(fallbackCalls, 0);
      },
    );

    test('a start lookup that throws never throws out of the save', () async {
      final w = await RunWeatherCapture.resolve(
        startFetch: Future<WeatherSnapshot?>.error(StateError('offline')),
        fallbackFetch: () async => null,
        startedAt: start,
        endedAt: end,
        hasRoute: true,
      );
      expect(w, isNull);
    });

    test(
      'a lookup still running at save time is abandoned, not awaited',
      () async {
        final never = Completer<WeatherSnapshot?>();
        final sw = Stopwatch()..start();
        final w = await RunWeatherCapture.resolve(
          startFetch: never.future,
          fallbackFetch: () async => null,
          startedAt: start,
          endedAt: end,
          hasRoute: true,
          timeout: const Duration(milliseconds: 30),
        );
        expect(w, isNull);
        expect(sw.elapsedMilliseconds, lessThan(1000));
      },
    );

    test(
      'a run with no start lookup (resumed after a kill) falls back once',
      () async {
        var fallbackCalls = 0;
        final w = await RunWeatherCapture.resolve(
          startFetch: null,
          fallbackFetch: () async {
            fallbackCalls++;
            return _snapshot(fetchedAt: end);
          },
          startedAt: start,
          endedAt: end,
          hasRoute: true,
        );
        expect(w, isNotNull);
        expect(fallbackCalls, 1);
      },
    );

    test('the fallback still refuses a stale snapshot', () async {
      final w = await RunWeatherCapture.resolve(
        startFetch: null,
        fallbackFetch: () async =>
            _snapshot(fetchedAt: start.subtract(const Duration(hours: 5))),
        startedAt: start,
        endedAt: end,
        hasRoute: true,
      );
      expect(w, isNull);
    });

    test('a stale snapshot from the start lookup is rejected too', () async {
      final w = await RunWeatherCapture.resolve(
        startFetch: Future.value(
          _snapshot(fetchedAt: start.subtract(const Duration(hours: 3))),
        ),
        fallbackFetch: () async => null,
        startedAt: start,
        endedAt: end,
        hasRoute: true,
      );
      expect(w, isNull);
    });

    test('indoor / route-less runs get no outdoor weather', () async {
      final w = await RunWeatherCapture.resolve(
        startFetch: fresh(),
        fallbackFetch: () async => _snapshot(),
        startedAt: start,
        endedAt: end,
        hasRoute: false,
      );
      expect(w, isNull);
    });
  });
}
