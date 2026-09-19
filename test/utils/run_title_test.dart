/// Editable run title: default naming, cleanup of a user-typed title, and that
/// the title survives every hop to storage — RunRecord toMap/fromMap (local
/// SQLite `runs.title`), the Supabase upload payload, and the models that
/// display it (ActivityDetail, FeedRun). The summary screen's title field is
/// covered too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/models/activity_telemetry.dart';
import 'package:run_app/models/feed_run.dart';
import 'package:run_app/services/cloud_sync_service.dart';
import 'package:run_app/theme/app_colors.dart';
import 'package:run_app/utils/database_service.dart';
import 'package:run_app/utils/run_title.dart';
import 'package:run_app/widgets/run_title_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

RunRecord _run({String? title, String type = 'tempo'}) => RunRecord(
  distanceKm: 8.2,
  averagePace: '5:10',
  durationSeconds: 2540,
  date: DateTime(2026, 9, 20, 7),
  routePolyline: '',
  workoutType: type,
  title: title,
);

void main() {
  group('RunTitle defaults', () {
    test('free runs are named by time of day', () {
      String at(int h) => RunTitle.forTimeOfDay(DateTime(2026, 9, 20, h));
      expect(at(5), 'Morning Run');
      expect(at(11), 'Morning Run');
      expect(at(12), 'Afternoon Run');
      expect(at(16), 'Afternoon Run');
      expect(at(17), 'Evening Run');
      expect(at(20), 'Evening Run');
      expect(at(21), 'Night Run');
      expect(at(2), 'Night Run');
    });

    test('planned runs use week + workout name', () {
      expect(
        RunTitle.resolve(
          startedAt: DateTime(2026, 9, 20, 7),
          isFreeRun: false,
          workoutName: 'Cruise Intervals',
          weekNumber: 3,
        ),
        'Week 3 · Cruise Intervals',
      );
    });

    test('planned run without a week keeps just the workout name', () {
      expect(
        RunTitle.resolve(
          startedAt: DateTime(2026, 9, 20, 7),
          isFreeRun: false,
          workoutName: 'Long Run',
        ),
        'Long Run',
      );
    });

    test('a free run ignores any workout name; a nameless plan run falls back', () {
      final morning = DateTime(2026, 9, 20, 7);
      expect(
        RunTitle.resolve(
          startedAt: morning,
          isFreeRun: true,
          workoutName: 'Long Run',
          weekNumber: 3,
        ),
        'Morning Run',
      );
      expect(
        RunTitle.resolve(startedAt: morning, isFreeRun: false, workoutName: ' '),
        'Morning Run',
      );
    });
  });

  group('RunTitle.normalize', () {
    test('trims and collapses whitespace', () {
      expect(RunTitle.normalize('  Track   night \n'), 'Track night');
    });

    test('blank input is null so callers fall back to the default', () {
      expect(RunTitle.normalize('   '), isNull);
      expect(RunTitle.normalize(null), isNull);
    });

    test('caps at maxLength', () {
      final out = RunTitle.normalize('x' * 200)!;
      expect(out.length, RunTitle.maxLength);
    });
  });

  group('RunRecord.title', () {
    test('a custom title round-trips through toMap/fromMap', () {
      final map = _run(title: 'Hill repeats with Sam').toMap();
      expect(map['title'], 'Hill repeats with Sam');
      expect(RunRecord.fromMap(map).title, 'Hill repeats with Sam');
    });

    test('omitted when null so existing rows stay NULL', () {
      final map = _run().toMap();
      expect(map.containsKey('title'), isFalse);
      expect(RunRecord.fromMap(map).title, isNull);
    });
  });

  group('cloud upload payload', () {
    test('includes the custom title', () {
      final payload = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(title: 'Hill repeats with Sam'),
      );
      expect(payload['title'], 'Hill repeats with Sam');
      expect(payload['user_id'], 'u1');
    });

    test('leaves title out when the run has none', () {
      final payload = CloudSyncService.buildRunPayload(
        userId: 'u1',
        run: _run(),
      );
      expect(payload.containsKey('title'), isFalse);
    });

    test('detects a project without the title column', () {
      expect(
        CloudSyncService.isMissingTitleColumn(
          PostgrestException(
            message: "Could not find the 'title' column of 'runs' "
                'in the schema cache',
            code: 'PGRST204',
          ),
        ),
        isTrue,
      );
      expect(
        CloudSyncService.isMissingTitleColumn(
          PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isFalse,
      );
    });
  });

  group('display', () {
    test('ActivityDetail uses the custom title, else the workout label', () {
      expect(
        ActivityDetail.fromRunRecord(
          _run(title: 'Week 3 · Cruise Intervals'),
          runnerName: 'You',
        ).title,
        'Week 3 · Cruise Intervals',
      );
      expect(
        ActivityDetail.fromRunRecord(_run(), runnerName: 'You').title,
        'Tempo Run',
      );
    });

    test('FeedRun prefers the athlete title over the derived label', () {
      FeedRun feed(String? title) => FeedRun.fromRows({
        'id': 1,
        'user_id': 'u1',
        'date': '2026-09-20T07:00:00Z',
        'distance_km': 8.2,
        'workout_type': 'tempo',
        'title': title,
      }, null);
      expect(feed('Sunday shakeout').title, 'Sunday shakeout');
      expect(feed(null).title, 'Tempo Run');
      expect(feed('  ').title, 'Tempo Run');
    });
  });

  group('RunTitleField', () {
    Future<TextEditingController> pump(
      WidgetTester tester,
      String initial,
    ) async {
      final controller = TextEditingController(text: initial);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(body: RunTitleField(controller: controller)),
        ),
      );
      return controller;
    }

    testWidgets('shows the pre-filled title and lets the user replace it', (
      tester,
    ) async {
      final controller = await pump(tester, 'Morning Run');
      expect(find.text('Morning Run'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Parkrun PB attempt');
      expect(controller.text, 'Parkrun PB attempt');
    });

    testWidgets('the pencil focuses the field', (tester) async {
      await pump(tester, 'Morning Run');
      await tester.tap(find.byTooltip('Edit title'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      // The pencil gets out of the way while editing.
      expect(find.byTooltip('Edit title'), findsNothing);
    });

    testWidgets('caps input at the max length', (tester) async {
      final controller = await pump(tester, '');
      await tester.enterText(find.byType(TextField), 'y' * 200);
      expect(controller.text.length, RunTitle.maxLength);
    });
  });
}
