/// Smoke coverage for PaywallScreen against the verified RevenueCat dashboard
/// shape: offering "default", package `$rc_monthly` → product
/// `premium_monthly:premium-monthly`, package `$rc_annual` → product
/// `premium_yearly:premium-yearly`, entitlement `endura_pro`.
///
/// Uses `PaywallScreen(debugOffering: ...)` — the same test-only injection
/// point `main_preview_paywall.dart` uses — to exercise the screen without a
/// real Purchases platform channel. `RevenueCatService` itself calls the
/// `purchases_flutter` static API directly (no injectable seam), so it isn't
/// unit-testable here; this file only covers what `PaywallScreen` does with
/// whatever `RevenueCatService.getOffering()` hands it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:run_app/screens/paywall_screen.dart';
import 'package:run_app/theme/app_colors.dart';

const _offeringContext = PresentedOfferingContext('default', null, null);

Package _monthlyPackage() => Package(
  r'$rc_monthly',
  PackageType.monthly,
  const StoreProduct(
    'premium_monthly:premium-monthly',
    'Endura Pro monthly plan',
    'Endura Pro (Monthly)',
    499,
    '₹499',
    'INR',
  ),
  _offeringContext,
);

Package _annualPackage() => Package(
  r'$rc_annual',
  PackageType.annual,
  const StoreProduct(
    'premium_yearly:premium-yearly',
    'Endura Pro annual plan',
    'Endura Pro (Annual)',
    3650,
    '₹3,650',
    'INR',
    pricePerMonthString: '₹304',
  ),
  _offeringContext,
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: const [AppColors.light]),
  home: child,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PaywallScreen — populated offering', () {
    testWidgets('renders both plans with their mapped product prices', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PaywallScreen(
            debugOffering: (
              annual: _annualPackage(),
              monthly: _monthlyPackage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both packages resolved — never falls back to the error card.
      expect(find.text("Couldn't load pricing"), findsNothing);
      expect(find.text('Annual'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      // The monthly plan's own price string, from the mapped
      // premium_monthly:premium-monthly product.
      expect(find.textContaining('₹499'), findsWidgets);
      // The annual plan's billed-amount caption, from the mapped
      // premium_yearly:premium-yearly product.
      expect(find.textContaining('₹3,650'), findsWidgets);
    });

    testWidgets('purchase CTA is enabled once packages have loaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PaywallScreen(
            debugOffering: (
              annual: _annualPackage(),
              monthly: _monthlyPackage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cta = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(cta.onPressed, isNotNull);
    });
  });

  group('PaywallScreen — empty/failed offering', () {
    testWidgets('shows the error card + inline Retry, never a blank screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const PaywallScreen(debugOffering: (annual: null, monthly: null)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load pricing"), findsOneWidget);
      // Inline card Retry + footer Retry button.
      expect(find.text('Retry'), findsWidgets);
      // No plan cards render when both packages are null.
      expect(find.text('Annual'), findsNothing);
      expect(find.text('Monthly'), findsNothing);
    });

    testWidgets('tapping Retry re-runs the load without hanging or throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const PaywallScreen(debugOffering: (annual: null, monthly: null)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsWidgets);

      // debugOffering resolves synchronously to the same null offering, so
      // this can't prove a *different* result — it proves _loadOffering()
      // re-running (briefly showing the spinner, then settling) never hangs
      // or throws, and the error state remains a real state, not a dead end.
      await tester.tap(find.text('Retry').first);
      await tester.pump(); // spinner frame
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load pricing"), findsOneWidget);
    });
  });
}
