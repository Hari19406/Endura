import 'package:flutter/material.dart';
import 'dart:math' as math;

class RunDetailScreen extends StatelessWidget {
  final dynamic run;
  final dynamic record;
  const RunDetailScreen({super.key, required this.run, this.record});

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

  String _workoutLabel(String type) {
    switch (type.toLowerCase()) {
      case 'easy': return 'Easy Run';
      case 'tempo': return 'Tempo';
      case 'interval': return 'Interval';
      case 'long': return 'Long Run';
      case 'recovery': return 'Recovery';
      default: return type;
    }
  }

  Color _workoutColor(String type) {
    switch (type.toLowerCase()) {
      case 'easy': return const Color(0xFF4CAF50);
      case 'tempo': return const Color(0xFFF57C00);
      case 'interval': return const Color(0xFFD32F2F);
      case 'long': return const Color(0xFF1976D2);
      case 'recovery': return const Color(0xFF7B1FA2);
      default: return const Color(0xFF888888);
    }
  }

  List<Map<String, double>> _getGpsPoints() {
    try {
      final points = run.gpsPoints;
      if (points == null || (points as List).isEmpty) return [];
      return List<Map<String, double>>.from(points);
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = run.distance as double;
    final pace = run.averagePace as String;
    final date = run.date as DateTime;
    final duration = record?.durationSeconds as int? ?? 0;
    final workoutType = record?.workoutType as String? ?? 'easy';
    final csValue = record?.csValueAtTime as double?;
    final calories = _estimateCalories(distance);
    final wColor = _workoutColor(workoutType);
    final gpsPoints = _getGpsPoints();

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        _buildStat(
                          label: 'DISTANCE',
                          value: distance.toStringAsFixed(2),
                          unit: 'km',
                        ),
                        _buildDivider(),
                        _buildStat(
                          label: 'AVG PACE',
                          value: pace,
                          unit: '/km',
                        ),
                        _buildDivider(),
                        _buildStat(
                          label: 'TIME',
                          value: _formatDuration(duration),
                          unit: '',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Secondary stats
                  Row(
                    children: [
                      Expanded(
                        child: _buildSecondaryCard(
                          icon: Icons.local_fire_department_outlined,
                          label: 'CALORIES',
                          value: '$calories',
                          unit: 'kcal',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSecondaryCard(
                          icon: Icons.speed_outlined,
                          label: 'CRITICAL SPEED',
                          value: csValue != null
                              ? csValue.toStringAsFixed(2)
                              : '—',
                          unit: csValue != null ? 'm/s' : '',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({
    required String label,
    required String value,
    required String unit,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAAAAAA),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0A0A0A),
              letterSpacing: -0.5,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF999999),
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 48,
      color: const Color(0xFFEEEEEE),
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildSecondaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF999999)),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAAAAAA),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0A0A0A),
              letterSpacing: -0.5,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF999999),
              ),
            ),
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