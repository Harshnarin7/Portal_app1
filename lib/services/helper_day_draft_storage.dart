import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// On-device NICU day drafts for Helper 2/3/4 when the nurse switches days
/// without tapping Save, or when the server row is not created yet (404).
class HelperDayDraftStorage {
  static String _key(String formKey, String enrollmentId, int nicuDay) =>
      'helper_draft_${formKey}_${enrollmentId.trim()}_d$nicuDay';

  static Future<void> save(
    String formKey,
    String enrollmentId,
    int nicuDay,
    Map<String, dynamic> json,
  ) async {
    final eid = enrollmentId.trim();
    if (eid.isEmpty || nicuDay < 1) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(formKey, eid, nicuDay), jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> load(
    String formKey,
    String enrollmentId,
    int nicuDay,
  ) async {
    final eid = enrollmentId.trim();
    if (eid.isEmpty || nicuDay < 1) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(formKey, eid, nicuDay));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clear(
    String formKey,
    String enrollmentId,
    int nicuDay,
  ) async {
    final eid = enrollmentId.trim();
    if (eid.isEmpty || nicuDay < 1) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(formKey, eid, nicuDay));
  }

  /// Minimal Monitoring and other calendar-day sheets (not NICU day index).
  static String _sheetDateKey(
    String formKey,
    String enrollmentId,
    String sheetDate,
  ) =>
      'helper_draft_${formKey}_${enrollmentId.trim()}_$sheetDate';

  static Future<void> saveBySheetDate(
    String formKey,
    String enrollmentId,
    String sheetDate,
    Map<String, dynamic> json,
  ) async {
    final eid = enrollmentId.trim();
    final d = sheetDate.trim();
    if (eid.isEmpty || d.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sheetDateKey(formKey, eid, d), jsonEncode(json));
  }

  static Future<Map<String, dynamic>?> loadBySheetDate(
    String formKey,
    String enrollmentId,
    String sheetDate,
  ) async {
    final eid = enrollmentId.trim();
    final d = sheetDate.trim();
    if (eid.isEmpty || d.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sheetDateKey(formKey, eid, d));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static Future<void> clearBySheetDate(
    String formKey,
    String enrollmentId,
    String sheetDate,
  ) async {
    final eid = enrollmentId.trim();
    final d = sheetDate.trim();
    if (eid.isEmpty || d.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sheetDateKey(formKey, eid, d));
  }
}
