// DOB drives NICU Day 1; Day N calendar date = Day 1 + (N − 1).

String formatIsoDateOnly(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? parseIsoDateOnly(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim().length >= 10 ? raw.trim().substring(0, 10) : raw.trim();
  return DateTime.tryParse(s);
}

/// Lockstep with web `NICU_DAY_GRACE_HOUR` / backend `NICU_DAY_GRACE_HOUR`.
const int kNicuDayGraceHour = 8;

/// NICU day number for [day1Date] as of [asOf], with grace hour (before
/// [graceHour] local, "today" is yesterday's calendar date for day math).
int nicuDayNumberFromDay1(
  DateTime? day1Date, [
  DateTime? asOf,
  int graceHour = kNicuDayGraceHour,
]) {
  if (day1Date == null) return 1;
  final now = asOf ?? DateTime.now();
  final base = DateTime(day1Date.year, day1Date.month, day1Date.day);
  var ref = DateTime(now.year, now.month, now.day);
  if (now.hour < graceHour) {
    ref = ref.subtract(const Duration(days: 1));
  }
  final n = ref.difference(base).inDays + 1;
  return n < 1 ? 1 : n;
}

/// Calendar date for NICU day [nicuDay] (1-based) from Day 1 anchor.
DateTime? calendarDateForNicuDay(DateTime? day1, int nicuDay) {
  if (day1 == null || nicuDay < 1) return null;
  final base = DateTime(day1.year, day1.month, day1.day);
  return base.add(Duration(days: nicuDay - 1));
}

/// NICU day (1-based) for a calendar date `YYYY-MM-DD`, or null if before Day 1.
int? nicuDayForCalendarYmd(DateTime? day1, String? ymd) {
  if (day1 == null || ymd == null || ymd.trim().isEmpty) return null;
  final cal = parseIsoDateOnly(ymd);
  if (cal == null) return null;
  final base = DateTime(day1.year, day1.month, day1.day);
  final target = DateTime(cal.year, cal.month, cal.day);
  final diff = target.difference(base).inDays;
  if (diff < 0) return null;
  return diff + 1;
}

String formatDisplayDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}
