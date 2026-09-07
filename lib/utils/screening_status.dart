// Mirrors backend/main.py compute_screening_status() so local CRF saves and
// patient chips match web ViewEntries: Eligible / Not Eligible / Screen Failure / Pending.

import 'package:flutter/material.dart';

String computeScreeningStatus({
  required int? gestationWeeks,
  int gestationDays = 0,
  bool? exclusionPresent,
  String? consentGiven,
  String? gestationKnown,
  String? gaSource,
}) {
  if (gestationKnown == 'No' && gaSource == 'Neither') {
    return 'Screen Failure';
  }

  if (gestationWeeks == null) {
    return 'Pending';
  }

  final totalDays = gestationWeeks * 7 + gestationDays;
  // Eligible window: 25w0d – 31w6d inclusive
  if (totalDays < 25 * 7 || totalDays > 31 * 7 + 6) {
    return 'Not Eligible';
  }

  if (exclusionPresent == true) {
    return 'Screen Failure';
  }

  final consent = (consentGiven ?? '').trim();
  if (consent == 'Yes' || consent == 'Trial run') {
    return 'Eligible';
  }
  if (consent == 'No' || consent == 'Not approached') {
    return 'Not Eligible';
  }
  return 'Pending';
}

Color screeningStatusColor(String status) {
  switch (status) {
    case 'Eligible':
      return const Color(0xFF15803D);
    case 'Screen Failure':
      return const Color(0xFFDC2626);
    case 'Not Eligible':
      return const Color(0xFFB45309);
    default:
      return const Color(0xFFD97706); // Pending
  }
}

/// Normalize any legacy / empty label to one of the four canonical statuses.
String normalizeScreeningStatus(String? raw) {
  final s = (raw ?? '').trim();
  if (s == 'Eligible' ||
      s == 'Not Eligible' ||
      s == 'Screen Failure' ||
      s == 'Pending') {
    return s;
  }
  if (s.isEmpty) return 'Pending';
  final lower = s.toLowerCase();
  if (lower == 'eligible' || lower == 'enrolled') return 'Eligible';
  if (lower == 'screen failure' || lower == 'excluded') return 'Screen Failure';
  if (lower == 'not eligible') return 'Not Eligible';
  if (lower == 'incomplete' || lower == 'pending') return 'Pending';
  return 'Pending';
}
