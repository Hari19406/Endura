// lib/utils/date_format_utils.dart

import 'package:intl/intl.dart';

/// Compact relative timestamp for feed / activity rows:
/// "just now", "5m", "3h", "2d", then an absolute "MMM d" (adding the year once
/// it's not the current year).
String relativeTime(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final d = ref.difference(when.isUtc ? when.toLocal() : when);

  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';

  final local = when.isUtc ? when.toLocal() : when;
  final pattern = local.year == ref.year ? 'MMM d' : 'MMM d, y';
  return DateFormat(pattern).format(local);
}
