import 'package:shared_preferences/shared_preferences.dart';

const helperSessionKeyVs6_1 = 'vs6_1';
const helperSessionKeyInfectGiHema = 'infect_gi_hema';
const helperSessionKeyMetabRenalVascEye = 'metab_renal_vasc_eye';

String _helperActiveDayKey(String formKey, String enrollmentId) =>
    'portal-helper-day-$formKey-${enrollmentId.trim()}';

Future<int?> readRememberedActiveDay(String formKey, String enrollmentId) async {
  final eid = enrollmentId.trim();
  if (eid.isEmpty) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt(_helperActiveDayKey(formKey, eid));
    if (n == null || n < 1) return null;
    return n;
  } catch (_) {
    return null;
  }
}

Future<void> rememberActiveDay(
  String formKey,
  String enrollmentId,
  int day,
) async {
  final eid = enrollmentId.trim();
  if (eid.isEmpty || day < 1) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_helperActiveDayKey(formKey, eid), day);
  } catch (_) {}
}

String formatBoBabyName(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^baby of\s+', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^b/o\s+', caseSensitive: false), '');
  return s.trim();
}
