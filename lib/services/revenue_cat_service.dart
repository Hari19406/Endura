import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import 'profile_service.dart';

class RevenueCatService {
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  /// Ceiling on the three native store calls below. Without it, a stalled
  /// store/network connection leaves the paywall's spinner running forever —
  /// nothing in the Purchases SDK itself times out on its own. Callers still
  /// see a plain `TimeoutException`, so their existing catch blocks (and,
  /// for the two that already degrade gracefully, no catch at all) keep
  /// working — this only bounds how long they can wait.
  static const _networkTimeout = Duration(seconds: 15);

  // Cached pro status — updated by the listener set up in init()
  static final ValueNotifier<bool> isProNotifier = ValueNotifier(false);

  /// Mirror the entitlement onto `profiles.is_pro` so it can drive the verified
  /// badge on the activity feed. Best-effort — never throws.
  static void _syncProToProfile(bool isPro) {
    ProfileService.instance
        .updateField('is_pro', isPro)
        .catchError((_) => false);
  }

  static Future<void> init(String supabaseUserId) async {
    if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
    final config = PurchasesConfiguration(
      Platform.isAndroid ? _androidKey : _iosKey,
    )..appUserID = supabaseUserId;
    await Purchases.configure(config);

    // Seed the cache immediately
    final info = await Purchases.getCustomerInfo();
    isProNotifier.value = info.entitlements.active.containsKey('endura_pro');
    _syncProToProfile(isProNotifier.value);

    // Keep cache live — fires when subscription status changes
    Purchases.addCustomerInfoUpdateListener((info) {
      final nowPro = info.entitlements.active.containsKey('endura_pro');
      final changed = isProNotifier.value != nowPro;
      isProNotifier.value = nowPro;
      if (changed) _syncProToProfile(nowPro);
    });
  }

  static Future<bool> isPro() async {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey('endura_pro');
  }

  /// Returns the annual and monthly packages from the default offering.
  static Future<({Package? annual, Package? monthly})> getOffering() async {
    try {
      final offerings = await Purchases.getOfferings().timeout(_networkTimeout);
      final current = offerings.current;
      return (annual: current?.annual, monthly: current?.monthly);
    } on TimeoutException catch (e) {
      debugPrint(
        '[RevenueCat] getOffering timed out after '
        '${_networkTimeout.inSeconds}s: $e',
      );
      return (annual: null, monthly: null);
    } catch (e) {
      debugPrint('[RevenueCat] getOffering error: $e');
      return (annual: null, monthly: null);
    }
  }

  /// Purchase a specific package. Returns true if the user is now pro.
  ///
  /// A `TimeoutException` (and everything else) is logged and rethrown —
  /// this is a bare service call with no UI state of its own, so the caller
  /// (the paywall screen's busy flag + error snackbar) owns recovering from
  /// it. Left uncaught otherwise, `.timeout()` would just leave the purchase
  /// button's spinner running forever.
  static Future<bool> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchase(
        PurchaseParams.package(package),
      ).timeout(_networkTimeout);
      final nowPro = result.customerInfo.entitlements.active.containsKey(
        'endura_pro',
      );
      isProNotifier.value = nowPro;
      return nowPro;
    } on TimeoutException catch (e) {
      debugPrint(
        '[RevenueCat] purchasePackage timed out after '
        '${_networkTimeout.inSeconds}s: $e',
      );
      rethrow;
    }
  }

  static Future<void> presentCustomerCenter() async {
    await RevenueCatUI.presentCustomerCenter();
  }

  /// Same timeout + log-and-rethrow shape as [purchasePackage] — the paywall's
  /// "Restore purchases" button is the caller and owns resetting its own busy
  /// state / showing a message.
  static Future<bool> restorePurchases() async {
    try {
      final info = await Purchases.restorePurchases().timeout(_networkTimeout);
      final nowPro = info.entitlements.active.containsKey('endura_pro');
      isProNotifier.value = nowPro;
      return nowPro;
    } on TimeoutException catch (e) {
      debugPrint(
        '[RevenueCat] restorePurchases timed out after '
        '${_networkTimeout.inSeconds}s: $e',
      );
      rethrow;
    }
  }
}
