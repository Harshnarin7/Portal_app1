import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'form_c_resuscitation.dart';
import '../data/intergrowth_very_preterm.dart';
import '../models/form_b.dart';
import '../models/form_c.dart';
import '../models/birth_resuscitation.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../services/screening_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/required_asterisk.dart';
import '../widgets/field_logic_badge.dart';
import '../utils/clock_time_24.dart';
import '../data/form_b_indications.dart';
import '../models/crf.dart';
import '../services/pdf_service.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';

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

String _normalizeSiteKey(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return "";
  if (t.toUpperCase().startsWith("PGIMER")) return "PGIMER";
  if (_kBabyAdmissionRules.containsKey(t) || _kBabyAnnualRules.containsKey(t)) {
    return t;
  }
  if (_kSiteCodeToName.containsValue(t)) return t;
  return _kSiteCodeToName[t] ?? t;
}

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
  bool _isSaved           = false;
  bool _isEditing         = false;
  bool _babyUidMaxReached = false;
  String _babyUidDuplicateMsg = '';
  Timer? _babyUidCheckTimer;
  String _enrollmentDuplicateMsg = '';

  // ── Randomization ─────────────────────────────────────────────────────────
  bool? _randomized;
  String? _notRandomizedReason;

  /// Screening datetime used for GA-at-randomization (may be loaded from API).
  String _screeningDateTime = "";

  /// Last INTERGROWTH value we auto-set for Q14 — never clobber a nurse override.
  String? _lastAutoCentile;

  /// Form A formula: locked after an explicit Save, or when the caller asked
  /// for view-only. `_isEditing` stays false unless an Edit control flips it.
  bool get _formReadOnly => (_isSaved || widget.viewOnly) && !_isEditing;

  bool get _showEditAction => _isSaved || widget.viewOnly;

  /// Combined Form B print — web Print is gated on a full save; here both
  /// B1 and B2 must be filled (B2 = explicitly_saved + B4–B6 data).
  bool get _formBExportEnabled => _isSaved && _b2Complete && !_exportingPdf;

  bool _exportingPdf = false;
  bool _b2Complete = false;

  // ── Auto-strata from Gestation at Randomization (web Form B) ───────────────
  /// Null unless Randomised = Yes and Q12 is known (web does not fall back
  /// to screening GA).
  String? get _strata {
    if (_randomized != true) return null;
    final rand = _gestationAtRandomization;
    if (rand == null) return null;
    final totalDays = rand.$1 * 7 + rand.$2;
    return totalDays < (28 * 7) ? "< 28 weeks" : "≥ 28 – 31 weeks";
  }

  /// screening GA + elapsed calendar days (DOB − screening date), same as web.
  /// Uses the YYYY-MM-DD (or DD/MM/YYYY) date prefix only — never DateTime.tryParse
  /// on an ISO-Z string, which can shift the calendar day.
  (int weeks, int days)? get _gestationAtRandomization {
    final dob = _parseDobText(_dobController.text);
    if (dob == null) return null;
    final screeningDay = _calendarDateFromRaw(_screeningDateTime);
    if (screeningDay == null) return null;
    // Web skips the effect when gestation_weeks is falsy (0 / empty).
    if (widget.gestWeeks <= 0) return null;

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

  /// Validates combined DOB + TOB (web Form B save / handleTimeOfBirthChange rules).
  String? _birthDateTimeValidationMessage({
    int? hour,
    int? minute,
    int? second,
  }) {
    final dob = _parseDobText(_dobController.text);
    if (dob == null) return null;
    final dobDay = _dateOnly(dob);
    if (dobDay.isAfter(_todayDateOnly)) {
      return 'Date of Birth cannot be in the future';
    }
    final DateTime? birth;
    if (hour != null) {
      birth = DateTime(
        dob.year,
        dob.month,
        dob.day,
        hour,
        minute ?? 0,
        second ?? 0,
      );
    } else {
      if (_timeController.text.trim().isEmpty) return null;
      birth = _birthDateTime;
    }
    if (birth == null) return null;
    if (birth.isAfter(DateTime.now())) {
      return 'Time of Birth cannot be in the future';
    }
    final screening = _parseScreeningDateTime(_screeningDateTime);
    if (screening != null && birth.isBefore(screening)) {
      return 'Cannot be before the Screening Date & Time (Form A)';
    }
    return null;
  }

  /// Live check (same as web BirthResuscitationForm birthBeforeScreening).
  bool get _birthBeforeScreening {
    final msg = _birthDateTimeValidationMessage();
    return msg != null && msg.contains('Screening');
  }

  String? get _birthDateTimeBannerMessage => _birthDateTimeValidationMessage();

  String get _gestationRandDisplay {
    final rand = _gestationAtRandomization;
    if (rand == null) return "—";
    return "${rand.$1}w ${rand.$2}d";
  }

  // ── Site-specific rules for Baby Admission No. / Baby Annual No. ──────────
  // Web keys by site name ("PGIMER"); callers may pass name OR site code ("01").
  String get _siteName => _normalizeSiteKey(widget.siteId);

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
  bool _conditionExpanded = true;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _isSaved = widget.viewOnly;
    _isEditing = !_isSaved;
    _screeningDateTime = widget.screeningDateTime.trim();
    // IOG: Baby Admission No. mirrors Baby UID live (matches web's
    // BirthResuscitationForm.jsx useEffect ~L497-502, which keeps
    // baby_admission_no synced to baby_uid on every change for site IOG).
    if (_siteName == 'IOG') {
      _babyUidCtrl.addListener(_syncBabyAdmissionFromUid);
      _syncBabyAdmissionFromUid();
    }
    _babyUidCtrl.addListener(_scheduleBabyUidDuplicateCheck);
    _enrollmentIdCtrl.addListener(_scheduleEnrollmentDuplicateCheck);
    _birthWeightCtrl.addListener(_onAutoCentileInputsChanged);
    _dobController.addListener(_onAutoCentileInputsChanged);
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

  String _enrollmentIdForBabyUidCheck() {
    final e = _enrollmentIdCtrl.text.trim();
    if (e.length >= 5 && e.contains('-')) return e;
    if (_randomized == false || _requiredResuscitation == false) {
      return 'NR-${widget.screeningId}';
    }
    return e;
  }

  void _scheduleBabyUidDuplicateCheck() {
    _babyUidCheckTimer?.cancel();
    final uid = _babyUidCtrl.text.trim();
    if (uid.isEmpty || !RegExp(r'^\d{1,12}$').hasMatch(uid)) {
      if (_babyUidDuplicateMsg.isNotEmpty) {
        setState(() => _babyUidDuplicateMsg = '');
      }
      return;
    }
    _babyUidCheckTimer = Timer(const Duration(milliseconds: 50), () async {
      try {
        final eid = _enrollmentIdForBabyUidCheck();
        final res = await FormsApiService.instance.checkBabyUidDuplicate(
          babyUid: uid,
          screeningId: widget.screeningId,
          enrollmentId: eid.isEmpty ? null : eid,
        );
        if (!mounted) return;
        if (res['duplicate'] == true) {
          setState(() {
            _babyUidDuplicateMsg = (res['message'] ??
                    'This Baby UID is already used at this site.')
                .toString();
          });
        } else if (_babyUidDuplicateMsg.isNotEmpty) {
          setState(() => _babyUidDuplicateMsg = '');
        }
      } catch (_) {
        if (mounted && _babyUidDuplicateMsg.isNotEmpty) {
          setState(() => _babyUidDuplicateMsg = '');
        }
      }
    });
  }

  Future<void> _scheduleEnrollmentDuplicateCheck() async {
    final eid = _enrollmentIdCtrl.text.trim().toUpperCase();
    if (!_isCompleteEnrollmentId(eid)) {
      if (_enrollmentDuplicateMsg.isNotEmpty) {
        setState(() => _enrollmentDuplicateMsg = '');
      }
      _scheduleBabyUidDuplicateCheck();
      return;
    }
    try {
      final res = await FormsApiService.instance.checkEnrollmentIdDuplicate(
        enrollmentId: eid,
        screeningId: widget.screeningId,
      );
      if (!mounted) return;
      if (res['duplicate'] == true) {
        setState(() {
          _enrollmentDuplicateMsg = (res['message'] ??
                  'This Enrollment ID is already used by another patient.')
              .toString();
        });
      } else if (_enrollmentDuplicateMsg.isNotEmpty) {
        setState(() => _enrollmentDuplicateMsg = '');
      }
    } catch (_) {
      if (mounted && _enrollmentDuplicateMsg.isNotEmpty) {
        setState(() => _enrollmentDuplicateMsg = '');
      }
    }
    _scheduleBabyUidDuplicateCheck();
  }

  /// Q19 Normal, Q20 Normal, Q21 No (HR not below 100) — Q22 hidden (web birthConditionAllNormal).
  bool get _birthConditionAllNormal =>
      _poorRespiratoryEffort == false &&
      _poorMuscleTone == false &&
      _hrAbove100 == true;

  /// Web: alert when birthConditionAllNormal || required_resuscitation === "No".
  /// Web endParticipation (hide B4+) uses required_resuscitation === "No" (auto-set when all normal).
  bool get _showEndParticipationBanner =>
      _birthConditionAllNormal || _requiredResuscitation == false;

  bool get _endParticipation => _showEndParticipationBanner;

  void _applyAllNormalBirthCondition() {
    _initialStepsRequired = false;
    _requiredResuscitation = false;
    _clearRandomizationFields();
  }

  void _onBirthConditionFieldChanged(void Function() apply) {
    setState(() {
      apply();
      if (_birthConditionAllNormal) {
        _applyAllNormalBirthCondition();
      }
    });
  }

  void _clearRandomizationFields() {
    _randomized = null;
    _notRandomizedReason = null;
    _notRandomizedOtherCtrl.clear();
    _randomizationDateCtrl.clear();
    _enrollmentIdCtrl.clear();
  }

  void _onAutoCentileInputsChanged() {
    final before = _growthCentileCtrl.text;
    _syncAutoCentile();
    if (mounted && _growthCentileCtrl.text != before) setState(() {});
  }

  /// Mirror web INTERGROWTH auto-fill: set Q14 when GA/weight/sex are in
  /// chart range; clear only values this form auto-set.
  void _syncAutoCentile() {
    final rand = _gestationAtRandomization;
    final w = double.tryParse(_birthWeightCtrl.text.trim());
    final result = (rand == null || w == null)
        ? null
        : classifyVeryPretermCentile(w / 1000, rand.$1, rand.$2, _gender);
    final current = _growthCentileCtrl.text.trim();
    final wasUntouchedOrAuto =
        current.isEmpty || current == _lastAutoCentile;

    if (result == null) {
      if (wasUntouchedOrAuto && current.isNotEmpty) {
        _growthCentileCtrl.text = "";
      }
      _lastAutoCentile = null;
      return;
    }
    final autoValue = result.lowerPoint == 0
        ? result.label
        : '${result.lowerPoint}';
    if (wasUntouchedOrAuto && current != autoValue) {
      // Direct controller update — bypasses digits-only inputFormatters (manual entry).
      _growthCentileCtrl.text = autoValue;
    }
    _lastAutoCentile = autoValue;
  }

  IgVpCentileResult? get _centileClass {
    final rand = _gestationAtRandomization;
    final w = double.tryParse(_birthWeightCtrl.text.trim());
    if (rand == null || w == null) return null;
    return classifyVeryPretermCentile(w / 1000, rand.$1, rand.$2, _gender);
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
    if (!_formReadOnly && !_isFormBEmpty()) {
      final eid = _enrollmentIdCtrl.text.trim().isNotEmpty
          ? _enrollmentIdCtrl.text.trim()
          : (_randomized == false ? "NR-${widget.screeningId}" : "");
      ApiService().saveFormB(_snapshotFormB(enrollmentId: eid));
    }
    _babyUidCtrl.removeListener(_syncBabyAdmissionFromUid);
    _babyUidCtrl.removeListener(_scheduleBabyUidDuplicateCheck);
    _enrollmentIdCtrl.removeListener(_scheduleEnrollmentDuplicateCheck);
    _babyUidCheckTimer?.cancel();
    _birthWeightCtrl.removeListener(_onAutoCentileInputsChanged);
    _dobController.removeListener(_onAutoCentileInputsChanged);
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
          : normalizeFormBIndicationsFromCsv(existing.indication);
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
    if (_birthConditionAllNormal) {
      _applyAllNormalBirthCondition();
    }
  }

  void _applyServerBirthData(BirthResuscitationData d) {
    if ((d.babyUid ?? "").trim().isNotEmpty) {
      _babyUidCtrl.text = d.babyUid!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleBabyUidDuplicateCheck();
      });
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
      _dobController.text = _formatDobDisplay(dob);
    }
    if ((d.timeOfBirth ?? "").trim().isNotEmpty) {
      _timeController.text = _normalizeHms(d.timeOfBirth!);
    }
    if (d.indicationForDelivery.isNotEmpty) {
      _indications = normalizeFormBIndications(d.indicationForDelivery);
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scheduleEnrollmentDuplicateCheck();
        });
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
    if (_birthConditionAllNormal) {
      _applyAllNormalBirthCondition();
    }
  }

  String? _isoToDisplayDate(String iso) {
    try {
      final d = DateTime.parse(iso.split("T").first);
      return "${d.day.toString().padLeft(2, '0')}-"
          "${d.month.toString().padLeft(2, '0')}-"
          "${d.year}";
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadExistingFormB() async {
    debugPrint(
      '[FORMB_DEBUG] _loadExistingFormB start — '
      'widget.screeningId=${widget.screeningId} '
      'widget.maternalUid=${widget.maternalUid} '
      'widget.motherName=${widget.motherName}',
    );

    final existing = await ApiService().loadFormB(widget.screeningId);

    if (existing == null) {
      debugPrint('[FORMB_DEBUG] local draft existing=null');
    } else {
      debugPrint(
        '[FORMB_DEBUG] local draft existing: '
        'screeningId=${existing.screeningId} '
        'enrollmentId=${existing.enrollmentId}',
      );
    }

    // Prefer server row when we have an enrollment id (local or NR- fallback).
    final draftEid = (existing?.enrollmentId ?? "").trim();
    String eid = draftEid;
    final eidSource = eid.isNotEmpty
        ? 'existing.enrollmentId'
        : 'NR-fallback(NR-${widget.screeningId})';
    if (eid.isEmpty) eid = "NR-${widget.screeningId}";
    debugPrint(
      '[FORMB_DEBUG] resolved eid="$eid" '
      '(draft enrollmentId="$draftEid", source=$eidSource)',
    );

    BirthResuscitationData? remote;
    try {
      final json =
          await FormsApiService.instance.loadBirthResuscitation(eid);
      if (json != null) {
        remote = BirthResuscitationData.fromJson(json);
      }
    } catch (_) {}

    if (remote == null) {
      debugPrint('[FORMB_DEBUG] remote=null (GET birth-resuscitation for eid="$eid")');
    } else {
      debugPrint(
        '[FORMB_DEBUG] remote loaded: '
        'enrollmentId=${remote.enrollmentId} '
        'screeningId=${remote.screeningId} '
        'babyUid=${remote.babyUid} '
        'birthWeight=${remote.birthWeight} '
        'explicitlySaved=${remote.explicitlySaved}',
      );
    }

    if (!mounted) return;
    setState(() {
      // Server first (authoritative when online), then local draft overlays
      // non-empty values so offline edits are never lost.
      if (remote != null) _applyServerBirthData(remote);
      if (existing != null) {
        _applyLocalFormB(existing, overlayOnly: remote != null);
      }
      _syncAutoCentile();
      // Form A: lock from server explicitly_saved, not from "a row exists".
      final explicitSaved = remote?.explicitlySaved == true;
      _isSaved = widget.viewOnly || explicitSaved;
      _isEditing = !_isSaved;
      _b2Complete =
          explicitSaved && remote?.hasB2ClinicalData == true;
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
    if (_endParticipation || _randomized == false) {
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
      // Match web: omit / null when Q12 cannot be computed — do not fall
      // back to screening GA (that would store the wrong strata source).
      ..gestationRandWeeks = _gestationAtRandomization?.$1
      ..gestationRandDays = _gestationAtRandomization?.$2
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
      // Match web buildPayload: ppv_required true only if Q23 = Yes;
      // randomised only when Q23 = Yes (Q22/Q23 No clears the UI fields).
      ..ppvRequired =
          _requiredResuscitation == true ? true : null
      ..randomised =
          _requiredResuscitation == true ? _randomized : null
      ..randomisationDate = randDateIso
      ..strata = _randomized == true ? _strata : null
      ..enrollmentReasonNotRandomized =
          _randomized == false ? _notRandomizedReason : null
      ..enrollmentReasonNotRandomizedOther =
          _notRandomizedReason == "Other"
              ? _notRandomizedOtherCtrl.text.trim()
              : null;
  }

  /// Form B owns Q12/Q23/Q24/Q27 — send explicit nulls so a PUT can clear
  /// stale screening-GA fallback / leftover randomised flags. Form C's
  /// toJson() still omits nulls so it will not wipe these.
  ///
  /// [explicitlySaved] is true only for the Save button (`_onSaveContinue`),
  /// never for Save for Later / Cancel (`_saveDraft`).
  Map<String, dynamic> _formBJson(
    BirthResuscitationData d, {
    bool explicitlySaved = false,
  }) {
    final json = d.toJson();
    json['gestation_rand_weeks'] = d.gestationRandWeeks;
    json['gestation_rand_days'] = d.gestationRandDays;
    json['randomised'] = d.randomised;
    json['ppv_required'] = d.ppvRequired;
    json['strata'] = d.strata;
    if (explicitlySaved) {
      json['explicitly_saved'] = true;
    }
    return json;
  }

  Future<void> _saveDraft({bool popAfter = true}) async {
    if (_isFormBEmpty()) {
      if (popAfter && mounted) Navigator.of(context).pop(false);
      return;
    }
    if (_timeController.text.trim().isNotEmpty) {
      _timeController.text = _normalizeHms(_timeController.text);
    }
    final birthIssue = _birthDateTimeValidationMessage();
    if (birthIssue != null) {
      _showMsg(birthIssue);
      return;
    }
    final eid = _resolveEnrollmentIdForSync();
    final formB = _snapshotFormB(enrollmentId: eid);
    await ApiService().saveFormB(formB);

    // Best-effort server sync when we already have an enrollment / NR- id.
    if (eid.isNotEmpty) {
      try {
        await FormsApiService.instance
            .saveBirthResuscitation(_formBJson(_buildBirthPayload(eid)));
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

    if (_enrollmentDuplicateMsg.isNotEmpty) {
      _showMsg(_enrollmentDuplicateMsg);
      return;
    }
    if (_babyUidCtrl.text.trim().isNotEmpty && _babyUidDuplicateMsg.isNotEmpty) {
      _showMsg(_babyUidDuplicateMsg);
      return;
    }
    if (_dobController.text.isEmpty) { _showMsg("Please select Date of Birth"); return; }
    if (_timeController.text.isEmpty) { _showMsg("Please select Time of Birth"); return; }
    // Persist as HH:MM:SS (web Form B1 / ModernTimeInput).
    _timeController.text = _normalizeHms(_timeController.text);
    final dob = _parseDobText(_dobController.text);
    if (dob != null && _dateOnly(dob).isAfter(_todayDateOnly)) {
      _showMsg('Date of Birth cannot be in the future');
      return;
    }
    final birthIssue = _birthDateTimeValidationMessage();
    if (birthIssue != null) {
      _showMsg(birthIssue);
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
    if (!_birthConditionAllNormal && _initialStepsRequired == null) {
      _showMsg("Please select initial steps status"); return;
    }
    // Q23 only when initial steps = Required
    if (!_birthConditionAllNormal &&
        _initialStepsRequired == true &&
        _requiredResuscitation == null) {
      _showMsg("Please select whether baby requires ventilation (PPV)"); return;
    }

    // Build shared B1–B3 payload for ALL exits (including end-participation).
    // Backend requires enrollment_id — only randomised cases sync to server.
    if (_requiredResuscitation == true && _randomized == null) {
      _showMsg("Please select randomization status"); return;
    }
    if (!_endParticipation &&
        _randomized == false &&
        _notRandomizedReason == null) {
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
      await FormsApiService.instance.saveBirthResuscitation(
          _formBJson(shared, explicitlySaved: true));
    } catch (e) {
      if (!mounted) return;
      _showMsg("Save failed — check connection and try again. ($e)");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSaved = true;
      _isEditing = false;
    });

    if (_endParticipation) {
      if (_birthConditionAllNormal) {
        _applyAllNormalBirthCondition();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
          "Form B1 saved. PPV not required — complete Forms A–C only; "
          "Forms D and later stay locked.",
        ),
        backgroundColor: AppTheme.of(context).success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
      return;
    }

    if (_randomized == false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Form B1 saved and synced (not randomised)"),
        backgroundColor: AppTheme.of(context).success,
      ));
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FormCResuscitationDetails(
          key: ValueKey('form-c-${widget.screeningId}'),
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
    ).then((result) async {
      await _refreshB2Complete();
      if (result == true && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  /// Parses the DOB display text ("dd-MM-yyyy" or legacy "DD/MM/YY") back
  /// to a DateTime for the backend payload. Returns null on any parse failure.
  DateTime? _parseDobText(String s) {
    if (s.isEmpty) return null;
    final t = s.trim();
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final parts = t.split(RegExp(r'[/-]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final yy = int.tryParse(parts[2]);
    if (d == null || m == null || yy == null) return null;
    final year = yy < 100 ? 2000 + yy : yy;
    return DateTime(year, m, d);
  }

  String _formatDobDisplay(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-"
      "${d.month.toString().padLeft(2, '0')}-"
      "${d.year}";

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _todayDateOnly {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Earliest DOB selectable — screening calendar day when Form A has it (web minDate).
  DateTime _dobPickerFirstDate() {
    final screening = _calendarDateFromRaw(_screeningDateTime);
    if (screening != null) return _dateOnly(screening);
    return DateTime(2000, 1, 1);
  }

  /// Latest DOB selectable — end of today (web todayEnd / maxDate).
  DateTime _dobPickerLastDate() => _todayDateOnly;

  /// Calendar date from Form A screening datetime (ISO prefix or DD/MM/YYYY).
  /// Ignores clock time and timezone so Q12 matches web's date-only elapsed days.
  DateTime? _calendarDateFromRaw(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(t);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      return DateTime(y, mo, d);
    }
    return null;
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

  /// Normalize clock time to HH:MM:SS (24h; accepts "01:00 PM" → 13:00:00).
  String _normalizeHms(String value) => normalizeClockTimeHms(value);

  /// Parse HH:MM[:SS] or 12h AM/PM into hour/minute/second; falls back to now.
  ({int hour, int minute, int second}) _parseHms(String value) {
    final now = TimeOfDay.now();
    final parsed = parseClockTimeHms(value);
    if (parsed == null) {
      return (hour: now.hour, minute: now.minute, second: 0);
    }
    return parsed;
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
                      child: Text("HH (24h)",
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

  Future<void> _pickRandomizationDate() async {
    final picked = await showModernDatePicker(
      context  : context,
      firstDate: DateTime(2020),
      lastDate : DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (picked != null) {
      _randomizationDateCtrl.text = _formatDobDisplay(picked);
    }
  }

  // ============================================================
  // THEME-AWARE HELPERS  (aligned with Form A style)
  // ============================================================

  InputDecoration _input(String label, AppColors c,
      {String? helper, FieldLogicType? logic, String? logicTitle}) {
    final labelStyle = TextStyle(color: c.textSecondary, fontSize: 13);
    final labelWidget = logic == null
        ? requiredLabel(label, style: labelStyle)
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              requiredLabel(label, style: labelStyle),
              FieldLogicBadge(type: logic, title: logicTitle ?? ''),
            ],
          );
    return InputDecoration(
      label        : labelWidget,
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
  Widget _infoTile(String label, String value, AppColors c,
      {FieldLogicType? logic, String? logicTitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(label,
                style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (logic != null)
              FieldLogicBadge(type: logic, title: logicTitle ?? ''),
          ],
        ),
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
    FieldLogicType? logic,
    String? logicTitle,
  }) {
    final tColor     = trueColor  ?? c.danger;
    final fColor     = falseColor ?? c.success;
    final showError  = _submitted && value == null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          requiredLabel(
            title,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          if (logic != null)
            FieldLogicBadge(type: logic, title: logicTitle ?? ''),
        ],
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
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text("27. Strata",
                      style: TextStyle(color: c.textTertiary, fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const FieldLogicBadge(
                    type: FieldLogicType.auto,
                    title: "Auto from Gestation at Randomization",
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(_strata ?? "—",
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
      bottomNavigationBar: _formReadOnly ? null : _buildBottomBar(c),
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
          absorbing: _formReadOnly,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Form(
              key: _formKey,
              child: Column(children: [
                if (_formReadOnly) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.primary.withOpacity(0.25)),
                    ),
                    child: Text(
                      "Saved — tap Edit Form in the header to make changes",
                      style: TextStyle(
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                if (_isEditing && (_isSaved || widget.viewOnly)) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.warning.withOpacity(0.35)),
                    ),
                    child: Text(
                      "Editing saved Form B1",
                      style: TextStyle(
                        color: c.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                if (_showEndParticipationBanner) ...[
                  _buildEndParticipationBanner(c),
                  const SizedBox(height: 14),
                ],
                const FieldLogicLegend(),
                _buildIdentificationSection(c),
              _buildBirthDetailsSection(c),
              _buildConditionSection(c),
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
        Text("Birth & Resuscitation",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                letterSpacing: .3)),
        const SizedBox(height: 2),
        Text("Fill for all consented subjects · CRF Birth & Resuscitation",
            style: TextStyle(
                fontSize: 11,
                color: c.primary.withOpacity(0.7),
                fontWeight: FontWeight.w500)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: IconButton(
            tooltip: _formBExportEnabled
                ? "Export / Share Form B PDF"
                : "Save Form B1 and Form B2 to export a PDF",
            onPressed: _formBExportEnabled ? _exportShareFormBPdf : null,
            icon: _exportingPdf
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primary,
                    ),
                  )
                : Icon(Icons.ios_share_rounded,
                    color: _formBExportEnabled
                        ? c.textPrimary
                        : c.textTertiary,
                    size: 20),
          ),
        ),
        if (_showEditAction)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: IconButton(
              tooltip: _isEditing ? "Done Editing" : "Edit Form",
              onPressed: _toggleEditing,
              icon: Icon(
                _isEditing ? Icons.check_rounded : Icons.edit_rounded,
                color: _isEditing ? c.success : c.textPrimary,
                size: 20,
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
    );
  }

  void _toggleEditing() {
    setState(() => _isEditing = !_isEditing);
    if (_isEditing) _ensureEditableSession();
  }

  /// Form A restarts 10s autosave here. B1 has no periodic timer — listeners
  /// stay attached through AbsorbPointer lock — so this is a no-op hook.
  void _ensureEditableSession() {}

  CRF _crfForPdf() {
    final parts = widget.motherName.trim().split(RegExp(r'\s+'));
    final first = parts.isEmpty || parts.first.isEmpty ? '' : parts.first;
    final surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return CRF(
      screeningId: widget.screeningId,
      site: widget.siteId,
      siteId: widget.siteId,
      screeningDateTime: _screeningDateTime,
      screenedBy: '',
      motherFirstName: first,
      motherSurname: surname,
      husbandFirstName: '',
      husbandSurname: '',
      motherPhone: widget.motherPhone,
      husbandPhone: widget.husbandPhone,
      maternalUid: widget.maternalUid,
      hospitalNo: '',
      gestationWeeks: widget.gestWeeks,
      gestationDays: widget.gestDays,
      gestationMethod: '',
      expectedDeliveryDate: '',
      gestationKnownInWeeks: widget.gestWeeks > 0,
      eddKnown: false,
      exclusion: false,
      exclusionReason: '',
      anomalyDetails: '',
      eligibilityStatus: '',
      consentStatus: '',
      consentRefusalReason: '',
      relationshipToParticipant: '',
      relationshipOther: '',
      consentTakenBy: '',
      enrollmentId: _resolveEnrollmentIdForSync(),
    );
  }

  Future<void> _refreshB2Complete() async {
    final eid = _resolveEnrollmentIdForSync();
    var complete = false;
    if (eid.isNotEmpty) {
      try {
        final json =
            await FormsApiService.instance.loadBirthResuscitation(eid);
        if (json != null) {
          final d = BirthResuscitationData.fromJson(json);
          complete = d.explicitlySaved == true && d.hasB2ClinicalData;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _b2Complete = complete);
  }

  Future<String> _loadPiNameForPrint() async {
    final site = _siteName.trim();
    if (site.isEmpty) return '';
    try {
      final res = await ApiClient.instance.request(
        'GET',
        '/sites/${Uri.encodeComponent(site)}/pi-name',
      );
      return (res['pi_name'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  String _preparedByForPrint() {
    try {
      return context.read<AuthProvider>().user?.fullName.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _exportShareFormBPdf() async {
    if (!_formBExportEnabled) return;
    setState(() => _exportingPdf = true);
    try {
      final eid = _resolveEnrollmentIdForSync();
      FormC? formC;
      BirthResuscitationData? birth;
      try {
        formC = await ApiService().loadFormC(widget.screeningId);
      } catch (_) {}
      if (eid.isNotEmpty) {
        try {
          final json =
              await FormsApiService.instance.loadBirthResuscitation(eid);
          if (json != null) birth = BirthResuscitationData.fromJson(json);
        } catch (_) {}
      }
      birth ??= eid.isEmpty ? null : _buildBirthPayload(eid);
      final pi = await _loadPiNameForPrint();
      if (!mounted) return;
      await PdfService.shareFormBPdf(
        crf: _crfForPdf(),
        formB: _snapshotFormB(enrollmentId: eid),
        formC: formC,
        birth: birth,
        preparedBy: _preparedByForPrint(),
        piName: pi,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not export Form B PDF: $e")),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
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
          onChanged: (v) {
            setState(() => _babyUidMaxReached = v.length == 12);
            _scheduleBabyUidDuplicateCheck();
          },
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            if (!RegExp(r'^\d+$').hasMatch(v)) return "Digits only";
            if (v.length > 12) return "Baby UID cannot exceed 12 digits";
            if (_babyUidDuplicateMsg.isNotEmpty) return _babyUidDuplicateMsg;
            return null;
          },
        ),
        if (_babyUidDuplicateMsg.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _babyUidDuplicateMsg,
            style: TextStyle(
              color: c.warning,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
              if (_babyAnnualRule!.numeric && _babyAnnualRule!.max == 4)
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}$')),
              if (_babyAnnualRule!.numeric && _babyAnnualRule!.max != 4)
                FilteringTextInputFormatter.digitsOnly,
              if (!(_babyAnnualRule!.numeric && _babyAnnualRule!.max == 4))
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
          hint      : "Select date (dd-MM-yyyy)",
          controller: _dobController,
          icon      : Icons.calendar_today_rounded,
          c         : c,
          onTap     : () async {
            final first = _dobPickerFirstDate();
            final last = _dobPickerLastDate();
            var initial = _parseDobText(_dobController.text) ?? last;
            if (initial.isBefore(first)) initial = first;
            if (initial.isAfter(last)) initial = last;
            final picked = await showModernDatePicker(
              context    : context,
              initialDate: initial,
              firstDate  : first,
              lastDate   : last.isBefore(first) ? first : last,
            );
            if (picked != null) {
              final pickedDay = _dateOnly(picked);
              final screeningDay = _calendarDateFromRaw(_screeningDateTime);
              if (screeningDay != null &&
                  pickedDay.isBefore(_dateOnly(screeningDay))) {
                return; // reject — cannot predate screening (web DatePicker)
              }
              if (pickedDay.isAfter(_todayDateOnly)) {
                _showMsg('Date of Birth cannot be in the future');
                return;
              }
              setState(() {
                _dobController.text = _formatDobDisplay(picked);
              });
              _syncAutoCentile();
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
            if (_dobController.text.trim().isEmpty) {
              _showMsg('Please select Date of Birth first');
              return;
            }
            final picked = await _pickTimeHms(
              context,
              initial: _parseHms(_timeController.text),
            );
            if (picked != null) {
              final issue = _birthDateTimeValidationMessage(
                hour: picked.hour,
                minute: picked.minute,
                second: picked.second,
              );
              if (issue != null) {
                _showMsg(issue);
                return;
              }
              setState(() {
                _timeController.text =
                    "${picked.hour.toString().padLeft(2, '0')}:"
                    "${picked.minute.toString().padLeft(2, '0')}:"
                    "${picked.second.toString().padLeft(2, '0')}";
              });
            }
          },
        ),
        if (_birthDateTimeBannerMessage != null) ...[
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
                    _birthBeforeScreening
                        ? "Date & Time of Birth cannot be before the Screening Date & Time recorded in Form A."
                        : _birthDateTimeBannerMessage!,
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
          onChanged: (v) => setState(() {
            _gender = v;
            _syncAutoCentile();
          }),
          c        : c,
          showError: _submitted && _gender == null,
        ),

        _infoTile(
            "11. Gestation at Screening",
            "${widget.gestWeeks}w ${widget.gestDays}d",
            c,
            logic: FieldLogicType.carried,
            logicTitle: "From Form A — Screening"),
        const SizedBox(height: 10),
        _infoTile(
            "12. Gestation at Randomization",
            _gestationRandDisplay,
            c,
            logic: FieldLogicType.auto,
            logicTitle: "Auto from Form A gestational age and date of birth"),
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
            FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
          ],
          decoration:
              _input("14. Intrauterine Growth Status (centile)", c,
                      logic: FieldLogicType.auto,
                      logicTitle:
                          "Auto-calculated from birth weight, GA at randomization and gender — INTERGROWTH-21st Very Preterm")
                  .copyWith(
            hintText: "0–100",
            helperMaxLines: 6,
            helperText: () {
              final r = _centileClass;
              if (r != null) {
                const cols = [
                  "3rd",
                  "5th",
                  "10th",
                  "50th",
                  "90th",
                  "95th",
                  "97th"
                ];
                final refs = [
                  for (var i = 0; i < cols.length; i++)
                    "${cols[i]} ${r.row[i].toStringAsFixed(2)}kg"
                ].join("  ");
                return "Auto (INTERGROWTH-21st Very Preterm) — ${r.label}\n$refs";
              }
              return "Auto-fills once GA at randomization, birth weight and gender (Male/Female) are entered — covers 24+0–32+6 weeks only";
            }(),
          ),
          style: TextStyle(color: c.textPrimary),
          onChanged: (v) {
            if (v.isNotEmpty && (double.tryParse(v) ?? 0) > 100) {
              _growthCentileCtrl.text = _lastAutoCentile ?? "";
              return;
            }
            // Nurse typed a value — if it differs from auto, keep it.
            if (v.trim() != _lastAutoCentile) {
              // leave as override; last auto stays so we can still detect
            }
          },
          validator: (v) {
            if (v != null && v.trim().isNotEmpty) {
              final trimmed = v.trim();
              if (trimmed == igVpBelowThirdCentileValue) return null;
              final val = double.tryParse(trimmed);
              if (val == null) return "Enter a valid number";
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
          "18. Indication",
          required: true,
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text("(select all that apply)",
              style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
        ...kFormBIndicationOptions.map((opt) {
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
      children: [
        if (_conditionExpanded) ...[
              _boolChoiceChip(
                title     : "19. Respiratory effort *",
                trueLabel : "Absent/poor",
                falseLabel: "Normal",
                value     : _poorRespiratoryEffort,
                onChanged : (v) => _onBirthConditionFieldChanged(
                    () => _poorRespiratoryEffort = v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              _boolChoiceChip(
                title     : "20. Muscle tone *",
                trueLabel : "Limp/poor",
                falseLabel: "Normal",
                value     : _poorMuscleTone,
                onChanged : (v) => _onBirthConditionFieldChanged(
                    () => _poorMuscleTone = v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              // CRF asks HR < 100; stored inverted as hr_above_100 (same as web).
              _boolChoiceChip(
                title     : "21. HR < 100 *",
                trueLabel : "YES",
                falseLabel: "NO",
                value     : _hrAbove100 == null ? null : !_hrAbove100!,
                onChanged : (v) => _onBirthConditionFieldChanged(
                    () => _hrAbove100 = !v),
                trueColor : c.danger,
                falseColor: c.success,
                c         : c,
              ),
              if (!_birthConditionAllNormal)
                _boolChoiceChip(
                  title     : "22. Initial steps *",
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
                      _clearRandomizationFields();
                    }
                  }),
                  trueColor : c.danger,
                  falseColor: c.success,
                  c         : c,
                ),
              if (!_birthConditionAllNormal && _initialStepsRequired == true)
                _boolChoiceChip(
                  title     : "23. Does baby require ventilation (PPV)? *",
                  trueLabel : "Required",
                  falseLabel: "Not required",
                  value     : _requiredResuscitation,
                  onChanged : (v) => setState(() {
                    _requiredResuscitation = v;
                    if (!v) _clearRandomizationFields();
                  }),
                  trueColor : c.danger,
                  falseColor: c.success,
                  c         : c,
                ),
        ],
        if (_conditionExpanded && _requiredResuscitation == true)
          ..._randomizationFields(c),
      ],
    );
  }

  // ── END PARTICIPATION BANNER ───────────────────────────────────────────────

  Widget _buildEndParticipationBanner(AppColors c) {
    return Container(
      width: double.infinity,
      padding : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color        : c.dangerSoft,
        borderRadius : BorderRadius.circular(10),
        border       : Border.all(color: c.danger.withOpacity(0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: c.danger, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Resuscitation (PPV) not required — Forms D and later stay locked. Complete Forms A–C only, then stop.",
            style: TextStyle(
              color: c.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ]),
    );
  }

  // ── RANDOMIZATION (nested in B3, same as web) ─────────────────────────────

  List<Widget> _randomizationFields(AppColors c) {
    return [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text("Randomization details",
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3)),
              ),
              _boolChoiceChip(
                title     : "24. Randomised? *",
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
                logic     : FieldLogicType.conditional,
                logicTitle: "Gates strata (if Yes) and reason not randomized (if No)",
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
                  onChanged: (_) => _scheduleEnrollmentDuplicateCheck(),
                  validator: (v) {
                    if (_randomized != true) return null;
                    final t = (v ?? "").trim();
                    if (t.isEmpty || t == "$_siteCode-") {
                      return "Required";
                    }
                    if (!_isCompleteEnrollmentId(t)) {
                      return "Format: $_siteCode-A-001";
                    }
                    if (_enrollmentDuplicateMsg.isNotEmpty) {
                      return _enrollmentDuplicateMsg;
                    }
                    return null;
                  },
                ),
                if (_enrollmentDuplicateMsg.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _enrollmentDuplicateMsg,
                    style: TextStyle(
                      color: c.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                }),
                if (_notRandomizedReason == "Other") ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notRandomizedOtherCtrl,
                    decoration: _input("Specify other reason *", c),
                    style: TextStyle(color: c.textPrimary),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Required" : null,
                  ),
                ],
              ],
    ];
  }
}
