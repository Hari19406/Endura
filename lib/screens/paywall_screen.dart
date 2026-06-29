import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';

// Endura teal — brand color, intentionally not a theme token (fixed across light/dark)
const _kBrand = Color(0xFF00E5CC);
// Replace these before App Store submission
const _kTermsUrl = 'https://endurarun.app/terms';
const _kPrivacyUrl = 'https://endurarun.app/privacy';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Package? _annualPackage;
  Package? _monthlyPackage;
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
        _loadingOffering = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    } catch (e) {
      debugPrint('[Paywall] purchase error: $e');
    } finally {
      if (mounted) setState(() => _purchasingId = null);
    }
  }

  Future<void> _restore() async {
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

  String? _monthlyEquivalent(Package pkg) {
    final price = pkg.storeProduct.price;
    if (price <= 0) return null;
    final symbol =
        pkg.storeProduct.priceString.replaceAll(RegExp(r'[\d.,\s]'), '').trim();
    final monthly = price / 12;
    return '$symbol${monthly.toStringAsFixed(2)}/mo';
  }

  bool get _hasTrial =>
      (_annualPackage?.storeProduct.introductoryPrice?.price ?? -1) == 0;

  String _trialLabel() {
    final intro = _annualPackage?.storeProduct.introductoryPrice;
    if (intro == null || intro.price > 0) return '';
    final n = intro.periodNumberOfUnits;
    switch (intro.periodUnit) {
      case PeriodUnit.day:
        return '$n-day free trial';
      case PeriodUnit.week:
        return '$n-week free trial';
      case PeriodUnit.month:
        return '$n-month free trial';
      default:
        return 'Free trial included';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _purchasingId != null;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                child: IconButton(
                  icon: Icon(Icons.close, color: c.textTertiary),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Endura Pro',
                      style: TextStyle(
                        color: _kBrand,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Coached running. Built around you.',
                      style:
                          TextStyle(color: c.textSecondary, fontSize: 16),
                    ),
                    const SizedBox(height: 28),
                    ...[
                      'Adaptive plans that react to your runs week by week',
                      'Threshold, VO₂max & long run sessions guided by Max',
                      'vDOT fitness tracking — Max gets smarter every run',
                      'Race target paces set automatically for your goal',
                    ].map((f) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.check_circle_rounded,
                                    color: _kBrand, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  f,
                                  style: TextStyle(
                                      color: c.textPrimary, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        )),
                    const Spacer(),
                    if (_loadingOffering)
                      const Center(
                        child: CircularProgressIndicator(color: _kBrand),
                      )
                    else ...[
                      if (_annualPackage != null)
                        _AnnualCard(
                          package: _annualPackage!,
                          monthlyEquivalent:
                              _monthlyEquivalent(_annualPackage!),
                          hasTrial: _hasTrial,
                          trialLabel: _trialLabel(),
                          loading: _purchasingId ==
                              _annualPackage!.identifier,
                          disabled: busy,
                          onTap: busy
                              ? null
                              : () => _purchase(_annualPackage!),
                        ),
                      const SizedBox(height: 10),
                      if (_monthlyPackage != null)
                        _MonthlyCard(
                          package: _monthlyPackage!,
                          loading: _purchasingId ==
                              _monthlyPackage!.identifier,
                          disabled: busy,
                          colors: c,
                          onTap: busy
                              ? null
                              : () => _purchase(_monthlyPackage!),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: busy ? null : _restore,
                        child: _purchasingId == 'restore'
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white38),
                              )
                            : Text(
                                'Restore purchases',
                                style:
                                    TextStyle(color: c.textTertiary),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _LegalLink('Terms of Use', _kTermsUrl,
                                  c.textFaint),
                              Text('  ·  ',
                                  style: TextStyle(
                                      color: c.textFaint, fontSize: 12)),
                              _LegalLink('Privacy Policy', _kPrivacyUrl,
                                  c.textFaint),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Subscription auto-renews. Cancel anytime in settings.',
                            style: TextStyle(
                                color: c.textFaint, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnualCard extends StatelessWidget {
  final Package package;
  final String? monthlyEquivalent;
  final bool hasTrial;
  final String trialLabel;
  final bool loading;
  final bool disabled;
  final VoidCallback? onTap;

  const _AnnualCard({
    required this.package,
    required this.monthlyEquivalent,
    required this.hasTrial,
    required this.trialLabel,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled && !loading ? 0.5 : 1.0,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: _kBrand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black45),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Annual',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${package.storeProduct.priceString}/yr',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        if (monthlyEquivalent != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Only $monthlyEquivalent',
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13),
                          ),
                        ],
                        if (hasTrial) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              trialLabel,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: const Text(
                  'BEST VALUE',
                  style: TextStyle(
                    color: _kBrand,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  final Package package;
  final bool loading;
  final bool disabled;
  final AppColors colors;
  final VoidCallback? onTap;

  const _MonthlyCard({
    required this.package,
    required this.loading,
    required this.disabled,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled && !loading ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.textTertiary),
                  ),
                )
              : Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Cancel anytime',
                          style: TextStyle(
                              color: c.textTertiary, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${package.storeProduct.priceString}/mo',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
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
      onTap: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
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
