/// Short-notice interception.
///
/// Shown when the athlete picks a race too close to build real fitness for.
/// The point is that nobody gets ejected: the honest coaching truth is stated,
/// a better path is offered as the primary action, and continuing anyway stays
/// one tap away. Interception, never a wall.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'onboarding_screen.dart' show EC, ET;
import 'plan_runway.dart';

enum ShortNoticeChoice {
  /// Train for this race anyway, on a compressed plan.
  continueAnyway,

  /// Back out and pick something further away.
  pickAnother,
}

Future<ShortNoticeChoice?> showShortNoticeSheet(
  BuildContext context, {
  required String raceName,
  required String goal,
  required PlanRunway runway,
}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<ShortNoticeChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _ShortNoticeSheet(raceName: raceName, goal: goal, runway: runway),
  );
}

class _ShortNoticeSheet extends StatelessWidget {
  final String raceName;
  final String goal;
  final PlanRunway runway;

  const _ShortNoticeSheet({
    required this.raceName,
    required this.goal,
    required this.runway,
  });

  @override
  Widget build(BuildContext context) {
    final weeks = runway.weeksAvailable;
    final distance = PlanRunway.labelFor(goal);

    return Container(
      decoration: const BoxDecoration(
        color: EC.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: EC.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: EC.amber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SHORT NOTICE',
                style: TextStyle(
                  color: EC.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 14),

            Text(
              weeks <= 1
                  ? 'That race is next week'
                  : 'That is $weeks weeks away',
              style: const TextStyle(
                color: EC.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),

            // The honest coaching truth, not a scare.
            Text(
              'There is time to sharpen up and taper for $raceName, but not '
              'enough to build new endurance for a $distance. A '
              '${runway.recommendedWeeks}-week build is where the real gains '
              'come from.',
              style: const TextStyle(
                color: EC.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            _PrimaryButton(
              label: 'Pick a race further out',
              onTap: () =>
                  Navigator.of(context).pop(ShortNoticeChoice.pickAnother),
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
              label: 'Train for it anyway',
              onTap: () =>
                  Navigator.of(context).pop(ShortNoticeChoice.continueAnyway),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: EC.teal,
          foregroundColor: EC.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ET.radius),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: TextButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        style: TextButton.styleFrom(
          foregroundColor: EC.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ET.radius),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
