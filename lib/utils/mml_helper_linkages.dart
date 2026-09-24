// Daily Monitoring Sheet (DMS) → Helper 2–5 autofill parsers.
// Mirrors web RespCVNeuroLog / InfectGIHemaLog / MetabRenalVascEyeLog.

import 'dart:convert';

import '../models/resp_cv_neuro_day.dart';

const mmlGlucoseLowMax = 45.0;
const mmlGlucoseHighMin = 125.0;

/// Helper 4 #15 effective weight (kg).
/// Latest DMS 5.7.A (`growth_a.weight_g` / 1000) is used only once it has
/// recovered to/past birth weight; otherwise stay on birth weight (grams/1000).
/// Falls back to whichever of the two is available.
double? effectiveFeedWeightKg({
  double? dmsWeightKg,
  double? birthWeightGrams,
}) {
  final birthKg = (birthWeightGrams != null && birthWeightGrams > 0)
      ? birthWeightGrams / 1000.0
      : null;
  if (dmsWeightKg != null && birthKg != null) {
    return dmsWeightKg >= birthKg ? dmsWeightKg : birthKg;
  }
  return birthKg ?? dmsWeightKg;
}

/// #15 Feed Volume ml/kg/d = cumulative ml ÷ effective kg, 1 decimal.
double? feedVolumeMlPerKgDay(double? cumVolMl, double? effectiveWeightKg) {
  if (cumVolMl == null || effectiveWeightKg == null || !(effectiveWeightKg > 0)) {
    return null;
  }
  return ((cumVolMl / effectiveWeightKg) * 10).round() / 10.0;
}

String formatFeedVolumeMlPerKgDay(double v) {
  final tenths = (v * 10).round();
  if (tenths % 10 == 0) return '${tenths ~/ 10}';
  return (tenths / 10).toString();
}

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
bool mmlFluidBolusValuePresent(dynamic raw) {
  if (raw == null) return false;
  final s = raw.toString();
  if (s.isEmpty) return false;
  return RegExp(r'^\s*\d+(?:\.\d+)?').hasMatch(s);
}

/// 5.1.B cv_b on the helper NICU calendar day → Helper 2 #29 fluid bolus given.
bool mmlHasFluidBolusForHelperDay(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  bool rowOnHelperDay(Map row) {
    if (helperCalendarDate == null || helperCalendarDate.isEmpty) return true;
    final d = row['date']?.toString();
    if (d == null || d.isEmpty) return true;
    final ds = d.length >= 10 ? d.substring(0, 10) : d;
    return ds == helperCalendarDate;
  }

  final entries = parseMmlEntriesJson(data['entries_json']);
  final cvB = entries?['cv_b'];
  if (cvB is List && cvB.isNotEmpty) {
    for (final e in cvB) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      if (!rowOnHelperDay(map)) continue;
      if (!mmlJsonEntryHasData(map)) continue;
      if (mmlFluidBolusValuePresent(map['fluid_bolus_given'])) return true;
    }
    return false;
  }
  if (entries == null) {
    return mmlFluidBolusValuePresent(data['fluid_bolus_given']);
  }
  return false;
}

bool mmlHasFluidBolus(Map<String, dynamic> data) {
  return mmlHasFluidBolusForHelperDay(data);
}

List<double> parseGiAFeedVolumeValues(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  bool rowOnHelperDay(Map row) {
    if (helperCalendarDate == null || helperCalendarDate.isEmpty) return true;
    final d = row['date']?.toString();
    if (d == null || d.isEmpty) return true;
    final ds = d.length >= 10 ? d.substring(0, 10) : d;
    return ds == helperCalendarDate;
  }

  final values = <double>[];
  final entries = parseMmlEntriesJson(data['entries_json']);
  final giA = entries?['gi_a'];
  if (giA is List && giA.isNotEmpty) {
    for (final e in giA) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      if (!rowOnHelperDay(map)) continue;
      if (!mmlJsonEntryHasData(map)) continue;
      final n = double.tryParse(map['cumulative_feed_volume']?.toString() ?? '');
      if (n != null) values.add(n);
    }
    return values;
  }
  if (entries == null) {
    final flat = double.tryParse(data['cumulative_feed_volume']?.toString() ?? '');
    if (flat != null) values.add(flat);
  }
  return values;
}

List<double> mergeGiAFeedValueLists(List<double> a, List<double> b) =>
    [...a, ...b];

double? sumGiAFeedVolumeValues(List<double> values) {
  if (values.isEmpty) return null;
  return values.fold<double>(0, (sum, n) => sum + n);
}

/// Sum of gi_a cumulative_feed_volume entries; legacy flat column fallback.
double? mmlSumCumulativeFeedVolume(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  return sumGiAFeedVolumeValues(
    parseGiAFeedVolumeValues(data, helperCalendarDate: helperCalendarDate),
  );
}

bool feedVolumeLooksMmlSourced(String? current, List<double> entryValues) {
  final ints = entryValues.map((v) => v.round()).where((v) => v >= 0).toList();
  return episodeTotalLooksMmlSourced(current, ints);
}

class MmlStringFieldSync {
  final String nextValue;
  final bool nextAutofilled;
  final bool changed;

  const MmlStringFieldSync({
    required this.nextValue,
    required this.nextAutofilled,
    required this.changed,
  });
}

bool mmlIsEmptyField(String? value) {
  return value == null || value.trim().isEmpty;
}

/// Mirror MML aggregate onto a helper text field (update sum/min/max or clear when MML empty).
MmlStringFieldSync mmlSyncAggregateFieldFromMml({
  required String? current,
  required bool blockedByNotDone,
  required bool wasAutofilled,
  required bool stillMatchesLastAuto,
  required bool Function(String?, dynamic) looksSourced,
  required dynamic entryValuesForSourced,
  required String? mmlValue,
  bool force = false,
}) {
  if (blockedByNotDone) {
    return MmlStringFieldSync(
      nextValue: current?.trim() ?? '',
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  final cur = current?.trim() ?? '';
  final isEmpty = cur.isEmpty;
  final canTouch = force ||
      isEmpty ||
      stillMatchesLastAuto ||
      wasAutofilled ||
      looksSourced(current, entryValuesForSourced);

  final mml = mmlValue?.trim() ?? '';
  final hasMml = mml.isNotEmpty;

  if (hasMml) {
    if (!canTouch) {
      return MmlStringFieldSync(
        nextValue: cur,
        nextAutofilled: wasAutofilled,
        changed: false,
      );
    }
    if (cur == mml) {
      return MmlStringFieldSync(
        nextValue: mml,
        nextAutofilled: true,
        changed: !wasAutofilled,
      );
    }
    return MmlStringFieldSync(
      nextValue: mml,
      nextAutofilled: true,
      changed: true,
    );
  }

  if (isEmpty) {
    if (wasAutofilled) {
      return const MmlStringFieldSync(
        nextValue: '',
        nextAutofilled: false,
        changed: true,
      );
    }
    return MmlStringFieldSync(
      nextValue: cur,
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  if (!canTouch) {
    return MmlStringFieldSync(
      nextValue: cur,
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  return const MmlStringFieldSync(
    nextValue: '',
    nextAutofilled: false,
    changed: true,
  );
}

bool glucoseFieldLooksMmlSourced(
  String? current,
  String fieldKey,
  List<double> readings,
) {
  final expected = computeGlucoseAutofillFromMml(readings)[fieldKey];
  if (expected == null) return false;
  return (current?.trim() ?? '') == expected.trim();
}

bool mmlGlucoseStaleWhenNoReadings(
  String? current,
  String fieldKey,
  List<double> readings,
) {
  if (readings.isNotEmpty) return false;
  final t = current?.trim() ?? '';
  if (t.isEmpty) return false;
  const sentinels = {'Not Tested', 'Not Low', 'Not High', '0'};
  if (sentinels.contains(t)) return false;
  if (fieldKey == 'hypoglycemia_episodes' && t == '0') return false;
  return true;
}

MmlStringFieldSync mmlSyncGlucoseFieldFromMml({
  required String? current,
  required bool wasAutofilled,
  required bool stillMatchesLastAuto,
  required bool force,
  required String fieldKey,
  required List<double> readings,
  required String computedValue,
}) {
  final cur = current?.trim() ?? '';
  final next = computedValue.trim();
  final canTouch = force ||
      mmlIsEmptyField(current) ||
      stillMatchesLastAuto ||
      wasAutofilled ||
      glucoseFieldLooksMmlSourced(current, fieldKey, readings) ||
      mmlGlucoseStaleWhenNoReadings(current, fieldKey, readings);

  if (!canTouch) {
    return MmlStringFieldSync(
      nextValue: cur,
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  if (cur == next) {
    return MmlStringFieldSync(
      nextValue: next,
      nextAutofilled: true,
      changed: !wasAutofilled,
    );
  }
  return MmlStringFieldSync(
    nextValue: next,
    nextAutofilled: true,
    changed: true,
  );
}

/// 5.6.A product flags for Helper 3 #28–#30 (any reading that day).
class MmlHemeTransfusionFlags {
  final bool prbc;
  final bool platelet;
  final bool ffpCryo;

  const MmlHemeTransfusionFlags({
    this.prbc = false,
    this.platelet = false,
    this.ffpCryo = false,
  });

  bool get any => prbc || platelet || ffpCryo;

  MmlHemeTransfusionFlags merge(MmlHemeTransfusionFlags other) {
    return MmlHemeTransfusionFlags(
      prbc: prbc || other.prbc,
      platelet: platelet || other.platelet,
      ffpCryo: ffpCryo || other.ffpCryo,
    );
  }
}

List<String> mmlParseTransfusionProducts(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

MmlHemeTransfusionFlags parseHemeATransfusionFlags(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  bool rowOnHelperDay(Map row) {
    if (helperCalendarDate == null || helperCalendarDate.isEmpty) return true;
    final d = row['date']?.toString();
    if (d == null || d.isEmpty) return true;
    final ds = d.length >= 10 ? d.substring(0, 10) : d;
    return ds == helperCalendarDate;
  }

  var prbc = false;
  var platelet = false;
  var ffpCryo = false;

  void absorbProducts(List<String> products) {
    if (products.contains('PRBC')) prbc = true;
    if (products.contains('Platelets')) platelet = true;
    if (products.contains('FFP/Cryo')) ffpCryo = true;
  }

  final entries = parseMmlEntriesJson(data['entries_json']);
  final list = entries?['heme_a'];
  if (list is List && list.isNotEmpty) {
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (!rowOnHelperDay(map)) continue;
      if (!mmlJsonEntryHasData(map)) continue;
      absorbProducts(mmlParseTransfusionProducts(map['transfusion_products']));
    }
    return MmlHemeTransfusionFlags(
      prbc: prbc,
      platelet: platelet,
      ffpCryo: ffpCryo,
    );
  }
  if (entries == null) {
    absorbProducts(mmlParseTransfusionProducts(data['transfusion_products']));
  }
  return MmlHemeTransfusionFlags(
    prbc: prbc,
    platelet: platelet,
    ffpCryo: ffpCryo,
  );
}

/// MML may set Yes only; never auto-No. Respect explicit nurse No (false).
bool mmlYnLooksMmlSourced(bool? current, bool mmlYes) {
  if (!mmlYes) return false;
  return current == null || current == true;
}

class MmlTransfusionYnSync {
  final bool? nextValue;
  final bool nextAutofilled;
  final bool changed;

  const MmlTransfusionYnSync({
    required this.nextValue,
    required this.nextAutofilled,
    required this.changed,
  });
}

/// Mirror 5.6.A products onto Helper #28–#30; respect nurse explicit No (false).
MmlTransfusionYnSync mmlSyncTransfusionYnFromMml({
  required bool? current,
  required bool mmlHas,
  required bool wasAutofilled,
}) {
  if (current == false) {
    return MmlTransfusionYnSync(
      nextValue: current,
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  if (mmlHas) {
    if (mmlYnLooksMmlSourced(current, true) || wasAutofilled) {
      final changed = current != true;
      return MmlTransfusionYnSync(
        nextValue: true,
        nextAutofilled: true,
        changed: changed,
      );
    }
    return MmlTransfusionYnSync(
      nextValue: current,
      nextAutofilled: wasAutofilled,
      changed: false,
    );
  }
  if (current == true) {
    return const MmlTransfusionYnSync(
      nextValue: null,
      nextAutofilled: false,
      changed: true,
    );
  }
  return MmlTransfusionYnSync(
    nextValue: current,
    nextAutofilled: wasAutofilled,
    changed: false,
  );
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

/// resp_b readings for Helper 2 #8–#10 (legacy flat columns when no entries_json).
class MmlRespBBloodGasReadings {
  final List<double> ph;
  final List<double> pao2;
  final List<double> paco2;

  const MmlRespBBloodGasReadings({
    this.ph = const [],
    this.pao2 = const [],
    this.paco2 = const [],
  });
}

MmlRespBBloodGasReadings parseRespBBloodGasReadings(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  void pushNum(List<double> arr, dynamic raw) {
    if (raw == null) return;
    final s = raw.toString().trim();
    if (s.isEmpty) return;
    final n = double.tryParse(s);
    if (n != null && n > 0) arr.add(n);
  }

  bool respBRowHasData(Map row) {
    for (final e in row.entries) {
      if (e.key == 'id' || e.key == 'date' || e.key == 'time') continue;
      final v = e.value;
      if (v == null) continue;
      if (v is bool) return true;
      if (v is List && v.isNotEmpty) return true;
      if (v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  final sheetYmd =
      _normalizeYmd(data['record_date']) ?? _normalizeYmd(helperCalendarDate);
  final effectiveDate = _normalizeYmd(helperCalendarDate) ?? sheetYmd;
  final sheetIsHelperDay = _mmlSheetMatchesHelperDay(data, effectiveDate);

  bool rowOnHelperDay(Map row) {
    if (sheetIsHelperDay) return true;
    if (effectiveDate == null || effectiveDate.isEmpty) return true;
    final ds = _normalizeYmd(row['date']) ?? sheetYmd;
    if (ds == null || ds.isEmpty) return true;
    return ds == effectiveDate;
  }

  final ph = <double>[];
  final pao2 = <double>[];
  final paco2 = <double>[];

  final entries = parseMmlEntriesJson(data['entries_json']);
  final list = entries?['resp_b'];
  if (list is List && list.isNotEmpty) {
    for (final row in list) {
      if (row is! Map) continue;
      if (!rowOnHelperDay(row)) continue;
      if (!respBRowHasData(row)) continue;
      pushNum(ph, row['ph']);
      pushNum(pao2, row['pao2']);
      pushNum(paco2, row['paco2']);
    }
  }
  if (entries == null) {
    pushNum(ph, data['ph']);
    pushNum(pao2, data['pao2']);
    pushNum(paco2, data['paco2']);
  }
  return MmlRespBBloodGasReadings(ph: ph, pao2: pao2, paco2: paco2);
}

bool mmlRespBHasBloodGasRows(MmlRespBBloodGasReadings r) =>
    r.ph.isNotEmpty || r.pao2.isNotEmpty || r.paco2.isNotEmpty;

MmlRespBBloodGasReadings mergeRespBBloodGasReadings(
  MmlRespBBloodGasReadings a,
  MmlRespBBloodGasReadings b,
) {
  return MmlRespBBloodGasReadings(
    ph: [...a.ph, ...b.ph],
    pao2: [...a.pao2, ...b.pao2],
    paco2: [...a.paco2, ...b.paco2],
  );
}

bool mmlBloodGasNumMatches(double a, double b) => (a - b).abs() < 1e-6;

/// True when the helper value is empty or matches a 5.2.B reading (safe to refresh).
bool bloodGasPhLooksMmlSourced(String? current, List<double> readings) {
  if (current == null || current.trim().isEmpty) return true;
  final n = double.tryParse(current.trim());
  if (n == null || readings.isEmpty) return false;
  final minPh = readings.reduce((a, b) => a < b ? a : b);
  return mmlBloodGasNumMatches(n, minPh);
}

bool bloodGasRangeLooksMmlSourced(
  String? low,
  String? high,
  List<double> readings,
) {
  final loEmpty = low == null || low.trim().isEmpty;
  final hiEmpty = high == null || high.trim().isEmpty;
  if (loEmpty && hiEmpty) return true;
  final lo = double.tryParse(low?.trim() ?? '');
  final hi = double.tryParse(high?.trim() ?? '');
  if (lo == null || hi == null) return false;
  if (readings.isEmpty) return false;
  final minR = readings.reduce((a, b) => a < b ? a : b);
  final maxR = readings.reduce((a, b) => a > b ? a : b);
  return mmlBloodGasNumMatches(lo, minR) && mmlBloodGasNumMatches(hi, maxR);
}

String _mmlFmtBloodGasNum(double n) {
  final r = (n * 100).roundToDouble() / 100;
  return r == r.roundToDouble() ? '${r.round()}' : '$r';
}

/// Maps 5.2.B → Helper 2 lowest pH and PaO₂/PaCO₂ low–high ranges.
Map<String, String> computeBloodGasAutofillFromMml(MmlRespBBloodGasReadings r) {
  final out = <String, String>{};
  if (r.ph.isNotEmpty) {
    out['lowest_ph'] = _mmlFmtBloodGasNum(r.ph.reduce((a, b) => a < b ? a : b));
  }
  if (r.pao2.isNotEmpty) {
    final lo = r.pao2.reduce((a, b) => a < b ? a : b);
    final hi = r.pao2.reduce((a, b) => a > b ? a : b);
    out['pao2_low'] = _mmlFmtBloodGasNum(lo);
    out['pao2_high'] = _mmlFmtBloodGasNum(hi);
  }
  if (r.paco2.isNotEmpty) {
    final lo = r.paco2.reduce((a, b) => a < b ? a : b);
    final hi = r.paco2.reduce((a, b) => a > b ? a : b);
    out['paco2_low'] = _mmlFmtBloodGasNum(lo);
    out['paco2_high'] = _mmlFmtBloodGasNum(hi);
  }
  return out;
}

bool _mmlJsonValueAnswered(dynamic v) {
  if (v == null) return false;
  if (v is bool) return true;
  if (v is List) return v.isNotEmpty;
  return v.toString().trim().isNotEmpty;
}

bool mmlJsonEntryHasData(Map row) {
  for (final e in row.entries) {
    if (e.key == 'id' || e.key == 'date' || e.key == 'time') continue;
    if (_mmlJsonValueAnswered(e.value)) return true;
  }
  return false;
}

class MmlRespCEpisodeReadings {
  final List<int> apnea;
  final List<int> desaturation;
  final List<int> severeDesat;

  const MmlRespCEpisodeReadings({
    this.apnea = const [],
    this.desaturation = const [],
    this.severeDesat = const [],
  });
}

MmlRespCEpisodeReadings parseRespCEpisodeReadings(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  void pushInt(List<int> arr, dynamic raw) {
    if (raw == null) return;
    final s = raw.toString().trim();
    if (s.isEmpty) return;
    final n = int.tryParse(s);
    if (n != null && n >= 0) arr.add(n);
  }

  final sheetYmd =
      _normalizeYmd(data['record_date']) ?? _normalizeYmd(helperCalendarDate);
  final effectiveDate = _normalizeYmd(helperCalendarDate) ?? sheetYmd;
  final sheetIsHelperDay = _mmlSheetMatchesHelperDay(data, effectiveDate);

  bool rowOnHelperDay(Map row) {
    if (sheetIsHelperDay) return true;
    if (effectiveDate == null || effectiveDate.isEmpty) return true;
    final ds = _normalizeYmd(row['date']) ?? sheetYmd;
    if (ds == null || ds.isEmpty) return true;
    return ds == effectiveDate;
  }

  void appendFlatRespC(
    List<int> apnea,
    List<int> desaturation,
    List<int> severeDesat,
  ) {
    final helperYmd = _normalizeYmd(effectiveDate);
    final sheet = _normalizeYmd(sheetYmd);
    if (helperYmd != null && sheet != null && sheet != helperYmd) return;
    pushInt(apnea, data['apnea_episodes']);
    pushInt(desaturation, data['desaturation_episodes']);
    pushInt(severeDesat, data['severe_desaturation_episodes']);
  }

  final apnea = <int>[];
  final desaturation = <int>[];
  final severeDesat = <int>[];

  final entries = parseMmlEntriesJson(data['entries_json']);
  final list = entries?['resp_c'];
  if (list is List && list.isNotEmpty) {
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (!rowOnHelperDay(map)) continue;
      if (!mmlJsonEntryHasData(map)) continue;
      pushInt(apnea, map['apnea_episodes']);
      pushInt(desaturation, map['desaturation_episodes']);
      pushInt(severeDesat, map['severe_desaturation_episodes']);
    }
  }
  if (entries == null) {
    appendFlatRespC(apnea, desaturation, severeDesat);
  }
  return MmlRespCEpisodeReadings(
    apnea: apnea,
    desaturation: desaturation,
    severeDesat: severeDesat,
  );
}

bool mmlRespCHasEpisodeRows(MmlRespCEpisodeReadings r) =>
    r.apnea.isNotEmpty || r.desaturation.isNotEmpty || r.severeDesat.isNotEmpty;

MmlRespCEpisodeReadings mergeRespCEpisodeReadings(
  MmlRespCEpisodeReadings a,
  MmlRespCEpisodeReadings b,
) {
  return MmlRespCEpisodeReadings(
    apnea: [...a.apnea, ...b.apnea],
    desaturation: [...a.desaturation, ...b.desaturation],
    severeDesat: [...a.severeDesat, ...b.severeDesat],
  );
}

Map<String, String> computeEpisodeAutofillFromMml(MmlRespCEpisodeReadings r) {
  final out = <String, String>{};
  void putSum(String key, List<int> vals) {
    if (vals.isEmpty) return;
    final total = vals.fold<int>(0, (a, b) => a + b);
    if (total > 0) {
      out[key] = _mmlFmtBloodGasNum(total.toDouble());
    }
  }

  putSum('apnea_count', r.apnea);
  putSum('desaturation_count', r.desaturation);
  putSum('severe_desaturation_count', r.severeDesat);
  return out;
}

/// True when MML 5.2.C aggregate is a positive count (ignore stale flat `0`).
bool mmlEpisodeComputedCountIsReal(Map<String, String> computed, String key) {
  final mml = computed[key];
  if (mml == null || mml.trim().isEmpty) return false;
  final n = int.tryParse(mml.trim());
  return n != null && n > 0;
}

bool episodeTotalLooksMmlSourced(String? current, List<int> entryValues) {
  if (current == null || current.trim().isEmpty) return true;
  final n = int.tryParse(current.trim());
  if (n == null || n < 0 || entryValues.isEmpty) return false;
  final total = entryValues.fold<int>(0, (a, b) => a + b);
  if (n == total) return true;
  final sums = <int>{0};
  for (final v in entryValues) {
    final next = <int>{...sums};
    for (final s in sums) {
      next.add(s + v);
    }
    sums
      ..clear()
      ..addAll(next);
  }
  return sums.contains(n);
}

bool mmlEpisodeFieldIsNotDone(String? value) {
  final t = value?.trim() ?? '';
  return t == 'Not Recorded / Not Done' || t == 'Not Done';
}

const kMmlNotRecordedLabel = 'Not Recorded / Not Done';

class MmlHelperSingleField {
  final String value;
  final bool notDone;

  const MmlHelperSingleField({required this.value, required this.notDone});
}

MmlHelperSingleField mmlParseHelperSingleField(String? str) {
  if (str == kMmlNotRecordedLabel) {
    return const MmlHelperSingleField(value: '', notDone: true);
  }
  return MmlHelperSingleField(value: str ?? '', notDone: false);
}

String? mmlCombineHelperSingleField(String value, bool notDone) {
  if (notDone) return kMmlNotRecordedLabel;
  final t = value.trim();
  return t.isEmpty ? null : t;
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

List<String> _mmlRespAModesList(Map row) {
  final v = row['respiratory_modes'];
  if (v is List) {
    return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  return v
          ?.toString()
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList() ??
      [];
}

/// Helper 2 pills use `AC`; MML 5.2.A uses `A/C`.
List<String> normalizeHelperSupportModes(List<String> modes) {
  final out = <String>{};
  for (final m in modes) {
    if (m.isEmpty) continue;
    out.add(m == 'A/C' ? 'AC' : m);
  }
  return out.toList();
}

/// Calendar YMD for MML ↔ Helper day matching (DD-MM-YYYY or ISO).
String? normalizeMmlYmd(dynamic raw) => _normalizeYmd(raw);

String? _normalizeYmd(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.substring(0, 10);
  final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
  if (dmy != null) {
    final dd = dmy.group(1)!.padLeft(2, '0');
    final mm = dmy.group(2)!.padLeft(2, '0');
    return '${dmy.group(3)}-$mm-$dd';
  }
  return s.length >= 10 ? s.substring(0, 10) : s;
}

bool _mmlSheetMatchesHelperDay(Map<String, dynamic> data, String? helperYmd) {
  if (helperYmd == null || helperYmd.isEmpty) return false;
  final sheetYmd = _normalizeYmd(data['record_date']);
  return sheetYmd != null && sheetYmd == _normalizeYmd(helperYmd);
}

List<Map<String, dynamic>> parseRespAEntries(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
}) {
  final sheetYmd = _normalizeYmd(data['record_date']) ?? _normalizeYmd(helperCalendarDate);
  final effectiveDate = _normalizeYmd(helperCalendarDate) ?? sheetYmd;
  final sheetIsHelperDay = _mmlSheetMatchesHelperDay(data, effectiveDate);

  bool rowOnHelperDay(Map row) {
    if (sheetIsHelperDay) return true;
    if (effectiveDate == null || effectiveDate.isEmpty) return true;
    final ds = _normalizeYmd(row['date']) ?? sheetYmd;
    if (ds == null || ds.isEmpty) return true;
    return ds == effectiveDate;
  }

  void appendFlatRespA(List<Map<String, dynamic>> rows) {
    final helperYmd = _normalizeYmd(effectiveDate);
    final sheet = _normalizeYmd(sheetYmd);
    if (helperYmd != null && sheet != null && sheet != helperYmd) return;
    final modes = _mmlRespAModesList({
      'respiratory_modes': data['respiratory_modes'],
    });
    final hasFlat = modes.isNotEmpty ||
        (data['max_fio2']?.toString().trim().isNotEmpty == true) ||
        (data['max_map_cpap']?.toString().trim().isNotEmpty == true) ||
        (data['max_map_cpap_secondary']?.toString().trim().isNotEmpty == true);
    if (!hasFlat) return;
    rows.add({
      'date': sheetYmd,
      'respiratory_modes': modes,
      'max_map_cpap': data['max_map_cpap'] ?? '',
      'max_map_cpap_secondary': data['max_map_cpap_secondary'] ?? '',
      'max_fio2': data['max_fio2'] ?? '',
    });
  }

  final rows = <Map<String, dynamic>>[];
  final entries = parseMmlEntriesJson(data['entries_json']);
  final list = entries?['resp_a'];
  if (list is List && list.isNotEmpty) {
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (!rowOnHelperDay(map)) continue;
      final modes = _mmlRespAModesList(map);
      final hasNums = map['max_fio2']?.toString().trim().isNotEmpty == true ||
          map['max_map_cpap']?.toString().trim().isNotEmpty == true ||
          map['max_map_cpap_secondary']?.toString().trim().isNotEmpty == true;
      if (modes.isEmpty && !hasNums) continue;
      rows.add(map);
    }
  }

  appendFlatRespA(rows);

  if (rows.isEmpty && entries == null) {
    appendFlatRespA(rows);
  }

  return rows;
}

class MmlRespAAutofill {
  final List<String> modesUnion;
  final String? aggregateMode;
  final List<double> cpapVals;
  final List<double> mapVals;
  final List<double> fio2Vals;
  final String? maxFio2;
  final String? mapCpap;
  final String? mapCpapSecondary;
  final bool hasRows;

  const MmlRespAAutofill({
    this.modesUnion = const [],
    this.aggregateMode,
    this.cpapVals = const [],
    this.mapVals = const [],
    this.fio2Vals = const [],
    this.maxFio2,
    this.mapCpap,
    this.mapCpapSecondary,
    this.hasRows = false,
  });
}

MmlRespAAutofill computeRespAAutofillFromMml(List<Map<String, dynamic>> rows) {
  final cpapVals = <double>[];
  final mapVals = <double>[];
  final fio2Vals = <double>[];
  final modeSet = <String>{};

  void pushNum(List<double> arr, dynamic raw) {
    if (raw == null) return;
    final s = raw.toString().trim();
    if (s.isEmpty) return;
    final n = double.tryParse(s);
    if (n != null) arr.add(n);
  }

  for (final row in rows) {
    final modes = _mmlRespAModesList(row);
    modeSet.addAll(modes);
    final mode = RespCvNeuroValidators.mapCpapMode(modes);
    if (mode == 'BOTH') {
      pushNum(cpapVals, row['max_map_cpap_secondary']);
      pushNum(mapVals, row['max_map_cpap']);
    } else if (mode == 'CPAP') {
      pushNum(cpapVals, row['max_map_cpap']);
    } else if (mode == 'MAP') {
      pushNum(mapVals, row['max_map_cpap']);
    }
    pushNum(fio2Vals, row['max_fio2']);
  }

  final modesUnion = normalizeHelperSupportModes(modeSet.toList());
  final aggregateMode = RespCvNeuroValidators.mapCpapMode(modesUnion);
  final maxCpap =
      cpapVals.isEmpty ? null : cpapVals.reduce((a, b) => a > b ? a : b);
  final maxMap =
      mapVals.isEmpty ? null : mapVals.reduce((a, b) => a > b ? a : b);
  final maxFio2 =
      fio2Vals.isEmpty ? null : fio2Vals.reduce((a, b) => a > b ? a : b);

  String? fmt(double? n) =>
      n == null ? null : _mmlFmtBloodGasNum(n);

  String? mapCpap;
  String? mapCpapSecondary;
  if (aggregateMode == 'BOTH') {
    mapCpap = fmt(maxMap);
    mapCpapSecondary = fmt(maxCpap);
  } else if (aggregateMode == 'CPAP') {
    mapCpap = fmt(maxCpap);
  } else if (aggregateMode == 'MAP') {
    mapCpap = fmt(maxMap);
  }

  return MmlRespAAutofill(
    modesUnion: modesUnion,
    aggregateMode: aggregateMode,
    cpapVals: cpapVals,
    mapVals: mapVals,
    fio2Vals: fio2Vals,
    maxFio2: fmt(maxFio2),
    mapCpap: mapCpap,
    mapCpapSecondary: mapCpapSecondary,
    hasRows: rows.isNotEmpty,
  );
}

bool respNumericLooksMmlSourced(String? current, List<double> values) {
  if (current == null || current.trim().isEmpty) return true;
  final n = double.tryParse(current.trim());
  if (n == null || values.isEmpty) return false;
  final maxV = values.reduce((a, b) => a > b ? a : b);
  return mmlBloodGasNumMatches(n, maxV);
}

bool respModesUnionLooksSourced(List<String> current, List<String> union) {
  final a = normalizeHelperSupportModes(current).toSet();
  final b = normalizeHelperSupportModes(union).toSet();
  if (a.isEmpty) return true;
  if (b.isEmpty) return true;
  return a.length == b.length && a.containsAll(b);
}

bool modesArraysEqual(List<String>? a, List<String>? b) {
  final na = normalizeHelperSupportModes(a ?? const []);
  final nb = normalizeHelperSupportModes(b ?? const []);
  if (na.isEmpty && nb.isEmpty) return true;
  return respModesUnionLooksSourced(na, nb) &&
      respModesUnionLooksSourced(nb, na);
}

/// DMS 5.1.C uses Epinephrine/Norepinephrine; Helper 2 pills use Adrenaline/Noradrenaline.
const vasoactiveDrugNameAliases = {
  'Epinephrine': 'Adrenaline',
  'Norepinephrine': 'Noradrenaline',
};

class MmlListFieldAutofill {
  final bool hasRows;
  final List<String> values;
  const MmlListFieldAutofill({
    this.hasRows = false,
    this.values = const [],
  });
}

List<String> _mmlListFieldValues(dynamic row, String listKey) {
  dynamic v;
  if (row is Map) v = row[listKey];
  if (v is List) {
    return v
        .map((x) => x.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (v == null) return const [];
  return v
      .toString()
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

MmlListFieldAutofill parseMmlListField(
  Map<String, dynamic> data, {
  String? helperCalendarDate,
  required String blockKey,
  required String listKey,
  Map<String, String>? valueMap,
}) {
  final sheetYmd =
      _normalizeYmd(data['record_date']) ?? _normalizeYmd(helperCalendarDate);
  final effectiveDate = _normalizeYmd(helperCalendarDate) ?? sheetYmd;
  final sheetIsHelperDay = _mmlSheetMatchesHelperDay(data, effectiveDate);

  bool rowOnHelperDay(Map row) {
    if (sheetIsHelperDay) return true;
    if (effectiveDate == null || effectiveDate.isEmpty) return true;
    final ds = _normalizeYmd(row['date']) ?? sheetYmd;
    if (ds == null || ds.isEmpty) return true;
    return ds == effectiveDate;
  }

  final seen = <String>[];
  void push(String raw) {
    final mapped = valueMap?[raw] ?? raw;
    if (mapped.isNotEmpty && !seen.contains(mapped)) seen.add(mapped);
  }

  final entries = parseMmlEntriesJson(data['entries_json']);
  final list = entries?[blockKey];
  if (list is List && list.isNotEmpty) {
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (!rowOnHelperDay(map)) continue;
      for (final v in _mmlListFieldValues(map, listKey)) {
        push(v);
      }
    }
  }
  if (seen.isEmpty && entries == null) {
    for (final v in _mmlListFieldValues(data, listKey)) {
      push(v);
    }
  }
  return MmlListFieldAutofill(hasRows: seen.isNotEmpty, values: seen);
}

MmlListFieldAutofill mergeMmlListFieldAutofill(
  Iterable<MmlListFieldAutofill?> parts,
) {
  final seen = <String>[];
  var hasRows = false;
  for (final part in parts) {
    if (part == null) continue;
    if (part.hasRows) hasRows = true;
    for (final v in part.values) {
      if (v.isNotEmpty && !seen.contains(v)) seen.add(v);
    }
  }
  return MmlListFieldAutofill(
    hasRows: hasRows || seen.isNotEmpty,
    values: seen,
  );
}

String formatNicuCalendarYmd(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

({String from, String to}) parseMmlTimeRangeStr(dynamic value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty) return (from: '', to: '');
  final parts = s
      .split(RegExp(r'\s*[–—−-]\s*|\s+to\s+', caseSensitive: false))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  String toHHmm(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$', caseSensitive: false)
        .firstMatch(raw.trim());
    if (m == null) return '';
    var h = int.tryParse(m.group(1)!) ?? -1;
    final min = m.group(2)!;
    final ap = (m.group(3) ?? '').toUpperCase();
    if (ap == 'PM' && h < 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    if (h < 0 || h > 23) return '';
    return '${h.toString().padLeft(2, '0')}:$min';
  }

  if (parts.length == 1) return (from: toHHmm(parts[0]), to: '');
  return (from: toHHmm(parts[0]), to: toHHmm(parts[1]));
}

int? _hhmmToMinutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// DMS 5.2.A rows → FiO₂ AUC rectangles for the two 12h windows (web parity).
({List<Map<String, String>> w1, List<Map<String, String>> w2})
    buildFio2AucRowsFromRespA(List<Map<String, dynamic>> respARows) {
  final spans = <({int from, int to, double fio2})>[];
  for (final row in respARows) {
    final tr = parseMmlTimeRangeStr(row['time_range']);
    final fromMin = _hhmmToMinutes(tr.from);
    final toMin = _hhmmToMinutes(tr.to);
    if (fromMin == null || toMin == null || toMin <= fromMin) continue;
    final n = double.tryParse('${row['max_fio2'] ?? ''}');
    if (n == null) continue;
    spans.add((from: fromMin, to: toMin, fio2: n));
  }
  spans.sort((a, b) => a.from.compareTo(b.from));
  const boundary = 12 * 60;
  final w1Spans = <({int from, int to, double fio2})>[];
  final w2Spans = <({int from, int to, double fio2})>[];
  for (final s in spans) {
    if (s.to <= boundary) {
      w1Spans.add(s);
    } else if (s.from >= boundary) {
      w2Spans.add((from: s.from - boundary, to: s.to - boundary, fio2: s.fio2));
    } else {
      w1Spans.add((from: s.from, to: boundary, fio2: s.fio2));
      w2Spans.add((from: 0, to: s.to - boundary, fio2: s.fio2));
    }
  }
  List<Map<String, String>> toRows(List<({int from, int to, double fio2})> list) {
    return list
        .map((s) => {
              'fio2': s.fio2 == s.fio2.roundToDouble()
                  ? '${s.fio2.round()}'
                  : '${s.fio2}',
              'dur':
                  (((((s.to - s.from) / 60) * 100).round()) / 100).toString(),
            })
        .toList();
  }

  return (w1: toRows(w1Spans), w2: toRows(w2Spans));
}
