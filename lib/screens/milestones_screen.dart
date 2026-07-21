import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../engines/achievement_engine.dart' as achieve;
import '../widgets/achievement_tile.dart';

/// Full list of every achievement earned so far. Locked/upcoming achievements
/// aren't shown yet — that's a planned follow-up (grayed-out preview rows).
class MilestonesScreen extends StatelessWidget {
  final List<achieve.Achievement> achievements;

  const MilestonesScreen({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = sortAchievements(achievements);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        title: Text(
          'Milestones',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: sorted.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(bottom: index < sorted.length - 1 ? 12 : 0),
          child: AchievementTile(achievement: sorted[index]),
        ),
      ),
    );
  }
}
