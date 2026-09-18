/// 24-hour clock parsing (e.g. "01:00 PM" → "13:00:00").
String normalizeClockTimeHms(String value) {
  final s = value.trim();
  if (s.isEmpty) return "";

  final ampm = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(A\.?M\.?|P\.?M\.?)$',
    caseSensitive: false,
  ).firstMatch(s);
  if (ampm != null) {
    var h = int.tryParse(ampm.group(1)!) ?? 0;
    final mm = ampm.group(2)!;
    final ss = (ampm.group(3) ?? '00').padLeft(2, '0');
    final ap = ampm.group(4)!.replaceAll('.', '').toUpperCase();
    if (ap == 'PM' && h != 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    if (h > 23) return s;
    return '${h.toString().padLeft(2, '0')}:$mm:$ss';
  }

  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
  if (m == null) return s;
  final h = int.tryParse(m.group(1)!) ?? 0;
  if (h > 23) return s;
  final mm = m.group(2)!;
  final ss = (m.group(3) ?? '00').padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$mm:$ss';
}

/// HH:MM[:SS] or 12h with AM/PM → hour/minute/second (24h).
({int hour, int minute, int second})? parseClockTimeHms(String value) {
  final norm = normalizeClockTimeHms(value);
  final m = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$').firstMatch(norm);
  if (m == null) return null;
  return (
    hour: int.parse(m.group(1)!),
    minute: int.parse(m.group(2)!),
    second: int.parse(m.group(3)!),
  );
}

/// Split `dd-MM-yyyy` or `dd/MM/yyyy` (also `.`) into day/month/year tokens.
List<String>? splitDdMmYyyy(String datePart) {
  final parts = datePart.trim().split(RegExp(r'[/\-.]'));
  if (parts.length != 3) return null;
  return parts;
}

/// Web DatePicker display: `dd-MM-yyyy`.
String formatDdMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.year}';

/// Web Q11 display: `dd-MM-yyyy  |  HH:mm` (24h).
String formatDdMmYyyyPipeHHmm(DateTime d) =>
    '${formatDdMmYyyy(d)}  |  '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

/// "DD-MM-YYYY HH:MM" or slashes, optional `|`, or 12h AM/PM → ISO local.
String? ddMmYyyyHhMmToIso(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final segs = raw.trim().split(RegExp(r'\s+')).where((s) => s != '|').toList();
  if (segs.isEmpty) return null;
  final datePart = segs[0];
  final timePart = segs.length > 1 ? segs[1] : '00:00';
  final parts = splitDdMmYyyy(datePart);
  if (parts == null) return null;
  final d = parts[0].padLeft(2, '0');
  final m = parts[1].padLeft(2, '0');
  final y = parts[2];
  final clock = normalizeClockTimeHms(timePart);
  final tm = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$').firstMatch(clock);
  if (tm == null) return '$y-$m-${d}T$timePart:00';
  return '$y-$m-${d}T${tm.group(1)}:${tm.group(2)}:${tm.group(3)}';
}
