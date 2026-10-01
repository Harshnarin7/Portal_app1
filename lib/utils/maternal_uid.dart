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

  static String saveError(String? site, String value) {
    final v = value.trim();
    if (site == 'PGIMER') {
      if (v.isEmpty) return 'CR number is required — exactly 12 digits.';
      if (!RegExp(r'^\d{12}$').hasMatch(v)) {
        return v.length > 12
            ? 'Cannot be more than 12 digits'
            : 'Must be exactly 12 digits';
      }
    }
    if (site == 'AMC') {
      if (v.isEmpty) return 'CR number is required — e.g. 123/2026.';
      if (!RegExp(r'^\d+/\d{4}$').hasMatch(v)) {
        return 'Must be in serial/year format, e.g. 123/2026';
      }
    }
    return '';
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
