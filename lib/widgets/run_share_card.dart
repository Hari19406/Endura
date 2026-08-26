import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/analytics_service.dart';
import '../services/social_share_service.dart';
import '../theme/app_colors.dart';
import '../utils/database_service.dart';
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

/// Visual style of the exported card.
/// [transparent] has no background at all — stats and route float on alpha,
/// for overlaying on the user's own photos/videos (Strava-style). Applies to
/// every [ShareCardTemplate], including [ShareCardTemplate.poster].
enum ShareCardStyle { classic, transparent }

/// Layout of the exported card. All render at the same story size.
enum ShareCardTemplate {
  full,
  compact,
  blank,
  poster,
  weekByDay,
  bigDistance,
  timeOnFeet,
  statsOnly,
}

/// Grouping used by the "Pick a layout" picker sheet. [charts] has no
/// templates yet — it renders a "Coming soon" placeholder.
enum ShareCardCategory { all, charts, activity }

ShareCardCategory _categoryOf(ShareCardTemplate t) => ShareCardCategory.activity;

String _labelOf(ShareCardTemplate t) => switch (t) {
  ShareCardTemplate.full => 'Full',
  ShareCardTemplate.compact => 'Compact',
  ShareCardTemplate.blank => 'Blank',
  ShareCardTemplate.poster => 'Poster',
  ShareCardTemplate.weekByDay => 'Week by Day',
  ShareCardTemplate.bigDistance => 'Big Distance',
  ShareCardTemplate.timeOnFeet => 'Time on Feet',
  ShareCardTemplate.statsOnly => 'Stats Only',
};

String _categoryLabel(ShareCardCategory c) => switch (c) {
  ShareCardCategory.all => 'All',
  ShareCardCategory.charts => 'Charts',
  ShareCardCategory.activity => 'Activity',
};

/// Per-day distance for the Mon–Sun week containing [ShareRunData.date],
/// used by [ShareCardTemplate.weekByDay]. Index 0 = Monday.
Future<List<double>> _loadWeekKm(DateTime anchor) async {
  final weekStart = DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
  ).subtract(Duration(days: anchor.weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 7));

  final runs = await DatabaseService.instance.getAllRuns();
  final km = List<double>.filled(7, 0.0);
  for (final r in runs) {
    if (r.date.isBefore(weekStart) || !r.date.isBefore(weekEnd)) continue;
    final dayIndex = r.date.weekday - 1;
    km[dayIndex] += r.distanceKm;
  }
  return km;
}

/// Opens a bottom sheet with a story-format preview of the run card, a
/// template picker, a style toggle (opaque / transparent), and quick
/// share/save actions.
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
  ShareCardStyle _style = ShareCardStyle.classic;
  bool _busy = false;
  List<double>? _weekKm;

  String get _styleName =>
      _style == ShareCardStyle.transparent ? 'transparent' : 'classic';

  String get _templateName => _template.name;

  String get _templateLabel => _labelOf(_template);

  @override
  void initState() {
    super.initState();
    _loadWeekKm(widget.data.date)
        .then((km) {
          if (mounted) setState(() => _weekKm = km);
        })
        .catchError((e) {
          debugPrint('[RunShareSheet] week load failed: $e');
        });
  }

  Future<Uint8List> _renderPng() async {
    final boundary =
        _cardKeys[_template]!.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    // 360x640 logical * 3 = 1080x1920, native story resolution.
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
        style: _styleName,
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
        style: _styleName,
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
        style: _styleName,
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
      builder: (_) => _LayoutPickerSheet(
        data: widget.data,
        style: _style,
        weekKm: _weekKm,
        selected: _template,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _template = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isTransparent = _style == ShareCardStyle.transparent;
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

          // Style toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChip(
                'Solid',
                _style == ShareCardStyle.classic,
                () => setState(() => _style = ShareCardStyle.classic),
              ),
              const SizedBox(width: 8),
              _buildChip(
                'Transparent',
                _style == ShareCardStyle.transparent,
                () => setState(() => _style = ShareCardStyle.transparent),
              ),
            ],
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
                    painter: isTransparent ? _CheckerboardPainter() : null,
                    child: RepaintBoundary(
                      key: _cardKeys[_template],
                      child: RunShareCard(
                        data: widget.data,
                        template: _template,
                        style: _style,
                        weekKm: _weekKm,
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
                  icon: Icons.ios_share,
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
                      color: tint.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: tint.withOpacity(0.35)),
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

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? c.onAccent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// "Pick a layout" bottom sheet — category tabs (All / Charts / Activity)
/// over a grid of live thumbnails. Pops the tapped [ShareCardTemplate].
class _LayoutPickerSheet extends StatefulWidget {
  final ShareRunData data;
  final ShareCardStyle style;
  final List<double>? weekKm;
  final ShareCardTemplate selected;

  const _LayoutPickerSheet({
    required this.data,
    required this.style,
    required this.weekKm,
    required this.selected,
  });

  @override
  State<_LayoutPickerSheet> createState() => _LayoutPickerSheetState();
}

class _LayoutPickerSheetState extends State<_LayoutPickerSheet> {
  ShareCardCategory _category = ShareCardCategory.all;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final templates = ShareCardTemplate.values
        .where(
          (t) =>
              _category == ShareCardCategory.all ||
              _categoryOf(t) == _category,
        )
        .toList();

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final cat in ShareCardCategory.values) ...[
                      _buildCategoryChip(cat),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _category == ShareCardCategory.charts
                    ? _buildComingSoon(c)
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.62,
                            ),
                        itemCount: templates.length,
                        itemBuilder: (context, i) =>
                            _buildThumbnail(templates[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildComingSoon(AppColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 40, color: c.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chart-based layouts are on the way',
            style: TextStyle(fontSize: 12, color: c.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(ShareCardCategory cat) {
    final c = context.colors;
    final selected = _category == cat;
    return GestureDetector(
      onTap: () => setState(() => _category = cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: Text(
          _categoryLabel(cat),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? c.onAccent : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ShareCardTemplate t) {
    final c = context.colors;
    final isSelected = t == widget.selected;
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
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: RunShareCard.width,
                  height: RunShareCard.height,
                  child: IgnorePointer(
                    child: RunShareCard(
                      data: widget.data,
                      template: t,
                      style: widget.style,
                      weekKm: widget.weekKm,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _labelOf(t),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  _categoryLabel(_categoryOf(t)),
                  style: TextStyle(fontSize: 10, color: c.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The story-format (9:16) card itself. Always uses its own fixed palette
/// regardless of app theme — it's a branded export, not an in-app surface.
/// [ShareCardStyle.transparent] drops the background entirely (any template)
/// so the exported PNG keeps its alpha channel; text/route colors stay put
/// so legibility is the user's call based on what they overlay it on.
class RunShareCard extends StatelessWidget {
  final ShareRunData data;
  final ShareCardTemplate template;
  final ShareCardStyle style;
  /// Mon–Sun distance for [ShareCardTemplate.weekByDay]; null while loading,
  /// in which case the template renders with all-zero bars.
  final List<double>? weekKm;

  const RunShareCard({
    super.key,
    required this.data,
    this.template = ShareCardTemplate.full,
    this.style = ShareCardStyle.classic,
    this.weekKm,
  });

  static const double width = 360;
  static const double height = 640;

  static const Color _darkBg = Color(0xFF0A0A0A);
  static const Color _posterBg = Color(0xFFF3EFE6);
  static const Color _posterInk = Color(0xFF2A2620);
  static const Color _posterInkMuted = Color(0xFF8C8577);

  /// Endura's actual brand color (same value as AppColors.chartAccent and
  /// the paywall's brand accent) — used for the route trace on every
  /// template, not just Poster.
  static const Color _mapBlue = Color(0xFF00E5CC);

  /// Shared big/bold wordmark treatment used at the top of every template.
  static const TextStyle _wordmarkStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    letterSpacing: 3,
  );

  /// Route trace capped to a fixed box — a long thin out-and-back doesn't
  /// blow up to fill the whole card, a tight loop doesn't look tiny. Always
  /// returns a fixed-footprint widget (never `Expanded`/`.expand()`-based),
  /// so it's safe to drop straight into a `Center`-ed, shrink-wrapped
  /// Column (Compact) as well as inside an `Expanded` (Full/Blank/Poster).
  Widget _buildRouteBox({
    required bool isTransparent,
    required double boxWidth,
    required double boxHeight,
    double strokeWidth = 3,
    bool showPlaceholderIcon = true,
  }) {
    final hasRoute = data.gpsPoints.length > 1;
    Widget inner;
    if (hasRoute) {
      inner = CustomPaint(
        size: Size.infinite,
        painter: _ShareRoutePainter(
          points: data.gpsPoints,
          color: _mapBlue,
          strokeWidth: strokeWidth,
        ),
      );
    } else if (showPlaceholderIcon && !isTransparent) {
      inner = Center(
        child: Icon(
          Icons.directions_run,
          color: Colors.white12,
          size: boxWidth * 0.5,
        ),
      );
    } else {
      inner = const SizedBox.shrink();
    }
    return SizedBox(width: boxWidth, height: boxHeight, child: inner);
  }

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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final wColor = WorkoutTypeStyle.color(data.workoutType);
    final isTransparent = style == ShareCardStyle.transparent;
    final isPoster = template == ShareCardTemplate.poster;
    final background = isTransparent ? null : (isPoster ? _posterBg : _darkBg);

    final content = switch (template) {
      ShareCardTemplate.full => _buildFullContent(wColor, isTransparent),
      ShareCardTemplate.compact => _buildCompactContent(isTransparent),
      ShareCardTemplate.blank => _buildBlankContent(isTransparent),
      ShareCardTemplate.poster => _buildPosterContent(isTransparent),
      ShareCardTemplate.weekByDay => _buildWeekByDayContent(),
      ShareCardTemplate.bigDistance => _buildBigDistanceContent(),
      ShareCardTemplate.timeOnFeet => _buildTimeOnFeetContent(),
      ShareCardTemplate.statsOnly => _buildStatsOnlyContent(),
    };

    return Container(
      width: width,
      height: height,
      color: background,
      child: Stack(
        children: [
          if (template == ShareCardTemplate.full && !isTransparent)
            // Subtle brand glow behind the route.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.1,
                    colors: [wColor.withOpacity(0.10), Colors.transparent],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: content,
          ),
        ],
      ),
    );
  }

  // ── Full — route trace + hero distance ──────────────────────────────────

  Widget _buildFullContent(Color wColor, bool isTransparent) {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text(
          _formatDate(data.date),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Center(
            child: _buildRouteBox(
              isTransparent: isTransparent,
              boxWidth: 220,
              boxHeight: 220,
            ),
          ),
        ),
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
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildStat(
              'AVG PACE',
              UnitUtils.formatPaceString(data.averagePace, data.useMiles),
              UnitUtils.perUnitLabel(data.useMiles),
            ),
            const SizedBox(width: 36),
            if (data.durationSeconds > 0)
              _buildStat('TIME', _formatDuration(data.durationSeconds), ''),
          ],
        ),
        const SizedBox(height: 28),
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
            color: Colors.white,
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
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Compact — wordmark + date header, stats stacked at the bottom ───────

  Widget _buildCompactContent(bool isTransparent) {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildRouteBox(
            isTransparent: isTransparent,
            boxWidth: 170,
            boxHeight: 170,
          ),
          const SizedBox(height: 24),
          _buildCompactStat(
            'DISTANCE',
            distanceValue.toStringAsFixed(2),
            UnitUtils.unitLabel(data.useMiles),
          ),
          const SizedBox(height: 14),
          _buildCompactStat(
            'PACE',
            UnitUtils.formatPaceString(data.averagePace, data.useMiles),
            UnitUtils.perUnitLabel(data.useMiles),
          ),
          if (data.durationSeconds > 0) ...[
            const SizedBox(height: 14),
            _buildCompactStat(
              'TIME',
              _formatDuration(data.durationSeconds),
              '',
            ),
          ],
          const SizedBox(height: 28),
          Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildCompactStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Blank — wordmark header, route trace, stats pinned low ──────────────

  Widget _buildBlankContent(bool isTransparent) {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        Expanded(
          child: Center(
            child: _buildRouteBox(
              isTransparent: isTransparent,
              boxWidth: 220,
              boxHeight: 220,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBlankStat(
              'DISTANCE',
              '${distanceValue.toStringAsFixed(2)}${UnitUtils.unitLabel(data.useMiles)}',
            ),
            _buildBlankStat(
              'PACE',
              '${UnitUtils.formatPaceString(data.averagePace, data.useMiles)}${UnitUtils.perUnitLabel(data.useMiles)}',
            ),
            if (data.durationSeconds > 0)
              _buildBlankStat('TIME', _formatDuration(data.durationSeconds)),
          ],
        ),
      ],
    );
  }

  Widget _buildBlankStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // ── Poster — light ground, one bold route stroke ────────────────────────

  Widget _buildPosterContent(bool isTransparent) {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: _posterInk)),
        Expanded(
          child: Center(
            child: _buildRouteBox(
              isTransparent: isTransparent,
              boxWidth: 230,
              boxHeight: 320,
              strokeWidth: 9,
              showPlaceholderIcon: false,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DISTANCE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _posterInkMuted,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceValue.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: _posterInk,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      UnitUtils.unitLabel(data.useMiles),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _posterInkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'PACE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _posterInkMuted,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${UnitUtils.formatPaceString(data.averagePace, data.useMiles)}${UnitUtils.perUnitLabel(data.useMiles)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _posterInk,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── Week by Day — Mon–Sun bar chart of the week this run falls in ───────

  Widget _buildWeekByDayContent() {
    final km = weekKm ?? List<double>.filled(7, 0.0);
    final total = km.fold<double>(0, (a, b) => a + b);
    final maxKm = km.fold<double>(0.001, (a, b) => a > b ? a : b);
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final todayIndex = data.date.weekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'THIS WEEK',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${total.toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _mapBlue,
              ),
            ),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < 7; i++)
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      km[i] > 0 ? km[i].toStringAsFixed(1) : '',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 22,
                      height: 8 + (km[i] / maxKm) * 210,
                      decoration: BoxDecoration(
                        color: km[i] > 0 ? _mapBlue : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                        border: i == todayIndex
                            ? Border.all(color: Colors.white, width: 1.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayLetters[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: i == todayIndex
                            ? Colors.white
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.directions_run, size: 13, color: _mapBlue),
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
    );
  }

  // ── Big Distance — single oversized hero stat ────────────────────────────

  Widget _buildBigDistanceContent() {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DISTANCE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceValue.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -3,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      UnitUtils.unitLabel(data.useMiles),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.directions_run, size: 13, color: WorkoutTypeStyle.color(data.workoutType)),
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
    );
  }

  // ── Time on Feet — single oversized hero stat, duration-led ──────────────

  Widget _buildTimeOnFeetContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TIME ON FEET',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _formatDuration(data.durationSeconds),
                  style: const TextStyle(
                    fontSize: 68,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -2,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.directions_run, size: 13, color: WorkoutTypeStyle.color(data.workoutType)),
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
    );
  }

  // ── Stats Only — three-column row, no route ──────────────────────────────

  Widget _buildStatsOnlyContent() {
    final distanceValue = UnitUtils.displayDistance(
      data.distanceKm,
      data.useMiles,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENDURA', style: _wordmarkStyle.copyWith(color: Colors.white)),
        Expanded(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildCompactStat(
                  'DISTANCE',
                  distanceValue.toStringAsFixed(2),
                  UnitUtils.unitLabel(data.useMiles),
                ),
                _buildCompactStat(
                  'TIME',
                  _formatDuration(data.durationSeconds),
                  '',
                ),
                _buildCompactStat(
                  'PACE',
                  UnitUtils.formatPaceString(data.averagePace, data.useMiles),
                  UnitUtils.perUnitLabel(data.useMiles),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Icon(Icons.directions_run, size: 13, color: WorkoutTypeStyle.color(data.workoutType)),
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
    );
  }
}

/// Route trace on a transparent background. White by default; [color] and
/// [strokeWidth] let the poster template draw a heavier, colored stroke.
class _ShareRoutePainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Color color;
  final double strokeWidth;

  const _ShareRoutePainter({
    required this.points,
    this.color = Colors.white,
    this.strokeWidth = 3,
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
      ..color = color.withOpacity(0.95)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_ShareRoutePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Grey checkerboard shown behind the transparent preview so the user can
/// see which parts of the export have no background.
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
