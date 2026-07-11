import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/unit_utils.dart';
import '../utils/workout_type_style.dart';

/// Everything the share card needs to render, independent of where the run
/// came from (post-run summary or history detail).
class ShareRunData {
  final double distanceKm;
  final String averagePace; // "m:ss" per km
  final int durationSeconds;
  final DateTime date;
  final String workoutType;
  final List<Map<String, double>> gpsPoints; // {'lat': .., 'lng': ..}
  final bool useMiles;

  const ShareRunData({
    required this.distanceKm,
    required this.averagePace,
    required this.durationSeconds,
    required this.date,
    required this.workoutType,
    required this.gpsPoints,
    required this.useMiles,
  });
}

/// Opens a bottom sheet with a story-format preview of the run card and a
/// Share button that exports it as a PNG through the system share sheet
/// (Instagram stories, WhatsApp status, etc).
Future<void> showRunShareSheet(
  BuildContext context,
  ShareRunData data, {
  required String source,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RunShareSheet(data: data, source: source),
  );
}

class _RunShareSheet extends StatefulWidget {
  final ShareRunData data;
  final String source;
  const _RunShareSheet({required this.data, required this.source});

  @override
  State<_RunShareSheet> createState() => _RunShareSheetState();
}

class _RunShareSheetState extends State<_RunShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // 360x640 logical * 3 = 1080x1920, native story resolution.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/endura_run_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Analytics.runShared(
        workoutType: widget.data.workoutType,
        source: widget.source,
      );

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
      ));
    } catch (e) {
      debugPrint('[RunShareSheet] share failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t create share image')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final previewHeight = MediaQuery.of(context).size.height * 0.52;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Share your run',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: previewHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: RunShareCard(data: widget.data),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _sharing ? null : _share,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _sharing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.onAccent),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(
                  _sharing ? 'Preparing…' : 'Share',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The story-format (9:16) card itself. Always dark regardless of app theme —
/// it's a branded export, not an in-app surface.
class RunShareCard extends StatelessWidget {
  final ShareRunData data;
  const RunShareCard({super.key, required this.data});

  static const double width = 360;
  static const double height = 640;

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final wColor = WorkoutTypeStyle.color(data.workoutType);
    final distanceValue =
        UnitUtils.displayDistance(data.distanceKm, data.useMiles);
    final hasRoute = data.gpsPoints.length > 1;

    return Container(
      width: width,
      height: height,
      color: const Color(0xFF0A0A0A),
      child: Stack(
        children: [
          // Subtle brand glow behind the route.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [
                    wColor.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header — wordmark + workout chip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'ENDURA',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: wColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: wColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        WorkoutTypeStyle.label(data.workoutType).toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: wColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDate(data.date),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // Route trace
                Expanded(
                  child: hasRoute
                      ? CustomPaint(
                          size: Size.infinite,
                          painter: _ShareRoutePainter(
                            points: data.gpsPoints,
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.directions_run,
                            color: Colors.white12,
                            size: 110,
                          ),
                        ),
                ),

                // Hero distance
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceValue.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 62,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -2,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      UnitUtils.unitLabel(data.useMiles),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Secondary stats
                Row(
                  children: [
                    _buildStat(
                      'AVG PACE',
                      UnitUtils.formatPaceString(
                          data.averagePace, data.useMiles),
                      UnitUtils.perUnitLabel(data.useMiles),
                    ),
                    const SizedBox(width: 36),
                    if (data.durationSeconds > 0)
                      _buildStat(
                          'TIME', _formatDuration(data.durationSeconds), ''),
                  ],
                ),
                const SizedBox(height: 28),

                // Footer
                Row(
                  children: [
                    Icon(Icons.directions_run, size: 13, color: wColor),
                    const SizedBox(width: 6),
                    const Text(
                      'COACHED BY MAX',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white38,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Clean white route trace on a transparent background.
class _ShareRoutePainter extends CustomPainter {
  final List<Map<String, double>> points;

  const _ShareRoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

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

    const padding = 24.0;
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;

    final scaleX = drawWidth / lngRange;
    final scaleY = drawHeight / latRange;
    final scale = math.min(scaleX, scaleY);

    final offsetX = padding + (drawWidth - lngRange * scale) / 2;
    final offsetY = padding + (drawHeight - latRange * scale) / 2;

    Offset toOffset(Map<String, double> p) {
      final x = offsetX + (p['lng']! - minLng) * scale;
      final y = offsetY + (maxLat - p['lat']!) * scale;
      return Offset(x, y);
    }

    final path = Path();
    path.moveTo(toOffset(points.first).dx, toOffset(points.first).dy);
    for (int i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_ShareRoutePainter oldDelegate) => false;
}
