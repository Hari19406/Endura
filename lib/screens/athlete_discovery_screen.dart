// lib/screens/athlete_discovery_screen.dart
//
// Find other runners by name or city. Debounced search over
// SocialService.searchAthletes; empty state shows popular public athletes.
// Each tile carries a "Follows you" pill when that athlete already follows the
// signed-in user.

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/athlete_profile.dart';
import '../services/social_service.dart';
import '../theme/app_colors.dart';
import 'athlete_list_screen.dart';

class AthleteDiscoveryScreen extends StatefulWidget {
  const AthleteDiscoveryScreen({super.key});

  @override
  State<AthleteDiscoveryScreen> createState() => _AthleteDiscoveryScreenState();
}

class _AthleteDiscoveryScreenState extends State<AthleteDiscoveryScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _loading = false;
  List<AthleteProfile>? _results; // null until the first search runs
  List<AthleteProfile> _suggested = [];
  Set<String> _followsYou = {};

  static const _debounceMs = 300;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    final people = await SocialService.instance.suggestedAthletes();
    final follows = await SocialService.instance.getFollowerIdsAmong(
      people.map((p) => p.id).toList(),
    );
    if (!mounted) return;
    setState(() {
      _suggested = people;
      _followsYou = {..._followsYou, ...follows};
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _runSearch(q),
    );
  }

  Future<void> _runSearch(String q) async {
    final people = await SocialService.instance.searchAthletes(q);
    final follows = await SocialService.instance.getFollowerIdsAmong(
      people.map((p) => p.id).toList(),
    );
    if (!mounted || q != _query) return; // a newer keystroke won
    setState(() {
      _results = people;
      _followsYou = {..._followsYou, ...follows};
      _loading = false;
    });
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
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
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: c.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search runners by name or city',
              hintStyle: TextStyle(color: c.textFaint, fontSize: 14),
              prefixIcon: Icon(Icons.search, size: 20, color: c.textTertiary),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: c.textTertiary),
                      onPressed: _clear,
                      tooltip: 'Clear',
                    ),
              isDense: true,
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
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
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.colors;

    if (_query.isEmpty) {
      if (_suggested.isEmpty) {
        return _Hint(
          icon: Icons.search,
          text: 'Search runners by name or city.',
        );
      }
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'SUGGESTED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ..._suggested.map(
            (a) => AthleteRow(
              athlete: a,
              followsYou: _followsYou.contains(a.id),
            ),
          ),
        ],
      );
    }

    if (_loading && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final results = _results ?? const [];
    if (results.isEmpty) {
      return _Hint(
        icon: Icons.person_off_outlined,
        text: "No runners found matching '$_query'.",
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) => AthleteRow(
        athlete: results[i],
        followsYou: _followsYou.contains(results[i].id),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
