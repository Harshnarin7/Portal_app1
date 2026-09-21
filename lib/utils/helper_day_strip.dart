/// Mobile day strip shows only recent NICU days (not Day 1 → today).
const kMobileDayStripWindow = 7;

int helperDefaultStripStart(int todayNicuDay, {int window = kMobileDayStripWindow}) {
  if (todayNicuDay < 1) return 1;
  final start = todayNicuDay - window + 1;
  return start < 1 ? 1 : start;
}

int? helperDischargeNicuDay(DateTime? day1, String? dischargeYmd) {
  if (day1 == null || dischargeYmd == null || dischargeYmd.trim().isEmpty) {
    return null;
  }
  final raw = dischargeYmd.trim();
  final s = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  final base = DateTime(day1.year, day1.month, day1.day);
  final dis = DateTime(d.year, d.month, d.day);
  final n = dis.difference(base).inDays + 1;
  return n < 1 ? 1 : n;
}

List<int> helperVisibleStripDays({
  required int stripStart,
  required int totalDays,
  required int todayNicuDay,
  int? dischargeDay,
}) {
  var end = totalDays > todayNicuDay ? totalDays : todayNicuDay;
  if (totalDays > end) end = totalDays;
  if (dischargeDay != null && dischargeDay < end) end = dischargeDay;
  if (end < 1) end = 1;
  var start = stripStart < 1 ? 1 : stripStart;
  if (start > end) start = end;
  return [for (var d = start; d <= end; d++) d];
}

List<int> helperMissedDaysInWindow({
  required List<int> visibleDays,
  required int todayNicuDay,
  required Map<int, String> dayStatus,
}) {
  return visibleDays
      .where((d) =>
          d < todayNicuDay && (dayStatus[d] ?? 'empty') == 'empty')
      .toList();
}
