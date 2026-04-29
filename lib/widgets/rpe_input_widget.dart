import 'package:flutter/material.dart';

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
            const Text(
              'HOW DID IT FEEL?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 1.2,
              ),
            ),
            if (_selected != null)
              _RpeLabel(rpe: _selected!),
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
                      ? _rpeColor(value)
                      : _rpeColor(value).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: isSelected
                      ? Border.all(color: _rpeColor(value), width: 1.5)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : _rpeColor(value).withOpacity(0.7),
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
          children: const [
            Text(
              'Easy',
              style: TextStyle(fontSize: 10, color: Color(0xFF999999)),
            ),
            Text(
              'Max effort',
              style: TextStyle(fontSize: 10, color: Color(0xFF999999)),
            ),
          ],
        ),
      ],
    );
  }

  Color _rpeColor(int rpe) {
    if (rpe <= 3) return const Color(0xFF388E3C); // green
    if (rpe <= 6) return const Color(0xFFF57C00); // orange
    return const Color(0xFFD32F2F);               // red
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

  Color get _color {
    if (rpe <= 3) return const Color(0xFF388E3C);
    if (rpe <= 6) return const Color(0xFFF57C00);
    return const Color(0xFFD32F2F);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'RPE $rpe — $_label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}