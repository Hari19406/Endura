// lib/screens/athlete_list_screen.dart
//
// Reusable athlete list — used for followers, following, and search results.
// Tapping a row opens that athlete's profile.

import 'package:flutter/material.dart';

import '../models/athlete_profile.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import 'athlete_profile_screen.dart';

enum AthleteListMode { followers, following }

class AthleteListScreen extends StatefulWidget {
  final String userId;
  final AthleteListMode mode;
  const AthleteListScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  @override
  State<AthleteListScreen> createState() => _AthleteListScreenState();
}

class _AthleteListScreenState extends State<AthleteListScreen> {
  List<AthleteProfile>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = SocialService.instance;
    final people = widget.mode == AthleteListMode.followers
        ? await s.followers(widget.userId)
        : await s.following(widget.userId);
    if (mounted) setState(() => _people = people);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = widget.mode == AthleteListMode.followers
        ? 'Followers'
        : 'Following';
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
          ),
        ),
      ),
      body: _people == null
          ? const Center(child: CircularProgressIndicator())
          : _people!.isEmpty
          ? Center(
              child: Text(
                'Nobody here yet.',
                style: TextStyle(color: c.textTertiary),
              ),
            )
          : ListView.separated(
              itemCount: _people!.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
              itemBuilder: (context, i) =>
                  AthleteRow(athlete: _people![i]),
            ),
    );
  }
}

/// A single tappable athlete row (avatar, name, @username).
class AthleteRow extends StatelessWidget {
  final AthleteProfile athlete;
  const AthleteRow({super.key, required this.athlete});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AthleteProfileScreen(athleteId: athlete.id),
        ),
      ),
      leading: AthleteAvatar(athlete: athlete, radius: 20),
      title: Text(
        athlete.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      subtitle: athlete.username != null
          ? Text(
              '@${athlete.username}',
              style: TextStyle(color: c.textTertiary, fontSize: 12),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: c.textFaint, size: 20),
    );
  }
}

/// Circular avatar: network image when set, otherwise initials on a tinted disc.
class AthleteAvatar extends StatelessWidget {
  final AthleteProfile athlete;
  final double radius;
  const AthleteAvatar({super.key, required this.athlete, this.radius = 32});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = athlete.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: c.surfaceAlt,
        backgroundImage: NetworkImage(url),
      );
    }
    final initials = _initials(athlete.name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.surfaceAlt,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: c.textSecondary,
        ),
      ),
    );
  }

  String _initials(String name) {
    final cleaned = name.replaceAll('@', '').trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
