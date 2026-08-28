import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding/onboarding_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire up Supabase so preview screens that read live data (e.g. the race
  // picker via RaceService) behave like the real app. Requires:
  //   flutter run -t lib/main_preview.dart --dart-define-from-file=dart_defines.env
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      debugPrint('[Preview] Supabase init failed: $e');
    }
  } else {
    debugPrint(
      '[Preview] No SUPABASE_* dart-defines — live data screens will be empty. '
      'Pass --dart-define-from-file=dart_defines.env',
    );
  }

  runApp(const PreviewApp());
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: OnboardingScreen(onComplete: () {}),
    );
  }
}
