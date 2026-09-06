// lib/screens/edit_athlete_profile_screen.dart
//
// Form for the public social identity fields on `profiles`. Coaching config
// (vDOT, plan, training days) is edited elsewhere and untouched here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/athlete_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';

class EditAthleteProfileScreen extends StatefulWidget {
  final AthleteProfile profile;
  const EditAthleteProfileScreen({super.key, required this.profile});

  @override
  State<EditAthleteProfileScreen> createState() =>
      _EditAthleteProfileScreenState();
}

class _EditAthleteProfileScreenState extends State<EditAthleteProfileScreen> {
  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late bool _isPublic;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _displayName = TextEditingController(text: p.displayName ?? '');
    _username = TextEditingController(text: p.username ?? '');
    _bio = TextEditingController(text: p.bio ?? '');
    _city = TextEditingController(text: p.city ?? '');
    _country = TextEditingController(text: p.country ?? '');
    _isPublic = p.isPublic;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  String? _validateUsername(String v) {
    if (v.isEmpty) return null; // optional
    if (!RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(v)) {
      return '3–30 characters, letters, numbers and _ only';
    }
    return null;
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final usernameErr = _validateUsername(username);
    if (usernameErr != null) {
      setState(() => _error = usernameErr);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // Pre-check uniqueness for a friendly message (DB unique index is the
    // real guard).
    if (username.isNotEmpty &&
        !await ProfileService.instance.usernameAvailable(username)) {
      setState(() {
        _saving = false;
        _error = '@$username is taken';
      });
      return;
    }

    String? nullIfBlank(String s) => s.trim().isEmpty ? null : s.trim();

    final updated = widget.profile.copyWith(
      username: nullIfBlank(username),
      displayName: nullIfBlank(_displayName.text),
      bio: nullIfBlank(_bio.text),
      city: nullIfBlank(_city.text),
      country: nullIfBlank(_country.text),
      isPublic: _isPublic,
    );

    final ok = await ProfileService.instance.updateAthleteFields(updated);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, updated);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Edit Profile',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: c.danger, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _field(context, 'Display name', _displayName, maxLength: 40),
          _field(
            context,
            'Username',
            _username,
            prefix: '@',
            maxLength: 30,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
            ],
          ),
          _field(context, 'Bio', _bio, maxLength: 160, maxLines: 3),
          _field(context, 'City', _city, maxLength: 60),
          _field(context, 'Country', _country, maxLength: 60),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
            title: Text(
              'Public profile',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            subtitle: Text(
              'When off, only you can see your profile, stats and gear.',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
            activeThumbColor: c.accent,
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? prefix,
    int? maxLength,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLength: maxLength,
            maxLines: maxLines,
            inputFormatters: inputFormatters,
            style: TextStyle(color: c.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              prefixText: prefix,
              prefixStyle: TextStyle(color: c.textSecondary, fontSize: 15),
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
