import 'package:flutter/material.dart';
import '../services/revenue_cat_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = false;

  Future<void> _purchase() async {
    setState(() => _loading = true);
    try {
      await RevenueCatService.presentPaywall();
      final isPro = await RevenueCatService.isPro();
      if (isPro && mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Purchase error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
              const Text('Unlock Max\'s full coaching intelligence',
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

              _PlanButton(
                label: 'Annual — ₹3,999/yr',
                sublabel: 'Best value · 7-day free trial',
                highlight: true,
                loading: _loading,
                onTap: _purchase,
              ),
              const SizedBox(height: 12),
              _PlanButton(
                label: 'Monthly — ₹499/mo',
                sublabel: '7-day free trial',
                highlight: false,
                loading: _loading,
                onTap: _purchase,
              ),
              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () async {
                    await RevenueCatService.restorePurchases();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Restore purchases',
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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