import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../engines/memory/engine_memory_service.dart';
import '../engines/planner/race_plan_builder.dart';

class ManagePlanScreen extends StatefulWidget {
  final VoidCallback? onPlanChanged;
  const ManagePlanScreen({super.key, this.onPlanChanged});

  @override
  State<ManagePlanScreen> createState() => _ManagePlanScreenState();
}

class _ManagePlanScreenState extends State<ManagePlanScreen> {
  String _goalRace = 'half_marathon';
  DateTime _raceDate = DateTime.now().add(const Duration(days: 84));
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final memory = await EngineMemoryService().load();
    if (memory.hasRacePlan && memory.racePlan != null) {
      setState(() {
        _goalRace = memory.racePlan!.goalRace;
        _raceDate = memory.racePlan!.raceDate;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
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

    if (mounted) {
      setState(() => _isSaving = false);
      widget.onPlanChanged?.call();
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDeletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Remove your plan?',
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'This will delete your current training plan. This cannot be undone.',
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFD32F2F)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await EngineMemoryService().clearRacePlan();
      await EngineMemoryService().clearActivePlan();
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          'Manage Plan',
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
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
                  // ── Goal Race ────────────────────────────────────────────
                  Text(
                    'GOAL RACE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: ['5k', '10k', 'half_marathon', 'marathon'].map((
                      key,
                    ) {
                      final selected = _goalRace == key;
                      return GestureDetector(
                        onTap: () => setState(() => _goalRace = key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? c.accent : c.surface,
                            border: Border.all(
                              color: selected ? c.accent : c.border,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _raceLabel(key),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: selected ? c.onAccent : c.textPrimary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  // ── Race Date ────────────────────────────────────────────
                  Text(
                    'RACE DATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _raceDate,
                        firstDate: DateTime.now().add(const Duration(days: 14)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: ColorScheme.dark(
                              primary: c.accent,
                              surface: c.surface,
                              onSurface: c.textPrimary,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _raceDate = picked);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_raceDate.day} ${_monthName(_raceDate.month)} ${_raceDate.year}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary,
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: c.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Save ─────────────────────────────────────────────────
                  GestureDetector(
                    onTap: _isSaving ? null : _saveChanges,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _isSaving ? c.border : c.accent,
                        borderRadius: BorderRadius.circular(10),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: c.onAccent,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Divider ──────────────────────────────────────────────
                  Divider(color: c.divider),

                  const SizedBox(height: 28),

                  // ── Remove Plan ──────────────────────────────────────────
                  Text(
                    'REMOVE PLAN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Permanently deletes your current training plan.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _confirmDeletePlan,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        border: Border.all(color: const Color(0xFFD32F2F)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          'Remove Plan',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD32F2F),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  String _monthName(int month) {
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
    return months[month - 1];
  }
}
