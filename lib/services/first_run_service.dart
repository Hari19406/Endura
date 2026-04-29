// lib/services/first_run_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class FirstRunService {
  final SharedPreferences _prefs;

  FirstRunService(this._prefs);

  static Future<FirstRunService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FirstRunService(prefs);
  }

  String _onboardingKey() {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return 'onboarding_completed_unknown';
  return 'onboarding_completed_${user.id}';
}

  bool isOnboardingCompleted() {
    final key = _onboardingKey();
    if (_prefs.getBool(key) ?? false) return true;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      if (meta != null && meta['onboarding_complete'] == true) {
        _prefs.setBool(key, true);
        return true;
      }
    }

    return false;
  }

  Future<void> markOnboardingCompleted() async {
    final key = _onboardingKey();
    await _prefs.setBool(key, true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'onboarding_complete': true}),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('metadata update timed out'),
      ).catchError((e) {
        debugPrint('Failed to save onboarding flag to Supabase: $e');
      });
    }
  }

  Future<void> reset() async {
    final key = _onboardingKey();
    await _prefs.remove(key);
  }
}