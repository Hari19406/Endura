import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/matched_run_comparison.dart';
import '../utils/unit_utils.dart';

/// "You ran this route before" card for Activity Detail. Renders nothing when
/// there is no match. Compares today's run with the previous and best matched
/// runs; HR / elevation / GAP rows appear only when both runs have the data.
class MatchedRunCard extends StatelessWidget {
  /// Today's average pace as "m:ss" per km.
  final String avgPace;
  final MatchedRunsResult? result;
  final bool useMiles;

  const MatchedRunCard({
    super.key,
    required this.avgPace,
    required this.result,
    this.useMiles = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null || r.matchCount == 0) return const SizedBox.shrink();
    final c = Theme.of(context).extension<AppColors>()!;
    final primary = r.previous ?? r.best!;
    final primaryLabel = r.previous != null
        ? 'your previous run'
        : 'your fastest run on this route';
    final showBest = r.best != null && !r.previousIsBest && r.previous != null;

    return Container(
      key: const Key('matched-run-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MATCHED ROUTE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: c.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                _countLabel(r),
                key: const Key('matched-run-count'),
                style: TextStyle(fontSize: 11, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${UnitUtils.formatPaceString(avgPace, useMiles)}'
            '${UnitUtils.perUnitLabel(useMiles)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _headline(primary, primaryLabel),
            key: const Key('matched-run-headline'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _isFaster(primary) ? c.success : c.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _section(
            c,
            r.previous == null
                ? 'VS BEST ON THIS ROUTE'
                : r.previousIsBest
                ? 'VS PREVIOUS RUN \u00b7 YOUR BEST'
                : 'VS PREVIOUS RUN',
            primary,
          ),
          if (showBest) ...[
            const SizedBox(height: 14),
            _section(c, 'VS BEST ON THIS ROUTE', r.best!),
          ],
        ],
      ),
    );
  }

  String _countLabel(MatchedRunsResult r) {
    final n = r.previousCount > 0 ? r.previousCount : r.matchCount;
    final noun = n == 1 ? 'run' : 'runs';
    return r.previousCount > 0
        ? '$n previous $noun on this route'
        : '$n other $noun on this route';
  }

  bool _isFaster(MatchedRunComparison cmp) => cmp.timeIsLikeForLike
      ? cmp.timeDeltaSeconds < 0
      : (cmp.paceDeltaSecPerKm ?? 0) < 0;

  String _headline(MatchedRunComparison cmp, String label) {
    if (cmp.timeIsLikeForLike) {
      final d = cmp.timeDeltaSeconds;
      if (d == 0) return 'Same time as $label';
      return '${formatMatchedDuration(d)} ${d < 0 ? 'faster' : 'slower'}'
          ' than $label';
    }
    final p = cmp.paceDeltaSecPerKm;
    if (p == null || p == 0) return 'Same pace as $label';
    final shown = UnitUtils.displayPaceSeconds(p.abs().toDouble(), useMiles);
    return '${formatMatchedDuration(shown.round())}'
        '${UnitUtils.perUnitLabel(useMiles)} ${p < 0 ? 'faster' : 'slower'}'
        ' than $label';
  }

  Widget _section(
    AppColors c,
    String title,
    MatchedRunComparison cmp,
  ) {
    final rows = <Widget>[
      _row(
        c,
        'Time',
        formatMatchedDuration(cmp.other.durationSeconds),
        cmp.timeDeltaSeconds,
        lowerIsBetter: true,
        fmt: formatMatchedDuration,
      ),
      if (cmp.paceDeltaSecPerKm != null && cmp.other.paceSecPerKm != null)
        _row(
          c,
          'Pace',
          '${formatMatchedDuration(UnitUtils.displayPaceSeconds(cmp.other.paceSecPerKm!.toDouble(), useMiles).round())}'
              '${UnitUtils.perUnitLabel(useMiles)}',
          UnitUtils.displayPaceSeconds(
            cmp.paceDeltaSecPerKm!.toDouble(),
            useMiles,
          ).round(),
          lowerIsBetter: true,
          fmt: formatMatchedDuration,
        ),
      if (cmp.distanceDiffKm != null)
        _row(
          c,
          'Distance',
          '${UnitUtils.displayDistance(cmp.other.distanceKm, useMiles).toStringAsFixed(2)} ${UnitUtils.unitLabel(useMiles)}',
          null,
          trailingText:
              '${cmp.distanceDiffKm! > 0 ? '+' : '\u2212'}'
              '${UnitUtils.displayDistance(cmp.distanceDiffKm!.abs(), useMiles).toStringAsFixed(2)} ${UnitUtils.unitLabel(useMiles)}',
        ),
      if (cmp.hrDelta != null)
        _row(
          c,
          'Avg HR',
          '${cmp.other.avgHr} bpm',
          cmp.hrDelta,
          lowerIsBetter: false,
          neutral: true,
          fmt: (v) => '$v',
        ),
      if (cmp.elevationDeltaM != null)
        _row(
          c,
          'Elevation',
          '${cmp.other.elevationGainM!.round()} m',
          cmp.elevationDeltaM!.round(),
          neutral: true,
          fmt: (v) => '$v m',
        ),
      if (cmp.gapDeltaSecPerKm != null && cmp.other.gapSecPerKm != null)
        _row(
          c,
          'GAP',
          '${formatMatchedDuration(UnitUtils.displayPaceSeconds(cmp.other.gapSecPerKm!.toDouble(), useMiles).round())}'
              '${UnitUtils.perUnitLabel(useMiles)}',
          UnitUtils.displayPaceSeconds(
            cmp.gapDeltaSecPerKm!.toDouble(),
            useMiles,
          ).round(),
          lowerIsBetter: true,
          fmt: formatMatchedDuration,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: c.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        ...rows,
        if (cmp.splitDeltas.isNotEmpty && !useMiles) _splits(c, cmp),
      ],
    );
  }

  /// Per-km deltas. Splits are whole kilometres, so they're hidden in miles
  /// mode rather than mislabelled.
  Widget _splits(AppColors c, MatchedRunComparison cmp) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in cmp.splitDeltas)
            Container(
              key: Key('matched-split-${s.km}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Text(
                'km ${s.km}  ${_signed(s.deltaSeconds, formatMatchedDuration)}',
                style: TextStyle(
                  fontSize: 11,
                  color: s.deltaSeconds < 0
                      ? c.success
                      : s.deltaSeconds > 0
                      ? c.textSecondary
                      : c.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _signed(int v, String Function(int) fmt) =>
      v == 0 ? '0' : '${v < 0 ? '\u2212' : '+'}${fmt(v)}';

  Widget _row(
    AppColors c,
    String label,
    String otherValue,
    int? delta, {
    bool lowerIsBetter = true,
    bool neutral = false,
    String Function(int)? fmt,
    String? trailingText,
  }) {
    final text =
        trailingText ??
        (delta == null ? '' : _signed(delta, fmt ?? (v) => '${v.abs()}'));
    final better = delta != null && (lowerIsBetter ? delta < 0 : delta > 0);
    final color = neutral || delta == null || delta == 0
        ? c.textTertiary
        : better
        ? c.success
        : c.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          Text(
            otherValue,
            style: TextStyle(
              fontSize: 13,
              color: c.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
