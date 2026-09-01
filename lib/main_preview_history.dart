import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'screens/history_tab.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'utils/database_service.dart';

/// Preview harness for the You screen's History tab — same pattern as
/// [main_preview_share.dart]. Runs the tab against synthetic RunRecords so
/// the layout can be checked without a device or a populated database.
///
/// `flutter run -d web-server -t lib/main_preview_history.dart`
void main() => runApp(const HistoryPreviewApp());

/// Deterministic sample history: 14 months of runs across every workout type,
/// including a couple with no GPS route so the thumbnail fallback shows.
List<RunRecord> _sampleRecords() {
  final rng = math.Random(7);
  final now = DateTime.now();
  const types = ['easy', 'tempo', 'interval', 'long', 'free'];

  String polylineFor(int seed, bool hasRoute) {
    if (!hasRoute) return '';
    final r = math.Random(seed);
    double lat = 12.9716, lng = 77.5946;
    final pts = <String>[];
    for (int i = 0; i < 40; i++) {
      lat += (r.nextDouble() - 0.45) * 0.0016;
      lng += (r.nextDouble() - 0.42) * 0.0016;
      pts.add('$lat,$lng');
    }
    return pts.join(';');
  }

  final out = <RunRecord>[];
  for (int i = 0; i < 46; i++) {
    // Spread runs back over ~14 months, a few days apart.
    final date = now.subtract(Duration(days: (i * 9) + rng.nextInt(3)));
    final type = types[i % types.length];
    final distance = switch (type) {
      'long' => 14 + rng.nextDouble() * 8,
      'interval' => 6 + rng.nextDouble() * 3,
      'tempo' => 8 + rng.nextDouble() * 4,
      _ => 5 + rng.nextDouble() * 5,
    };
    final paceSeconds = 280 + rng.nextInt(90);
    final duration = (distance * paceSeconds).round();
    // Every 7th run has no usable route (treadmill / pre-polyline).
    final hasRoute = i % 7 != 3;

    out.add(
      RunRecord(
        id: i + 1,
        distanceKm: distance,
        averagePace:
            '${paceSeconds ~/ 60}:${(paceSeconds % 60).toString().padLeft(2, '0')}',
        durationSeconds: duration,
        date: date,
        routePolyline: polylineFor(i, hasRoute),
        workoutType: type,
        rpe: i % 4 == 0 ? null : 4 + rng.nextInt(6),
        elevationGain: i % 3 == 0 ? 0 : 20 + rng.nextDouble() * 180,
      ),
    );
  }
  return out;
}

class HistoryPreviewApp extends StatefulWidget {
  const HistoryPreviewApp({super.key});

  @override
  State<HistoryPreviewApp> createState() => _HistoryPreviewAppState();
}

class _HistoryPreviewAppState extends State<HistoryPreviewApp> {
  // Starts on system so the browser's colour-scheme emulation drives it;
  // the AppBar toggle still forces a specific theme.
  ThemeMode _mode = ThemeMode.system;
  bool _empty = false;
  late final List<RunRecord> _records = _sampleRecords();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _mode,
      home: Builder(
        builder: (context) {
          final c = context.colors;
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              backgroundColor: c.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                'You',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Toggle empty state',
                  icon: Icon(Icons.inbox_outlined, color: c.textSecondary),
                  onPressed: () => setState(() => _empty = !_empty),
                ),
                IconButton(
                  tooltip: 'Toggle theme',
                  icon: Icon(Icons.brightness_6, color: c.textSecondary),
                  onPressed: () => setState(
                    () => _mode = Theme.of(context).brightness == Brightness.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24, bottom: 12),
                  child: Text(
                    'History',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            body: HistoryTab(
              records: _empty ? const [] : _records,
              onRefresh: () async {},
              onOpenRun: (record) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Opened ${record.workoutType} run · '
                    '${record.distanceKm.toStringAsFixed(1)} km · '
                    '${record.date.day}/${record.date.month}/${record.date.year}',
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
