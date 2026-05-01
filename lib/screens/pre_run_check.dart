/// PreRunCheck — three-question pre-run gate.
///
/// Questions:
///   1. How are you feeling? (great / normal / tired / need rest)
///   2. How was your sleep? (good / poor)  — skipped if need rest
///   3. Any pain? (none / upper body / leg / chest)  — skipped if need rest
///
/// Outcomes:
///   great/normal + good sleep + no/upper pain → run as planned
///   tired or poor sleep or leg pain           → PreRunScaler adjusts dose
///   chest pain                                → blocked, doctor message
///   need rest                                 → shakeout or full rest
library;

import 'package:flutter/material.dart';
import '../engines/daily/pre_run_scaler.dart';
import '../engines/config/workout_template_library.dart';
import '../services/coach_message_builder.dart' as message;

// ============================================================================
// ENTRY POINT
// ============================================================================

Future<void> showPreRunCheck({
  required BuildContext context,
  required message.CoachMessage coachMessage,
  required void Function(message.CoachMessage scaled) onProceed,
  required VoidCallback onSkip,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PreRunCheckSheet(
      coachMessage: coachMessage,
      onProceed: onProceed,
      onSkip: onSkip,
    ),
  );
}

// ============================================================================
// SHEET
// ============================================================================

enum _Step { sleep, pain, restChoice, chestWarning }

class _PreRunCheckSheet extends StatefulWidget {
  final message.CoachMessage coachMessage;
  final void Function(message.CoachMessage scaled) onProceed;
  final VoidCallback onSkip;

  const _PreRunCheckSheet({
    required this.coachMessage,
    required this.onProceed,
    required this.onSkip,
  });

  @override
  State<_PreRunCheckSheet> createState() => _PreRunCheckSheetState();
}

class _PreRunCheckSheetState extends State<_PreRunCheckSheet> {
  _Step _step = _Step.sleep;
  PreRunSleep? _sleep;

  // ── Step handlers ────────────────────────────────────────────────────────

  void _onSleepSelected(PreRunSleep sleep) {
  _sleep = sleep;
  setState(() => _step = _Step.pain);
}

  void _onPainSelected(PainLocation pain) {
    if (pain == PainLocation.chest) {
      setState(() => _step = _Step.chestWarning);
      return;
    }
    _finalize(pain);
  }

  void _finalize(PainLocation pain) {
  final inputs = PreRunInputs(
    feeling: PreRunFeeling.normal,
    sleep: _sleep ?? PreRunSleep.good,
    pain: pain,
  );
  final scaler = const PreRunScaler();
  final result = scaler.scale(widget.coachMessage.resolvedWorkout, inputs);
  final scaled = _rebuildMessage(result.workout, result.coachNote);
  Navigator.pop(context);
  widget.onProceed(scaled);
}

  void _onTakeFullRest() {
    Navigator.pop(context);
    widget.onSkip();
  }

  void _onTakeRecoveryRun() {
    // Recovery run → pass through with no scaling, shakeout intent
    Navigator.pop(context);
    widget.onProceed(widget.coachMessage);
  }

  message.CoachMessage _rebuildMessage(ResolvedWorkout scaled, String? note) {
    final original = widget.coachMessage;
    return message.CoachMessage(
      reflectionText: note ?? original.reflectionText,
      acknowledgementText: original.acknowledgementText,
      workoutTitle: scaled.name,
      workoutSteps: original.workoutSteps,
      resolvedWorkout: scaled,
      workoutIntent: scaled.intent,
      goalText: original.goalText,
      feelText: original.feelText,
      phaseLabel: original.phaseLabel,
      weekNumber: original.weekNumber,
      movedFromDay: original.movedFromDay,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
  return switch (_step) {
    _Step.sleep        => _SleepStep(onSleep: _onSleepSelected),
    _Step.pain         => _PainStep(onPain: _onPainSelected, onBack: () => setState(() => _step = _Step.sleep)),
    _Step.restChoice   => _RestChoiceStep(onFullRest: _onTakeFullRest, onRecoveryRun: _onTakeRecoveryRun, onBack: () => setState(() => _step = _Step.sleep)),
    _Step.chestWarning => _ChestWarningStep(onDismiss: () { Navigator.pop(context); widget.onSkip(); }),
  };
}
}

// ============================================================================
// STEP WIDGETS
// ============================================================================

class _SleepStep extends StatelessWidget {
  final void Function(PreRunSleep) onSleep;

  const _SleepStep({required this.onSleep});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'How was your sleep?',
      subtitle: 'Poor sleep affects recovery and performance.',
      children: [
        _OptionCard(emoji: '😴', label: 'Slept well', subtitle: '7+ hours, felt rested', onTap: () => onSleep(PreRunSleep.good)),
        _OptionCard(emoji: '🥱', label: 'Poor sleep', subtitle: 'Broken or under 6 hours', onTap: () => onSleep(PreRunSleep.poor)),
      ],
    );
  }
}

class _PainStep extends StatelessWidget {
  final void Function(PainLocation) onPain;
  final VoidCallback onBack;

  const _PainStep({required this.onPain, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Any pain or discomfort?',
      subtitle: 'Be honest — this keeps you running long term.',
      onBack: onBack,
      children: [
        _OptionCard(emoji: '✅', label: 'No pain', subtitle: 'Feeling physically fine', onTap: () => onPain(PainLocation.none)),
        _OptionCard(emoji: '💪', label: 'Upper body', subtitle: 'Shoulders, arms, back — won\'t affect the run', onTap: () => onPain(PainLocation.upperBody)),
        _OptionCard(emoji: '🦵', label: 'Leg or foot pain', subtitle: 'Shins, knees, calves, feet — dose reduced', onTap: () => onPain(PainLocation.leg)),
        _OptionCard(emoji: '❤️', label: 'Chest or breathing', subtitle: 'Take today off and consider seeing a doctor', onTap: () => onPain(PainLocation.chest)),
      ],
    );
  }
}

class _RestChoiceStep extends StatelessWidget {
  final VoidCallback onFullRest;
  final VoidCallback onRecoveryRun;
  final VoidCallback onBack;

  const _RestChoiceStep({
    required this.onFullRest,
    required this.onRecoveryRun,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'That\'s okay.',
      subtitle: 'What do you want to do today?',
      onBack: onBack,
      children: [
        _OptionCard(emoji: '🛌', label: 'Take full rest', subtitle: 'Skip today, mark as rest day', onTap: onFullRest),
        _OptionCard(emoji: '🚶', label: 'Easy recovery run', subtitle: '20–30 min shakeout at very easy pace', onTap: onRecoveryRun),
      ],
    );
  }
}

class _ChestWarningStep extends StatelessWidget {
  final VoidCallback onDismiss;

  const _ChestWarningStep({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dragHandle(),
        const SizedBox(height: 24),
        const Text('❤️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const Text(
          'Take today off',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0A0A0A)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Chest pain or breathing issues during exercise should always be checked. Consider speaking to a doctor before your next run.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF666666), height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Got it, taking rest today',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED COMPONENTS
// ============================================================================

class _StepShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _dragHandle()),
        const SizedBox(height: 20),
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0A0A0A), letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF999999), height: 1.4)),
        const SizedBox(height: 20),
        ...children.expand((w) => [w, const SizedBox(height: 10)]).toList()..removeLast(),
        if (onBack != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onBack,
            child: const Row(
              children: [
                Icon(Icons.arrow_back_ios_rounded, size: 13, color: Color(0xFF999999)),
                SizedBox(width: 4),
                Text('Go back', style: TextStyle(fontSize: 13, color: Color(0xFF999999), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Widget _dragHandle() => Container(
  width: 36, height: 4,
  decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
);

class _OptionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E8E8), width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0A0A0A))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }
}