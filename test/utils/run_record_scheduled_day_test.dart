/// RunRecord.scheduledDayId — the completed-run → plan-slot link column added
/// in DB v10. Verifies it survives the toMap / fromMap round trip and is
/// omitted (kept NULL) when absent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:run_app/utils/database_service.dart';

RunRecord _run({String? scheduledDayId}) => RunRecord(
  distanceKm: 8.2,
  averagePace: '5:10',
  durationSeconds: 2540,
  date: DateTime(2026, 9, 11, 7),
  routePolyline: '',
  workoutType: 'interval',
  scheduledDayId: scheduledDayId,
);

void main() {
  test('scheduled_day_id round-trips through toMap/fromMap', () {
    final map = _run(scheduledDayId: 'plan_9::w3::d2').toMap();
    expect(map['scheduled_day_id'], 'plan_9::w3::d2');

    final back = RunRecord.fromMap(map);
    expect(back.scheduledDayId, 'plan_9::w3::d2');
  });

  test('omitted when null so existing rows stay NULL', () {
    final map = _run().toMap();
    expect(map.containsKey('scheduled_day_id'), isFalse);
    expect(RunRecord.fromMap(map).scheduledDayId, isNull);
  });
}
