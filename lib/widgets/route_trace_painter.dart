import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Route trace on a transparent background, auto-fitted to the available box
/// with the aspect ratio preserved.
///
/// Shared between the share-card poster templates (large, [padding] 24) and
/// the History tab's run thumbnails (64x64, [padding] 6). Points are the
/// `{lat, lng}` maps produced by `RunHistory.gpsPoints`.
class RouteTracePainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color color;
  final double strokeWidth;

  /// Inset kept clear on every side. The default matches the share card's
  /// original spacing so poster output is unchanged.
  final double padding;

  /// Soft black shadow under the line so it stays readable on bright photos.
  final bool dropShadow;

  const RouteTracePainter({
    required this.points,
    this.color = Colors.white,
    this.strokeWidth = 3,
    this.padding = 24,
    this.dropShadow = false,
  });

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

    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height - padding * 2;
    if (drawWidth <= 0 || drawHeight <= 0) return;

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

    if (dropShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black54
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path.shift(const Offset(0, 1)), shadowPaint);
    }

    final linePaint = Paint()
      ..color = color.withOpacity(0.95)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(RouteTracePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.padding != padding ||
      oldDelegate.dropShadow != dropShadow;
}
