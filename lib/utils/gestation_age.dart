/// Gestational-age helpers matching web `frontend-app/src/utils/datetime.js`
/// (`calendarDaysBetween`, `eddFromLmp`, `gestAgeFromLmp`, `gestAgeFromEdd`).
///
/// Auto-GA is anchored to [asOf] (Form A `screening_datetime`), not "now".

class GestAge {
  final int weeks;
  final int days;
  const GestAge(this.weeks, this.days);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day difference (b − a), matching web `calendarDaysBetween`.
int calendarDaysBetween(DateTime a, DateTime b) {
  final a0 = dateOnly(a);
  final b0 = dateOnly(b);
  return b0.difference(a0).inDays;
}

/// Naegele's rule: EDD = LMP + 1 year − 3 months + 7 days
/// (same as 9 calendar months + 7 days). This is not LMP + 280 days —
/// that approximation is 1–2 days early when the 9-month span has extra
/// 31-day months (e.g. LMP 15 Mar → EDD 22 Dec, not 20 Dec).
DateTime eddFromLmp(DateTime lmp) {
  final d = dateOnly(lmp);
  return DateTime(d.year + 1, d.month - 3, d.day + 7);
}

/// Inverse Naegele: LMP = EDD − 1 year + 3 months − 7 days.
DateTime lmpFromEdd(DateTime edd) {
  final d = dateOnly(edd);
  return DateTime(d.year - 1, d.month + 3, d.day - 7);
}

/// Completed weeks/days since LMP as of [asOf].
GestAge? gestAgeFromLmp(DateTime lmp, DateTime asOf) {
  final gestDays = calendarDaysBetween(lmp, asOf);
  if (gestDays < 0) return const GestAge(0, 0);
  return GestAge(gestDays ~/ 7, gestDays % 7);
}

/// GA from EDD via inverse Naegele, then same LMP arithmetic.
GestAge? gestAgeFromEdd(DateTime edd, DateTime asOf) {
  return gestAgeFromLmp(lmpFromEdd(edd), asOf);
}
