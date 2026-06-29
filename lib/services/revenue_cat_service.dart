import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatService {
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  // Cached pro status — updated by the listener set up in init()
  static final ValueNotifier<bool> isProNotifier = ValueNotifier(false);

  static Future<void> init(String supabaseUserId) async {
    if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
    final config = PurchasesConfiguration(
      Platform.isAndroid ? _androidKey : _iosKey,
    )..appUserID = supabaseUserId;
    await Purchases.configure(config);

    // Seed the cache immediately
    final info = await Purchases.getCustomerInfo();
    isProNotifier.value = info.entitlements.active.containsKey('pro');

    // Keep cache live — fires when subscription status changes
    Purchases.addCustomerInfoUpdateListener((info) {
      isProNotifier.value = info.entitlements.active.containsKey('pro');
    });
  }

  static Future<bool> isPro() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('pro');
  }

  /// Returns the annual and monthly packages from the default offering.
  static Future<({Package? annual, Package? monthly})> getOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      return (
        annual: current?.annual,
        monthly: current?.monthly,
      );
    } catch (e) {
      debugPrint('[RevenueCat] getOffering error: $e');
      return (annual: null, monthly: null);
    }
  }

  /// Purchase a specific package. Returns true if the user is now pro.
  static Future<bool> purchasePackage(Package package) async {
    final info = await Purchases.purchasePackage(package);
    final nowPro = info.entitlements.active.containsKey('pro');
    isProNotifier.value = nowPro;
    return nowPro;
  }

  static Future<void> presentCustomerCenter() async {
    await RevenueCatUI.presentCustomerCenter();
  }

  static Future<bool> restorePurchases() async {
    final info = await Purchases.restorePurchases();
    final nowPro = info.entitlements.active.containsKey('pro');
    isProNotifier.value = nowPro;
    return nowPro;
  }
}
