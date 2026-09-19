import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'route_trace_painter.dart';
import '../services/analytics_service.dart';
import '../services/social_share_service.dart';
import '../theme/app_colors.dart';

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

/// Layout of the exported card. Every template renders on a fully
/// transparent canvas at the same story size, for overlaying on the user's
/// own photos/videos. Metrics are always metric (km, /km) regardless of the
/// app's unit setting.
enum ShareCardTemplate {
  full,
  overlayDuo,
  overlayTrio,
  verticalMetrics,
  telemetryHud,
  raceTicket,
}

String _labelOf(ShareCardTemplate t) => switch (t) {
  ShareCardTemplate.full => 'Full Map Route',
  ShareCardTemplate.overlayDuo => 'Overlay Duo',
  ShareCardTemplate.overlayTrio => 'Overlay Trio',
  ShareCardTemplate.verticalMetrics => 'Vertical Stack',
  ShareCardTemplate.telemetryHud => 'Telemetry HUD',
  ShareCardTemplate.raceTicket => 'Race Ticket',
};

/// Opens a bottom sheet with a story-format preview of the run card, a
/// template picker, and quick share/save actions.
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
  // One RepaintBoundary key per template — reused across the static preview
  // and (briefly, while rendering) the picker thumbnails.
  final Map<ShareCardTemplate, GlobalKey> _cardKeys = {
    for (final t in ShareCardTemplate.values) t: GlobalKey(),
  };
  ShareCardTemplate _template = ShareCardTemplate.full;
  bool _busy = false;

  String get _templateName => _template.name;

  String get _templateLabel => _labelOf(_template);

  Future<Uint8List> _renderPng() async {
    final boundary =
        _cardKeys[_template]!.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    // 360x640 logical * 3 = 1080x1920, native story resolution. The card has
    // no background, so the PNG keeps its alpha channel.
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<File> _writeTempPng() async {
    final bytes = await _renderPng();
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/endura_run_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _writeTempPng();

      await Analytics.runShared(
        workoutType: widget.data.workoutType,
        source: widget.source,
        style: 'transparent',
        template: _templateName,
        action: 'share',
      );

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } catch (e) {
      debugPrint('[RunShareSheet] share failed: $e');
      _showError('Couldn\'t create share image');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Targeted share to a specific app; falls back to the system sheet when
  /// the app isn't installed.
  Future<void> _shareToApp(String packageName, String analyticsAction) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _writeTempPng();

      await Analytics.runShared(
        workoutType: widget.data.workoutType,
        source: widget.source,
        style: 'transparent',
        template: _templateName,
        action: analyticsAction,
      );

      final opened = await SocialShareService.shareImageTo(
        file.path,
        packageName,
      );
      if (!opened) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
        );
      }
    } catch (e) {
      debugPrint('[RunShareSheet] targeted share failed: $e');
      _showError('Couldn\'t create share image');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) {
        _showError('Gallery access denied');
        return;
      }
      final bytes = await _renderPng();
      await Gal.putImageBytes(
        bytes,
        name: 'endura_run_${DateTime.now().millisecondsSinceEpoch}',
      );

      await Analytics.runShared(
        workoutType: widget.data.workoutType,
        source: widget.source,
        style: 'transparent',
        template: _templateName,
        action: 'save',
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to gallery')));
      }
    } catch (e) {
      debugPrint('[RunShareSheet] save failed: $e');
      _showError('Couldn\'t save image');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _openLayoutPicker() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<ShareCardTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LayoutPickerSheet(data: widget.data, selected: _template),
    );
    if (picked != null && mounted) {
      setState(() => _template = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final previewHeight = MediaQuery.of(context).size.height * 0.46;

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
          const SizedBox(height: 14),

          // Static preview of the selected layout
          SizedBox(
            height: previewHeight,
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  // Checkerboard sits OUTSIDE the RepaintBoundary so the
                  // exported PNG keeps its alpha channel.
                  child: CustomPaint(
                    painter: _CheckerboardPainter(),
                    child: RepaintBoundary(
                      key: _cardKeys[_template],
                      child: RunShareCard(
                        data: widget.data,
                        template: _template,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          GestureDetector(
            onTap: _openLayoutPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.grid_view_rounded, size: 15, color: c.accent),
                  const SizedBox(width: 8),
                  Text(
                    '$_templateLabel · Change layout',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildQuickAction(
                  label: 'Instagram',
                  asset: 'assets/instagram_logo.png',
                  onTap: () => _shareToApp(
                    SocialShareService.instagramPackage,
                    'instagram',
                  ),
                ),
                _buildQuickAction(
                  label: 'WhatsApp',
                  asset: 'assets/whatsapp_logo.png',
                  onTap: () => _shareToApp(
                    SocialShareService.whatsappPackage,
                    'whatsapp',
                  ),
                ),
                _buildQuickAction(
                  label: 'Save',
                  icon: Icons.download_outlined,
                  color: c.textPrimary,
                  onTap: _saveToGallery,
                ),
                _buildQuickAction(
                  label: 'More',
                  icon: Icons.share,
                  color: c.textPrimary,
                  onTap: _share,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required String label,
    IconData? icon,
    String? asset,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final tint = color ?? c.textPrimary;
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Opacity(
        opacity: _busy ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: asset != null
                  // Brand logos carry their own color — neutral circle.
                  ? BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border),
                    )
                  : BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: tint.withValues(alpha: 0.35)),
                    ),
              child: asset != null
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Image.asset(asset, fit: BoxFit.contain),
                    )
                  : Icon(icon, size: 24, color: tint),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Pick a layout" bottom sheet — a grid of live thumbnails over a
/// checkerboard. Pops the tapped [ShareCardTemplate].
class _LayoutPickerSheet extends StatelessWidget {
  final ShareRunData data;
  final ShareCardTemplate selected;

  const _LayoutPickerSheet({required this.data, required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final templates = ShareCardTemplate.values;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pick a layout',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: templates.length,
                  itemBuilder: (context, i) =>
                      _buildThumbnail(context, templates[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(BuildContext context, ShareCardTemplate t) {
    final c = context.colors;
    final isSelected = t == selected;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? c.accent : c.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: _CheckerboardPainter(),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: RunShareCard.width,
                    height: RunShareCard.height,
                    child: IgnorePointer(
                      child: RunShareCard(data: data, template: t),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _labelOf(t),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The story-format (9:16) card itself. Every template has NO background —
/// text and route float on alpha so the exported PNG can be dropped over any
/// photo. All text carries a soft drop shadow for legibility on bright
/// backgrounds.
class RunShareCard extends StatelessWidget {
  final ShareRunData data;
  final ShareCardTemplate template;

  const RunShareCard({
    super.key,
    required this.data,
    this.template = ShareCardTemplate.full,
  });

  static const double width = 360;
  static const double height = 640;

  static const List<Shadow> _shadow = [
    Shadow(offset: Offset(0, 1), blurRadius: 4.0, color: Colors.black54),
  ];

  // ── Athletic condensed identity — Full Map Route & Vertical Stack ───────
  // The italic serif styles used by Overlay Duo/Trio are a separate,
  // unrelated typographic system.

  /// `ENDURA` watermark.
  static TextStyle get _brandMarkStyle => GoogleFonts.barlowCondensed(
    fontSize: 17,
    fontWeight: FontWeight.w900,
    letterSpacing: 3.5,
    color: Colors.white,
    shadows: const [
      Shadow(offset: Offset(0, 1), blurRadius: 4.0, color: Colors.black54),
      Shadow(offset: Offset(0, 2), blurRadius: 10.0, color: Colors.black38),
    ],
  );

  /// Distance/Pace/Time values.
  static TextStyle get _mapMetricValueStyle => GoogleFonts.barlowCondensed(
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: Colors.white,
    fontFeatures: const [FontFeature.tabularFigures()],
    shadows: _shadow,
  );

  /// DISTANCE/PACE/TIME labels.
  static TextStyle get _mapMetricLabelStyle => GoogleFonts.inter(
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.5,
    color: Colors.white.withValues(alpha: 0.8),
    shadows: _shadow,
  );

  String get _distanceText => '${data.distanceKm.toStringAsFixed(2)} km';
  String get _distanceTextShort => '${data.distanceKm.toStringAsFixed(1)} km';
  String get _paceText => '${data.averagePace} /km';

  /// "Xh Ym Zs" or "Xm Ys".
  String _formatDurationWords(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (template) {
      ShareCardTemplate.full => _buildFullContent(),
      ShareCardTemplate.overlayDuo => _buildOverlayDuoContent(),
      ShareCardTemplate.overlayTrio => _buildOverlayTrioContent(),
      ShareCardTemplate.verticalMetrics => _buildVerticalMetricsContent(),
      ShareCardTemplate.telemetryHud => _buildTelemetryHudContent(),
      ShareCardTemplate.raceTicket => _buildRaceTicketContent(),
    };

    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: content,
      ),
    );
  }

  // ── Full Map Route — watermark, orange route, telemetry bar ─────────────

  Widget _buildFullContent() {
    final hasRoute = data.gpsPoints.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('ENDURA', style: _brandMarkStyle),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: hasRoute
                  ? CustomPaint(
                      size: Size.infinite,
                      painter: RouteTracePainter(
                        points: data.gpsPoints,
                        color: Colors.white,
                        strokeWidth: 4,
                        dropShadow: true,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMapMetric('DISTANCE', _distanceText),
            _buildMapMetric('PACE', _paceText),
            _buildMapMetric('TIME', _formatDurationWords(data.durationSeconds)),
          ],
        ),
      ],
    );
  }

  /// One of three equal-width telemetry columns; scales down instead of
  /// overflowing on long values (e.g. "3h 42m 10s").
  Widget _buildMapMetric(String label, String value) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _mapMetricLabelStyle),
            const SizedBox(height: 4),
            Text(value, style: _mapMetricValueStyle.copyWith(fontSize: 20)),
          ],
        ),
      ),
    );
  }

  // ── Overlay Duo — Distance + Pace ───────────────────────────────────────

  Widget _buildOverlayDuoContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverlayStat('Distance', _distanceTextShort),
                const SizedBox(width: 48),
                _buildOverlayStat('Pace', _paceText),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('ENDURA', style: _brandMarkStyle),
        ],
      ),
    );
  }

  // ── Overlay Trio — Distance + Pace + Time ───────────────────────────────

  Widget _buildOverlayTrioContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverlayStat('Distance', _distanceTextShort),
                const SizedBox(width: 32),
                _buildOverlayStat('Pace', _paceText),
                const SizedBox(width: 32),
                _buildOverlayStat(
                  'Time',
                  _formatDurationWords(data.durationSeconds),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('ENDURA', style: _brandMarkStyle),
        ],
      ),
    );
  }

  /// Label in a clean medium-weight sans-serif, value in an italic serif
  /// display cut.
  Widget _buildOverlayStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.8),
            letterSpacing: 0.8,
            shadows: _shadow,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'serif',
            fontStyle: FontStyle.italic,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: _shadow,
          ),
        ),
      ],
    );
  }

  // ── Vertical Stack — Distance / Time / Pace, ENDURA below ───────────────

  Widget _buildVerticalMetricsContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildVerticalMetric('DISTANCE', _distanceText),
          const SizedBox(height: 28),
          _buildVerticalMetric(
            'TIME',
            _formatDurationWords(data.durationSeconds),
          ),
          const SizedBox(height: 28),
          _buildVerticalMetric('PACE', _paceText),
          const SizedBox(height: 36),
          Text('ENDURA', style: _brandMarkStyle),
        ],
      ),
    );
  }

  Widget _buildVerticalMetric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mapMetricLabelStyle),
        const SizedBox(height: 6),
        Text(value, style: _mapMetricValueStyle.copyWith(fontSize: 44)),
      ],
    );
  }

  // ── Telemetry HUD — monospaced flight-recorder readout ──────────────────
  // Space Mono / Libre Barcode are scoped to these two templates only.

  static const List<String> _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  String get _hudDate =>
      '${data.date.day.toString().padLeft(2, '0')} '
      '${_months[data.date.month - 1]} ${data.date.year}';

  /// Code 39 payload: `*DDMMYYYY*` (asterisks are the start/stop characters).
  String get _barcodeDate =>
      '*${data.date.day.toString().padLeft(2, '0')}'
      '${data.date.month.toString().padLeft(2, '0')}'
      '${data.date.year}*';

  Widget _buildTelemetryHudContent() {
    final style = GoogleFonts.spaceMono(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      shadows: _shadow,
    );
    Widget row(String key, String value) => Row(
      children: [
        SizedBox(width: 78, child: Text('$key:', style: style)),
        Expanded(child: Text(value.toUpperCase(), style: style)),
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('DATE', _hudDate),
            const Divider(color: Colors.white54, thickness: 1, height: 22),
            row('DIST', _distanceTextShort),
            const SizedBox(height: 8),
            row('PACE', _paceText),
            const SizedBox(height: 8),
            row('TIME', _formatDurationWords(data.durationSeconds)),
            const SizedBox(height: 16),
            Text(
              'ENDURA',
              style: GoogleFonts.spaceMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
                color: Colors.white,
                shadows: _shadow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Race Ticket — barcode, compact metrics row, footer ──────────────────

  Widget _buildRaceTicketContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              child: Text(
                _barcodeDate,
                style: GoogleFonts.libreBarcode39(
                  fontSize: 54,
                  color: Colors.white,
                  shadows: _shadow,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMapMetric('DISTANCE', _distanceText),
              _buildMapMetric('PACE', _paceText),
              _buildMapMetric(
                'TIME',
                _formatDurationWords(data.durationSeconds),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'SHARED BY',
                style: _mapMetricLabelStyle.copyWith(
                  fontSize: 9,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              Text('ENDURA', style: _brandMarkStyle),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grey checkerboard shown behind transparent previews so the user can see
/// which parts of the export have no background.
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 16.0;
    final light = Paint()..color = const Color(0xFF3A3A3C);
    final dark = Paint()..color = const Color(0xFF2C2C2E);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isLight = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          isLight ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) => false;
}
