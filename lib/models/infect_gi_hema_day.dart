// Helper Form 3 — Infection / GI / Hematology Daily Log
// Mirrors InfectGIHemaLog.jsx + InfectGIHemaDayCreate (fields 1–30).

class InfectGiHemaDay {
  final String enrollmentId;
  int nicuDay;

  // Infection 1–9
  bool? sepsisSuspected;
  bool? bloodCultureSent;
  bool? bloodCulturePositive;
  bool? antibiotics;
  bool? lpDone;
  bool? meningitis;
  String? meningitisType; // Probable | Proven
  bool? clabsi;
  bool? vap;

  // GI 10–22
  bool? npo;
  bool? men;
  bool? enteralFeedsReceived;
  List<String> feedType = [];
  double? cumulativeFeedVolume;
  double? feedVolume;
  bool? ivFluids;
  bool? parenteralNutrition;
  bool? probiotic;
  bool? feedIntolerance;
  bool? necSuspected;
  String? necConfirmedStage; // modified Bell's staging: IA | IB | IIA | IIB | IIIA | IIIB
  bool? cholestasis;

  // Hema 23–30
  double? hbValue;
  bool? jaundice;
  bool? phototherapy;
  double? peakTsb;
  bool? exchangeTransfusion;
  bool? prbcTransfusion;
  bool? plateletTransfusion;
  bool? ffpCryo;

  String? submissionStatus;
  String? savedAt;
  String? savedBy;

  InfectGiHemaDay({required this.enrollmentId, required this.nicuDay});

  static const feedTypeOptions = ['PDHM', 'EBM', 'FM'];
  static const meningitisTypeOptions = ['Probable', 'Proven'];
  // Modified Bell's staging — must match web's PillSingle options exactly
  // (RespCVNeuroLog... InfectGIHemaLog.jsx) and the backend's
  // NEC_STAGE_ORDER keys (main.py), which computes "definite NEC" as
  // stage >= IIA. The old coarse 'Stage I/II/III' set silently failed
  // that backend check (unrecognized key defaults to 0) and was also
  // invisible to web's picker, which only recognizes these six values.
  static const necStageOptions = ['IA', 'IB', 'IIA', 'IIB', 'IIIA', 'IIIB'];

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

  static List<String> _splitCsv(dynamic v) {
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

  factory InfectGiHemaDay.fromJson(Map<String, dynamic> json) {
    final d = InfectGiHemaDay(
      enrollmentId: (json['enrollment_id'] ?? '').toString(),
      nicuDay: json['nicu_day'] is int
          ? json['nicu_day'] as int
          : int.tryParse('${json['nicu_day']}') ?? 1,
    );
    d.sepsisSuspected = _asBool(json['sepsis_suspected']);
    d.bloodCultureSent = _asBool(json['blood_culture_sent']);
    d.bloodCulturePositive = _asBool(json['blood_culture_positive']);
    d.antibiotics = _asBool(json['antibiotics']);
    d.lpDone = _asBool(json['lp_done']);
    d.meningitis = _asBool(json['meningitis']);
    d.meningitisType = json['meningitis_type']?.toString();
    d.clabsi = _asBool(json['clabsi']);
    d.vap = _asBool(json['vap']);
    d.npo = _asBool(json['npo']);
    d.men = _asBool(json['men']);
    d.enteralFeedsReceived = _asBool(json['enteral_feeds_received']);
    d.feedType = _splitCsv(json['feed_type']);
    d.cumulativeFeedVolume = _asDouble(json['cumulative_feed_volume']);
    d.feedVolume = _asDouble(json['feed_volume']);
    d.ivFluids = _asBool(json['iv_fluids']);
    d.parenteralNutrition = _asBool(json['parenteral_nutrition']);
    d.probiotic = _asBool(json['probiotic']);
    d.feedIntolerance = _asBool(json['feed_intolerance']);
    d.necSuspected = _asBool(json['nec_suspected']);
    d.necConfirmedStage = json['nec_confirmed_stage']?.toString();
    d.cholestasis = _asBool(json['cholestasis']);
    d.hbValue = _asDouble(json['hb_value']);
    d.jaundice = _asBool(json['jaundice']);
    d.phototherapy = _asBool(json['phototherapy']);
    d.peakTsb = _asDouble(json['peak_tsb']);
    d.exchangeTransfusion = _asBool(json['exchange_transfusion']);
    d.prbcTransfusion = _asBool(json['prbc_transfusion']);
    d.plateletTransfusion = _asBool(json['platelet_transfusion']);
    d.ffpCryo = _asBool(json['ffp_cryo']);
    d.submissionStatus = json['submission_status']?.toString();
    d.savedAt = json['saved_at']?.toString();
    d.savedBy = json['saved_by']?.toString();
    return d;
  }

  void copyClinicalFrom(InfectGiHemaDay src) {
    sepsisSuspected = src.sepsisSuspected;
    bloodCultureSent = src.bloodCultureSent;
    bloodCulturePositive = src.bloodCulturePositive;
    antibiotics = src.antibiotics;
    lpDone = src.lpDone;
    meningitis = src.meningitis;
    meningitisType = src.meningitisType;
    clabsi = src.clabsi;
    vap = src.vap;
    npo = src.npo;
    men = src.men;
    enteralFeedsReceived = src.enteralFeedsReceived;
    feedType = List.of(src.feedType);
    cumulativeFeedVolume = src.cumulativeFeedVolume;
    feedVolume = src.feedVolume;
    ivFluids = src.ivFluids;
    parenteralNutrition = src.parenteralNutrition;
    probiotic = src.probiotic;
    feedIntolerance = src.feedIntolerance;
    necSuspected = src.necSuspected;
    necConfirmedStage = src.necConfirmedStage;
    cholestasis = src.cholestasis;
    hbValue = src.hbValue;
    jaundice = src.jaundice;
    phototherapy = src.phototherapy;
    peakTsb = src.peakTsb;
    exchangeTransfusion = src.exchangeTransfusion;
    prbcTransfusion = src.prbcTransfusion;
    plateletTransfusion = src.plateletTransfusion;
    ffpCryo = src.ffpCryo;
  }

  Map<String, dynamic> toJson({
    required String submissionStatus,
    String? savedAt,
    String? savedBy,
  }) {
    return {
      'enrollment_id': enrollmentId,
      'nicu_day': nicuDay,
      'sepsis_suspected': sepsisSuspected,
      'blood_culture_sent': bloodCultureSent,
      'blood_culture_positive': bloodCulturePositive,
      'antibiotics': antibiotics,
      'lp_done': lpDone,
      'meningitis': meningitis,
      'meningitis_type':
          (meningitisType?.trim().isEmpty ?? true) ? null : meningitisType,
      'clabsi': clabsi,
      'vap': vap,
      'npo': npo,
      'men': men,
      'enteral_feeds_received': enteralFeedsReceived,
      'feed_type': feedType.isEmpty ? null : feedType.join(','),
      'cumulative_feed_volume': cumulativeFeedVolume,
      'feed_volume': feedVolume,
      'iv_fluids': ivFluids,
      'parenteral_nutrition': parenteralNutrition,
      'probiotic': probiotic,
      'feed_intolerance': feedIntolerance,
      'nec_suspected': necSuspected,
      'nec_confirmed_stage': (necConfirmedStage?.trim().isEmpty ?? true)
          ? null
          : necConfirmedStage,
      'cholestasis': cholestasis,
      'hb_value': hbValue,
      'jaundice': jaundice,
      'phototherapy': phototherapy,
      'peak_tsb': peakTsb,
      'exchange_transfusion': exchangeTransfusion,
      'prbc_transfusion': prbcTransfusion,
      'platelet_transfusion': plateletTransfusion,
      'ffp_cryo': ffpCryo,
      'submission_status': submissionStatus,
      'saved_at': savedAt,
      'saved_by': savedBy,
    };
  }
}

/// Frontend completion rules from InfectGIHemaLog.jsx (Submit at 100%).
class InfectGiHemaCompletion {
  final int answered;
  final int total;
  int get percent =>
      total > 0 ? ((answered / total) * 100).round().clamp(0, 100) : 0;

  const InfectGiHemaCompletion(this.answered, this.total);

  static bool _ans(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true; // bool false counts as answered
  }

  static InfectGiHemaCompletion compute(InfectGiHemaDay d) {
    final keys = <dynamic>[
      d.sepsisSuspected,
      d.antibiotics,
      d.lpDone,
      d.meningitis,
      d.clabsi,
      d.vap,
    ];
    if (d.sepsisSuspected == true) {
      keys.add(d.bloodCultureSent);
      if (d.bloodCultureSent == true) keys.add(d.bloodCulturePositive);
    }
    if (d.meningitis == true) keys.add(d.meningitisType);

    keys.addAll([
      d.npo,
      d.ivFluids,
      d.parenteralNutrition,
      d.probiotic,
      d.feedIntolerance,
      d.necSuspected,
      d.cholestasis,
    ]);
    if (d.npo == false) {
      keys.addAll([
        d.men,
        d.enteralFeedsReceived,
        d.cumulativeFeedVolume,
        d.feedVolume,
      ]);
      if (d.enteralFeedsReceived == true) keys.add(d.feedType);
    }
    if (d.necSuspected == true) keys.add(d.necConfirmedStage);

    keys.addAll([
      d.hbValue,
      d.jaundice,
      d.peakTsb,
      d.exchangeTransfusion,
      d.prbcTransfusion,
      d.plateletTransfusion,
      d.ffpCryo,
    ]);
    if (d.jaundice == true) keys.add(d.phototherapy);

    final answered = keys.where(_ans).length;
    return InfectGiHemaCompletion(answered, keys.length);
  }
}

class InfectGiHemaValidators {
  static String? cumulativeFeedVolume(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return "Value can't be negative";
    if (n > 1000) return 'Looks high (>1000 ml) — please double-check';
    return null;
  }

  static String? feedVolume(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return "Value can't be negative";
    if (n > 220) return 'Usually ≤220 ml/kg/d — please double-check';
    return null;
  }

  static String? hb(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return "Value can't be negative";
    if (n > 30) return 'Hb usually ≤30 g/dL — please double-check';
    if (n < 3) return 'Hb looks unusually low — please double-check';
    return null;
  }

  static String? peakTsb(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim());
    if (n == null) return 'Enter a valid number';
    if (n < 0) return "Value can't be negative";
    if (n > 35) return 'Peak TSB usually ≤35 mg/dL — please double-check';
    return null;
  }
}