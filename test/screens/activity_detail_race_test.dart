import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/screens/activity_detail_screen.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

RunRecord _record({int? id, String type = 'easy', List<int>? splits}) =>
    RunRecord(
      id: id,
      date: DateTime(2026, 9, 20, 7),
      distanceKm: 5.0,
      averagePace: '5:00',
      durationSeconds: 1500,
      routePolyline: '',
      workoutType: type,
      splits: [
        for (var i = 0; i < (splits ?? [300, 300, 290, 290, 290]).length; i++)
          {'km': i + 1, 'seconds': (splits ?? [300, 300, 290, 290, 290])[i]},
      ],
    );

Widget _host(ActivityDetail a) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.dark]),
  home: ActivityDetailScreen(activity: a),
);

/// Lets real async database work finish, pumping until [done] appears.
Future<void> _settle(WidgetTester t, Finder done) async {
  for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  sqfliteFfiInit();

  group('split strategy on Activity Detail', () {
    testWidgets('shown for a run with enough full kilometres', (t) async {
      final a = ActivityDetail.fromRunRecord(_record(), runnerName: 'x');
      await t.pumpWidget(_host(a));
      await t.pump();
      expect(find.byKey(const Key('split-strategy-card')), findsOneWidget);
      expect(find.text('Negative Split'), findsOneWidget);
    });

    testWidgets('hidden for a run with under 4 full kilometres', (t) async {
      final a = ActivityDetail.fromRunRecord(
        _record(splits: [300, 290, 280]),
        runnerName: 'x',
      );
      await t.pumpWidget(_host(a));
      await t.pump();
      expect(find.byKey(const Key('split-strategy-card')), findsNothing);
    });
  });

  group('marking a race from Activity Detail', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, _) => DatabaseService.createSchemaForTesting(db),
        ),
      );
      DatabaseService.useDatabaseForTesting(db);
    });

    tearDown(() async {
      DatabaseService.useDatabaseForTesting(null);
      await db.close();
    });

    testWidgets('flag toggles the run to race and back', (t) async {
      late int id;
      await t.runAsync(() async {
        id = await DatabaseService.instance.insertRun(_record());
      });
      final rec = (await t.runAsync(() => DatabaseService.instance.getRunById(id)))!;
      await t.pumpWidget(
        _host(ActivityDetail.fromRunRecord(rec, runnerName: 'x')),
      );
      await t.pump();

      await t.tap(find.byKey(const Key('mark-race-button')));
      await _settle(t, find.byTooltip('Unmark race'));
      expect(
        (await t.runAsync(() => DatabaseService.instance.getRunById(id)))!
            .workoutType,
        'race',
      );
      expect(find.byTooltip('Unmark race'), findsOneWidget);

      await t.tap(find.byKey(const Key('mark-race-button')));
      await _settle(t, find.byTooltip('Mark as race'));
      expect(
        (await t.runAsync(() => DatabaseService.instance.getRunById(id)))!
            .workoutType,
        'free',
      );
      expect(find.byTooltip('Mark as race'), findsOneWidget);
    });

    testWidgets('no flag for a run without a local id', (t) async {
      final a = ActivityDetail.fromRunRecord(_record(), runnerName: 'x');
      await t.pumpWidget(_host(a));
      await t.pump();
      expect(find.byKey(const Key('mark-race-button')), findsNothing);
    });
  });
}
