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

/// Calendar date for NICU day [nicuDay] (1-based) from Day 1 anchor.
DateTime? calendarDateForNicuDay(DateTime? day1, int nicuDay) {
  if (day1 == null || nicuDay < 1) return null;
  final base = DateTime(day1.year, day1.month, day1.day);
  return base.add(Duration(days: nicuDay - 1));
}

String formatDisplayDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}
