// lib/screens/edit_athlete_profile_screen.dart
//
// Form for the public social identity fields on `profiles`. Coaching config
// (vDOT, plan, training days) is edited elsewhere and untouched here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/athlete_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../utils/image_compress.dart';

class EditAthleteProfileScreen extends StatefulWidget {
  final AthleteProfile profile;
  const EditAthleteProfileScreen({super.key, required this.profile});

  @override
  State<EditAthleteProfileScreen> createState() =>
      _EditAthleteProfileScreenState();
}

class _EditAthleteProfileScreenState extends State<EditAthleteProfileScreen> {
  late final TextEditingController _displayName;
  late final TextEditingController _bio;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late bool _isPublic;

  bool _saving = false;
  String? _error;

  String? _avatarUrl;
  Uint8List? _avatarPreview; // freshly picked, not yet on the profile object
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _displayName = TextEditingController(text: p.displayName ?? '');
    _bio = TextEditingController(text: p.bio ?? '');
    _city = TextEditingController(text: p.city ?? '');
    _country = TextEditingController(text: p.country ?? '');
    _isPublic = p.isPublic;
    _avatarUrl = p.avatarUrl;
  }

  Future<void> _pickAvatar() async {
    if (_avatarBusy) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null) return;
      setState(() => _avatarBusy = true);
      final raw = await picked.readAsBytes();
      final jpeg = AvatarCompressor.toAvatarJpeg(raw);
      if (jpeg == null) {
        setState(() {
          _avatarBusy = false;
          _error = 'That image could not be processed.';
        });
        return;
      }
      final url = await ProfileService.instance.uploadAvatar(jpeg);
      if (!mounted) return;
      setState(() {
        _avatarBusy = false;
        if (url != null) {
          _avatarUrl = url;
          _avatarPreview = jpeg;
        } else {
          _error = 'Avatar upload failed. Try again.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _avatarBusy = false;
          _error = 'Could not open the image picker.';
        });
      }
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    String? nullIfBlank(String s) => s.trim().isEmpty ? null : s.trim();

    final updated = widget.profile.copyWith(
      displayName: nullIfBlank(_displayName.text),
      bio: nullIfBlank(_bio.text),
      city: nullIfBlank(_city.text),
      country: nullIfBlank(_country.text),
      isPublic: _isPublic,
      avatarUrl: _avatarUrl,
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
          Center(child: _avatarPicker(context)),
          const SizedBox(height: 24),
          _field(context, 'Display name', _displayName, maxLength: 40),
          _field(
            context,
            'Bio (optional)',
            _bio,
            maxLength: 160,
            maxLines: 3,
            hint: 'Tell other runners a bit about yourself',
          ),
          _field(
            context,
            'City (optional)',
            _city,
            maxLength: 60,
            hint: 'Shown under your name to tell runners apart',
          ),
          _field(context, 'Country (optional)', _country, maxLength: 60),
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

  Widget _avatarPicker(BuildContext context) {
    final c = context.colors;
    ImageProvider? image;
    if (_avatarPreview != null) {
      image = MemoryImage(_avatarPreview!);
    } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      image = NetworkImage(_avatarUrl!);
    }
    return GestureDetector(
      onTap: _avatarBusy ? null : _pickAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: c.surfaceAlt,
            backgroundImage: image,
            child: image == null
                ? Icon(Icons.person, size: 40, color: c.textTertiary)
                : null,
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
              border: Border.all(color: c.background, width: 2),
            ),
            child: _avatarBusy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(c.onAccent),
                    ),
                  )
                : Icon(Icons.camera_alt, size: 14, color: c.onAccent),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    int? maxLength,
    int maxLines = 1,
    String? hint,
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
            style: TextStyle(color: c.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
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
