// lib/models/birth_resuscitation.dart
//
// Single shared model for the mobile Form B (screens: FormBBirthResuscitation)
// and Form C (screen: FormCResuscitationDetails) — these are UI-split halves
// of ONE backend record: the `birth_resuscitation` table / BirthResuscitation
// SQLAlchemy model in the web backend.
//
// Field names below are IDENTICAL to backend/models.py `BirthResuscitation`
// and backend/schemas.py `BirthResuscitationCreate` — do not rename these,
// the sync depends on exact key matches with no translation layer.
//
// Numbering in comments (B1./B2./.../64.) matches the numbering shown in
// BirthResuscitationForm.jsx on the web portal.

class BirthResuscitationData {
  // ── Keys ──────────────────────────────────────────────────────────────
  String? screeningId;             // screening_id
  String? enrollmentId;            // enrollment_id  (B3: 26.)

  // ── B1 · Identification ──────────────────────────────────────────────
  String? babyUid;                 // baby_uid            (B1: 4.)
  String? babyAdmissionNo;         // baby_admission_no    (B1: 6.)
  String? babyAnnualNo;            // baby_annual_no       (B1: 7.)

  // ── B2 · Birth Details ───────────────────────────────────────────────
  DateTime? dateOfBirth;           // date_of_birth        (B2: 8.)
  String? timeOfBirth;             // time_of_birth  "HH:mm" (B2: 9.)
  String? gender;                  // gender               (B2: 10.)
  int? gestationWeeks;             // gestation_weeks       (B2: 11. — from screening)
  int? gestationDays;              // gestation_days
  int? gestationRandWeeks;         // gestation_rand_weeks  (B2: 12.)
  int? gestationRandDays;          // gestation_rand_days
  double? birthWeight;             // birth_weight          (B2: 13.)
  String? intrauterineCentile;     // intrauterine_centile  (B2: 14.)
  String? deliveryMode;            // delivery_mode         (B2: 15.)
  String? vaginalDeliveryType;     // vaginal_delivery_type (B2: 16.)
  String? lscsType;                // lscs_type             (B2: 17.)
  List<String> indicationForDelivery = []; // indication_for_delivery (B2: 18. multi-select, comma-joined on save)
  String? indicationEdfDetail;     // indication_edf_detail
  String? fetalIndicationDetail;   // fetal_indication_detail
  String? obstetricIndicationDetail; // obstetric_indication_detail
  String? indicationForDeliveryOther; // indication_for_delivery_other

  // ── B3 · Condition at Birth & Randomization ─────────────────────────
  bool? poorRespEfforts;           // poor_resp_efforts     (B3: 19.)
  bool? poorMuscleTone;            // poor_muscle_tone      (B3: 20.)
  bool? hrAbove100;                // hr_above_100          (B3: 21.)
  bool? initialSteps;              // initial_steps         (B3: 22.)
  bool? requiredResuscitation;     // required_resuscitation(B3: 23.)
  bool? randomised;                // randomised            (B3: 24.)
  String? randomisationDate;       // randomisation_date    (B3: 25.)
  String? strata;                  // strata                (B3: 27.)
  String? blenderLetter;           // blender_letter (device identifier, from Blender Code selector)
  String? enrollmentReasonNotRandomized;       // (B3: 28.)
  String? enrollmentReasonNotRandomizedOther;

  // ── B4 · Resuscitation Interventions ─────────────────────────────────
  bool? ppvRequired;               // ppv_required          (29.)
  String? devicePpv;               // device_ppv    "T-piece" | "Self-inflating bag" | "Both"
  String? sibPeepWith;             // sib_peep_with (29a.)
  double? sibPeepCmh2o;            // sib_peep_cmh2o
  double? tpiecePip;               // tpiece_pip    (29b.)
  double? tpiecePeep;              // tpiece_peep
  double? tpieceFlow;              // tpiece_flow
  String? interfaceUsed;           // interface_used        (30.)
  int? ppvDuration;                // ppv_duration  seconds (31.)
  bool? intubation;                // intubation             (32.)
  bool? chestCompression;          // chest_compression      (33.)
  int? ccDuration;                 // cc_duration   seconds (34.)
  bool? adrenaline;                // adrenaline              (35.)
  String? adrenalineDilution;      // adrenaline_dilution    (36.)
  String? adrenalineRoute;         // adrenaline_route       (37.)
  int? medDoses;                   // med_doses              (39.)
  double? adrenalineCumulative;    // adrenaline_cumulative  (40.)
  bool? fluidBolus;                // fluid_bolus             (41.)
  int? fluidBolusDoses;            // fluid_bolus_doses      (42.)
  double? fluidBolusCumulative;    // fluid_bolus_cumulative (43.)
  bool? placentalTransfusion;      // placental_transfusion   (44.)
  String? transfusionMethod;       // transfusion_method      (45.)
  String? cordClampTimestamp;      // cord_clamp_timestamp "HH:mm:ss" (46.)
  int? cordClampTime;              // cord_clamp_time seconds (47.)
  int? timeToRespiration;          // time_to_respiration seconds (48.)
  int? respirationDays;            // respiration_days
  int? respirationHours;           // respiration_hours
  int? spo25min;                   // spo2_5min               (49.)
  int? timeToSpo280;               // time_to_spo2_80          (50.)

  // ── B5 · Minute-wise Intervention Summary ────────────────────────────
  // Keys match web exactly: oxygen(51.) ventilation(52.) chest_compression(53.)
  // intubation(54.) medication(55.) fluid_bolus cpap — each maps minute-label
  // ("1","5","10" etc, same as web's `times`) -> value string.
  // apgar is its own top-level key inside the same map, matching web's
  // `formData.interventions.apgar`.
  Map<String, Map<String, String>> interventions = {
    'oxygen': {},
    'cpap': {},
    'apgar': {},
  };

  // ── B6 · Cord Blood & Resuscitation Exit ─────────────────────────────
  bool? resusFailure;              // resus_failure           (60. — toggle text)
  bool? cordBloodDone;             // cord_blood_done         (56.)
  bool? cordBloodWithin1hr;        // cord_blood_within_1hr   (57.)
  String? cordBloodSource;         // cord_blood_source       (58.)
  double? cordPh;                  // cord_ph                 (59.)
  double? cordSbe;                 // cord_sbe                (59.)
  double? cordPco2;                // cord_pco2                (59.)
  double? spo2ExitTrialGas;     // spo2_exit_trial_gas
  String? totalResusTime;       // total_resus_time — MM:SS from APGAR timer
  String? reasonExitTrialGas;   // reason_exit_trial_gas
  String? reasonExitTrialGasOther; // reason_exit_trial_gas_other
  bool? blenderStopped;            // blender_stopped          (59.)
  List<String> blenderInterruptReasons = []; // blender_interrupt_reasons (60.)
  String? blenderStoppedDescription; // blender_stopped_description

  BirthResuscitationData();

  /// Builds the payload for `BirthResuscitationCreate`.
  ///
  /// [omitNulls] defaults to true so Form B and Form C can each POST only the
  /// fields they own. The backend POST upsert does `setattr` for every key —
  /// sending nulls would wipe the other screen's half of the record.
  Map<String, dynamic> toJson({bool omitNulls = true}) {
    final map = <String, dynamic>{
      'screening_id': screeningId,
      'enrollment_id': enrollmentId,
      'baby_uid': babyUid,
      'baby_admission_no': babyAdmissionNo,
      'baby_annual_no': babyAnnualNo,
      'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
      'time_of_birth': timeOfBirth,
      'gender': gender,
      'gestation_weeks': gestationWeeks,
      'gestation_days': gestationDays,
      'gestation_rand_weeks': gestationRandWeeks,
      'gestation_rand_days': gestationRandDays,
      'birth_weight': birthWeight,
      'intrauterine_centile': intrauterineCentile,
      'delivery_mode': deliveryMode,
      'vaginal_delivery_type': vaginalDeliveryType,
      'lscs_type': lscsType,
      // Web stores this as a single string (values joined) — keep identical
      // join behaviour so both clients parse it the same way back out.
      'indication_for_delivery': indicationForDelivery.isEmpty
          ? null
          : indicationForDelivery.join(', '),
      'indication_edf_detail': indicationEdfDetail,
      'fetal_indication_detail': fetalIndicationDetail,
      'obstetric_indication_detail': obstetricIndicationDetail,
      'indication_for_delivery_other': indicationForDeliveryOther,
      'poor_resp_efforts': poorRespEfforts,
      'poor_muscle_tone': poorMuscleTone,
      'hr_above_100': hrAbove100,
      'initial_steps': initialSteps,
      'required_resuscitation': requiredResuscitation,
      'randomised': randomised,
      'randomisation_date': randomisationDate,
      'strata': strata,
      'blender_letter': blenderLetter,
      'enrollment_reason_not_randomized': enrollmentReasonNotRandomized,
      'enrollment_reason_not_randomized_other':
          enrollmentReasonNotRandomizedOther,
      'ppv_required': ppvRequired,
      'device_ppv': devicePpv,
      'sib_peep_with': sibPeepWith,
      'sib_peep_cmh2o': sibPeepCmh2o,
      'tpiece_pip': tpiecePip,
      'tpiece_peep': tpiecePeep,
      'tpiece_flow': tpieceFlow,
      'interface_used': interfaceUsed,
      'ppv_duration': ppvDuration,
      'intubation': intubation,
      'chest_compression': chestCompression,
      'cc_duration': ccDuration,
      'adrenaline': adrenaline,
      'adrenaline_dilution': adrenalineDilution,
      'adrenaline_route': adrenalineRoute,
      'med_doses': medDoses,
      'adrenaline_cumulative': adrenalineCumulative,
      'fluid_bolus': fluidBolus,
      'fluid_bolus_doses': fluidBolusDoses,
      'fluid_bolus_cumulative': fluidBolusCumulative,
      'placental_transfusion': placentalTransfusion,
      'transfusion_method': transfusionMethod,
      'cord_clamp_timestamp': cordClampTimestamp,
      'cord_clamp_time': cordClampTime,
      'time_to_respiration': timeToRespiration,
      'respiration_days': respirationDays,
      'respiration_hours': respirationHours,
      'spo2_5min': spo25min,
      'time_to_spo2_80': timeToSpo280,
      'interventions': _interventionsPayload(),
      'resus_failure': resusFailure,
      'cord_blood_done': cordBloodDone,
      'cord_blood_within_1hr': cordBloodWithin1hr,
      'cord_blood_source': cordBloodSource,
      'cord_ph': cordPh,
      'cord_sbe': cordSbe,
      'cord_pco2': cordPco2,
      'spo2_exit_trial_gas': spo2ExitTrialGas,
      'total_resus_time': totalResusTime,
      // Web folds "Other" free-text into reason_exit_trial_gas itself.
      'reason_exit_trial_gas': reasonExitTrialGas == 'Other'
          ? (reasonExitTrialGasOther?.trim().isNotEmpty == true
              ? reasonExitTrialGasOther
              : 'Other')
          : reasonExitTrialGas,
      'blender_stopped': blenderStopped,
      // Only send when this screen answered Q59 (Form C). Form B leaves
      // blenderStopped null so omitNulls won't wipe Form C's reasons.
      'blender_interrupt_reasons': blenderStopped == null
          ? null
          : blenderInterruptReasons.join(', '),
      'blender_stopped_description': blenderStopped == false
          ? ''
          : blenderStoppedDescription,
    };
    if (omitNulls) {
      map.removeWhere((_, v) => v == null);
    }
    return map;
  }

  /// Omit empty intervention maps so Form B saves don't wipe Form C B5 data.
  Map<String, dynamic>? _interventionsPayload() {
    final oxygen = _normalizeInterventionMap(interventions['oxygen']);
    final cpap = _normalizeInterventionMap(interventions['cpap']);
    final apgar = Map<String, String>.from(interventions['apgar'] ?? {})
      ..removeWhere((_, v) => v.trim().isEmpty);
    if (oxygen.isEmpty && cpap.isEmpty && apgar.isEmpty) return null;
    return {
      'oxygen': oxygen,
      'cpap': cpap,
      'apgar': apgar,
    };
  }

  /// Web IntvCell stores "Yes"/"No"/"NR" (labels show Y/N). Map mobile Y/N.
  Map<String, String> _normalizeInterventionMap(Map<String, String>? raw) {
    if (raw == null || raw.isEmpty) return {};
    const mapYn = {'Y': 'Yes', 'N': 'No', 'Yes': 'Yes', 'No': 'No', 'NR': 'NR'};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final t = v.trim();
      if (t.isEmpty) return;
      out[k] = mapYn[t] ?? t;
    });
    return out;
  }

  factory BirthResuscitationData.fromJson(Map<String, dynamic> json) {
    final d = BirthResuscitationData();
    d.screeningId = json['screening_id'];
    d.enrollmentId = json['enrollment_id'];
    d.babyUid = json['baby_uid'];
    d.babyAdmissionNo = json['baby_admission_no'];
    d.babyAnnualNo = json['baby_annual_no'];
    d.dateOfBirth = json['date_of_birth'] != null
        ? DateTime.tryParse(json['date_of_birth'])
        : null;
    d.timeOfBirth = json['time_of_birth'];
    d.gender = json['gender'];
    d.gestationWeeks = json['gestation_weeks'];
    d.gestationDays = json['gestation_days'];
    d.gestationRandWeeks = json['gestation_rand_weeks'];
    d.gestationRandDays = json['gestation_rand_days'];
    d.birthWeight = (json['birth_weight'] as num?)?.toDouble();
    d.intrauterineCentile = json['intrauterine_centile'];
    d.deliveryMode = json['delivery_mode'];
    d.vaginalDeliveryType = json['vaginal_delivery_type'];
    d.lscsType = json['lscs_type'];
    d.indicationForDelivery = (json['indication_for_delivery'] as String?)
            ?.split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    d.indicationEdfDetail = json['indication_edf_detail'];
    d.fetalIndicationDetail = json['fetal_indication_detail'];
    d.obstetricIndicationDetail = json['obstetric_indication_detail'];
    d.indicationForDeliveryOther = json['indication_for_delivery_other'];
    d.poorRespEfforts = json['poor_resp_efforts'];
    d.poorMuscleTone = json['poor_muscle_tone'];
    d.hrAbove100 = json['hr_above_100'];
    d.initialSteps = json['initial_steps'];
    d.requiredResuscitation = json['required_resuscitation'];
    d.randomised = json['randomised'];
    d.randomisationDate = json['randomisation_date'];
    d.strata = json['strata'];
    d.blenderLetter = json['blender_letter'];
    d.enrollmentReasonNotRandomized = json['enrollment_reason_not_randomized'];
    d.enrollmentReasonNotRandomizedOther =
        json['enrollment_reason_not_randomized_other'];
    d.ppvRequired = json['ppv_required'];
    d.devicePpv = json['device_ppv'];
    d.sibPeepWith = json['sib_peep_with'];
    d.sibPeepCmh2o = (json['sib_peep_cmh2o'] as num?)?.toDouble();
    d.tpiecePip = (json['tpiece_pip'] as num?)?.toDouble();
    d.tpiecePeep = (json['tpiece_peep'] as num?)?.toDouble();
    d.tpieceFlow = (json['tpiece_flow'] as num?)?.toDouble();
    d.interfaceUsed = json['interface_used'];
    d.ppvDuration = json['ppv_duration'];
    d.intubation = json['intubation'];
    d.chestCompression = json['chest_compression'];
    d.ccDuration = json['cc_duration'];
    d.adrenaline = json['adrenaline'];
    d.adrenalineDilution = json['adrenaline_dilution'];
    d.adrenalineRoute = json['adrenaline_route'];
    d.medDoses = json['med_doses'];
    d.adrenalineCumulative = (json['adrenaline_cumulative'] as num?)?.toDouble();
    d.fluidBolus = json['fluid_bolus'];
    d.fluidBolusDoses = json['fluid_bolus_doses'];
    d.fluidBolusCumulative = (json['fluid_bolus_cumulative'] as num?)?.toDouble();
    d.placentalTransfusion = json['placental_transfusion'];
    d.transfusionMethod = json['transfusion_method'];
    d.cordClampTimestamp = json['cord_clamp_timestamp'];
    d.cordClampTime = json['cord_clamp_time'];
    d.timeToRespiration = json['time_to_respiration'];
    d.respirationDays = json['respiration_days'];
    d.respirationHours = json['respiration_hours'];
    d.spo25min = json['spo2_5min'];
    d.timeToSpo280 = json['time_to_spo2_80'];
    if (json['interventions'] != null) {
      final raw = json['interventions'] as Map;
      d.interventions = {
        'oxygen': Map<String, String>.from(
          ((raw['oxygen'] as Map?) ?? {}).map(
              (mk, mv) => MapEntry(mk.toString(), mv.toString())),
        ),
        'cpap': Map<String, String>.from(
          ((raw['cpap'] as Map?) ?? {}).map(
              (mk, mv) => MapEntry(mk.toString(), mv.toString())),
        ),
        'apgar': Map<String, String>.from(
          ((raw['apgar'] as Map?) ?? {}).map(
              (mk, mv) => MapEntry(mk.toString(), mv.toString())),
        ),
      };
    }
    d.resusFailure = json['resus_failure'];
    d.cordBloodDone = json['cord_blood_done'];
    d.cordBloodWithin1hr = json['cord_blood_within_1hr'];
    d.cordBloodSource = json['cord_blood_source'];
    d.cordPh = (json['cord_ph'] as num?)?.toDouble();
    d.cordSbe = (json['cord_sbe'] as num?)?.toDouble();
    d.cordPco2 = (json['cord_pco2'] as num?)?.toDouble();
    d.spo2ExitTrialGas = (json['spo2_exit_trial_gas'] as num?)?.toDouble();
    d.totalResusTime = normalizeTotalResusTimeMmSs(json['total_resus_time']);
    d.reasonExitTrialGas = json['reason_exit_trial_gas'];
    d.reasonExitTrialGasOther = json['reason_exit_trial_gas_other'];
    d.blenderStopped = json['blender_stopped'];
    d.blenderInterruptReasons = parseBlenderInterruptReasons(
      json['blender_interrupt_reasons'],
    );
    if (d.blenderInterruptReasons.isEmpty &&
        d.blenderStopped == true &&
        (json['blender_stopped_description'] ?? '').toString().trim().isNotEmpty) {
      d.blenderInterruptReasons = [kBlenderAbruptReason];
    }
    d.blenderStoppedDescription = json['blender_stopped_description'];
    return d;
  }
}

/// Field 57 Total resus time — store/display as MM:SS.
/// Legacy integer minutes become "MM:00".
String? normalizeTotalResusTimeMmSs(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{1,3}$').hasMatch(s)) {
    final m = int.tryParse(s) ?? 0;
    return '${m.toString().padLeft(2, '0')}:00';
  }
  final m = RegExp(r'^(\d{1,3}):([0-5]?\d)$').firstMatch(s);
  if (m == null) return s;
  final mm = (int.tryParse(m.group(1)!) ?? 0).clamp(0, 999);
  final ss = (int.tryParse(m.group(2)!) ?? 0).clamp(0, 59);
  return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
}

const kBlenderInterruptReasons = [
  "Blender stopped abruptly",
  "Surfactant decision",
  "Intubation",
  "FiO₂ – 21 or 100%",
  "Early transfer",
];
const kBlenderAbruptReason = "Blender stopped abruptly";

List<String> parseBlenderInterruptReasons(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return [];
  return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}
