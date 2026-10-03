import 'package:flutter/services.dart';

/// Maternal UID / CR number — same rules as web ScreeningForm idFieldRule.
class MaternalUid {
  static String sanitize(String? site, String raw) {
    if (site == 'PGIMER') {
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      return digits.length > 12 ? digits.substring(0, 12) : digits;
    }
    if (site == 'AMC') return raw.replaceAll(RegExp(r'[^0-9/]'), '');
    return raw;
  }

  static String placeholder(String? site) {
    if (site == 'PGIMER') return '12-digit CR number';
    if (site == 'AMC') return 'e.g. 123/2026';
    return 'e.g. 20260495-4829';
  }

  static String liveError(String? site, String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (site == null || site.isEmpty) {
      return 'Select a site — the CR number format depends on the site.';
    }
    if (site == 'PGIMER' && !RegExp(r'^\d{12}$').hasMatch(v)) {
      return v.length > 12
          ? 'Cannot be more than 12 digits'
          : 'Must be exactly 12 digits';
    }
    if (site == 'AMC' && !RegExp(r'^\d+/\d{4}$').hasMatch(v)) {
      return 'Must be in serial/year format, e.g. 123/2026';
    }
    return '';
  }

  /// Format only. An empty CR number is allowed on both logs and is
  /// shown later as "CR pending".
  static String saveError(String? site, String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    return liveError(site, v);
  }

  static List<TextInputFormatter> formatters(String? site) {
    if (site == 'PGIMER') {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ];
    }
    if (site == 'AMC') {
      return [FilteringTextInputFormatter.allow(RegExp(r'[0-9/]'))];
    }
    return const [];
  }
}

/// Trim, uppercase, and strip spaces and hyphens — same as web `normalizeCr`.
String normalizeCr(String? value) =>
    (value ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');

/// Same site, same CR number, and same date of birth. Not a duplicate across
/// sites or different dates. [excludeId] skips the row being edited.
Map<String, dynamic>? findDuplicateCr(
  List<Map<String, dynamic>> entries, {
  required String? site,
  required String uid,
  int? excludeId,
  String? dateOfBirth,
  bool matchDob = false,
}) {
  final cr = normalizeCr(uid);
  if (cr.isEmpty || site == null || site.isEmpty) return null;
  for (final e in entries) {
    if (e['id'] == excludeId) continue;
    if (e['site_name'] != site) continue;
    if (normalizeCr(e['mother_uid']?.toString()) != cr) continue;
    if (matchDob &&
        (e['date_of_birth'] ?? '').toString() != (dateOfBirth ?? '')) {
      continue;
    }
    return e;
  }
  return null;
}
