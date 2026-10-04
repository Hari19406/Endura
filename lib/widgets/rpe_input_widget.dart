import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A compact RPE (Rate of Perceived Exertion) input shown after every run.
/// Emits the selected value via [onRpeSelected].
/// Call this from [RunSummaryScreen] before saving the run record.
class RpeInputWidget extends StatefulWidget {
  final void Function(int rpe) onRpeSelected;
  final int? initialValue;

  const RpeInputWidget({
    super.key,
    required this.onRpeSelected,
    this.initialValue,
  });

  @override
  State<RpeInputWidget> createState() => _RpeInputWidgetState();
}

class _RpeInputWidgetState extends State<RpeInputWidget> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'HOW DID IT FEEL?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            if (_selected != null) _RpeLabel(rpe: _selected!),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(10, (i) {
            final value = i + 1;
            final isSelected = _selected == value;
            return GestureDetector(
              onTap: () {
                setState(() => _selected = value);
                widget.onRpeSelected(value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 28,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? _rpeColor(context, value)
                      : _rpeColor(context, value).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: isSelected
                      ? Border.all(color: _rpeColor(context, value), width: 1.5)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? context.colors.onAccent
                          : _rpeColor(context, value).withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Easy',
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textTertiary,
              ),
            ),
            Text(
              'Max effort',
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _rpeColor(BuildContext context, int rpe) {
    final c = context.colors;
    if (rpe <= 3) return c.success;
    if (rpe <= 6) return c.workoutTempo;
    return c.danger;
  }
}

class _RpeLabel extends StatelessWidget {
  final int rpe;
  const _RpeLabel({required this.rpe});

  String get _label {
    if (rpe <= 2) return 'Very easy';
    if (rpe <= 4) return 'Comfortable';
    if (rpe <= 6) return 'Moderate';
    if (rpe <= 7) return 'Hard';
    if (rpe == 8) return 'Very hard';
    if (rpe == 9) return 'Near max';
    return 'Maximum';
  }

  Color _color(BuildContext context) {
    final c = context.colors;
    if (rpe <= 3) return c.success;
    if (rpe <= 6) return c.workoutTempo;
    return c.danger;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'RPE $rpe — $_label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
