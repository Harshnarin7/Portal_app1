// Helper Form 5 — Minimal Monitoring Log
// Dual-write like web MinimalMonitoringLog.jsx:
//   entries_json = full multi-entry map (source of truth + Form 4 glucose)
//   flat columns  = first entry of each block (flattenEntries)

import 'dart:convert';

import 'resp_cv_neuro_day.dart';

const kMmlBoundaryHour = 8;

/// Helper Form 5 header dropdown only (web `MML_DROPDOWN_CUTOFF_HOUR`).
/// Before this hour, nurses may pick yesterday or today; from this hour onward
/// only today. Unrelated to [kMmlBoundaryHour] used by `/today` and other forms.
const kMmlDropdownCutoffHour = 8;

/// Real local calendar date (YYYY-MM-DD), not grace-shifted NICU working day.
String realCalendarDateYmd([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

String mmlFormatDisplayDateYmd(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;
  final y = int.tryParse(parts[0]);
  final mo = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || mo == null || d == null) return ymd;
  return '${d.toString().padLeft(2, '0')}-'
      '${mo.toString().padLeft(2, '0')}-'
      '$y';
}

class MmlDropdownDateOption {
  final String value;
  final String label;
  const MmlDropdownDateOption(this.value, this.label);
}

List<MmlDropdownDateOption> mmlDropdownDateOptions({
  DateTime? now,
  int cutoffHour = kMmlDropdownCutoffHour,
}) {
  final n = now ?? DateTime.now();
  final today = realCalendarDateYmd(n);
  final y = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
  final yesterday = realCalendarDateYmd(y);
  MmlDropdownDateOption opt(String value) =>
      MmlDropdownDateOption(value, mmlFormatDisplayDateYmd(value));
  if (n.hour < cutoffHour) {
    return [opt(yesterday), opt(today)];
  }
  return [opt(today)];
}

String mmlDefaultSheetDate({
  DateTime? now,
  int cutoffHour = kMmlDropdownCutoffHour,
}) {
  final opts = mmlDropdownDateOptions(now: now, cutoffHour: cutoffHour);
  return opts.last.value;
}

/// Same rule as backend `_mml_sheet_date` / web `MML_BOUNDARY_HOUR`:
/// before [boundaryHour] local time, "today" is still yesterday's date.
DateTime? mmlParseDateTime(String dateYmd, String timeHm) {
  final dp = dateYmd.split('-');
  if (dp.length < 3) return null;
  final y = int.tryParse(dp[0]);
  final mo = int.tryParse(dp[1]);
  final d = int.tryParse(dp[2]);
  if (y == null || mo == null || d == null) return null;
  final tp = timeHm.trim().split(':');
  if (tp.isEmpty) return null;
  final h = int.tryParse(tp[0]) ?? 0;
  final min = tp.length > 1 ? (int.tryParse(tp[1]) ?? 0) : 0;
  return DateTime(y, mo, d, h, min);
}

bool mmlIsFutureDateTime(String dateYmd, String timeHm) {
  final dt = mmlParseDateTime(dateYmd, timeHm);
  if (dt == null) return false;
  return dt.isAfter(DateTime.now());
}

String mmlMaxAllowedTimeHm(String dateYmd, {DateTime? now}) {
  final todayReal = realCalendarDateYmd(now);
  if (dateYmd.compareTo(todayReal) > 0) return '00:00';
  if (dateYmd.compareTo(todayReal) < 0) return '23:59';
  final n = now ?? DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:'
      '${n.minute.toString().padLeft(2, '0')}';
}

const kMmlSevereDesatExceedsMsg =
    "Severe desaturations can't exceed total desaturation episodes";

void mmlApplyRespCEpisodeConstraints(MmlEntry entry) {
  final desat = int.tryParse(
    entry['desaturation_episodes']?.toString().trim() ?? '',
  );
  final severe = int.tryParse(
    entry['severe_desaturation_episodes']?.toString().trim() ?? '',
  );
  if (desat != null && severe != null && severe > desat) {
    entry['severe_desaturation_episodes'] = desat.toString();
  }
}

String mmlClampTimeHm(String dateYmd, String timeHm, {DateTime? now}) {
  if (timeHm.isEmpty) return timeHm;
  final hm = timeHm.length >= 5 ? timeHm.substring(0, 5) : timeHm;
  final max = mmlMaxAllowedTimeHm(dateYmd, now: now);
  return hm.compareTo(max) <= 0 ? hm : max;
}

/// Strip legacy "Should not have been done" sentinel from 5.1.B fluid bolus.
String mmlNormalizeFluidBolusValue(dynamic v) {
  if (v == null) return '';
  final s = v.toString().trim();
  if (s.isEmpty) return '';
  if (RegExp(r'^should\s+not\s+have\s+been\s+done$', caseSensitive: false)
      .hasMatch(s)) {
    return '';
  }
  return s;
}

void mmlSanitizeFluidBolusEntries(Map<String, List<MmlEntry>> entries) {
  for (final entry in entries['cv_b'] ?? const <MmlEntry>[]) {
    entry['fluid_bolus_given'] =
        mmlNormalizeFluidBolusValue(entry['fluid_bolus_given']);
  }
}

String mmlSheetDate({DateTime? now, int boundaryHour = kMmlBoundaryHour}) {
  final n = now ?? DateTime.now();
  var sheet = DateTime(n.year, n.month, n.day);
  final hour = boundaryHour.clamp(0, 23);
  if (n.hour < hour) {
    sheet = sheet.subtract(const Duration(days: 1));
  }
  return '${sheet.year.toString().padLeft(4, '0')}-'
      '${sheet.month.toString().padLeft(2, '0')}-'
      '${sheet.day.toString().padLeft(2, '0')}';
}

/// Next local DateTime when the Minimal Monitoring sheet rolls to a new day.
DateTime mmlNextBoundary({DateTime? now, int boundaryHour = kMmlBoundaryHour}) {
  final n = now ?? DateTime.now();
  final hour = boundaryHour.clamp(0, 23);
  var next = DateTime(n.year, n.month, n.day, hour);
  if (!n.isBefore(next)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}

const kMmlBlockKeys = [
  'cv_a',
  'cv_b',
  'cv_c',
  'cv_d',
  'resp_a',
  'resp_b',
  'resp_c',
  'resp_d',
  'met_a',
  'met_b',
  'met_c',
  'gi_a',
  'gi_b',
  'neuro_a',
  'neuro_b',
  'heme_a',
];

class MmlEntry {
  String id;
  String date;
  String time;
  final Map<String, dynamic> fields;

  MmlEntry({
    String? id,
    String? date,
    String? time,
    Map<String, dynamic>? fields,
  })  : id = id ?? _uid(),
        date = date ?? _todayYmd(),
        time = time ?? _nowHm(),
        fields = fields ?? {};

  static String _uid() =>
      '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch % 1000}';

  static String _todayYmd() => mmlSheetDate();

  static String _nowHm() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  dynamic operator [](String key) {
    if (key == 'id') return id;
    if (key == 'date') return date;
    if (key == 'time') return time;
    return fields[key];
  }

  void operator []=(String key, dynamic value) {
    if (key == 'id') {
      id = value?.toString() ?? id;
      return;
    }
    if (key == 'date') {
      date = value?.toString() ?? '';
      return;
    }
    if (key == 'time') {
      time = value?.toString() ?? '';
      return;
    }
    fields[key] = value;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'time': time,
        ...fields,
      };

  factory MmlEntry.fromJson(Map<String, dynamic> json) {
    final fields = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('date')
      ..remove('time');
    // Normalize list fields that may arrive as CSV
    for (final k in [
      'vasoactive_drugs',
      'pda_agent',
      'respiratory_modes',
      'postnatal_steroids',
      'electrolytes',
      'transfusion_products',
    ]) {
      if (fields[k] is String) {
        fields[k] = (fields[k] as String)
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (fields[k] is! List) {
        // leave as-is
      }
    }
    return MmlEntry(
      id: json['id']?.toString(),
      date: json['date']?.toString(),
      time: json['time']?.toString(),
      fields: fields,
    );
  }

  /// True when at least one clinical field is filled (ignores id/date/time).
  bool hasClinicalData() {
    for (final v in fields.values) {
      if (_mmlValueAnswered(v)) return true;
    }
    return false;
  }

  MmlEntry copy() => MmlEntry(
        id: id,
        date: date,
        time: time,
        fields: Map<String, dynamic>.from(fields.map((k, v) {
          if (v is List) return MapEntry(k, List.from(v));
          return MapEntry(k, v);
        })),
      );
}

bool _mmlValueAnswered(dynamic v) {
  if (v == null) return false;
  if (v is bool) return true;
  if (v is List) return v.isNotEmpty;
  return v.toString().trim().isNotEmpty;
}

class MinimalMonitoringSheet {
  final String enrollmentId;
  String? recordDate;
  String? submissionStatus;
  String? savedAt;
  String? savedBy;

  /// Block key → list of entries (same shape as web emptyEntries()).
  Map<String, List<MmlEntry>> entries = {};

  MinimalMonitoringSheet({required this.enrollmentId}) {
    entries = emptyEntries();
  }

  static MmlEntry fresh(Map<String, dynamic> fields) =>
      MmlEntry(fields: Map<String, dynamic>.from(fields));

  static String _nowTimeHm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  /// Web `commitFilledDraftRows` — filled trailing row becomes a saved reading.
  void commitFilledDraftRows(String sheetDateYmd) {
    for (final key in kMmlBlockKeys) {
      final list = entries[key];
      if (list == null || list.isEmpty) continue;
      if (!list.last.hasClinicalData()) continue;
      final template = Map<String, dynamic>.from(
        emptyEntries()[key]!.first.fields,
      );
      list.add(MmlEntry(
        id: '${DateTime.now().millisecondsSinceEpoch}-$key',
        date: sheetDateYmd,
        time: _nowTimeHm(),
        fields: template,
      ));
    }
  }

  /// Persist only rows with clinical data (no date/time-only draft shells).
  Map<String, dynamic> entriesMapForPersist() {
    final out = <String, dynamic>{};
    for (final k in kMmlBlockKeys) {
      out[k] = (entries[k] ?? [])
          .where((e) => e.hasClinicalData())
          .map((e) => e.toJson())
          .toList();
    }
    return out;
  }

  static Map<String, List<MmlEntry>> emptyEntries() => {
        'cv_a': [
          fresh({
            'axillary_temp': '',
            'sbp': '',
            'dbp': '',
            'map_value': '',
          })
        ],
        'cv_b': [fresh({'fluid_bolus_given': ''})],
        'cv_c': [
          fresh({
            'vasoactive_drugs': <String>[],
            'vasoactive_dose': '',
            'vasoactive_unit': '',
          })
        ],
        'cv_d': [
          fresh({'pda_agent': <String>[], 'pda_dose': ''})
        ],
        'resp_a': [
          fresh({
            'time_range': '',
            'respiratory_modes': <String>[],
            'max_map_cpap': '',
            'max_map_cpap_secondary': '',
            'max_fio2': '',
          })
        ],
        'resp_b': [fresh({'ph': '', 'pao2': '', 'paco2': ''})],
        'resp_c': [
          fresh({
            'apnea_episodes': '',
            'desaturation_episodes': '',
            'severe_desaturation_episodes': '',
          })
        ],
        'resp_d': [
          fresh({
            'postnatal_steroids': <String>[],
            'steroid_dose': '',
            'steroid_other': '',
          })
        ],
        'met_a': [fresh({'glucose': ''})],
        'met_b': [
          fresh({'alp': '', 'total_calcium': '', 'phosphorus': ''})
        ],
        'met_c': [
          fresh({
            'electrolyte_abnormality': null,
            'electrolytes': <String>[],
            'hypo_hyper': '',
            'symptomatic_status': '',
            'symptomatic_detail': '',
          })
        ],
        'gi_a': [
          fresh({'cumulative_feed_volume': ''})
        ],
        'gi_b': [fresh({'direct_bilirubin': ''})],
        'neuro_a': [
          fresh({
            'ventriculomegaly_severity': '',
            'vi': '',
            'ahw': '',
          })
        ],
        'neuro_b': [
          fresh({'tod': '', 'aca_ri': '', 'mca_ri': ''})
        ],
        'heme_a': [
          fresh({
            'transfusion_products': <String>[],
            'transfusion_count': '',
            'prbc_volume': '',
          })
        ],
      };

  static List<String> _splitList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return v
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String _listToString(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).join(',');
    return v?.toString() ?? '';
  }

  static double? _asNum(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static int? _asInt(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static Map<String, List<MmlEntry>> hydrate(Map<String, dynamic> d) {
    final raw = d['entries_json'];
    if (raw != null && raw.toString().trim().isNotEmpty) {
      try {
        final parsed = raw is String ? jsonDecode(raw) : raw;
        if (parsed is Map) {
          final base = emptyEntries();
          for (final k in base.keys) {
            final list = parsed[k];
            if (list is List && list.isNotEmpty) {
              base[k] = list
                  .whereType<Map>()
                  .map((e) =>
                      MmlEntry.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            }
          }
          mmlSanitizeFluidBolusEntries(base);
          return base;
        }
      } catch (_) {}
    }
    // Legacy flat → one entry per block
    final e = emptyEntries();
    e['cv_a']![0]
      ..date = (d['record_date'] ?? e['cv_a']![0].date).toString()
      ..['axillary_temp'] = d['axillary_temp'] ?? ''
      ..['sbp'] = d['sbp'] ?? ''
      ..['dbp'] = d['dbp'] ?? ''
      ..['map_value'] = d['map_value'] ?? '';
    e['cv_b']![0]['fluid_bolus_given'] =
        mmlNormalizeFluidBolusValue(d['fluid_bolus_given']);
    e['cv_c']![0]
      ..['vasoactive_drugs'] = _splitList(d['vasoactive_drugs'])
      ..['vasoactive_dose'] = d['vasoactive_dose'] ?? ''
      ..['vasoactive_unit'] = d['vasoactive_unit'] ?? '';
    e['cv_d']![0]
      ..['pda_agent'] = _splitList(d['pda_agent'])
      ..['pda_dose'] = d['pda_dose'] ?? '';
    e['resp_a']![0]
      ..['time_range'] = d['respiratory_time'] ?? ''
      ..['respiratory_modes'] = _splitList(d['respiratory_modes'])
      ..['max_map_cpap'] = d['max_map_cpap'] ?? ''
      ..['max_map_cpap_secondary'] = d['max_map_cpap_secondary'] ?? ''
      ..['max_fio2'] = d['max_fio2'] ?? '';
    e['resp_b']![0]
      ..['ph'] = d['ph'] ?? ''
      ..['pao2'] = d['pao2'] ?? ''
      ..['paco2'] = d['paco2'] ?? '';
    e['resp_c']![0]
      ..['apnea_episodes'] = d['apnea_episodes'] ?? ''
      ..['desaturation_episodes'] = d['desaturation_episodes'] ?? ''
      ..['severe_desaturation_episodes'] =
          d['severe_desaturation_episodes'] ?? '';
    e['resp_d']![0]
      ..['postnatal_steroids'] = _splitList(d['postnatal_steroids'])
      ..['steroid_dose'] = d['steroid_dose'] ?? ''
      ..['steroid_other'] = d['steroid_other'] ?? '';
    e['met_a']![0]['glucose'] = d['glucose'] ?? '';
    e['met_b']![0]
      ..['alp'] = d['alp'] ?? ''
      ..['total_calcium'] = d['total_calcium'] ?? ''
      ..['phosphorus'] = d['phosphorus'] ?? '';
    e['met_c']![0]
      ..['electrolyte_abnormality'] = d['electrolyte_abnormality']
      ..['electrolytes'] = _splitList(d['electrolytes'])
      ..['hypo_hyper'] = d['hypo_hyper'] ?? ''
      ..['symptomatic_status'] = d['symptomatic_status'] ?? ''
      ..['symptomatic_detail'] = d['symptomatic_detail'] ?? '';
    e['gi_a']![0]
      ..['cumulative_feed_volume'] = d['cumulative_feed_volume'] ?? '';
    e['gi_b']![0]['direct_bilirubin'] = d['direct_bilirubin'] ?? '';
    e['neuro_a']![0]
      ..date = (d['imaging_date'] ?? e['neuro_a']![0].date).toString()
      ..['ventriculomegaly_severity'] = d['ventriculomegaly_severity'] ?? ''
      ..['vi'] = d['vi'] ?? ''
      ..['ahw'] = d['ahw'] ?? '';
    e['neuro_b']![0]
      ..['tod'] = d['tod'] ?? ''
      ..['aca_ri'] = d['aca_ri'] ?? ''
      ..['mca_ri'] = d['mca_ri'] ?? '';
    e['heme_a']![0]
      ..['transfusion_products'] = _splitList(d['transfusion_products'])
      ..['transfusion_count'] = d['transfusion_count'] ?? ''
      ..['prbc_volume'] = d['prbc_volume'] ?? '';
    mmlSanitizeFluidBolusEntries(e);
    return e;
  }

  factory MinimalMonitoringSheet.fromJson(Map<String, dynamic> json) {
    final s = MinimalMonitoringSheet(
      enrollmentId: json['enrollment_id']?.toString() ?? '',
    );
    s.recordDate = json['record_date']?.toString();
    s.submissionStatus = json['submission_status']?.toString();
    s.savedAt = json['saved_at']?.toString();
    s.savedBy = json['saved_by']?.toString();
    s.entries = hydrate(json);
    return s;
  }

  MmlEntry _g(String key, [int i = 0]) {
    final list = entries[key];
    if (list == null || list.isEmpty) return fresh({});
    if (i >= list.length) return list.first;
    return list[i];
  }

  /// Flatten first entry of each block + full entries_json (web parity).
  /// Sends empty strings for clears (do not strip nulls for string fields).
  Map<String, dynamic> toJson({String? savedBy, String? sheetRecordDate}) {
    mmlSanitizeFluidBolusEntries(entries);
    final cvA = _g('cv_a');
    final cvB = _g('cv_b');
    final cvC = _g('cv_c');
    final cvD = _g('cv_d');
    final rA = _g('resp_a');
    final rB = _g('resp_b');
    final rC = _g('resp_c');
    final rD = _g('resp_d');
    final mA = _g('met_a');
    final mB = _g('met_b');
    final mC = _g('met_c');
    final giA = _g('gi_a');
    final giB = _g('gi_b');
    final nA = _g('neuro_a');
    final nB = _g('neuro_b');
    final hA = _g('heme_a');

    final entriesMap = entriesMapForPersist();

    final pdaDose = cvD['pda_dose'];
    final steroidDose = rD['steroid_dose'];

    return {
      'enrollment_id': enrollmentId,
      'record_date': sheetRecordDate ?? recordDate ?? cvA.date,
      'shift': '',
      'axillary_temp': _asNum(cvA['axillary_temp']),
      'sbp': _asNum(cvA['sbp']),
      'dbp': _asNum(cvA['dbp']),
      'map_value': _asNum(cvA['map_value']),
      'fluid_bolus_given':
          mmlNormalizeFluidBolusValue(cvB['fluid_bolus_given']),
      'vasoactive_drugs': _listToString(cvC['vasoactive_drugs']),
      'vasoactive_dose': cvC['vasoactive_dose'] ?? '',
      'vasoactive_unit': cvC['vasoactive_unit'] ?? '',
      'pda_agent': _listToString(cvD['pda_agent']),
      'pda_dose': (pdaDose == null || pdaDose.toString().trim().isEmpty)
          ? null
          : pdaDose.toString(),
      'respiratory_time': (rA['time_range']?.toString().isNotEmpty == true)
          ? rA['time_range']
          : (rA.time),
      'respiratory_modes': _listToString(rA['respiratory_modes']),
      'max_map_cpap': _asNum(rA['max_map_cpap']),
      'max_map_cpap_secondary': _asNum(rA['max_map_cpap_secondary']),
      'max_fio2': _asNum(rA['max_fio2']),
      'ph': _asNum(rB['ph']),
      'pao2': _asNum(rB['pao2']),
      'paco2': _asNum(rB['paco2']),
      'apnea_shift': '',
      'apnea_episodes': _asInt(rC['apnea_episodes']),
      'desaturation_episodes': _asInt(rC['desaturation_episodes']),
      'severe_desaturation_episodes':
          _asInt(rC['severe_desaturation_episodes']),
      'postnatal_steroids': _listToString(rD['postnatal_steroids']),
      'steroid_dose':
          (steroidDose == null || steroidDose.toString().trim().isEmpty)
              ? null
              : steroidDose.toString(),
      'steroid_other': rD['steroid_other'] ?? '',
      'glucose': _asNum(mA['glucose']),
      'alp': _asNum(mB['alp']),
      'total_calcium': _asNum(mB['total_calcium']),
      'phosphorus': _asNum(mB['phosphorus']),
      'electrolyte_abnormality': mC['electrolyte_abnormality'],
      'electrolytes': _listToString(mC['electrolytes']),
      'hypo_hyper': mC['hypo_hyper'] ?? '',
      'symptomatic_status': mC['symptomatic_status'] ?? '',
      'symptomatic_detail': mC['symptomatic_detail'] ?? '',
      'feed_shift': '',
      'cumulative_feed_volume': _asNum(giA['cumulative_feed_volume']),
      'direct_bilirubin': _asNum(giB['direct_bilirubin']),
      'imaging_date': nA.date,
      'ventriculomegaly_severity': nA['ventriculomegaly_severity'] ?? '',
      'vi': _asNum(nA['vi']),
      'ahw': _asNum(nA['ahw']),
      'tod': _asNum(nB['tod']),
      'aca_ri': _asNum(nB['aca_ri']),
      'mca_ri': _asNum(nB['mca_ri']),
      'transfusion_products': _listToString(hA['transfusion_products']),
      'transfusion_count': _asInt(hA['transfusion_count']),
      'prbc_volume': _asNum(hA['prbc_volume']),
      'entries_json': jsonEncode(entriesMap),
      'submission_status': 'draft',
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'saved_by': savedBy ?? this.savedBy ?? 'Nurse',
    };
  }

  /// Soft validation messages (same ranges as web).
  String? validate() {
    for (final e in entries['resp_a'] ?? <MmlEntry>[]) {
      final modes = _splitList(e['respiratory_modes']);
      final mapMode = RespCvNeuroValidators.mapCpapMode(modes);
      if (mapMode == 'BOTH') {
        final cpapErr = RespCvNeuroValidators.mapCpap(
          e['max_map_cpap_secondary']?.toString(),
          'CPAP',
        );
        if (cpapErr != null) return cpapErr;
        final mapErr = RespCvNeuroValidators.mapCpap(
          e['max_map_cpap']?.toString(),
          'MAP',
        );
        if (mapErr != null) return mapErr;
      } else if (mapMode != null && mapMode != 'NA') {
        final err = RespCvNeuroValidators.mapCpap(
          e['max_map_cpap']?.toString(),
          mapMode,
        );
        if (err != null) return err;
      }
      final f = _asNum(e['max_fio2']);
      if (f != null && (f < 21 || f > 100)) {
        return 'Max FiO₂ must be 21–100';
      }
    }
    final respB = entries['resp_b'] ?? <MmlEntry>[];
    for (var i = 0; i < respB.length; i++) {
      final e = respB[i];
      if (i == respB.length - 1 && !e.hasClinicalData()) continue;
      final p = _asNum(e['ph']);
      if (p != null && (p < 6.6 || p > 7.8)) {
        return 'pH is usually 6.6–7.8 — please double-check this value';
      }
      final pao2 = _asNum(e['pao2']);
      if (pao2 != null && (pao2 < 20 || pao2 > 600)) {
        return 'PaO₂ is usually 20–600 mmHg — please double-check';
      }
      final paco2 = _asNum(e['paco2']);
      if (paco2 != null && (paco2 < 15 || paco2 > 150)) {
        return 'PaCO₂ is usually 15–150 mmHg — please double-check';
      }
    }
    for (final e in entries['resp_c'] ?? <MmlEntry>[]) {
      for (final k in [
        'apnea_episodes',
        'desaturation_episodes',
        'severe_desaturation_episodes'
      ]) {
        final t = e[k]?.toString().trim() ?? '';
        if (t.isEmpty) continue;
        final n = int.tryParse(t);
        if (n == null || n < 0) {
          return 'Episode counts must be whole numbers ≥ 0';
        }
      }
      final desat = int.tryParse(
        e['desaturation_episodes']?.toString().trim() ?? '',
      );
      final severe = int.tryParse(
        e['severe_desaturation_episodes']?.toString().trim() ?? '',
      );
      if (desat != null && severe != null && severe > desat) {
        return kMmlSevereDesatExceedsMsg;
      }
    }
    for (final e in entries['resp_d'] ?? <MmlEntry>[]) {
      final steroids = (e['postnatal_steroids'] as List?) ?? const [];
      if (steroids.contains('Other') &&
          (e['steroid_other']?.toString().trim().isEmpty ?? true)) {
        return 'Specify Other steroid name';
      }
    }
    for (final e in entries['met_c'] ?? <MmlEntry>[]) {
      if (e['symptomatic_status'] == 'symptomatic' &&
          (e['symptomatic_detail']?.toString().trim().isEmpty ?? true)) {
        return 'Symptomatic detail is required';
      }
    }
    for (final e in entries['heme_a'] ?? <MmlEntry>[]) {
      final t = e['transfusion_count']?.toString().trim() ?? '';
      if (t.isNotEmpty) {
        final n = int.tryParse(t);
        if (n == null || n < 0) {
          return 'Transfusion count must be a whole number ≥ 0';
        }
      }
    }
    final maxDate = realCalendarDateYmd();
    for (final block in kMmlBlockKeys) {
      final list = entries[block] ?? <MmlEntry>[];
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (i == list.length - 1 && !e.hasClinicalData()) continue;
        if (e.date.compareTo(maxDate) > 0) {
          return 'Date cannot be in the future';
        }
        if (block == 'resp_a') {
          final raw = (e['time_range'] ?? '').toString();
          final parts = raw
              .split(RegExp(r'\s*[–—−-]\s*|\s+to\s+', caseSensitive: false))
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          for (final part in parts) {
            final hm = part.length >= 5 ? part.substring(0, 5) : part;
            if (hm.isNotEmpty && mmlIsFutureDateTime(e.date, hm)) {
              return 'Time cannot be in the future';
            }
          }
        } else if (e.time.isNotEmpty && mmlIsFutureDateTime(e.date, e.time)) {
          return 'Time cannot be in the future';
        }
      }
    }
    return null;
  }
}

/// Backward-compatible alias used by older imports.
typedef MinimalMonitoringDay = MinimalMonitoringSheet;