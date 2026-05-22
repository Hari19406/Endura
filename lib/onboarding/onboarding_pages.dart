import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'onboarding_screen.dart' show EC, ET;

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
            letterSpacing: 0.8),
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
            letterSpacing: -0.3),
      );
}

class _Sub extends StatelessWidget {
  final String text;
  const _Sub(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 14,
            color: EC.textSecondary,
            height: 1.55),
      );
}

/// Full-width selection row — dark card with teal border when selected
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
        child: Row(children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? EC.textPrimary : EC.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub!,
                      style: const TextStyle(
                          fontSize: 12.5, color: EC.textSecondary)),
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
                  color: selected ? EC.teal : EC.border, width: 1.5),
            ),
            child: selected
                ? const Icon(Icons.check, size: 13, color: EC.black)
                : null,
          ),
        ]),
      ),
    );
  }
}

Widget _iconBox(Color bg, IconData icon, Color fg) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10)),
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
                        0.3 + 0.3 * sin(loopCtrl.value * 2 * pi)),
                    width: 1.5),
              ),
              child: const Icon(Icons.directions_run_rounded,
                  size: 36, color: EC.teal),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Endura',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EC.teal,
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: EC.textPrimary,
                  height: 1.2,
                  letterSpacing: -0.5),
              children: [
                TextSpan(text: "Meet "),
                TextSpan(
                    text: 'Max',
                    style: TextStyle(color: EC.teal)),
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
                height: 1.6),
          ),
          const SizedBox(height: 12),
          const Text('Takes about 2 minutes',
              style: TextStyle(fontSize: 12, color: EC.muted)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2 — GOAL
// ─────────────────────────────────────────────────────────────────────────────

class OPageGoal extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const OPageGoal({super.key, required this.selected, required this.onSelect});

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
          const _Sub('Pick your race. Max builds everything backwards from here.'),
          const SizedBox(height: 28),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _g('5k', '5K', 'The perfect starting race',
                    const Color(0xFF003D35), EC.teal),
                const SizedBox(height: 10),
                _g('10k', '10K', 'Step up the challenge',
                    const Color(0xFF1E1040), EC.violet),
                const SizedBox(height: 10),
                _g('half_marathon', 'Half Marathon', "The runner's milestone",
                    const Color(0xFF3D1A00), EC.orange),
                const SizedBox(height: 10),
                _g('marathon', 'Marathon', 'The ultimate test',
                    const Color(0xFF3D0000), EC.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _g(String key, String label, String sub, Color bg, Color fg) =>
      _Row(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(10)),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.3)),
          ),
        ),
        label: label,
        sub: sub,
        selected: selected == key,
        onTap: () => onSelect(key),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3 — EXPERIENCE
// ─────────────────────────────────────────────────────────────────────────────

class OPageExperience extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const OPageExperience(
      {super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          const _Label('Your background'),
          const SizedBox(height: 8),
          const _Title('How would you\ndescribe yourself?'),
          const SizedBox(height: 6),
          const _Sub(
              'Be honest — Max uses this to set the right intensity from day one.'),
          const SizedBox(height: 28),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFF003D35),
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('B',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.teal)),
              ),
            ),
            label: 'Beginner',
            sub: 'I can run 5K without stopping, in under 60 minutes',
            selected: selected == 'beginner',
            onTap: () => onSelect('beginner'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFF1E1040),
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('I',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.violet)),
              ),
            ),
            label: 'Intermediate',
            sub: 'I run regularly but don\'t follow a structured plan',
            selected: selected == 'intermediate',
            onTap: () => onSelect('intermediate'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFF3D1A00),
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('A',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.orange)),
              ),
            ),
            label: 'Advanced',
            sub: 'I run at least 10K and do structured interval training',
            selected: selected == 'advanced',
            onTap: () => onSelect('advanced'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 4 — BEST TIME  (CupertinoPicker drum scroll)
// ─────────────────────────────────────────────────────────────────────────────

class OPageBestTime extends StatelessWidget {
  final bool knowsTime;
  final String distance;
  final int hours, minutes, seconds;
  final ValueChanged<bool> onToggleKnows;
  final ValueChanged<String> onDistChanged;
  final ValueChanged<int> onHoursChanged;
  final ValueChanged<int> onMinsChanged;
  final ValueChanged<int> onSecsChanged;

  const OPageBestTime({
    super.key,
    required this.knowsTime,
    required this.distance,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onToggleKnows,
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
              'Use your most recent time — not your goal. Max needs your current fitness, not your dream.'),
          const SizedBox(height: 20),

          // ── Toggle ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: Row(children: [
              _tab('I know my time', knowsTime, () => onToggleKnows(true)),
              _tab("I'm not sure", !knowsTime, () => onToggleKnows(false)),
            ]),
          ),
          const SizedBox(height: 20),

          if (knowsTime) ...[
            // ── Distance tabs ──────────────────────────────────────
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
                            horizontal: 18, vertical: 9),
                        decoration: BoxDecoration(
                          color: sel ? EC.teal : EC.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? EC.teal : EC.border,
                              width: ET.borderWidth),
                        ),
                        child: Text(lbl,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    sel ? EC.black : EC.textSecondary)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── Live display ──────────────────────────────────────
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 14,
                      color: EC.textSecondary,
                      height: 1.5),
                  children: [
                    const TextSpan(text: 'I can currently run a '),
                    TextSpan(
                        text: _distLabel,
                        style: const TextStyle(
                            color: EC.teal,
                            fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' in '),
                    TextSpan(
                        text:
                            '${_pad(hours)}h ${_pad(minutes)}m ${_pad(seconds)}s',
                        style: const TextStyle(
                            color: EC.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Drum pickers ──────────────────────────────────────
            Expanded(
              child: Row(
                children: [
                  Expanded(
                      child: _drum(
                    label: 'HH',
                    count: 6,
                    selected: hours,
                    onChanged: onHoursChanged,
                  )),
                  _colon(),
                  Expanded(
                      child: _drum(
                    label: 'MM',
                    count: 60,
                    selected: minutes,
                    onChanged: onMinsChanged,
                  )),
                  _colon(),
                  Expanded(
                      child: _drum(
                    label: 'SS',
                    count: 60,
                    selected: seconds,
                    onChanged: onSecsChanged,
                  )),
                ],
              ),
            ),
          ] else ...[
            // ── Don't know state ───────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: EC.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: EC.border)),
                      child: const Center(
                        child: Text('?',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: EC.textPrimary)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "No problem.\nMax will calibrate your zones\nfrom your first few runs.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          color: EC.textSecondary,
                          height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tab(String label, bool sel, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: sel ? EC.teal : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? EC.black : EC.textSecondary)),
          ),
        ),
      );

  Widget _colon() => const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Text(':',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
                color: EC.muted)),
      );

  Widget _drum({
    required String label,
    required int count,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: EC.muted,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: EC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EC.border, width: ET.borderWidth),
            ),
            child: CupertinoPicker(
              scrollController:
                  FixedExtentScrollController(initialItem: selected),
              itemExtent: 44,
              onSelectedItemChanged: onChanged,
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(
                        color: EC.teal.withOpacity(0.5), width: 1),
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
                        color: EC.textPrimary),
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
  const OPageDaysCount(
      {super.key, required this.runsPerWeek, required this.onChanged});

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
              'Keep it realistic. Max will push you within what you can commit to.'),
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
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: sel ? EC.surface2 : EC.surface,
                        borderRadius: BorderRadius.circular(ET.cardRadius),
                        border: Border.all(
                          color: sel ? EC.teal : EC.border,
                          width: sel ? 1.5 : ET.borderWidth,
                        ),
                      ),
                      child: Row(children: [
                        Text(
                          '$n ${n == 1 ? 'Day' : 'Days'}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: EC.textPrimary),
                        ),
                        const Spacer(),
                        if (sel)
                          const Icon(Icons.check_circle_rounded,
                              size: 20, color: EC.teal),
                      ]),
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
    'Sunday'
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
              'Select every day you\'re free to run. Max picks the best ones.'),
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
                        fontWeight: FontWeight.w500),
                  )
                : remaining < 0
                    ? Text(
                        'Deselect ${-remaining} day${-remaining == 1 ? '' : 's'}',
                        key: ValueKey(remaining),
                        style: const TextStyle(
                            fontSize: 13, color: EC.amber),
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
                        horizontal: 18, vertical: 15),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(children: [
                      Text(_days[i],
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: EC.textPrimary)),
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
                              width: 1.5),
                        ),
                        child: sel
                            ? const Icon(Icons.check,
                                size: 14, color: EC.black)
                            : null,
                      ),
                    ]),
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
    'Sunday'
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
              'The long run is the cornerstone of your week. Pick a day when you have the most time.'),
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
                        horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: sel ? EC.surface2 : EC.surface,
                      borderRadius: BorderRadius.circular(ET.cardRadius),
                      border: Border.all(
                        color: sel ? EC.teal : EC.border,
                        width: sel ? 1.5 : ET.borderWidth,
                      ),
                    ),
                    child: Row(children: [
                      Text(_days[dayIdx],
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: EC.textPrimary)),
                      const Spacer(),
                      if (sel)
                        const Icon(Icons.check_circle_rounded,
                            size: 20, color: EC.teal),
                    ]),
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
  const OPageIntensity(
      {super.key, required this.selected, required this.onSelect});

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
              'Max builds your plan around this. You can adjust it anytime.'),
          const SizedBox(height: 28),
          _Row(
            leading: _iconBox(const Color(0xFF003D35),
                Icons.sentiment_satisfied_rounded, EC.teal),
            label: 'Finish comfortably',
            sub: 'Cross the line feeling strong',
            selected: selected == 'steady',
            onTap: () => onSelect('steady'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: _iconBox(const Color(0xFF1E1040),
                Icons.trending_up_rounded, EC.violet),
            label: 'Improve steadily',
            sub: 'Get faster week over week',
            selected: selected == 'structured',
            onTap: () => onSelect('structured'),
          ),
          const SizedBox(height: 10),
          _Row(
            leading: _iconBox(
                const Color(0xFF3D1A00), Icons.bolt_rounded, EC.orange),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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

          // ── Start date ──────────────────────────────────────────
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
                Text(_startLabel(widget.startDate),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.textPrimary)),
                const SizedBox(height: 12),
                Row(children: [
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
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: (!_sameDay(widget.startDate, today) &&
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
                          color: (!_sameDay(widget.startDate, today) &&
                                  !_sameDay(widget.startDate, tomorrow))
                              ? EC.black
                              : EC.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Plan length ─────────────────────────────────────────
          _sectionHead('PLAN LENGTH'),
          const SizedBox(height: 10),
          ..._weekOptions.map((w) {
            final endDate = widget.startDate.add(Duration(days: w * 7));
            const months = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: sel ? EC.surface2 : EC.surface,
                    borderRadius: BorderRadius.circular(ET.cardRadius),
                    border: Border.all(
                      color: sel ? EC.teal : EC.border,
                      width: sel ? 1.5 : ET.borderWidth,
                    ),
                  ),
                  child: Row(children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$w Weeks',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: EC.textPrimary)),
                        const SizedBox(height: 2),
                        Text(endLabel,
                            style: const TextStyle(
                                fontSize: 12, color: EC.textSecondary)),
                      ],
                    ),
                    const Spacer(),
                    if (sel)
                      const Icon(Icons.check_circle_rounded,
                          size: 20, color: EC.teal),
                  ]),
                ),
              ),
            );
          }),

          // ── I have a race ───────────────────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _pickRaceDate();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: widget.raceDate != null ? EC.surface2 : EC.surface,
                borderRadius: BorderRadius.circular(ET.cardRadius),
                border: Border.all(
                  color: widget.raceDate != null ? EC.teal : EC.border,
                  width: widget.raceDate != null ? 1.5 : ET.borderWidth,
                ),
              ),
              child: Row(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('I have a race date',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: EC.textPrimary)),
                    if (widget.raceDate != null) ...[
                      const SizedBox(height: 2),
                      Text(_raceLabel(widget.raceDate!),
                          style:
                              const TextStyle(fontSize: 12, color: EC.teal)),
                    ] else
                      const Text('Tap to pick your race date',
                          style: TextStyle(
                              fontSize: 12, color: EC.textSecondary)),
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
              ]),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHead(String t) => Text(t,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: EC.muted,
          letterSpacing: 1.2));

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
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? EC.black : EC.textSecondary)),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _raceLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
              'Max uses your age to personalise recovery, load, and intensity. Nothing else.'),
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
                    letterSpacing: 2),
              ),
              Row(children: [
                _dobField('DD', _day, 2),
                _sep(),
                _dobField('MM', _month, 2),
                _sep(),
                _dobField('YYYY', _year, 4),
              ]),
            ],
          ),
          if (widget.dob != null) ...[
            const SizedBox(height: 16),
            Builder(builder: (_) {
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
            }),
          ],
        ],
      ),
    );
  }

  Widget _sep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('/',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w200,
                color: EC.muted)),
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
                color: EC.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 14,
                  color: EC.muted,
                  fontWeight: FontWeight.w400),
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
  const OPageGender(
      {super.key, required this.selected, required this.onSelect});

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
              'Used only to personalise your training load calculations.'),
          const SizedBox(height: 32),
          _Row(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: EC.surface2,
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('M',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.teal)),
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
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('F',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.violet)),
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
                  borderRadius: BorderRadius.circular(10)),
              child: const Center(
                child: Text('O',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: EC.textSecondary)),
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
  final String firstName, lastName;
  final ValueChanged<String> onFirstChanged, onLastChanged;

  const OPageName({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.onFirstChanged,
    required this.onLastChanged,
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
              "We'll use your name to make every interaction feel personal."),
          const SizedBox(height: 40),
          _field('First name', firstName, onFirstChanged, TextInputAction.next),
          const SizedBox(height: 12),
          _field('Last name', lastName, onLastChanged, TextInputAction.done),
          const Spacer(),
          if (firstName.trim().isNotEmpty)
            Center(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 14, color: EC.textSecondary),
                  children: [
                    const TextSpan(text: "Max will call you "),
                    TextSpan(
                        text: firstName.trim(),
                        style: const TextStyle(
                            color: EC.teal,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _field(String hint, String value, ValueChanged<String> onChanged,
      TextInputAction action) {
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
            color: EC.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: EC.muted),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 13 — GENERATE PLAN
// ─────────────────────────────────────────────────────────────────────────────

class OPageGeneratePlan extends StatelessWidget {
  final String firstName, goal;
  final DateTime startDate;
  final int? planWeeks;
  final DateTime? raceDate;
  final int runsPerWeek;
  final List<int> selectedDays;
  final String? intensity;
  final int vdotScore;
  final VoidCallback onGenerate;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  const OPageGeneratePlan({
    super.key,
    required this.firstName,
    required this.goal,
    required this.startDate,
    required this.planWeeks,
    required this.raceDate,
    required this.runsPerWeek,
    required this.selectedDays,
    required this.intensity,
    required this.vdotScore,
    required this.onGenerate,
  });

  String get _goalLabel => switch (goal) {
        '10k' => '10K',
        'half_marathon' => 'Half Marathon',
        'marathon' => 'Marathon',
        _ => '5K',
      };

  String get _intensityLabel => switch (intensity) {
        'structured'  => 'Improve steadily',
        'performance' => 'Peak performance',
        _             => 'Finish comfortably',
      };

  int get _weeks {
    if (planWeeks != null) return planWeeks!;
    if (raceDate != null) {
      return raceDate!.difference(DateTime.now()).inDays ~/ 7;
    }
    return 12;
  }

  String get _endDateLabel {
    final d = raceDate ?? startDate.add(Duration(days: _weeks * 7));
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: EC.textPrimary,
                  height: 1.25,
                  letterSpacing: -0.3),
              children: [
                const TextSpan(text: "Your plan is\nalmost ready, "),
                TextSpan(
                    text: '$firstName.',
                    style: const TextStyle(color: EC.teal)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const _Sub(
              'Here\'s what Max has built for you. Review before we lock it in.'),
          const SizedBox(height: 24),

          // ── Summary card ────────────────────────────────────────
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: EC.teal.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_goalLabel,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EC.teal,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 14),
                _summaryRow(Icons.calendar_today_rounded,
                    '$_weeks weeks · ending $_endDateLabel'),
                const SizedBox(height: 10),
                _summaryRow(Icons.bolt_rounded, _intensityLabel),
                const SizedBox(height: 10),
                _summaryRow(Icons.analytics_outlined, 'vDOT $vdotScore'),
                const SizedBox(height: 16),
                const Text('TRAINING DAYS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: EC.muted,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(7, (i) {
                    final active = selectedDays.contains(i);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? EC.teal : EC.surface2,
                          border: Border.all(
                              color: active ? EC.teal : EC.border, width: 1),
                        ),
                        child: Center(
                          child: Text(_dayLabels[i],
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: active ? EC.black : EC.muted)),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                onGenerate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EC.teal,
                foregroundColor: EC.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ET.radius)),
              ),
              child: const Text('Generate my plan',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 16, color: EC.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 14, color: EC.textSecondary)),
        ),
      ]);
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
        vsync: this, duration: const Duration(milliseconds: 3600))
      ..forward();

    Future.delayed(const Duration(milliseconds: 700),
        () { if (mounted) setState(() => _stage = 1); });
    Future.delayed(const Duration(milliseconds: 1600),
        () { if (mounted) setState(() => _stage = 2); });
    Future.delayed(const Duration(milliseconds: 2500),
        () { if (mounted) setState(() => _stage = 3); });
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
                        color: EC.textPrimary),
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
                child: Row(children: [
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
                  Text(_steps[i],
                      style: TextStyle(
                          fontSize: 14,
                          color: done ? EC.textPrimary : EC.textSecondary)),
                ]),
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
          ..strokeWidth = 6);

    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = EC.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE — WEEKLY MILEAGE
// ─────────────────────────────────────────────────────────────────────────────

class OPageWeeklyMileage extends StatefulWidget {
  final double weeklyKm;
  final ValueChanged<double> onChanged;

  const OPageWeeklyMileage({
    super.key,
    required this.weeklyKm,
    required this.onChanged,
  });

  @override
  State<OPageWeeklyMileage> createState() => _OPageWeeklyMileageState();
}

class _OPageWeeklyMileageState extends State<OPageWeeklyMileage> {
  late TextEditingController _ctrl;

  static const double _min = 5;
  static const double _max = 150;
  static const double _step = 5;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.weeklyKm == 0 ? '' : widget.weeklyKm.round().toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _increment() {
    final current = widget.weeklyKm;
    final next = (current + _step).clamp(_min, _max);
    _update(next);
  }

  void _decrement() {
    final current = widget.weeklyKm;
    final next = (current - _step).clamp(_min, _max);
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
    if (parsed != null && parsed >= _min && parsed <= _max) {
      widget.onChanged(parsed);
    }
  }

  String _hint(double km) {
    if (km <= 15) return 'Just getting started — Max will build you up gradually';
    if (km <= 30) return 'Building a base — good foundation to work from';
    if (km <= 50) return 'Solid volume — Max can push with real structure';
    if (km <= 80) return 'High mileage — Max will train you seriously';
    return 'Elite volume — Max will manage load very carefully';
  }

  @override
  Widget build(BuildContext context) {
    final km = widget.weeklyKm;
    final hasValue = km > 0;

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
          const _Sub('Average over the last 2–4 weeks. Be honest — not your best week.'),
          const SizedBox(height: 48),

          // ── Input row ─────────────────────────────────────────────────
          Row(
            children: [
              // Decrement button
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: km > _min ? _decrement : null,
              ),
              const SizedBox(width: 16),

              // Number input
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: EC.surface,
                    borderRadius: BorderRadius.circular(ET.cardRadius),
                    border: Border.all(
                      color: hasValue ? EC.teal : EC.border,
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

              // Increment button
              _StepButton(
                icon: Icons.add_rounded,
                onTap: km < _max ? _increment : null,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Per week label ─────────────────────────────────────────────
          Center(
            child: Text(
              'per week',
              style: const TextStyle(fontSize: 12, color: EC.muted),
            ),
          ),

          const SizedBox(height: 32),

          // ── Hint band ─────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: hasValue
                ? Container(
                    key: ValueKey(_hint(km)),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: EC.teal.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: EC.teal.withOpacity(0.2),
                          width: ET.borderWidth),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.bolt_rounded,
                            size: 16, color: EC.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _hint(km),
                            style: const TextStyle(
                              fontSize: 13,
                              color: EC.teal,
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

/// Reusable stepper button used by OPageWeeklyMileage
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
        child: Icon(
          icon,
          size: 24,
          color: enabled ? EC.textPrimary : EC.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RACE TIME PROJECTION ENGINE
// ─────────────────────────────────────────────────────────────────────────────

/// Uses Riegel formula: T2 = T1 × (D2 / D1) ^ 1.06
/// Projects times for all 4 distances from a single anchor time,
/// then applies a vDOT-based improvement after N weeks of training.
class _RaceProjection {
  final int currentTimeSec;   // user's entered time in seconds
  final double paceDistanceKm; // distance their time is for
  final int planWeeks;
  final String experienceLevel; // 'beginner' | 'intermediate' | 'advanced'

  static const _distances = {
    '5k':           5.0,
    '10k':          10.0,
    'half_marathon': 21.0975,
    'marathon':     42.195,
  };

  // vDOT improvement per 12 weeks by experience level
  // Scales linearly for other week counts
  static const _vdotGainPer12Weeks = {
    'beginner':     3.0,
    'intermediate': 2.0,
    'advanced':     1.0,
  };

  // vDOT → race pace (sec/km) lookup table
  // Source: standard Jack Daniels vDOT tables
  static const _vdotPaceTable = {
    30: 440.0,  // 7:20/km
    32: 422.0,
    34: 405.0,
    36: 390.0,
    38: 375.0,
    40: 361.0,  // 6:01/km
    42: 348.0,
    44: 336.0,
    46: 325.0,
    48: 314.0,
    50: 304.0,  // 5:04/km
    52: 295.0,
    54: 286.0,
    56: 278.0,
    58: 270.0,
    60: 263.0,  // 4:23/km
    62: 256.0,
    64: 249.0,
    66: 243.0,
    68: 237.0,
    70: 232.0,  // 3:52/km
  };

  const _RaceProjection({
    required this.currentTimeSec,
    required this.paceDistanceKm,
    required this.planWeeks,
    required this.experienceLevel,
  });

  /// Riegel: project time from one distance to another
  double _riegel(double fromSec, double fromKm, double toKm) {
    return fromSec * pow(toKm / fromKm, 1.06);
  }

  /// Linear interpolation on the vDOT pace table
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

  /// Derive rough current vDOT from entered time + distance
  int get _currentVdot {
    // Use 5K equivalent time via Riegel, then map to vDOT
    final fiveKEquivSec = _riegel(currentTimeSec.toDouble(), paceDistanceKm, 5.0);
    final paceSec = fiveKEquivSec / 5.0; // sec/km for 5K
    // Find closest vDOT
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

  /// Projected vDOT after completing the plan
  int get _projectedVdot {
    final gainPer12 =
        _vdotGainPer12Weeks[experienceLevel] ?? 2.0;
    final gain = (gainPer12 * planWeeks / 12).round();
    return (_currentVdot + gain).clamp(30, 85);
  }

  /// Current time in seconds for a given distance key
  int currentSec(String distKey) {
    final km = _distances[distKey]!;
    return _riegel(currentTimeSec.toDouble(), paceDistanceKm, km).round();
  }

  /// Projected time in seconds for a given distance key
  int projectedSec(String distKey) {
    final km = _distances[distKey]!;
    // Compute ratio of projected pace to current pace, apply to current time
    final currentPaceSec = _paceSec(_currentVdot);
    final projectedPaceSec = _paceSec(_projectedVdot);
    final improvementRatio = projectedPaceSec / currentPaceSec;
    return (currentSec(distKey) * improvementRatio).round();
  }

  /// Delta in seconds (negative = improvement = faster)
  int deltaSec(String distKey) {
    return projectedSec(distKey) - currentSec(distKey);
  }
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
  final int currentTimeSec;     // user's entered time in seconds
  final double paceDistanceKm;  // distance that time was for
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

  /// Format seconds → h:mm:ss or m:ss
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

  /// Format delta seconds as -Xm Ys or -Xh Ym
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

    final goalCurrent   = proj.currentSec(_goalDistKey);
    final goalProjected = proj.projectedSec(_goalDistKey);

    return SingleChildScrollView(
      padding: ET.pagePad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),

          // ── Greeting ──────────────────────────────────────────────
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: EC.textPrimary,
                  height: 1.2,
                  letterSpacing: -0.5),
              children: [
                const TextSpan(text: "Welcome,\n"),
                TextSpan(
                    text: '$firstName.',
                    style: const TextStyle(color: EC.teal)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Your $_goalLabel plan is locked in.\nMax is ready when you are.",
            style: const TextStyle(
                fontSize: 15, color: EC.textSecondary, height: 1.6),
          ),

          const SizedBox(height: 32),

          // ── Goal headline card ─────────────────────────────────────
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
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: EC.teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_goalLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: EC.teal,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Text('PROJECTED TARGET',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: EC.muted,
                          letterSpacing: 1.1)),
                ]),
                const SizedBox(height: 14),
                // Current → Projected with arrow
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NOW',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: EC.muted,
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(_fmt(goalCurrent),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: EC.textSecondary)),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 1.5,
                          color: EC.teal.withOpacity(0.4),
                        ),
                        const Icon(Icons.directions_run_rounded,
                            size: 18, color: EC.teal),
                        Container(
                          width: 28,
                          height: 1.5,
                          color: EC.teal.withOpacity(0.4),
                        ),
                      ]),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IN $planWeeks WEEKS',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: EC.muted,
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(_fmt(goalProjected),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: EC.textPrimary)),
                      ],
                    ),
                    const Spacer(),
                    // Delta badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: EC.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _fmtDelta(proj.deltaSec(_goalDistKey)),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: EC.teal),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── All distances table ────────────────────────────────────
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
                // Header row
                Row(children: [
                  const SizedBox(width: 52),
                  Expanded(
                    child: Text('Current',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: EC.muted,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text('In $planWeeks weeks',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: EC.teal,
                            letterSpacing: 0.5)),
                  ),
                ]),
                const SizedBox(height: 14),
                const Divider(color: EC.border, height: 1),
                const SizedBox(height: 14),

                // Distance rows
                ...List.generate(_distanceKeys.length, (i) {
                  final key   = _distanceKeys[i];
                  final label = _distanceLabels[i];
                  final color = _distanceColors[i];
                  final curSec  = proj.currentSec(key);
                  final projSec = proj.projectedSec(key);
                  final delta   = proj.deltaSec(key);
                  final isGoal  = key == _goalDistKey;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        // Distance badge
                        Container(
                          width: 44,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Current time
                        Expanded(
                          child: Text(
                            _fmt(curSec),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isGoal
                                    ? EC.textPrimary
                                    : EC.textSecondary),
                          ),
                        ),

                        // Arrow dots
                        SizedBox(
                          width: 32,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _dot(EC.muted),
                              const SizedBox(width: 2),
                              const Icon(Icons.directions_run_rounded,
                                  size: 12, color: EC.teal),
                              const SizedBox(width: 2),
                              _dot(EC.muted),
                            ],
                          ),
                        ),

                        // Projected time + delta
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
                                        : EC.textSecondary),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fmtDelta(delta),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: EC.teal),
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

                // Footnote
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 13, color: EC.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Projected after consistent plan completion. '
                        'Times are calculated using your vDOT $vdot '
                        'and Riegel race equivalence formula.',
                        style: const TextStyle(
                            fontSize: 11,
                            color: EC.muted,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── CTA ────────────────────────────────────────────────────
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
                    borderRadius: BorderRadius.circular(ET.radius)),
              ),
              child: const Text("Let's get to work",
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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