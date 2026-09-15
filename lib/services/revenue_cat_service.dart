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
      if (kDebugMode) _logOfferingDiagnostics(current);
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

  /// Debug-only: makes a misconfigured dashboard (vs. a genuine network
  /// failure) distinguishable in logcat. Both look identical to the paywall
  /// UI — "Couldn't load pricing" either way — but a null [current] or a
  /// present offering whose `annual`/`monthly` are still null are dashboard
  /// problems no amount of retrying fixes, not transient ones.
  static void _logOfferingDiagnostics(Offering? current) {
    if (current == null) {
      debugPrint(
        '[RevenueCat] getOffering: no current offering returned. Check the '
        '"default" offering is set as the CURRENT offering in the '
        'RevenueCat dashboard.',
      );
      return;
    }
    final packages = current.availablePackages;
    debugPrint(
      '[RevenueCat] getOffering: offering "${current.identifier}" — '
      '${packages.length} package(s): '
      '${packages.map((p) => p.identifier).join(', ')}',
    );
    if (current.annual == null && current.monthly == null) {
      debugPrint(
        '[RevenueCat] getOffering: neither \$rc_annual nor \$rc_monthly '
        'resolved on this offering. Either the package(s) above are typed '
        'as something other than Annual/Monthly in the RC dashboard, or '
        'they have no Play Store product attached for this app — cross-check '
        'Offerings → "${current.identifier}" → Packages against the '
        'Play Console subscription products.',
      );
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
