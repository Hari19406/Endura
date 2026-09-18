/// RestartPlanBanner — floating opt-in banner offering to restart the active
/// plan from today when the athlete has fallen behind schedule. Tapping opens
/// [RestartPlanBottomSheet], which owns the confirm/persist flow.
///
/// Purely semantic theming throughout — every color comes from
/// `context.colors` (the app's `AppColors` ThemeExtension, itself backed by
/// `ThemeData.colorScheme`) and every text style from `Theme.of(context)
/// .textTheme`, so the visual theme can be swapped centrally with no changes
/// here.
library;

import 'package:flutter/material.dart';

import '../services/analytics_service.dart' show Analytics;
import '../services/plan_restart_service.dart';
import '../theme/app_colors.dart';

class RestartPlanBanner extends StatelessWidget {
  /// Called after the plan has been successfully restarted, so the caller can
  /// reload its state off the updated plan.
  final VoidCallback onRestarted;

  const RestartPlanBanner({super.key, required this.onRestarted});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openSheet(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.chartAccent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.restart_alt_rounded,
                  size: 20,
                  color: c.chartAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restart your plan from today',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Restart your plan from today to get back on track.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    Analytics.capture('restart_plan_banner_tapped');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RestartPlanBottomSheet(onRestarted: onRestarted),
    );
  }
}

class RestartPlanBottomSheet extends StatefulWidget {
  final VoidCallback onRestarted;

  const RestartPlanBottomSheet({super.key, required this.onRestarted});

  @override
  State<RestartPlanBottomSheet> createState() =>
      _RestartPlanBottomSheetState();
}

class _RestartPlanBottomSheetState extends State<RestartPlanBottomSheet> {
  bool _busy = false;

  Future<void> _restart() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await PlanRestartService.restartFromToday();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    if (ok) {
      Analytics.capture('plan_restarted_from_today');
      widget.onRestarted();
    }
  }

  Widget _bullet(BuildContext context, String text) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: c.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, color: c.textSecondary),
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.chartAccent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_today_rounded,
                      size: 26,
                      color: c.chartAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: c.chartAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PLAN UPDATE',
                      style: textTheme.labelSmall?.copyWith(
                        color: c.chartAccent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'RESTART FROM TODAY',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Move your plan forward so you pick it up from here. Every workout shifts by whole weeks, so your weeks still run Monday to Sunday.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'What happens when you restart?',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _bullet(
                        context,
                        'Your plan moves forward to the current week',
                      ),
                      const SizedBox(height: 8),
                      _bullet(
                        context,
                        'All future workouts will shift to align with the new schedule',
                      ),
                      const SizedBox(height: 8),
                      _bullet(
                        context,
                        'Pick your training back up from your next workout',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _restart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      disabledBackgroundColor: c.accent.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(c.onAccent),
                            ),
                          )
                        : Text(
                            'Restart Plan',
                            style: textTheme.titleMedium?.copyWith(
                              color: c.onAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will update your training schedule',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
