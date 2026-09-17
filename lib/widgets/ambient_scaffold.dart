// lib/widgets/ambient_scaffold.dart
//
// Shared "Night Ultra" ambient background — the staggered 4-node zig-zag
// radial glow originally built for the Home dashboard. Wrap any screen's
// Scaffold content in this instead of `Scaffold(...)` directly to pick up
// the same theme-aware glow (boosted alphas in light mode, since the same
// low alphas that read as a punchy glow on a near-black background wash
// out to nothing against a near-white one).

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AmbientScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;

  /// Wraps [body] in a [SafeArea] when true (default). Set to false when the
  /// screen already manages its own insets (e.g. it supplies its own
  /// padding, or it's embedded inside another Scaffold that already applies
  /// safe-area handling).
  final bool safeArea;

  const AmbientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.safeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Light-theme surfaces are near-white, so the same low alphas that read
    // as a punchy glow on a near-black dark background wash out to nothing.
    // Boost intensity substantially in light mode to compensate.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glowNode1Alpha = isDark ? 0.28 : 0.42;
    final glowNode2Alpha = isDark ? 0.22 : 0.35;
    final glowNode3Alpha = isDark ? 0.20 : 0.32;
    final glowNode4Alpha = isDark ? 0.24 : 0.38;
    final glowStop = isDark ? 0.7 : 0.75;

    final content = safeArea ? SafeArea(child: body) : body;

    return Scaffold(
      backgroundColor: c.background,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          // Base fill — the solid color every glow node fades out to.
          Positioned.fill(child: ColoredBox(color: c.background)),
          // Ambient lighting nodes, staggered zig-zag around the edges.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.1, -0.9),
                    radius: 1.3,
                    colors: [
                      c.heroGradientEnd.withValues(alpha: glowNode1Alpha),
                      Colors.transparent,
                    ],
                    stops: [0.0, glowStop],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.2, -0.25),
                    radius: 1.2,
                    colors: [
                      c.heroGradientStart.withValues(alpha: glowNode2Alpha),
                      Colors.transparent,
                    ],
                    stops: [0.0, glowStop],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.2, 0.4),
                    radius: 1.2,
                    colors: [
                      c.heroGradientEnd.withValues(alpha: glowNode3Alpha),
                      Colors.transparent,
                    ],
                    stops: [0.0, glowStop],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.1, 0.95),
                    radius: 1.3,
                    colors: [
                      c.heroGradientStart.withValues(alpha: glowNode4Alpha),
                      Colors.transparent,
                    ],
                    stops: [0.0, glowStop],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: content),
        ],
      ),
    );
  }
}
