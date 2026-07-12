import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';
import '../widgets/run_share_card.dart';

class RunDetailScreen extends StatefulWidget {
  final dynamic run;
  final dynamic record;
  const RunDetailScreen({super.key, required this.run, this.record});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  bool _useMiles = UnitUtils.useMilesNotifier.value;

  @override
  void initState() {
    super.initState();
    UnitUtils.useMilesNotifier.addListener(_onUnitPrefChanged);
  }

  void _onUnitPrefChanged() {
    if (mounted) setState(() => _useMiles = UnitUtils.useMilesNotifier.value);
  }

  @override
  void dispose() {
    UnitUtils.useMilesNotifier.removeListener(_onUnitPrefChanged);
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _formatDate(DateTime date) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Monday','Tuesday','Wednesday','Thursday',
                  'Friday','Saturday','Sunday'];
    final day = days[date.weekday - 1];
    return '$day, ${months[date.month - 1]} ${date.day} · '
        '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
  }

  int _estimateCalories(double distanceKm) => (distanceKm * 65).round();

  String _workoutLabel(String type) => WorkoutTypeStyle.label(type);

  Color _workoutColor(String type) => WorkoutTypeStyle.color(type);

  List<Map<String, double>> _getGpsPoints() {
    try {
      final points = widget.run.gpsPoints;
      if (points == null || (points as List).isEmpty) return [];
      return List<Map<String, double>>.from(points);
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.run.distance as double;
    final pace = widget.run.averagePace as String;
    final date = widget.run.date as DateTime;
    final duration = widget.record?.durationSeconds as int? ?? 0;
    final workoutType = widget.record?.workoutType as String? ?? 'easy';
    final calories = _estimateCalories(distance);
    final wColor = _workoutColor(workoutType);
    final gpsPoints = _getGpsPoints();

    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 48,
        height: 54,
        child: FloatingActionButton.extended(
          onPressed: () => showRunShareSheet(
            context,
            ShareRunData(
              distanceKm: distance,
              averagePace: pace,
              durationSeconds: duration,
              date: date,
              workoutType: workoutType,
              gpsPoints: gpsPoints,
              useMiles: _useMiles,
            ),
            source: 'run_detail',
          ),
          backgroundColor: context.colors.accent,
          foregroundColor: context.colors.onAccent,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.ios_share, size: 20),
          label: const Text(
            'Share',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0A),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // Route painter or gradient background
                  Positioned.fill(
                    child: gpsPoints.length > 1
                        ? CustomPaint(
                            painter: _RoutePainter(
                              points: gpsPoints,
                              lineColor: wColor,
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF0A0A0A),
                                  wColor.withOpacity(0.15),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.directions_run,
                                color: Colors.white12,
                                size: 80,
                              ),
                            ),
                          ),
                  ),

                  // Dark gradient overlay at bottom for text readability
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0A0A0A).withOpacity(0.85),
                          ],
                          stops: const [0.4, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Text overlay at bottom
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: wColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: wColor.withOpacity(0.5)),
                          ),
                          child: Text(
                            _workoutLabel(workoutType).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: wColor,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _formatDate(date),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary stats
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.border),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        _buildStat(
                          context,
                          label: 'DISTANCE',
                          value: UnitUtils.displayDistance(distance, _useMiles).toStringAsFixed(2),
                          unit: UnitUtils.unitLabel(_useMiles),
                        ),
                        _buildDivider(context),
                        _buildStat(
                          context,
                          label: 'AVG PACE',
                          value: UnitUtils.formatPaceString(pace, _useMiles),
                          unit: UnitUtils.perUnitLabel(_useMiles),
                        ),
                        _buildDivider(context),
                        _buildStat(
                          context,
                          label: 'TIME',
                          value: _formatDuration(duration),
                          unit: '',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Secondary stats
                  SizedBox(
                    width: double.infinity,
                    child: _buildSecondaryCard(
                      context,
                      icon: Icons.local_fire_department_outlined,
                      label: 'CALORIES',
                      value: '$calories',
                      unit: 'kcal',
                    ),
                  ),
                  // Clearance for the floating Share button.
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
  }) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: TextStyle(
                fontSize: 11,
                color: c.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: context.colors.border,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildSecondaryCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.divider,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: c.textTertiary),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 11,
                  color: c.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color lineColor;

  const _RoutePainter({required this.points, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0A),
    );

    // Get bounds
    double minLat = points.first['lat']!;
    double maxLat = points.first['lat']!;
    double minLng = points.first['lng']!;
    double maxLng = points.first['lng']!;

    for (final p in points) {
      minLat = math.min(minLat, p['lat']!);
      maxLat = math.max(maxLat, p['lat']!);
      minLng = math.min(minLng, p['lng']!);
      maxLng = math.max(maxLng, p['lng']!);
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    if (latRange == 0 || lngRange == 0) return;

    // Padding so route doesn't touch edges
    const padding = 40.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;

    // Scale maintaining aspect ratio
    final scaleX = drawWidth / lngRange;
    final scaleY = drawHeight / latRange;
    final scale = math.min(scaleX, scaleY);

    final offsetX = padding + (drawWidth - lngRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    Offset toOffset(Map<String, double> p) {
      final x = offsetX + (p['lng']! - minLng) * scale;
      // Flip Y — latitude increases upward but canvas Y increases downward
      final y = offsetY + (maxLat - p['lat']!) * scale;
      return Offset(x, y);
    }

    // Glow effect — draw wide faint line first
    final glowPaint = Paint()
      ..color = lineColor.withOpacity(0.15)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, glowPaint);

    // Main route line
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    // Start dot — green
    final startOffset = toOffset(points.first);
    canvas.drawCircle(
      startOffset,
      5,
      Paint()..color = const Color(0xFF4CAF50),
    );

    // End dot — colored by workout type
    final endOffset = toOffset(points.last);
    canvas.drawCircle(
      endOffset,
      5,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => false;
}