// Helper Form 4 — Metab / Renal / Vasc / Eye Daily Log
// Mirrors MetabRenalVascEyeLog.jsx + MetabRenalVascEyeDayCreate.

import 'dart:convert';

class MrveReading {
  String id;
  String date;
  String time;
  String value; // ph or electrolyte value

  MrveReading({
    String? id,
    this.date = '',
    this.time = '',
    this.value = '',
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, dynamic> toPhJson() =>
      {'id': id, 'date': date, 'time': time, 'ph': value};
  Map<String, dynamic> toValueJson() =>
      {'id': id, 'date': date, 'time': time, 'value': value};

  factory MrveReading.fromPh(Map<String, dynamic> j) => MrveReading(
        id: j['id']?.toString(),
        date: j['date']?.toString() ?? '',
        time: j['time']?.toString() ?? '',
        value: '${j['ph'] ?? ''}',
      );

  factory MrveReading.fromValue(Map<String, dynamic> j) => MrveReading(
        id: j['id']?.toString(),
        date: j['date']?.toString() ?? '',
        time: j['time']?.toString() ?? '',
        value: '${j['value'] ?? ''}',
      );
}

class MetabRenalVascEyeDay {
  final String enrollmentId;
  int nicuDay;

  String? lowestGlucose;
  String? hypoglycemiaEpisodes;
  bool? hypoglycemiaRx;
  String? highestGlucose;
  bool? insulin;
  bool? metabolicAcidosis;
  String? sodiumValue;
  String? potassiumValue;
  String? ionizedCalciumValue;
  bool? osteopeniaSuspected;

  List<MrveReading> phReadings = [];
  List<MrveReading> sodiumReadings = [];
  List<MrveReading> potassiumReadings = [];
  List<MrveReading> calciumReadings = [];

  bool? akiSuspected;
  // KDIGO stage removed to match web (MetabRenalVascEyeLog.jsx) — no longer
  // captured going forward. akiStageOptions kept only as a reference for
  // legacy-data migration below.
  String? creatinineValue;
  double? urineOutput8am2pm;
  double? urineOutput2pm8pm;
  double? urineOutput8pm8am;
  String? urineOutputTotal;
  bool? dialysisCrrt;

  String? axillaryTemperature;

  bool? piccInSitu;
  bool? uvcInSitu;
  bool? uacInSitu;
  bool? peripheralIv;
  bool? peripheralArterial;
  bool? extravasationInjury;
  bool? lineComplication;

  bool? ropScreeningDue;
  bool? ropScreened;
  bool? ropDetected;
  String? ropStage;
  bool? plusDisease;
  bool? ropTreatment;

  // Multi-select to match web (PillMulti in MetabRenalVascEyeLog.jsx);
  // wire format is a comma-joined string, same as feedType elsewhere.
  List<String> location = [];
  bool? survivedTheDay;

  String? submissionStatus;
  String? savedAt;
  String? savedBy;

  MetabRenalVascEyeDay({required this.enrollmentId, required this.nicuDay});

  // Legacy KDIGO values recognized only for migrating old rows above.
  static const ropStageOptions = [
    'Stage 1',
    'Stage 2',
    'Stage 3',
    'Stage 4',
    'Stage 5'
  ];
  static const locationOptions = [
    'DR',
    'NICU',
    'Step-down/Nursery',
    'KMC-N',
    'Other'
  ];

  static List<String> _splitCsv(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return v
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == 'yes' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == '0') return false;
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static List<MrveReading> _parsePh(dynamic raw) {
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => MrveReading.fromPh(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<MrveReading> _parseVal(dynamic raw) {
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => MrveReading.fromValue(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String? latestValue(List<MrveReading> readings) {
    for (var i = readings.length - 1; i >= 0; i--) {
      final v = readings[i].value.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static bool? deriveAcidosis(List<MrveReading> readings) {
    var any = false;
    var low = false;
    for (final r in readings) {
      final n = double.tryParse(r.value.trim());
      if (n == null) continue;
      any = true;
      if (n < 7.2) low = true;
    }
    if (!any) return null;
    return low;
  }

  static String? sumUrine(double? a, double? b, double? c) {
    var sum = 0.0;
    var any = false;
    for (final v in [a, b, c]) {
      if (v == null) continue;
      any = true;
      sum += v;
    }
    if (!any) return null;
    final s = sum.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static bool isNumericHighGlucose(String? v) {
    if (v == null) return false;
    final s = v.trim();
    if (s.isEmpty ||
        s.toLowerCase() == 'not high' ||
        s.toLowerCase() == 'not tested' ||
        s.toLowerCase() == 'not low') {
      return false;
    }
    final n = double.tryParse(s);
    return n != null && n > 180;
  }

  factory MetabRenalVascEyeDay.fromJson(Map<String, dynamic> json) {
    final d = MetabRenalVascEyeDay(
      enrollmentId: (json['enrollment_id'] ?? '').toString(),
      nicuDay: json['nicu_day'] is int
          ? json['nicu_day'] as int
          : int.tryParse('${json['nicu_day']}') ?? 1,
    );
    d.lowestGlucose = json['lowest_glucose']?.toString();
    d.hypoglycemiaEpisodes = json['hypoglycemia_episodes']?.toString();
    d.hypoglycemiaRx = _asBool(json['hypoglycemia_rx']);
    d.highestGlucose = json['highest_glucose']?.toString();
    d.insulin = _asBool(json['insulin']);
    d.metabolicAcidosis = _asBool(json['metabolic_acidosis']);
    d.sodiumValue = json['sodium_value']?.toString();
    d.potassiumValue = json['potassium_value']?.toString();
    d.ionizedCalciumValue = json['ionized_calcium_value']?.toString();
    d.osteopeniaSuspected = _asBool(json['osteopenia_suspected']);
    d.phReadings = _parsePh(json['ph_readings_json']);
    d.sodiumReadings = _parseVal(json['sodium_readings_json']);
    d.potassiumReadings = _parseVal(json['potassium_readings_json']);
    d.calciumReadings = _parseVal(json['calcium_readings_json']);
    d.akiSuspected = _asBool(json['aki_suspected']);
    // KDIGO stage is no longer captured on this form (removed, matches web
    // migrateAkiFromLegacy) — this only derives aki_suspected, including
    // from older rows that pre-date the aki_suspected/aki_stage split and
    // only had a combined "N"/"Stage X" legacy value.
    final legacyAki =
        json['aki_kdigo_stage']?.toString() ?? json['aki_stage']?.toString();
    if (d.akiSuspected == null && legacyAki != null && legacyAki.isNotEmpty) {
      if (legacyAki == 'N' || legacyAki.toLowerCase() == 'no') {
        d.akiSuspected = false;
      } else if (legacyAki.startsWith('Stage')) {
        d.akiSuspected = true;
      }
    }
    d.creatinineValue = json['creatinine_value']?.toString();
    if (d.creatinineValue == null || d.creatinineValue!.trim().isEmpty) {
      final legacyCreat = json['creatinine'];
      if (legacyCreat != null && legacyCreat.toString().trim().isNotEmpty) {
        d.creatinineValue = legacyCreat.toString();
      }
    }
    d.urineOutput8am2pm = _asDouble(json['urine_output_8am_2pm']);
    d.urineOutput2pm8pm = _asDouble(json['urine_output_2pm_8pm']);
    d.urineOutput8pm8am = _asDouble(json['urine_output_8pm_8am']);
    d.urineOutputTotal = json['urine_output_total']?.toString();
    d.dialysisCrrt = _asBool(json['dialysis_crrt']);
    d.axillaryTemperature = json['axillary_temperature']?.toString();
    d.piccInSitu = _asBool(json['picc_in_situ']);
    d.uvcInSitu = _asBool(json['uvc_in_situ']);
    d.uacInSitu = _asBool(json['uac_in_situ']);
    d.peripheralIv = _asBool(json['peripheral_iv']);
    d.peripheralArterial = _asBool(json['peripheral_arterial']);
    d.extravasationInjury = _asBool(json['extravasation_injury']);
    d.lineComplication = _asBool(json['line_complication']);
    d.ropScreeningDue = _asBool(json['rop_screening_due']);
    d.ropScreened = _asBool(json['rop_screened']);
    d.ropDetected = _asBool(json['rop_detected']);
    d.ropStage = json['rop_stage']?.toString();
    d.plusDisease = _asBool(json['plus_disease']);
    d.ropTreatment = _asBool(json['rop_treatment']);
    d.location = _splitCsv(json['location']);
    d.survivedTheDay = _asBool(json['survived_the_day']);
    d.submissionStatus = json['submission_status']?.toString();
    d.savedAt = json['saved_at']?.toString();
    d.savedBy = json['saved_by']?.toString();
    return d;
  }

  /// Recompute summaries from reading lists.
  /// Acidosis: prefer derived value when any finite pH exists; if the list is
  /// empty keep the stored flag (legacy rows); if list has blank rows only → null.
  void recomputeDerived() {
    final derived = deriveAcidosis(phReadings);
    if (derived != null) {
      metabolicAcidosis = derived;
    } else if (phReadings.isNotEmpty) {
      metabolicAcidosis = null;
    }
    // Electrolyte summaries follow latest reading (null if list empty/blank)
    sodiumValue = latestValue(sodiumReadings);
    potassiumValue = latestValue(potassiumReadings);
    ionizedCalciumValue = latestValue(calciumReadings);
    urineOutputTotal =
        sumUrine(urineOutput8am2pm, urineOutput2pm8pm, urineOutput8pm8am);
  }

  void copyClinicalFrom(MetabRenalVascEyeDay src) {
    lowestGlucose = src.lowestGlucose;
    hypoglycemiaEpisodes = src.hypoglycemiaEpisodes;
    hypoglycemiaRx = src.hypoglycemiaRx;
    highestGlucose = src.highestGlucose;
    insulin = src.insulin;
    metabolicAcidosis = src.metabolicAcidosis;
    sodiumValue = src.sodiumValue;
    potassiumValue = src.potassiumValue;
    ionizedCalciumValue = src.ionizedCalciumValue;
    osteopeniaSuspected = src.osteopeniaSuspected;
    // Fresh ids so reading-row TextEditingControllers remount/sync after copy.
    phReadings = src.phReadings
        .map((r) =>
            MrveReading(date: r.date, time: r.time, value: r.value))
        .toList();
    sodiumReadings = src.sodiumReadings
        .map((r) =>
            MrveReading(date: r.date, time: r.time, value: r.value))
        .toList();
    potassiumReadings = src.potassiumReadings
        .map((r) =>
            MrveReading(date: r.date, time: r.time, value: r.value))
        .toList();
    calciumReadings = src.calciumReadings
        .map((r) =>
            MrveReading(date: r.date, time: r.time, value: r.value))
        .toList();
    akiSuspected = src.akiSuspected;
    creatinineValue = src.creatinineValue;
    urineOutput8am2pm = src.urineOutput8am2pm;
    urineOutput2pm8pm = src.urineOutput2pm8pm;
    urineOutput8pm8am = src.urineOutput8pm8am;
    urineOutputTotal = src.urineOutputTotal;
    dialysisCrrt = src.dialysisCrrt;
    axillaryTemperature = src.axillaryTemperature;
    piccInSitu = src.piccInSitu;
    uvcInSitu = src.uvcInSitu;
    uacInSitu = src.uacInSitu;
    peripheralIv = src.peripheralIv;
    peripheralArterial = src.peripheralArterial;
    extravasationInjury = src.extravasationInjury;
    lineComplication = src.lineComplication;
    ropScreeningDue = src.ropScreeningDue;
    ropScreened = src.ropScreened;
    ropDetected = src.ropDetected;
    ropStage = src.ropStage;
    plusDisease = src.plusDisease;
    ropTreatment = src.ropTreatment;
    location = List.of(src.location);
    survivedTheDay = src.survivedTheDay;
  }

  Map<String, dynamic> toJson({
    required String submissionStatus,
    String? savedAt,
    String? savedBy,
  }) {
    recomputeDerived();
    final creatNum = double.tryParse(creatinineValue?.trim() ?? '');
    return {
      'enrollment_id': enrollmentId,
      'nicu_day': nicuDay,
      'lowest_glucose': lowestGlucose,
      'hypoglycemia_episodes': hypoglycemiaEpisodes,
      'hypoglycemia_rx': hypoglycemiaRx,
      'highest_glucose': highestGlucose,
      'insulin': insulin,
      'metabolic_acidosis': metabolicAcidosis,
      'sodium_value': sodiumValue,
      'potassium_value': potassiumValue,
      'ionized_calcium_value': ionizedCalciumValue,
      'osteopenia_suspected': osteopeniaSuspected,
      'ph_readings_json':
          jsonEncode(phReadings.map((r) => r.toPhJson()).toList()),
      'sodium_readings_json':
          jsonEncode(sodiumReadings.map((r) => r.toValueJson()).toList()),
      'potassium_readings_json':
          jsonEncode(potassiumReadings.map((r) => r.toValueJson()).toList()),
      'calcium_readings_json':
          jsonEncode(calciumReadings.map((r) => r.toValueJson()).toList()),
      'aki_suspected': akiSuspected,
      'creatinine_value': creatinineValue,
      'creatinine': creatNum,
      'urine_output_8am_2pm': urineOutput8am2pm,
      'urine_output_2pm_8pm': urineOutput2pm8pm,
      'urine_output_8pm_8am': urineOutput8pm8am,
      'urine_output_total': urineOutputTotal,
      'dialysis_crrt': dialysisCrrt,
      'axillary_temperature': axillaryTemperature,
      'picc_in_situ': piccInSitu,
      'uvc_in_situ': uvcInSitu,
      'uac_in_situ': uacInSitu,
      'peripheral_iv': peripheralIv,
      'peripheral_arterial': peripheralArterial,
      'extravasation_injury': extravasationInjury,
      'line_complication': lineComplication,
      'rop_screening_due': ropScreeningDue,
      'rop_screened': ropScreened,
      'rop_detected': ropDetected,
      'rop_stage': ropStage,
      'plus_disease': plusDisease,
      'rop_treatment': ropTreatment,
      'location': location.isEmpty ? null : location.join(','),
      'survived_the_day': survivedTheDay,
      'submission_status': submissionStatus,
      'saved_at': savedAt,
      'saved_by': savedBy,
    };
  }
}

class MetabRenalVascEyeCompletion {
  final int answered;
  final int total;
  int get percent =>
      total > 0 ? ((answered / total) * 100).round().clamp(0, 100) : 0;

  const MetabRenalVascEyeCompletion(this.answered, this.total);

  static bool _ans(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true; // bool false counts as answered
  }

  static MetabRenalVascEyeCompletion compute(MetabRenalVascEyeDay d) {
    final ep = double.tryParse(d.hypoglycemiaEpisodes?.trim() ?? '') ?? 0;
    final urineAnswered = d.urineOutput8am2pm != null ||
        d.urineOutput2pm8pm != null ||
        d.urineOutput8pm8am != null ||
        (d.urineOutputTotal?.trim().isNotEmpty ?? false);

    final list = <bool>[
      _ans(d.lowestGlucose),
      _ans(d.hypoglycemiaEpisodes),
      if (ep > 0) _ans(d.hypoglycemiaRx),
      _ans(d.highestGlucose),
      if (MetabRenalVascEyeDay.isNumericHighGlucose(d.highestGlucose))
        _ans(d.insulin),
      _ans(d.metabolicAcidosis),
      _ans(d.sodiumValue),
      _ans(d.potassiumValue),
      _ans(d.ionizedCalciumValue),
      _ans(d.osteopeniaSuspected),
      _ans(d.akiSuspected),
      _ans(d.creatinineValue),
      urineAnswered,
      _ans(d.dialysisCrrt),
      _ans(d.axillaryTemperature),
      _ans(d.piccInSitu),
      _ans(d.uvcInSitu),
      _ans(d.uacInSitu),
      _ans(d.peripheralIv),
      _ans(d.peripheralArterial),
      if (d.peripheralIv == true || d.peripheralArterial == true)
        _ans(d.extravasationInjury),
      _ans(d.lineComplication),
      _ans(d.ropScreeningDue),
      if (d.ropScreeningDue == true) _ans(d.ropScreened),
      if (d.ropScreeningDue == true && d.ropScreened == true)
        _ans(d.ropDetected),
      _ans(d.location),
      _ans(d.survivedTheDay),
    ];
    return MetabRenalVascEyeCompletion(
        list.where((e) => e).length, list.length);
  }
}