/// PlanCalendar — the one place plan-week date math lives.
///
/// A training plan's weeks are Monday-aligned: week N covers the seven days
/// starting at `week1Monday + (N-1)*7`, and a day slot's `weekday` (0 = Monday
/// … 6 = Sunday) is its real calendar weekday. Everything here works on
/// calendar dates (year/month/day) via `DateTime(y, m, d + n)` normalisation
/// rather than `Duration` arithmetic, so a DST change or a UTC-stamped legacy
/// value can never shift a date by a day.
library;

class PlanCalendar {
  const PlanCalendar._();

  /// The local calendar date of [d], time zeroed. A UTC instant (how legacy
  /// plans stored `builtAt`) is converted to local first, so a plan built at
  /// 01:00 IST doesn't read as the previous UTC day.
  static DateTime dateOnly(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    return DateTime(local.year, local.month, local.day);
  }

  /// Monday (date-only) of the week containing [d].
  static DateTime mondayOf(DateTime d) {
    final day = dateOnly(d);
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }

  /// The calendar date of plan week [weekNumber] (1-based), day [weekday]
  /// (0 = Monday), for a plan anchored on [anchor] — any date in week 1; it is
  /// snapped to that week's Monday.
  static DateTime dateFor(DateTime anchor, int weekNumber, int weekday) {
    final monday = mondayOf(anchor);
    return DateTime(
      monday.year,
      monday.month,
      monday.day + (weekNumber - 1) * 7 + weekday,
    );
  }

  /// Whole calendar days from [from] to [to] (negative when [to] is earlier).
  /// Uses UTC midnights internally so DST never truncates a day off the result.
  static int daysBetween(DateTime from, DateTime to) {
    final a = dateOnly(from);
    final b = dateOnly(to);
    return DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
  }

  /// [d] moved by [days] calendar days, keeping its time of day (and UTC-ness).
  static DateTime shiftDays(DateTime d, int days) => d.isUtc
      ? DateTime.utc(
          d.year,
          d.month,
          d.day + days,
          d.hour,
          d.minute,
          d.second,
          d.millisecond,
          d.microsecond,
        )
      : DateTime(
          d.year,
          d.month,
          d.day + days,
          d.hour,
          d.minute,
          d.second,
          d.millisecond,
          d.microsecond,
        );
}
