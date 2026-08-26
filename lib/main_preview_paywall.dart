import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'screens/paywall_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PaywallPreviewApp());
}

const _offeringContext = PresentedOfferingContext('default', null, null);

final _annualIntro = const IntroductoryPrice(
  0,
  'Free',
  'P7D',
  1,
  PeriodUnit.day,
  7,
);

final _annualPackage = Package(
  '\$rc_annual',
  PackageType.annual,
  StoreProduct(
    'endura_pro_annual',
    'Endura Pro annual plan',
    'Endura Pro (Annual)',
    3650,
    '₹3,650',
    'INR',
    introductoryPrice: _annualIntro,
    pricePerMonthString: '₹304',
  ),
  _offeringContext,
);

final _monthlyPackage = Package(
  '\$rc_monthly',
  PackageType.monthly,
  StoreProduct(
    'endura_pro_monthly',
    'Endura Pro monthly plan',
    'Endura Pro (Monthly)',
    499,
    '₹499',
    'INR',
  ),
  _offeringContext,
);

class PaywallPreviewApp extends StatelessWidget {
  const PaywallPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: PaywallScreen(
        debugOffering: (annual: _annualPackage, monthly: _monthlyPackage),
      ),
    );
  }
}
