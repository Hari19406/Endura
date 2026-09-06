// lib/utils/image_compress.dart
//
// Pure-Dart avatar downscale: center-crop to square, resize to <=400px, encode
// JPEG, stepping quality down until the payload is comfortably small
// (~35-50 KB) so the public `avatars` bucket stays tiny on the free tier.

import 'dart:typed_data';

import 'package:image/image.dart' as img;

class AvatarCompressor {
  static const int _maxEdge = 400;
  static const int _targetBytes = 50 * 1024;

  /// Returns JPEG bytes, or null if [raw] can't be decoded.
  static Uint8List? toAvatarJpeg(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    // Center square crop.
    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );

    final resized = side > _maxEdge
        ? img.copyResize(square, width: _maxEdge, height: _maxEdge)
        : square;

    for (final q in [82, 70, 60, 50, 40]) {
      final bytes = img.encodeJpg(resized, quality: q);
      if (bytes.length <= _targetBytes || q == 40) return bytes;
    }
    return img.encodeJpg(resized, quality: 40);
  }
}
