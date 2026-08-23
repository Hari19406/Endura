import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';

// Endura teal — brand color, intentionally not a theme token (fixed across light/dark)
const _kBrand = Color(0xFF00E5CC);
const _kTermsUrl =
    'https://laced-drill-6ab.notion.site/Terms-of-Service-for-Endura-3862582d8c2d80358fcfcc0442194dc7';
const _kPrivacyUrl =
    'https://laced-drill-6ab.notion.site/Privacy-Policy-for-Endura-3862582d8c2d802b9495d8391dadfb44';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Package? _annualPackage;
  Package? _monthlyPackage;
  Package? _selected;
  bool _loadingOffering = true;
  String? _purchasingId;

  @override
  void initState() {
    super.initState();
    Analytics.paywallViewed();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    final offering = await RevenueCatService.getOffering();
    if (mounted) {
      setState(() {
        _annualPackage = offering.annual;
        _monthlyPackage = offering.monthly;
        // Default to the annual plan — the trial-led path.
        _selected = offering.annual ?? offering.monthly;
        _loadingOffering = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
    HapticFeedback.mediumImpact();
    setState(() => _purchasingId = package.identifier);
    try {
      final nowPro = await RevenueCatService.purchasePackage(package);
      if (nowPro) {
        await Analytics.subscriptionStarted();
        if (mounted) Navigator.pop(context, true);
      }
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    } catch (e) {
      debugPrint('[Paywall] purchase error: $e');
    } finally {
      if (mounted) setState(() => _purchasingId = null);
    }
  }

  Future<void> _restore() async {
    HapticFeedback.lightImpact();
    setState(() => _purchasingId = 'restore');
    try {
      final nowPro = await RevenueCatService.restorePurchases();
      if (mounted) {
        if (nowPro) {
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active subscription found.')),
          );
        }
      }
    } catch (e) {
      debugPrint('[Paywall] restore error: $e');
    } finally {
      if (mounted) setState(() => _purchasingId = null);
    }
  }

  String _friendlyError(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.networkError:
        return 'No internet. Check your connection and try again.';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchases are not enabled on this device.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Payment is pending — check your App Store account.';
      default:
        return 'Something went wrong. Try again or restore purchases.';
    }
  }

  // ---- Trial helpers (driven off the selected package) -------------------

  IntroductoryPrice? _introOf(Package? pkg) {
    final intro = pkg?.storeProduct.introductoryPrice;
    if (intro == null || intro.price > 0) return null;
    return intro;
  }

  int _trialDays(IntroductoryPrice intro) {
    final n = intro.periodNumberOfUnits;
    switch (intro.periodUnit) {
      case PeriodUnit.week:
        return n * 7;
      case PeriodUnit.month:
        return n * 30;
      case PeriodUnit.day:
      default:
        return n;
    }
  }

  String _monthlyEquivalent(Package pkg) {
    final price = pkg.storeProduct.price;
    final symbol = pkg.storeProduct.priceString
        .replaceAll(RegExp(r'[\d.,\s]'), '')
        .trim();
    final monthly = price / 12;
    return '$symbol${monthly.toStringAsFixed(2)}';
  }

  int? _savingsPercent() {
    final a = _annualPackage, m = _monthlyPackage;
    if (a == null || m == null) return null;
    final yearAtMonthly = m.storeProduct.price * 12;
    if (yearAtMonthly <= 0) return null;
    final pct = (1 - a.storeProduct.price / yearAtMonthly) * 100;
    if (pct <= 0) return null;
    return pct.round();
  }

  bool get _selectedIsAnnual =>
      _selected != null && _selected == _annualPackage;

  void _openPlanPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlanPickerSheet(
        annual: _annualPackage,
        monthly: _monthlyPackage,
        selected: _selected,
        savingsPercent: _savingsPercent(),
        monthlyEquivalent: _annualPackage != null
            ? _monthlyEquivalent(_annualPackage!)
            : null,
        onPick: (pkg) {
          HapticFeedback.selectionClick();
          setState(() => _selected = pkg);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _purchasingId != null;
    final intro = _introOf(_selected);
    final hasTrial = intro != null;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // Teal hero glow behind the header, fading into the background.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _kBrand.withValues(alpha: 0.35),
                      _kBrand.withValues(alpha: 0.12),
                      _kBrand.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                    child: IconButton(
                      icon: Icon(Icons.close, color: c.textTertiary),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context, false);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: _loadingOffering
                      ? const Center(
                          child: CircularProgressIndicator(color: _kBrand),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Endura Pro',
                                style: TextStyle(
                                  color: _kBrand,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hasTrial
                                    ? 'How your ${_trialDays(intro)}-day\nfree trial works'
                                    : 'Coached running.\nBuilt around you.',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (hasTrial)
                                _TrialTimeline(
                                  colors: c,
                                  trialDays: _trialDays(intro),
                                )
                              else
                                _FeatureList(colors: c),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                ),
                // ---- Footer: price summary + CTA --------------------------------
                if (!_loadingOffering && _selected != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Column(
                      children: [
                        _PriceSummary(
                          colors: c,
                          selected: _selected!,
                          isAnnual: _selectedIsAnnual,
                          hasTrial: hasTrial,
                          trialDays: hasTrial ? _trialDays(intro) : 0,
                          monthlyEquivalent: _selectedIsAnnual
                              ? _monthlyEquivalent(_selected!)
                              : null,
                          savingsPercent: _selectedIsAnnual
                              ? _savingsPercent()
                              : null,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: busy
                                ? null
                                : () => _purchase(_selected!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kBrand,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: _kBrand.withValues(
                                alpha: 0.5,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: _purchasingId == _selected!.identifier
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black45,
                                    ),
                                  )
                                : Text(
                                    hasTrial ? 'Continue' : 'Subscribe',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_monthlyPackage != null && _annualPackage != null)
                          TextButton(
                            onPressed: busy ? null : _openPlanPicker,
                            child: Text(
                              'See all plans',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: busy ? null : _restore,
                          child: _purchasingId == 'restore'
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white38,
                                  ),
                                )
                              : Text(
                                  'Restore purchases',
                                  style: TextStyle(
                                    color: c.textTertiary,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegalLink('Terms of Use', _kTermsUrl, c.textFaint),
                            Text(
                              '  ·  ',
                              style: TextStyle(
                                color: c.textFaint,
                                fontSize: 11,
                              ),
                            ),
                            _LegalLink(
                              'Privacy Policy',
                              _kPrivacyUrl,
                              c.textFaint,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Auto-renews. Cancel anytime in settings.',
                          style: TextStyle(color: c.textFaint, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Trial timeline (Today → reminder → billed) --------------------------

class _TrialTimeline extends StatelessWidget {
  final AppColors colors;
  final int trialDays;

  const _TrialTimeline({required this.colors, required this.trialDays});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final reminderDay = (trialDays - 2).clamp(1, trialDays);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _TimelineStep(
            colors: c,
            icon: Icons.lock_outline_rounded,
            title: 'Today',
            body:
                'Unlock Endura Pro in full — adaptive plans, guided sessions and race paces from Max.',
            isFirst: true,
            isLast: false,
          ),
          _TimelineStep(
            colors: c,
            icon: Icons.notifications_none_rounded,
            title: 'Day $reminderDay',
            body: "We'll send a reminder that your free trial is ending soon.",
            isFirst: false,
            isLast: false,
          ),
          _TimelineStep(
            colors: c,
            icon: Icons.star_rounded,
            title: 'Day $trialDays',
            body:
                'Your subscription begins. Cancel any time before this to avoid being charged.',
            isFirst: false,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final AppColors colors;
  final IconData icon;
  final String title;
  final String body;
  final bool isFirst;
  final bool isLast;

  const _TimelineStep({
    required this.colors,
    required this.icon,
    required this.title,
    required this.body,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Continuous vertical bar: solid through the steps, rounded cap on
          // the first, fading out below the last icon (Buddy-style).
          SizedBox(
            width: 36,
            child: Container(
              decoration: BoxDecoration(
                color: isLast ? null : _kBrand,
                gradient: isLast
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_kBrand, _kBrand.withValues(alpha: 0.0)],
                      )
                    : null,
                borderRadius: isFirst
                    ? const BorderRadius.vertical(top: Radius.circular(18))
                    : null,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: isFirst ? 10 : 6),
                  child: Icon(icon, color: Colors.black, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Fallback feature list (shown when the plan has no trial) -------------

class _FeatureList extends StatelessWidget {
  final AppColors colors;
  const _FeatureList({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    const features = [
      'Adaptive plans that react to your runs week by week',
      'Threshold, VO₂max & long run sessions guided by Max',
      'vDOT fitness tracking — Max gets smarter every run',
      'Race target paces set automatically for your goal',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: features
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: _kBrand,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(color: c.textPrimary, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ---- Price summary above the CTA -----------------------------------------

class _PriceSummary extends StatelessWidget {
  final AppColors colors;
  final Package selected;
  final bool isAnnual;
  final bool hasTrial;
  final int trialDays;
  final String? monthlyEquivalent;
  final int? savingsPercent;

  const _PriceSummary({
    required this.colors,
    required this.selected,
    required this.isAnnual,
    required this.hasTrial,
    required this.trialDays,
    required this.monthlyEquivalent,
    required this.savingsPercent,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final price = selected.storeProduct.priceString;
    final period = isAnnual ? 'year' : 'month';

    final headline = hasTrial
        ? '$trialDays days free, then $price/$period'
        : '$price/$period';

    final sub = isAnnual
        ? (monthlyEquivalent != null
              ? "That's just $monthlyEquivalent/mo, billed annually"
              : 'Billed annually')
        : 'Billed monthly';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (savingsPercent != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kBrand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SAVE $savingsPercent%',
                  style: const TextStyle(
                    color: _kBrand,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(sub, style: TextStyle(color: c.textTertiary, fontSize: 13)),
      ],
    );
  }
}

// ---- "See all plans" bottom sheet ----------------------------------------

class _PlanPickerSheet extends StatelessWidget {
  final Package? annual;
  final Package? monthly;
  final Package? selected;
  final int? savingsPercent;
  final String? monthlyEquivalent;
  final ValueChanged<Package> onPick;

  const _PlanPickerSheet({
    required this.annual,
    required this.monthly,
    required this.selected,
    required this.savingsPercent,
    required this.monthlyEquivalent,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Choose your plan',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (annual != null)
            _PlanRow(
              colors: c,
              title: 'Yearly',
              price: '${annual!.storeProduct.priceString}/yr',
              subtitle: monthlyEquivalent != null
                  ? '$monthlyEquivalent/mo · billed annually'
                  : 'Billed annually',
              badge: savingsPercent != null ? 'SAVE $savingsPercent%' : null,
              isSelected: selected == annual,
              onTap: () => onPick(annual!),
            ),
          const SizedBox(height: 12),
          if (monthly != null)
            _PlanRow(
              colors: c,
              title: 'Monthly',
              price: '${monthly!.storeProduct.priceString}/mo',
              subtitle: 'Billed monthly · cancel anytime',
              badge: null,
              isSelected: selected == monthly,
              onTap: () => onPick(monthly!),
            ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final AppColors colors;
  final String title;
  final String price;
  final String subtitle;
  final String? badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlanRow({
    required this.colors,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _kBrand : c.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? _kBrand : c.textTertiary,
              size: 24,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kBrand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: _kBrand,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: c.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  final String label;
  final String url;
  final Color color;

  const _LegalLink(this.label, this.url, this.color);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    );
  }
}
