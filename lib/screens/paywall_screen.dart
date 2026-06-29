import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/revenue_cat_service.dart';
import '../services/analytics_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Package? _annualPackage;
  Package? _monthlyPackage;
  bool _loadingOffering = true;
  String? _purchasingId; // which package is currently purchasing

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
          SnackBar(content: Text('Purchase failed: ${e.name}')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Endura Pro',
                  style: TextStyle(
                    color: Color(0xFF00E5CC),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  )),
              const SizedBox(height: 8),
              const Text("Unlock Max's full coaching intelligence",
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 32),

              ...[
                'Adaptive weekly plans that react to your runs',
                'Threshold, VO2max & long run sessions',
                'vDOT tracking — Max gets smarter every run',
                'Priority support',
              ].map((f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF00E5CC), size: 20),
                      const SizedBox(width: 12),
                      Text(f,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15)),
                    ]),
                  )),

              const Spacer(),

              if (_loadingOffering)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5CC)),
                )
              else ...[
                if (_annualPackage != null)
                  _PlanButton(
                    label:
                        'Annual — ${_annualPackage!.storeProduct.priceString}/yr',
                    sublabel: 'Best value',
                    highlight: true,
                    loading: _purchasingId == _annualPackage!.identifier,
                    onTap: () => _purchase(_annualPackage!),
                  ),
                const SizedBox(height: 12),
                if (_monthlyPackage != null)
                  _PlanButton(
                    label:
                        'Monthly — ${_monthlyPackage!.storeProduct.priceString}/mo',
                    sublabel: 'Cancel anytime',
                    highlight: false,
                    loading: _purchasingId == _monthlyPackage!.identifier,
                    onTap: () => _purchase(_monthlyPackage!),
                  ),
              ],

              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _purchasingId != null ? null : _restore,
                  child: _purchasingId == 'restore'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white38),
                        )
                      : const Text('Restore purchases',
                          style: TextStyle(color: Colors.white38)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool highlight;
  final bool loading;
  final VoidCallback onTap;

  const _PlanButton({
    required this.label,
    required this.sublabel,
    required this.highlight,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF00E5CC)
              : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(14),
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: highlight ? Colors.black : Colors.white,
                  ),
                ),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: highlight ? Colors.black : Colors.white,
                    )),
                const SizedBox(height: 2),
                Text(sublabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: highlight ? Colors.black54 : Colors.white38,
                    )),
              ]),
      ),
    );
  }
}
