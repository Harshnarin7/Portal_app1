// Minimal Monitoring (Helper 5) → daily helper autofill parsers.
// Mirrors web RespCVNeuroLog / InfectGIHemaLog / MetabRenalVascEyeLog.

import 'dart:convert';

const mmlGlucoseLowMax = 45.0;
const mmlGlucoseHighMin = 180.0;

Map<String, dynamic>? parseMmlEntriesJson(dynamic raw) {
  if (raw == null) return null;
  dynamic entries = raw;
  if (entries is String) {
    try {
      entries = jsonDecode(entries);
    } catch (_) {
      return null;
    }
  }
  if (entries is Map) {
    return Map<String, dynamic>.from(entries);
  }
  return null;
}

/// True if MM sheet has any numeric 5.1.B bolus entry (cv_b or legacy column).
bool mmlHasFluidBolus(Map<String, dynamic> data) {
  bool hasLeadingNumber(dynamic raw) {
    if (raw == null) return false;
    final s = raw.toString();
    if (s.isEmpty) return false;
    return RegExp(r'^\s*\d+(?:\.\d+)?').hasMatch(s);
  }

  final entries = parseMmlEntriesJson(data['entries_json']);
  final cvB = entries?['cv_b'];
  if (cvB is List) {
    for (final e in cvB) {
      if (e is Map && hasLeadingNumber(e['fluid_bolus_given'])) return true;
    }
  }
  return hasLeadingNumber(data['fluid_bolus_given']);
}

/// Sum of gi_a cumulative_feed_volume entries; legacy flat column fallback.
double? mmlSumCumulativeFeedVolume(Map<String, dynamic> data) {
  final entries = parseMmlEntriesJson(data['entries_json']);
  final giA = entries?['gi_a'];
  if (giA is List && giA.isNotEmpty) {
    var sum = 0.0;
    var found = false;
    for (final e in giA) {
      if (e is! Map) continue;
      final n = double.tryParse(e['cumulative_feed_volume']?.toString() ?? '');
      if (n == null) continue;
      sum += n;
      found = true;
    }
    return found ? sum : null;
  }
  final flat = double.tryParse(data['cumulative_feed_volume']?.toString() ?? '');
  return flat;
}

/// met_a[].glucose readings; flat glucose only when entries_json missing.
List<double> parseMetAGlucoseReadings(Map<String, dynamic> data) {
  final entries = parseMmlEntriesJson(data['entries_json']);
  if (entries != null && entries['met_a'] is List) {
    final out = <double>[];
    for (final row in entries['met_a'] as List) {
      if (row is! Map) continue;
      final raw = row['glucose'];
      if (raw == null || raw.toString().trim().isEmpty) continue;
      final n = double.tryParse(raw.toString());
      if (n != null) out.add(n);
    }
    return out;
  }
  final flat = data['glucose'];
  if (flat != null && flat.toString().trim().isNotEmpty) {
    final n = double.tryParse(flat.toString());
    if (n != null) return [n];
  }
  return [];
}

Map<String, String> computeGlucoseAutofillFromMml(List<double> readings) {
  if (readings.isEmpty) {
    return {
      'lowest_glucose': 'Not Tested',
      'hypoglycemia_episodes': '0',
      'highest_glucose': 'Not Tested',
    };
  }
  final lows = readings.where((v) => v < mmlGlucoseLowMax).toList();
  final highs = readings.where((v) => v > mmlGlucoseHighMin).toList();
  String fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';
  return {
    'lowest_glucose':
        lows.isEmpty ? 'Not Low' : fmt(lows.reduce((a, b) => a < b ? a : b)),
    'hypoglycemia_episodes': '${lows.length}',
    'highest_glucose':
        highs.isEmpty ? 'Not High' : fmt(highs.reduce((a, b) => a > b ? a : b)),
  };
}

String formatNicuCalendarYmd(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
