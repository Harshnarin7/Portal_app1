// lib/screens/screening_form.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/crf.dart';
import '../services/api_service.dart';
import '../widgets/success_banner.dart';
import '../services/pdf_service.dart';
import 'form_b_birth_resuscitation.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/screening_api_service.dart';
import '../services/forms_api_service.dart';
import 'dashboard_screen.dart';

// ── Theme ──────────────────────────────────────────────────────────────────
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../widgets/theme_toggle_widget.dart';

String screeningCounterKey(String site) => "screening_counter_$site";
const String draftIndexKey = "screening_draft_keys";
String _userRole = "admin";

class ScreeningForm extends StatefulWidget {
  final bool loadDraft;
  final String? draftKey;

  const ScreeningForm({
    super.key,
    this.loadDraft = false,
    this.draftKey,
  });

  @override
  State<ScreeningForm> createState() => _ScreeningFormState();
}

class _ScreeningFormState extends State<ScreeningForm>
    with SingleTickerProviderStateMixin {

  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  Set<String> _previousYesExclusions = {};

  bool _submitted = false;
  bool _proceedToConsent = false;
  bool _consentPopupShown = false;

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

  // ── Auto-save timer ──
  Timer? _autoSaveTimer;

  bool _idAssigned = false;
  bool _exclusionPresent = false;

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
    return _motherFirstCtrl.text.trim().isEmpty &&
        _motherSurnameCtrl.text.trim().isEmpty &&
        _husbandFirstCtrl.text.trim().isEmpty &&
        _husbandSurnameCtrl.text.trim().isEmpty &&
        _motherPhoneCtrl.text.trim().isEmpty &&
        _husbandPhoneCtrl.text.trim().isEmpty &&
        _maternalUidCtrl.text.trim().isEmpty &&
        _hospitalNoCtrl.text.trim().isEmpty;
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
  final TextEditingController _gestWeeksCtrl     = TextEditingController(text: "24");
  final TextEditingController _gestDaysCtrl      = TextEditingController(text: "0");
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
  String _resuscitationReason = "";
  String _resuscitationOther  = "";
  String _anomalyDetails      = "";
  String _hydropsType         = "";

  String _consentStatus              = "Select";
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

  final Map<String, List<String>> _nursesBySite = {
    "PGIMER": [
      "Mannat Guliani", "Shalini Dhiman", "Navkiran Kaur",
      "Geetika", "Priyanka Thakur", "Seemran Kaur",
      "Tanvi Saini", "Yashvi Jolly",
    ],
  };

  String _selectedSite = "PGIMER";

  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  // ── VALIDATORS ─────────────────────────────────────────────────────────────

  String? _screeningDateValidator(String? value) {
    if (value == null || value.trim().isEmpty) return "Required";
    try {
      final parts    = value.split(" ");
      final datePart = parts[0];
      final d        = datePart.split("/");
      final selectedDate = DateTime(int.parse(d[2]), int.parse(d[1]), int.parse(d[0]));
      final diff = DateTime.now().difference(selectedDate).inDays;
      if (diff > 7) return "Screening date cannot be older than 7 days";
      if (diff < 0) return "Screening date cannot be in the future";
      return null;
    } catch (_) {
      return "Invalid date format";
    }
  }

  // ── LIFECYCLE ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _maternalUidFocus.addListener(() {
      if (!_maternalUidFocus.hasFocus) {
        setState(() => _maternalUidLimitReached = false);
      }
    });

    _loadUserContext();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    if (widget.loadDraft && widget.draftKey != null) {
      _currentDraftKey = widget.draftKey;
      _loadDraftIfExists();
    }

    _maternalUidCtrl.addListener(() {
      setState(() => _maternalUidLimitReached = _maternalUidCtrl.text.length >= 15);
    });

    // ── Auto-save every 60 seconds ──
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_isFormCompletelyEmpty()) _saveDraft(silent: true);
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
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
    _gestWeeksCtrl.dispose();
    _gestDaysCtrl.dispose();
    _expectedDeliveryCtrl.dispose();
    _lmpCtrl.dispose();
    _screeningDateTimeCtrl.dispose();
    _screenedByCtrl.dispose();
    _scanController.dispose();
    _husbandPhoneFocus.dispose();
    _motherPhoneFocus.dispose();
    _maternalUidFocus.dispose();
    super.dispose();
  }

  // ── USER CONTEXT ───────────────────────────────────────────────────────────

  Future<void> _loadUserContext() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString("user_role") ?? "admin";
    if (_userRole == "site") {
      final site = prefs.getString("site_name");
      if (site != null) {
        setState(() {
          _selectedSite = site;
          _screeningIdCtrl.clear();
          _idAssigned = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil("/login", (route) => false);
  }

  // ── GESTATION HELPERS ──────────────────────────────────────────────────────

  void _recalculateGestationFromEDD(DateTime edd) {
    final today   = DateTime.now();
    final diffDays = edd.difference(today).inDays;
    int gestDays  = 280 - diffDays;
    if (gestDays < 0) gestDays = 0;
    setState(() {
      _gestWeeksCtrl.text = (gestDays ~/ 7).toString();
      _gestDaysCtrl.text  = (gestDays % 7).toString();
    });
    if (_isGestationOutOfRange()) _showGestationOutOfRangePopup();
  }

  // Eligibility range matches webform ScreeningForm.jsx getEligibilityStatus():
  // eligible = 24w0d .. 31w6d inclusive (t < 24*7 => low, t > 31*7+6 => high)
  bool _isGestationOutOfRange() {
    final weeks = int.tryParse(_gestWeeksCtrl.text) ?? 0;
    final days  = int.tryParse(_gestDaysCtrl.text)  ?? 0;
    if (weeks < 24) return true;
    if (weeks > 31) return true;
    if (weeks == 31 && days > 6) return true;
    return false;
  }

  bool get _isEligibleGestation {
    final weeks = int.tryParse(_gestWeeksCtrl.text) ?? 0;
    final days  = int.tryParse(_gestDaysCtrl.text)  ?? 0;
    if (weeks < 24) return false;
    if (weeks > 31) return false;
    if (weeks == 31 && days > 6) return false;
    return true;
  }

  void _resetGestationSection() {
    setState(() {
      _gestationKnownInWeeks = null;
      _eddKnown              = null;
      _gaSource              = null;
      _gestWeeksCtrl.text    = "24";
      _gestDaysCtrl.text     = "0";
      _expectedDeliveryCtrl.clear();
      _lmpCtrl.clear();
      _gaAssessmentMethod = "Select";
    });
  }

  void _resetExclusionSection() {
    setState(() {
      _exclusionAnswers.updateAll((key, value) => null);
      _exclusionPresent = false;
      _previousYesExclusions.clear();
      _proceedToConsent   = false;
      _consentPopupShown  = false;
      _insufficientReason  = "";
      _resuscitationReason = "";
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

    setState(() => _exclusionPresent = currentYesKeys.isNotEmpty);

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

    if (_allExclusionsNo && !_consentPopupShown) {
      _consentPopupShown = true;
      final c = AppTheme.of(context);
      Future.microtask(() {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(Icons.check_circle_rounded, color: c.success, size: 20),
              const SizedBox(width: 8),
              Text("Proceed for Consent?",
                  style: TextStyle(color: c.success, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
            content: Text(
              "None of the exclusions are fulfilled.\n\nFit to proceed for the consent.\n\nDo you want to proceed?",
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            actions: [
              // ── FIX: "Later" saves draft then pops back to dashboard ──
              TextButton(
                onPressed: () async {
                  setState(() => _proceedToConsent = true);
                  Navigator.pop(context); // close dialog first
                  await _saveDraft();
                  if (!mounted) return;
                  Navigator.of(context).pop(true); // go back to dashboard
                },
                child: Text("Later", style: TextStyle(color: c.warning, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: c.success, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _proceedToConsent = true);
                },
                child: const Text("Now"),
              ),
            ],
          ),
        );
      });
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
          if (_resuscitationReason.isEmpty) return false;
          if (_resuscitationReason == "Other" && _resuscitationOther.trim().isEmpty) return false;
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
    final siteCode = _siteMap[_selectedSite] ?? "00";

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
      // It is replaced by the server's real ID as soon as a sync succeeds.
    }

    final prefs = await SharedPreferences.getInstance();
    final key   = screeningCounterKey(_selectedSite);
    final last  = prefs.getInt(key) ?? 0;
    final next  = last + 1;
    _assignedScreeningId = "$siteCode-LOCAL-${next.toString().padLeft(4, '0')}";
    _screeningIdCtrl.text = _assignedScreeningId!;
    await prefs.setInt(key, next);
    _idAssigned = true;
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
      'site_name'   : _selectedSite.isNotEmpty ? _selectedSite : (useDraftFallbacks ? "DRAFT" : null),
      'site_id'     : _siteMap[_selectedSite] ?? (useDraftFallbacks ? "00" : null),
      'screened_by' : _screenedByCtrl.text.trim().isNotEmpty && _screenedByCtrl.text != "Select"
          ? _screenedByCtrl.text.trim() : (useDraftFallbacks ? "DRAFT" : null),
      'mother_first_name' : _motherFirstCtrl.text.trim().isNotEmpty
          ? _motherFirstCtrl.text.trim() : (useDraftFallbacks ? "DRAFT" : null),
      'mother_surname'    : _motherSurnameCtrl.text.trim().isNotEmpty ? _motherSurnameCtrl.text.trim() : null,
      'husband_first_name': _husbandFirstCtrl.text.trim().isNotEmpty
          ? _husbandFirstCtrl.text.trim() : (useDraftFallbacks ? "DRAFT" : null),
      'husband_surname'   : _husbandSurnameCtrl.text.trim().isNotEmpty ? _husbandSurnameCtrl.text.trim() : null,
      'mother_contact'    : _motherPhoneCtrl.text.trim().isNotEmpty ? _motherPhoneCtrl.text.trim() : null,
      'husband_contact'   : _husbandPhoneCtrl.text.trim().isNotEmpty ? _husbandPhoneCtrl.text.trim() : null,
      'maternal_uid'      : _maternalUidCtrl.text.trim().isNotEmpty ? _maternalUidCtrl.text.trim() : null,
      'hospital_admission_number': _hospitalNoCtrl.text.trim().isNotEmpty ? _hospitalNoCtrl.text.trim() : null,
      'gestation_weeks': weeks ?? (useDraftFallbacks ? 0 : null),
      'gestation_days' : days  ?? 0,
      'gestation_method': gaMethod,
      'expected_delivery_date': _ddmmyyyyToIsoDate(_expectedDeliveryCtrl.text),
      'lmp_date'              : _ddmmyyyyToIsoDate(_lmpCtrl.text),
      'exclusion_present': _exclusionPresent,
      'exclusion_reasons': exclusionLabels.isNotEmpty ? exclusionLabels.join(", ") : null,
      'reason_for_insufficient_time': _exclusionAnswers["INSUFFICIENT"] == "Yes" && _insufficientReason.trim().isNotEmpty
          ? _insufficientReason.trim() : null,
      'decision_forego_resuscitation_reason': _exclusionAnswers["RESUSCITATION"] == "Yes" && _resuscitationReason.isNotEmpty
          ? _resuscitationReason : null,
      'decision_forego_resuscitation_reason_other': _resuscitationReason == "Other" && _resuscitationOther.trim().isNotEmpty
          ? _resuscitationOther.trim() : null,
      'major_structural_anomalies_if_yes': _exclusionAnswers["ANOMALY"] == "Yes" && _anomalyDetails.trim().isNotEmpty
          ? _anomalyDetails.trim() : null,
      'fetal_hydrops': _exclusionAnswers["HYDROPS"] == "Yes" && _hydropsType.isNotEmpty ? _hydropsType : null,
      'consent_given'   : _consentStatus != "Select" ? _consentStatus : null,
      'consent_taken_by': _consentTakenBy != "Select" ? _consentTakenBy : null,
      'relationship_to_participant': _relationshipToParticipant != "Select" ? _relationshipToParticipant : null,
      'relationship_other'         : _relationshipOtherText.trim().isNotEmpty ? _relationshipOtherText.trim() : null,
      'reason_for_consent_refusal' : _consentRefusalReasons.isNotEmpty ? _consentRefusalReasons.join(", ") : null,
      'reason_for_consent_refusal_other': _consentRefusalOtherText.trim().isNotEmpty ? _consentRefusalOtherText.trim() : null,
      'reason_not_approached'      : _notApproachedReasons.isNotEmpty ? _notApproachedReasons.join(", ") : null,
      'reason_not_approached_other': _notApproachedOtherText.trim().isNotEmpty ? _notApproachedOtherText.trim() : null,
      'video_pis_shown': _videoPisShown != "Select" ? _videoPisShown : null,
    };
  }

  /// POSTs (create) or PUTs (update) the current form state to the real
  /// `/screenings/` backend endpoint — the same one ScreeningForm.jsx uses.
  Future<Map<String, dynamic>?> _syncToBackend({bool isDraft = false}) async {
    final payload = _buildSyncPayload(useDraftFallbacks: isDraft);
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

  Future<void> _saveDraft({bool silent = false}) async {
    if (_isFormCompletelyEmpty()) return;
    await _assignScreeningIdIfNeeded();

    // Best-effort background sync to the real backend so progress is visible
    // on the web portal too. Failures (e.g. offline) are silent here — the
    // local SharedPreferences draft below still keeps the data safe.
    try {
      await _syncToBackend(isDraft: true);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    _currentDraftKey ??= "draft_${DateTime.now().millisecondsSinceEpoch}";

    final draft = {
      "screeningId"         : _assignedScreeningId,
      "site"                : _selectedSite,
      "savedAt"             : DateTime.now().toIso8601String(),
      "screeningDateTime"   : _screeningDateTimeCtrl.text,
      "screenedBy"          : _screenedByCtrl.text,
      "motherFirst"         : _motherFirstCtrl.text,
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
      "resuscitationReason" : _resuscitationReason,
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
      _selectedSite              = data["site"] ?? _selectedSite;
      _idAssigned                = true;
      _screeningDateTimeCtrl.text= data["screeningDateTime"] ?? "";
      _screenedByCtrl.text       = data["screenedBy"] ?? "";
      _motherFirstCtrl.text      = data["motherFirst"] ?? "";
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
      _gestWeeksCtrl.text        = data["gestWeeks"] ?? "24";
      _gestDaysCtrl.text         = data["gestDays"] ?? "0";
      _gaAssessmentMethod        = data["gaMethod"] ?? "Select";
      _expectedDeliveryCtrl.text = data["expectedDelivery"] ?? "";
      _exclusionAnswers.addAll(
          Map<String, String?>.from(data["exclusionAnswers"] ?? {}));
      _insufficientReason        = data["insufficientReason"] ?? "";
      _resuscitationReason       = data["resuscitationReason"] ?? "";
      _resuscitationOther        = data["resuscitationOther"] ?? "";
      _anomalyDetails            = data["anomalyDetails"] ?? "";
      _hydropsType               = data["hydropsType"] ?? "";
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
      _proceedToConsent          = data["proceedToConsent"] ?? false;
      _currentDraftKey           = widget.draftKey;
    });
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

    final weeks       = int.tryParse(_gestWeeksCtrl.text.trim()) ?? 0;
    final days        = int.tryParse(_gestDaysCtrl.text.trim())  ?? 0;
    final eligibility = _exclusionPresent ? "Not Eligible" : "Eligible";

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
      gestationWeeks      : weeks,
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
    );

    try {
      await _api.saveCRF(crf);
      // Save to the real PORTAL backend — POST to create / PUT to update the
      // same `/screenings/` record the web portal reads and writes.
      await _syncToBackend(isDraft: false);

      // ── Generate PDF in the background ──
      // Don't block returning to the dashboard on this: it's CPU-bound and
      // the dashboard already regenerates the PDF on demand (_generatePdf)
      // when the record is opened, so waiting here just adds dead time to
      // every single save.
      // ignore: unawaited_futures
      PdfService.generateCrfPdf(crf);

      // ── Clean up draft BEFORE popping ──
      final prefs = await SharedPreferences.getInstance();
      if (_currentDraftKey != null) {
        await prefs.remove(_currentDraftKey!);
        await _removeDraftKey(_currentDraftKey!);
        _currentDraftKey = null;
      }

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

    if (totalDays < (24 * 7) ||
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
          "Gestational age cannot be determined.\n\nPlease do not proceed with screening.",
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: c.danger, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
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
          "Gestational age is outside the eligible range (24+0 to 31+6 weeks).\n\nScreening has been ended.",
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: c.danger, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context, true); // go back to dashboard
            },
            child: const Text("OK"),
          ),
        ],
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

  Future<void> saveFormAToFirebase(Map<String, dynamic> data) async {
    final id = data['screeningId'];
    // Firebase removed — data saved to PORTAL backend
  }

  Future<void> _onSiteChangedWithConfirm(String? newSite) async {
    if (newSite == null || newSite == _selectedSite) return;
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
      setState(() { _selectedSite = newSite; _screenedByCtrl.clear(); });
    } else {
      setState(() {});
    }
  }

  // ── DECORATIONS ───────────────────────────────────────────────────────────

  InputDecoration _inputDecoration(String label, {String? hint, String? helper}) {
    final c = AppTheme.of(context);
    return InputDecoration(
      labelText  : label,
      hintText   : hint,
      helperText : helper,
      helperStyle: TextStyle(color: c.textTertiary, fontSize: 12),
      labelStyle : TextStyle(color: c.textSecondary, fontSize: 13),
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
      _inputDecoration("$label *", hint: hint, helper: helper);

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
                final value = int.tryParse(controller.text) ?? min;
                if (value > min) {
                  setState(() => controller.text = "${value - 1}");
                  if (_isGestationOutOfRange()) _showGestationOutOfRangePopup();
                }
              },
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                readOnly: !enabled,
                validator: validator,
                style: TextStyle(color: c.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 16),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: c.success, size: 20),
              onPressed: () {
                final value = int.tryParse(controller.text) ?? min;
                if (value < max) {
                  setState(() => controller.text = "${value + 1}");
                  if (_isGestationOutOfRange()) _showGestationOutOfRangePopup();
                }
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
      onTap: () => setState(() {
        _exclusionAnswers[key] = value;
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
            decoration: _requiredDecoration("25. If yes, specify reason"),
            style: TextStyle(color: c.textPrimary),
            onChanged: (v) => _insufficientReason = v,
          ),
          if (_submitted && _insufficientReason.trim().isEmpty)
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Required", style: TextStyle(color: c.danger, fontSize: 12))),
        ]);

      case "RESUSCITATION":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("23. If yes, reason (select all that apply) *", style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          ...["Periviable", "Socio-economic", "Major CMF", "Other"].map((v) =>
              _styledRadio(v, _resuscitationReason, c, (val) =>
                  setState(() => _resuscitationReason = val!))),
          if (_submitted && _resuscitationReason.isEmpty)
            Text("Please select a reason", style: TextStyle(color: c.danger, fontSize: 12)),
          if (_resuscitationReason == "Other") ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: _requiredDecoration("Please specify…"),
              style: TextStyle(color: c.textPrimary),
              onChanged: (v) => _resuscitationOther = v,
            ),
            if (_submitted && _resuscitationOther.trim().isEmpty)
              Text("Required", style: TextStyle(color: c.danger, fontSize: 12)),
          ],
        ]);

      case "ANOMALY":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            decoration: _requiredDecoration("19a. If yes, specify structural anomaly"),
            style: TextStyle(color: c.textPrimary),
            onChanged: (v) => _anomalyDetails = v,
          ),
          if (_submitted && _anomalyDetails.trim().isEmpty)
            Padding(padding: const EdgeInsets.only(top: 4),
                child: Text("Required", style: TextStyle(color: c.danger, fontSize: 12))),
        ]);

      case "HYDROPS":
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("21. If yes, select fetal hydrops type *", style: TextStyle(color: c.textSecondary, fontSize: 13)),
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
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]')),
    ];

    return WillPopScope(
      onWillPop: () async {
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
        bottomNavigationBar: _buildBottomBar(c),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [c.bgGradTop, c.bg], stops: const [0.0, 0.35],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _buildStepIndicator(c),

                    _buildGestationSection(c),

                    if (_isEligibleGestation) _buildIdentificationSection(c, nameFormatter),

                    if (_isEligibleGestation) _buildExclusionSection(c),

                    if (_isEligibleGestation && _allExclusionsNo && _proceedToConsent)
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

                    const SizedBox(height: 40),
                  ],
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
        Text("Pregnant women < 32 weeks at admission",
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
              label: Text("Draft", style: TextStyle(color: c.warning, fontWeight: FontWeight.w700)),
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
            label: const Text("Save & Close",
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
    );
  }

  // ── GESTATION SECTION ─────────────────────────────────────────────────────

  Widget _buildGestationSection(AppColors c) {
    return _sectionCard(
      title: "A1 · GESTATION ASSESSMENT",
      icon: Icons.pregnant_woman_rounded,
      accentColor: c.primary,
      trailing: TextButton.icon(
        onPressed: _resetGestationSection,
        icon: Icon(Icons.refresh_rounded, size: 16, color: c.textSecondary),
        label: Text("Reset", style: TextStyle(color: c.textSecondary, fontSize: 12)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      ),
      children: [
        Text("1. Gestation in weeks clearly mentioned?",
            style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gestRadio("Yes", true, c)),
          const SizedBox(width: 8),
          Expanded(child: _gestRadio("No",  false, c)),
        ]),

        if (_gestationKnownInWeeks == true) ...[
          const SizedBox(height: 18),
          Text("2. Best estimate GA (weeks / days) · 3. Method of assessment",
              style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(children: [
              Text("2a. Weeks", style: TextStyle(color: c.textTertiary, fontSize: 12)),
              const SizedBox(height: 6),
              _numberStepper(controller: _gestWeeksCtrl, min: 24, max: 31),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(children: [
              Text("2b. Days", style: TextStyle(color: c.textTertiary, fontSize: 12)),
              const SizedBox(height: 6),
              _numberStepper(controller: _gestDaysCtrl, min: 0, max: 6),
            ])),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _expectedDeliveryCtrl,
            readOnly: true,
            decoration: _inputDecoration("4. Expected Delivery Date (Optional)").copyWith(
              suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18),
            ),
            style: TextStyle(color: c.textPrimary),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2035),
              );
              if (picked != null) {
                _expectedDeliveryCtrl.text =
                    "${picked.day}/${picked.month}/${picked.year}";
              }
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _gaAssessmentMethod,
            dropdownColor: c.surface,
            decoration: _requiredDecoration("3. Method of gestation assessment"),
            items: [
              _ddItem("Select", c, hint: true),
              _ddItem("LMP", c), _ddItem("Early USG (<24w)", c),
              _ddItem("Fundal Height", c), _ddItem("Method not known", c),
            ],
            onChanged: (v) => setState(() {
              _gaAssessmentMethod = v!;
              // Matches web: switching away from LMP clears the LMP-specific
              // fields so a stale date doesn't linger under a different method.
              if (v != "LMP") {
                _lmpCtrl.clear();
              }
            }),
            style: TextStyle(color: c.textPrimary),
          ),

          // "3a. LMP Date" — matches web ScreeningForm.jsx exactly: shown
          // whenever Method of gestation assessment = LMP. Required, since
          // web enforces this as a required field when this method is chosen.
          if (_gaAssessmentMethod == "LMP") ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _lmpCtrl, readOnly: true,
              decoration: _requiredDecoration("3a. LMP Date").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _lmpCtrl.text = "${picked.day}/${picked.month}/${picked.year}";
                  // Auto-calc EDD from LMP, same formula used by the other
                  // LMP field below and by web's parseDateOnly/+280 days logic.
                  final edd = picked.add(const Duration(days: 280));
                  _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
                  setState(() {});
                }
              },
            ),
          ],
        ],

        if (_gestationKnownInWeeks == false) ...[
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            value: _gaSource,
            dropdownColor: c.surface,
            decoration: _requiredDecoration("5. If No, is any of the following known?"),
            items: [
              _ddItem("LMP", c), _ddItem("EDD", c), _ddItem("Neither", c),
            ],
            onChanged: (v) {
              setState(() {
                _gaSource = v;
                _eddKnown = (v == "LMP" || v == "EDD") ? true : false;
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
              decoration: _requiredDecoration("6. LMP Date").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _lmpCtrl.text = "${picked.day}/${picked.month}/${picked.year}";
                  final edd = picked.add(const Duration(days: 280));
                  _expectedDeliveryCtrl.text = "${edd.day}/${edd.month}/${edd.year}";
                  final totalDays = DateTime.now().difference(picked).inDays;
                  _gestWeeksCtrl.text = (totalDays ~/ 7).toString();
                  _gestDaysCtrl.text  = (totalDays % 7).toString();
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _expectedDeliveryCtrl, readOnly: true,
              decoration: _requiredDecoration("Expected Delivery Date (auto-calculated)"),
              style: TextStyle(color: c.textPrimary),
            ),
          ],

          if (_gaSource == "EDD") ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _expectedDeliveryCtrl, readOnly: true,
              decoration: _requiredDecoration("7. Expected Delivery Date").copyWith(
                suffixIcon: Icon(Icons.calendar_today, color: c.textTertiary, size: 18)),
              style: TextStyle(color: c.textPrimary),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(), lastDate: DateTime(2035),
                );
                if (picked != null) {
                  _expectedDeliveryCtrl.text =
                      "${picked.day}/${picked.month}/${picked.year}";
                  final remaining = picked.difference(DateTime.now()).inDays;
                  final totalGest = 280 - remaining;
                  _gestWeeksCtrl.text = (totalGest ~/ 7).toString();
                  _gestDaysCtrl.text  = (totalGest % 7).toString();
                  setState(() {});
                }
              },
            ),
          ],

          if (_gaSource == "LMP" || _gaSource == "EDD") ...[
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
          _gestWeeksCtrl.text = value ? "24" : "";
          _gestDaysCtrl.text  = value ? "0"  : "";
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
    final inRange = weeks >= 24 && (weeks < 31 || (weeks == 31 && days <= 6));
    final color   = inRange ? c.success : c.danger;
    final soft    = inRange ? c.successSoft : c.dangerSoft;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("8. Calculated Gestational Age",
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        Text("${_gestWeeksCtrl.text} weeks  ${_gestDaysCtrl.text} days",
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        if (!inRange) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: c.danger, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(
              weeks < 25
                  ? "Below 24 weeks — cannot proceed."
                  : "Above 31+6 weeks — cannot proceed.",
              style: TextStyle(color: c.danger, fontSize: 12, fontWeight: FontWeight.w600),
            )),
          ]),
        ],
      ]),
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
      title: "A2 · IDENTIFICATION",
      icon: Icons.badge_rounded,
      accentColor: c.primary,
      children: [
        TextFormField(
          controller: _screeningIdCtrl, readOnly: true,
          decoration: _inputDecoration("9. Screening ID"),
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedSite,
              dropdownColor: c.surface,
              decoration: _inputDecoration("10. Site"),
              items: _siteMap.keys.map((s) =>
                  DropdownMenuItem(value: s,
                      child: Text(s, style: TextStyle(color: c.textPrimary)))).toList(),
              onChanged: _userRole == "admin"
                  ? (v) async => _onSiteChangedWithConfirm(v)
                  : null,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              readOnly: true,
              controller: TextEditingController(text: _siteMap[_selectedSite]),
              decoration: _inputDecoration("11. Site ID"),
              style: TextStyle(color: c.textPrimary),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        TextFormField(
          controller: _screeningDateTimeCtrl, readOnly: true,
          decoration: _requiredDecoration("12. Screening Date & Time", hint: "Tap to choose").copyWith(
            suffixIcon: Icon(Icons.access_time_rounded, color: c.textTertiary, size: 18),
          ),
          style: TextStyle(color: c.textPrimary),
          validator: _screeningDateValidator,
          onTap: () async {
            final now = DateTime.now();
            final pickedDate = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: now.subtract(const Duration(days: 7)),
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

        DropdownButtonFormField<String>(
          value: _screenedByCtrl.text.isEmpty ? "Select" : _screenedByCtrl.text,
          decoration: _requiredDecoration("13. Screened by (First name)"),
          dropdownColor: c.surface,
          items: [
            _ddItem("Select", c, hint: true),
            ...(_nursesBySite[_selectedSite] ?? []).map((n) => _ddItem(n, c)),
          ],
          onChanged: (value) {
            setState(() => _screenedByCtrl.text = value ?? "Select");
            _assignScreeningIdIfNeeded();
          },
          validator: (v) => _submitted && (v == null || v == "Select") ? "Required" : null,
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 3, height: 14,
                decoration: BoxDecoration(
                    color: c.primary.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text("A3 · MATERNAL IDENTIFICATION",
                style: TextStyle(color: c.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .3)),
          ]),
        ),

        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _motherFirstCtrl,
              onChanged: (_) => _assignScreeningIdIfNeeded(),
              decoration: _requiredDecoration("14a. Mother's First Name"),
              validator: (v) => _submitted ? _charOnlyValidator(v) : null,
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _motherSurnameCtrl,
              decoration: _inputDecoration("14b. Mother's Surname (optional)"),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty &&
                    !RegExp(r'^[A-Za-z ]+$').hasMatch(v.trim())) return "Letters only";
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
              decoration: _requiredDecoration("15a. Husband's First Name"),
              validator: (v) => _submitted ? _charOnlyValidator(v) : null,
              inputFormatters: nameFormatter,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _husbandSurnameCtrl,
              decoration: _inputDecoration("15b. Husband's Surname (optional)"),
              validator: (v) {
                if (v != null && v.trim().isNotEmpty &&
                    !RegExp(r'^[A-Za-z ]+$').hasMatch(v.trim())) return "Letters only";
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
                controller: _motherPhoneCtrl,
                focusNode: _motherPhoneFocus,
                decoration: _requiredDecoration("18a. Mobile Number — Mother (10 digits)"),
                keyboardType: TextInputType.number,
                style: TextStyle(color: c.textPrimary),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: _phoneValidator,
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
                decoration: _requiredDecoration("18b. Mobile Number — Husband (10 digits)")
                    .copyWith(counterText: ""),
                validator: _phoneValidator,
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

        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _maternalUidCtrl,
                focusNode: _maternalUidFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: _requiredDecoration("16. Maternal UID (CR number, max 12 digits)")
                    .copyWith(counterText: ""),
                onChanged: (v) => setState(() => _maternalUidLimitReached = v.length == 12),
                style: TextStyle(color: c.textPrimary),
              ),
              if (_maternalUidFocus.hasFocus && _maternalUidLimitReached)
                Padding(padding: const EdgeInsets.only(top: 3),
                    child: Text("Maximum 12 digits reached",
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
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _inputDecoration("17. Hospital Admission Number (optional)"),
          style: TextStyle(color: c.textPrimary),
        ),
      ],
    );
  }

  // ── EXCLUSION SECTION ─────────────────────────────────────────────────────

  Widget _buildExclusionSection(AppColors c) {
    return _sectionCard(
      title: "A4 · EXCLUSION CRITERIA",
      icon: Icons.block_rounded,
      accentColor: c.danger,
      trailing: TextButton.icon(
        onPressed: _exclusionAnswers.values.any((v) => v != null)
            ? _resetExclusionSection : null,
        icon: Icon(Icons.refresh_rounded, size: 16, color: c.danger),
        label: Text("Reset", style: TextStyle(color: c.danger, fontSize: 12)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      ),
      children: [
        _exclusionYesNo("ANOMALY",
            "19. Major structural anomalies or genetic abnormality (suspected/proven)"),
        _exclusionYesNo("HYDROPS", "20. Fetal Hydrops"),
        _exclusionYesNo("RESUSCITATION", "22. Decision to forego resuscitation"),
        _exclusionYesNo("INSUFFICIENT", "24. Insufficient time for antenatal consent"),
        _exclusionYesNo("IUFD", "26. Intrauterine Fetal Death (IUFD)"),

        if (_allExclusionsAnswered) ...[
          const SizedBox(height: 4),
          _infoBanner(
            icon: _exclusionPresent
                ? Icons.cancel_rounded
                : Icons.check_circle_rounded,
            text: _exclusionPresent
                ? "Patient is NOT eligible for the trial."
                : "No exclusions — eligible to proceed.",
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
      title: "A5 · CONSENT",
      icon: Icons.verified_rounded,
      accentColor: c.success,
      children: [
        DropdownButtonFormField<String>(
          value: _consentStatus,
          decoration: _requiredDecoration("27. Consent"),
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
            decoration: _requiredDecoration("28. Consent obtained from"),
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
              decoration: _requiredDecoration("Specify relationship"),
              onChanged: (v) => _relationshipOtherText = v,
              style: TextStyle(color: c.textPrimary),
              validator: (v) {
                if (_submitted && (v == null || v.trim().isEmpty)) return "Required";
                return null;
              },
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _consentTakenBy,
            decoration: _requiredDecoration("31. Consent obtained by (nurse)"),
            dropdownColor: c.surface,
            items: [
              _ddItem("Select", c, hint: true),
              ...(_nursesBySite[_selectedSite] ?? []).map((n) => _ddItem(n, c)),
            ],
            onChanged: (v) => setState(() => _consentTakenBy = v!),
            validator: (v) =>
                _submitted && (v == null || v == "Select") ? "Required" : null,
            style: TextStyle(color: c.textPrimary),
          ),
          const SizedBox(height: 14),
        ],

        // 29. Reason for refusal (if No)
        if (_consentStatus == "No") ...[
          Text("29. If no, reason for consent refusal (select all that apply) *",
              style: TextStyle(color: c.textSecondary, fontSize: 13)),
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
          Text("30. If not approached, reason (select all that apply) *",
              style: TextStyle(color: c.textSecondary, fontSize: 13)),
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
            ),
          ],
          const SizedBox(height: 14),
        ],

        // 32. Video PIS shown — shown whenever consent_given has any value
        if (_consentStatus != "Select") ...[
          DropdownButtonFormField<String>(
            value: _videoPisShown,
            decoration: _requiredDecoration("32. Video PIS shown?"),
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

  String? _charOnlyValidator(String? v) {
    if (v == null || v.trim().isEmpty) return "Required";
    if (!RegExp(r'^[A-Za-z ]+$').hasMatch(v.trim())) return "Letters only";
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) return "Required";
    if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) return "Enter 10 digits";
    return null;
  }
}