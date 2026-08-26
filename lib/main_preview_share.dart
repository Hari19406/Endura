import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'widgets/run_share_card.dart';

void main() {
  runApp(const ShareCardPreviewApp());
}

final _sampleData = ShareRunData(
  distanceKm: 8.2,
  averagePace: '5:12',
  durationSeconds: 42 * 60 + 30,
  date: DateTime.now(),
  workoutType: 'tempo',
  gpsPoints: [
    {'lat': 12.9716, 'lng': 77.5946},
    {'lat': 12.9750, 'lng': 77.5980},
    {'lat': 12.9790, 'lng': 77.6010},
    {'lat': 12.9770, 'lng': 77.6050},
    {'lat': 12.9720, 'lng': 77.6020},
  ],
  useMiles: false,
);

class ShareCardPreviewApp extends StatelessWidget {
  const ShareCardPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showRunShareSheet(
              context,
              _sampleData,
              source: 'preview',
            ),
            child: const Text('Open share sheet'),
          ),
        ),
      ),
    );
  }
}
