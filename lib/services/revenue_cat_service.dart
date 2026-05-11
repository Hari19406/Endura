import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatService {
  static const _androidKey = 'test_ssqCThHhzwWBvTvcwdhtpPNooBE';
  static const _iosKey = 'appl_xxxxxxxxxxxx';

  static Future<void> init(String supabaseUserId) async {
    await Purchases.setLogLevel(LogLevel.debug); // remove before release
    final config = PurchasesConfiguration(
      Platform.isAndroid ? _androidKey : _iosKey,
    )..appUserID = supabaseUserId;
    await Purchases.configure(config);
  }

  static Future<bool> isPro() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('pro');
  }

  static Future<void> presentPaywall() async {
    await RevenueCatUI.presentPaywallIfNeeded('pro');
  }

  static Future<void> presentCustomerCenter() async {
    await RevenueCatUI.presentCustomerCenter();
  }

  static Future<void> restorePurchases() async {
    await Purchases.restorePurchases();
  }
}