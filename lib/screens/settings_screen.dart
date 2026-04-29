// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/database_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/training_days_service.dart';
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
    final storedDays =
        await TrainingDaysService.loadOrDefault(storedRunsPerWeek);
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
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: Color(0xFF388E3C),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Sign out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
          ),
        ),
        content: const Text(
          'Your runs are safely backed up to the cloud. Sign back in anytime to restore them.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF666666))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: const Text('Sign out',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Delete account?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
          ),
        ),
        content: const Text(
          'This permanently deletes all your runs, training history, and account. This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF666666),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF666666))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD32F2F)),
            child: const Text('Delete everything',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          backgroundColor: Colors.white,
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.black),
              SizedBox(width: 16),
              Text('Deleting your account...'),
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
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text('Delete failed',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000))),
              content: const Text(
                'Could not delete your cloud data. Check your connection and try again.',
                style: TextStyle(
                    fontSize: 14, color: Color(0xFF666666), height: 1.5),
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

      await Supabase.instance.client.auth.signOut();
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
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0A0A0A),
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0A0A0A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF000000)))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    _buildCard(
                      child: _buildSignOutRow(),
                    ),
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
                          color: Colors.grey.shade400,
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
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF999999),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }

  Widget _buildSwitchRow({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF000000),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSignOutRow() {
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
                  const Text(
                    'Sign out',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentUser?.email ??
                        currentUser?.userMetadata?['full_name'] as String? ??
                        '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.logout, color: Color(0xFF999999), size: 20),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF999999),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

}