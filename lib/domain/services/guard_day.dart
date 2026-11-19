/// Guard-only calendar boundary (pure Dart, no Flutter, no localization).
///
/// A guard day starts at 06:00 local time: 00:00-05:59 belong to the previous
/// guard day. Everything else in the app (weather, ledger, focus sessions,
/// tasks) keeps the natural midnight boundary and must NOT use this function.
library guard_day;

/// Returns the guard day key (`yyyy-MM-dd`) for [t].
///
/// Implemented by shifting the timestamp back six hours and formatting the
/// resulting calendar date with plain string padding, so the domain layer has
/// no dependency on `dart:io` / Flutter / intl locale data.
String guardDayKey(DateTime t) {
  final DateTime shifted = t.subtract(const Duration(hours: 6));
  final String year = shifted.year.toString().padLeft(4, '0');
  final String month = shifted.month.toString().padLeft(2, '0');
  final String day = shifted.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
