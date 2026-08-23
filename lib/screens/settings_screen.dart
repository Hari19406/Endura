// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/database_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/training_days_service.dart';
import '../services/profile_service.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useMetric = true;
  bool _voiceCoaching = false;
  bool _isLoading = true;
  int _runsPerWeek = 4;
  List<int> _trainingDays = TrainingDaysService.defaultsFor(4);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getInt('runs_per_week');
    final storedRunsPerWeek = (storedValue ?? 4).clamp(1, 7);
    final storedDays = await TrainingDaysService.loadOrDefault(
      storedRunsPerWeek,
    );
    if (mounted) {
      setState(() {
        _useMetric = prefs.getString('distance_unit') != 'miles';
        _voiceCoaching = prefs.getBool('voice_coaching') ?? false;
        _runsPerWeek = storedRunsPerWeek;
        _trainingDays = storedDays;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('distance_unit', _useMetric ? 'km' : 'miles');
    await prefs.setBool('voice_coaching', _voiceCoaching);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved'),
          backgroundColor: context.colors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Sign out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        content: Text(
          'Your runs are safely backed up to the cloud. Sign back in anytime to restore them.',
          style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.textPrimary),
            child: const Text(
              'Sign out',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await CloudSyncService.instance.syncPendingRuns();
      await Supabase.instance.client.auth.signOut();
      await DatabaseService.instance.deleteAllRuns();
      await DatabaseService.instance.deleteAllSnapshots();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppInitializer()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Delete account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
        content: Text(
          'This permanently deletes all your runs, training history, and account. This cannot be undone.',
          style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text(
              'Delete everything',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: c.surface,
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(
                'Deleting your account...',
                style: TextStyle(color: c.textPrimary),
              ),
            ],
          ),
        ),
      );
    }

    try {
      final cloudDeleted = await CloudSyncService.instance.deleteAllCloudRuns();

      if (!cloudDeleted) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(
                'Delete failed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              content: Text(
                'Could not delete your cloud data. Check your connection and try again.',
                style: TextStyle(
                  fontSize: 14,
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      await ProfileService.instance.deleteProfile();
      await Supabase.instance.client.rpc('delete_current_user');
      await DatabaseService.instance.deleteAllRuns();
      await DatabaseService.instance.deleteAllSnapshots();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppInitializer()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: context.colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // APPEARANCE
                    _buildSectionHeader('APPEARANCE'),
                    const SizedBox(height: 12),
                    _buildCard(child: _buildThemeSelector()),
                    const SizedBox(height: 24),

                    // UNITS
                    _buildSectionHeader('UNITS'),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: _buildSwitchRow(
                        label: 'Use metric (km)',
                        subtitle: 'Switch off to use miles',
                        value: _useMetric,
                        onChanged: (value) {
                          setState(() => _useMetric = value);
                          UnitUtils.setMiles(!value);
                          _saveSettings();
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // TRAINING
                    _buildSectionHeader('TRAINING'),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: _buildSwitchRow(
                        label: 'Voice coaching',
                        subtitle: 'Spoken pace and distance every km',
                        value: _voiceCoaching,
                        onChanged: (value) {
                          setState(() => _voiceCoaching = value);
                          _saveSettings();
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ACCOUNT
                    _buildSectionHeader('ACCOUNT'),
                    const SizedBox(height: 12),
                    _buildCard(child: _buildSignOutRow()),
                    const SizedBox(height: 24),

                    // DATA
                    _buildSectionHeader('DATA'),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: _buildDangerRow(
                        label: 'Delete account',
                        subtitle: 'Permanently removes all your data',
                        onPressed: _confirmDeleteAccount,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // App version
                    Center(
                      child: Text(
                        'Endura v1.1.0',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textFaint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.colors.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  Widget _buildThemeSelector() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how Endura looks',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildThemeOption('Light', ThemeMode.light, mode),
                const SizedBox(width: 8),
                _buildThemeOption('Dark', ThemeMode.dark, mode),
                const SizedBox(width: 8),
                _buildThemeOption('System', ThemeMode.system, mode),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption(String label, ThemeMode value, ThemeMode current) {
    final c = context.colors;
    final selected = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => ThemeController.instance.setMode(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            border: Border.all(color: selected ? c.accent : c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? c.onAccent : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildSignOutRow() {
    final c = context.colors;
    final currentUser = Supabase.instance.client.auth.currentUser;

    return InkWell(
      onTap: _signOut,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign out',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.email ??
                        currentUser?.userMetadata?['full_name'] as String? ??
                        '',
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.logout, color: c.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerRow({
    required String label,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
