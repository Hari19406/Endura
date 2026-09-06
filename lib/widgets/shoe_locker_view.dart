// lib/widgets/shoe_locker_view.dart
//
// Gear tab body: the shoe locker with per-pair mileage bars and active/retired
// grouping. Read-only when [editable] is false (viewing another athlete).

import 'package:flutter/material.dart';

import '../models/shoe.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';

class ShoeLockerView extends StatelessWidget {
  final List<Shoe> shoes;
  final bool editable;
  final Future<void> Function()? onAdd;
  final Future<void> Function(Shoe)? onEdit;

  const ShoeLockerView({
    super.key,
    required this.shoes,
    this.editable = false,
    this.onAdd,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = shoes.where((s) => !s.isRetired).toList();
    final retired = shoes.where((s) => s.isRetired).toList();

    if (shoes.isEmpty) {
      return _EmptyLocker(editable: editable, onAdd: onAdd);
    }

    return ValueListenableBuilder<bool>(
      valueListenable: UnitUtils.useMilesNotifier,
      builder: (context, useMiles, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          if (editable) ...[
            _AddButton(onAdd: onAdd),
            const SizedBox(height: 20),
          ],
          _sectionLabel(context, 'ACTIVE'),
          const SizedBox(height: 12),
          if (active.isEmpty)
            Text(
              'No active pairs.',
              style: TextStyle(fontSize: 13, color: c.textTertiary),
            )
          else
            ...active.map(
              (s) => _ShoeCard(
                shoe: s,
                useMiles: useMiles,
                onTap: editable && onEdit != null ? () => onEdit!(s) : null,
              ),
            ),
          if (retired.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionLabel(context, 'RETIRED'),
            const SizedBox(height: 12),
            ...retired.map(
              (s) => _ShoeCard(
                shoe: s,
                useMiles: useMiles,
                onTap: editable && onEdit != null ? () => onEdit!(s) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: context.colors.textTertiary,
      letterSpacing: 1.2,
    ),
  );
}

class _ShoeCard extends StatelessWidget {
  final Shoe shoe;
  final bool useMiles;
  final VoidCallback? onTap;

  const _ShoeCard({required this.shoe, required this.useMiles, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dist = UnitUtils.displayDistance(shoe.distanceKm, useMiles);
    final max = UnitUtils.displayDistance(shoe.maxDistanceKm, useMiles);
    final unit = UnitUtils.unitLabel(useMiles);
    final barColor = shoe.isRetired
        ? c.textTertiary
        : (shoe.isPastTarget ? c.danger : c.chartAccent);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shoe.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: shoe.isRetired ? c.textTertiary : c.textPrimary,
                    ),
                  ),
                ),
                if (shoe.isDefault && !shoe.isRetired)
                  _Badge(text: 'DEFAULT', color: c.accent, fg: c.onAccent),
                if (shoe.isRetired)
                  _Badge(
                    text: 'RETIRED',
                    color: c.divider,
                    fg: c.textSecondary,
                  ),
              ],
            ),
            if (shoe.nickname != null && shoe.nickname!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '${shoe.brand} ${shoe.model}',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: shoe.wearFraction,
                minHeight: 6,
                backgroundColor: c.divider,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${dist.toStringAsFixed(0)} / ${max.toStringAsFixed(0)} $unit',
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color fg;
  const _Badge({required this.text, required this.color, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: fg,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _AddButton extends StatelessWidget {
  final Future<void> Function()? onAdd;
  const _AddButton({this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onAdd == null ? null : () => onAdd!(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 18, color: c.textPrimary),
            const SizedBox(width: 8),
            Text(
              'Add a shoe',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLocker extends StatelessWidget {
  final bool editable;
  final Future<void> Function()? onAdd;
  const _EmptyLocker({required this.editable, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_run, size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              editable
                  ? 'No shoes yet. Add a pair to start tracking mileage.'
                  : 'This athlete has no shoes in their locker.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            if (editable) ...[
              const SizedBox(height: 16),
              SizedBox(width: 200, child: _AddButton(onAdd: onAdd)),
            ],
          ],
        ),
      ),
    );
  }
}
