import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/planner/race_plan_builder.dart';
import '../engines/plan/plan_materialization_coordinator.dart';
import '../models/race_plan.dart';
import '../models/training_phase.dart';
import '../services/training_days_service.dart';
import '../widgets/ambient_scaffold.dart';

class ManagePlanScreen extends StatefulWidget {
  final VoidCallback? onPlanChanged;
  const ManagePlanScreen({super.key, this.onPlanChanged});

  @override
  State<ManagePlanScreen> createState() => _ManagePlanScreenState();
}

class _ManagePlanScreenState extends State<ManagePlanScreen> {
  static const _goalOptions = ['5k', '10k', 'half_marathon', 'marathon'];

  String _goalRace = 'half_marathon';
  DateTime _raceDate = DateTime.now().add(const Duration(days: 84));
  RacePlan? _racePlan;
  List<int> _trainingDays = const [];
  int? _longRunDayIndex;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final memory = await EngineMemoryService().load();
    final prefs = await SharedPreferences.getInstance();
    final trainingDays = await TrainingDaysService.loadOrDefault(
      prefs.getInt('runs_per_week') ?? 4,
    );

    if (!mounted) return;
    setState(() {
      _trainingDays = trainingDays;
      if (memory.hasRacePlan && memory.racePlan != null) {
        _racePlan = memory.racePlan;
        _goalRace = memory.racePlan!.goalRace;
        _raceDate = memory.racePlan!.raceDate;
      }
      _longRunDayIndex =
          (memory.longRunDayIndex != null &&
              trainingDays.contains(memory.longRunDayIndex))
          ? memory.longRunDayIndex
          : (trainingDays.isEmpty
                ? null
                : trainingDays.reduce((a, b) => a > b ? a : b));
      _isLoading = false;
    });
  }

  Future<void> _pickRaceDate() async {
    final c = context.colors;
    final picked = await showDatePicker(
      context: context,
      initialDate: _raceDate,
      firstDate: DateTime.now().add(const Duration(days: 14)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: c.accent,
                brightness: Theme.of(ctx).brightness,
              ).copyWith(
                primary: c.accent,
                onPrimary: c.onAccent,
                surface: c.surface,
                onSurface: c.textPrimary,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _raceDate = picked);
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    final memory = await EngineMemoryService().load();
    final currentPlan = memory.racePlan;

    final originalStart = currentPlan?.createdAt ?? DateTime.now();

    final newPlan = RacePlanBuilder.build(
      currentWeeklyKm: currentPlan?.startingWeeklyKm ?? 20.0,
      goalRace: _goalRace,
      raceDate: _raceDate,
      experienceLevel: currentPlan?.experienceLevel ?? 'beginner',
      now: originalStart,
    );

    await EngineMemoryService().saveRacePlan(newPlan);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('goal_race', _goalRace);
    await prefs.setString('race_date', _raceDate.toIso8601String());
    await prefs.setString('plan_start_date', originalStart.toIso8601String());
    await prefs.setInt('plan_weeks', newPlan.totalWeeks);

    // Re-materialise the whole plan for the edited inputs. Completed weeks in
    // the stored plan stay frozen; everything from the current week on is
    // rebuilt.
    try {
      final trainingDays = await TrainingDaysService.loadOrDefault(
        prefs.getInt('runs_per_week') ?? 4,
      );
      final materialized = await PlanMaterializationCoordinator.instance
          .recompute(
            skeleton: newPlan,
            trainingDayIndices: trainingDays,
            longRunDayIndex: _longRunDayIndex,
            goalRace: _goalRace,
            experienceLevel: currentPlan?.experienceLevel ?? 'intermediate',
            vdot: memory.vdotScore,
            goalTimeSeconds:
                prefs.getInt('target_finish_seconds') ??
                prefs.getInt('time_to_beat_seconds'),
          )
          .timeout(const Duration(seconds: 20));
      if (materialized != null) {
        await EngineMemoryService().save(
          (await EngineMemoryService().load()).copyWith(
            materializedPlanId: materialized.planId,
            sessionProgress: materialized.sessionProgress,
            ladderPositions: materialized.ladderState,
            longRunDayIndex: _longRunDayIndex,
          ),
          syncToCloud: false,
        );
      }
    } catch (e) {
      debugPrint('[ManagePlan] Re-materialisation error (non-fatal): $e');
    }

    if (mounted) {
      setState(() => _isSaving = false);
      widget.onPlanChanged?.call();
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDeletePlan() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.colors;
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Remove your plan?',
                  style: tt.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your past logged runs will stay safe, but your current '
                  'training schedule will be archived. This cannot be undone.',
                  style: tt.bodyMedium?.copyWith(
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.danger,
                      side: BorderSide(color: c.danger),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Remove Plan',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.danger,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      'Cancel',
                      style: tt.labelLarge?.copyWith(color: c.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await EngineMemoryService().resetCurrentPlan();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('goal_race');
      await prefs.remove('plan_start_date');
      await prefs.remove('plan_weeks');
      await prefs.remove('race_date');

      if (mounted) {
        widget.onPlanChanged?.call();
        Navigator.of(context).pop();
      }
    }
  }

  String _raceLabel(String key) => switch (key) {
    '5k' => '5K',
    '10k' => '10K',
    'half_marathon' => 'Half Marathon',
    'marathon' => 'Marathon',
    _ => '5K',
  };

  int _weeksRemaining() =>
      (_raceDate.difference(DateTime.now()).inDays / 7).ceil().clamp(0, 999);

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(BuildContext context, String text) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return Text(
      text,
      style: tt.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: c.textTertiary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _overviewCard(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    final plan = _racePlan;
    final now = DateTime.now();
    final currentWeek = plan?.currentWeek(now);
    final phase =
        currentWeek?.phase ??
        plan?.weeks.firstOrNull?.phase ??
        TrainingPhase.base;
    final weeklyKm = currentWeek?.targetKm ?? plan?.startingWeeklyKm;
    final weeksLeft = _weeksRemaining();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${phase.displayName.toUpperCase()} PHASE',
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.accent,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _raceLabel(_goalRace),
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMM d, y').format(_raceDate),
            style: tt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  context,
                  label: 'WEEKS LEFT',
                  value: '$weeksLeft',
                ),
              ),
              Container(width: 1, height: 30, color: c.divider),
              const SizedBox(width: 16),
              Expanded(
                child: _statTile(
                  context,
                  label: 'WEEKLY VOLUME',
                  value: weeklyKm == null ? '—' : '${weeklyKm.round()} km',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: c.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _goalGrid(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: _goalOptions.map((key) {
        final selected = _goalRace == key;
        return GestureDetector(
          onTap: () => setState(() => _goalRace = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.accent : c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? c.accent : c.border),
            ),
            child: Text(
              _raceLabel(key),
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? c.onAccent : c.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _raceDateCard(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    final weeksLeft = _weeksRemaining();
    return GestureDetector(
      onTap: _pickRaceDate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 20,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE, MMM d, y').format(_raceDate),
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Race day',
                    style: tt.labelSmall?.copyWith(
                      color: c.textTertiary,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$weeksLeft ${weeksLeft == 1 ? 'week' : 'weeks'} left',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _longRunDaySelector(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: List.generate(7, (i) {
        final enabled = _trainingDays.contains(i);
        final selected = _longRunDayIndex == i;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
            child: GestureDetector(
              onTap: enabled
                  ? () => setState(() => _longRunDayIndex = i)
                  : null,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? c.accent : c.border),
                ),
                child: Text(
                  TrainingDaysService.dayNames[i].substring(0, 3),
                  style: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: !enabled
                        ? c.textFaint
                        : (selected ? c.onAccent : c.textPrimary),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _saveButton(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: _isSaving ? null : _saveChanges,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _isSaving ? c.border : c.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _isSaving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.onAccent,
                  ),
                )
              : Text(
                  'Save Changes',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.onAccent,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _dangerZone(BuildContext context) {
    final c = context.colors;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: c.danger),
              const SizedBox(width: 8),
              Text(
                'DANGER ZONE',
                style: tt.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.danger,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Removing your plan archives your current training schedule — '
            'it does not delete your past logged runs or activity history.',
            style: tt.bodySmall?.copyWith(color: c.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _confirmDeletePlan,
              style: OutlinedButton.styleFrom(
                foregroundColor: c.danger,
                side: BorderSide(color: c.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Remove Plan',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AmbientScaffold(
      appBar: AppBar(
        title: Text(
          'Manage Plan',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        backgroundColor: c.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_racePlan != null) ...[
                    _overviewCard(context),
                    const SizedBox(height: 28),
                  ],

                  _sectionLabel(context, 'GOAL RACE'),
                  const SizedBox(height: 12),
                  _goalGrid(context),

                  const SizedBox(height: 28),

                  _sectionLabel(context, 'RACE DATE'),
                  const SizedBox(height: 12),
                  _raceDateCard(context),

                  if (_trainingDays.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionLabel(context, 'PREFERRED LONG RUN DAY'),
                    const SizedBox(height: 12),
                    _longRunDaySelector(context),
                  ],

                  const SizedBox(height: 32),
                  _saveButton(context),

                  const SizedBox(height: 32),
                  _dangerZone(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
