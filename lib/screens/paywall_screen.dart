import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  String _userName = '';

  @override
  void initState() {
    super.initState();
    Analytics.paywallViewed();
    _loadOffering();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String name = prefs.getString('user_name') ?? '';
      if (name.isEmpty) {
        final user = Supabase.instance.client.auth.currentUser;
        final meta = user?.userMetadata;
        name =
            (meta?['name'] as String?) ?? (meta?['full_name'] as String?) ?? '';
        if (name.isEmpty) {
          name = user?.email?.split('@').first ?? '';
        }
      }
      if (mounted) setState(() => _userName = name.split(' ').first);
    } catch (e) {
      debugPrint('[Paywall] load name error: $e');
    }
  }

  Future<void> _loadOffering() async {
    setState(() => _loadingOffering = true);
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

  bool get _offeringUnavailable =>
      !_loadingOffering && _annualPackage == null && _monthlyPackage == null;

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
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Hero(colors: c, userName: _userName),
                              const SizedBox(height: 28),
                              if (_annualPackage != null ||
                                  _monthlyPackage != null)
                                _InlinePlanSelector(
                                  colors: c,
                                  annual: _annualPackage,
                                  monthly: _monthlyPackage,
                                  selected: _selected,
                                  savingsPercent: _savingsPercent(),
                                  monthlyEquivalent: _annualPackage != null
                                      ? _monthlyEquivalent(_annualPackage!)
                                      : null,
                                  introOf: _introOf,
                                  trialDaysOf: _trialDays,
                                  onPick: (pkg) {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selected = pkg);
                                  },
                                )
                              else if (_offeringUnavailable)
                                _OfferingUnavailableCard(
                                  colors: c,
                                  onRetry: _loadOffering,
                                ),
                              const SizedBox(height: 32),
                              if (hasTrial)
                                _TrialTimeline(
                                  colors: c,
                                  trialDays: _trialDays(intro),
                                ),
                              if (hasTrial) const SizedBox(height: 32),
                              _FeatureList(colors: c),
                              const SizedBox(height: 20),
                              _GuaranteeCard(colors: c),
                              const SizedBox(height: 16),
                              _TrustBanner(colors: c),
                            ],
                          ),
                        ),
                ),
                // ---- Footer: price summary + CTA --------------------------------
                if (_offeringUnavailable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _loadOffering,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          'Retry',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!_loadingOffering && _selected != null)
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
                                    hasTrial ? 'Start free trial' : 'Subscribe',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
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

// ---- Hero: personalized greeting ------------------------------------------

class _Hero extends StatelessWidget {
  final AppColors colors;
  final String userName;

  const _Hero({required this.colors, required this.userName});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final greeting = userName.isNotEmpty
        ? '$userName, your training\nstarts now'
        : 'Your training\nstarts now';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ENDURA PRO',
          style: TextStyle(
            color: _kBrand,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          greeting,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.bold,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A plan built around your goal race, with Max adjusting every week to keep you on track.',
          style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.4),
        ),
      ],
    );
  }
}

// ---- Inline plan selector (Annual / Monthly cards) ------------------------

class _InlinePlanSelector extends StatelessWidget {
  final AppColors colors;
  final Package? annual;
  final Package? monthly;
  final Package? selected;
  final int? savingsPercent;
  final String? monthlyEquivalent;
  final IntroductoryPrice? Function(Package?) introOf;
  final int Function(IntroductoryPrice) trialDaysOf;
  final ValueChanged<Package> onPick;

  const _InlinePlanSelector({
    required this.colors,
    required this.annual,
    required this.monthly,
    required this.selected,
    required this.savingsPercent,
    required this.monthlyEquivalent,
    required this.introOf,
    required this.trialDaysOf,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      children: [
        if (annual != null)
          _PlanCard(
            colors: c,
            title: 'Annual',
            price: monthlyEquivalent != null
                ? '$monthlyEquivalent/mo'
                : annual!.storeProduct.priceString,
            subtitle: savingsPercent != null
                ? 'Save $savingsPercent% vs monthly · billed annually'
                : 'Billed annually',
            badge: 'RECOMMENDED',
            trialTag: _trialTag(annual),
            isSelected: selected == annual,
            onTap: () => onPick(annual!),
          ),
        if (annual != null && monthly != null) const SizedBox(height: 12),
        if (monthly != null)
          _PlanCard(
            colors: c,
            title: 'Monthly',
            price: '${monthly!.storeProduct.priceString}/mo',
            subtitle: 'Billed monthly · cancel anytime',
            badge: null,
            trialTag: _trialTag(monthly),
            isSelected: selected == monthly,
            onTap: () => onPick(monthly!),
          ),
      ],
    );
  }

  String? _trialTag(Package? pkg) {
    final intro = introOf(pkg);
    if (intro == null) return null;
    return '${trialDaysOf(intro)}-day free trial';
  }
}

class _PlanCard extends StatelessWidget {
  final AppColors colors;
  final String title;
  final String price;
  final String subtitle;
  final String? badge;
  final String? trialTag;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.colors,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.badge,
    required this.trialTag,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: isSelected ? _kBrand.withValues(alpha: 0.08) : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? _kBrand : c.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _kBrand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected ? _kBrand : c.textTertiary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (trialTag != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.lock_clock_rounded,
                    color: _kBrand,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    trialTag!,
                    style: const TextStyle(
                      color: _kBrand,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Fallback shown when the store offering fails to load -----------------

class _OfferingUnavailableCard extends StatelessWidget {
  final AppColors colors;
  final VoidCallback onRetry;

  const _OfferingUnavailableCard({required this.colors, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: c.textTertiary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't load pricing",
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(color: c.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(color: _kBrand, fontWeight: FontWeight.bold),
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

// ---- Feature list (icon rows) ----------------------------------------------

class _FeatureItem {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureItem(this.icon, this.title, this.body);
}

const _kFeatures = [
  _FeatureItem(
    Icons.calendar_month_rounded,
    'Personalized training plans',
    'Built around your goal race and current fitness — not a generic template.',
  ),
  _FeatureItem(
    Icons.forum_rounded,
    'Coaching from Max',
    'Session-by-session guidance, pacing targets and encouragement on every run.',
  ),
  _FeatureItem(
    Icons.trending_up_rounded,
    'Adapts as you run',
    'Your plan adjusts automatically as your fitness evolves — never static.',
  ),
  _FeatureItem(
    Icons.flag_rounded,
    'Race-day pacing',
    'Precise target paces for your goal race, dialed in as race day gets closer.',
  ),
];

class _FeatureList extends StatelessWidget {
  final AppColors colors;
  const _FeatureList({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What you get',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: _kFeatures
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _kBrand.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(f.icon, color: _kBrand, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.title,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                f.body,
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ---- Guarantee card (truthful — store-managed cancellation, no fake refund
// promise we don't actually offer) ------------------------------------------

class _GuaranteeCard extends StatelessWidget {
  final AppColors colors;
  const _GuaranteeCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: _kBrand,
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cancel anytime, no lock-in',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage or cancel your subscription anytime from your account settings — no calls, no fine print.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Trust banner (no fabricated stats/testimonials) ----------------------

class _TrustBanner extends StatelessWidget {
  final AppColors colors;
  const _TrustBanner({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, color: _kBrand, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Built by runners, backed by real training science — not a generic template.',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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

  const _PriceSummary({
    required this.colors,
    required this.selected,
    required this.isAnnual,
    required this.hasTrial,
    required this.trialDays,
    required this.monthlyEquivalent,
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
        Text(
          headline,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 3),
        Text(sub, style: TextStyle(color: c.textTertiary, fontSize: 13)),
      ],
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
