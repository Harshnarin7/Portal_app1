import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'form_c_resuscitation.dart';
import '../models/form_b.dart';
import '../models/birth_resuscitation.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../services/screening_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/required_asterisk.dart';

// ─── SITE-SPECIFIC RULES for Baby Admission No. / Baby Annual No. ─────────────
// Mirrors BirthResuscitationForm.jsx BABY_ADMISSION_RULES / BABY_ANNUAL_RULES
// (webforms/frontend-app/src/BirthResuscitationForm.jsx, ~L361-390) verbatim.

class _AdmissionRule {
  final String label;
  final String placeholder;
  final int min;
  final int max;
  final bool required;
  const _AdmissionRule(this.label, this.placeholder, this.min, this.max,
      {this.required = false});
}

class _AnnualRule {
  final String label;
  final String placeholder;
  final int min;
  final int max;
  final bool numeric;
  const _AnnualRule(this.label, this.placeholder, this.min, this.max,
      {this.numeric = false});
}

const Map<String, _AdmissionRule> _kBabyAdmissionRules = {
  "PGIMER": _AdmissionRule(
      "6. Baby Admission No.", "Not assigned yet", 10, 10),
  "GMCH-A":
      _AdmissionRule("6. MRD Number for Baby", "Not assigned yet", 4, 6),
  "AMC": _AdmissionRule("6. Baby Admission No. (NICU only)",
      "Not assigned yet", 11, 11),
  "GMCH": _AdmissionRule("6. Baby Admission No.", "Not assigned yet", 9, 11),
  "IOG": _AdmissionRule("6. Baby MRD No. (same as UID)",
      "Not assigned yet", 4, 6),
};

// Fallback for any site not in the map above — optional, up to 15 chars,
// no numeric restriction (matches web's inline fallback object).
const _AdmissionRule _kBabyAdmissionDefaultRule =
    _AdmissionRule("6. Baby Admission No.", "Not assigned yet", 0, 15);

// Sites with no entry here (GMCH-A, GMCH, and anything else unlisted) get
// babyAnnualRule == null on web, which hides the field entirely.
const Map<String, _AnnualRule> _kBabyAnnualRules = {
  "PGIMER": _AnnualRule(
      "7. Baby Annual No.", "4-digit annual number", 4, 4,
      numeric: true),
  "AMC": _AnnualRule("7. Delivery Room Logbook Serial No.",
      "Logbook serial number", 0, 20),
  "IOG": _AnnualRule("7. SNCU No.", "4-digit SNCU number", 4, 4,
      numeric: true),
};

/// Maps site codes (CRF.siteId) → site names used by the rule tables / web.
/// Web keys rules by site name ("PGIMER"); mobile often passes "01".
const Map<String, String> _kSiteCodeToName = {
  "01": "PGIMER",
  "02": "GMCH",
  "03": "IOG",
  "04": "AFMC",
  "05": "GMCH-A",
  "06": "AMC",
};

/// Enrollment ID format: `{site}-{A|B|C|D}-{###}` e.g. `01-A-001`.
String _formatEnrollmentId(String raw, String siteCode) {
  final site = siteCode.padLeft(2, "0");
  final site2 = site.length >= 2 ? site.substring(0, 2) : site.padLeft(2, "0");
  var cleaned = raw.toUpperCase().replaceAll(RegExp(r"[^A-D0-9]"), "");
  if (cleaned.startsWith(site2)) {
    cleaned = cleaned.substring(2);
  } else if (cleaned.length >= 2 && RegExp(r"^\d{2}").hasMatch(cleaned)) {
    cleaned = cleaned.substring(2);
  }
  String? letter;
  final nums = StringBuffer();
  for (final ch in cleaned.split("")) {
    if (letter == null && RegExp(r"[A-D]").hasMatch(ch)) {
      letter = ch;
    } else if (letter != null &&
        RegExp(r"[0-9]").hasMatch(ch) &&
        nums.length < 3) {
      nums.write(ch);
    }
  }
  if (letter == null) return "$site2-";
  if (nums.isEmpty) return "$site2-$letter-";
  return "$site2-$letter-${nums.toString()}";
}

bool _isCompleteEnrollmentId(String value) =>
    RegExp(r"^\d{2}-[A-D]-\d{3}$").hasMatch(value.trim());

class _EnrollmentIdInputFormatter extends TextInputFormatter {
  final String siteCode;
  _EnrollmentIdInputFormatter(this.siteCode);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = _formatEnrollmentId(newValue.text, siteCode);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class FormBBirthResuscitation extends StatefulWidget {
  final String screeningId;
  final String maternalUid;
  final String motherName;
  final String motherPhone;
  final String husbandPhone;
  final int gestWeeks;
  final int gestDays;
  final String siteId;
  /// Form A screening datetime (ISO or DD/MM/YYYY…) — needed to compute
  /// Gestation at Randomization = screening GA + (DOB − screening date).
  final String screeningDateTime;
  /// When true, form is read-only (previously filled review).
  final bool viewOnly;

  const FormBBirthResuscitation({
    super.key,
    required this.screeningId,
    required this.maternalUid,
    required this.motherName,
    required this.motherPhone,
    required this.husbandPhone,
    required this.gestWeeks,
    required this.gestDays,
    required this.siteId,
    this.screeningDateTime = "",
    this.viewOnly = false,
  });

  @override
  State<FormBBirthResuscitation> createState() =>
      _FormBBirthResuscitationState();
}

class _FormBBirthResuscitationState extends State<FormBBirthResuscitation> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────────
  final TextEditingController _babyUidCtrl            = TextEditingController();
  final TextEditingController _babyAdmissionCtrl      = TextEditingController();
  final TextEditingController _birthWeightCtrl        = TextEditingController();
  final TextEditingController _randomizationDateCtrl  = TextEditingController();
  final TextEditingController _enrollmentIdCtrl       = TextEditingController();
  final TextEditingController _notRandomizedOtherCtrl = TextEditingController();
  final TextEditingController _indicationOtherCtrl    = TextEditingController();
  final TextEditingController _dobController          = TextEditingController();
  final TextEditingController _timeController         = TextEditingController();
  final TextEditingController _babyAnnualNumberCtrl   = TextEditingController();
  final TextEditingController _growthCentileCtrl      = TextEditingController();
  // NOTE: web's indication_edf_detail / fetal_indication_detail /
  // obstetric_indication_detail are dead backend columns with NO rendered
  // input anywhere in BirthResuscitationForm.jsx (verified) — not added here
  // to avoid inventing UI the web form doesn't have.

  // ── Birth details ──────────────────────────────────────────────────────────
  List<String> _indications = [];
  String? _delivery;
  String? _vaginalType;
  String? _lscsType;
  String? _gender;

  // ── Condition at birth ─────────────────────────────────────────────────────
  bool? _poorRespiratoryEffort;
  bool? _poorMuscleTone;
  bool? _hrAbove100;                 // B3.21 (webform)
  bool? _initialStepsRequired;
  bool? _requiredResuscitation;

  // ── Inline validation flags ────────────────────────────────────────────────
  bool _submitted         = false;
  bool _babyUidMaxReached = false;

  // ── Randomization ─────────────────────────────────────────────────────────
  bool? _randomized;
  String? _notRandomizedReason;

  /// Screening datetime used for GA-at-randomization (may be loaded from API).
  String _screeningDateTime = "";

  // ── Auto-strata from Gestation at Randomization (web Form B1) ───────────────
  String get _strata {
    final rand = _gestationAtRandomization;
    final totalDays = rand != null
        ? rand.$1 * 7 + rand.$2
        : widget.gestWeeks * 7 + widget.gestDays;
    return totalDays < (28 * 7) ? "< 28 weeks" : "≥ 28 – 31 weeks";
  }

  /// screening GA + elapsed calendar days (DOB − screening date), same as web.
  (int weeks, int days)? get _gestationAtRandomization {
    final dob = _parseDobText(_dobController.text);
    if (dob == null) return null;
    final screeningDay = _parseScreeningDateTime(_screeningDateTime);
    if (screeningDay == null) return null;
    if (widget.gestWeeks <= 0 && widget.gestDays <= 0) return null;

    final screeningGA = widget.gestWeeks * 7 + widget.gestDays;
    final s = DateTime(screeningDay.year, screeningDay.month, screeningDay.day);
    final b = DateTime(dob.year, dob.month, dob.day);
    final elapsed = b.difference(s).inDays;
    final elapsedDays = elapsed < 0 ? 0 : elapsed;
    final randomisationGA = screeningGA + elapsedDays;
    return (randomisationGA ~/ 7, randomisationGA % 7);
  }

  /// Combined DOB + TOB for comparison with Form A screening datetime.
  DateTime? get _birthDateTime {
    final dob = _parseDobText(_dobController.text);
    if (dob == null) return null;
    final tob = _timeController.text.trim();
    if (tob.isEmpty) return null;
    final hms = _parseHms(tob);
    return DateTime(
      dob.year,
      dob.month,
      dob.day,
      hms.hour,
      hms.minute,
      hms.second,
    );
  }

  /// Live check (same as web BirthResuscitationForm birthBeforeScreening).
  bool get _birthBeforeScreening {
    final birth = _birthDateTime;
    final screening = _parseScreeningDateTime(_screeningDateTime);
    if (birth == null || screening == null) return false;
    return birth.isBefore(screening);
  }

  String get _gestationRandDisplay {
    final rand = _gestationAtRandomization;
    if (rand == null) return "— (enter Date of Birth)";
    return "${rand.$1}w ${rand.$2}d";
  }

  // ── Site-specific rules for Baby Admission No. / Baby Annual No. ──────────
  // Web keys by site name ("PGIMER"); callers may pass name OR site code ("01").
  String get _siteName {
    final raw = widget.siteId.trim();
    if (raw.isEmpty) return "";
    if (_kBabyAdmissionRules.containsKey(raw) ||
        _kBabyAnnualRules.containsKey(raw) ||
        _kSiteCodeToName.containsValue(raw)) {
      return raw;
    }
    return _kSiteCodeToName[raw] ?? raw;
  }

  /// Two-digit site code for Enrollment ID prefix (e.g. "01").
  String get _siteCode {
    final raw = widget.siteId.trim();
    if (RegExp(r"^\d{1,2}$").hasMatch(raw)) {
      return raw.padLeft(2, "0");
    }
    for (final e in _kSiteCodeToName.entries) {
      if (e.value == raw || e.value == _siteName) return e.key;
    }
    return "00";
  }

  void _ensureEnrollmentIdPrefix() {
    final cur = _enrollmentIdCtrl.text.trim();
    if (cur.isEmpty || cur == "-" || !cur.startsWith(_siteCode)) {
      _enrollmentIdCtrl.text = "$_siteCode-";
      _enrollmentIdCtrl.selection =
          TextSelection.collapsed(offset: _enrollmentIdCtrl.text.length);
    }
  }

  _AdmissionRule get _babyAdmissionRule =>
      _kBabyAdmissionRules[_siteName] ?? _kBabyAdmissionDefaultRule;

  _AnnualRule? get _babyAnnualRule => _kBabyAnnualRules[_siteName];

  // ── Section collapse state ─────────────────────────────────────────────────
  bool _conditionExpanded     = true;
  bool _randomizationExpanded = true;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _screeningDateTime = widget.screeningDateTime.trim();
    // IOG: Baby Admission No. mirrors Baby UID live (matches web's
    // BirthResuscitationForm.jsx useEffect ~L497-502, which keeps
    // baby_admission_no synced to baby_uid on every change for site IOG).
    if (_siteName == 'IOG') {
      _babyUidCtrl.addListener(_syncBabyAdmissionFromUid);
      _syncBabyAdmissionFromUid();
    }
    _bootstrapFormB();
  }

  Future<void> _bootstrapFormB() async {
    if (_screeningDateTime.isEmpty && widget.screeningId.trim().isNotEmpty) {
      try {
        final clinical = await ScreeningApiService.instance
            .getScreening(widget.screeningId);
        final dt = clinical?['screening_datetime']?.toString() ?? '';
        if (dt.isNotEmpty && mounted) {
          setState(() => _screeningDateTime = dt);
        }
      } catch (_) {}
    }
    await _loadExistingFormB();
  }

  // IOG-only: keep Baby Admission No. equal to Baby UID, including when
  // Baby UID is populated from an existing record on load.
  void _syncBabyAdmissionFromUid() {
    if (_babyAdmissionCtrl.text != _babyUidCtrl.text) {
      _babyAdmissionCtrl.text = _babyUidCtrl.text;
    }
  }

  bool _isFormBEmpty() {
    return _babyUidCtrl.text.trim().isEmpty &&
        _babyAdmissionCtrl.text.trim().isEmpty &&
        _babyAnnualNumberCtrl.text.trim().isEmpty &&
        _birthWeightCtrl.text.trim().isEmpty &&
        _growthCentileCtrl.text.trim().isEmpty &&
        _dobController.text.trim().isEmpty &&
        _timeController.text.trim().isEmpty &&
        _indications.isEmpty &&
        _delivery == null &&
        _gender == null &&
        _poorRespiratoryEffort == null &&
        _poorMuscleTone == null &&
        _hrAbove100 == null &&
        _initialStepsRequired == null &&
        _requiredResuscitation == null &&
        _randomized == null &&
        _enrollmentIdCtrl.text.trim().isEmpty;
  }

  @override
  void dispose() {
    // Flush local draft so back/swipe dismiss never loses in-progress data.
    if (!widget.viewOnly && !_isFormBEmpty()) {
      final eid = _enrollmentIdCtrl.text.trim().isNotEmpty
          ? _enrollmentIdCtrl.text.trim()
          : (_randomized == false ? "NR-${widget.screeningId}" : "");
      ApiService().saveFormB(_snapshotFormB(enrollmentId: eid));
    }
    _babyUidCtrl.removeListener(_syncBabyAdmissionFromUid);
    _babyUidCtrl.dispose();
    _babyAdmissionCtrl.dispose();
    _birthWeightCtrl.dispose();
    _randomizationDateCtrl.dispose();
    _enrollmentIdCtrl.dispose();
    _notRandomizedOtherCtrl.dispose();
    _indicationOtherCtrl.dispose();
    _dobController.dispose();
    _timeController.dispose();
    _babyAnnualNumberCtrl.dispose();
    _growthCentileCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD EXISTING
  // ============================================================

  void _applyLocalFormB(FormB existing, {bool overlayOnly = false}) {
    void setText(TextEditingController c, String v) {
      if (!overlayOnly || v.trim().isNotEmpty) c.text = v;
    }

    setText(_babyUidCtrl, existing.babyUid);
    setText(_babyAdmissionCtrl, existing.babyAdmissionNo);
    setText(_babyAnnualNumberCtrl, existing.babyAnnualNo);
    setText(_birthWeightCtrl, existing.birthWeight);
    setText(_growthCentileCtrl, existing.intrauterineCentile);
    setText(_dobController, existing.dateOfBirth);
    if (!overlayOnly || existing.timeOfBirth.trim().isNotEmpty) {
      _timeController.text = _normalizeHms(existing.timeOfBirth);
    }
    if (!overlayOnly || existing.indication.trim().isNotEmpty) {
      _indications = existing.indication.trim().isEmpty
          ? (overlayOnly ? _indications : [])
          : existing.indication
              .split(",")
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    }
    setText(_indicationOtherCtrl, existing.indicationOther);
    if (!overlayOnly || existing.delivery.isNotEmpty) {
      _delivery = existing.delivery.isEmpty ? _delivery : existing.delivery;
      if (_delivery == "Vaginal") {
        if (!overlayOnly || existing.labor.isNotEmpty) {
          _vaginalType = existing.labor.isEmpty ? null : existing.labor;
        }
      } else if (_delivery == "LSCS") {
        if (!overlayOnly || existing.labor.isNotEmpty) {
          _lscsType = existing.labor.isEmpty ? null : existing.labor;
        }
      }
    }
    if (!overlayOnly || existing.gender.isNotEmpty) {
      _gender = existing.gender.isEmpty ? _gender : existing.gender;
    }
    if (!overlayOnly || existing.requiredResuscitation != null) {
      _requiredResuscitation =
          existing.requiredResuscitation ?? _requiredResuscitation;
    }
    if (!overlayOnly || existing.randomized != null) {
      _randomized = existing.randomized ?? _randomized;
    }
    if (!overlayOnly || existing.poorRespiratoryEffort != null) {
      _poorRespiratoryEffort =
          existing.poorRespiratoryEffort ?? _poorRespiratoryEffort;
    }
    if (!overlayOnly || existing.poorMuscleTone != null) {
      _poorMuscleTone = existing.poorMuscleTone ?? _poorMuscleTone;
    }
    if (!overlayOnly || existing.hrAbove100 != null) {
      _hrAbove100 = existing.hrAbove100 ?? _hrAbove100;
    }
    if (!overlayOnly || existing.initialStepsRequired != null) {
      _initialStepsRequired =
          existing.initialStepsRequired ?? _initialStepsRequired;
    }
    if (existing.enrollmentId.trim().isNotEmpty &&
        !existing.enrollmentId.trim().startsWith("NR-")) {
      setText(
          _enrollmentIdCtrl,
          _formatEnrollmentId(existing.enrollmentId.trim(), _siteCode));
    }
    setText(_randomizationDateCtrl, existing.randomizationDate);
    if (!overlayOnly || existing.notRandomizedReason.isNotEmpty) {
      _notRandomizedReason = existing.notRandomizedReason.isEmpty
          ? _notRandomizedReason
          : existing.notRandomizedReason;
    }
    setText(_notRandomizedOtherCtrl, existing.notRandomizedOther);
  }

  void _applyServerBirthData(BirthResuscitationData d) {
    if ((d.babyUid ?? "").trim().isNotEmpty) {
      _babyUidCtrl.text = d.babyUid!.trim();
    }
    if ((d.babyAdmissionNo ?? "").trim().isNotEmpty) {
      _babyAdmissionCtrl.text = d.babyAdmissionNo!.trim();
    }
    if ((d.babyAnnualNo ?? "").trim().isNotEmpty) {
      _babyAnnualNumberCtrl.text = d.babyAnnualNo!.trim();
    }
    if (d.birthWeight != null) {
      _birthWeightCtrl.text = d.birthWeight.toString();
    }
    if ((d.intrauterineCentile ?? "").trim().isNotEmpty) {
      _growthCentileCtrl.text = d.intrauterineCentile!.trim();
    }
    if (d.dateOfBirth != null) {
      final dob = d.dateOfBirth!;
      _dobController.text =
          "${dob.day.toString().padLeft(2, '0')}/${dob.month.toString().padLeft(2, '0')}/${dob.year}";
    }
    if ((d.timeOfBirth ?? "").trim().isNotEmpty) {
      _timeController.text = _normalizeHms(d.timeOfBirth!);
    }
    if (d.indicationForDelivery.isNotEmpty) {
      _indications = List<String>.from(d.indicationForDelivery);
    }
    if ((d.indicationForDeliveryOther ?? "").trim().isNotEmpty) {
      _indicationOtherCtrl.text = d.indicationForDeliveryOther!.trim();
    }
    if ((d.deliveryMode ?? "").isNotEmpty) {
      _delivery = d.deliveryMode;
      if (_delivery == "Vaginal") {
        _vaginalType = d.vaginalDeliveryType;
      } else if (_delivery == "LSCS") {
        _lscsType = d.lscsType;
      }
    }
    if ((d.gender ?? "").isNotEmpty) _gender = d.gender;
    if (d.requiredResuscitation != null) {
      _requiredResuscitation = d.requiredResuscitation;
    }
    if (d.randomised != null) _randomized = d.randomised;
    if (d.poorRespEfforts != null) _poorRespiratoryEffort = d.poorRespEfforts;
    if (d.poorMuscleTone != null) _poorMuscleTone = d.poorMuscleTone;
    if (d.hrAbove100 != null) _hrAbove100 = d.hrAbove100;
    if (d.initialSteps != null) _initialStepsRequired = d.initialSteps;
    if ((d.enrollmentId ?? "").trim().isNotEmpty) {
      final eid = d.enrollmentId!.trim();
      // Keep nurse-facing enrollment id; hide synthetic NR- keys in the field.
      if (!eid.startsWith("NR-")) {
        _enrollmentIdCtrl.text = _formatEnrollmentId(eid, _siteCode);
      }
    }
    if ((d.randomisationDate ?? "").trim().isNotEmpty) {
      _randomizationDateCtrl.text =
          _isoToDisplayDate(d.randomisationDate!.trim()) ??
              d.randomisationDate!.trim();
    }
    if ((d.enrollmentReasonNotRandomized ?? "").isNotEmpty) {
      _notRandomizedReason = d.enrollmentReasonNotRandomized;
    }
    if ((d.enrollmentReasonNotRandomizedOther ?? "").trim().isNotEmpty) {
      _notRandomizedOtherCtrl.text =
          d.enrollmentReasonNotRandomizedOther!.trim();
    }
  }

  String? _isoToDisplayDate(String iso) {
    try {
      final d = DateTime.parse(iso.split("T").first);
      return "${d.day.toString().padLeft(2, '0')}/"
          "${d.month.toString().padLeft(2, '0')}/"
          "${d.year}";
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadExistingFormB() async {
    final existing = await ApiService().loadFormB(widget.screeningId);

    // Prefer server row when we have an enrollment id (local or NR- fallback).
    String eid = (existing?.enrollmentId ?? "").trim();
    if (eid.isEmpty) eid = "NR-${widget.screeningId}";

    BirthResuscitationData? remote;
    try {
      final json =
          await FormsApiService.instance.loadBirthResuscitation(eid);
      if (json != null) {
        remote = BirthResuscitationData.fromJson(json);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      // Server first (authoritative when online), then local draft overlays
      // non-empty values so offline edits are never lost.
      if (remote != null) _applyServerBirthData(remote);
      if (existing != null) {
        _applyLocalFormB(existing, overlayOnly: remote != null);
      }
    });
  }

  // ============================================================
  // DRAFT / SAVE
  // ============================================================

  FormB _snapshotFormB({String enrollmentId = ""}) {
    return FormB(
      screeningId: widget.screeningId,
      babyUid: _babyUidCtrl.text,
      babyAdmissionNo: _babyAdmissionCtrl.text,
      babyAnnualNo: _babyAnnualNumberCtrl.text,
      birthWeight: _birthWeightCtrl.text,
      intrauterineCentile: _growthCentileCtrl.text,
      dateOfBirth: _dobController.text,
      timeOfBirth: _timeController.text,
      indication: _indications.join(", "),
      indicationOther: _indicationOtherCtrl.text,
      delivery: _delivery ?? "",
      labor: _delivery == "Vaginal"
          ? (_vaginalType ?? "")
          : (_lscsType ?? ""),
      gender: _gender ?? "",
      requiredResuscitation: _requiredResuscitation,
      randomized: _randomized,
      enrollmentId: enrollmentId.isNotEmpty
          ? enrollmentId
          : _enrollmentIdCtrl.text.trim(),
      poorRespiratoryEffort: _poorRespiratoryEffort,
      poorMuscleTone: _poorMuscleTone,
      hrAbove100: _hrAbove100,
      initialStepsRequired: _initialStepsRequired,
      randomizationDate: _randomizationDateCtrl.text,
      notRandomizedReason: _notRandomizedReason ?? "",
      notRandomizedOther: _notRandomizedOtherCtrl.text,
    );
  }

  /// Enrollment id for server sync: typed id, else NR- for not-randomised / no-PPV.
  String _resolveEnrollmentIdForSync() {
    final typed = _enrollmentIdCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    if (_randomized == false || _requiredResuscitation == false) {
      return "NR-${widget.screeningId}";
    }
    return "";
  }

  /// Build B1–B3 BirthResuscitationData for draft/full POST (same keys as web).
  BirthResuscitationData _buildBirthPayload(String enrollmentId) {
    String? randDateIso;
    if (_randomized == true &&
        _randomizationDateCtrl.text.trim().isNotEmpty) {
      randDateIso = _toIsoDate(_randomizationDateCtrl.text.trim());
    }
    final noPpv = _requiredResuscitation == false;
    return BirthResuscitationData()
      ..screeningId = widget.screeningId
      ..enrollmentId = enrollmentId
      ..babyUid = _babyUidCtrl.text.trim().isEmpty
          ? null
          : _babyUidCtrl.text.trim()
      ..babyAdmissionNo = _babyAdmissionCtrl.text.trim().isEmpty
          ? null
          : _babyAdmissionCtrl.text.trim()
      ..babyAnnualNo = _babyAnnualNumberCtrl.text.trim().isEmpty
          ? null
          : _babyAnnualNumberCtrl.text.trim()
      ..dateOfBirth = _parseDobText(_dobController.text)
      ..timeOfBirth = _timeController.text.trim().isEmpty
          ? null
          : _normalizeHms(_timeController.text)
      ..gender = _gender
      ..gestationWeeks = widget.gestWeeks
      ..gestationDays = widget.gestDays
      ..gestationRandWeeks =
          _gestationAtRandomization?.$1 ?? widget.gestWeeks
      ..gestationRandDays =
          _gestationAtRandomization?.$2 ?? widget.gestDays
      ..birthWeight = double.tryParse(_birthWeightCtrl.text)
      ..intrauterineCentile = _growthCentileCtrl.text.trim().isEmpty
          ? null
          : _growthCentileCtrl.text.trim()
      ..deliveryMode = _delivery
      ..vaginalDeliveryType =
          _delivery == "Vaginal" ? _vaginalType : null
      ..lscsType = _delivery == "LSCS" ? _lscsType : null
      ..indicationForDelivery = List<String>.from(_indications)
      ..indicationForDeliveryOther = _indications.contains("Other")
          ? _indicationOtherCtrl.text.trim()
          : null
      ..poorRespEfforts = _poorRespiratoryEffort
      ..poorMuscleTone = _poorMuscleTone
      ..hrAbove100 = _hrAbove100
      ..initialSteps = _initialStepsRequired
      ..requiredResuscitation = _requiredResuscitation
      // Match web: explicit false for no-PPV so status logic is unambiguous.
      ..ppvRequired = noPpv
          ? false
          : (_requiredResuscitation == true ? true : null)
      ..randomised = noPpv
          ? false
          : (_requiredResuscitation == true ? _randomized : null)
      ..randomisationDate = randDateIso
      ..strata = _randomized == true ? _strata : null
      ..enrollmentReasonNotRandomized =
          _randomized == false ? _notRandomizedReason : null
      ..enrollmentReasonNotRandomizedOther =
          _notRandomizedReason == "Other"
              ? _notRandomizedOtherCtrl.text.trim()
              : null;
  }

  Future<void> _saveDraft({bool popAfter = true}) async {
    if (_isFormBEmpty()) {
      if (popAfter && mounted) Navigator.of(context).pop(false);
      return;
    }
    if (_timeController.text.trim().isNotEmpty) {
      _timeController.text = _normalizeHms(_timeController.text);
    }
    if (_birthBeforeScreening) {
      _showMsg(
        "Date & Time of Birth cannot be before the Screening Date & Time recorded in Form A",
      );
      return;
    }
    final eid = _resolveEnrollmentIdForSync();
    final formB = _snapshotFormB(enrollmentId: eid);
    await ApiService().saveFormB(formB);

    // Best-effort server sync when we already have an enrollment / NR- id.
    if (eid.isNotEmpty) {
      try {
        await FormsApiService.instance
            .saveBirthResuscitation(_buildBirthPayload(eid).toJson());
      } catch (_) {
        // Offline / partial — local draft still kept.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Draft saved"),
      backgroundColor: AppTheme.of(context).success,
      behavior: SnackBarBehavior.floating,
    ));
    if (popAfter) Navigator.of(context).pop(true);
  }

  Future<void> _onSaveContinue() async {
    setState(() => _submitted = true);

    if (_dobController.text.isEmpty) { _showMsg("Please select Date of Birth"); return; }
    if (_timeController.text.isEmpty) { _showMsg("Please select Time of Birth"); return; }
    // Persist as HH:MM:SS (web Form B1 / ModernTimeInput).
    _timeController.text = _normalizeHms(_timeController.text);
    if (_birthBeforeScreening) {
      _showMsg(
        "Date & Time of Birth cannot be before the Screening Date & Time recorded in Form A",
      );
      return;
    }
    if (_indications.isEmpty) { _showMsg("Please select at least one indication"); return; }
    if (_indications.contains("Other") && _indicationOtherCtrl.text.trim().isEmpty) {
      _showMsg("Please specify other indication"); return;
    }
    if (_delivery == null) { _showMsg("Please select delivery type"); return; }
    if (_delivery == "Vaginal" && _vaginalType == null) {
      _showMsg("Please select vaginal delivery type"); return;
    }
    if (_delivery == "LSCS" && _lscsType == null) {
      _showMsg("Please select LSCS type"); return;
    }
    if (_gender == null) { _showMsg("Please select gender"); return; }
    if (!_formKey.currentState!.validate()) return;
    if (_poorRespiratoryEffort == null) {
      _showMsg("Please select respiratory effort status"); return;
    }
    if (_poorMuscleTone == null) { _showMsg("Please select muscle tone status"); return; }
    if (_hrAbove100 == null) { _showMsg("Please select HR < 100 status"); return; }
    if (_initialStepsRequired == null) {
      _showMsg("Please select initial steps status"); return;
    }
    // Q23 only when initial steps = Required
    if (_initialStepsRequired == true && _requiredResuscitation == null) {
      _showMsg("Please select whether baby requires ventilation (PPV)"); return;
    }

    // Build shared B1–B3 payload for ALL exits (including end-participation).
    // Backend requires enrollment_id — only randomised cases sync to server.
    if (_requiredResuscitation == true && _randomized == null) {
      _showMsg("Please select randomization status"); return;
    }
    if (_randomized == false && _notRandomizedReason == null) {
      _showMsg("Please select reason for not randomizing"); return;
    }
    if (_notRandomizedReason == "Other" && _notRandomizedOtherCtrl.text.trim().isEmpty) {
      _showMsg("Please specify other reason"); return;
    }
    if (_randomized == true) {
      if (_enrollmentIdCtrl.text.trim().isEmpty ||
          !_isCompleteEnrollmentId(_enrollmentIdCtrl.text.trim())) {
        _showMsg("Enrollment ID must be $_siteCode-A-001 format"); return;
      }
    }

    // Randomised → nurse-entered enrollment ID.
    // Not randomised / no PPV → stable NR-{screeningId} so the row still
    // syncs to the same birth_resuscitation table the web form uses.
    final enrollmentId = _resolveEnrollmentIdForSync();
    if (enrollmentId.isEmpty) {
      _showMsg("Please enter Enrollment ID");
      return;
    }

    final shared = _buildBirthPayload(enrollmentId);
    shared.babyUid = _babyUidCtrl.text.trim().isEmpty
        ? null
        : _babyUidCtrl.text.trim();

    final formB = _snapshotFormB(enrollmentId: enrollmentId);
    await ApiService().saveFormB(formB);

    try {
      await FormsApiService.instance.saveBirthResuscitation(shared.toJson());
    } catch (e) {
      if (!mounted) return;
      _showMsg("Save failed — check connection and try again. ($e)");
      return;
    }

    if (_requiredResuscitation == false) {
      _showParticipationEndedDialog();
      return;
    }

    if (_randomized == false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Form B1 saved and synced (not randomised)"),
        backgroundColor: AppTheme.of(context).success,
      ));
      Navigator.of(context).pop(true);
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormCResuscitationDetails(
          screeningId: widget.screeningId,
          gestation  : widget.gestDays == 0
              ? "${widget.gestWeeks} weeks"
              : "${widget.gestWeeks} weeks ${widget.gestDays} days",
          motherName : widget.motherName,
          babyUid    : _babyUidCtrl.text.trim(),
          formB      : formB,
          shared     : shared,
        ),
      ),
    ).then((result) {
      if (result == true && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  /// Parses the DOB display text ("DD/MM/YY") back to a DateTime for the
  /// backend payload. Returns null on any parse failure.
  DateTime? _parseDobText(String s) {
    if (s.isEmpty) return null;
    final parts = s.split("/");
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final yy = int.tryParse(parts[2]);
    if (d == null || m == null || yy == null) return null;
    final year = yy < 100 ? 2000 + yy : yy;
    return DateTime(year, m, d);
  }

  /// Screening datetime from Form A — ISO or DD/MM/YYYY[ HH:mm[:ss]].
  /// Includes time when present (required for birth-before-screening check).
  DateTime? _parseScreeningDateTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;

    final m = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(t);
    if (m != null) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final yRaw = int.tryParse(m.group(3)!);
      if (d == null || mo == null || yRaw == null) return null;
      final y = yRaw < 100 ? 2000 + yRaw : yRaw;
      final hh = int.tryParse(m.group(4) ?? '0') ?? 0;
      final mm = int.tryParse(m.group(5) ?? '0') ?? 0;
      final ss = int.tryParse(m.group(6) ?? '0') ?? 0;
      return DateTime(y, mo, d, hh, mm, ss);
    }

    // YYYY-MM-DD[ HH:mm[:ss]]
    final ymd = RegExp(
      r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(t);
    if (ymd != null) {
      final y = int.tryParse(ymd.group(1)!);
      final mo = int.tryParse(ymd.group(2)!);
      final d = int.tryParse(ymd.group(3)!);
      if (y == null || mo == null || d == null) return null;
      final hh = int.tryParse(ymd.group(4) ?? '0') ?? 0;
      final mm = int.tryParse(ymd.group(5) ?? '0') ?? 0;
      final ss = int.tryParse(ymd.group(6) ?? '0') ?? 0;
      return DateTime(y, mo, d, hh, mm, ss);
    }
    return null;
  }

  /// Accepts D/M/YYYY or DD/MM/YYYY (or already ISO) → YYYY-MM-DD for web date inputs.
  String? _toIsoDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return t;
    final parts = t.split(RegExp(r'[/-]'));
    if (parts.length != 3) return t;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return t;
    final year = y < 100 ? 2000 + y : y;
    return '${year.toString().padLeft(4, '0')}-'
        '${m.toString().padLeft(2, '0')}-'
        '${d.toString().padLeft(2, '0')}';
  }

  /// Normalize clock time to HH:MM:SS (web Form B1). HH:MM → HH:MM:00.
  String _normalizeHms(String value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$')
        .firstMatch(value.trim());
    if (m == null) return value.trim();
    final hh = m.group(1)!.padLeft(2, '0');
    final mm = m.group(2)!;
    final ss = (m.group(3) ?? '00').padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  /// Parse HH:MM[:SS] into hour/minute/second; falls back to now.
  ({int hour, int minute, int second}) _parseHms(String value) {
    final now = TimeOfDay.now();
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$')
        .firstMatch(value.trim());
    if (m == null) {
      return (hour: now.hour, minute: now.minute, second: 0);
    }
    return (
      hour: int.tryParse(m.group(1)!) ?? now.hour,
      minute: int.tryParse(m.group(2)!) ?? now.minute,
      second: int.tryParse(m.group(3) ?? '0') ?? 0,
    );
  }

  /// Clock-time picker with seconds (matches web ModernTimeInput HH:MM:SS).
  Future<({int hour, int minute, int second})?> _pickTimeHms(
    BuildContext context, {
    required ({int hour, int minute, int second}) initial,
  }) {
    int hh = initial.hour.clamp(0, 23);
    int mm = initial.minute.clamp(0, 59);
    int ss = initial.second.clamp(0, 59);
    final c = AppTheme.of(context);

    return showDialog<({int hour, int minute, int second})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: c.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.access_time_rounded,
                  color: c.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Text("Time of Birth",
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Center(
                      child: Text("Hours",
                          style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
              const SizedBox(width: 20),
              Expanded(
                  child: Center(
                      child: Text("Minutes",
                          style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
              const SizedBox(width: 20),
              Expanded(
                  child: Center(
                      child: Text("Seconds",
                          style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _timeSpinner(
                      hh, 0, 23, c, (v) => setDlg(() => hh = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":",
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                  child: _timeSpinner(
                      mm, 0, 59, c, (v) => setDlg(() => mm = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":",
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                  child: _timeSpinner(
                      ss, 0, 59, c, (v) => setDlg(() => ss = v))),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.primary.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  "${hh.toString().padLeft(2, '0')}:"
                  "${mm.toString().padLeft(2, '0')}:"
                  "${ss.toString().padLeft(2, '0')}",
                  style: TextStyle(
                      color: c.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel",
                  style: TextStyle(
                      color: c.textTertiary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () =>
                  Navigator.pop(ctx, (hour: hh, minute: mm, second: ss)),
              child: const Text("Confirm",
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeSpinner(
      int value, int min, int max, AppColors c, void Function(int) onChange) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => onChange(value < max ? value + 1 : min),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.primary.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Icon(Icons.keyboard_arrow_up_rounded,
                color: c.primary, size: 20),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(value.toString().padLeft(2, '0'),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        GestureDetector(
          onTap: () => onChange(value > min ? value - 1 : max),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.primary.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: c.primary, size: 20),
          ),
        ),
      ]),
    );
  }

  void _showMsg(String msg) {
    final c = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior        : SnackBarBehavior.floating,
        backgroundColor : c.surface,
        margin          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape           : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.danger.withOpacity(0.4))),
        content: Row(children: [
          Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: TextStyle(color: c.textPrimary, fontSize: 13))),
        ]),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showParticipationEndedDialog() {
    final c = AppTheme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(Icons.cancel_rounded, color: c.danger, size: 22),
          const SizedBox(width: 10),
          Text("Participation Ended",
              style: TextStyle(
                  color: c.danger, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Text(
          "No resuscitation beyond initial steps was required.\n\nTrial participation ends here.",
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: c.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRandomizationDate() async {
    final picked = await showModernDatePicker(
      context  : context,
      firstDate: DateTime(2020),
      lastDate : DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (picked != null) {
      _randomizationDateCtrl.text =
          "${picked.day}/${picked.month}/${picked.year}";
    }
  }

  // ============================================================
  // THEME-AWARE HELPERS  (aligned with Form A style)
  // ============================================================

  InputDecoration _input(String label, AppColors c, {String? helper}) {
    final labelStyle = TextStyle(color: c.textSecondary, fontSize: 13);
    return InputDecoration(
      label        : requiredLabel(label, style: labelStyle),
      helperText   : helper,
      helperStyle  : TextStyle(color: c.textTertiary, fontSize: 11),
      labelStyle   : labelStyle,
      floatingLabelStyle: labelStyle,
      filled       : true,
      fillColor    : c.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.danger, width: 1.5)),
    );
  }

  /// Read-only info tile — identical to Form A style
  Widget _infoTile(String label, String value, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: c.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      ]),
    );
  }

  /// Section card — exact Form A signature & style.
  /// Collapsible sections pass a TextButton as [trailing].
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    required AppColors c,
    Widget? trailing,
    Color? accentColor,
  }) {
    final color = accentColor ?? c.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: c.borderLight)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: .4)),
            if (trailing != null) ...[const Spacer(), trailing],
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ]),
    );
  }

  /// Reusable bool choice chip row
  Widget _boolChoiceChip({
    required String title,
    required String trueLabel,
    required String falseLabel,
    required bool? value,
    required void Function(bool) onChanged,
    required AppColors c,
    Color? trueColor,
    Color? falseColor,
  }) {
    final tColor     = trueColor  ?? c.danger;
    final fColor     = falseColor ?? c.success;
    final showError  = _submitted && value == null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      requiredLabel(
        title,
        style: TextStyle(
            color: c.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _chip(trueLabel,  value == true,  tColor, c, () => onChanged(true)),
        const SizedBox(width: 10),
        _chip(falseLabel, value == false, fColor, c, () => onChanged(false)),
      ]),
      if (showError)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text("Required",
              style: TextStyle(color: c.danger, fontSize: 11)),
        ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _chip(String label, bool selected, Color color, AppColors c,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : c.border, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : c.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ),
    );
  }

  /// Compact pill-style radio group
  Widget _pillRadio({
    required String title,
    required List<String> options,
    required String? value,
    required void Function(String) onChanged,
    required AppColors c,
    bool showError = false,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      requiredLabel(
        title,
        style: TextStyle(
            color: c.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((opt) {
          final sel = value == opt;
          return GestureDetector(
            onTap: () => setState(() => onChanged(opt)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? c.primary : c.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: sel ? c.primary : c.border, width: 1.5),
                boxShadow: sel
                    ? [
                        BoxShadow(
                            color: c.primary.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2))
                      ]
                    : [],
              ),
              child: Text(opt,
                  style: TextStyle(
                      color: sel ? Colors.white : c.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          );
        }).toList(),
      ),
      if (showError)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 14),
    ]);
  }

  /// Date / time picker tile
  Widget _dateTile({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required AppColors c,
    required VoidCallback onTap,
  }) {
    final filled = controller.text.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      requiredLabel(
        label,
        style: TextStyle(
            color: c.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _submitted && !filled
                  ? c.danger
                  : filled
                      ? c.success.withOpacity(0.5)
                      : c.border,
              width: 1.5,
            ),
          ),
          child: Row(children: [
            Icon(icon,
                color: filled ? c.success : c.textTertiary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                filled ? controller.text : hint,
                style: TextStyle(
                    color: filled ? c.textPrimary : c.textTertiary,
                    fontSize: 13),
              ),
            ),
            if (filled)
              Icon(Icons.check_circle_rounded,
                  color: c.success, size: 16),
          ]),
        ),
      ),
      if (_submitted && !filled)
        Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
    ]);
  }

  /// Sub-section label — matches Form A's "Baby Details" divider style
  Widget _subLabel(String text, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: c.primary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .3)),
      ]),
    );
  }

  /// Strata info banner (used in Randomization section)
  Widget _strataBanner(AppColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.primary.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.layers_rounded, color: c.primary, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("27. Strata (auto, from Gestation at Randomization)",
                  style: TextStyle(color: c.textTertiary, fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_strata,
                  style: TextStyle(
                      color: c.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ],
          ),
        ),
      ]),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _buildAppBar(c),
      bottomNavigationBar: widget.viewOnly ? null : _buildBottomBar(c),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.bgGradTop, c.bg],
            stops: const [0.0, 0.35],
          ),
        ),
        child: AbsorbPointer(
          absorbing: widget.viewOnly,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Form(
              key: _formKey,
              child: Column(children: [
                if (widget.viewOnly) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.primary.withOpacity(0.35)),
                    ),
                    child: Row(children: [
                      Icon(Icons.visibility_rounded, color: c.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text("View only — previously filled Form B1",
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ]),
                  ),
                ],
                _buildIdentificationSection(c),
              _buildBirthDetailsSection(c),
              _buildConditionSection(c),
              if (_requiredResuscitation == false) _buildEndParticipationBanner(c),
              if (_requiredResuscitation == true) _buildRandomizationSection(c),
              const SizedBox(height: 20),
            ]),
          ),
        ),
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(AppColors c) {
    return AppBar(
      backgroundColor   : c.surface,
      elevation         : 0,
      surfaceTintColor  : Colors.transparent,
      toolbarHeight     : 66,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.borderLight),
      ),
      title: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Form B1: Birth & Resuscitation (1–28)",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                letterSpacing: .3)),
        const SizedBox(height: 2),
        Text("Complete for all consented subjects",
            style: TextStyle(
                fontSize: 11,
                color: c.primary.withOpacity(0.7),
                fontWeight: FontWeight.w500)),
      ]),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
    );
  }

  // ── Sticky bottom bar ──────────────────────────────────────────────────────

  Widget _buildBottomBar(AppColors c) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.borderLight)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -3))
          ],
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.save_outlined, size: 15, color: c.warning),
              label: Text("Save for Later",
                  style: TextStyle(
                      color: c.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              onPressed: () => _saveDraft(popAfter: true),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.warning.withOpacity(0.5)),
                backgroundColor: c.warningSoft,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Colors.white),
              label: const Text("Save",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              onPressed: _onSaveContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _saveDraft(popAfter: true),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("Cancel",
                  style: TextStyle(
                      color: c.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── IDENTIFICATION ─────────────────────────────────────────────────────────

  Widget _buildIdentificationSection(AppColors c) {
    return _sectionCard(
      title      : "B1 · Identification",
      icon       : Icons.badge_rounded,
      accentColor: c.primary,
      c          : c,
      children   : [
        // Web order: 1 → 2 → 3 → 4 → 5 → 5 → 6 → 7
        Row(children: [
          Expanded(child: _infoTile("1. Screening ID", widget.screeningId, c)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile("2. Maternal UID", widget.maternalUid, c)),
        ]),
        const SizedBox(height: 10),
        _infoTile("3. Mother's First Name", widget.motherName, c),
        const SizedBox(height: 14),

        // 4. Baby UID — optional until the hospital file exists
        TextFormField(
          controller: _babyUidCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: _input("4. Baby UID", c).copyWith(
            hintText: "Not assigned yet",
            helperText: _babyUidMaxReached
                ? "Maximum 12 digits reached"
                : "Optional — fill when assigned (up to 12 digits)",
            helperStyle: TextStyle(
                color: _babyUidMaxReached ? c.success : c.textTertiary,
                fontSize: 11),
          ),
          style: TextStyle(color: c.textPrimary),
          onChanged: (v) =>
              setState(() => _babyUidMaxReached = v.length == 12),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            if (!RegExp(r'^\d+$').hasMatch(v)) return "Digits only";
            if (v.length > 12) return "Baby UID cannot exceed 12 digits";
            return null;
          },
        ),
        const SizedBox(height: 12),

        // 5. Mobile numbers (same number on web for both)
        Row(children: [
          Expanded(child: _infoTile("5. Mobile No. — Mother",  widget.motherPhone,  c)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile("5. Mobile No. — Husband", widget.husbandPhone, c)),
        ]),
        const SizedBox(height: 12),

        // 6. Site-specific admission / MRD
        TextFormField(
          controller: _babyAdmissionCtrl,
          readOnly: _siteName == 'IOG',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_babyAdmissionRule.max),
          ],
          decoration: _input(
            _babyAdmissionRule.label,
            c,
          ).copyWith(hintText: _babyAdmissionRule.placeholder),
          style: TextStyle(color: c.textPrimary),
          // Optional until the baby's hospital file exists. Length range is
          // still enforced once a value is present.
          validator: (v) {
            final rule = _babyAdmissionRule;
            final val  = (v ?? "").trim();
            if (val.isEmpty) return null;
            if (!RegExp('^\\d{${rule.min},${rule.max}}\$').hasMatch(val)) {
              return rule.min == rule.max
                  ? "Must be ${rule.max} digits"
                  : "Must be ${rule.min}-${rule.max} digits";
            }
            return null;
          },
        ),
        const SizedBox(height: 12),

        // GMCH / GMCH-A (and any site not in _kBabyAnnualRules) have no
        // equivalent number — babyAnnualRule is null on web and the field
        // is not rendered at all.
        if (_babyAnnualRule != null)
          TextFormField(
            controller: _babyAnnualNumberCtrl,
            keyboardType: _babyAnnualRule!.numeric
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: [
              if (_babyAnnualRule!.numeric)
                FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_babyAnnualRule!.max),
            ],
            decoration: _input(_babyAnnualRule!.label, c)
                .copyWith(hintText: _babyAnnualRule!.placeholder),
            style: TextStyle(color: c.textPrimary),
            // Mirrors web: length range is only enforced for numeric rules
            // (AMC's logbook serial is free text with no length check at
            // submit, exactly like BirthResuscitationForm.jsx validate()).
            validator: (v) {
              final rule = _babyAnnualRule!;
              final val  = (v ?? "").trim();
              if (rule.numeric &&
                  val.isNotEmpty &&
                  !RegExp('^\\d{${rule.min},${rule.max}}\$').hasMatch(val)) {
                return rule.min == rule.max
                    ? "Must be ${rule.max} digits"
                    : "Must be ${rule.min}-${rule.max} digits";
              }
              return null;
            },
          ),
      ],
    );
  }

  // ── BIRTH DETAILS ──────────────────────────────────────────────────────────

  Widget _buildBirthDetailsSection(AppColors c) {
    return _sectionCard(
      title      : "B2 · Birth Details",
      icon       : Icons.child_care_rounded,
      accentColor: c.success,
      c          : c,
      // Web serial order: 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16/17 → 18
      children   : [
        _dateTile(
          label     : "8. Date of Birth *",
          hint      : "Select date (DD/MM/YY)",
          controller: _dobController,
          icon      : Icons.calendar_today_rounded,
          c         : c,
          onTap     : () async {
            final screening = _parseScreeningDateTime(_screeningDateTime);
            final first = screening != null
                ? DateTime(screening.year, screening.month, screening.day)
                : DateTime(2000);
            final now = DateTime.now();
            final initial = _parseDobText(_dobController.text) ??
                (first.isAfter(now) ? now : now);
            final picked = await showModernDatePicker(
              context    : context,
              initialDate: initial.isBefore(first) ? first : initial,
              firstDate  : first,
              lastDate   : now.isBefore(first) ? first : now,
            );
            if (picked != null) {
              setState(() {
                _dobController.text =
                    "${picked.day.toString().padLeft(2, '0')}/"
                    "${picked.month.toString().padLeft(2, '0')}/"
                    "${picked.year.toString().substring(2)}";
              });
            }
          },
        ),
        const SizedBox(height: 14),

        _dateTile(
          label     : "9. Time of Birth *",
          hint      : "Select time (HH:MM:SS)",
          controller: _timeController,
          icon      : Icons.access_time_rounded,
          c         : c,
          onTap     : () async {
            final picked = await _pickTimeHms(
              context,
              initial: _parseHms(_timeController.text),
            );
            if (picked != null) {
              setState(() {
                _timeController.text =
                    "${picked.hour.toString().padLeft(2, '0')}:"
                    "${picked.minute.toString().padLeft(2, '0')}:"
                    "${picked.second.toString().padLeft(2, '0')}";
              });
            }
          },
        ),
        if (_birthBeforeScreening) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.danger.withOpacity(0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Date & Time of Birth cannot be before the Screening Date & Time recorded in Form A.",
                    style: TextStyle(
                      color: c.danger,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),

        _pillRadio(
          title    : "10. Gender *",
          options  : const ["Female", "Male", "DSD"],
          value    : _gender,
          onChanged: (v) => setState(() => _gender = v),
          c        : c,
          showError: _submitted && _gender == null,
        ),

        _infoTile(
            "11. Gestation at Screening (auto)",
            "${widget.gestWeeks}w ${widget.gestDays}d",
            c),
        const SizedBox(height: 10),
        _infoTile(
            "12. Gestation at Randomization (auto from Form A and DOB)",
            _gestationRandDisplay,
            c),
        const SizedBox(height: 14),

        TextFormField(
          controller: _birthWeightCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: _input("13. Birth Weight (g) *", c),
          style: TextStyle(color: c.textPrimary),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return "Birth weight is required";
            final w = int.tryParse(v);
            if (w == null) return "Enter a valid number";
            if (w < 300)   return "Too low (min 300 g)";
            if (w > 6000)  return "Too high (max 6000 g)";
            return null;
          },
        ),
        const SizedBox(height: 14),

        TextFormField(
          controller: _growthCentileCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration:
              _input("14. Intrauterine Growth Status (centile, auto)", c),
          style: TextStyle(color: c.textPrimary),
          validator: (v) {
            if (v != null && v.trim().isNotEmpty) {
              final val = double.tryParse(v);
              if (val == null)          return "Enter a valid number";
              if (val < 0 || val > 100) return "Centile must be 0–100";
            }
            return null;
          },
        ),
        const SizedBox(height: 14),

        _pillRadio(
          title    : "15. Delivery Mode *",
          options  : const ["Vaginal", "LSCS"],
          value    : _delivery,
          onChanged: (v) => setState(() {
            _delivery    = v;
            _vaginalType = null;
            _lscsType    = null;
          }),
          c        : c,
          showError: _submitted && _delivery == null,
        ),

        if (_delivery == "Vaginal")
          _pillRadio(
            title    : "16. Vaginal Delivery Type *",
            options  : const ["Spontaneous", "Augmented", "Induced"],
            value    : _vaginalType,
            onChanged: (v) => setState(() => _vaginalType = v),
            c        : c,
            showError: _submitted && _vaginalType == null,
          ),

        if (_delivery == "LSCS")
          _pillRadio(
            title    : "17. LSCS Type *",
            options  : const ["Emergency", "Elective"],
            value    : _lscsType,
            onChanged: (v) => setState(() => _lscsType = v),
            c        : c,
            showError: _submitted && _lscsType == null,
          ),

        requiredLabel(
          "18. Indication (select all that apply) *",
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...[
          "pPROM",
          "PTL",
          "APH",
          "Placenta Previa",
          "PIH",
          "PE/Imminent Eclampsia",
          "Other",
        ].map((opt) {
          final sel = _indications.contains(opt);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (sel) {
                  _indications.remove(opt);
                  if (opt == "Other") _indicationOtherCtrl.clear();
                } else {
                  _indications.add(opt);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? c.primary : c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? c.primaryDark : c.border,
                  width: sel ? 2 : 1.5,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: c.primary.withOpacity(0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: sel ? Colors.white : c.border,
                      width: 2,
                    ),
                    color: sel ? Colors.white : Colors.transparent,
                  ),
                  child: sel
                      ? Icon(Icons.check, color: c.primary, size: 13)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: sel ? Colors.white : c.textSecondary,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
        if (_submitted && _indications.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("Select at least one indication",
                  style: TextStyle(color: c.danger, fontSize: 11))),
        if (_indications.contains("Other")) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _indicationOtherCtrl,
            decoration: _input("Specify other indication *", c),
            style: TextStyle(color: c.textPrimary),
            validator: (v) {
              if (_indications.contains("Other") &&
                  (v == null || v.trim().isEmpty)) return "Required";
              return null;
            },
          ),
        ],
      ],
    );
  }

  // ── CONDITION AT BIRTH ─────────────────────────────────────────────────────

  Widget _buildConditionSection(AppColors c) {
    return _sectionCard(
      title      : "B3 · Condition at Birth & Randomization",
      icon       : Icons.monitor_heart_rounded,
      accentColor: c.warning,
      c          : c,
      // Collapse toggle as trailing TextButton — matches Form A pattern
      trailing: TextButton.icon(
        onPressed: () =>
            setState(() => _conditionExpanded = !_conditionExpanded),
        icon: AnimatedRotation(
          turns   : _conditionExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child   : Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: c.textSecondary),
        ),
        label: Text(
          _conditionExpanded ? "Collapse" : "Expand",
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
        style: TextButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      ),
      children: _conditionExpanded
          ? [
              _boolChoiceChip(
                title     : "19. Respiratory effort",
                trueLabel : "Absent/poor",
                falseLabel: "Normal",
                value     : _poorRespiratoryEffort,
                onChanged : (v) =>
                    setState(() => _poorRespiratoryEffort = v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              _boolChoiceChip(
                title     : "20. Muscle tone",
                trueLabel : "Limp/poor",
                falseLabel: "Normal",
                value     : _poorMuscleTone,
                onChanged : (v) => setState(() => _poorMuscleTone = v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              // CRF asks HR < 100; stored inverted as hr_above_100 (same as web).
              _boolChoiceChip(
                title     : "21. HR < 100",
                trueLabel : "YES",
                falseLabel: "NO",
                value     : _hrAbove100 == null ? null : !_hrAbove100!,
                onChanged : (v) => setState(() => _hrAbove100 = !v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              _boolChoiceChip(
                title     : "22. Initial steps",
                trueLabel : "Required",
                falseLabel: "Not required",
                value     : _initialStepsRequired,
                onChanged : (v) => setState(() {
                  _initialStepsRequired = v;
                  // Q23 only applies when initial steps are required.
                  if (v) {
                    _requiredResuscitation = null;
                  } else {
                    _requiredResuscitation = false;
                    _randomized = null;
                    _notRandomizedReason = null;
                    _notRandomizedOtherCtrl.clear();
                  }
                }),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              if (_initialStepsRequired == true)
                _boolChoiceChip(
                  title     : "23. Does baby require ventilation (PPV)?",
                  trueLabel : "Required",
                  falseLabel: "Not required",
                  value     : _requiredResuscitation,
                  onChanged : (v) =>
                      setState(() => _requiredResuscitation = v),
                  trueColor : c.danger,
                  falseColor: c.success,
                  c         : c,
                ),
            ]
          : [],
    );
  }

  // ── END PARTICIPATION BANNER ───────────────────────────────────────────────

  Widget _buildEndParticipationBanner(AppColors c) {
    return Container(
      margin  : const EdgeInsets.only(bottom: 16),
      padding : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color        : c.dangerSoft,
        borderRadius : BorderRadius.circular(14),
        border       : Border.all(color: c.danger.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: c.danger.withOpacity(0.15), shape: BoxShape.circle),
          child: Icon(Icons.cancel_rounded, color: c.danger, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Trial Participation Ends Here",
                style: TextStyle(
                    color: c.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            const SizedBox(height: 3),
            Text("No ventilation (PPV) required — end participation.",
                style: TextStyle(
                    color: c.danger.withOpacity(0.75), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  // ── RANDOMIZATION ──────────────────────────────────────────────────────────

  Widget _buildRandomizationSection(AppColors c) {
    return _sectionCard(
      title      : "Randomization details",
      icon       : Icons.shuffle_rounded,
      accentColor: c.purple,
      c          : c,
      trailing: TextButton.icon(
        onPressed: () => setState(
            () => _randomizationExpanded = !_randomizationExpanded),
        icon: AnimatedRotation(
          turns   : _randomizationExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child   : Icon(Icons.keyboard_arrow_down_rounded,
              size: 16, color: c.textSecondary),
        ),
        label: Text(
          _randomizationExpanded ? "Collapse" : "Expand",
          style: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
        style: TextButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      ),
      children: _randomizationExpanded
          ? [
              _boolChoiceChip(
                title     : "24. Randomised?",
                trueLabel : "Yes",
                falseLabel: "No",
                value     : _randomized,
                onChanged : (v) => setState(() {
                  _randomized           = v;
                  _notRandomizedReason  = null;
                  _notRandomizedOtherCtrl.clear();
                  if (v) _ensureEnrollmentIdPrefix();
                }),
                trueColor : c.success,
                falseColor: c.danger,
                c         : c,
              ),

              // ── Randomized = YES ──────────────────────────────────────
              if (_randomized == true) ...[
                TextFormField(
                  controller: _randomizationDateCtrl,
                  readOnly  : true,
                  onTap     : _pickRandomizationDate,
                  decoration: _input("25. Randomization Date *", c).copyWith(
                    suffixIcon: Icon(Icons.calendar_today_rounded,
                        color: c.textTertiary, size: 18),
                  ),
                  style    : TextStyle(color: c.textPrimary),
                  validator: (v) =>
                      v == null || v.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _enrollmentIdCtrl,
                  decoration: _input("26. Enrollment ID *", c).copyWith(
                    hintText: "$_siteCode-A-001",
                    helperText: "Site $_siteCode · letter A–D · 3-digit serial",
                    helperMaxLines: 1,
                  ),
                  style: TextStyle(
                      color: c.textPrimary,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    _EnrollmentIdInputFormatter(_siteCode),
                  ],
                  onTap: _ensureEnrollmentIdPrefix,
                  validator: (v) {
                    if (_randomized != true) return null;
                    final t = (v ?? "").trim();
                    if (t.isEmpty || t == "$_siteCode-") {
                      return "Required";
                    }
                    if (!_isCompleteEnrollmentId(t)) {
                      return "Format: $_siteCode-A-001";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _strataBanner(c),
              ],

              // ── Randomized = NO ───────────────────────────────────────
              if (_randomized == false) ...[
                requiredLabel(
                  "28. Reason Not Randomized *",
                  style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...[
                  "GA ≥ 32 weeks",
                  "Trial nurse could not reach",
                  "Non-trial location",
                  "Missed delivery",
                  "Multiple deliveries",
                  "Consent withdrawn",
                  "Other",
                ].map((opt) {
                  final sel = _notRandomizedReason == opt;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _notRandomizedReason = opt),
                    child: Container(
                      margin : const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color       : sel ? c.primarySoft : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? c.primary : c.border),
                      ),
                      child: Row(children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape : BoxShape.circle,
                            border: Border.all(
                                color: sel ? c.primary : c.border,
                                width: 2),
                            color: sel
                                ? c.primary
                                : Colors.transparent,
                          ),
                          child: sel
                              ? const Icon(Icons.circle,
                                  color: Colors.white, size: 8)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(opt,
                            style: TextStyle(
                                color: sel
                                    ? c.primary
                                    : c.textSecondary,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13)),
                      ]),
                    ),
                  );
                }).toList(),
                if (_notRandomizedReason == "Other") ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notRandomizedOtherCtrl,
                    decoration: _input("28. Specify other reason *", c),
                    style: TextStyle(color: c.textPrimary),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Required" : null,
                  ),
                ],
              ],
            ]
          : [],
    );
  }
}