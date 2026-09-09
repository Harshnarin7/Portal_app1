// lib/screens/screening_form.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/crf.dart';
import '../services/api_service.dart';
import '../widgets/success_banner.dart';
import '../widgets/notes_box.dart';
import '../services/pdf_service.dart';
import 'form_b_birth_resuscitation.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/screening_api_service.dart';
import '../services/forms_api_service.dart';
import '../services/api_client.dart';
import '../utils/screening_status.dart';
import 'dashboard_screen.dart';

// ── Theme ──────────────────────────────────────────────────────────────────
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../theme/theme_notifier.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/required_asterisk.dart';

String screeningCounterKey(String site) => "screening_counter_$site";
const String draftIndexKey = "screening_draft_keys";
String _userRole = "admin";

class ScreeningForm extends StatefulWidget {
  final bool loadDraft;
  final String? draftKey;
  /// Open an already-saved screening in read-only mode (View filled forms).
  final bool viewOnly;
  final String? existingScreeningId;

  const ScreeningForm({
    super.key,
    this.loadDraft = false,
    this.draftKey,
    this.viewOnly = false,
    this.existingScreeningId,
  });

  @override
  State<ScreeningForm> createState() => _ScreeningFormState();
}

class _ScreeningFormState extends State<ScreeningForm>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  Set<String> _previousYesExclusions = {};

  bool _submitted = false;
  bool _proceedToConsent = false;
  bool _consentPopupShown = false;
  String _duplicateWarn = "";
  /// Live (as-you-type) hospital admission validation — same as web handleChange/blur.
  String? _hospitalNoLiveError;

  // Consent refusal
  Set<String> _consentRefusalReasons = {};
  String _consentRefusalOtherText = "";

  String? _currentDraftKey;
  String? _assignedScreeningId;

  // Not approached consent reason (multi-select, matches webform NOT_APPROACHED_REASONS)
  Set<String> _notApproachedReasons = {};
  String _notApproachedOtherText = "";

  // Video PIS shown (matches webform Q32 video_pis_shown)
  String _videoPisShown = "Select";

  bool _maternalUidLimitReached = false;
  bool _mobileLimitReached = false;
  bool _husbandPhoneLimitReached = false;
  final FocusNode _husbandPhoneFocus = FocusNode();
  bool _motherMobileLimitReached = false;
  final FocusNode _motherPhoneFocus = FocusNode();
  final FocusNode _maternalUidFocus = FocusNode();
  int _motherPhoneCount = 0;
  int _husbandPhoneCount = 0;
  int _maternalUidCount = 0;

  bool? _gestationKnownInWeeks;
  bool? _eddKnown;
  String? _gaSource;

  String _consentTakenBy = "Select";

  // ── Auto-save / draft durability (match web ~10s server autosave) ──
  Timer? _autoSaveTimer;
  Timer? _draftDebounce;

  bool _idAssigned = false;
  // Derived from _exclusionAnswers — never store a separate bool that can
  // drift (that caused "All options No" while field 23 showed Yes).
  bool get _exclusionPresent =>
      _exclusionAnswers.values.any((v) => v == "Yes");
  bool _loadingExisting = false;

  bool get _canShowClinicalDecision =>
      _gestationKnownInWeeks == true || _eddKnown == true;

  bool get _allExclusionsAnswered =>
      !_exclusionAnswers.values.contains(null);

  bool get _allExclusionsNo =>
      _allExclusionsAnswered &&
      _exclusionAnswers.values.every((v) => v == "No");

  bool get _gestationUndetermined =>
      _gestationKnownInWeeks == false && _eddKnown == false;

  bool get _canSaveAndClose {
    if (_gestationKnownInWeeks == false && _eddKnown == false) return true;
    if (_assignedScreeningId == null) return false;
    if (_screeningDateTimeCtrl.text.trim().isEmpty) return false;
    if (_selectedSite.isEmpty) return false;
    if (_screenedByCtrl.text == "Select") return false;

    if (_consentStatus == "No" && _consentRefusalReasons.isEmpty) return false;
    if (_consentStatus == "No" &&
        _consentRefusalReasons.contains("Other") &&
        _consentRefusalOtherText.trim().isEmpty) return false;

    if (_consentStatus == "Not approached" && _notApproachedReasons.isEmpty) return false;
    if (_consentStatus == "Not approached" &&
        _notApproachedReasons.contains("Other") &&
        _notApproachedOtherText.trim().isEmpty) return false;

    if (_consentStatus != "Select" && _videoPisShown == "Select") return false;

    if (_gestationKnownInWeeks == true || _eddKnown == true) {
      if (_gestationKnownInWeeks == false &&
          _eddKnown == true &&
          _expectedDeliveryCtrl.text.trim().isEmpty) return false;
      if (!_validateExclusionCompleted()) return false;
      if (!_validateExclusionSubOptions()) return false;
      if (!_exclusionPresent) {
        if (_consentStatus == "Select") return false;
        if (_relationshipToParticipant == "Select") return false;
        if (_relationshipToParticipant == "Other" &&
            _relationshipOtherText.trim().isEmpty) return false;
        if (_consentTakenBy == "Select") return false;
      }
    }
    return true;
  }

  bool _isDraftMode = false;

  bool _isFormEmpty() {
    return _motherFirstCtrl.text.trim().isEmpty &&
        _motherSurnameCtrl.text.trim().isEmpty &&
        _motherPhoneCtrl.text.trim().isEmpty &&
        _husbandFirstCtrl.text.trim().isEmpty &&
        _husbandSurnameCtrl.text.trim().isEmpty &&
        _hospitalNoCtrl.text.trim().isEmpty &&
        _maternalUidCtrl.text.trim().isEmpty;
  }

  bool _isFormComplete() {
    return _formKey.currentState?.validate() == true &&
        _validateExclusionCompleted() &&
        _screeningDateTimeCtrl.text.trim().isNotEmpty &&
        _expectedDeliveryCtrl.text.trim().isNotEmpty &&
        _screenedByCtrl.text.trim().isNotEmpty;
  }

  bool _isFormCompletelyEmpty() {
    // Include A1/gestation + exclusions + consent so filling only GA still drafts
    // (previously GA-only work was lost on back / kill before 60s timer).
    final hasIdentity = _motherFirstCtrl.text.trim().isNotEmpty ||
        _motherSurnameCtrl.text.trim().isNotEmpty ||
        _husbandFirstCtrl.text.trim().isNotEmpty ||
        _husbandSurnameCtrl.text.trim().isNotEmpty ||
        _motherPhoneCtrl.text.trim().isNotEmpty ||
        _husbandPhoneCtrl.text.trim().isNotEmpty ||
        _maternalUidCtrl.text.trim().isNotEmpty ||
        _hospitalNoCtrl.text.trim().isNotEmpty;
    final hasGestation = _gestationKnownInWeeks != null ||
        _gaSource != null ||
        _lmpCtrl.text.trim().isNotEmpty ||
        _expectedDeliveryCtrl.text.trim().isNotEmpty ||
        (_gestWeeksCtrl.text.trim().isNotEmpty &&
            _gestWeeksCtrl.text.trim() != "0") ||
        _gaAssessmentMethod != "Select";
    final hasExclusion = _exclusionAnswers.values.any((v) => v != null);
    final hasConsent = _consentStatus != "Select" ||
        _proceedToConsent ||
        _consentTakenBy != "Select";
    final hasMeta = _screeningDateTimeCtrl.text.trim().isNotEmpty ||
        (_assignedScreeningId != null && _assignedScreeningId!.isNotEmpty);
    return !(hasIdentity || hasGestation || hasExclusion || hasConsent || hasMeta);
  }

  // Controllers
  final TextEditingController _screeningIdCtrl   = TextEditingController();
  final TextEditingController _enrollmentIdCtrl  = TextEditingController();
  final TextEditingController _motherFirstCtrl   = TextEditingController();
  final TextEditingController _motherSurnameCtrl = TextEditingController();
  final TextEditingController _husbandFirstCtrl  = TextEditingController();
  final TextEditingController _husbandSurnameCtrl= TextEditingController();
  final TextEditingController _motherPhoneCtrl   = TextEditingController();
  final TextEditingController _husbandPhoneCtrl  = TextEditingController();
  final TextEditingController _maternalUidCtrl   = TextEditingController();
  final TextEditingController _hospitalNoCtrl    = TextEditingController();
  final TextEditingController _gestWeeksCtrl     = TextEditingController();
  final TextEditingController _gestDaysCtrl      = TextEditingController();
  final TextEditingController _expectedDeliveryCtrl = TextEditingController();
  final TextEditingController _lmpCtrl           = TextEditingController();
  final TextEditingController _screeningDateTimeCtrl = TextEditingController();
  final TextEditingController _screenedByCtrl    = TextEditingController(text: "Select");

  final Map<String, String?> _exclusionAnswers = {
    "INSUFFICIENT" : null,
    "RESUSCITATION": null,
    "ANOMALY"      : null,
    "HYDROPS"      : null,
    "IUFD"         : null,
  };

  String _insufficientReason  = "";
  Set<String> _resuscitationReasons = {}; // multi-select — was a single String
  String _resuscitationOther  = "";
  String _anomalyDetails      = "";
  String _hydropsType         = "";

  String _consentStatus              = "Select";
  /// ISO datetime for consent — set once when consent becomes Yes/Trial run.
  String? _consentDateTimeIso;
  String _gaAssessmentMethod         = "Select";
  String _relationshipToParticipant  = "Select";
  String _relationshipOtherText      = "";

  final Map<String, String> _siteMap = {
    "PGIMER": "01",
    "GMCH"  : "02",
    "IOG"   : "03",
    "AFMC"  : "04",
    "GMCH-A": "05",
    "AMC"   : "06",
  };

  List<String> _siteScreeners = [];

  /// Empty unless the logged-in user is site-locked (matches web `isSiteLocked`).
  String _selectedSite = "";
  bool _siteLocked = false;

  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  String _maternalUidLabel() {
    return "15. Maternal UID (CR number)";
  }

  int _maternalUidMaxLen() => _selectedSite == "PGIMER" ? 12 : 15;

  List<TextInputFormatter> _maternalUidFormatters() {
    if (_selectedSite == "AMC") {
      return [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        LengthLimitingTextInputFormatter(15),
      ];
    }
    if (_selectedSite == "PGIMER") {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ];
    }
    // GMCH / GMCH-A / IOG / AFMC: alphanumeric like web
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9/]')),
      LengthLimitingTextInputFormatter(15),
    ];
  }

  String _hospitalNoLabel() {
    if (_selectedSite == "GMCH-A") {
      return "16. Hospital Admission Number";
    }
    if (_selectedSite == "GMCH") {
      return "16. Hospital Admission Number";
    }
    if (_selectedSite == "IOG") {
      return "16. Hospital Admission Number";
    }
    if (_selectedSite == "AMC") {
      return "16. Hospital Admission Number";
    }
    return "16. Hospital Admission Number";
  }

  List<TextInputFormatter> _hospitalNoFormatters() {
    if (_selectedSite == "AMC") {
      return [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        LengthLimitingTextInputFormatter(15),
      ];
    }
    if (_selectedSite == "PGIMER") {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ];
    }
    if (_selectedSite == "GMCH-A") {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ];
    }
    if (_selectedSite == "GMCH") {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ];
    }
    if (_selectedSite == "IOG") {
      return [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ];
    }
    // AFMC and unknown: alphanumeric like web
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9/]')),
      LengthLimitingTextInputFormatter(15),
    ];
  }

  // ── VALIDATORS ─────────────────────────────────────────────────────────────

  String? _screeningDateValidator(String? value) {
    if (value == null || value.trim().isEmpty) return "Required";
    try {
      final parts    = value.split(" ");
      final datePart = parts[0];
      final d        = datePart.split("/");
      final selectedDate = DateTime(int.parse(d[2]), int.parse(d[1]), int.parse(d[0]));
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      // Match web ScreeningForm: maxDate=today only (no 7-day lookback rule).
      if (selectedDate.isAfter(todayDate)) return "Screening date cannot be in the future";
      return null;
    } catch (_) {
      return "Invalid date format";
    }
  }

  // ── LIFECYCLE ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _maternalUidFocus.addListener(() {
      if (!_maternalUidFocus.hasFocus) {
        setState(() => _maternalUidLimitReached = false);
      }
    });

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    _maternalUidCtrl.addListener(() {
      setState(() => _maternalUidLimitReached =
          _maternalUidCtrl.text.length >= _maternalUidMaxLen());
    });

    if (!widget.viewOnly) {
      _attachDraftListeners();
      // Match web ~10s autosave cadence
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && !_isFormCompletelyEmpty()) _saveDraft(silent: true);
      });
    }

    // Load site context first, then draft / existing — avoids clearing restored IDs/fields.
    _bootstrapForm();
  }

  Future<void> _bootstrapForm() async {
    await _loadUserContext();
    if (!mounted) return;
    final existingId = widget.existingScreeningId?.trim();
    if (existingId != null && existingId.isNotEmpty) {
      await _loadExistingScreening(existingId);
      return;
    }
    if (widget.loadDraft && widget.draftKey != null) {
      _currentDraftKey = widget.draftKey;
      await _loadDraftIfExists();
    }
  }

  String _isoToDdMmYyyy(String? iso) {
    if (iso == null || iso.trim().isEmpty) return "";
    final dt = DateTime.tryParse(iso.trim());
    if (dt == null) return "";
    return "${dt.day}/${dt.month}/${dt.year}";
  }

  String _isoToDdMmYyyyHHmm(String? iso) {
    if (iso == null || iso.trim().isEmpty) return "";
    final dt = DateTime.tryParse(iso.trim());
    if (dt == null) return "";
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "${dt.day}/${dt.month}/${dt.year} $h:$m";
  }

  String _unmapGestationMethod(String? v) {
    switch (v) {
      case "LMP":
        return "LMP";
      case "Early USG":
        return "Early USG (<24w)";
      case "Fundal Height":
        return "Fundal Height";
      case "Unknown":
        return "Method not known";
      default:
        return (v == null || v.isEmpty) ? "Select" : v;
    }
  }

  String? _exclusionKeyForLabel(String label) {
    final t = label.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains('structural') || t.contains('anomal')) return "ANOMALY";
    if (t.contains('hydrops')) return "HYDROPS";
    if (t.contains('resuscitation') || t.contains('forego')) return "RESUSCITATION";
    if (t.contains('insufficient')) return "INSUFFICIENT";
    if (t.contains('iufd')) return "IUFD";
    return null;
  }

  /// Draft JSON may store exclusion answers as Map<String, dynamic>.
  Map<String, String?> _parseExclusionAnswersMap(dynamic raw) {
    final out = <String, String?>{
      for (final k in _exclusionAnswers.keys) k: null,
    };
    if (raw is! Map) return out;
    for (final key in out.keys) {
      final v = raw[key];
      if (v == null) {
        out[key] = null;
      } else {
        final s = v.toString().trim();
        out[key] = (s == "Yes" || s == "No") ? s : null;
      }
    }
    return out;
  }

  Future<void> _loadExistingScreening(String screeningId) async {
    setState(() => _loadingExisting = true);
    try {
      final clinical = await ScreeningApiService.instance.getScreening(screeningId);
      final pii = await ScreeningApiService.instance.getPii(screeningId);
      if (!mounted) return;
      if (clinical == null) {
        setState(() => _loadingExisting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load screening $screeningId')),
        );
        return;
      }

      final reasonsRaw = (clinical['exclusion_reasons'] ?? '').toString();
      final yesKeys = <String>{};
      for (final part in reasonsRaw.split(RegExp(r'[,;]'))) {
        final key = _exclusionKeyForLabel(part);
        if (key != null) yesKeys.add(key);
      }
      // Prefer answers derived from reasons; treat server exclusion_present as
      // a fallback only when reasons are empty (legacy rows).
      final exclusionPresent =
          yesKeys.isNotEmpty || clinical['exclusion_present'] == true;
      final exclusionAnswers = <String, String?>{};
      for (final key in _exclusionAnswers.keys) {
        if (yesKeys.contains(key)) {
          exclusionAnswers[key] = "Yes";
        } else if (exclusionPresent ||
            reasonsRaw.isNotEmpty ||
            (clinical['consent_given']?.toString().isNotEmpty == true)) {
          exclusionAnswers[key] = "No";
        } else {
          exclusionAnswers[key] = null;
        }
      }

      final gestKnown = clinical['gestation_known']?.toString();
      final gaSource = clinical['ga_source']?.toString();

      setState(() {
        _assignedScreeningId = screeningId;
        _screeningIdCtrl.text = screeningId;
        _enrollmentId = clinical['enrollment_id']?.toString();
        _idAssigned = true;
        _serverConfirmedId = true;
        _selectedSite = (clinical['site_name'] ?? _selectedSite).toString();
        _screeningDateTimeCtrl.text =
            _isoToDdMmYyyyHHmm(clinical['screening_datetime']?.toString());
        _screenedByCtrl.text = (clinical['screened_by'] ?? '').toString();
        _motherFirstCtrl.text =
            (pii?['mother_first_name'] ?? clinical['mother_first_name'] ?? '').toString();
        _motherSurnameCtrl.text =
            (pii?['mother_surname'] ?? clinical['mother_surname'] ?? '').toString();
        _husbandFirstCtrl.text =
            (pii?['husband_first_name'] ?? clinical['husband_first_name'] ?? '').toString();
        _husbandSurnameCtrl.text =
            (pii?['husband_surname'] ?? clinical['husband_surname'] ?? '').toString();
        _motherPhoneCtrl.text =
            (pii?['mother_contact'] ?? clinical['mother_contact'] ?? '').toString();
        _husbandPhoneCtrl.text =
            (pii?['husband_contact'] ?? clinical['husband_contact'] ?? '').toString();
        _maternalUidCtrl.text =
            (pii?['maternal_uid'] ?? clinical['maternal_uid'] ?? '').toString();
        _hospitalNoCtrl.text = (pii?['hospital_admission_number'] ??
                clinical['hospital_admission_number'] ??
                '')
            .toString();
        _gestationKnownInWeeks = gestKnown == "Yes"
            ? true
            : (gestKnown == "No" ? false : (clinical['gestation_weeks'] != null));
        _gaSource = gaSource;
        _eddKnown = clinical['expected_delivery_date'] != null ? true : _eddKnown;
        _gestWeeksCtrl.text = clinical['gestation_weeks']?.toString() ?? "";
        _gestDaysCtrl.text = clinical['gestation_days']?.toString() ?? "0";
        _gaAssessmentMethod =
            _unmapGestationMethod(clinical['gestation_method']?.toString());
        _expectedDeliveryCtrl.text =
            _isoToDdMmYyyy(clinical['expected_delivery_date']?.toString());
        _lmpCtrl.text = _isoToDdMmYyyy(clinical['lmp_date']?.toString());
        _exclusionAnswers
          ..clear()
          ..addAll(exclusionAnswers);
        // Keep detail fields only when that exclusion is Yes
        _insufficientReason = yesKeys.contains("INSUFFICIENT")
            ? (clinical['reason_for_insufficient_time'] ?? '').toString()
            : "";
        final resus = yesKeys.contains("RESUSCITATION")
            ? (clinical['decision_forego_resuscitation_reason'] ?? '').toString()
            : "";
        _resuscitationReasons = resus.isEmpty
            ? {}
            : resus.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        _resuscitationOther = yesKeys.contains("RESUSCITATION")
            ? (clinical['decision_forego_resuscitation_reason_other'] ?? '').toString()
            : "";
        _anomalyDetails = yesKeys.contains("ANOMALY")
            ? (clinical['major_structural_anomalies_if_yes'] ?? '').toString()
            : "";
        final hydrops = yesKeys.contains("HYDROPS")
            ? (clinical['fetal_hydrops'] ?? '').toString()
            : "";
        _hydropsType = hydrops;
        final consent = (clinical['consent_given'] ?? '').toString();
        _consentStatus = consent.isNotEmpty ? consent : "Select";
        final consentDt = (clinical['consent_datetime'] ?? '').toString().trim();
        _consentDateTimeIso = consentDt.isNotEmpty ? consentDt : null;
        final rel = (clinical['relationship_to_participant'] ?? '').toString();
        _relationshipToParticipant = rel.isNotEmpty ? rel : "Select";
        _relationshipOtherText =
            (clinical['relationship_other'] ?? '').toString();
        final takenBy = (clinical['consent_taken_by'] ?? '').toString();
        _consentTakenBy = takenBy.isNotEmpty ? takenBy : "Select";
        final refuse = (clinical['reason_for_consent_refusal'] ?? '').toString();
        _consentRefusalReasons = refuse.isEmpty
            ? {}
            : refuse.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        _consentRefusalOtherText =
            (clinical['reason_for_consent_refusal_other'] ?? '').toString();
        final notApp = (clinical['reason_not_approached'] ?? '').toString();
        _notApproachedReasons = notApp.isEmpty
            ? {}
            : notApp.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        _notApproachedOtherText =
            (clinical['reason_not_approached_other'] ?? '').toString();
        final video = (clinical['video_pis_shown'] ?? '').toString();
        _videoPisShown = video.isNotEmpty ? video : "Select";
        _proceedToConsent = (exclusionAnswers.values.every((v) => v == "No") &&
                !exclusionAnswers.values.contains(null)) ||
            _consentStatus != "Select";
        _previousYesExclusions = yesKeys;
        _loadingExisting = false;
      });
      await _loadSiteScreeners();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingExisting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load screening: $e')),
      );
    }
  }

  void _attachDraftListeners() {
    final ctrls = [
      _motherFirstCtrl, _motherSurnameCtrl, _husbandFirstCtrl, _husbandSurnameCtrl,
      _motherPhoneCtrl, _husbandPhoneCtrl, _maternalUidCtrl, _hospitalNoCtrl,
      _gestWeeksCtrl, _gestDaysCtrl, _lmpCtrl, _expectedDeliveryCtrl,
      _screeningDateTimeCtrl, _screenedByCtrl,
    ];
    for (final c in ctrls) {
      c.addListener(_scheduleDraftSave);
    }
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isFormCompletelyEmpty()) {
        _saveDraft(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.viewOnly) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_isFormCompletelyEmpty()) {
        _saveDraft(silent: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _draftDebounce?.cancel();
    // Flush once more before controllers are disposed
    if (!widget.viewOnly && !_isFormCompletelyEmpty()) {
      // Fire-and-forget; dispose must stay sync
      _saveDraft(silent: true);
    }
    _screeningIdCtrl.dispose();
    _enrollmentIdCtrl.dispose();
    _motherFirstCtrl.dispose();
    _motherSurnameCtrl.dispose();
    _husbandFirstCtrl.dispose();
    _husbandSurnameCtrl.dispose();
    _motherPhoneCtrl.dispose();
    _husbandPhoneCtrl.dispose();
    _maternalUidCtrl.dispose();
    _hospitalNoCtrl.dispose();
    _scanController.dispose();
    _gestWeeksCtrl.dispose();
    _gestDaysCtrl.dispose();
    _expectedDeliveryCtrl.dispose();
    _lmpCtrl.dispose();
    _screeningDateTimeCtrl.dispose();
    _screenedByCtrl.dispose();
    _husbandPhoneFocus.dispose();
    _motherPhoneFocus.dispose();
    _maternalUidFocus.dispose();
    super.dispose();
  }

  // ── USER CONTEXT ───────────────────────────────────────────────────────────

  Future<void> _loadUserContext() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString("user_role") ?? "admin";
    if (!mounted) return;

    final user = context.read<AuthProvider>().user;
    final prefsSite = prefs.getString("site_name")?.trim() ?? "";
    final userSite = user?.siteName?.trim() ?? "";

    String? lockedSite;
    if (_userRole == "site" && prefsSite.isNotEmpty) {
      lockedSite = prefsSite;
    } else if (user != null && !user.role.isGlobal && userSite.isNotEmpty) {
      lockedSite = userSite;
    }

    if (mounted) {
      setState(() {
        _siteLocked = lockedSite != null;
        if (lockedSite != null) {
          _selectedSite = lockedSite;
          // Never wipe an in-progress / draft screening ID on reopen.
          if (!widget.loadDraft) {
            _screeningIdCtrl.clear();
            _idAssigned = false;
          }
        }
        // Do not default to PGIMER and do not write login name into Q12.
      });
    }

    await _loadSiteScreeners();
  }

  Future<void> _loadSiteScreeners() async {
    if (_selectedSite.isEmpty) {
      if (mounted) setState(() => _siteScreeners = []);
      return;
    }
    try {
      final list = await ApiClient.instance.getList(
        '/sites/${Uri.encodeComponent(_selectedSite)}/screeners',
      );
      final names = list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
      if (!mounted) return;
      setState(() => _siteScreeners = names);
      // Match web: autofill screened_by only when site-locked AND login name is on the roster.
      if (!_siteLocked) return;
      final user = context.read<AuthProvider>().user;
      final target = user?.fullName.trim().toLowerCase() ?? "";
      if (target.isEmpty) return;
      final cur = _screenedByCtrl.text.trim();
      if (cur.isNotEmpty && cur != "Select") return;
      String? match;
      for (final n in names) {
        if (n.trim().toLowerCase() == target) { match = n; break; }
      }
      if (match != null) {
        setState(() => _screenedByCtrl.text = match!);
      }
    } catch (_) {
      // No hardcoded nurse fallback — empty roster until the API succeeds.
      if (mounted) setState(() => _siteScreeners = []);
    }
  }

  Future<void> _checkDuplicateMotherName() async {
    final name = _motherFirstCtrl.text.trim();
    if (name.isEmpty || _selectedSite.isEmpty) {
      if (_duplicateWarn.isNotEmpty && mounted) setState(() => _duplicateWarn = "");
      return;
    }
    try {
      final patients = await ScreeningApiService.instance.getPatients(limit: 200);
      final currentId = _assignedScreeningId;
      final hits = <String>[];
      for (final p in patients) {
        final sid = p['screening_id']?.toString() ?? '';
        if (currentId != null && sid == currentId) continue;
        // PII may be absent from list payload — batch not needed for warning; web uses dedicated search.
        final mf = (p['mother_first_name'] ?? '').toString().trim();
        if (mf.toLowerCase() == name.toLowerCase()) hits.add(sid.isEmpty ? '?' : sid);
      }
      // Also check via PII batch for recent patients when list is de-identified
      if (hits.isEmpty) {
        final ids = patients
            .map((p) => p['screening_id']?.toString() ?? '')
            .where((s) => s.isNotEmpty && s != currentId)
            .take(40)
            .toList();
        if (ids.isNotEmpty) {
          try {
            final pii = await ScreeningApiService.instance.getPiiBatch(ids);
            pii.forEach((sid, row) {
              final mf = (row['mother_first_name'] ?? '').toString().trim();
              if (mf.toLowerCase() == name.toLowerCase()) hits.add(sid);
            });
          } catch (_) {}
        }
      }
      final msg = hits.isEmpty
          ? ""
          : '⚠️ A participant named "$name" already exists at $_selectedSite (${hits.first}). Please verify this is not a duplicate.';
      if (mounted) setState(() => _duplicateWarn = msg);
    } catch (_) {}
  }

  Future<void> _logout() async {
    // Do NOT prefs.clear() — that wiped screening drafts. Clear auth only.
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil("/login", (route) => false);
  }

  // ── GESTATION HELPERS ──────────────────────────────────────────────────────

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Calendar-day difference (b − a), matching web `calendarDaysBetween`.
  int _calendarDaysBetween(DateTime a, DateTime b) {
    final a0 = _dateOnly(a);
    final b0 = _dateOnly(b);
    return b0.difference(a0).inDays;
  }

  /// Naegele: EDD = LMP + 280 days.
  DateTime _eddFromLmp(DateTime lmp) => _dateOnly(lmp).add(const Duration(days: 280));

  /// GA from LMP (preferred when LMP is known) — completed weeks/days since LMP.
  void _setGestationFromLmp(DateTime lmp) {
    final gestDays = _calendarDaysBetween(lmp, DateTime.now());
    final safe = gestDays < 0 ? 0 : gestDays;
    _gestWeeksCtrl.text = (safe ~/ 7).toString();
    _gestDaysCtrl.text = (safe % 7).toString();
  }

  /// Match web `gestAgeFromEdd` — GA = 280 − (EDD − today).
  void _setGestationFromEdd(DateTime edd) {
    final daysUntilEdd = _calendarDaysBetween(DateTime.now(), edd);
    var gestDays = 280 - daysUntilEdd;
    if (gestDays < 0) gestDays = 0;
    _gestWeeksCtrl.text = (gestDays ~/ 7).toString();
    _gestDaysCtrl.text = (gestDays % 7).toString();
  }

  void _recalculateGestationFromEDD(DateTime edd) {
    setState(() => _setGestationFromEdd(edd));
  }

  // Eligibility range matches web ScreeningForm.jsx getEligibilityStatus():
  // eligible = 25w0d .. 31w6d inclusive (t < 25*7 => low, t > 31*7+6 => high)
  bool _isGestationOutOfRange() {
    final weeks = int.tryParse(_gestWeeksCtrl.text) ?? 0;
    final days  = int.tryParse(_gestDaysCtrl.text)  ?? 0;
    final t = weeks * 7 + days;
    if (_gestWeeksCtrl.text.trim().isEmpty) return false;
    if (t < 25 * 7) return true;
    if (t > 31 * 7 + 6) return true;
    return false;
  }

  bool get _isEligibleGestation {
    // Web shows A2–A5 as soon as Q1 = Yes, even before weeks are entered.
    // Hide them only when a completed GA is outside 25w0d–31w6d.
    if (_gestWeeksCtrl.text.trim().isEmpty) {
      return _gestationKnownInWeeks == true;
    }
    final weeks = int.tryParse(_gestWeeksCtrl.text) ?? 0;
    final days  = int.tryParse(_gestDaysCtrl.text)  ?? 0;
    final t = weeks * 7 + days;
    if (t < 25 * 7) return false;
    if (t > 31 * 7 + 6) return false;
    return true;
  }

  void _resetGestationSection() {
    setState(() {
      _gestationKnownInWeeks = null;
      _eddKnown              = null;
      _gaSource              = null;
      _gestWeeksCtrl.text    = "";
      _gestDaysCtrl.text     = "0";
      _expectedDeliveryCtrl.clear();
      _lmpCtrl.clear();
      _gaAssessmentMethod = "Select";
    });
  }

  void _resetExclusionSection() {
    setState(() {
      _exclusionAnswers.updateAll((key, value) => null);
      _previousYesExclusions.clear();
      _proceedToConsent   = false;
      _consentPopupShown  = false;
      _insufficientReason  = "";
      _resuscitationReasons = {};
      _resuscitationOther  = "";
      _anomalyDetails      = "";
      _hydropsType         = "";
    });
  }

  // ── EXCLUSION LOGIC ────────────────────────────────────────────────────────

  void _checkExclusionAndAlert() {
    final bool allAnswered = !_exclusionAnswers.values.contains(null);
    final Set<String> currentYesKeys = _exclusionAnswers.entries
        .where((e) => e.value == "Yes")
        .map((e) => e.key)
        .toSet();
    final List<String> currentYesLabels = currentYesKeys.map(_exclusionLabel).toList();

    // _exclusionPresent is derived from answers — no separate assignment.

    final bool yesSetChanged = !setEquals(currentYesKeys, _previousYesExclusions);

    if (allAnswered && currentYesKeys.isNotEmpty && yesSetChanged) {
      _previousYesExclusions = Set.from(currentYesKeys);
      final c = AppTheme.of(context);
      Future.microtask(() {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(Icons.block_rounded, color: c.danger, size: 20),
              const SizedBox(width: 8),
              Text("Exclusion Criteria Present",
                  style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("The following exclusion criteria are present:",
                    style: TextStyle(color: c.textSecondary, fontSize: 13)),
                const SizedBox(height: 10),
                ...currentYesLabels.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(
                          shape: BoxShape.circle, color: c.danger)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e,
                          style: TextStyle(color: c.textPrimary, fontSize: 13))),
                    ]),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: c.danger, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      });
    }

    // Match web ScreeningForm: when all exclusions are No, A5 consent
    // appears immediately (no Proceed Now/Later gate).
    if (_allExclusionsNo && !_proceedToConsent) {
      _proceedToConsent = true;
      _consentPopupShown = true;
    }

    if (currentYesKeys.isEmpty) _previousYesExclusions.clear();
    if (!_allExclusionsNo) {
      _proceedToConsent  = false;
      _consentPopupShown = false;
    }
  }

  String _exclusionLabel(String key) {
    switch (key) {
      case "ANOMALY"      : return "Major structural anomalies";
      case "HYDROPS"      : return "Fetal Hydrops";
      case "RESUSCITATION": return "Decision to forego resuscitation";
      case "INSUFFICIENT" : return "Insufficient time for antenatal consent";
      case "IUFD"         : return "Intrauterine Fetal Death (IUFD)";
      default             : return key;
    }
  }

  bool _validateExclusionCompleted() => !_exclusionAnswers.values.contains(null);

  bool _validateExclusionSubOptions() {
    for (final entry in _exclusionAnswers.entries) {
      if (entry.value != "Yes") continue;
      switch (entry.key) {
        case "INSUFFICIENT":
          if (_insufficientReason.trim().isEmpty) return false;
          break;
        case "RESUSCITATION":
          if (_resuscitationReasons.isEmpty) return false;
          if (_resuscitationReasons.contains("Other") && _resuscitationOther.trim().isEmpty) return false;
          break;
        case "ANOMALY":
          if (_anomalyDetails.trim().isEmpty) return false;
          break;
        case "HYDROPS":
          if (_hydropsType.isEmpty) return false;
          break;
        case "IUFD":
          break;
      }
    }
    return true;
  }

  // ── ID ASSIGNMENT ──────────────────────────────────────────────────────────
  // Mirrors ScreeningForm.jsx: the web portal never pre-generates a
  // screening_id — it creates the row on the first autosave and the server
  // assigns the ID. We do the same here so the ID the nurse sees matches the
  // one the web portal will show for the same record.

  bool _serverConfirmedId = false; // true once the backend has assigned a real ID
  String? _enrollmentId;

  Future<void> _assignScreeningIdIfNeeded() async {
    if (_idAssigned) return;
    if (_isFormCompletelyEmpty()) return;
    if (_selectedSite.isEmpty || !_siteMap.containsKey(_selectedSite)) return;
    final siteCode = _siteMap[_selectedSite] ?? "00";

    // Only create a server screening once we have real identity + GA —
    // never invent "DRAFT" placeholder patients.
    if (_canSyncDraftToServer()) {
      try {
        final resp = await _syncToBackend(isDraft: true);
        final sid = resp?['screening_id']?.toString();
        if (sid != null && sid.isNotEmpty) {
          _assignedScreeningId  = sid;
          _screeningIdCtrl.text = sid;
          _enrollmentId          = resp?['enrollment_id']?.toString();
          _serverConfirmedId     = true;
          _idAssigned            = true;
          if (mounted) setState(() {});
          return;
        }
      } catch (_) {
        // Offline / backend unreachable — fall back to a local placeholder ID.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final key   = screeningCounterKey(_selectedSite);
    final last  = prefs.getInt(key) ?? 0;
    final next  = last + 1;
    _assignedScreeningId = "$siteCode-LOCAL-${next.toString().padLeft(4, '0')}";
    _screeningIdCtrl.text = _assignedScreeningId!;
    await prefs.setInt(key, next);
    _idAssigned = true;
    if (mounted) setState(() {});
  }

  // ── SYNC PAYLOAD ──────────────────────────────────────────────────────────
  // Field names below are identical to ScreeningForm.jsx's buildPayloadFrom()
  // / backend/schemas.py ScreeningCreate, so a record saved from the mobile
  // app is indistinguishable from one saved on the web portal.

  String? _ddmmyyyyToIsoDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final datePart = s.trim().split(RegExp(r'\s+')).first;
    final parts = datePart.split('/');
    if (parts.length != 3) return null;
    final d = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    final y = parts[2];
    return "$y-$m-$d";
  }

  String? _ddmmyyyyHHmmToIso(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final segs = s.trim().split(RegExp(r'\s+'));
    if (segs.isEmpty) return null;
    final datePart = segs[0];
    final timePart = segs.length > 1 ? segs[1] : "00:00";
    final parts = datePart.split('/');
    if (parts.length != 3) return null;
    final d = parts[0].padLeft(2, '0');
    final m = parts[1].padLeft(2, '0');
    final y = parts[2];
    return "$y-$m-${d}T$timePart:00";
  }

  /// Maps the mobile "Method of Gestation Assessment" dropdown labels to the
  /// exact values the webform/backend use.
  String? _mapGestationMethod(String v) {
    switch (v) {
      case "LMP":               return "LMP";
      case "Early USG (<24w)":  return "Early USG";
      case "Fundal Height":     return "Fundal Height";
      case "Method not known":  return "Unknown";
      default:                  return null; // "Select"
    }
  }

  /// Maps the internal exclusion-answer keys to the exact label strings the
  /// webform stores in `exclusion_reasons` (comma-separated).
  String _exclusionLabelForSync(String key) {
    switch (key) {
      case "ANOMALY":        return "Structural anomaly";
      case "HYDROPS":        return "Fetal hydrops";
      case "RESUSCITATION":  return "Forego resuscitation";
      case "INSUFFICIENT":   return "Insufficient time";
      case "IUFD":            return "IUFD";
      default:                return key;
    }
  }

  Map<String, dynamic> _buildSyncPayload({bool useDraftFallbacks = false}) {
    final weeks = int.tryParse(_gestWeeksCtrl.text.trim());
    final days  = int.tryParse(_gestDaysCtrl.text.trim());
    final ended = _gaEndedParticipation || useDraftFallbacks;
    String screenedBy = _screenedByCtrl.text.trim();
    if (screenedBy.isEmpty || screenedBy == "Select") {
      screenedBy = "";
      if (ended) {
        try {
          final name = context.read<AuthProvider>().user?.fullName.trim() ?? "";
          screenedBy = name.isNotEmpty ? name : "N/A";
        } catch (_) {
          screenedBy = "N/A";
        }
      }
    }

    final exclusionLabels = _exclusionAnswers.entries
        .where((e) => e.value == "Yes")
        .map((e) => _exclusionLabelForSync(e.key))
        .toList();

    final gaMethod = _mapGestationMethod(_gaAssessmentMethod);

    return {
      if (_serverConfirmedId && _assignedScreeningId != null)
        'screening_id': _assignedScreeningId,
      'screening_datetime': _ddmmyyyyHHmmToIso(_screeningDateTimeCtrl.text) ??
          (useDraftFallbacks ? DateTime.now().toIso8601String() : null),
      'site_name'   : _selectedSite.isNotEmpty ? _selectedSite : null,
      'site_id'     : _siteMap[_selectedSite],
      'screened_by' : screenedBy.isNotEmpty ? screenedBy : null,
      // Never send literal "DRAFT" — it shows up as fake patients on Home.
      'mother_first_name' : _motherFirstCtrl.text.trim().isNotEmpty
          ? _motherFirstCtrl.text.trim() : (ended ? "" : null),
      'mother_surname'    : _motherSurnameCtrl.text.trim().isNotEmpty ? _motherSurnameCtrl.text.trim() : null,
      'husband_first_name': _husbandFirstCtrl.text.trim().isNotEmpty
          ? _husbandFirstCtrl.text.trim() : (ended ? "" : null),
      'husband_surname'   : _husbandSurnameCtrl.text.trim().isNotEmpty ? _husbandSurnameCtrl.text.trim() : null,
      'mother_contact'    : _motherPhoneCtrl.text.trim().isNotEmpty ? _motherPhoneCtrl.text.trim() : null,
      'husband_contact'   : _husbandPhoneCtrl.text.trim().isNotEmpty ? _husbandPhoneCtrl.text.trim() : null,
      'maternal_uid'      : _maternalUidCtrl.text.trim().isNotEmpty ? _maternalUidCtrl.text.trim() : null,
      'hospital_admission_number': _hospitalNoCtrl.text.trim().isNotEmpty ? _hospitalNoCtrl.text.trim() : null,
      // Persist GA path the same way as web buildPayloadFrom
      'gestation_known': _gestationKnownInWeeks == true
          ? "Yes"
          : (_gestationKnownInWeeks == false ? "No" : null),
      'ga_source': _gestationKnownInWeeks == false ? (_gaSource) : null,
      'gestation_weeks': weeks ?? (ended ? 0 : null),
      'gestation_days' : days  ?? 0,
      'gestation_method': gaMethod,
      'expected_delivery_date': _ddmmyyyyToIsoDate(_expectedDeliveryCtrl.text),
      'lmp_date'              : _ddmmyyyyToIsoDate(_lmpCtrl.text),
      // Omit until exclusions are answered — sending false early makes web
      // treat unanswered criteria as "No" when the draft is reopened.
      'exclusion_present': _allExclusionsAnswered
          ? _exclusionPresent
          : (ended ? false : null),
      // Use "" (not null) once answered so PUT clears a stale reasons string;
      // null is stripped by removeWhere and would leave old "Insufficient time".
      'exclusion_reasons': !_allExclusionsAnswered
          ? null
          : (exclusionLabels.isNotEmpty ? exclusionLabels.join(", ") : ""),
      'reason_for_insufficient_time': !_allExclusionsAnswered
          ? null
          : (_exclusionAnswers["INSUFFICIENT"] == "Yes" &&
                  _insufficientReason.trim().isNotEmpty
              ? _insufficientReason.trim()
              : ""),
      'decision_forego_resuscitation_reason': !_allExclusionsAnswered
          ? null
          : (_exclusionAnswers["RESUSCITATION"] == "Yes" &&
                  _resuscitationReasons.isNotEmpty
              ? _resuscitationReasons.join(", ")
              : ""),
      'decision_forego_resuscitation_reason_other': !_allExclusionsAnswered
          ? null
          : (_resuscitationReasons.contains("Other") &&
                  _resuscitationOther.trim().isNotEmpty
              ? _resuscitationOther.trim()
              : ""),
      'major_structural_anomalies_if_yes': !_allExclusionsAnswered
          ? null
          : (_exclusionAnswers["ANOMALY"] == "Yes" &&
                  _anomalyDetails.trim().isNotEmpty
              ? _anomalyDetails.trim()
              : ""),
      'fetal_hydrops': !_allExclusionsAnswered
          ? null
          : (_exclusionAnswers["HYDROPS"] == "Yes" && _hydropsType.isNotEmpty
              ? _hydropsType
              : ""),
      'consent_given'   : _consentStatus != "Select" ? _consentStatus : null,
      'consent_taken_by': _consentTakenBy != "Select" ? _consentTakenBy : null,
      'relationship_to_participant': _relationshipToParticipant != "Select" ? _relationshipToParticipant : null,
      'relationship_other'         : _relationshipOtherText.trim().isNotEmpty ? _relationshipOtherText.trim() : null,
      'reason_for_consent_refusal' : _consentRefusalReasons.isNotEmpty ? _consentRefusalReasons.join(", ") : null,
      'reason_for_consent_refusal_other': _consentRefusalOtherText.trim().isNotEmpty ? _consentRefusalOtherText.trim() : null,
      'reason_not_approached'      : _notApproachedReasons.isNotEmpty ? _notApproachedReasons.join(", ") : null,
      'reason_not_approached_other': _notApproachedOtherText.trim().isNotEmpty ? _notApproachedOtherText.trim() : null,
      'video_pis_shown': _videoPisShown != "Select" ? _videoPisShown : null,
      'consent_form_version': 'v1.0',
      'consent_language': 'English',
      if (_consentStatus == "Yes" || _consentStatus == "Trial run")
        'consent_datetime': () {
          _consentDateTimeIso ??= DateTime.now().toIso8601String();
          return _consentDateTimeIso;
        }(),
    };
  }

  /// True when A2–A5 are hidden (out of 25+0–31+6, or GA undeterminable).
  bool get _gaEndedParticipation =>
      _isGestationOutOfRange() ||
      (_gestationKnownInWeeks == false && _eddKnown == false);

  /// Draft/server sync only when required ScreeningCreate fields are real
  /// (avoids creating "DRAFT / Excluded" ghost patients on the home list).
  /// Ineligible / undeterminable GA still POSTs so the row appears on web.
  bool _canSyncDraftToServer() {
    if (_selectedSite.isEmpty || _siteMap[_selectedSite] == null) return false;
    if (_gestationKnownInWeeks == false && _eddKnown == false) return true;
    final weeks = int.tryParse(_gestWeeksCtrl.text.trim());
    if (weeks == null || weeks < 10 || weeks > 45) return false;
    if (_isGestationOutOfRange()) return true;
    return _screenedByCtrl.text.trim().isNotEmpty
        && _screenedByCtrl.text != "Select"
        && _motherFirstCtrl.text.trim().isNotEmpty
        && _husbandFirstCtrl.text.trim().isNotEmpty;
  }

  /// POSTs (create) or PUTs (update) the current form state to the real
  /// `/screenings/` backend endpoint — the same one ScreeningForm.jsx uses.
  Future<Map<String, dynamic>?> _syncToBackend({bool isDraft = false}) async {
    if (isDraft && !_canSyncDraftToServer() && !_serverConfirmedId) {
      return null;
    }
    if (isDraft && !_canSyncDraftToServer() && _serverConfirmedId) {
      // Allow updates only when we already have a server row AND names are set,
      // so we can overwrite an old "DRAFT" placeholder with the real name.
      if (_motherFirstCtrl.text.trim().isEmpty) return null;
    }
    final payload = _buildSyncPayload(useDraftFallbacks: isDraft);
    // Drop null keys so we don't overwrite required server fields with null.
    payload.removeWhere((_, v) => v == null);
    final resp = await ScreeningApiService.instance.syncScreening(
      payload: payload,
      existingScreeningId: _serverConfirmedId ? _assignedScreeningId : null,
    );
    final sid = resp['screening_id']?.toString();
    if (sid != null && sid.isNotEmpty) {
      _assignedScreeningId  = sid;
      _serverConfirmedId    = true;
      if (_screeningIdCtrl.text != sid) _screeningIdCtrl.text = sid;
    }
    final eid = resp['enrollment_id']?.toString();
    if (eid != null && eid.isNotEmpty) _enrollmentId = eid;
    return resp;
  }

  // ── DRAFT ──────────────────────────────────────────────────────────────────

  /// Clears the on-device draft entry (SharedPreferences). Safe to call repeatedly.
  Future<void> _clearLocalDraft() async {
    if (_currentDraftKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentDraftKey!);
    await _removeDraftKey(_currentDraftKey!);
    _currentDraftKey = null;
  }

  /// True when Form A has been filled far enough that keeping a "Draft" card
  /// next to the same record on the web patient list is confusing.
  bool _looksFullyFilledForDraftClear() {
    final consentDone = _consentStatus != "Select" && _consentStatus.trim().isNotEmpty;
    if (consentDone) return true;
    if (_exclusionPresent && _allExclusionsAnswered) return true;
    if (_gestationKnownInWeeks == false && _eddKnown == false) return true;
    if (_isGestationOutOfRange()) return true;
    return false;
  }

  Future<void> _saveDraft({bool silent = false}) async {
    if (_isFormCompletelyEmpty()) return;
    await _assignScreeningIdIfNeeded();

    // Best-effort background sync to the real backend so progress is visible
    // on the web portal too. Failures (e.g. offline) are silent here — the
    // local SharedPreferences draft below still keeps the data safe.
    Map<String, dynamic>? syncResp;
    try {
      syncResp = await _syncToBackend(isDraft: true);
    } catch (_) {
      syncResp = null;
    }

    // Only drop the local draft after a successful server sync. If sync failed
    // (offline / error), keep SharedPreferences so edits are never lost.
    if (syncResp != null &&
        _serverConfirmedId &&
        _looksFullyFilledForDraftClear()) {
      await _clearLocalDraft();
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Saved to server — removed from local drafts"),
        ));
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _currentDraftKey ??= "draft_${DateTime.now().millisecondsSinceEpoch}";

    final draft = {
      "screeningId"         : _assignedScreeningId,
      "enrollmentId"        : _enrollmentId,
      "serverConfirmedId"   : _serverConfirmedId,
      "site"                : _selectedSite,
      "savedAt"             : DateTime.now().toIso8601String(),
      "screeningDateTime"   : _screeningDateTimeCtrl.text,
      "screenedBy"          : _screenedByCtrl.text,
      "motherFirst"         : _motherFirstCtrl.text,
      "motherFirstName"     : _motherFirstCtrl.text, // dashboard list key
      "motherSurname"       : _motherSurnameCtrl.text,
      "husbandFirst"        : _husbandFirstCtrl.text,
      "husbandSurname"      : _husbandSurnameCtrl.text,
      "motherPhone"         : _motherPhoneCtrl.text,
      "husbandPhone"        : _husbandPhoneCtrl.text,
      "maternalUid"         : _maternalUidCtrl.text,
      "hospitalNo"          : _hospitalNoCtrl.text,
      "gestationKnownInWeeks": _gestationKnownInWeeks,
      "eddKnown"            : _eddKnown,
      "gaSource"            : _gaSource,
      "lmpDate"             : _lmpCtrl.text,
      "gestWeeks"           : _gestWeeksCtrl.text,
      "gestDays"            : _gestDaysCtrl.text,
      "gaMethod"            : _gaAssessmentMethod,
      "expectedDelivery"    : _expectedDeliveryCtrl.text,
      "exclusionAnswers"    : _exclusionAnswers,
      "insufficientReason"  : _insufficientReason,
      "resuscitationReasons": _resuscitationReasons.toList(),
      "resuscitationOther"  : _resuscitationOther,
      "anomalyDetails"      : _anomalyDetails,
      "hydropsType"         : _hydropsType,
      "consentStatus"       : _consentStatus,
      "relationship"        : _relationshipToParticipant,
      "relationshipOther"   : _relationshipOtherText,
      "consentTakenBy"      : _consentTakenBy,
      "consentRefusalReasons": _consentRefusalReasons.toList(),
      "consentRefusalOther" : _consentRefusalOtherText,
      "notApproachedReasons": _notApproachedReasons.toList(),
      "notApproachedOther"  : _notApproachedOtherText,
      "videoPisShown"       : _videoPisShown,
      "proceedToConsent"    : _proceedToConsent,
    };

    await prefs.setString(_currentDraftKey!, jsonEncode(draft));
    await _addDraftKey(_currentDraftKey!);
    if (!mounted) return;
    if (!silent) _showDraftSavedMessage();
  }

  Future<void> _loadDraftIfExists() async {
    final prefs   = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(widget.draftKey!);
    if (jsonStr == null) return;

    final data = jsonDecode(jsonStr);
    setState(() {
      _assignedScreeningId       = data["screeningId"];
      _screeningIdCtrl.text      = _assignedScreeningId ?? "";
      _enrollmentId              = data["enrollmentId"]?.toString();
      _selectedSite              = data["site"] ?? _selectedSite;
      _idAssigned                = (_assignedScreeningId ?? "").isNotEmpty;
      // Real server IDs look like "01-0007"; LOCAL placeholders must still POST
      final sid = _assignedScreeningId ?? "";
      _serverConfirmedId = data["serverConfirmedId"] == true ||
          RegExp(r'^\d{2}-\d+$').hasMatch(sid);
      _screeningDateTimeCtrl.text= data["screeningDateTime"] ?? "";
      _screenedByCtrl.text       = data["screenedBy"] ?? "";
      _motherFirstCtrl.text      = data["motherFirst"] ?? data["motherFirstName"] ?? "";
      _motherSurnameCtrl.text    = data["motherSurname"] ?? "";
      _husbandFirstCtrl.text     = data["husbandFirst"] ?? "";
      _husbandSurnameCtrl.text   = data["husbandSurname"] ?? "";
      _motherPhoneCtrl.text      = data["motherPhone"] ?? "";
      _husbandPhoneCtrl.text     = data["husbandPhone"] ?? "";
      _maternalUidCtrl.text      = data["maternalUid"] ?? "";
      _hospitalNoCtrl.text       = data["hospitalNo"] ?? "";
      _gestationKnownInWeeks     = data["gestationKnownInWeeks"];
      _eddKnown                  = data["eddKnown"];
      _gaSource                  = data["gaSource"];
      _lmpCtrl.text              = data["lmpDate"] ?? "";
      _gestWeeksCtrl.text        = data["gestWeeks"] ?? "";
      _gestDaysCtrl.text         = data["gestDays"] ?? "0";
      _gaAssessmentMethod        = data["gaMethod"] ?? "Select";
      _expectedDeliveryCtrl.text = data["expectedDelivery"] ?? "";
      _exclusionAnswers
        ..clear()
        ..addAll(_parseExclusionAnswersMap(data["exclusionAnswers"]));
      _insufficientReason        = data["insufficientReason"] ?? "";
      if (_exclusionAnswers["INSUFFICIENT"] != "Yes") _insufficientReason = "";
      if (data["resuscitationReasons"] != null) {
        _resuscitationReasons = Set<String>.from(data["resuscitationReasons"]);
      } else if ((data["resuscitationReason"] ?? "").toString().isNotEmpty) {
        _resuscitationReasons = {data["resuscitationReason"].toString()};
      } else {
        _resuscitationReasons = {};
      }
      if (_exclusionAnswers["RESUSCITATION"] != "Yes") {
        _resuscitationReasons = {};
      }
      _resuscitationOther        = data["resuscitationOther"] ?? "";
      _anomalyDetails            = data["anomalyDetails"] ?? "";
      if (_exclusionAnswers["ANOMALY"] != "Yes") _anomalyDetails = "";
      _hydropsType               = data["hydropsType"] ?? "";
      if (_exclusionAnswers["HYDROPS"] != "Yes") _hydropsType = "";
      _consentStatus             = data["consentStatus"] ?? "Select";
      _relationshipToParticipant = data["relationship"] ?? "Select";
      _relationshipOtherText     = data["relationshipOther"] ?? "";
      _consentTakenBy            = (data["consentTakenBy"] as String?)?.isNotEmpty == true
          ? data["consentTakenBy"]
          : "Select";
      _consentRefusalReasons     = Set<String>.from(data["consentRefusalReasons"] ?? []);
      _consentRefusalOtherText   = data["consentRefusalOther"] ?? "";
      _notApproachedReasons      = Set<String>.from(data["notApproachedReasons"] ?? []);
      _notApproachedOtherText    = data["notApproachedOther"] ?? "";
      _videoPisShown             = data["videoPisShown"] ?? "Select";
      _proceedToConsent = _allExclusionsNo || _consentStatus != "Select";
      _previousYesExclusions = _exclusionAnswers.entries
          .where((e) => e.value == "Yes")
          .map((e) => e.key)
          .toSet();
      _currentDraftKey           = widget.draftKey;
      _hospitalNoLiveError       = _hospitalNoLiveMessage(_hospitalNoCtrl.text);
    });

    // Prefer LMP→GA when LMP is known; otherwise recompute from EDD.
    if (_gestationKnownInWeeks == false) {
      if (_gaSource == "LMP" && _lmpCtrl.text.trim().isNotEmpty) {
        final lmp = _parseDdMmYyyy(_lmpCtrl.text);
        if (lmp != null) {
          final edd = _eddFromLmp(lmp);
          setState(() {
            _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
            _setGestationFromLmp(lmp);
          });
        }
      } else if (_gaSource == "EDD" && _expectedDeliveryCtrl.text.trim().isNotEmpty) {
        final edd = _parseDdMmYyyy(_expectedDeliveryCtrl.text);
        if (edd != null) {
          setState(() => _setGestationFromEdd(edd));
        }
      }
    } else if (_gestationKnownInWeeks == true &&
        _gaAssessmentMethod == "LMP" &&
        _lmpCtrl.text.trim().isNotEmpty) {
      final lmp = _parseDdMmYyyy(_lmpCtrl.text);
      if (lmp != null) {
        final edd = _eddFromLmp(lmp);
        setState(() {
          _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
        });
      }
    }

    await _loadSiteScreeners();
  }

  DateTime? _parseDdMmYyyy(String raw) {
    try {
      final part = raw.trim().split(RegExp(r'\s+')).first;
      final d = part.split("/");
      if (d.length != 3) return null;
      return DateTime(int.parse(d[2]), int.parse(d[1]), int.parse(d[0]));
    } catch (_) {
      return null;
    }
  }

  Future<void> _addDraftKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getStringList(draftIndexKey) ?? [];
    if (!keys.contains(key)) {
      keys.add(key);
      await prefs.setStringList(draftIndexKey, keys);
    }
  }

  Future<void> _removeDraftKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getStringList(draftIndexKey) ?? [];
    keys.remove(key);
    await prefs.setStringList(draftIndexKey, keys);
  }

  // ── SUBMIT ─────────────────────────────────────────────────────────────────

  // ── FIX: _submit is now a Future<bool> so callers can await it and act on result ──
  Future<bool> _submit() async {
    _submitted = true;

    if (_assignedScreeningId == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Screening ID could not be assigned")));
      return false;
    }

    if ((_gestationKnownInWeeks == true || _eddKnown == true) &&
        !_validateExclusionCompleted()) {
      setState(() => _submitted = true);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please answer all exclusion criteria (Yes / No)")));
      return false;
    }

    if (_exclusionPresent && !_validateExclusionSubOptions()) {
      setState(() => _submitted = true);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please complete all required exclusion details")));
      return false;
    }

    final weeksParsed = int.tryParse(_gestWeeksCtrl.text.trim());
    final days        = int.tryParse(_gestDaysCtrl.text.trim()) ?? 0;

    try {
      // Sync to shared backend FIRST so web + mobile stay aligned.
      final syncResp = await _syncToBackend(isDraft: false);
      final serverStatus = syncResp?['screening_status']?.toString();
      final eligibility = (serverStatus != null && serverStatus.isNotEmpty)
          ? normalizeScreeningStatus(serverStatus)
          : computeScreeningStatus(
              gestationWeeks: weeksParsed,
              gestationDays: days,
              exclusionPresent:
                  _allExclusionsAnswered ? _exclusionPresent : null,
              consentGiven:
                  _consentStatus != "Select" ? _consentStatus : null,
              gestationKnown: _gestationKnownInWeeks == true
                  ? "Yes"
                  : (_gestationKnownInWeeks == false ? "No" : null),
              gaSource:
                  _gestationKnownInWeeks == false ? _gaSource : null,
            );

      final crf = CRF(
        screeningId         : _assignedScreeningId!,
        site                : _selectedSite,
        siteId              : _siteMap[_selectedSite] ?? "",
        screeningDateTime   : _screeningDateTimeCtrl.text.trim(),
        screenedBy          : _screenedByCtrl.text.trim(),
        motherFirstName     : _motherFirstCtrl.text.trim(),
        motherSurname       : _motherSurnameCtrl.text.trim(),
        husbandFirstName    : _husbandFirstCtrl.text.trim(),
        husbandSurname      : _husbandSurnameCtrl.text.trim(),
        motherPhone         : _motherPhoneCtrl.text.trim(),
        husbandPhone        : _husbandPhoneCtrl.text.trim(),
        maternalUid         : _maternalUidCtrl.text.trim(),
        hospitalNo          : _hospitalNoCtrl.text.trim(),
        gestationWeeks      : weeksParsed ?? 0,
        gestationDays       : days,
        gestationMethod     : _gaAssessmentMethod,
        expectedDeliveryDate: _expectedDeliveryCtrl.text.trim(),
        gestationKnownInWeeks: _gestationKnownInWeeks == true,
        eddKnown            : _eddKnown == true,
        exclusion           : _exclusionPresent,
        exclusionReason     : _exclusionAnswers.entries
            .where((e) => e.value == "Yes")
            .map((e) => e.key)
            .join("; "),
        anomalyDetails      : _anomalyDetails,
        eligibilityStatus   : eligibility,
        consentStatus       : _consentStatus,
        consentRefusalReason: _consentStatus == "No" && _consentRefusalReasons.isNotEmpty
            ? _consentRefusalReasons.join(", ")
            : "",
        relationshipToParticipant: _relationshipToParticipant,
        relationshipOther   : _relationshipOtherText,
        consentTakenBy      : _consentTakenBy != "Select" ? _consentTakenBy : "",
        enrollmentId        : _enrollmentId ?? "",
      );

      // Local device CRF store (best-effort — must not block draft cleanup).
      try {
        await _api.saveCRF(crf);
      } catch (_) {}

      // ignore: unawaited_futures
      PdfService.generateCrfPdf(crf);

      // Always drop local draft once the server has the final record.
      await _clearLocalDraft();

      return true; // signal success to caller

    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to save: $e")));
      return false;
    }
  }

  // ── FIX: _confirmSaveAndClose is async, awaits _submit, then pops ──
  Future<void> _confirmSaveAndClose() async {
    print("SAVE & CLOSE CLICKED");
   if (_gestationKnownInWeeks == false && _eddKnown == false) {
     _showScreeningEndedPopup();
     return;
   }

  final weeks = int.tryParse(_gestWeeksCtrl.text);
  final days = int.tryParse(_gestDaysCtrl.text);

  if (weeks != null && days != null) {
    final totalDays = (weeks * 7) + days;

    if (totalDays < (25 * 7) ||
        totalDays > (31 * 7) + 6) {
      _showGestationOutOfRangePopup();
      return;
    }
  }

  final c = AppTheme.of(context);

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        "Confirm Save",
        style: TextStyle(
          color: c.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        "Are you sure you want to save and close?",
        style: TextStyle(
          color: c.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            "No",
            style: TextStyle(
              color: c.textTertiary,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("Yes"),
        ),
      ],
    ),
  );

  if (confirm != true) return;
  if (!mounted) return;

  // Show a non-dismissible spinner while syncing to the backend so the
  // screen doesn't just appear frozen on a slow connection.
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final success = await _submit();

  if (!mounted) return;
  Navigator.pop(context); // close the spinner

  if (!mounted) return;

  if (success) {
    print("ABOUT TO POP");
  Navigator.pop(context, true);
}
}
  // ── POPUPS ─────────────────────────────────────────────────────────────────

  void _showScreeningEndedPopup() {
    final c = AppTheme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.cancel_rounded, color: c.danger, size: 20),
          const SizedBox(width: 8),
          Text("Screening Ended",
              style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        content: Text(
          "Gestational age cannot be determined.\n\nPlease do not proceed with screening. Your progress was saved and will show on the web portal for this site.",
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: c.danger, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              await _saveDraft(silent: true);
              if (!context.mounted) return;
              Navigator.pop(context); // close dialog
              Navigator.pop(context, true); // go back to dashboard
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showGestationOutOfRangePopup() {
    final c = AppTheme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: c.danger, size: 20),
          const SizedBox(width: 8),
          Text("Screening Ended",
              style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        content: Text(
          "Gestational age is outside the eligible range (25+0 to 31+6 weeks).\n\nScreening has been ended. Your progress was saved and will show on the web portal for this site.",
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: c.danger, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              await _saveDraft(silent: true);
              if (!context.mounted) return;
              Navigator.pop(context); // close dialog
              Navigator.pop(context, true); // go back to dashboard
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ── QR SCAN ────────────────────────────────────────────────────────────────

  Future<void> _scanCRNumber() async {
    final c = AppTheme.of(context);
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 320, height: 320,
          child: MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue ?? "";
              if (code.isNotEmpty) {
                Navigator.pop(context);
                _maternalUidCtrl.text = code;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("Scanned: $code")));
              }
            },
          ),
        ),
      ),
    );
  }

  void _showDraftSavedMessage() {
    if (!mounted) return;
    final c = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.warning.withOpacity(0.4))),
        content: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: c.warningSoft, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.save_rounded, color: c.warning, size: 18),
          ),
          const SizedBox(width: 12),
          Text("Draft saved successfully",
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
        ]),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollToFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _formKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut, alignment: 0.1);
    });
  }

  Future<void> saveFormAToFirebase(Map<String, dynamic> data) async {
    final id = data['screeningId'];
    // Firebase removed — data saved to PORTAL backend
  }

  Future<void> _applySiteChange(String newSite) async {
    setState(() {
      _selectedSite = newSite;
      _screenedByCtrl.text = "Select";
      _consentTakenBy = "Select";
      _siteScreeners = [];
    });
    await _loadSiteScreeners();
  }

  Future<void> _onSiteChangedWithConfirm(String? newSite) async {
    if (newSite == null || newSite == _selectedSite) return;
    if (_selectedSite.isEmpty) {
      await _applySiteChange(newSite);
      return;
    }
    final c = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Change site?",
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800)),
        content: Text("Changing site will affect Screening ID assignment. Continue?",
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text("Cancel", style: TextStyle(color: c.textTertiary))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Yes, update")),
        ],
      ),
    );
    if (confirmed == true) {
      await _applySiteChange(newSite);
    } else {
      setState(() {});
    }
  }

  // ── DECORATIONS ───────────────────────────────────────────────────────────

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
    String? helper,
    bool required = false,
  }) {
    final c = AppTheme.of(context);
    final labelStyle = TextStyle(color: c.textSecondary, fontSize: 13);
    return InputDecoration(
      // Red * for mandatory fields (not black labelText "*").
      label: requiredLabel(label, style: labelStyle, required: required),
      hintText   : hint,
      helperText : helper,
      helperStyle: TextStyle(color: c.textTertiary, fontSize: 12),
      labelStyle : labelStyle,
      floatingLabelStyle: labelStyle,
      hintStyle  : TextStyle(color: c.textTertiary,  fontSize: 13),
      filled     : true,
      fillColor  : c.surfaceAlt,
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

  InputDecoration _requiredDecoration(String label, {String? hint, String? helper}) =>
      _inputDecoration(label, hint: hint, helper: helper, required: true);

  Widget _reqText(String label, AppColors c, {double fontSize = 13}) =>
      requiredLabel(
        label,
        style: TextStyle(color: c.textSecondary, fontSize: fontSize),
        required: true,
      );

  // ── SECTION CARD ──────────────────────────────────────────────────────────

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? trailing,
    Color? accentColor,
  }) {
    final c     = AppTheme.of(context);
    final color = accentColor ?? c.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
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
            Container(width: 3, height: 16,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: c.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: .4)),
            if (trailing != null) ...[const Spacer(), trailing],
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]),
    );
  }

  // ── NUMBER STEPPER ────────────────────────────────────────────────────────

  Widget _numberStepper({
    required TextEditingController controller,
    required int min,
    required int max,
    /// First +/- tap on an empty field snaps here (weeks: 25, the eligibility floor).
    int? emptySnapTo,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    final c = AppTheme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
              color: c.surfaceAlt, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border)),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger, size: 20),
              onPressed: () {
                final parsed = int.tryParse(controller.text);
                final snap = emptySnapTo ?? min;
                setState(() {
                  if (parsed == null) {
                    controller.text = "$snap";
                  } else if (parsed > min) {
                    controller.text = "${parsed - 1}";
                  }
                });
              },
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                readOnly: !enabled,
                validator: validator,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: c.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 16),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: c.success, size: 20),
              onPressed: () {
                final parsed = int.tryParse(controller.text);
                final snap = emptySnapTo ?? min;
                setState(() {
                  if (parsed == null) {
                    controller.text = "$snap";
                  } else if (parsed < max) {
                    controller.text = "${parsed + 1}";
                  }
                });
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ── EXCLUSION YES/NO ──────────────────────────────────────────────────────

  Widget _exclusionYesNo(String key, String label) {
    final c = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _exclusionAnswers[key] == "Yes"
                ? c.danger.withOpacity(0.4)
                : _exclusionAnswers[key] == "No"
                    ? c.success.withOpacity(0.3)
                    : c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(children: [
                _yesNoChip("Yes", key, c.danger),
                const SizedBox(width: 8),
                _yesNoChip("No",  key, c.success),
              ]),
              if (_exclusionAnswers[key] == null && _submitted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("Required", style: TextStyle(color: c.danger, fontSize: 12)),
                ),
              if (_exclusionAnswers[key] == "Yes") ...[
                const SizedBox(height: 12),
                _exclusionSubFields(key, c),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _yesNoChip(String value, String key, Color color) {
    final c        = AppTheme.of(context);
    final selected = _exclusionAnswers[key] == value;
    return GestureDetector(
      key: ValueKey('excl-$key-$value'),
      onTap: () => setState(() {
        _exclusionAnswers[key] = value;
        if (value == "No") {
          switch (key) {
            case "INSUFFICIENT":
              _insufficientReason = "";
              break;
            case "RESUSCITATION":
              _resuscitationReasons = {};
              _resuscitationOther = "";
              break;
            case "ANOMALY":
              _anomalyDetails = "";
              break;
            case "HYDROPS":
              _hydropsType = "";
              break;
          }
        }
        _checkExclusionAndAlert();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : c.border, width: 1.5),
        ),
        child: Text(value,
            style: TextStyle(
                color: selected ? color : c.textSecondary,
                fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }

  Widget _exclusionSubFields(String key, AppColors c) {
    switch (key) {
      case "INSUFFICIENT":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            decoration: _requiredDecoration("24. If yes, specify"),
            style: TextStyle(color: c.textPrimary),
            onChanged: (v) => _insufficientReason = v,
          ),
          if (_submitted && _insufficientReason.trim().isEmpty)
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Required", style: TextStyle(color: c.danger, fontSize: 12))),
        ]);

      case "RESUSCITATION":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _reqText("22. If yes (select all that apply)", c),
          const SizedBox(height: 6),
          ...["Periviable", "Socio-economic", "Major CMF", "Other"].map((v) =>
              _multiCheckboxTile(v, _resuscitationReasons, c, () => setState(() {
                if (_resuscitationReasons.contains(v)) {
                  _resuscitationReasons.remove(v);
                } else {
                  _resuscitationReasons.add(v);
                }
              }))),
          if (_submitted && _resuscitationReasons.isEmpty)
            Text("Please select at least one reason", style: TextStyle(color: c.danger, fontSize: 12)),
          if (_resuscitationReasons.contains("Other")) ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: _requiredDecoration("Please specify…"),
              style: TextStyle(color: c.textPrimary),
              onChanged: (v) => _resuscitationOther = v,
              validator: (v) {
                if (_submitted &&
                    _resuscitationReasons.contains("Other") &&
                    (v == null || v.trim().isEmpty)) return "Required";
                return null;
              },
            ),
            if (_submitted && _resuscitationOther.trim().isEmpty)
              Text("Required", style: TextStyle(color: c.danger, fontSize: 12)),
          ],
        ]);

      case "ANOMALY":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            decoration: _requiredDecoration("If yes, specify"),
            style: TextStyle(color: c.textPrimary),
            onChanged: (v) => _anomalyDetails = v,
          ),
          if (_submitted && _anomalyDetails.trim().isEmpty)
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Required", style: TextStyle(color: c.danger, fontSize: 12))),
        ]);

      case "HYDROPS":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _reqText("20. If yes", c),
          const SizedBox(height: 6),
          ...["Immune", "Non-immune", "Unclear"].map((v) =>
              _styledRadio(v, _hydropsType, c, (val) =>
                  setState(() => _hydropsType = val!))),
          if (_submitted && _hydropsType.isEmpty)
            Text("Please select hydrops type", style: TextStyle(color: c.danger, fontSize: 12)),
        ]);

      default:
        return const SizedBox.shrink();
    }
  }

  // Same visual language as _styledRadio, but a square checkbox indicator
  // (not a circle) to visually signal "multi-select" vs "pick one", and
  // toggles membership in a Set instead of replacing a single value.
  Widget _multiCheckboxTile(String value, Set<String> selectedSet, AppColors c,
      VoidCallback onToggle) {
    final selected = selectedSet.contains(value);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary.withOpacity(0.14) : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: selected ? c.primary : c.border, width: 2),
              color: selected ? c.primary : Colors.transparent,
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 12) : null,
          ),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(
              color: selected ? c.primaryDark : c.textSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _styledRadio(String value, String groupValue, AppColors c,
      void Function(String?) onChanged) {
    final selected = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primarySoft : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c.primary : c.border),
        ),
        child: Row(children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? c.primary : c.border, width: 2),
              color: selected ? c.primary : Colors.transparent,
            ),
            child: selected ? Icon(Icons.circle, color: Colors.white, size: 8) : null,
          ),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(
              color: selected ? c.primary : c.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13)),
        ]),
      ),
    );
  }

  // ── STEP INDICATOR ────────────────────────────────────────────────────────

  Widget _buildStepIndicator(AppColors c) {
    final steps = ["Gestation", "Identification", "Exclusion", "Consent"];
    int activeStep = 0;
    if (_gestationKnownInWeeks != null) activeStep = 1;
    if (_isEligibleGestation && activeStep >= 1) activeStep = 2;
    if (_allExclusionsAnswered && activeStep >= 2) activeStep = 3;
    if (_proceedToConsent) activeStep = 4;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIdx = i ~/ 2;
          final done = stepIdx < activeStep;
          return Expanded(child: Container(
            height: 2,
            color: done ? c.primary : c.border,
          ));
        }
        final stepIdx = i ~/ 2;
        final done    = stepIdx < activeStep;
        final current = stepIdx == activeStep;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? c.primary : current ? c.primarySoft : c.surfaceAlt,
              border: Border.all(
                  color: done || current ? c.primary : c.border, width: 1.5),
            ),
            child: Center(
              child: done
                  ? Icon(Icons.check_rounded, color: Colors.white, size: 13)
                  : Text("${stepIdx + 1}",
                      style: TextStyle(
                          color: current ? c.primary : c.textTertiary,
                          fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          Text(steps[stepIdx],
              style: TextStyle(
                  color: done || current ? c.primary : c.textTertiary,
                  fontSize: 9, fontWeight: FontWeight.w600)),
        ]);
      })),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final nameFormatter = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r"[\p{L} .'\-]", unicode: true)),
    ];

    return WillPopScope(
      onWillPop: () async {
        if (widget.viewOnly) return true;
        if (_submitted) return true;
        if (_isFormCompletelyEmpty()) return true;

        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text("Leave this form?",
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800)),
            content: Text("Your progress will be saved as draft.",
                style: TextStyle(color: c.textSecondary)),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text("Stay", style: TextStyle(color: c.textTertiary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: c.danger, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text("Leave", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (shouldLeave == true) {
          await _saveDraft();
          return true;
        }
        return false;
      },

      child: Scaffold(
        backgroundColor: c.bg,
        appBar: _buildAppBar(c),
        bottomNavigationBar: widget.viewOnly ? null : _buildBottomBar(c),
        body: _loadingExisting
            ? const Center(child: CircularProgressIndicator())
            : Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [c.bgGradTop, c.bg], stops: const [0.0, 0.35],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: AbsorbPointer(
                absorbing: widget.viewOnly,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      if (widget.viewOnly) ...[
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
                            "View only — previously filled Form A (Screening)",
                            style: TextStyle(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],

                      _buildStepIndicator(c),

                      _buildGestationSection(c),

                      if (_isEligibleGestation) _buildIdentificationSection(c, nameFormatter),

                      if (_isEligibleGestation) _buildExclusionSection(c),

                      // Match web: show A5 when all exclusions No, or consent already saved
                      if (_isEligibleGestation &&
                          (_allExclusionsNo ||
                              (_consentStatus != "Select" &&
                                  _consentStatus.isNotEmpty)))
                        _buildConsentSection(c),

                      if (_submitted && _formKey.currentState?.validate() == false)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: c.dangerSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.danger.withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline, color: c.danger),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              "Please fill all mandatory fields highlighted in red",
                              style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                            )),
                          ]),
                        ),

                      // Same as web NotesBox — optional local notes keyed by screening id.
                      NotesBox(
                        formKey: "form_a_${(_assignedScreeningId != null && _assignedScreeningId!.isNotEmpty) ? _assignedScreeningId! : "new"}",
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(AppColors c) {
    return AppBar(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 66,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.borderLight),
      ),
      title: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Form A : Screening",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: c.textPrimary, letterSpacing: .3)),
        const SizedBox(height: 2),
        Text("Eligibility Assessment · 25 weeks 0 days to 31 weeks 6 days",
            style: TextStyle(fontSize: 11, color: c.primary.withOpacity(0.7),
                fontWeight: FontWeight.w500)),
      ]),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: Center(child: ThemeToggle()),
        ),
        GestureDetector(
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: c.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text("Logout?",
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800)),
                content: Text("Are you sure you want to logout?",
                    style: TextStyle(color: c.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: Text("Cancel", style: TextStyle(color: c.textTertiary))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: c.danger, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Logout"),
                  ),
                ],
              ),
            );
            if (confirm == true) await _logout();
          },
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: c.dangerSoft, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.danger.withOpacity(0.2))),
            child: Icon(Icons.logout_rounded, color: c.danger, size: 18),
          ),
        ),
      ],
    );
  }

  // ── STICKY BOTTOM BAR ─────────────────────────────────────────────────────

  Widget _buildBottomBar(AppColors c) {
    // SafeArea keeps buttons above tablet/system nav bars.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderLight)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(children: [
        // Save as Draft
        if (!(_gestationKnownInWeeks == false && _eddKnown == false))
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.save_outlined, size: 16, color: c.warning),
              label: Text("Save for Later", style: TextStyle(color: c.warning, fontWeight: FontWeight.w700, fontSize: 12)),
              onPressed: () async {
                await _saveDraft();
                if (!mounted) return;
                Navigator.of(context).pop(true); // ── FIX: return to dashboard after saving draft ──
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.warning.withOpacity(0.5)),
                backgroundColor: c.warningSoft,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

        const SizedBox(width: 10),

        // Save & Close
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
            label: const Text("Save",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            // ── FIX: onPressed is async, _confirmSaveAndClose is awaited ──
            onPressed: () async {
              setState(() => _submitted = true);
              if (_formKey.currentState?.validate() != true) {
                _scrollToFirstError();
                return;
              }
              if (_gestationKnownInWeeks == false && _eddKnown == false) {
                _showScreeningEndedPopup(); return;
              }
              if (_isGestationOutOfRange()) {
                _showGestationOutOfRangePopup(); return;
              }
              if ((_gestationKnownInWeeks == true || _eddKnown == true) &&
                  !_validateExclusionCompleted()) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please answer all exclusion criteria")));
                return;
              }
              await _confirmSaveAndClose(); // ── FIX: awaited ──
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.success,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),

        const SizedBox(width: 10),

        // Cancel — saves draft and returns to dashboard
        Expanded(
          child: OutlinedButton(
            onPressed: () async {
              await _saveDraft();
              if (!mounted) return;
              Navigator.of(context).pop(true); // ── FIX: always pop after cancel ──
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.border),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Cancel",
                style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ),
    );
  }

  // ── GESTATION SECTION ─────────────────────────────────────────────────────

  Widget _buildGestationSection(AppColors c) {
    return _sectionCard(
      title: "A1 · Screening",
      icon: Icons.pregnant_woman_rounded,
      accentColor: c.primary,
      children: [
        Text("1. Gestation in weeks clearly mentioned",
            style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gestRadio("Yes", true, c)),
          const SizedBox(width: 8),
          Expanded(child: _gestRadio("No",  false, c)),
        ]),

        if (_gestationKnownInWeeks == true) ...[
          const SizedBox(height: 18),
          Text("2. Best estimate gestational age — Weeks",
              style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Weeks", style: TextStyle(color: c.textTertiary, fontSize: 12)),
              const SizedBox(height: 6),
              // Web Q2: number input min 10 max 45 (eligibility banner is 25w0d–31w6d).
              _numberStepper(
                controller: _gestWeeksCtrl,
                min: 10,
                max: 45,
                emptySnapTo: 25,
                validator: (v) {
                  if (!_submitted) return null;
                  if (v == null || v.trim().isEmpty) return "Required";
                  final n = int.tryParse(v);
                  if (n == null || n < 10 || n > 45) {
                    return "Must be between 10 and 45 weeks";
                  }
                  return null;
                },
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Days", style: TextStyle(color: c.textTertiary, fontSize: 12)),
              const SizedBox(height: 6),
              _numberStepper(
                controller: _gestDaysCtrl,
                min: 0,
                max: 6,
                validator: (v) {
                  if (!_submitted) return null;
                  if (v == null || v.trim().isEmpty) return "Required";
                  final n = int.tryParse(v);
                  if (n == null || n < 0 || n > 6) return "Must be 0–6 days";
                  return null;
                },
              ),
            ])),
          ]),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _gaAssessmentMethod,
            dropdownColor: c.surface,
            decoration: _requiredDecoration("3. Method of gestation assessment"),
            items: [
              _ddItem("Select", c, hint: true),
              _ddItem("LMP", c),
              _ddItem("Early USG (<24w)", c),
              _ddItem("Fundal Height", c),
              _ddItem("Method not known", c),
            ],
            onChanged: (v) => setState(() {
              _gaAssessmentMethod = v!;
              if (v != "LMP") {
                _lmpCtrl.clear();
                _expectedDeliveryCtrl.clear();
              }
            }),
            style: TextStyle(color: c.textPrimary),
          ),

          // Web uses the same number "3." for LMP date when method = LMP.
          if (_gaAssessmentMethod == "LMP") ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _lmpCtrl, readOnly: true,
              decoration: _requiredDecoration("3. LMP date").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showModernDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _lmpCtrl.text = "${picked.day}/${picked.month}/${picked.year}";
                  final edd = _eddFromLmp(picked);
                  _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _expectedDeliveryCtrl, readOnly: true,
              decoration: _inputDecoration("EDD (auto-calculated from LMP)"),
              style: TextStyle(color: c.textPrimary),
            ),
          ],

          // Field 7 comes after method (3.) — same order as web Form A.
          if (_gestWeeksCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _gestationResultBanner(c),
          ],
        ],

        if (_gestationKnownInWeeks == false) ...[
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            value: _gaSource ?? "Select",
            dropdownColor: c.surface,
            decoration: _requiredDecoration("4. If No, is any of the following known?"),
            items: [
              _ddItem("Select", c, hint: true),
              _ddItem("LMP", c), _ddItem("EDD", c), _ddItem("Neither", c),
            ],
            onChanged: (v) {
              setState(() {
                _gaSource = (v == null || v == "Select") ? null : v;
                _eddKnown = (_gaSource == "LMP" || _gaSource == "EDD");
                _lmpCtrl.clear();
                _expectedDeliveryCtrl.clear();
                _gestWeeksCtrl.clear();
                _gestDaysCtrl.clear();
              });
            },
            style: TextStyle(color: c.textPrimary),
          ),

          if (_gaSource == "LMP") ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _lmpCtrl, readOnly: true,
              decoration: _requiredDecoration("5. If LMP known, LMP").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showModernDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _lmpCtrl.text = "${picked.day}/${picked.month}/${picked.year}";
                  final edd = _eddFromLmp(picked);
                  _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
                  // Prefer LMP→GA directly (avoids wrong GA from a stale EDD).
                  _setGestationFromLmp(picked);
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _expectedDeliveryCtrl, readOnly: true,
              decoration: _inputDecoration("EDD (auto-calculated in app)"),
              style: TextStyle(color: c.textPrimary),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: _inputDecoration(
                  "7. Calculated gestational age (auto calculated in app)"),
              child: Text(
                _gestWeeksCtrl.text.trim().isEmpty
                    ? "____ weeks ; ____ days"
                    : "${_gestWeeksCtrl.text} weeks ; ${_gestDaysCtrl.text.isEmpty ? "0" : _gestDaysCtrl.text} days",
                style: TextStyle(
                    color: _gestWeeksCtrl.text.trim().isEmpty
                        ? c.textTertiary
                        : c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
          ],

          if (_gaSource == "EDD") ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _expectedDeliveryCtrl, readOnly: true,
              decoration: _requiredDecoration("6. If LMP not known, EDD").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showModernDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1900), lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _expectedDeliveryCtrl.text =
                      "${picked.day}/${picked.month}/${picked.year}";
                  _setGestationFromEdd(picked);
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: _inputDecoration(
                  "7. Calculated gestational age (auto calculated in app)"),
              child: Text(
                _gestWeeksCtrl.text.trim().isEmpty
                    ? "____ weeks ; ____ days"
                    : "${_gestWeeksCtrl.text} weeks ; ${_gestDaysCtrl.text.isEmpty ? "0" : _gestDaysCtrl.text} days",
                style: TextStyle(
                    color: _gestWeeksCtrl.text.trim().isEmpty
                        ? c.textTertiary
                        : c.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
          ],

          if ((_gaSource == "LMP" || _gaSource == "EDD") &&
              _gestWeeksCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _gestationResultBanner(c),
          ],

          if (_gaSource == "Neither") ...[
            const SizedBox(height: 16),
            _infoBanner(
              icon: Icons.warning_amber_rounded,
              text: "Gestational age cannot be determined.\nEnd participation.",
              color: c.danger, softColor: c.dangerSoft, c: c,
            ),
          ],
        ],
      ],
    );
  }

  Widget _gestRadio(String label, bool value, AppColors c) {
    final selected = _gestationKnownInWeeks == value;
    final color    = value ? c.success : c.danger;
    return GestureDetector(
      onTap: () {
        setState(() {
          _gestationKnownInWeeks = value;
          _gaSource = null;
          _eddKnown = null;
          // Match web: do not pre-fill 25+0 — weeks/days stay empty until entered.
          _gestWeeksCtrl.text = "";
          _gestDaysCtrl.text = "";
          _gaAssessmentMethod = "Select";
          _lmpCtrl.clear();
          _expectedDeliveryCtrl.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : c.border, width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? color : c.border, width: 2),
              color: selected ? color : Colors.transparent,
            ),
            child: selected ? const Icon(Icons.circle, color: Colors.white, size: 8) : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              color: selected ? color : c.textSecondary,
              fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _gestationResultBanner(AppColors c) {
    final weeks = int.tryParse(_gestWeeksCtrl.text) ?? 0;
    final days  = int.tryParse(_gestDaysCtrl.text)  ?? 0;
    final inRange = (() {
      final t = weeks * 7 + days;
      return t >= 25 * 7 && t <= 31 * 7 + 6;
    })();
    final tooHigh = weeks * 7 + days > 31 * 7 + 6;
    final color   = inRange ? c.success : c.danger;
    final soft    = inRange ? c.successSoft : c.dangerSoft;
    final weeksText = _gestWeeksCtrl.text.trim().isEmpty ? "____" : _gestWeeksCtrl.text;
    final daysText = _gestDaysCtrl.text.trim().isEmpty ? "____" : _gestDaysCtrl.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("7. Calculated gestational age (auto calculated in app)",
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            Text("$weeksText weeks ; $daysText days",
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              inRange
                  ? "Participant is eligible for the study."
                  : "Participant is not eligible for the study.",
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        if (tooHigh) ...[
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.cancel_rounded,
            text: "If ≥32 weeks – cannot proceed. Gestational age is outside the eligibility window (25 weeks 0 days to 31 weeks 6 days).",
            color: c.danger, softColor: c.dangerSoft, c: c,
          ),
        ],
        if (!inRange && !tooHigh && _gestWeeksCtrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.cancel_rounded,
            text: "Gestational age <25 weeks — outside eligibility window (25w0d–31w6d). Cannot proceed.",
            color: c.danger, softColor: c.dangerSoft, c: c,
          ),
        ],
      ],
    );
  }

  Widget _infoBanner({required IconData icon, required String text,
      required Color color, required Color softColor, required AppColors c}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: softColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(
            color: color, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  DropdownMenuItem<String> _ddItem(String v, AppColors c, {bool hint = false}) =>
      DropdownMenuItem(
        value: v,
        child: Text(v, style: TextStyle(
            color: hint ? c.textTertiary : c.textPrimary, fontSize: 13)),
      );

  // ── IDENTIFICATION SECTION ────────────────────────────────────────────────

  Widget _buildIdentificationSection(AppColors c, List<TextInputFormatter> nameFormatter) {
    return _sectionCard(
      title: "A2 · Identification",
      icon: Icons.badge_rounded,
      accentColor: c.primary,
      children: [
        TextFormField(
          controller: _screeningIdCtrl, readOnly: true,
          decoration: _inputDecoration("8. Screening ID (auto filled)"),
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _siteMap.containsKey(_selectedSite) ? _selectedSite : null,
              hint: Text("-- Select Site --",
                  style: TextStyle(color: c.textTertiary)),
              dropdownColor: c.surface,
              decoration: _requiredDecoration("9. Site"),
              items: _siteMap.keys.map((s) =>
                  DropdownMenuItem(value: s,
                      child: Text(s, style: TextStyle(color: c.textPrimary)))).toList(),
              onChanged: _siteLocked
                  ? null
                  : (v) async => _onSiteChangedWithConfirm(v),
              validator: (v) =>
                  _submitted && (v == null || v.isEmpty) ? "Required" : null,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              readOnly: true,
              controller: TextEditingController(text: _siteMap[_selectedSite] ?? ""),
              decoration: _inputDecoration("10. Site ID (auto filled)"),
              style: TextStyle(color: c.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        TextFormField(
          controller: _screeningDateTimeCtrl, readOnly: true,
          decoration: _requiredDecoration("11. Screening Date & Time", hint: "Tap to choose").copyWith(
            suffixIcon: Icon(Icons.access_time_rounded, color: c.textTertiary, size: 18),
          ),
          style: TextStyle(color: c.textPrimary),
          validator: _screeningDateValidator,
          onTap: () async {
            final now = DateTime.now();
            final pickedDate = await showModernDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(1900),
              lastDate: now,
            );
            if (pickedDate != null) {
              final pickedTime = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now());
              if (pickedTime != null) {
                _screeningDateTimeCtrl.text =
                    "${pickedDate.day.toString().padLeft(2, '0')}/"
                    "${pickedDate.month.toString().padLeft(2, '0')}/"
                    "${pickedDate.year}  "
                    "${pickedTime.hour.toString().padLeft(2, '0')}:"
                    "${pickedTime.minute.toString().padLeft(2, '0')}";
                setState(() {});
              }
            }
          },
        ),
        const SizedBox(height: 12),

        Builder(builder: (_) {
          final opts = _consentNurseOptions();
          final cur = _screenedByCtrl.text.trim();
          final value = cur.isEmpty
              ? "Select"
              : (opts.contains(cur) || cur == "Select" ? cur : cur);
          return DropdownButtonFormField<String>(
            value: value,
            decoration: _requiredDecoration("12. Screened by (First name)"),
            dropdownColor: c.surface,
            items: [
              _ddItem("Select", c, hint: true),
              if (cur.isNotEmpty && cur != "Select" && !opts.contains(cur))
                _ddItem(cur, c),
              ...opts.map((n) => _ddItem(n, c)),
            ],
            onChanged: (v) => setState(() {
              _screenedByCtrl.text = (v == null || v == "Select") ? "" : v;
            }),
            validator: (v) => _submitted && (v == null || v == "Select" || v.trim().isEmpty)
                ? "Required" : null,
            style: TextStyle(color: c.textPrimary),
          );
        }),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 3, height: 14,
                decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text("A3 · Maternal Identification",
                style: TextStyle(color: c.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .3)),
          ]),
        ),

        if (_duplicateWarn.isNotEmpty) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.warning.withOpacity(0.35)),
            ),
            child: Text(_duplicateWarn,
                style: TextStyle(color: c.warning, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],

        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _motherFirstCtrl,
              onChanged: (_) {
                _assignScreeningIdIfNeeded();
                _checkDuplicateMotherName();
              },
              decoration: _requiredDecoration("13. Mother's Name — First"),
              validator: (v) => _submitted ? _charOnlyValidator(v) : null,
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _motherSurnameCtrl,
              decoration: _inputDecoration("Surname"),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty &&
                    !RegExp(r"^[\p{L} .'\-]+$", unicode: true).hasMatch(v.trim())) {
                  return "Letters only";
                }
                return null;
              },
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _husbandFirstCtrl,
              decoration: _requiredDecoration("14. Husband's Name — First"),
              validator: (v) => _submitted ? _charOnlyValidator(v) : null,
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _husbandSurnameCtrl,
              decoration: _inputDecoration("Surname"),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty &&
                    !RegExp(r"^[\p{L} .'\-]+$", unicode: true).hasMatch(v.trim())) {
                  return "Letters only";
                }
                return null;
              },
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _maternalUidCtrl,
                focusNode: _maternalUidFocus,
                keyboardType: _selectedSite == "PGIMER"
                    ? TextInputType.number
                    : TextInputType.text,
                inputFormatters: _maternalUidFormatters(),
                decoration: _requiredDecoration(_maternalUidLabel())
                    .copyWith(counterText: ""),
                validator: (v) => _submitted ? _maternalUidValidator(v) : null,
                onChanged: (v) => setState(() {
                  final max = _maternalUidMaxLen();
                  _maternalUidLimitReached = v.length >= max;
                  _maternalUidCount = v.length;
                }),
                style: TextStyle(color: c.textPrimary),
              ),
              if (_maternalUidFocus.hasFocus && _maternalUidLimitReached)
                Padding(padding: const EdgeInsets.only(top: 3),
                    child: Text(_selectedSite == "PGIMER"
                            ? "Maximum 12 digits reached"
                            : "Maximum length reached",
                        style: TextStyle(color: c.success,
                            fontSize: 11, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(width: 12),
          ScaleTransition(
            scale: _scanAnimation,
            child: GestureDetector(
              onTap: _scanCRNumber,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c.primary, c.primaryDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                      color: c.primary.withOpacity(0.35),
                      blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 26),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        TextFormField(
          controller: _hospitalNoCtrl,
          keyboardType: const {"PGIMER", "GMCH-A", "GMCH", "IOG"}
                  .contains(_selectedSite)
              ? TextInputType.number
              : TextInputType.text,
          inputFormatters: _hospitalNoFormatters(),
          decoration: (_selectedSite == "PGIMER"
                  ? _requiredDecoration("16. Hospital Admission Number")
                  : _inputDecoration(_hospitalNoLabel()))
              .copyWith(
            errorText: _hospitalNoLiveError,
            hintText: _hospitalNoHint(),
          ),
          validator: (v) => _submitted ? _hospitalNoValidator(v) : null,
          onChanged: (v) => setState(() {
            _hospitalNoLiveError = _hospitalNoLiveMessage(v);
          }),
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _motherPhoneCtrl,
                focusNode: _motherPhoneFocus,
                decoration: _requiredDecoration("17. Mobile Number — Mother"),
                keyboardType: TextInputType.number,
                style: TextStyle(color: c.textPrimary),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (v) => _submitted ? _phoneValidator(v) : null,
                onChanged: (value) => setState(() {
                  _motherPhoneCount       = value.length;
                  _motherMobileLimitReached = value.length >= 10;
                }),
              ),
              if (_motherPhoneFocus.hasFocus)
                Align(alignment: Alignment.centerRight,
                    child: Padding(padding: const EdgeInsets.only(top: 3, right: 4),
                        child: Text("${_motherPhoneCount}/10",
                            style: TextStyle(
                                color: _motherPhoneCount == 10 ? c.success : c.textTertiary,
                                fontSize: 11, fontWeight: FontWeight.w600)))),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _husbandPhoneCtrl,
                focusNode: _husbandPhoneFocus,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: _requiredDecoration("Husband")
                    .copyWith(counterText: ""),
                validator: (v) => _submitted ? _phoneValidator(v) : null,
                style: TextStyle(color: c.textPrimary),
                onChanged: (value) => setState(() {
                  _husbandPhoneCount       = value.length;
                  _husbandPhoneLimitReached = value.length == 10;
                }),
              ),
              if (_husbandPhoneFocus.hasFocus)
                Align(alignment: Alignment.centerRight,
                    child: Padding(padding: const EdgeInsets.only(top: 3, right: 4),
                        child: Text("${_husbandPhoneCount}/10",
                            style: TextStyle(
                                color: _husbandPhoneCount == 10 ? c.success : c.textTertiary,
                                fontSize: 11, fontWeight: FontWeight.w600)))),
            ]),
          ),
        ]),
        const SizedBox(height: 12),

      ],
    );
  }

  // ── EXCLUSION SECTION ─────────────────────────────────────────────────────

  Widget _buildExclusionSection(AppColors c) {
    return _sectionCard(
      title: "A4 · Exclusion Criteria",
      icon: Icons.block_rounded,
      accentColor: c.danger,
      children: [
        _exclusionYesNo("ANOMALY",
            "18. Major structural anomalies or genetic abnormality (suspected/proven)"),
        _exclusionYesNo("HYDROPS", "19. Fetal Hydrops"),
        _exclusionYesNo("RESUSCITATION", "21. Decision to forego resuscitation"),
        _exclusionYesNo("INSUFFICIENT", "23. Insufficient time for consent"),
        _exclusionYesNo("IUFD", "25. IUFD"),

        if (_allExclusionsAnswered) ...[
          const SizedBox(height: 4),
          _infoBanner(
            icon: _exclusionPresent
                ? Icons.cancel_rounded
                : Icons.check_circle_rounded,
            text: _exclusionPresent
                ? "Exclusion criteria present — participant is not fit for consent. End participation."
                : "All options No — Proceed for consent",
            color:    _exclusionPresent ? c.danger   : c.success,
            softColor: _exclusionPresent ? c.dangerSoft : c.successSoft,
            c: c,
          ),
        ],
      ],
    );
  }

  // ── CONSENT SECTION ───────────────────────────────────────────────────────

  Widget _buildConsentSection(AppColors c) {
    return _sectionCard(
      title: "A5 · Proceed for Consent",
      icon: Icons.verified_rounded,
      accentColor: c.success,
      children: [
        DropdownButtonFormField<String>(
          value: _consentStatus,
          decoration: _requiredDecoration("26. Consent"),
          dropdownColor: c.surface,
          items: [
            _ddItem("Select", c, hint: true),
            _ddItem("Yes", c), _ddItem("No", c),
            _ddItem("Trial run", c),
            _ddItem("Not approached", c),
          ],
          onChanged: (v) {
            setState(() {
              _consentStatus = v!;
              if (v == "Yes" || v == "Trial run") {
                _consentDateTimeIso ??= DateTime.now().toIso8601String();
              } else {
                _consentDateTimeIso = null;
              }
              if (_consentStatus != "Yes" && _consentStatus != "No" && _consentStatus != "Trial run") {
                _relationshipToParticipant = "Select";
                _relationshipOtherText     = "";
                _consentTakenBy            = "Select";
              }
              _consentRefusalReasons.clear();
              _consentRefusalOtherText = "";
              _notApproachedReasons.clear();
              _notApproachedOtherText  = "";
            });
          },
          validator: (v) => _submitted && (v == null || v == "Select") ? "Required" : null,
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 14),

        // 28 + 31: Consent obtained from | Consent obtained by (nurse)
        // shown for Yes / No / Trial run — matches webform which shows this
        // block whenever consent_given is Yes, No, or Trial run.
        if (_consentStatus == "Yes" || _consentStatus == "No" || _consentStatus == "Trial run") ...[
          DropdownButtonFormField<String>(
            value: _relationshipToParticipant,
            decoration: _requiredDecoration("27. Consent obtained from"),
            dropdownColor: c.surface,
            items: [
              _ddItem("Select", c, hint: true),
              _ddItem("Mother", c),
              _ddItem("Husband", c),
              _ddItem("Other", c),
            ],
            onChanged: (v) => setState(() {
              _relationshipToParticipant = v!;
              if (v != "Other") _relationshipOtherText = "";
            }),
            validator: (v) =>
                _submitted && (v == null || v == "Select") ? "Required" : null,
            style: TextStyle(color: c.textPrimary),
          ),
          if (_relationshipToParticipant == "Other") ...[
            const SizedBox(height: 10),
            TextFormField(
              decoration: _requiredDecoration("Specify"),
              onChanged: (v) => _relationshipOtherText = v,
              style: TextStyle(color: c.textPrimary),
              validator: (v) {
                if (_submitted && (v == null || v.trim().isEmpty)) return "Required";
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
        ],

        // 28. Reason for refusal (if No)
        if (_consentStatus == "No") ...[
          _reqText("28. If no, reason for consent refusal (select all that apply)", c),
          const SizedBox(height: 8),
          ...[
            "Fear of adverse effects", "Family pressure", "Not known", "Other"
          ].map((reason) => _styledCheckbox(reason, c)),
          if (_consentRefusalReasons.contains("Other")) ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: _inputDecoration("Please specify…"),
              style: TextStyle(color: c.textPrimary),
              onChanged: (v) => _consentRefusalOtherText = v,
              validator: (v) {
                if (_consentStatus == "No" &&
                    _consentRefusalReasons.contains("Other") &&
                    (v == null || v.trim().isEmpty)) return "Required";
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
        ],

        // 30. Reason not approached (if Not approached) — multi-select, matches webform
        if (_consentStatus == "Not approached") ...[
          _reqText("29. If not approached, reason (select all that apply)", c),
          const SizedBox(height: 8),
          ...[
            "Nurse on leave", "Parent not available", "Missed screening", "Other"
          ].map((reason) => GestureDetector(
                onTap: () => setState(() {
                  _notApproachedReasons.contains(reason)
                      ? _notApproachedReasons.remove(reason)
                      : _notApproachedReasons.add(reason);
                }),
                child: _checkboxRow(reason, _notApproachedReasons.contains(reason), c),
              )),
          if (_notApproachedReasons.contains("Other")) ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: _inputDecoration("Please specify…"),
              style: TextStyle(color: c.textPrimary),
              onChanged: (v) => _notApproachedOtherText = v,
              validator: (v) {
                if (_consentStatus == "Not approached" &&
                    _notApproachedReasons.contains("Other") &&
                    (v == null || v.trim().isEmpty)) return "Required";
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
        ],

        // 30. Consent obtained by — Yes / No / Trial run (web order after 28/29)
        if (_consentStatus == "Yes" || _consentStatus == "No" || _consentStatus == "Trial run") ...[
          DropdownButtonFormField<String>(
            value: _consentTakenBy,
            decoration: _requiredDecoration("30. Consent obtained by (First name)"),
            dropdownColor: c.surface,
            items: [
              _ddItem("Select", c, hint: true),
              ...(_consentNurseOptions()).map((n) => _ddItem(n, c)),
            ],
            onChanged: (v) => setState(() => _consentTakenBy = v!),
            validator: (v) =>
                _submitted && (v == null || v == "Select") ? "Required" : null,
            style: TextStyle(color: c.textPrimary),
          ),
          const SizedBox(height: 14),
        ],

        // 31. Video PIS shown — whenever any consent value is selected
        if (_consentStatus != "Select") ...[
          DropdownButtonFormField<String>(
            value: _videoPisShown,
            decoration: _requiredDecoration("31. Video PIS shown"),
            dropdownColor: c.surface,
            items: [
              _ddItem("Select", c, hint: true),
              _ddItem("Yes", c), _ddItem("No", c),
            ],
            onChanged: (v) => setState(() => _videoPisShown = v!),
            validator: (v) =>
                _submitted && (v == null || v == "Select") ? "Required" : null,
            style: TextStyle(color: c.textPrimary),
          ),
        ],
      ],
    );
  }

  Widget _checkboxRow(String label, bool checked, AppColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: checked ? c.primarySoft : c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: checked ? c.primary : c.border),
      ),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: checked ? c.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: checked ? c.primary : c.border, width: 1.5),
          ),
          child: checked
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
              : null,
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
            color: checked ? c.primary : c.textSecondary,
            fontSize: 13, fontWeight: checked ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }

  Widget _styledCheckbox(String label, AppColors c) {
    final checked = _consentRefusalReasons.contains(label);
    return GestureDetector(
      onTap: () => setState(() {
        checked
            ? _consentRefusalReasons.remove(label)
            : _consentRefusalReasons.add(label);
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked ? c.primarySoft : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: checked ? c.primary : c.border),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: checked ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: checked ? c.primary : c.border, width: 1.5),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                : null,
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
              color: checked ? c.primary : c.textSecondary,
              fontSize: 13, fontWeight: checked ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  // ── VALIDATORS ────────────────────────────────────────────────────────────

  List<String> _consentNurseOptions() => _siteScreeners;

  String? _maternalUidValidator(String? v) {
    final val = (v ?? "").trim();
    if (_selectedSite == "PGIMER") {
      if (val.isEmpty) return "Required";
      if (!RegExp(r'^\d{12}$').hasMatch(val)) return "Must be exactly 12 digits";
      return null;
    }
    if (_selectedSite == "AMC") {
      if (val.isEmpty) return "Required";
      if (!RegExp(r'^\d+/\d{4}$').hasMatch(val)) {
        return "Must be in serial/year format, e.g. 123/2026";
      }
      return null;
    }
    if (val.isEmpty) return "Required";
    return null;
  }

  String? _hospitalNoValidator(String? v) {
    final val = (v ?? "").trim();
    if (_selectedSite == "PGIMER") {
      if (val.isEmpty) return "Required";
      if (!RegExp(r'^\d{10}$').hasMatch(val)) return "Must be exactly 10 digits";
      return null;
    }
    if (_selectedSite == "GMCH-A" && val.isNotEmpty &&
        !RegExp(r'^\d{4,6}$').hasMatch(val)) {
      return "Must be 4–6 digits";
    }
    if (_selectedSite == "GMCH" && val.isNotEmpty &&
        !RegExp(r'^\d{9,11}$').hasMatch(val)) {
      return "Must be 9–11 digits";
    }
    if (_selectedSite == "IOG" && val.isNotEmpty &&
        !RegExp(r'^\d{4,6}$').hasMatch(val)) {
      return "Must be 4–6 digits";
    }
    if (_selectedSite == "AMC" && val.isNotEmpty &&
        !RegExp(r'^\d+/\d{4}$').hasMatch(val)) {
      return "Must be in serial/year format, e.g. 123/2026";
    }
    return null;
  }

  /// Live hint while typing (web shows field-error as soon as value fails pattern).
  String? _hospitalNoLiveMessage(String? v) {
    final val = (v ?? "").trim();
    if (val.isEmpty) {
      return _selectedSite == "PGIMER" ? "Required" : null;
    }
    return _hospitalNoValidator(val);
  }

  String _hospitalNoHint() {
    switch (_selectedSite) {
      case "GMCH-A":
        return "4–6 digit MRD number";
      case "AMC":
        return "e.g. 123/2026";
      case "GMCH":
        return "9–11 digit number";
      case "IOG":
        return "4–6 digit MRD number";
      case "PGIMER":
        return "10-digit admission number";
      default:
        return "Admission / MRD number";
    }
  }

  String? _charOnlyValidator(String? v) {
    if (v == null || v.trim().isEmpty) return "Required";
    if (!RegExp(r"^[\p{L} .'\-]+$", unicode: true).hasMatch(v.trim())) {
      return "Letters only";
    }
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) return "Required";
    // Match web save: exactly 10 digits and must start with 6–9.
    if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) {
      return "Must be exactly 10 digits";
    }
    if (!RegExp(r'^[6-9]').hasMatch(v.trim())) {
      return "Indian mobile must start with 6, 7, 8, or 9";
    }
    return null;
  }
}
