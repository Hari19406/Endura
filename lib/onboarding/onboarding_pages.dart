import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'onboarding_screen.dart' show EC, ET;
import '../../engines/config/archetype_table.dart';
import '../../services/race_service.dart';
import '../../models/race_listing.dart';
import '../../utils/unit_utils.dart';
import 'plan_runway.dart';
import 'volume_guidance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: EC.teal,
      letterSpacing: 0.8,
    ),
  );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: EC.textPrimary,
      height: 1.25,
      letterSpacing: -0.3,
    ),
  );
}

class _Sub extends StatelessWidget {
  final String text;
  const _Sub(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 14, color: EC.textSecondary, height: 1.55),
  );
}

class _Row extends StatelessWidget {
  final Widget leading;
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  const _Row({
    required this.leading,
    required this.label,
    this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? EC.surface2 : EC.surface,
          borderRadius: BorderRadius.circular(ET.cardRadius),
          border: Border.all(
            color: selected ? EC.teal : EC.border,
            width: selected ? 1.5 : ET.borderWidth,
          ),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: EC.textPrimary,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: EC.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? EC.teal : Colors.transparent,
                border: Border.all(
                  color: selected ? EC.teal : EC.border,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: EC.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _iconBox(Color bg, IconData icon, Color fg) => Container(
  width: 44,
  height: 44,
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
  child: Icon(icon, size: 22, color: fg),
);

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 1 — INTRO
// ─────────────────────────────────────────────────────────────────────────────

class OPageIntro extends StatelessWidget {
  final AnimationController loopCtrl;
  const OPageIntro({super.key, required this.loopCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: loopCtrl,
            builder: (_, __) => Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: EC.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: EC.teal.withOpacity(
                    0.3 + 0.3 * sin(loopCtrl.value * 2 * pi),
                  ),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.directions_run_rounded,
                size: 36,
                color: EC.teal,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Endura',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: EC.teal,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: EC.textPrimary,
                height: 1.2,
                letterSpacing: -0.5,
              ),
              children: [
                TextSpan(text: "Meet "),
                TextSpan(
                  text: 'Max',
                  style: TextStyle(color: EC.teal),
                ),
                TextSpan(text: ".\nYour personal\nrunning coach."),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Max learns how you run, adapts every week,\nand builds a plan that actually fits your life.",
            style: TextStyle(
              fontSize: 15,
              color: EC.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Takes about 2 minutes',
            style: TextStyle(fontSize: 12, color: EC.muted),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2 — GOAL
// ─────────────────────────────────────────────────────────────────────────────

const _raceDistanceKeys = {'5k', '10k', 'half_marathon', 'marathon'};

class OPageGoal extends StatelessWidget {
  /// Non-null once a race (or its distance) has been chosen in the funnel.
  final String? selected;

  /// Called when the user taps the (only live) "Upcoming race" row.
  final VoidCallback onOpenRaceFunnel;

  const OPageGoal({
    super.key,
    required this.selected,
    required this.onOpenRaceFunnel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your goal'),
          const SizedBox(height: 8),
          const _Title('What are you\ntraining for?'),
          const SizedBox(height: 6),
          const _Sub(
            "Pick a starting point — we'll fine-tune the details with a few quick questions.",
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: const Text(
              '~1 min setup',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EC.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(child: _buildCategoryList()),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _SectionHeader(
          'Race goals',
          'Training toward a finish line — first-timer or PR.',
        ),
        const SizedBox(height: 12),
        _upcomingRaceRow(),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.workspace_premium_outlined,
          iconBg: Color(0xFF1E1040),
          iconFg: EC.violet,
          label: 'Train for your first half',
          sub: 'Build to 13.1 with a gradual ramp and one speed day per week.',
        ),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.military_tech_outlined,
          iconBg: Color(0xFF3D0000),
          iconFg: EC.red,
          label: 'Train for your first marathon',
          sub: 'A 16+ week buildup designed for first-time marathoners.',
        ),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.flag_outlined,
          iconBg: Color(0xFF003D35),
          iconFg: EC.teal,
          label: 'Train for your first 5K',
          sub: 'Lower-volume plan with one speed workout per week.',
        ),
        const SizedBox(height: 26),
        const _SectionHeader(
          'General fitness',
          'Stay consistent and improve without a race target.',
        ),
        const SizedBox(height: 12),
        const _ComingSoonRow(
          icon: Icons.monitor_heart_outlined,
          iconBg: Color(0xFF0F2E1E),
          iconFg: EC.teal,
          label: 'General fitness',
          sub: 'Stay consistent and improve between events. Pick your level.',
        ),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.bolt,
          iconBg: Color(0xFF0F2E1E),
          iconFg: EC.teal,
          label: 'Run faster (general fitness)',
          sub: 'No race target. Two speed workouts per week to build fitness.',
        ),
        const SizedBox(height: 26),
        const _SectionHeader(
          'Getting started',
          'New to running, coming back, or rebuilding after time off.',
        ),
        const SizedBox(height: 12),
        const _ComingSoonRow(
          icon: Icons.directions_walk,
          iconBg: Color(0xFF10202E),
          iconFg: EC.teal,
          label: 'Get back into running',
          sub:
              'Three days a week, time-based runs. Easy ramp for lapsed runners.',
        ),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.auto_awesome,
          iconBg: Color(0xFF1E1040),
          iconFg: EC.violet,
          label: 'Intro to running',
          sub: 'A friendly 5-week walk/run plan to get you off the couch.',
        ),
        const SizedBox(height: 10),
        const _ComingSoonRow(
          icon: Icons.medical_services_outlined,
          iconBg: Color(0xFF3D1A00),
          iconFg: EC.orange,
          label: 'Return from injury',
          sub: 'Rebuild slowly with a guided ramp window after time off.',
        ),
      ],
    );
  }

  Widget _upcomingRaceRow() => _Row(
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1400),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.emoji_events_outlined, color: EC.amber, size: 22),
      ),
    ),
    label: 'Upcoming race',
    sub: 'Train toward a race day with a structured build. Pick your distance.',
    selected: _raceDistanceKeys.contains(selected),
    onTap: onOpenRaceFunnel,
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: EC.textPrimary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12.5, color: EC.textSecondary),
        ),
      ],
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String label;
  final String sub;
  const _ComingSoonRow({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: EC.surface2,
              content: Text(
                '“$label” is coming soon — we\'re still building it.',
                style: const TextStyle(color: EC.textPrimary, fontSize: 13),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      },
      child: Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: EC.surface,
            borderRadius: BorderRadius.circular(ET.cardRadius),
            border: Border.all(color: EC.border, width: ET.borderWidth),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconFg, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: EC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: EC.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EC.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EC.border, width: ET.borderWidth),
                ),
                child: const Text(
                  'Coming soon',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: EC.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3 — EXPERIENCE
// ─────────────────────────────────────────────────────────────────────────────

class OPageExperience extends StatelessWidget {
  final String? selected;
  final String goal;
  final ValueChanged<String> onSelect;
  const OPageExperience({
    super.key,
    required this.selected,
    required this.goal,
    required this.onSelect,
  });

  static const _opts = [
    (
      'just_starting',
      Icons.spa_outlined,
      Color(0xFF10202E),
      EC.teal,
      'Just getting started',
      'New to running — building the habit',
    ),
    (
      'early',
      Icons.trending_up_rounded,
      Color(0xFF0F2E1E),
      EC.teal,
      'Early stages',
      'Running a few months, still finding my feet',
    ),
    (
      'regular',
      Icons.directions_run_rounded,
      Color(0xFF1E1040),
      EC.violet,
      'Regular runner',
      'Out 2–3× a week, comfortable with distance',
    ),
    (
      'seasoned',
      Icons.military_tech_outlined,
      Color(0xFF3D1A00),
      EC.orange,
      'Seasoned runner',
      'Consistent for years, raced before',
    ),
    (
      'competitive',
      Icons.emoji_events_outlined,
      Color(0xFF3D0000),
      EC.red,
      'Competitive athlete',
      'Structured training, chasing results',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your experience'),
          const SizedBox(height: 8),
          _Title("What's your\n${_goalLabelFor(goal)} experience?"),
          const SizedBox(height: 6),
          const _Sub(
            'Be honest — this sets the right starting intensity for your plan.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _opts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final (key, icon, bg, fg, label, sub) = _opts[i];
                return _Row(
                  leading: _iconBox(bg, icon, fg),
                  label: label,
                  sub: sub,
                  selected: selected == key,
                  onTap: () => onSelect(key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 4 — BEST TIME
// ─────────────────────────────────────────────────────────────────────────────

class OPageBestTime extends StatelessWidget {
  final String distance;
  final int hours, minutes, seconds;
  final ValueChanged<String> onDistChanged;
  final ValueChanged<int> onHoursChanged;
  final ValueChanged<int> onMinsChanged;
  final ValueChanged<int> onSecsChanged;

  const OPageBestTime({
    super.key,
    required this.distance,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onDistChanged,
    required this.onHoursChanged,
    required this.onMinsChanged,
    required this.onSecsChanged,
  });

  String get _distLabel => switch (distance) {
    '10k' => '10K',
    'half' => 'Half Marathon',
    'marathon' => 'Marathon',
    _ => '5K',
  };

  String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your fitness'),
          const SizedBox(height: 8),
          const _Title("What's your\ncurrent race time?"),
          const SizedBox(height: 6),
          const _Sub(
            'Use your most recent time — not your goal. Max needs your current fitness, not your dream.',
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['5k', '10k', 'half', 'marathon'].map((d) {
                final lbl = switch (d) {
                  '10k' => '10K',
                  'half' => 'Half',
                  'marathon' => 'Marathon',
                  _ => '5K',
                };
                final sel = distance == d;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onDistChanged(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? EC.teal : EC.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel ? EC.teal : EC.border,
                          width: ET.borderWidth,
                        ),
                      ),
                      child: Text(
                        lbl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? EC.black : EC.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: EC.textSecondary,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'I can currently run a '),
                  TextSpan(
                    text: _distLabel,
                    style: const TextStyle(
                      color: EC.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' in '),
                  TextSpan(
                    text: '${_pad(hours)}h ${_pad(minutes)}m ${_pad(seconds)}s',
                    style: const TextStyle(
                      color: EC.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _drum(
                    label: 'HH',
                    count: 6,
                    selected: hours,
                    onChanged: onHoursChanged,
                  ),
                ),
                _colon(),
                Expanded(
                  child: _drum(
                    label: 'MM',
                    count: 60,
                    selected: minutes,
                    onChanged: onMinsChanged,
                  ),
                ),
                _colon(),
                Expanded(
                  child: _drum(
                    label: 'SS',
                    count: 60,
                    selected: seconds,
                    onChanged: onSecsChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colon() => const Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Text(
      ':',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w300,
        color: EC.muted,
      ),
    ),
  );

  Widget _drum({
    required String label,
    required int count,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: EC.muted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: selected,
              ),
              itemExtent: 44,
              onSelectedItemChanged: onChanged,
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: EC.teal.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                ),
              ),
              children: List.generate(
                count,
                (i) => Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: EC.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 5 — DAYS COUNT
// ─────────────────────────────────────────────────────────────────────────────

class OPageDaysCount extends StatelessWidget {
  final int runsPerWeek;
  final ValueChanged<int> onChanged;
  const OPageDaysCount({
    super.key,
    required this.runsPerWeek,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your schedule'),
          const SizedBox(height: 8),
          const _Title('How many days a\nweek can you run?'),
          const SizedBox(height: 6),
          const _Sub(
            'Keep it realistic. Max will push you within what you can commit to.',
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [3, 4, 5, 6].map((n) {
                final sel = runsPerWeek == n;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onChanged(n);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? EC.surface2 : EC.surface,
                        borderRadius: BorderRadius.circular(ET.cardRadius),
                        border: Border.all(
                          color: sel ? EC.teal : EC.border,
                          width: sel ? 1.5 : ET.borderWidth,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$n ${n == 1 ? 'Day' : 'Days'}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: EC.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (sel)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: EC.teal,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 6 — DAY PICKER
// ─────────────────────────────────────────────────────────────────────────────

class OPageDayPicker extends StatelessWidget {
  final int runsPerWeek;
  final List<int> selectedDays;
  final ValueChanged<List<int>> onChanged;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  const OPageDayPicker({
    super.key,
    required this.runsPerWeek,
    required this.selectedDays,
    required this.onChanged,
  });

  void _toggle(int idx) {
    final updated = List<int>.from(selectedDays);
    if (updated.contains(idx)) {
      if (updated.length <= 1) return;
      updated.remove(idx);
    } else {
      updated.add(idx);
    }
    updated.sort();
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = runsPerWeek - selectedDays.length;
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your days'),
          const SizedBox(height: 8),
          const _Title('Which days\nwork for you?'),
          const SizedBox(height: 6),
          const _Sub(
            'Select every day you\'re free to run. Max picks the best ones.',
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: remaining > 0
                ? Text(
                    'Select $remaining more day${remaining == 1 ? '' : 's'} to continue',
                    key: ValueKey(remaining),
                    style: const TextStyle(
                      fontSize: 13,
                      color: EC.teal,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : remaining < 0
                ? Text(
                    'Deselect ${-remaining} day${-remaining == 1 ? '' : 's'}',
                    key: ValueKey(remaining),
                    style: const TextStyle(fontSize: 13, color: EC.amber),
                  )
                : const Text('', key: ValueKey(0)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final sel = selectedDays.contains(i);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _toggle(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _days[i],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: EC.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel ? EC.teal : Colors.transparent,
                            border: Border.all(
                              color: sel ? EC.teal : EC.border,
                              width: 1.5,
                            ),
                          ),
                          child: sel
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: EC.black,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 7 — LONG RUN DAY
// ─────────────────────────────────────────────────────────────────────────────

class OPageLongRunDay extends StatelessWidget {
  final List<int> availableDays;
  final int? selectedDayIndex;
  final ValueChanged<int> onSelect;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  const OPageLongRunDay({
    super.key,
    required this.availableDays,
    required this.selectedDayIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Long run'),
          const SizedBox(height: 8),
          const _Title('Which day for\nyour long run?'),
          const SizedBox(height: 6),
          const _Sub(
            'The long run is the cornerstone of your week. Pick a day when you have the most time.',
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: availableDays.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final dayIdx = availableDays[i];
                final sel = selectedDayIndex == dayIdx;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(dayIdx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _days[dayIdx],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: EC.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (sel)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: EC.teal,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 8 — INTENSITY
// ─────────────────────────────────────────────────────────────────────────────

class OPageIntensity extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const OPageIntensity({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Training style'),
          const SizedBox(height: 8),
          const _Title('How hard do you\nwant to push?'),
          const SizedBox(height: 6),
          const _Sub(
            'Max builds your plan around this. You can adjust it anytime.',
          ),
          const SizedBox(height: 28),
          _Row(
            leading: _iconBox(
              const Color(0xFF003D35),
              Icons.sentiment_satisfied_rounded,
              EC.teal,
            ),
            label: 'Finish comfortably',
            sub: 'Cross the line feeling strong',
            selected: selected == 'steady',
            onTap: () => onSelect('steady'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: _iconBox(
              const Color(0xFF1E1040),
              Icons.trending_up_rounded,
              EC.violet,
            ),
            label: 'Improve steadily',
            sub: 'Get faster week over week',
            selected: selected == 'structured',
            onTap: () => onSelect('structured'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: _iconBox(
              const Color(0xFF3D1A00),
              Icons.bolt_rounded,
              EC.orange,
            ),
            label: 'Peak performance',
            sub: 'Push limits and hit a PR',
            selected: selected == 'performance',
            onTap: () => onSelect('performance'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 9 — PLAN TIMELINE
// ─────────────────────────────────────────────────────────────────────────────

class OPagePlanTimeline extends StatefulWidget {
  final DateTime startDate;
  final int? planWeeks;
  final DateTime? raceDate;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<int> onWeeksChanged;
  final ValueChanged<DateTime> onRaceDate;

  const OPagePlanTimeline({
    super.key,
    required this.startDate,
    required this.planWeeks,
    required this.raceDate,
    required this.onStartChanged,
    required this.onWeeksChanged,
    required this.onRaceDate,
  });

  @override
  State<OPagePlanTimeline> createState() => _OPagePlanTimelineState();
}

class _OPagePlanTimelineState extends State<OPagePlanTimeline> {
  static const _weekOptions = [8, 10, 12];

  String _startLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  Future<void> _pickRaceDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 84)),
      firstDate: now.add(const Duration(days: 14)),
      lastDate: now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: EC.teal,
            onPrimary: EC.black,
            surface: EC.surface,
            onSurface: EC.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) widget.onRaceDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return SingleChildScrollView(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your timeline'),
          const SizedBox(height: 8),
          const _Title('When do you want\nto start?'),
          const SizedBox(height: 6),
          const _Sub('Pick a start date and how long you want to train.'),
          const SizedBox(height: 24),
          _sectionHead('START DATE'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(ET.cardRadius),
              border: Border.all(color: EC.teal, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _startLabel(widget.startDate),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EC.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _startChip('Today', today),
                    const SizedBox(width: 8),
                    _startChip('Tomorrow', tomorrow),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: widget.startDate,
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 60)),
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: EC.teal,
                                onPrimary: EC.black,
                                surface: EC.surface,
                                onSurface: EC.textPrimary,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) widget.onStartChanged(picked);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (!_sameDay(widget.startDate, today) &&
                                  !_sameDay(widget.startDate, tomorrow))
                              ? EC.teal
                              : EC.surface2,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (!_sameDay(widget.startDate, today) &&
                                  !_sameDay(widget.startDate, tomorrow))
                              ? _startLabel(widget.startDate)
                              : 'Custom',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                (!_sameDay(widget.startDate, today) &&
                                    !_sameDay(widget.startDate, tomorrow))
                                ? EC.black
                                : EC.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHead('PLAN LENGTH'),
          const SizedBox(height: 10),
          ..._weekOptions.map((w) {
            final endDate = widget.startDate.add(Duration(days: w * 7));
            const months = [
              'Jan',
              'Feb',
              'Mar',
              'Apr',
              'May',
              'Jun',
              'Jul',
              'Aug',
              'Sep',
              'Oct',
              'Nov',
              'Dec',
            ];
            final endLabel =
                '${endDate.day} ${months[endDate.month - 1]} ${endDate.year}';
            final sel = widget.planWeeks == w && widget.raceDate == null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onWeeksChanged(w);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? EC.surface2 : EC.surface,
                    borderRadius: BorderRadius.circular(ET.cardRadius),
                    border: Border.all(
                      color: sel ? EC.teal : EC.border,
                      width: sel ? 1.5 : ET.borderWidth,
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$w Weeks',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: EC.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            endLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: EC.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (sel)
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: EC.teal,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _pickRaceDate();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: widget.raceDate != null ? EC.surface2 : EC.surface,
                borderRadius: BorderRadius.circular(ET.cardRadius),
                border: Border.all(
                  color: widget.raceDate != null ? EC.teal : EC.border,
                  width: widget.raceDate != null ? 1.5 : ET.borderWidth,
                ),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'I have a race date',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: EC.textPrimary,
                        ),
                      ),
                      if (widget.raceDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _raceLabel(widget.raceDate!),
                          style: const TextStyle(fontSize: 12, color: EC.teal),
                        ),
                      ] else
                        const Text(
                          'Tap to pick your race date',
                          style: TextStyle(
                            fontSize: 12,
                            color: EC.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    widget.raceDate != null
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: widget.raceDate != null ? EC.teal : EC.muted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHead(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: EC.muted,
      letterSpacing: 1.2,
    ),
  );

  Widget _startChip(String label, DateTime date) {
    final sel = _sameDay(widget.startDate, date);
    return GestureDetector(
      onTap: () => widget.onStartChanged(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? EC.teal : EC.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: sel ? EC.black : EC.textSecondary,
          ),
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _raceLabel(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weeks = d.difference(DateTime.now()).inDays ~/ 7;
    return '${d.day} ${months[d.month - 1]} ${d.year} · $weeks weeks away';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 10 — DATE OF BIRTH
// ─────────────────────────────────────────────────────────────────────────────

class OPageDob extends StatefulWidget {
  final DateTime? dob;
  final ValueChanged<DateTime> onChanged;
  const OPageDob({super.key, required this.dob, required this.onChanged});

  @override
  State<OPageDob> createState() => _OPageDobState();
}

class _OPageDobState extends State<OPageDob> {
  final _day = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.dob != null) {
      _day.text = widget.dob!.day.toString().padLeft(2, '0');
      _month.text = widget.dob!.month.toString().padLeft(2, '0');
      _year.text = widget.dob!.year.toString();
    }
  }

  @override
  void dispose() {
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  void _tryParse() {
    final d = int.tryParse(_day.text);
    final m = int.tryParse(_month.text);
    final y = int.tryParse(_year.text);
    if (d != null &&
        m != null &&
        y != null &&
        y > 1900 &&
        y < DateTime.now().year) {
      try {
        widget.onChanged(DateTime(y, m, d));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('About you'),
          const SizedBox(height: 8),
          const _Title('When were\nyou born?'),
          const SizedBox(height: 6),
          const _Sub(
            'Max uses your age to personalise recovery, load, and intensity. Nothing else.',
          ),
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '14 / 08 / 1993',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: EC.muted.withValues(alpha: 0.15),
                  letterSpacing: 2,
                ),
              ),
              Row(
                children: [
                  _dobField('DD', _day, 2),
                  _sep(),
                  _dobField('MM', _month, 2),
                  _sep(),
                  _dobField('YYYY', _year, 4),
                ],
              ),
            ],
          ),
          if (widget.dob != null) ...[
            const SizedBox(height: 16),
            Builder(
              builder: (_) {
                final now = DateTime.now();
                final dob = widget.dob!;
                int age = now.year - dob.year;
                if (now.month < dob.month ||
                    (now.month == dob.month && now.day < dob.day)) {
                  age--;
                }
                return Text(
                  'Age: $age',
                  style: const TextStyle(fontSize: 13, color: EC.teal),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: Text(
      '/',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w200,
        color: EC.muted,
      ),
    ),
  );

  Widget _dobField(String hint, TextEditingController ctrl, int max) =>
      Expanded(
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: EC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.dob != null ? EC.teal : EC.border,
              width: widget.dob != null ? 1.5 : ET.borderWidth,
            ),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: EC.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: EC.muted,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(max),
            ],
            onChanged: (_) => _tryParse(),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 11 — GENDER
// ─────────────────────────────────────────────────────────────────────────────

class OPageGender extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const OPageGender({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('About you'),
          const SizedBox(height: 8),
          const _Title('How do you\nidentify?'),
          const SizedBox(height: 6),
          const _Sub(
            'Used only to personalise your training load calculations.',
          ),
          const SizedBox(height: 32),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EC.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'M',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EC.teal,
                  ),
                ),
              ),
            ),
            label: 'Male',
            selected: selected == 'male',
            onTap: () => onSelect('male'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EC.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'F',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EC.violet,
                  ),
                ),
              ),
            ),
            label: 'Female',
            selected: selected == 'female',
            onTap: () => onSelect('female'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: EC.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'O',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EC.textSecondary,
                  ),
                ),
              ),
            ),
            label: 'Prefer not to say',
            selected: selected == 'other',
            onTap: () => onSelect('other'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 12 — NAME
// ─────────────────────────────────────────────────────────────────────────────

class OPageName extends StatelessWidget {
  final String firstName;
  final ValueChanged<String> onFirstChanged;

  const OPageName({
    super.key,
    required this.firstName,
    required this.onFirstChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Almost there'),
          const SizedBox(height: 8),
          const _Title("What should\nMax call you?"),
          const SizedBox(height: 6),
          const _Sub(
            "We'll use your name to make every interaction feel personal.",
          ),
          const SizedBox(height: 40),
          _field('First name', firstName, onFirstChanged, TextInputAction.done),
          const Spacer(),
          if (firstName.trim().isNotEmpty)
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: EC.textSecondary),
                  children: [
                    const TextSpan(text: "Max will call you "),
                    TextSpan(
                      text: firstName.trim(),
                      style: const TextStyle(
                        color: EC.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _field(
    String hint,
    String value,
    ValueChanged<String> onChanged,
    TextInputAction action,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: EC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value.trim().isNotEmpty ? EC.teal : EC.border,
          width: value.trim().isNotEmpty ? 1.5 : ET.borderWidth,
        ),
      ),
      child: TextField(
        textInputAction: action,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: EC.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: EC.muted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE — RACE DAY
// ─────────────────────────────────────────────────────────────────────────────

class OPageRaceDay extends StatelessWidget {
  final DateTime startDate;
  final int planWeeks;
  final int selectedDayIndex;
  final ValueChanged<int> onSelect;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  const OPageRaceDay({
    super.key,
    required this.startDate,
    required this.planWeeks,
    required this.selectedDayIndex,
    required this.onSelect,
  });

  DateTime get _lastWeekMonday {
    final endOfPlan = startDate.add(Duration(days: planWeeks * 7));
    return endOfPlan.subtract(Duration(days: endOfPlan.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final monday = _lastWeekMonday;
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Race week'),
          const SizedBox(height: 8),
          const _Title('Which day is\nyour race?'),
          const SizedBox(height: 6),
          const _Sub(
            'Pick the day in your final training week. Sunday is the most common race day.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final date = monday.add(Duration(days: i));
                final sel = selectedDayIndex == i;
                final dateLabel = '${date.day} ${_months[date.month - 1]}';
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            _dayLabels[i],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: EC.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: EC.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (i == 6)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: EC.teal.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Most common',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: EC.teal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (sel)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: EC.teal,
                          )
                        else
                          const SizedBox(width: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 14 — BUILD PLAN
// ─────────────────────────────────────────────────────────────────────────────

class OPageBuildPlan extends StatefulWidget {
  final String firstName, goal;
  final Future<void> Function() onComplete;

  const OPageBuildPlan({
    super.key,
    required this.firstName,
    required this.goal,
    required this.onComplete,
  });

  @override
  State<OPageBuildPlan> createState() => _OPageBuildPlanState();
}

class _OPageBuildPlanState extends State<OPageBuildPlan>
    with SingleTickerProviderStateMixin {
  late AnimationController _ring;
  int _stage = 0;

  static const _steps = [
    'Analysing your profile...',
    'Calculating your zones...',
    'Building your training plan...',
    'Locking everything in...',
  ];

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..forward();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _stage = 1);
    });
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _stage = 2);
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _stage = 3);
    });
    Future.delayed(const Duration(milliseconds: 3400), () async {
      if (mounted) setState(() => _stage = 4);
      await widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).size.height * 0.25;
    return Padding(
      padding: ET.pagePad,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPad),
          SizedBox(
            width: 110,
            height: 110,
            child: AnimatedBuilder(
              animation: _ring,
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(110, 110),
                    painter: _RingPainter(_ring.value),
                  ),
                  Text(
                    '${(_ring.value * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: EC.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          ...List.generate(_steps.length, (i) {
            final done = _stage > i;
            final active = _stage == i;
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 350),
              opacity: _stage >= i ? 1.0 : 0.2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? EC.teal
                            : active
                            ? EC.surface2
                            : EC.surface,
                        border: Border.all(
                          color: done
                              ? EC.teal
                              : active
                              ? EC.teal.withOpacity(0.5)
                              : EC.border,
                          width: 1.5,
                        ),
                      ),
                      child: done
                          ? const Icon(Icons.check, size: 13, color: EC.black)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _steps[i],
                      style: TextStyle(
                        fontSize: 14,
                        color: done ? EC.textPrimary : EC.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = EC.surface2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..color = EC.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE — WEEKLY MILEAGE
// ─────────────────────────────────────────────────────────────────────────────

class OPageWeeklyMileage extends StatefulWidget {
  final double weeklyKm;
  final String? goalRace;
  final int runsPerWeek; // ← NEW: used to gate slider bounds
  final ValueChanged<double> onChanged;

  const OPageWeeklyMileage({
    super.key,
    required this.weeklyKm,
    required this.onChanged,
    required this.runsPerWeek, // ← NEW: required
    this.goalRace,
  });

  @override
  State<OPageWeeklyMileage> createState() => _OPageWeeklyMileageState();
}

class _OPageWeeklyMileageState extends State<OPageWeeklyMileage> {
  late TextEditingController _ctrl;
  static const double _step = 5;

  /// Get range from ArchetypeTable based on race + days.
  WeeklyKmRange get _range => WeeklyKmRange.forRaceAndDays(
    race: widget.goalRace ?? '10k',
    days: widget.runsPerWeek,
  );

  @override
  void initState() {
    super.initState();
    // Prefill with default from table if user hasn't set a value yet.
    final initial = widget.weeklyKm > 0 ? widget.weeklyKm : _range.defaultKm;
    _ctrl = TextEditingController(text: initial.round().toString());
    if (widget.weeklyKm == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChanged(initial);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _increment() {
    final next = (widget.weeklyKm + _step).clamp(_range.min, _range.max);
    _update(next);
  }

  void _decrement() {
    final next = (widget.weeklyKm - _step).clamp(_range.min, _range.max);
    _update(next);
  }

  void _update(double value) {
    HapticFeedback.selectionClick();
    widget.onChanged(value);
    _ctrl.text = value.round().toString();
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _onTyped(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed != null && parsed >= _range.min && parsed <= _range.max) {
      widget.onChanged(parsed);
    }
  }

  String _hint(double km) {
    if (km < _range.min) {
      final raceName = switch (widget.goalRace) {
        '10k' => '10K',
        'half_marathon' => 'half marathon',
        'marathon' => 'marathon',
        _ => '5K',
      };
      return 'Below the recommended base for a $raceName with ${widget.runsPerWeek} days';
    }
    if (km > _range.max * 0.9)
      return 'High volume — Max will manage load carefully';
    if (km <= 25)
      return 'Just getting started — Max will build you up gradually';
    if (km <= 40) return 'Building a base — good foundation to work from';
    if (km <= 60) return 'Solid volume — Max can push with real structure';
    return 'High mileage — Max will train you seriously';
  }

  bool get _isBelowMin => widget.weeklyKm > 0 && widget.weeklyKm < _range.min;

  @override
  Widget build(BuildContext context) {
    final km = widget.weeklyKm;
    final hasValue = km > 0;
    final belowMin = _isBelowMin;

    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Training volume'),
          const SizedBox(height: 8),
          const _Title('How far do you\nrun each week?'),
          const SizedBox(height: 6),
          const _Sub(
            'Average over the last 2–4 weeks. Be honest — not your best week.',
          ),
          const SizedBox(height: 8),
          // Range hint
          Text(
            '${_range.min.round()}–${_range.max.round()} km for ${widget.runsPerWeek} days',
            style: const TextStyle(fontSize: 12, color: EC.muted),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: km > _range.min ? _decrement : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: EC.surface,
                    borderRadius: BorderRadius.circular(ET.cardRadius),
                    border: Border.all(
                      color: belowMin
                          ? EC.amber
                          : hasValue
                          ? EC.teal
                          : EC.border,
                      width: hasValue ? 1.5 : ET.borderWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IntrinsicWidth(
                        child: TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: EC.textPrimary,
                            letterSpacing: -1,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0',
                            hintStyle: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: EC.muted,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          onChanged: _onTyped,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'km',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: EC.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: km < _range.max ? _increment : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'per week',
              style: TextStyle(fontSize: 12, color: EC.muted),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: hasValue
                ? Container(
                    key: ValueKey(_hint(km)),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: belowMin
                          ? EC.amber.withOpacity(0.07)
                          : EC.teal.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: belowMin
                            ? EC.amber.withOpacity(0.3)
                            : EC.teal.withOpacity(0.2),
                        width: ET.borderWidth,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          belowMin
                              ? Icons.warning_amber_rounded
                              : Icons.bolt_rounded,
                          size: 16,
                          color: belowMin ? EC.amber : EC.teal,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hint(km),
                            style: TextStyle(
                              fontSize: 13,
                              color: belowMin ? EC.amber : EC.teal,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? EC.surface2 : EC.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? EC.border : EC.surface,
            width: ET.borderWidth,
          ),
        ),
        child: Icon(icon, size: 24, color: enabled ? EC.textPrimary : EC.muted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RACE TIME PROJECTION ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class _RaceProjection {
  final int currentTimeSec;
  final double paceDistanceKm;
  final int planWeeks;
  final String experienceLevel;

  static const _distances = {
    '5k': 5.0,
    '10k': 10.0,
    'half_marathon': 21.0975,
    'marathon': 42.195,
  };

  static const _vdotGainPer12Weeks = {
    'beginner': 3.0,
    'intermediate': 2.0,
    'advanced': 1.0,
  };

  static const _vdotPaceTable = {
    30: 440.0,
    32: 422.0,
    34: 405.0,
    36: 390.0,
    38: 375.0,
    40: 361.0,
    42: 348.0,
    44: 336.0,
    46: 325.0,
    48: 314.0,
    50: 304.0,
    52: 295.0,
    54: 286.0,
    56: 278.0,
    58: 270.0,
    60: 263.0,
    62: 256.0,
    64: 249.0,
    66: 243.0,
    68: 237.0,
    70: 232.0,
  };

  const _RaceProjection({
    required this.currentTimeSec,
    required this.paceDistanceKm,
    required this.planWeeks,
    required this.experienceLevel,
  });

  double _riegel(double fromSec, double fromKm, double toKm) =>
      fromSec * pow(toKm / fromKm, 1.06);

  double _paceSec(int vdot) {
    final keys = _vdotPaceTable.keys.toList()..sort();
    if (vdot <= keys.first) return _vdotPaceTable[keys.first]!;
    if (vdot >= keys.last) return _vdotPaceTable[keys.last]!;
    for (int i = 0; i < keys.length - 1; i++) {
      if (vdot >= keys[i] && vdot <= keys[i + 1]) {
        final lo = _vdotPaceTable[keys[i]]!;
        final hi = _vdotPaceTable[keys[i + 1]]!;
        final t = (vdot - keys[i]) / (keys[i + 1] - keys[i]);
        return lo + (hi - lo) * t;
      }
    }
    return 361.0;
  }

  int get _currentVdot {
    final fiveKEquivSec = _riegel(
      currentTimeSec.toDouble(),
      paceDistanceKm,
      5.0,
    );
    final paceSec = fiveKEquivSec / 5.0;
    final keys = _vdotPaceTable.keys.toList()..sort();
    for (int i = 0; i < keys.length - 1; i++) {
      final lo = _vdotPaceTable[keys[i]]!;
      final hi = _vdotPaceTable[keys[i + 1]]!;
      if (paceSec <= lo && paceSec >= hi) {
        final t = (lo - paceSec) / (lo - hi);
        return (keys[i] + t * (keys[i + 1] - keys[i])).round();
      }
    }
    return paceSec > _vdotPaceTable[keys.first]! ? keys.first : keys.last;
  }

  int get _projectedVdot {
    final gainPer12 = _vdotGainPer12Weeks[experienceLevel] ?? 2.0;
    final gain = (gainPer12 * planWeeks / 12).round();
    return (_currentVdot + gain).clamp(30, 85);
  }

  int currentSec(String distKey) {
    final km = _distances[distKey]!;
    return _riegel(currentTimeSec.toDouble(), paceDistanceKm, km).round();
  }

  int projectedSec(String distKey) {
    final improvementRatio = _paceSec(_projectedVdot) / _paceSec(_currentVdot);
    return (currentSec(distKey) * improvementRatio).round();
  }

  int deltaSec(String distKey) => projectedSec(distKey) - currentSec(distKey);
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 15 — WELCOME
// ─────────────────────────────────────────────────────────────────────────────

class OPageWelcome extends StatelessWidget {
  final String firstName;
  final String goal;
  final int vdot;
  final int planWeeks;
  final String experienceLevel;
  final int currentTimeSec;
  final double paceDistanceKm;
  final VoidCallback onContinue;

  static const _distanceKeys = ['5k', '10k', 'half_marathon', 'marathon'];
  static const _distanceLabels = ['5K', '10K', '21.1', '42.2'];
  static const _distanceColors = [EC.teal, EC.violet, EC.orange, EC.red];

  const OPageWelcome({
    super.key,
    required this.firstName,
    required this.goal,
    required this.vdot,
    required this.planWeeks,
    required this.experienceLevel,
    required this.currentTimeSec,
    required this.paceDistanceKm,
    required this.onContinue,
  });

  String get _goalLabel => switch (goal) {
    '10k' => '10K',
    'half_marathon' => 'Half Marathon',
    'marathon' => 'Marathon',
    _ => '5K',
  };

  String get _goalDistKey => switch (goal) {
    '10k' => '10k',
    'half_marathon' => 'half_marathon',
    'marathon' => 'marathon',
    _ => '5k',
  };

  String _fmt(int totalSec) {
    if (totalSec <= 0) return '--:--';
    if (totalSec >= 3600) {
      final h = totalSec ~/ 3600;
      final m = (totalSec % 3600) ~/ 60;
      final s = totalSec % 60;
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _fmtDelta(int deltaSec) {
    final abs = deltaSec.abs();
    final sign = deltaSec < 0 ? '-' : '+';
    if (abs >= 3600) {
      final h = abs ~/ 3600;
      final m = (abs % 3600) ~/ 60;
      return '$sign${h}h ${m}m';
    }
    final m = abs ~/ 60;
    final s = abs % 60;
    if (m == 0) return '$sign${s}s';
    if (s == 0) return '$sign${m}m';
    return '$sign${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final proj = _RaceProjection(
      currentTimeSec: currentTimeSec,
      paceDistanceKm: paceDistanceKm,
      planWeeks: planWeeks,
      experienceLevel: experienceLevel,
    );

    final goalCurrent = proj.currentSec(_goalDistKey);
    final goalProjected = proj.projectedSec(_goalDistKey);

    return SingleChildScrollView(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: EC.textPrimary,
                height: 1.2,
                letterSpacing: -0.5,
              ),
              children: [
                const TextSpan(text: "Welcome,\n"),
                TextSpan(
                  text: '$firstName.',
                  style: const TextStyle(color: EC.teal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Your $_goalLabel plan is locked in.\nMax is ready when you are.",
            style: const TextStyle(
              fontSize: 15,
              color: EC.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(ET.cardRadius),
              border: Border.all(color: EC.teal.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: EC.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _goalLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: EC.teal,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PROJECTED TARGET',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: EC.muted,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOW',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: EC.muted,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmt(goalCurrent),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: EC.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 1.5,
                            color: EC.teal.withOpacity(0.4),
                          ),
                          const Icon(
                            Icons.directions_run_rounded,
                            size: 18,
                            color: EC.teal,
                          ),
                          Container(
                            width: 28,
                            height: 1.5,
                            color: EC.teal.withOpacity(0.4),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IN $planWeeks WEEKS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: EC.muted,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmt(goalProjected),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: EC.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: EC.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _fmtDelta(proj.deltaSec(_goalDistKey)),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: EC.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(ET.cardRadius),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 52),
                    Expanded(
                      child: Text(
                        'Current',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: EC.muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: Text(
                        'In $planWeeks weeks',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: EC.teal,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: EC.border, height: 1),
                const SizedBox(height: 14),
                ...List.generate(_distanceKeys.length, (i) {
                  final key = _distanceKeys[i];
                  final label = _distanceLabels[i];
                  final color = _distanceColors[i];
                  final curSec = proj.currentSec(key);
                  final projSec = proj.projectedSec(key);
                  final delta = proj.deltaSec(key);
                  final isGoal = key == _goalDistKey;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _fmt(curSec),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isGoal ? EC.textPrimary : EC.textSecondary,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _dot(EC.muted),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.directions_run_rounded,
                                size: 12,
                                color: EC.teal,
                              ),
                              const SizedBox(width: 2),
                              _dot(EC.muted),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                _fmt(projSec),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isGoal
                                      ? EC.textPrimary
                                      : EC.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fmtDelta(delta),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: EC.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(color: EC.border, height: 1),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: EC.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Projected after consistent plan completion. '
                        'Times are calculated using your vDOT $vdot '
                        'and Riegel race equivalence formula.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: EC.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: EC.teal,
                foregroundColor: EC.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ET.radius),
                ),
              ),
              child: const Text(
                "Let's get to work",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 3,
    height: 3,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// NEW RACE-FIRST FUNNEL PAGES
// ═════════════════════════════════════════════════════════════════════════════

const _months3 = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _wkd3 = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dLabel(DateTime d) =>
    '${_wkd3[d.weekday - 1]} ${d.day} ${_months3[d.month - 1]}';

String _fmtHMS(int s) {
  if (s <= 0) return '--:--';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _goalLabelFor(String goal) => switch (goal) {
  '10k' => '10K',
  'half_marathon' => 'Half Marathon',
  'marathon' => 'Marathon',
  _ => '5K',
};

// ── Data holders shared with OnboardingScreen ────────────────────────────────

class PlanStartOption {
  final DateTime startDate;
  final int weeks;
  final bool isToday;
  const PlanStartOption({
    required this.startDate,
    required this.weeks,
    required this.isToday,
  });
}

enum TargetTimeMode { beat, finish }

typedef RaceSelected =
    void Function({
      String? id,
      required String name,
      String? city,
      required DateTime date,
      String? distanceKey,
    });

String _ordinal(int d) {
  if (d >= 11 && d <= 13) return 'th';
  switch (d % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RACE PICKER
// ─────────────────────────────────────────────────────────────────────────────

class OPageRacePicker extends StatefulWidget {
  final String? raceName;
  final DateTime? raceDate;
  final String? goal;
  final RaceSelected onSelect;

  /// The top-left X. Goes back to the goal screen.
  final VoidCallback onClose;

  /// Called once a race + its distance are locked in — advances to the next page.
  final VoidCallback onAdvance;

  const OPageRacePicker({
    super.key,
    required this.raceName,
    required this.raceDate,
    required this.goal,
    required this.onSelect,
    required this.onClose,
    required this.onAdvance,
  });

  @override
  State<OPageRacePicker> createState() => _OPageRacePickerState();
}

class _OPageRacePickerState extends State<OPageRacePicker> {
  final _searchCtrl = TextEditingController();
  List<RaceListing> _all = [];
  bool _loading = true;

  String _query = '';
  String? _fDistance; // '5k'|'10k'|'half_marathon'|'marathon'
  String? _fCity;
  DateTime? _fDate;

  // manual entry
  bool _manual = false;
  final _manualNameCtrl = TextEditingController();
  DateTime? _manualDate;
  String? _manualDist;

  static const _distOpts = [
    ('5k', '5K'),
    ('10k', '10K'),
    ('half_marathon', 'HM'),
    ('marathon', 'FM'),
  ];
  static const _distChips = [
    ('5k', '5K'),
    ('10k', '10K'),
    ('half_marathon', 'HM'),
    ('marathon', 'FM'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // India-only for now — data quality (city/distance parsing) is only
    // solid there. Expand to other countries once this proves out.
    final rows = await RaceService.instance.upcomingRaces(
      country: 'India',
      limit: 250,
    );
    if (!mounted) return;
    setState(() {
      _all = rows;
      _loading = false;
    });
  }

  String? _distKey(String? label) {
    if (label == null) return null;
    final l = label.toLowerCase();
    if (l.contains('marathon') && !l.contains('half')) return 'marathon';
    if (l.contains('42') || l.contains('26.2')) return 'marathon';
    if (l.contains('half') || l.contains('21') || l.contains('13.1')) {
      return 'half_marathon';
    }
    if (l.contains('10k') || l.contains('10 k') || l.contains('10km')) {
      return '10k';
    }
    if (l.contains('5k') || l.contains('5 k') || l.contains('5km')) return '5k';
    return null;
  }

  List<String> get _cities =>
      _all
          .map((r) => r.city)
          .whereType<String>()
          .where((c) => c.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<RaceListing> get _filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((r) {
      if (q.isNotEmpty) {
        final hay = '${r.name} ${r.city ?? ''} ${r.country ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_fDistance != null && _distKey(r.distanceLabel) != _fDistance) {
        return false;
      }
      if (_fCity != null && r.city != _fCity) return false;
      if (_fDate != null && r.raceDate.isAfter(_fDate!)) return false;
      return true;
    }).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onClose();
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 26, color: EC.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _manual ? _buildManual() : _buildBrowser()),
        ],
      ),
    );
  }

  // ── Browser ──────────────────────────────────────────────────────────────

  Widget _buildBrowser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What race are\nyou running?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: EC.textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Choose a race to train for',
            style: TextStyle(color: EC.textSecondary, fontSize: 14),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _manual = true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "Don't see your race?",
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _searchField(),
        const SizedBox(height: 16),
        _filterRow(),
        const SizedBox(height: 16),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: EC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EC.border, width: ET.borderWidth),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: EC.textPrimary, fontSize: 14),
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          hintText: 'Search for your race',
          hintStyle: TextStyle(color: EC.muted, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: EC.muted, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _filterRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _filterPill(
          'Date',
          _fDate == null ? null : _fmtDate(_fDate!),
          _openDateFilter,
          onClear: () => setState(() => _fDate = null),
        ),
        _filterPill(
          'Distance',
          _fDistance == null
              ? null
              : _distOpts.firstWhere((o) => o.$1 == _fDistance).$2,
          _openDistanceFilter,
          onClear: () => setState(() => _fDistance = null),
        ),
        _filterPill(
          'City',
          _fCity,
          _openCityFilter,
          onClear: () => setState(() => _fCity = null),
        ),
      ],
    );
  }

  Widget _filterPill(
    String label,
    String? value,
    VoidCallback onTap, {
    VoidCallback? onClear,
  }) {
    final active = value != null;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: EC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? EC.teal : EC.border,
            width: active ? 1.2 : ET.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value ?? label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? EC.teal : EC.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            if (active && onClear != null)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onClear();
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 15, color: EC.teal),
                ),
              )
            else
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: active ? EC.teal : EC.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: EC.teal, strokeWidth: 2),
      );
    }
    final rows = _filtered;
    if (rows.isEmpty) return _empty();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _raceCard(rows[i]),
    );
  }

  Widget _raceCard(RaceListing r) {
    return GestureDetector(
      onTap: () => _choose(r),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: EC.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EC.border, width: ET.borderWidth),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: EC.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _fmtDate(r.raceDate),
                        style: const TextStyle(
                          color: EC.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    r.name,
                    style: const TextStyle(
                      color: EC.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.military_tech_outlined,
                        size: 15,
                        color: EC.textSecondary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _metaLine(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: EC.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: EC.muted, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, color: EC.muted, size: 32),
            const SizedBox(height: 12),
            const Text(
              'No races match those filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EC.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() {
                _query = '';
                _searchCtrl.clear();
                _fDistance = null;
                _fCity = null;
                _fDate = null;
              }),
              child: const Text(
                'Clear filters',
                style: TextStyle(
                  color: EC.teal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${_months3[d.month - 1]} ${d.day}${_ordinal(d.day)}, ${d.year}';

  String _metaLine(RaceListing r) {
    final dist = r.distanceLabel?.trim();
    final loc = [
      r.city,
      r.country,
    ].where((e) => e != null && e.trim().isNotEmpty).join(', ');
    final parts = [
      if (dist != null && dist.isNotEmpty) dist,
      if (loc.isNotEmpty) loc,
    ];
    return parts.isEmpty ? 'Race' : parts.join('  •  ');
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void _choose(RaceListing r) {
    HapticFeedback.lightImpact();
    final k = _distKey(r.distanceLabel);
    if (k != null) {
      widget.onSelect(
        id: r.id,
        name: r.name,
        city: r.city,
        date: r.raceDate,
        distanceKey: k,
      );
      widget.onAdvance();
    } else {
      _askDistance(r);
    }
  }

  Future<void> _askDistance(RaceListing r) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.name,
                style: const TextStyle(
                  color: EC.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Which distance are you running?',
                style: TextStyle(color: EC.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _distChips.map((c) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onSelect(
                        id: r.id,
                        name: r.name,
                        city: r.city,
                        date: r.raceDate,
                        distanceKey: c.$1,
                      );
                      widget.onAdvance();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: EC.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: EC.border,
                          width: ET.borderWidth,
                        ),
                      ),
                      child: Text(
                        c.$2,
                        style: const TextStyle(
                          color: EC.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter sheets ────────────────────────────────────────────────────────

  Future<void> _openDateFilter() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fDate ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: EC.teal,
            onPrimary: EC.black,
            surface: EC.surface,
            onSurface: EC.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _fDate = picked);
  }

  Future<void> _openDistanceFilter() => _openSheet<String>(
    title: 'Distance',
    current: _fDistance,
    options: [for (final o in _distOpts) (o.$1, o.$2)],
    onPick: (v) => setState(() => _fDistance = v),
  );

  /// City filter — a live search field over the cities present in loaded
  /// races, not a plain scrolling list.
  Future<void> _openCityFilter() {
    final ctrl = TextEditingController();
    var query = '';
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: EC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final q = query.trim().toLowerCase();
          final matches = q.isEmpty
              ? _cities
              : _cities.where((c) => c.toLowerCase().contains(q)).toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Text(
                      'City',
                      style: TextStyle(
                        color: EC.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: EC.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: EC.border,
                          width: ET.borderWidth,
                        ),
                      ),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        style: const TextStyle(
                          color: EC.textPrimary,
                          fontSize: 14,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search city',
                          hintStyle: TextStyle(color: EC.muted, fontSize: 14),
                          prefixIcon: Icon(
                            Icons.search,
                            color: EC.muted,
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in matches)
                          _sheetRow(c, _fCity == c, () {
                            Navigator.pop(ctx);
                            setState(() => _fCity = c);
                          }),
                        if (matches.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 20,
                            ),
                            child: Text(
                              'No cities match',
                              style: TextStyle(
                                color: EC.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSheet<T>({
    required String title,
    required T? current,
    required List<(T, String)> options,
    required ValueChanged<T?> onPick,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: EC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: EC.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      _sheetRow(o.$2, current == o.$1, () {
                        Navigator.pop(ctx);
                        onPick(o.$1);
                      }),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? EC.teal : EC.textPrimary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: EC.teal, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Manual entry ─────────────────────────────────────────────────────────

  bool get _manualReady =>
      _manualNameCtrl.text.trim().isNotEmpty &&
      _manualDate != null &&
      _manualDist != null;

  Widget _buildManual() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        GestureDetector(
          onTap: () => setState(() => _manual = false),
          child: const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios_new, size: 15, color: EC.teal),
                SizedBox(width: 6),
                Text(
                  'Back to races',
                  style: TextStyle(
                    color: EC.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Text(
          'Add your race',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: EC.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "We'll build your plan around the date and distance you give.",
          style: TextStyle(color: EC.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 22),
        _manualLabel('RACE NAME'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: EC.surface,
            borderRadius: BorderRadius.circular(ET.cardRadius),
            border: Border.all(color: EC.border, width: ET.borderWidth),
          ),
          child: TextField(
            controller: _manualNameCtrl,
            style: const TextStyle(color: EC.textPrimary, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'e.g. Bengaluru Marathon',
              hintStyle: TextStyle(color: EC.muted, fontSize: 14),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _manualLabel('RACE DATE'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickManualDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(ET.cardRadius),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: EC.teal,
                  size: 17,
                ),
                const SizedBox(width: 12),
                Text(
                  _manualDate == null ? 'Pick a date' : _fmtDate(_manualDate!),
                  style: TextStyle(
                    color: _manualDate == null ? EC.muted : EC.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _manualLabel('DISTANCE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _distChips.map((c) {
            final sel = _manualDist == c.$1;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _manualDist = c.$1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: sel ? EC.teal : EC.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? EC.teal : EC.border,
                    width: ET.borderWidth,
                  ),
                ),
                child: Text(
                  c.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? EC.black : EC.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _manualReady
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onSelect(
                      id: null,
                      name: _manualNameCtrl.text.trim(),
                      city: null,
                      date: _manualDate!,
                      distanceKey: _manualDist,
                    );
                    widget.onAdvance();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: EC.teal,
              foregroundColor: EC.black,
              disabledBackgroundColor: EC.surface2,
              disabledForegroundColor: EC.muted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ET.radius),
              ),
            ),
            child: const Text(
              'Use this race',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _manualLabel(String t) => Text(
    t,
    style: const TextStyle(
      color: EC.muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );

  Future<void> _pickManualDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 70)),
      firstDate: now.add(const Duration(days: 14)),
      lastDate: now.add(const Duration(days: 500)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: EC.teal,
            onPrimary: EC.black,
            surface: EC.surface,
            onSurface: EC.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _manualDate = picked);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAST-MONTH VOLUME
// ─────────────────────────────────────────────────────────────────────────────

class OPagePastMonth extends StatelessWidget {
  final String? selected;
  final void Function(String bucket, double km) onSelect;
  const OPagePastMonth({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  // (label, representative total km for the last 4 weeks)
  static const _buckets = <(String, double)>[
    ('0 km — just starting out', 0),
    ('Under 25 km', 13),
    ('25–50 km', 37.5),
    ('50–100 km', 75),
    ('100–150 km', 125),
    ('150 km or more', 175),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Recent training'),
          const SizedBox(height: 8),
          const _Title('How much have you\nrun in the past month?'),
          const SizedBox(height: 6),
          const _Sub(
            'A rough total is fine. This sets a safe starting volume.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _buckets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final (label, km) = _buckets[i];
                final sel = selected == label;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(label, km);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 17,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: EC.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (sel)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: EC.teal,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RACE GOAL
// ─────────────────────────────────────────────────────────────────────────────

class OPageRaceGoal extends StatelessWidget {
  final String? selected;
  final String goal;
  final ValueChanged<String> onSelect;
  const OPageRaceGoal({
    super.key,
    required this.selected,
    required this.goal,
    required this.onSelect,
  });

  static const _opts = [
    (
      'pr',
      Icons.trending_up_rounded,
      Color(0xFF3D0000),
      EC.red,
      'Set a PR',
      'Beat a time I\'ve already run',
    ),
    (
      'target_time',
      Icons.timer_outlined,
      Color(0xFF3D1A00),
      EC.orange,
      'Run a specific time',
      'I have a finish time in mind',
    ),
    (
      'finish',
      Icons.flag_outlined,
      Color(0xFF003D35),
      EC.teal,
      'Just complete it',
      'Cross the line feeling strong',
    ),
    (
      'enjoy',
      Icons.celebration_outlined,
      Color(0xFF1E1040),
      EC.violet,
      'Enjoy the experience',
      'Have fun, no pressure on the clock',
    ),
    (
      'undecided',
      Icons.help_outline_rounded,
      Color(0xFF10202E),
      EC.teal,
      'Not sure yet',
      'Decide as training goes on',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _Label('Your ${_goalLabelFor(goal)} goal'),
          const SizedBox(height: 8),
          const _Title("What do you want\nfrom race day?"),
          const SizedBox(height: 6),
          const _Sub('This shapes how hard the plan pushes you.'),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _opts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final (key, icon, bg, fg, label, sub) = _opts[i];
                return _Row(
                  leading: _iconBox(bg, icon, fg),
                  label: label,
                  sub: sub,
                  selected: selected == key,
                  onTap: () => onSelect(key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARGET TIME  (shown only for pr / target_time)
// ─────────────────────────────────────────────────────────────────────────────

class OPageTargetTime extends StatelessWidget {
  final TargetTimeMode mode;
  final String goal;
  final int? seconds;
  final ValueChanged<int> onChanged;

  const OPageTargetTime({
    super.key,
    required this.mode,
    required this.goal,
    required this.seconds,
    required this.onChanged,
  });

  int get _h => (seconds ?? 0) ~/ 3600;
  int get _m => ((seconds ?? 0) % 3600) ~/ 60;
  int get _s => (seconds ?? 0) % 60;

  void _emit({int? h, int? m, int? s}) =>
      onChanged((h ?? _h) * 3600 + (m ?? _m) * 60 + (s ?? _s));

  @override
  Widget build(BuildContext context) {
    final title = mode == TargetTimeMode.beat
        ? 'What time do you\nwant to beat?'
        : "What's your target\nfinish time?";
    final sub = mode == TargetTimeMode.beat
        ? 'Your current best for the ${_goalLabelFor(goal)} — the plan will aim to take you under it.'
        : 'Your goal ${_goalLabelFor(goal)} time. Be ambitious but realistic.';

    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          _Label(mode == TargetTimeMode.beat ? 'Time to beat' : 'Target time'),
          const SizedBox(height: 8),
          _Title(title),
          const SizedBox(height: 6),
          _Sub(sub),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _fmtHMS(seconds ?? 0),
              style: const TextStyle(
                color: EC.teal,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _drum('HH', 8, _h, (v) => _emit(h: v))),
                _colon(),
                Expanded(child: _drum('MM', 60, _m, (v) => _emit(m: v))),
                _colon(),
                Expanded(child: _drum('SS', 60, _s, (v) => _emit(s: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colon() => const Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Text(
      ':',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w300,
        color: EC.muted,
      ),
    ),
  );

  Widget _drum(String label, int count, int selected, ValueChanged<int> onSel) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: EC.muted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: selected,
              ),
              itemExtent: 44,
              onSelectedItemChanged: onSel,
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: EC.teal.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                ),
              ),
              children: List.generate(
                count,
                (i) => Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: EC.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RUNS PER WEEK  (slider + live plan preview)
// ─────────────────────────────────────────────────────────────────────────────

class OPageRunsPerWeek extends StatelessWidget {
  final int runsPerWeek;
  final double baselineWeeklyKm;
  final String goal;
  final String experienceBridged;
  final ValueChanged<int> onChanged;

  const OPageRunsPerWeek({
    super.key,
    required this.runsPerWeek,
    required this.baselineWeeklyKm,
    required this.goal,
    required this.experienceBridged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final g = VolumeGuidance.resolve(
      goal: goal,
      experienceBridged: experienceBridged,
      baselineWeeklyKm: baselineWeeklyKm,
      selectedRuns: runsPerWeek,
    );

    // The ceiling moves with the athlete's base, so it can land on the floor.
    final locked = g.maxRuns <= kMinRunsPerWeek;
    final atRecommended = runsPerWeek == g.recommendedRuns;

    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) {
        final unit = UnitUtils.unitLabel(useMiles);
        final lo = UnitUtils.displayDistance(
          g.loKm.toDouble(),
          useMiles,
        ).round();
        final hi = UnitUtils.displayDistance(
          g.hiKm.toDouble(),
          useMiles,
        ).round();

        return SingleChildScrollView(
          padding: ET.pagePad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const _Label('Your week'),
              const SizedBox(height: 8),
              const _Title('How many days a\nweek can you run?'),
              const SizedBox(height: 6),
              const _Sub(
                'This sets your weekly volume. We build up from what you run '
                'now, so pick what fits your life.',
              ),
              const SizedBox(height: 28),

              SizedBox(
                height: 26,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: atRecommended ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: EC.teal.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 13, color: EC.teal),
                          SizedBox(width: 5),
                          Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              color: EC.teal,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '$runsPerWeek days',
                  style: const TextStyle(
                    color: EC.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: EC.teal,
                  inactiveTrackColor: EC.surface2,
                  thumbColor: EC.teal,
                  overlayColor: EC.teal.withOpacity(0.15),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: runsPerWeek
                      .clamp(kMinRunsPerWeek, g.maxRuns)
                      .toDouble(),
                  min: kMinRunsPerWeek.toDouble(),
                  max: g.maxRuns.toDouble(),
                  divisions: locked ? null : g.maxRuns - kMinRunsPerWeek,
                  onChanged: locked
                      ? null
                      : (v) {
                          HapticFeedback.selectionClick();
                          onChanged(v.round());
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$kMinRunsPerWeek',
                      style: const TextStyle(color: EC.muted, fontSize: 12),
                    ),
                    Text(
                      '${g.maxRuns}',
                      style: const TextStyle(color: EC.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),

              if (g.maxRuns < kMaxRunsPerWeek) ...[
                const SizedBox(height: 12),
                _GuidanceNote(
                  icon: Icons.shield_outlined,
                  tone: EC.textSecondary,
                  text:
                      'Capped at ${g.maxRuns} days for now — that is what your '
                      'current ${UnitUtils.displayDistance(baselineWeeklyKm, useMiles).round()} '
                      '$unit a week safely supports. It opens up as you build.',
                ),
              ],

              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: EC.surface,
                  borderRadius: BorderRadius.circular(ET.cardRadius),
                  border: Border.all(color: EC.border, width: ET.borderWidth),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR PLAN AT A GLANCE',
                      style: TextStyle(
                        color: EC.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _planRow(
                      Icons.route_outlined,
                      'Weekly distance',
                      '$lo–$hi $unit',
                    ),
                    const SizedBox(height: 10),
                    _planRow(
                      Icons.calendar_month_outlined,
                      'Runs per week',
                      '$runsPerWeek',
                    ),
                    const SizedBox(height: 10),
                    _planRow(
                      Icons.bolt_rounded,
                      'Hard workouts',
                      g.qualitySessions == 0
                          ? 'None — all easy running'
                          : '${g.qualitySessions} of $runsPerWeek runs',
                    ),
                  ],
                ),
              ),

              if (g.isStretch) ...[
                const SizedBox(height: 14),
                _GuidanceNote(
                  icon: Icons.trending_up_rounded,
                  tone: EC.amber,
                  text:
                      'That is a big step up from your recent '
                      '${UnitUtils.displayDistance(baselineWeeklyKm, useMiles).round()} '
                      '$unit a week. We will ramp you into it gradually.',
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _planRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 16, color: EC.teal),
      const SizedBox(width: 10),
      Text(
        label,
        style: const TextStyle(color: EC.textSecondary, fontSize: 13),
      ),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: EC.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

/// Small inline note used for the safety cap and the stretch warning.
class _GuidanceNote extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String text;

  const _GuidanceNote({
    required this.icon,
    required this.tone,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: tone),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: tone, fontSize: 12, height: 1.45),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAN START
// ─────────────────────────────────────────────────────────────────────────────

class OPagePlanStart extends StatelessWidget {
  final List<PlanStartOption> options;
  final DateTime? selectedStart;
  final ValueChanged<PlanStartOption> onSelect;
  final PlanRunway runway;
  final String goal;

  const OPagePlanStart({
    super.key,
    required this.options,
    required this.selectedStart,
    required this.onSelect,
    required this.runway,
    required this.goal,
  });

  /// One component, three verdicts — see PlanRunway.
  String get _subtitle => switch (runway.regime) {
    RunwayRegime.short =>
      'Both options land you on race day. With '
          '${runway.weeksAvailable} weeks we will compress the build.',
    RunwayRegime.matched =>
      'You have the runway to do this properly. Starting sooner gives the '
          'plan more room.',
    RunwayRegime.surplus =>
      'You have more time than a ${PlanRunway.labelFor(goal)} build needs, so '
          'we will open with a base phase rather than make you wait.',
  };

  @override
  Widget build(BuildContext context) {
    final warning = runway.warningFor(goal);

    return SingleChildScrollView(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Start date'),
          const SizedBox(height: 8),
          const _Title('When do you want\nto start?'),
          const SizedBox(height: 6),
          _Sub(_subtitle),
          const SizedBox(height: 28),
          ...options.map((o) {
            final sel =
                selectedStart != null &&
                selectedStart!.year == o.startDate.year &&
                selectedStart!.month == o.startDate.month &&
                selectedStart!.day == o.startDate.day;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(o);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: sel ? EC.surface2 : EC.surface,
                    borderRadius: BorderRadius.circular(ET.cardRadius),
                    border: Border.all(
                      color: sel ? EC.teal : EC.border,
                      width: sel ? 1.5 : ET.borderWidth,
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.isToday
                                ? 'Start today'
                                : 'Start ${_wkd3[o.startDate.weekday - 1]}',
                            style: const TextStyle(
                              color: EC.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_dLabel(o.startDate)} ${o.startDate.year}',
                            style: const TextStyle(
                              color: EC.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            runway.verdict,
                            style: TextStyle(
                              color: runway.regime == RunwayRegime.matched
                                  ? EC.teal
                                  : EC.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? EC.teal.withOpacity(0.15) : EC.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${o.weeks} wk',
                          style: TextStyle(
                            color: sel ? EC.teal : EC.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (warning != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: EC.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(ET.cardRadius),
                border: Border.all(color: EC.amber.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: EC.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warning,
                      style: const TextStyle(
                        color: EC.amber,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
