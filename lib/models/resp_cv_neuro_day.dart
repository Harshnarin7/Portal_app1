// lib/models/resp_cv_neuro_day.dart
//
// Helper Form 2 — Resp / CV / Neuro Daily Log.
// Mirrors web RespCVNeuroLog.jsx + backend RespCVNeuroDayCreate 1:1.
// Numbering: 2.1 Weight, then 1–37 (same as web).

class RespCvNeuroDay {
  final String enrollmentId;
  int nicuDay;

  // 2.1
  String? weightKg;

  // Respiratory 1–22
  bool? respiratorySupport;
  bool? endotrachealIntubation;
  List<String> supportModes = [];
  double? mapCpap;
  double? mapCpapSecondary;
  double? maxFio2;
  double? maxFlow;
  bool? suppO2;
  String? lowestPh;
  String? pao2Range; // "low-high" | "Not Done"
  String? paco2Range;
  bool? surfactant;
  bool? caffeine;
  String? apneaCount;
  String? desaturationCount;
  String? severeDesaturationCount;
  bool? extubAttempted;
  bool? extubFailure;
  bool? pulmHemorrhage;
  bool? pneumothorax;
  bool? chestDrain;
  bool? pphn;
  bool? postnatalSteroids;

  // Cardiovascular 23–29
  bool? pdaSuspected;
  bool? echoDone;
  bool? hsPda;
  bool? shock;
  bool? vasoactiveSupport;
  List<String> vasoactiveDrugs = [];
  String? fluidBolus;

  // Neurological 30–37
  bool? cranialUsg;
  bool? ivh;
  String? ivhGrade; // I | II | III | IV
  bool? cpvlConfirmed;
  bool? ventriculomegaly;
  bool? clinicalSeizures;
  bool? eegSeizures;
  bool? aedsGiven;
  bool? nonIvhIch;

  String? submissionStatus; // empty | draft | submitted | late
  String? savedAt;
  String? savedBy;
  String? submittedAt;
  String? submittedBy;

  RespCvNeuroDay({
    required this.enrollmentId,
    required this.nicuDay,
  });

  static const supportModeOptions = [
    'NC',
    'HFNC',
    'CPAP',
    'NIPPV',
    'SIMV',
    'AC',
    'PSV',
    'HFOV',
  ];

  static const vasoactiveDrugOptions = [
    'Dopamine',
    'Dobutamine',
    'Adrenaline',
    'Noradrenaline',
    'Milrinone',
    'Vasopressin',
  ];

  static const ivhGradeOptions = ['I', 'II', 'III', 'IV'];

  static List<String> _splitCsv(dynamic v) {
    if (v == null) return [];
    final s = v.toString().trim();
    if (s.isEmpty) return [];
    return s
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

  factory RespCvNeuroDay.fromJson(Map<String, dynamic> json) {
    final d = RespCvNeuroDay(
      enrollmentId: (json['enrollment_id'] ?? '').toString(),
      nicuDay: (json['nicu_day'] is int)
          ? json['nicu_day'] as int
          : int.tryParse('${json['nicu_day']}') ?? 1,
    );
    d.weightKg = json['weight_kg']?.toString();
    d.respiratorySupport = _asBool(json['respiratory_support']);
    d.endotrachealIntubation = _asBool(json['endotracheal_intubation']);
    d.supportModes = _splitCsv(json['support_modes']);
    d.mapCpap = _asDouble(json['map_cpap']);
    d.mapCpapSecondary = _asDouble(json['map_cpap_secondary']);
    d.maxFio2 = _asDouble(json['max_fio2']);
    d.maxFlow = _asDouble(json['max_flow']);
    d.suppO2 = _asBool(json['supp_o2']);
    d.lowestPh = json['lowest_ph']?.toString();
    d.pao2Range = json['pao2_range']?.toString();
    d.paco2Range = json['paco2_range']?.toString();
    d.surfactant = _asBool(json['surfactant']);
    d.caffeine = _asBool(json['caffeine']);
    d.apneaCount = json['apnea_count']?.toString();
    d.desaturationCount = json['desaturation_count']?.toString();
    d.severeDesaturationCount = json['severe_desaturation_count']?.toString();
    d.extubAttempted = _asBool(json['extub_attempted']);
    d.extubFailure = _asBool(json['extub_failure']);
    d.pulmHemorrhage = _asBool(json['pulm_hemorrhage']);
    d.pneumothorax = _asBool(json['pneumothorax']);
    d.chestDrain = _asBool(json['chest_drain']);
    d.pphn = _asBool(json['pphn']);
    d.postnatalSteroids = _asBool(json['postnatal_steroids']);
    d.pdaSuspected = _asBool(json['pda_suspected']);
    d.echoDone = _asBool(json['echo_done']);
    d.hsPda = _asBool(json['hs_pda']);
    d.shock = _asBool(json['shock']);
    d.vasoactiveSupport = _asBool(json['vasoactive_support']);
    d.vasoactiveDrugs = _splitCsv(json['vasoactive_drugs']);
    d.fluidBolus = json['fluid_bolus']?.toString();
    d.cranialUsg = _asBool(json['cranial_usg']);
    d.ivh = _asBool(json['ivh']);
    d.ivhGrade = json['ivh_grade']?.toString();
    d.cpvlConfirmed = _asBool(json['cpvl_confirmed']);
    d.ventriculomegaly = _asBool(json['ventriculomegaly']);
    d.clinicalSeizures = _asBool(json['clinical_seizures']);
    d.eegSeizures = _asBool(json['eeg_seizures']);
    d.aedsGiven = _asBool(json['aeds_given']);
    d.nonIvhIch = _asBool(json['non_ivh_ich']);
    d.submissionStatus = json['submission_status']?.toString();
    d.savedAt = json['saved_at']?.toString();
    d.savedBy = json['saved_by']?.toString();
    d.submittedAt = json['submitted_at']?.toString();
    d.submittedBy = json['submitted_by']?.toString();
    return d;
  }

  /// Clinical fields only (for copy-from-previous-day).
  void copyClinicalFrom(RespCvNeuroDay src) {
    weightKg = src.weightKg;
    respiratorySupport = src.respiratorySupport;
    endotrachealIntubation = src.endotrachealIntubation;
    supportModes = List.of(src.supportModes);
    mapCpap = src.mapCpap;
    mapCpapSecondary = src.mapCpapSecondary;
    maxFio2 = src.maxFio2;
    maxFlow = src.maxFlow;
    suppO2 = src.suppO2;
    lowestPh = src.lowestPh;
    pao2Range = src.pao2Range;
    paco2Range = src.paco2Range;
    surfactant = src.surfactant;
    caffeine = src.caffeine;
    apneaCount = src.apneaCount;
    desaturationCount = src.desaturationCount;
    severeDesaturationCount = src.severeDesaturationCount;
    extubAttempted = src.extubAttempted;
    extubFailure = src.extubFailure;
    pulmHemorrhage = src.pulmHemorrhage;
    pneumothorax = src.pneumothorax;
    chestDrain = src.chestDrain;
    pphn = src.pphn;
    postnatalSteroids = src.postnatalSteroids;
    pdaSuspected = src.pdaSuspected;
    echoDone = src.echoDone;
    hsPda = src.hsPda;
    shock = src.shock;
    vasoactiveSupport = src.vasoactiveSupport;
    vasoactiveDrugs = List.of(src.vasoactiveDrugs);
    fluidBolus = src.fluidBolus;
    cranialUsg = src.cranialUsg;
    ivh = src.ivh;
    ivhGrade = src.ivhGrade;
    cpvlConfirmed = src.cpvlConfirmed;
    ventriculomegaly = src.ventriculomegaly;
    clinicalSeizures = src.clinicalSeizures;
    eegSeizures = src.eegSeizures;
    aedsGiven = src.aedsGiven;
    nonIvhIch = src.nonIvhIch;
  }

  void clearClinical() {
    weightKg = null;
    respiratorySupport = null;
    endotrachealIntubation = null;
    supportModes = [];
    mapCpap = null;
    mapCpapSecondary = null;
    maxFio2 = null;
    maxFlow = null;
    suppO2 = null;
    lowestPh = null;
    pao2Range = null;
    paco2Range = null;
    surfactant = null;
    caffeine = null;
    apneaCount = null;
    desaturationCount = null;
    severeDesaturationCount = null;
    extubAttempted = null;
    extubFailure = null;
    pulmHemorrhage = null;
    pneumothorax = null;
    chestDrain = null;
    pphn = null;
    postnatalSteroids = null;
    pdaSuspected = null;
    echoDone = null;
    hsPda = null;
    shock = null;
    vasoactiveSupport = null;
    vasoactiveDrugs = [];
    fluidBolus = null;
    cranialUsg = null;
    ivh = null;
    ivhGrade = null;
    cpvlConfirmed = null;
    ventriculomegaly = null;
    clinicalSeizures = null;
    eegSeizures = null;
    aedsGiven = null;
    nonIvhIch = null;
  }

  Map<String, dynamic> toJson({
    required String submissionStatus,
    String? savedAt,
    String? savedBy,
  }) {
    return {
      'enrollment_id': enrollmentId,
      'nicu_day': nicuDay,
      'weight_kg': (weightKg?.trim().isEmpty ?? true) ? null : weightKg!.trim(),
      'respiratory_support': respiratorySupport,
      'endotracheal_intubation': endotrachealIntubation,
      'support_modes':
          supportModes.isEmpty ? null : supportModes.join(', '),
      'map_cpap': mapCpap,
      'map_cpap_secondary': mapCpapSecondary,
      'max_fio2': maxFio2,
      'max_flow': maxFlow,
      'supp_o2': suppO2,
      'lowest_ph':
          (lowestPh?.trim().isEmpty ?? true) ? null : lowestPh!.trim(),
      'pao2_range':
          (pao2Range?.trim().isEmpty ?? true) ? null : pao2Range!.trim(),
      'paco2_range':
          (paco2Range?.trim().isEmpty ?? true) ? null : paco2Range!.trim(),
      'surfactant': surfactant,
      'caffeine': caffeine,
      'apnea_count':
          (apneaCount?.trim().isEmpty ?? true) ? null : apneaCount!.trim(),
      'desaturation_count': (desaturationCount?.trim().isEmpty ?? true)
          ? null
          : desaturationCount!.trim(),
      'severe_desaturation_count':
          (severeDesaturationCount?.trim().isEmpty ?? true)
              ? null
              : severeDesaturationCount!.trim(),
      'extub_attempted': extubAttempted,
      'extub_failure': extubFailure,
      'pulm_hemorrhage': pulmHemorrhage,
      'pneumothorax': pneumothorax,
      'chest_drain': chestDrain,
      'pphn': pphn,
      'postnatal_steroids': postnatalSteroids,
      'pda_suspected': pdaSuspected,
      'echo_done': echoDone,
      'hs_pda': hsPda,
      'shock': shock,
      'vasoactive_support': vasoactiveSupport,
      'vasoactive_drugs':
          vasoactiveDrugs.isEmpty ? null : vasoactiveDrugs.join(', '),
      'fluid_bolus':
          (fluidBolus?.trim().isEmpty ?? true) ? null : fluidBolus!.trim(),
      'cranial_usg': cranialUsg,
      'ivh': ivh,
      'ivh_grade':
          (ivhGrade?.trim().isEmpty ?? true) ? null : ivhGrade!.trim(),
      'cpvl_confirmed': cpvlConfirmed,
      'ventriculomegaly': ventriculomegaly,
      'clinical_seizures': clinicalSeizures,
      'eeg_seizures': eegSeizures,
      'aeds_given': aedsGiven,
      'non_ivh_ich': nonIvhIch,
      'submission_status': submissionStatus,
      'saved_at': savedAt,
      'saved_by': savedBy,
    };
  }
}

// ── Validations (same messages / ranges as RespCVNeuroLog.jsx) ─────────────

class RespCvNeuroValidators {
  static String? weightEntries(String? str) {
    if (str == null || str.trim().isEmpty) return null;
    final entries =
        str.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    for (final entry in entries) {
      final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(g|kg)?$', caseSensitive: false)
          .firstMatch(entry);
      if (m == null) {
        return '"$entry" isn\'t a valid weight — use e.g. 1250g or 1.25kg';
      }
      final num = double.parse(m.group(1)!);
      final unit = (m.group(2) ?? 'g').toLowerCase();
      if (unit == 'kg') {
        if (num < 0.2 || num > 8) {
          return '"$entry" is outside the expected 0.2–8 kg range';
        }
      } else if (num < 200 || num > 8000) {
        return '"$entry" is outside the expected 200–8000 g range';
      }
    }
    return null;
  }

  /// NC/HFNC → NA; CPAP only → CPAP; pressure → MAP; both → BOTH
  static String? mapCpapMode(List<String> modes) {
    if (modes.isEmpty) return null;
    const pressure = ['NIPPV', 'SIMV', 'AC', 'PSV', 'HFOV'];
    final hasPressure = modes.any(pressure.contains);
    final hasCpap = modes.contains('CPAP');
    if (hasPressure && hasCpap) return 'BOTH';
    if (hasPressure) return 'MAP';
    if (hasCpap) return 'CPAP';
    if (modes.any((m) => m == 'NC' || m == 'HFNC')) return 'NA';
    return null;
  }

  static String? mapCpap(String? value, String? mode) {
    if (value == null || value.trim().isEmpty) return null;
    final num = double.tryParse(value.trim());
    if (num == null) return 'Enter a valid number';
    if (num < 0) return "Value can't be negative";
    if (mode == 'CPAP') {
      if (num < 3 || num > 12) {
        return 'CPAP is usually 3–12 cmH₂O — please double-check this value';
      }
    } else if (mode == 'MAP') {
      if (num < 4 || num > 30) {
        return 'MAP is usually 4–30 cmH₂O — please double-check this value';
      }
    } else if (num > 40) {
      return 'This value looks too high for MAP/CPAP — please double-check';
    }
    return null;
  }

  static String? maxFio2(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final num = double.tryParse(value.trim());
    if (num == null) return 'Enter a valid number';
    if (num < 21) return "Max FiO₂ can't be below 21% (room air)";
    if (num > 100) return "Max FiO₂ can't be above 100%";
    return null;
  }

  static String? maxFlow(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final num = double.tryParse(value.trim());
    if (num == null) return 'Enter a valid number';
    if (num < 0) return "Value can't be negative";
    if (num > 30) {
      return 'Max Gas Flow is usually 0–30 L/min — please double-check this value';
    }
    return null;
  }

  static String? ph(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final num = double.tryParse(value.trim());
    if (num == null) return 'Enter a valid number';
    if (num < 6.6 || num > 7.8) {
      return 'pH is usually 6.6–7.8 — please double-check this value';
    }
    return null;
  }

  static String? bloodGasValue(String? value,
      {required double min, required double max, required String label}) {
    if (value == null || value.trim().isEmpty) return null;
    final num = double.tryParse(value.trim());
    if (num == null) return 'Enter a valid number';
    if (num < min || num > max) {
      return '$label is usually ${min.toInt()}–${max.toInt()} mmHg — please double-check';
    }
    return null;
  }

  static String? rangeOrder(String? low, String? high) {
    if (low == null ||
        high == null ||
        low.trim().isEmpty ||
        high.trim().isEmpty) {
      return null;
    }
    final lo = double.tryParse(low.trim());
    final hi = double.tryParse(high.trim());
    if (lo == null || hi == null) return null;
    if (lo > hi) return "Lowest value can't be greater than highest";
    return null;
  }

  static String? count(String? value, {int max = 50, String? label}) {
    if (value == null || value.trim().isEmpty) return null;
    final n = double.tryParse(value.trim());
    if (n == null) return 'Enter a valid number';
    if (n != n.roundToDouble()) return 'Enter a whole number';
    if (n < 0) return "Value can't be negative";
    if (n > max) {
      return '${label != null ? '$label ' : ''}seems unusually high — please double-check';
    }
    return null;
  }

  static String? fluidBolus(String? str) {
    if (str == null || str.trim().isEmpty) return null;
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*m[Ll]\s*/\s*kg\b')
        .firstMatch(str.trim());
    if (m == null) return 'Use the format "Xml/kg" — e.g. 10ml/kg NS';
    final num = double.parse(m.group(1)!);
    if (num <= 0) return 'Bolus volume must be greater than 0';
    if (num > 30) {
      return 'Fluid bolus is usually 5–30ml/kg — please double-check this value';
    }
    return null;
  }

  static ({String low, String high, bool notDone}) parseRange(String? str) {
    if (str == null || str.trim().isEmpty) {
      return (low: '', high: '', notDone: false);
    }
    if (str.trim().toLowerCase() == 'not done') {
      return (low: '', high: '', notDone: true);
    }
    final parts = str.split('-').map((s) => s.trim()).toList();
    if (parts.length == 2) {
      return (low: parts[0], high: parts[1], notDone: false);
    }
    return (low: str.trim(), high: '', notDone: false);
  }

  static String? combineRange(String low, String high, bool notDone) {
    if (notDone) return 'Not Done';
    if (low.trim().isEmpty && high.trim().isEmpty) return null;
    return '${low.trim()}-${high.trim()}';
  }
}

/// Frontend completion rules from RespCVNeuroLog.jsx (gates Submit at 100%).
class RespCvNeuroCompletion {
  final int answered;
  final int total;
  int get percent =>
      total > 0 ? ((answered / total) * 100).round().clamp(0, 100) : 0;

  const RespCvNeuroCompletion(this.answered, this.total);

  static RespCvNeuroCompletion compute({
    required String weightKg,
    required bool? respiratorySupport,
    required bool? endotrachealIntubation,
    required List<String> supportModes,
    required String mapCpap,
    required String mapCpapSecondary,
    required String maxFio2,
    required String maxFlow,
    required bool? suppO2,
    required String lowestPh,
    required bool pao2NotDone,
    required String pao2Low,
    required String pao2High,
    required bool paco2NotDone,
    required String paco2Low,
    required String paco2High,
    required bool? surfactant,
    required bool? caffeine,
    required String apneaCount,
    required String desatCount,
    required String severeDesatCount,
    required bool? extubAttempted,
    required bool? extubFailure,
    required bool? pulmHemorrhage,
    required bool? pneumothorax,
    required bool? chestDrain,
    required bool? pphn,
    required bool? postnatalSteroids,
    required bool? pdaSuspected,
    required bool? echoDone,
    required bool? hsPda,
    required bool? shock,
    required bool? vasoactiveSupport,
    required List<String> vasoactiveDrugs,
    required String fluidBolus,
    required bool? cranialUsg,
    required bool? ivh,
    required String? ivhGrade,
    required bool? cpvlConfirmed,
    required bool? ventriculomegaly,
    required bool? clinicalSeizures,
    required bool? eegSeizures,
    required bool? aedsGiven,
    required bool? nonIvhIch,
  }) {
    final mapMode = RespCvNeuroValidators.mapCpapMode(supportModes);
    final isBoth = mapMode == 'BOTH';
    final isNa = mapMode == 'NA';
    final supportNo = respiratorySupport == false;

    final respEvents = [
      surfactant,
      caffeine,
      extubAttempted,
      pulmHemorrhage,
      pneumothorax,
      chestDrain,
      pphn,
      postnatalSteroids,
    ];
    final respEventsAnswered = respEvents.where((v) => v != null).length;

    final respTotal = 23 + (isBoth ? 1 : 0);
    var respAnswered = (weightKg.trim().isNotEmpty ? 1 : 0) +
        (respiratorySupport != null ? 1 : 0) +
        (endotrachealIntubation != null ? 1 : 0) +
        ((supportNo || supportModes.isNotEmpty) ? 1 : 0) +
        ((supportNo || isNa || mapCpap.trim().isNotEmpty) ? 1 : 0) +
        (isBoth && mapCpapSecondary.trim().isNotEmpty ? 1 : 0) +
        ((supportNo || maxFio2.trim().isNotEmpty) ? 1 : 0) +
        ((supportNo || maxFlow.trim().isNotEmpty) ? 1 : 0) +
        ((supportNo || suppO2 != null) ? 1 : 0) +
        (lowestPh.trim().isNotEmpty ? 1 : 0) +
        ((pao2NotDone ||
                (pao2Low.trim().isNotEmpty && pao2High.trim().isNotEmpty))
            ? 1
            : 0) +
        ((paco2NotDone ||
                (paco2Low.trim().isNotEmpty && paco2High.trim().isNotEmpty))
            ? 1
            : 0) +
        (apneaCount.trim().isNotEmpty ? 1 : 0) +
        (desatCount.trim().isNotEmpty ? 1 : 0) +
        (severeDesatCount.trim().isNotEmpty ? 1 : 0) +
        ((extubAttempted != true || extubFailure != null) ? 1 : 0) +
        respEventsAnswered;
    if (respAnswered > respTotal) respAnswered = respTotal;

    final vasoVisible = vasoactiveSupport == true;
    final cvTotal = vasoVisible ? 7 : 6;
    final cvKeys = [pdaSuspected, echoDone, hsPda, shock, vasoactiveSupport];
    var cvAnswered = cvKeys.where((v) => v != null).length +
        (fluidBolus.trim().isNotEmpty ? 1 : 0) +
        (vasoVisible && vasoactiveDrugs.isNotEmpty ? 1 : 0);
    if (cvAnswered > cvTotal) cvAnswered = cvTotal;

    final cranialYes = cranialUsg == true;
    final ivhGradeVisible = cranialYes && ivh == true;
    final neuroTotal = 5 + (cranialYes ? 3 : 0) + (ivhGradeVisible ? 1 : 0);
    final neuroBase = [
      cranialUsg,
      clinicalSeizures,
      eegSeizures,
      aedsGiven,
      nonIvhIch,
    ];
    final neuroUsg = [ivh, cpvlConfirmed, ventriculomegaly];
    var neuroAnswered = neuroBase.where((v) => v != null).length +
        (cranialYes ? neuroUsg.where((v) => v != null).length : 0) +
        (ivhGradeVisible && (ivhGrade?.isNotEmpty ?? false) ? 1 : 0);
    if (neuroAnswered > neuroTotal) neuroAnswered = neuroTotal;

    return RespCvNeuroCompletion(
      respAnswered + cvAnswered + neuroAnswered,
      respTotal + cvTotal + neuroTotal,
    );
  }
}
