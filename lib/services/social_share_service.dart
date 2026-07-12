import 'dart:io';

import 'package:flutter/services.dart';

/// Targeted share-to-app intents via a small Android platform channel
/// (share_plus can only open the generic system sheet).
class SocialShareService {
  static const MethodChannel _channel = MethodChannel('endura/social_share');

  static const String whatsappPackage = 'com.whatsapp';
  static const String instagramPackage = 'com.instagram.android';

  /// Opens [packageName]'s share flow with the image at [path].
  /// Returns false if the app isn't installed (caller should fall back to
  /// the system share sheet).
  static Future<bool> shareImageTo(String path, String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('shareImageTo', {
        'path': path,
        'package': packageName,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
