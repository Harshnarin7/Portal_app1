import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'form_c_resuscitation.dart';
import '../models/form_b.dart';
import '../models/birth_resuscitation.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';

class FormBBirthResuscitation extends StatefulWidget {
  final String screeningId;
  final String maternalUid;
  final String motherName;
  final String motherPhone;
  final String husbandPhone;
  final int gestWeeks;
  final int gestDays;
  final String siteId;
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
  final TextEditingController _enrollmentNumberCtrl   = TextEditingController();
  final TextEditingController _notRandomizedOtherCtrl = TextEditingController();
  final TextEditingController _indicationOtherCtrl    = TextEditingController();
  final TextEditingController _dobController          = TextEditingController();
  final TextEditingController _timeController         = TextEditingController();
  final TextEditingController _babyAnnualNumberCtrl   = TextEditingController();
  final TextEditingController _growthCentileCtrl      = TextEditingController();
  // 18. Conditional indication detail controllers (webform B2.18)
  final TextEditingController _edfDetailCtrl          = TextEditingController();
  final TextEditingController _fetalDetailCtrl        = TextEditingController();
  final TextEditingController _obstetricDetailCtrl    = TextEditingController();

  // ── Birth details ──────────────────────────────────────────────────────────
  List<String> _indications = [];
  String? _delivery;
  String? _vaginalType;
  String? _lscsType;
  String? _gender;
  String? _blenderCode;

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

  // ── Auto-strata from gestation ─────────────────────────────────────────────
  String get _strata =>
      widget.gestWeeks < 28 ? "< 28 weeks" : "≥ 28 – 31 weeks";

  // ── Section collapse state ─────────────────────────────────────────────────
  bool _conditionExpanded     = true;
  bool _randomizationExpanded = true;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadExistingFormB();
  }

  @override
  void dispose() {
    _babyUidCtrl.dispose();
    _babyAdmissionCtrl.dispose();
    _birthWeightCtrl.dispose();
    _randomizationDateCtrl.dispose();
    _enrollmentNumberCtrl.dispose();
    _notRandomizedOtherCtrl.dispose();
    _indicationOtherCtrl.dispose();
    _dobController.dispose();
    _timeController.dispose();
    _babyAnnualNumberCtrl.dispose();
    _growthCentileCtrl.dispose();
    _edfDetailCtrl.dispose();
    _fetalDetailCtrl.dispose();
    _obstetricDetailCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD EXISTING
  // ============================================================

  Future<void> _loadExistingFormB() async {
    final existing = await ApiService().loadFormB(widget.screeningId);
    if (existing == null) return;
    setState(() {
      _babyUidCtrl.text     = existing.babyUid ?? "";
      _birthWeightCtrl.text = existing.birthWeight ?? "";
      _dobController.text   = existing.dateOfBirth ?? "";
      _timeController.text  = existing.timeOfBirth ?? "";
      _indications          = existing.indication == null || existing.indication!.isEmpty
          ? []
          : existing.indication!.split(",").map((e) => e.trim()).toList();
      _delivery = existing.delivery;
      if (_delivery == "Vaginal") {
        _vaginalType = existing.labor;
      } else {
        _lscsType = existing.labor;
      }
      _gender                = existing.gender;
      _requiredResuscitation = existing.requiredResuscitation;
      _randomized            = existing.randomized;
      _poorRespiratoryEffort = existing.poorRespiratoryEffort;
      _poorMuscleTone        = existing.poorMuscleTone;
      _initialStepsRequired  = existing.initialStepsRequired;

      if (existing.enrollmentId != null && existing.enrollmentId!.contains("-")) {
        final parts = existing.enrollmentId!.split("-");
        if (parts.length == 3) {
          _blenderCode = parts[1];
          _enrollmentNumberCtrl.text = parts[2];
        }
      }
    });
  }

  // ============================================================
  // SAVE & CONTINUE
  // ============================================================

  Future<void> _onSaveContinue() async {
    setState(() => _submitted = true);

    if (_dobController.text.isEmpty) { _showMsg("Please select Date of Birth"); return; }
    if (_timeController.text.isEmpty) { _showMsg("Please select Time of Birth"); return; }
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
    if (_requiredResuscitation == null) {
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
      if (_blenderCode == null || _blenderCode!.isEmpty) {
        _showMsg("Please select blender code"); return;
      }
      if (_enrollmentNumberCtrl.text.trim().isEmpty) {
        _showMsg("Please enter enrollment number"); return;
      }
      if (_enrollmentNumberCtrl.text.trim().length != 3) {
        _showMsg("Enrollment number must be exactly 3 digits"); return;
      }
    }

    final enrollmentId = _randomized == true
        ? "${widget.siteId}-${_blenderCode ?? ''}-${_enrollmentNumberCtrl.text.padLeft(3, '0')}"
        : null;

    String? randDateIso;
    if (_randomized == true && _randomizationDateCtrl.text.trim().isNotEmpty) {
      randDateIso = _toIsoDate(_randomizationDateCtrl.text.trim());
    }

    final shared = BirthResuscitationData()
      ..screeningId           = widget.screeningId
      ..enrollmentId          = enrollmentId
      ..babyUid               = _babyUidCtrl.text.trim()
      ..babyAdmissionNo       = _babyAdmissionCtrl.text.trim().isEmpty
                                  ? null : _babyAdmissionCtrl.text.trim()
      ..babyAnnualNo          = _babyAnnualNumberCtrl.text.trim().isEmpty
                                  ? null : _babyAnnualNumberCtrl.text.trim()
      ..dateOfBirth           = _parseDobText(_dobController.text)
      ..timeOfBirth           = _timeController.text.trim().isEmpty
                                  ? null : _timeController.text.trim()
      ..gender                = _gender
      ..gestationWeeks        = widget.gestWeeks
      ..gestationDays         = widget.gestDays
      ..gestationRandWeeks    = widget.gestWeeks
      ..gestationRandDays     = widget.gestDays
      ..birthWeight           = double.tryParse(_birthWeightCtrl.text)
      ..intrauterineCentile   = _growthCentileCtrl.text.trim().isEmpty
                                  ? null : _growthCentileCtrl.text.trim()
      ..deliveryMode          = _delivery
      ..vaginalDeliveryType   = _delivery == "Vaginal" ? _vaginalType : null
      ..lscsType              = _delivery == "LSCS"    ? _lscsType    : null
      ..indicationForDelivery = List<String>.from(_indications)
      ..indicationForDeliveryOther = _indications.contains("Other")
                                  ? _indicationOtherCtrl.text.trim() : null
      ..poorRespEfforts       = _poorRespiratoryEffort
      ..poorMuscleTone        = _poorMuscleTone
      ..hrAbove100            = _hrAbove100
      ..initialSteps          = _initialStepsRequired
      ..requiredResuscitation = _requiredResuscitation
      ..ppvRequired           = _requiredResuscitation == true ? true : null
      ..randomised            = _requiredResuscitation == true ? _randomized : null
      ..randomisationDate     = randDateIso
      ..strata                = _randomized == true ? _strata : null
      ..enrollmentReasonNotRandomized      = _randomized == false
                                  ? _notRandomizedReason : null
      ..enrollmentReasonNotRandomizedOther = _notRandomizedReason == "Other"
                                  ? _notRandomizedOtherCtrl.text.trim() : null;

    final formB = FormB(
      screeningId          : widget.screeningId,
      babyUid              : _babyUidCtrl.text,
      birthWeight          : _birthWeightCtrl.text,
      dateOfBirth          : _dobController.text,
      timeOfBirth          : _timeController.text,
      indication           : _indications.join(", "),
      delivery             : _delivery ?? "",
      labor                : _delivery == "Vaginal" ? (_vaginalType ?? "") : (_lscsType ?? ""),
      gender               : _gender ?? "",
      requiredResuscitation: _requiredResuscitation ?? false,
      randomized           : _randomized ?? false,
      enrollmentId         : enrollmentId ?? "",
      poorRespiratoryEffort: _poorRespiratoryEffort,
      poorMuscleTone       : _poorMuscleTone,
      initialStepsRequired : _initialStepsRequired,
    );
    await ApiService().saveFormB(formB);

    // Server sync only when enrollment_id exists (backend requires it).
    if (enrollmentId != null && enrollmentId.isNotEmpty) {
      try {
        await FormsApiService.instance.saveBirthResuscitation(shared.toJson());
      } catch (e) {
        if (!mounted) return;
        _showMsg("Save failed — check connection and try again. ($e)");
        return;
      }
    }

    if (_requiredResuscitation == false) {
      _showParticipationEndedDialog();
      return;
    }

    if (_randomized == false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Form B saved locally (not randomised — server sync needs enrollment ID)"),
        backgroundColor: AppTheme.of(context).warning,
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
    final picked = await showDatePicker(
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
    return InputDecoration(
      labelText    : label,
      helperText   : helper,
      helperStyle  : TextStyle(color: c.textTertiary, fontSize: 11),
      labelStyle   : TextStyle(color: c.textSecondary, fontSize: 13),
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
      Text(title,
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
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
      Text(title,
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
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
      Text(label,
          style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
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
        Text("Strata: ",
            style: TextStyle(color: c.textSecondary, fontSize: 13)),
        Text(_strata,
            style: TextStyle(
                color: c.primary,
                fontWeight: FontWeight.w800,
                fontSize: 13)),
        const Spacer(),
        Text("(27.)",
            style: TextStyle(color: c.textTertiary, fontSize: 11)),
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
                        child: Text("View only — previously filled Form B",
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
        Text("Form B: Birth & Resuscitation",
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.arrow_forward_rounded,
              size: 18, color: Colors.white),
          label: const Text("Save & Continue",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          onPressed: _onSaveContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primary,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  // ── IDENTIFICATION ─────────────────────────────────────────────────────────

  Widget _buildIdentificationSection(AppColors c) {
    return _sectionCard(
      title      : "IDENTIFICATION",
      icon       : Icons.badge_rounded,
      accentColor: c.primary,
      c          : c,
      children   : [
        Row(children: [
          Expanded(child: _infoTile("1. Screening ID", widget.screeningId, c)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile("2. Maternal UID", widget.maternalUid, c)),
        ]),
        const SizedBox(height: 10),
        _infoTile("3. Mother's First Name", widget.motherName, c),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _infoTile("5. Mobile No. — Mother",  widget.motherPhone,  c)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile("5. Mobile No. — Husband", widget.husbandPhone, c)),
        ]),

        const SizedBox(height: 18),
        _subLabel("Baby Details", c),

        // Baby UID
        TextFormField(
          controller: _babyUidCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: _input("4. Baby UID *", c).copyWith(
            helperText: _babyUidMaxReached
                ? "Maximum 12 digits reached"
                : "Enter 12-digit Baby UID",
            helperStyle: TextStyle(
                color: _babyUidMaxReached ? c.success : c.textTertiary,
                fontSize: 11),
          ),
          style: TextStyle(color: c.textPrimary),
          onChanged: (v) =>
              setState(() => _babyUidMaxReached = v.length == 12),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return "Required";
            if (v.length != 12) return "Baby UID must be exactly 12 digits";
            return null;
          },
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _babyAdmissionCtrl,
          decoration: _input("6. Baby Admission No.", c),
          style: TextStyle(color: c.textPrimary),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _babyAnnualNumberCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _input("7. Baby Annual No.", c),
          style: TextStyle(color: c.textPrimary),
        ),
      ],
    );
  }

  // ── BIRTH DETAILS ──────────────────────────────────────────────────────────

  Widget _buildBirthDetailsSection(AppColors c) {
    return _sectionCard(
      title      : "BIRTH DETAILS",
      icon       : Icons.child_care_rounded,
      accentColor: c.success,
      c          : c,
      children   : [
        _infoTile(
            "11. Gestation at Screening (auto)",
            "${widget.gestWeeks}w ${widget.gestDays}d",
            c),
        const SizedBox(height: 10),
        _infoTile(
            "12. Gestation at Randomization (auto)",
            "${widget.gestWeeks}w ${widget.gestDays}d",
            c),
        const SizedBox(height: 16),

        // Birth weight
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

        // Growth centile
        TextFormField(
          controller: _growthCentileCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration:
              _input("14. Intrauterine Growth Status (Centile)", c),
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
        const SizedBox(height: 16),

        // Date of birth
        _dateTile(
          label     : "8. Date of Birth *",
          hint      : "Select date (DD/MM/YY)",
          controller: _dobController,
          icon      : Icons.calendar_today_rounded,
          c         : c,
          onTap     : () async {
            final picked = await showDatePicker(
              context    : context,
              initialDate: DateTime.now(),
              firstDate  : DateTime(2000),
              lastDate   : DateTime.now(),
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

        // Time of birth
        _dateTile(
          label     : "9. Time of Birth *",
          hint      : "Select time (HH:MM)",
          controller: _timeController,
          icon      : Icons.access_time_rounded,
          c         : c,
          onTap     : () async {
            final picked = await showTimePicker(
              context    : context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              setState(() {
                _timeController.text =
                    "${picked.hour.toString().padLeft(2, '0')}:"
                    "${picked.minute.toString().padLeft(2, '0')}";
              });
            }
          },
        ),
        const SizedBox(height: 18),

        // Indication (18. — webform B2.18)
        Text("18. Indication for Delivery *  (select all that apply)",
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            "pPROM",
            "PTL",
            "APH",
            "Placenta Previa",
            "PIH",
            "PE/Imminent Eclampsia",
            "Other",
          ].map((opt) {
            final sel = _indications.contains(opt);
            return FilterChip(
              selected        : sel,
              label           : Text(opt),
              labelStyle      : TextStyle(
                  color: sel ? Colors.white : c.textSecondary,
                  fontSize: 12),
              backgroundColor : c.surfaceAlt,
              selectedColor   : c.primary,
              checkmarkColor  : Colors.white,
              side            : BorderSide(
                  color: sel ? c.primary : c.border, width: 1.5),
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _indications.add(opt);
                  } else {
                    _indications.remove(opt);
                    if (opt == "Other") _indicationOtherCtrl.clear();
                  }
                });
              },
            );
          }).toList(),
        ),
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
        const SizedBox(height: 18),

        // Delivery
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

        // Gender  (10. — webform values: Female / Male / DSD)
        _pillRadio(
          title    : "10. Gender *",
          options  : const ["Female", "Male", "DSD"],
          value    : _gender,
          onChanged: (v) => setState(() => _gender = v),
          c        : c,
          showError: _submitted && _gender == null,
        ),
      ],
    );
  }

  // ── CONDITION AT BIRTH ─────────────────────────────────────────────────────

  Widget _buildConditionSection(AppColors c) {
    return _sectionCard(
      title      : "CONDITION AT BIRTH & RANDOMIZATION",
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
                onChanged : (v) =>
                    setState(() => _initialStepsRequired = v),
                trueColor : c.warning,
                falseColor: c.success,
                c         : c,
              ),
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
      title      : "RANDOMIZATION",
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

                _subLabel("26. Enrollment ID", c),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Site ID
                  Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Site ID",
                              style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Container(
                            height: 46,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            decoration: BoxDecoration(
                                color: c.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.border)),
                            child: Text(widget.siteId,
                                style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                        ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(" – ",
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),

                  // Blender code
                  Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Blender Code *",
                              style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 46,
                            child: DropdownButtonFormField<String>(
                              value        : _blenderCode,
                              isExpanded   : true,
                              dropdownColor: c.surface,
                              decoration: InputDecoration(
                                hintText : "Select",
                                hintStyle: TextStyle(color: c.textTertiary),
                                filled   : true,
                                fillColor: c.surfaceAlt,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: c.border)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: c.border)),
                              ),
                              items: [null, "A", "B", "C", "D"].map((v) =>
                                  DropdownMenuItem(
                                    value: v,
                                    child: Text(v ?? "Select",
                                        style: TextStyle(
                                            color: v == null
                                                ? c.textTertiary
                                                : c.textPrimary,
                                            fontSize: 13)),
                                  )).toList(),
                              onChanged: (v) =>
                                  setState(() => _blenderCode = v),
                              validator: (v) =>
                                  (_randomized == true &&
                                          (v == null || v.isEmpty))
                                      ? "Required"
                                      : null,
                              style: TextStyle(color: c.textPrimary),
                            ),
                          ),
                        ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(" – ",
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),

                  // Subject number
                  Expanded(
                    flex: 2,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Subject No *",
                              style: TextStyle(
                                  color: c.textTertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 46,
                            child: TextFormField(
                              controller: _enrollmentNumberCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                              decoration: InputDecoration(
                                hintText : "001",
                                hintStyle: TextStyle(color: c.textTertiary),
                                filled   : true,
                                fillColor: c.surfaceAlt,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: c.border)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: c.border)),
                              ),
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                if (_randomized == true) {
                                  if (v == null || v.isEmpty) return "Required";
                                  if (v.length != 3) return "3 digits";
                                }
                                return null;
                              },
                            ),
                          ),
                        ]),
                  ),
                ]),

                const SizedBox(height: 14),

                // Live enrollment ID preview
                if (_blenderCode != null &&
                    _enrollmentNumberCtrl.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color       : c.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: c.primary.withOpacity(0.35)),
                    ),
                    child: Row(children: [
                      Icon(Icons.verified_rounded,
                          color: c.primary, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        "${widget.siteId}-$_blenderCode-"
                        "${_enrollmentNumberCtrl.text.padLeft(3, '0')}",
                        style: TextStyle(
                            color: c.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 1),
                      ),
                    ]),
                  ),

                // ── STRATA appears here, after enrollment ID ──
                const SizedBox(height: 12),
                _strataBanner(c),
              ],

              // ── Randomized = NO ───────────────────────────────────────
              if (_randomized == false) ...[
                Text("28. Reason for not randomizing *",
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