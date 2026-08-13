import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../models/form_c.dart';
import '../models/birth_resuscitation.dart';
import '../models/form_b.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';

class FormCResuscitationDetails extends StatefulWidget {
  final String screeningId;
  final FormB?  formB;
  final String  gestation;
  final String  motherName;
  final String  babyUid;
  // Shared birth-resuscitation payload, already populated in Form B with
  // B1–B3 fields. Form C fills B4–B6 into the same object and re-saves so
  // the whole thing lands in ONE backend row (birth_resuscitation table).
  final BirthResuscitationData? shared;
  /// When true, form is read-only (previously filled review).
  final bool viewOnly;

  const FormCResuscitationDetails({
    super.key,
    required this.screeningId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.formB,
    this.shared,
    this.viewOnly = false,
  });

  @override
  State<FormCResuscitationDetails> createState() =>
      _FormCResuscitationDetailsState();
}

class _FormCResuscitationDetailsState
    extends State<FormCResuscitationDetails> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();

  // ── Controllers ──────────────────────────────────────────────────────────
  final _ventDurationCtrl  = TextEditingController();
  final _ccDurationCtrl    = TextEditingController();
  final _epiDoseCtrl       = TextEditingController();
  final _cordClampTimeCtrl = TextEditingController();
  final _timeToRespCtrl    = TextEditingController();
  final _timeToSpo2Ctrl    = TextEditingController();
  final _spo2At5Ctrl       = TextEditingController();
  final _fio2ExitCtrl      = TextEditingController();
  final _spo2ExitCtrl      = TextEditingController();
  final _totalTimeCtrl     = TextEditingController();
  final _exitOtherCtrl     = TextEditingController();
  final _phCtrl            = TextEditingController();
  final _beCtrl            = TextEditingController();
  final _pco2Ctrl          = TextEditingController();
  // ── NEW controllers — B4/B6 fields missing before ────────────────────────
  final _sibPeepValueCtrl   = TextEditingController();   // 29a. cmH₂O
  final _tpiecePipCtrl      = TextEditingController();   // 29b. PIP
  final _tpiecePeepCtrl     = TextEditingController();   // 29b. PEEP
  final _tpieceFlowCtrl     = TextEditingController();   // 29b. Flow
  final _adrenalineCumCtrl  = TextEditingController();   // 40. cumulative
  final _fluidBolusDosesCtrl= TextEditingController();   // 42.
  final _fluidBolusCumCtrl  = TextEditingController();   // 43.
  final _respirationDaysCtrl  = TextEditingController(); // 48. days
  final _respirationHoursCtrl = TextEditingController(); // 48. hours
  final _blenderStopDescCtrl  = TextEditingController(); // 64.

  // Cord clamp — managed as plain string, NOT a TextEditingController
  String _cordClampedAtDisplay      = "";
  int?   _cordClampedAtTotalSeconds;

  // ── State ─────────────────────────────────────────────────────────────────
  // Form C is only reached when Form B Q23 = Required → PPV path.
  bool?   _ventilation = true;
  String? _device;
  bool?   _sibPeep;
  String? _sibPeepWith;         // 29a. Yes / No dropdown (with PEEP valve?)
  String? _interface;
  bool?   _intubation;
  bool?   _chestCompression;
  bool?   _epinephrine;
  String? _adrenalineDilution;  // 36.
  String? _adrenalineRoute;     // 37.
  bool?   _fluidBolus;
  bool?   _placentalTransfusion;
  String? _placentalMethod;
  bool?   _cordBloodDone;
  bool?   _cordBloodWithin1hr;  // 57.
  String? _cordBloodSource;     // 58.
  bool?   _resusFailure;
  String? _exitReason;
  bool?   _blenderStopped;      // 64.

  bool _submitted = false;

  // ── Timeline ──────────────────────────────────────────────────────────────
  final List<int>    _timelineMins = [1, 5, 10, 15, 20];
  // Web B5 (48–50): Oxygen, CPAP, Apgar only.
  final List<String> _timelineRows = [
    "Oxygen", "CPAP",
  ];
  final Map<String, Map<int, String?>> _timeline = {};

  final Map<int, TextEditingController> _apgarCtrls = {
    1:  TextEditingController(),
    5:  TextEditingController(),
    10: TextEditingController(),
    15: TextEditingController(),
    20: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    for (final row in _timelineRows) {
      _timeline[row] = {for (final m in _timelineMins) m: null};
    }
    if (widget.shared != null) {
      _applyBirthData(widget.shared!);
    } else {
      _hydrateFromSaved();
    }
  }

  void _applyBirthData(BirthResuscitationData d) {
    setState(() {
      _device = d.devicePpv;
      _sibPeepWith = d.sibPeepWith;
      _sibPeep = d.sibPeepWith == "Yes"
          ? true
          : (d.sibPeepWith == "No" ? false : null);
      if (d.sibPeepCmh2o != null) {
        _sibPeepValueCtrl.text = d.sibPeepCmh2o.toString();
      }
      if (d.tpiecePip != null) _tpiecePipCtrl.text = d.tpiecePip.toString();
      if (d.tpiecePeep != null) _tpiecePeepCtrl.text = d.tpiecePeep.toString();
      if (d.tpieceFlow != null) _tpieceFlowCtrl.text = d.tpieceFlow.toString();
      _interface = d.interfaceUsed;
      if (d.ppvDuration != null) {
        _ventDurationCtrl.text = d.ppvDuration.toString();
      }
      _intubation = d.intubation;
      _chestCompression = d.chestCompression;
      if (d.ccDuration != null) _ccDurationCtrl.text = d.ccDuration.toString();
      _epinephrine = d.adrenaline;
      _adrenalineDilution = d.adrenalineDilution;
      _adrenalineRoute = d.adrenalineRoute;
      _fluidBolus = d.fluidBolus;
      if (d.fluidBolusDoses != null) {
        _fluidBolusDosesCtrl.text = d.fluidBolusDoses.toString();
      }
      if (d.fluidBolusCumulative != null) {
        _fluidBolusCumCtrl.text = d.fluidBolusCumulative.toString();
      }
      _placentalTransfusion = d.placentalTransfusion;
      _placentalMethod = d.transfusionMethod;
      _cordClampedAtDisplay = d.cordClampTimestamp ?? "";
      if (d.cordClampTime != null) {
        _cordClampTimeCtrl.text = "${d.cordClampTime} sec";
      }
      if (d.timeToRespiration != null) {
        _timeToRespCtrl.text = _secondsToHms(d.timeToRespiration!);
      }
      if (d.spo25min != null) _spo2At5Ctrl.text = d.spo25min.toString();
      if (d.timeToSpo280 != null) {
        _timeToSpo2Ctrl.text = _secondsToHms(d.timeToSpo280!);
      }
      _cordBloodDone = d.cordBloodDone;
      _cordBloodWithin1hr = d.cordBloodWithin1hr;
      _cordBloodSource = d.cordBloodSource;
      if (d.cordPh != null) _phCtrl.text = d.cordPh.toString();
      if (d.cordSbe != null) _beCtrl.text = d.cordSbe.toString();
      if (d.cordPco2 != null) _pco2Ctrl.text = d.cordPco2.toString();
      _resusFailure = d.resusFailure;
      if (d.spo2ExitTrialGas != null) {
        _spo2ExitCtrl.text = d.spo2ExitTrialGas.toString();
      }
      if (d.totalResusTime != null) {
        _totalTimeCtrl.text = d.totalResusTime.toString();
      }
      final exit = d.reasonExitTrialGas ?? "";
      const exitOpts = [
        "Responded to resuscitation",
        "Required override to 100% O2 or CC",
        "Other",
      ];
      if (exit.isEmpty) {
        _exitReason = null;
      } else if (exitOpts.contains(exit)) {
        _exitReason = exit;
      } else {
        _exitReason = "Other";
        _exitOtherCtrl.text = exit;
      }
      _blenderStopped = d.blenderStopped;
      if (d.blenderStoppedDescription != null) {
        _blenderStopDescCtrl.text = d.blenderStoppedDescription!;
      }
      const rowLabel = {"oxygen": "Oxygen", "cpap": "CPAP"};
      const ynIn = {"Yes": "Y", "No": "N", "Y": "Y", "N": "N", "NR": "NR"};
      d.interventions.forEach((key, minMap) {
        if (key == "apgar") {
          minMap.forEach((min, val) {
            final m = int.tryParse(min);
            if (m != null) _apgarCtrls[m]?.text = val;
          });
          return;
        }
        final row = rowLabel[key];
        if (row == null || !_timeline.containsKey(row)) return;
        minMap.forEach((min, val) {
          final m = int.tryParse(min);
          if (m == null) return;
          _timeline[row]![m] = ynIn[val] ?? val;
        });
      });
    });
  }

  String _secondsToHms(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return "${h.toString().padLeft(2, '0')}:"
        "${m.toString().padLeft(2, '0')}:"
        "${s.toString().padLeft(2, '0')}";
  }

  Future<void> _hydrateFromSaved() async {
    final eid = widget.formB?.enrollmentId.trim() ?? '';
    if (eid.isNotEmpty) {
      try {
        final remote =
            await FormsApiService.instance.loadBirthResuscitation(eid);
        if (remote != null && mounted) {
          _applyBirthData(BirthResuscitationData.fromJson(remote));
          return;
        }
      } catch (_) {}
    }
    final existing = await _api.loadFormC(widget.screeningId);
    if (existing == null || !mounted) return;
    setState(() {
      _ventilation = existing.ventilation;
      _device = existing.device.isEmpty ? null : existing.device;
      _sibPeep = existing.sibPeep;
      _sibPeepWith = existing.sibPeep ? "Yes" : "No";
      _interface = existing.interface.isEmpty ? null : existing.interface;
      _ventDurationCtrl.text = existing.ventilationDuration;
      _intubation = existing.intubation;
      _chestCompression = existing.chestCompression;
      _ccDurationCtrl.text = existing.chestCompressionDuration;
      _epinephrine = existing.epinephrine;
      _epiDoseCtrl.text = existing.epinephrineDoses;
      _fluidBolus = existing.fluidBolus;
      _placentalTransfusion = existing.placentalTransfusion;
      _placentalMethod =
          existing.placentalMethod.isEmpty ? null : existing.placentalMethod;
      _cordClampedAtDisplay = existing.cordClampedAt;
      _cordClampTimeCtrl.text = existing.cordClampTime;
      _timeToRespCtrl.text = existing.timeToRespiration;
      _timeToSpo2Ctrl.text = existing.timeToSpo2Above80;
      _spo2At5Ctrl.text = existing.spo2At5Min;
      _totalTimeCtrl.text = existing.totalTime;
      _fio2ExitCtrl.text = existing.fio2Exit;
      _spo2ExitCtrl.text = existing.spo2Exit;
      _phCtrl.text = existing.ph;
      _beCtrl.text = existing.be;
      _pco2Ctrl.text = existing.pco2;
      _cordBloodDone = existing.cordBloodDone;
      _resusFailure = existing.resusFailure;
      final exit = existing.exitReason;
      const exitOpts = [
        "Responded to resuscitation",
        "Required override to 100% O2 or CC",
        "Other",
      ];
      if (exit.isEmpty) {
        _exitReason = null;
      } else if (exitOpts.contains(exit)) {
        _exitReason = exit;
      } else {
        _exitReason = "Other";
        _exitOtherCtrl.text = exit;
      }
      for (final row in _timelineRows) {
        final saved = existing.timelineChecks[row];
        if (saved == null) continue;
        for (final m in _timelineMins) {
          if (saved.containsKey(m)) {
            _timeline[row]![m] = saved[m]! ? "Y" : "N";
          }
        }
      }
      for (final e in existing.apgarScores.entries) {
        _apgarCtrls[e.key]?.text = e.value;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _ventDurationCtrl, _ccDurationCtrl, _epiDoseCtrl,
      _cordClampTimeCtrl, _timeToRespCtrl, _timeToSpo2Ctrl,
      _spo2At5Ctrl, _fio2ExitCtrl, _spo2ExitCtrl,
      _totalTimeCtrl, _exitOtherCtrl, _phCtrl, _beCtrl, _pco2Ctrl,
      _sibPeepValueCtrl, _tpiecePipCtrl, _tpiecePeepCtrl, _tpieceFlowCtrl,
      _adrenalineCumCtrl, _fluidBolusDosesCtrl, _fluidBolusCumCtrl,
      _respirationDaysCtrl, _respirationHoursCtrl, _blenderStopDescCtrl,
    ]) { c.dispose(); }
    for (final c in _apgarCtrls.values) c.dispose();
    super.dispose();
  }

  // ── Cord clamp auto-calc ──────────────────────────────────────────────────
  void _recalcCordClampTime() {
    if (_cordClampedAtTotalSeconds == null) return;
    final birthTimeStr = widget.formB?.timeOfBirth ?? "";
    if (birthTimeStr.isEmpty) {
      _cordClampTimeCtrl.text = "Birth time unavailable"; return;
    }
    final parts = birthTimeStr.split(":");
    if (parts.length < 2) { _cordClampTimeCtrl.text = "—"; return; }
    final birthSec = (int.tryParse(parts[0]) ?? 0) * 3600
                   + (int.tryParse(parts[1]) ?? 0) * 60;
    final diff = _cordClampedAtTotalSeconds! - birthSec;
    _cordClampTimeCtrl.text = "${diff < 0 ? 0 : diff} sec";
  }

  // ── HH:MM:SS spinner picker ───────────────────────────────────────────────
  Future<Duration?> _pickDuration(BuildContext context, {Duration? initial}) {
    int hh = initial?.inHours        ?? 0;
    int mm = (initial?.inMinutes ?? 0) % 60;
    int ss = (initial?.inSeconds ?? 0) % 60;
    final c = AppTheme.of(context);

    return showDialog<Duration>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.timer_outlined, color: c.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Text("Select Duration",
                style: TextStyle(color: c.textPrimary,
                    fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Center(child: Text("Hours",
                  style: TextStyle(color: c.textTertiary, fontSize: 11,
                      fontWeight: FontWeight.w600)))),
              const SizedBox(width: 20),
              Expanded(child: Center(child: Text("Minutes",
                  style: TextStyle(color: c.textTertiary, fontSize: 11,
                      fontWeight: FontWeight.w600)))),
              const SizedBox(width: 20),
              Expanded(child: Center(child: Text("Seconds",
                  style: TextStyle(color: c.textTertiary, fontSize: 11,
                      fontWeight: FontWeight.w600)))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _spinner(hh, 0, 23, c, (v) => setDlg(() => hh = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":", style: TextStyle(color: c.textSecondary,
                    fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: _spinner(mm, 0, 59, c, (v) => setDlg(() => mm = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":", style: TextStyle(color: c.textSecondary,
                    fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              Expanded(child: _spinner(ss, 0, 59, c, (v) => setDlg(() => ss = v))),
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
                  style: TextStyle(color: c.primary, fontSize: 22,
                      fontWeight: FontWeight.w800, letterSpacing: 3),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: TextStyle(
                  color: c.textTertiary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(
                  ctx, Duration(hours: hh, minutes: mm, seconds: ss)),
              child: const Text("Confirm",
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner(int value, int min, int max, AppColors c,
      void Function(int) onChange) {
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Icon(Icons.keyboard_arrow_up_rounded, color: c.primary, size: 20),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(value.toString().padLeft(2, '0'),
                style: TextStyle(color: c.textPrimary, fontSize: 22,
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
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: c.primary, size: 20),
          ),
        ),
      ]),
    );
  }

  String _fmtDuration(Duration d) =>
      "${d.inHours.toString().padLeft(2, '0')}:"
      "${(d.inMinutes % 60).toString().padLeft(2, '0')}:"
      "${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  // ── Save ──────────────────────────────────────────────────────────────────
  void _saveFormC() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final needsSibPeepDetails =
        (_device == "Self-inflating bag" || _device == "Both");
    final needsTpieceDetails =
        (_device == "T-piece" || _device == "Both");

    final checks = <List<dynamic>>[
      [_device == null,                                        "Please select device (29.)"],
      [needsSibPeepDetails && _sibPeepWith == null,            "Please answer SIB — With PEEP valve? (29a.)"],
      [needsSibPeepDetails && _sibPeepWith == "Yes" && _sibPeepValueCtrl.text.trim().isEmpty,
                                                                "Please enter SIB PEEP value (29a.)"],
      [needsTpieceDetails && _tpiecePipCtrl.text.trim().isEmpty,   "Please enter T-piece PIP (29b.)"],
      [needsTpieceDetails && _tpiecePeepCtrl.text.trim().isEmpty,  "Please enter T-piece PEEP (29b.)"],
      [needsTpieceDetails && _tpieceFlowCtrl.text.trim().isEmpty,  "Please enter T-piece Flow (29b.)"],
      [_interface == null,                                     "Please select interface (30.)"],
      [_intubation == null,                                     "Please select intubation (32.)"],
      [_chestCompression == null,                               "Please select chest compression (33.)"],
      [_epinephrine == null,                                    "Please select epinephrine (35.)"],
      [_epinephrine == true && _adrenalineDilution == null,     "Please select epinephrine dilution (36.)"],
      [_epinephrine == true && _adrenalineRoute == null,        "Please select epinephrine route (37.)"],
      [_fluidBolus == null,                                     "Please select fluid bolus (38.)"],
      [_placentalTransfusion == null,                           "Please select placental transfusion (41.)"],
      [_placentalTransfusion == true && _placentalMethod == null, "Please select transfusion method (42.)"],
      [_placentalTransfusion == true && _cordClampedAtTotalSeconds == null,
                                                                "Please select cord clamped time (43.)"],
      [_cordBloodDone == null,                                  "Please select cord blood status (51.)"],
      [_cordBloodDone == false && _cordBloodWithin1hr == null,  "Please answer within 1hr of birth (52.)"],
      [_cordBloodDone == false && _cordBloodWithin1hr == true && _cordBloodSource == null,
                                                                "Please select cord blood source (53.)"],
      [_resusFailure == null,                                   "Please select resuscitation failure (55.)"],
      [_exitReason == null,                                     "Please select reason for exit (58.)"],
      [_blenderStopped == null,                                 "Please answer PORTAL blender status (59.)"],
      [_blenderStopped == true && _blenderStopDescCtrl.text.trim().isEmpty,
                                                                "Please describe blender stop (59.)"],
    ];

    for (final check in checks) {
      if (check[0] as bool) { _showMsg(check[1] as String); return; }
    }

    // Merge with existing backend / shared Form B record so B1–B3 is not wiped.
    BirthResuscitationData data;
    if (widget.shared != null) {
      data = widget.shared!;
    } else {
      data = BirthResuscitationData();
      final eid = widget.formB?.enrollmentId.trim() ?? '';
      if (eid.isNotEmpty) {
        try {
          final remote =
              await FormsApiService.instance.loadBirthResuscitation(eid);
          if (remote != null) {
            data = BirthResuscitationData.fromJson(remote);
          }
        } catch (_) {
          // Fall through with empty base — still save B4–B6 keys.
        }
      }
      data
        ..screeningId ??= widget.screeningId
        ..enrollmentId ??= eid.isEmpty ? null : eid
        ..babyUid ??= widget.babyUid;
    }

    if (data.enrollmentId == null || data.enrollmentId!.trim().isEmpty) {
      _showMsg("Missing enrollment ID — complete Form B randomisation first.");
      return;
    }

    data
      ..ppvRequired         = true
      ..requiredResuscitation = true
      ..devicePpv           = _device
      ..sibPeepWith         = needsSibPeepDetails ? _sibPeepWith : null
      ..sibPeepCmh2o        = needsSibPeepDetails
          ? double.tryParse(_sibPeepValueCtrl.text.trim()) : null
      ..tpiecePip           = needsTpieceDetails
          ? double.tryParse(_tpiecePipCtrl.text.trim()) : null
      ..tpiecePeep          = needsTpieceDetails
          ? double.tryParse(_tpiecePeepCtrl.text.trim()) : null
      ..tpieceFlow          = needsTpieceDetails
          ? double.tryParse(_tpieceFlowCtrl.text.trim()) : null
      ..interfaceUsed       = _interface
      ..ppvDuration         = int.tryParse(_ventDurationCtrl.text.trim())
      ..intubation          = _intubation
      ..chestCompression    = _chestCompression
      ..ccDuration          = int.tryParse(_ccDurationCtrl.text.trim())
      ..adrenaline          = _epinephrine
      ..adrenalineDilution  = _epinephrine == true ? _adrenalineDilution : null
      ..adrenalineRoute     = _epinephrine == true ? _adrenalineRoute : null
      ..medDoses            = int.tryParse(_epiDoseCtrl.text.trim())
      ..adrenalineCumulative = double.tryParse(_adrenalineCumCtrl.text.trim())
      ..fluidBolus          = _fluidBolus
      ..fluidBolusDoses     = int.tryParse(_fluidBolusDosesCtrl.text.trim())
      ..fluidBolusCumulative= double.tryParse(_fluidBolusCumCtrl.text.trim())
      ..placentalTransfusion= _placentalTransfusion
      ..transfusionMethod   = _placentalTransfusion == true ? _placentalMethod : null
      ..cordClampTimestamp  = _placentalTransfusion == true && _cordClampedAtDisplay.isNotEmpty
          ? _cordClampedAtDisplay : null
      ..cordClampTime       = _placentalTransfusion == true
          ? _elapsedCordClampSeconds() : null
      ..timeToRespiration   = _hmsToSeconds(_timeToRespCtrl.text)
      ..spo25min            = int.tryParse(_spo2At5Ctrl.text.trim())
      ..timeToSpo280        = _hmsToSeconds(_timeToSpo2Ctrl.text)
      ..cordBloodDone       = _cordBloodDone
      ..cordBloodWithin1hr  = _cordBloodDone == false ? _cordBloodWithin1hr : null
      ..cordBloodSource     = (_cordBloodDone == false && _cordBloodWithin1hr == true)
          ? _cordBloodSource : null
      ..cordPh              = double.tryParse(_phCtrl.text.trim())
      ..cordSbe             = double.tryParse(_beCtrl.text.trim())
      ..cordPco2            = double.tryParse(_pco2Ctrl.text.trim())
      ..resusFailure        = _resusFailure
      ..spo2ExitTrialGas    = double.tryParse(_spo2ExitCtrl.text.trim())
      // Web stores total_resus_time in minutes (field 57).
      ..totalResusTime      = _totalTimeMinutes()
      ..reasonExitTrialGas  = _exitReason
      ..reasonExitTrialGasOther = _exitReason == "Other"
          ? _exitOtherCtrl.text.trim() : null
      ..blenderStopped      = _blenderStopped
      ..blenderStoppedDescription = _blenderStopped == true
          ? _blenderStopDescCtrl.text.trim() : null;

    // Fill the nested interventions map (B5 — minute-wise + Apgar).
    // Values must be Yes/No/NR to match web IntvCell.
    final ynMap = <String, Map<String, String>>{};
    const rowKey = {
      "Oxygen": "oxygen",
      "CPAP": "cpap",
    };
    const ynOut = {"Y": "Yes", "N": "No", "NR": "NR", "Yes": "Yes", "No": "No"};
    _timeline.forEach((row, minMap) {
      final key = rowKey[row] ?? row.toLowerCase();
      ynMap[key] = {
        for (final e in minMap.entries)
          if ((e.value ?? "").toString().trim().isNotEmpty)
            e.key.toString(): ynOut[e.value] ?? e.value.toString(),
      };
    });
    ynMap["apgar"] = {
      for (final e in _apgarCtrls.entries)
        if (e.value.text.trim().isNotEmpty)
          e.key.toString(): e.value.text.trim(),
    };
    data.interventions = ynMap;

    final timelineForModel = _timeline.map((row, minMap) =>
        MapEntry(row, minMap.map((min, val) => MapEntry(min, val == "Y"))));

    final formC = FormC(
      screeningId             : widget.screeningId,
      ventilation             : _ventilation ?? false,
      device                  : _device ?? "",
      sibPeep                 : _sibPeep ?? false,
      interface               : _interface ?? "",
      ventilationDuration     : _ventDurationCtrl.text.trim(),
      intubation              : _intubation ?? false,
      chestCompression        : _chestCompression ?? false,
      chestCompressionDuration: _ccDurationCtrl.text.trim(),
      epinephrine             : _epinephrine ?? false,
      epinephrineDoses        : _epiDoseCtrl.text.trim(),
      fluidBolus              : _fluidBolus ?? false,
      placentalTransfusion    : _placentalTransfusion ?? false,
      placentalMethod         : _placentalMethod ?? "",
      cordClampedAt           : _cordClampedAtDisplay,
      cordClampTime           : _cordClampTimeCtrl.text.trim(),
      timeToRespiration       : _timeToRespCtrl.text.trim(),
      timeToSpo2Above80       : _timeToSpo2Ctrl.text.trim(),
      spo2At5Min              : _spo2At5Ctrl.text.trim(),
      fio2Exit                : _fio2ExitCtrl.text.trim(),
      spo2Exit                : _spo2ExitCtrl.text.trim(),
      totalTime               : _totalTimeCtrl.text.trim(),
      ph                      : _phCtrl.text.trim(),
      be                      : _beCtrl.text.trim(),
      pco2                    : _pco2Ctrl.text.trim(),
      cordBloodDone           : _cordBloodDone ?? false,
      resusFailure            : _resusFailure ?? false,
      exitReason              : _exitReason == "Other"
          ? _exitOtherCtrl.text.trim() : _exitReason ?? "",
      timelineChecks          : timelineForModel,
      apgarScores             : _apgarCtrls.map(
          (key, ctrl) => MapEntry(key, ctrl.text.trim())),
    );

    try {
      // Legacy local cache
      await _api.saveFormC(formC);
      // Backend save — merged Form B + C payload via shared model
      try {
        await FormsApiService.instance
            .saveBirthResuscitation(data.toJson());
      } catch (e) {
        if (!mounted) return;
        _showMsg("Save failed — check connection and try again. ($e)");
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Form C saved successfully"),
        backgroundColor: AppTheme.of(context).success,
      ));
      // Return to dashboard (pop Form C; Form B also pops when result == true).
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showMsg("Failed to save: $e");
    }
  }

  /// Parses "HH:MM:SS" back to total seconds (int) — used for the numeric
  /// backend keys `time_to_respiration`, `time_to_spo2_80`.
  int? _hmsToSeconds(String s) {
    if (s.trim().isEmpty) return null;
    final p = s.split(":");
    if (p.length != 3) return null;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final sec = int.tryParse(p[2]) ?? 0;
    return h * 3600 + m * 60 + sec;
  }

  /// Elapsed cord-clamp seconds (0–300), matching web `cord_clamp_time`.
  int? _elapsedCordClampSeconds() {
    final t = _cordClampTimeCtrl.text.trim();
    final m = RegExp(r'^(\d+)\s*sec', caseSensitive: false).firstMatch(t);
    if (m != null) return int.tryParse(m.group(1)!);
    if (_cordClampedAtTotalSeconds == null) return null;
    final birthTimeStr = widget.formB?.timeOfBirth ?? "";
    if (birthTimeStr.isEmpty) return null;
    final parts = birthTimeStr.split(":");
    if (parts.length < 2) return null;
    final birthSec = (int.tryParse(parts[0]) ?? 0) * 3600
        + (int.tryParse(parts[1]) ?? 0) * 60;
    final diff = _cordClampedAtTotalSeconds! - birthSec;
    return diff < 0 ? 0 : diff;
  }

  /// Web field 57 stores minutes (0–999), not HMS seconds.
  int? _totalTimeMinutes() {
    final raw = _totalTimeCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d{1,3}$').hasMatch(raw)) return int.tryParse(raw);
    final secs = _hmsToSeconds(raw);
    if (secs == null) return null;
    return (secs / 60).round();
  }

  void _showMsg(String msg) {
    final c = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior       : SnackBarBehavior.floating,
      backgroundColor: c.surface,
      margin         : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.danger.withOpacity(0.4))),
      content: Row(children: [
        Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg,
            style: TextStyle(color: c.textPrimary, fontSize: 13))),
      ]),
      duration: const Duration(seconds: 3),
    ));
  }

  // ============================================================
  // WIDGET HELPERS
  // ============================================================

  InputDecoration _inputDec(String label, AppColors c) => InputDecoration(
    labelText     : label,
    labelStyle    : TextStyle(color: c.textSecondary, fontSize: 13),
    filled        : true,
    fillColor     : c.surfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.primary, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.danger)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.danger, width: 1.5)),
  );

  Widget _section(String title, IconData icon, Color accent,
      List<Widget> children, AppColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
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
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: accent, size: 16),
            ),
            const SizedBox(width: 10),
            Container(width: 3, height: 16,
                decoration: BoxDecoration(
                    color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: c.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: .4))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ]),
    );
  }

  Widget _yesNo(String title, bool? value, void Function(bool) onChanged,
      AppColors c, {Color? trueColor, Color? falseColor}) {
    final tc         = trueColor  ?? c.success;
    final fc         = falseColor ?? c.danger;
    final showError  = _submitted && value == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: c.textSecondary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        _chip("Yes", value == true,  tc, c, () => setState(() => onChanged(true))),
        const SizedBox(width: 10),
        _chip("No",  value == false, fc, c, () => setState(() => onChanged(false))),
      ]),
      if (showError)
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 16),
    ]);
  }

  Widget _chip(String label, bool selected, Color color,
      AppColors c, VoidCallback onTap) {
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
        child: Text(label, style: TextStyle(
            color: selected ? color : c.textSecondary,
            fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }

  Widget _pillRadio(String title, List<String> options, String? value,
      void Function(String) onChanged, AppColors c,
      {bool showError = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: c.textSecondary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: options.map((opt) {
        final sel = value == opt;
        return GestureDetector(
          onTap: () => setState(() => onChanged(opt)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? c.primary : c.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? c.primary : c.border, width: 1.5),
              boxShadow: sel ? [BoxShadow(color: c.primary.withOpacity(0.2),
                  blurRadius: 6, offset: const Offset(0, 2))] : [],
            ),
            child: Text(opt, style: TextStyle(
                color: sel ? Colors.white : c.textSecondary,
                fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        );
      }).toList()),
      if (showError)
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 14),
    ]);
  }

  // ── Single unified cord clamp tile ────────────────────────────────────────
  Widget _cordClampTile(AppColors c) {
    final filled    = _cordClampedAtDisplay.isNotEmpty;
    final showError = _submitted && !filled;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Cord clamped at (HH:MM:SS) *",
          style: TextStyle(color: c.textSecondary,
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () async {
          Duration? existing;
          if (filled) {
            final parts = _cordClampedAtDisplay.split(":");
            if (parts.length == 3) {
              existing = Duration(
                hours  : int.tryParse(parts[0]) ?? 0,
                minutes: int.tryParse(parts[1]) ?? 0,
                seconds: int.tryParse(parts[2]) ?? 0,
              );
            }
          }
          final dur = await _pickDuration(context, initial: existing);
          if (dur != null) {
            setState(() {
              _cordClampedAtTotalSeconds = dur.inSeconds;
              _cordClampedAtDisplay      = _fmtDuration(dur);
              _recalcCordClampTime();
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showError ? c.danger
                  : filled   ? c.success.withOpacity(0.5)
                             : c.border,
              width: 1.5,
            ),
          ),
          child: Row(children: [
            Icon(Icons.timer_outlined,
                color: filled ? c.success : c.textTertiary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                filled ? _cordClampedAtDisplay : "43. Cord clamped at (HH:MM:SS)",
                style: TextStyle(
                    color: filled ? c.textPrimary : c.textTertiary,
                    fontSize: 13,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
            if (filled) ...[
              GestureDetector(
                onTap: () => setState(() {
                  _cordClampedAtDisplay      = "";
                  _cordClampedAtTotalSeconds = null;
                  _cordClampTimeCtrl.clear();
                }),
                child: Icon(Icons.clear_rounded,
                    color: c.textTertiary, size: 16),
              ),
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, color: c.success, size: 16),
            ],
          ]),
        ),
      ),
      if (showError)
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 14),
    ]);
  }

  // ── Duration tile (for controllers) ──────────────────────────────────────
  Widget _durationTile({
    required String label,
    required TextEditingController ctrl,
    required AppColors c,
    required Future<Duration?> Function() onPick,
    bool isRequired = false,
  }) {
    final filled    = ctrl.text.isNotEmpty;
    final showError = _submitted && isRequired && !filled;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: c.textSecondary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () async {
          Duration? existing;
          if (filled) {
            final parts = ctrl.text.split(":");
            if (parts.length == 3) {
              existing = Duration(
                hours  : int.tryParse(parts[0]) ?? 0,
                minutes: int.tryParse(parts[1]) ?? 0,
                seconds: int.tryParse(parts[2]) ?? 0,
              );
            }
          }
          final dur = await onPick();
          if (dur != null) setState(() => ctrl.text = _fmtDuration(dur));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: showError ? c.danger
                  : filled   ? c.success.withOpacity(0.5)
                             : c.border,
              width: 1.5,
            ),
          ),
          child: Row(children: [
            Icon(Icons.timer_outlined,
                color: filled ? c.success : c.textTertiary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                filled ? ctrl.text : "Tap to select (HH:MM:SS)",
                style: TextStyle(
                    color: filled ? c.textPrimary : c.textTertiary,
                    fontSize: 13,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
            if (filled) ...[
              GestureDetector(
                onTap: () => setState(() => ctrl.clear()),
                child: Icon(Icons.clear_rounded,
                    color: c.textTertiary, size: 16),
              ),
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, color: c.success, size: 16),
            ],
          ]),
        ),
      ),
      if (showError)
        Padding(padding: const EdgeInsets.only(top: 4),
            child: Text("Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 14),
    ]);
  }

  Widget _autoField(String label, TextEditingController ctrl, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: c.textSecondary,
            fontSize: 13, fontWeight: FontWeight.w600))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: c.successSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.success.withOpacity(0.3))),
          child: Text("Auto-calculated", style: TextStyle(
              color: c.success, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: c.successSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.success.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(Icons.calculate_outlined, color: c.success, size: 16),
          const SizedBox(width: 10),
          Text(ctrl.text.isEmpty ? "—" : ctrl.text,
              style: TextStyle(
                  color: ctrl.text.isEmpty ? c.textTertiary : c.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 14),
    ]);
  }

  Widget _textField(String label, TextEditingController ctrl, AppColors c,
      {bool required = true,
       TextInputType keyboardType = TextInputType.number}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller  : ctrl,
        keyboardType: keyboardType,
        style       : TextStyle(color: c.textPrimary),
        decoration  : _inputDec(label, c),
        validator   : required
            ? (v) => (v == null || v.trim().isEmpty) ? "Required" : null
            : null,
      ),
    );
  }

  Widget _peepToggle(AppColors c) {
    // ignore: dead_code
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("PEEP valve (SIB)", style: TextStyle(color: c.textSecondary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _chip("With PEEP",    _sibPeep == true,  c.success, c,
            () => setState(() => _sibPeep = true))),
        const SizedBox(width: 10),
        Expanded(child: _chip("Without PEEP", _sibPeep == false, c.warning, c,
            () => setState(() => _sibPeep = false))),
      ]),
      const SizedBox(height: 14),
    ]);
  }
  // ignore: unused_element

  // ── Timeline table ────────────────────────────────────────────────────────
  static const double _colW = 82.0;

  Widget _timelineTable(AppColors c) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: 140),
          ..._timelineMins.map((m) => SizedBox(
            width: _colW,
            child: Text("$m min", textAlign: TextAlign.center,
                style: TextStyle(color: c.textTertiary,
                    fontWeight: FontWeight.w700, fontSize: 11)),
          )),
        ]),
        const SizedBox(height: 6),
        ..._timelineRows.map((rowName) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.borderLight),
          ),
          child: Row(children: [
            SizedBox(width: 140,
                child: Text(rowName, style: TextStyle(
                    color: c.textSecondary, fontSize: 11,
                    fontWeight: FontWeight.w500))),
            ..._timelineMins.map((min) {
              final cur = _timeline[rowName]![min];
              return SizedBox(width: _colW,
                  child: _ynrCell(rowName, min, cur, c));
            }),
          ]),
        )),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: c.warningSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.warning.withOpacity(0.3)),
          ),
          child: Row(children: [
            SizedBox(width: 140,
                child: Text("Apgar score", style: TextStyle(
                    color: c.warning, fontWeight: FontWeight.w700,
                    fontSize: 11))),
            ..._timelineMins.map((m) => SizedBox(
              width: _colW,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextFormField(
                  controller  : _apgarCtrls[m],
                  textAlign   : TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense    : true,
                    filled     : true,
                    fillColor  : c.surfaceAlt,
                    hintText   : "—",
                    hintStyle  : TextStyle(color: c.textTertiary, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.warning, width: 1.5)),
                  ),
                ),
              ),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _ynrCell(String row, int min, String? cur, AppColors c) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _miniChip("Y",  cur == "Y",  c.success, c,
          () => setState(() => _timeline[row]![min] = cur == "Y"  ? null : "Y")),
      const SizedBox(width: 2),
      _miniChip("N",  cur == "N",  c.danger,  c,
          () => setState(() => _timeline[row]![min] = cur == "N"  ? null : "N")),
      const SizedBox(width: 2),
      _miniChip("NR", cur == "NR", c.warning, c,
          () => setState(() => _timeline[row]![min] = cur == "NR" ? null : "NR")),
    ]);
  }

  Widget _miniChip(String label, bool selected, Color color,
      AppColors c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: selected ? color : c.border,
              width: selected ? 1.3 : 1),
        ),
        child: Text(label, style: TextStyle(
            color: selected ? color : c.textTertiary,
            fontSize: 9, fontWeight: FontWeight.w800)),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor    : c.bg,
      appBar             : _buildAppBar(c),
      bottomNavigationBar: widget.viewOnly ? null : _buildBottomBar(c),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [c.bgGradTop, c.bg], stops: const [0.0, 0.35],
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
                        child: Text("View only — previously filled Form C",
                            style: TextStyle(
                                color: c.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ),
                    ]),
                  ),
                ],
                _buildResuscitationSection(c),
                _buildTimelineSection(c),
                _buildCordBloodSection(c),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(AppColors c) {
    return AppBar(
      backgroundColor : c.surface,
      elevation       : 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight   : 66,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.borderLight),
      ),
      title: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Form C: Resuscitation Details",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: c.textPrimary, letterSpacing: .3)),
        const SizedBox(height: 2),
        Text("Complete after resuscitation",
            style: TextStyle(fontSize: 11,
                color: c.danger.withOpacity(0.8),
                fontWeight: FontWeight.w500)),
      ]),
      actions: [
        const Padding(padding: EdgeInsets.only(right: 8),
            child: Center(child: ThemeToggle())),
      ],
    );
  }

  Widget _buildBottomBar(AppColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderLight)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon : const Icon(Icons.save_outlined, size: 18, color: Colors.white),
          label: const Text("Save Form C",
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 14)),
          onPressed: _saveFormC,
          style: ElevatedButton.styleFrom(
            backgroundColor: c.success,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  // ── Section 1 ─────────────────────────────────────────────────────────────
  Widget _buildResuscitationSection(AppColors c) {
    return _section(
      "RESUSCITATION DETAILS",
      Icons.monitor_heart_rounded,
      c.danger,
      [
        // Web B4 starts at 29. Device used (Q23 already answered on Form B).
        _pillRadio("29. Device used",
              ["T-piece", "Self-inflating bag", "Both"],
              _device, (v) => setState(() => _device = v), c,
              showError: _submitted && _device == null),

          // 29a. SIB — With PEEP valve? + value  (visible when device includes SIB)
          if (_device == "Self-inflating bag" || _device == "Both") ...[
            _pillRadio("29a. SIB — With PEEP valve? *",
                ["Yes", "No"],
                _sibPeepWith,
                (v) => setState(() {
                  _sibPeepWith = v;
                  _sibPeep = v == "Yes";
                  if (v == "No") _sibPeepValueCtrl.clear();
                }), c,
                showError: _submitted && _sibPeepWith == null),
            if (_sibPeepWith == "Yes")
              _textField("29a. PEEP value (cmH₂O) *",
                  _sibPeepValueCtrl, c,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],

          // 29b. T-piece PIP / PEEP / Flow  (visible when device includes T-piece)
          if (_device == "T-piece" || _device == "Both") ...[
            _textField("29b. T-piece PIP (cmH₂O) *",
                _tpiecePipCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _textField("29b. T-piece PEEP (cmH₂O) *",
                _tpiecePeepCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _textField("29b. T-piece Flow (L/min) *",
                _tpieceFlowCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],

          _pillRadio("30. Interface",
              ["Mask", "LMA", "Mask + LMA", "Endotracheal tube"],
              _interface, (v) => setState(() => _interface = v), c,
              showError: _submitted && _interface == null),
          _textField("31. Duration of PPV (sec)",
              _ventDurationCtrl, c),

        _yesNo("32. Endotracheal intubation",
            _intubation, (v) => _intubation = v, c),
        _yesNo("33. Chest compressions",
            _chestCompression, (v) => _chestCompression = v, c),
        if (_chestCompression == true)
          _textField("34. Duration of CC (sec)", _ccDurationCtrl, c),

        _yesNo("35. Epinephrine", _epinephrine, (v) => _epinephrine = v, c),
        if (_epinephrine == true) ...[
          _pillRadio("36. Dilution",
              ["1:10000", "1:1000"],
              _adrenalineDilution,
              (v) => setState(() => _adrenalineDilution = v), c,
              showError: _submitted && _adrenalineDilution == null),
          _pillRadio("37. Route",
              ["Umbilical vein", "Peripheral vein", "Intratracheal"],
              _adrenalineRoute,
              (v) => setState(() => _adrenalineRoute = v), c,
              showError: _submitted && _adrenalineRoute == null),
        ],

        _yesNo("38. Fluid bolus", _fluidBolus, (v) => _fluidBolus = v, c),
        if (_fluidBolus == true) ...[
          _textField("39. Doses", _fluidBolusDosesCtrl, c),
          _textField("40. Cumulative (ml/mg)",
              _fluidBolusCumCtrl, c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ],

        _yesNo("41. Placental transfusion",
            _placentalTransfusion, (v) => _placentalTransfusion = v, c),
        if (_placentalTransfusion == true) ...[
          _pillRadio("42. Method",
              ["Deferred clamping", "Intact cord milking"],
              _placentalMethod,
              (v) => setState(() => _placentalMethod = v), c,
              showError: _submitted && _placentalMethod == null),
          // 43–44 only when placental transfusion = Yes (matches web)
          _cordClampTile(c),
          _autoField("44. Cord clamping time from birth (sec)",
              _cordClampTimeCtrl, c),
        ],

        _durationTile(
          label   : "45. Time to spontaneous respiratory efforts (HH:MM:SS)",
          ctrl    : _timeToRespCtrl,
          c       : c,
          onPick  : () => _pickDuration(context),
        ),
        _textField("46. SpO₂ at 5 min (%)", _spo2At5Ctrl, c),
        _durationTile(
          label   : "47. Time to SpO₂ > 80% (MM:SS)",
          ctrl    : _timeToSpo2Ctrl,
          c       : c,
          onPick  : () => _pickDuration(context),
        ),
      ],
      c,
    );
  }

  // ── Section 2 ─────────────────────────────────────────────────────────────
  Widget _buildTimelineSection(AppColors c) {
    return _section(
      "B5 · INTERVENTION (48–50)",
      Icons.timeline_rounded,
      c.warning,
      [_timelineTable(c)],
      c,
    );
  }

  // ── Section 3 ─────────────────────────────────────────────────────────────
  Widget _buildCordBloodSection(AppColors c) {
    return _section(
      "CORD BLOOD & RESUSCITATION EXIT",
      Icons.science_rounded,
      c.success,
      [
        _yesNo("51. Cord blood analysis",
            _cordBloodDone, (v) {
              _cordBloodDone = v;
              _cordBloodWithin1hr = null;
              _cordBloodSource = null;
              _phCtrl.clear();
              _beCtrl.clear();
              _pco2Ctrl.clear();
            }, c),
        if (_cordBloodDone == false) ...[
          _pillRadio("52. If no, within 1 hr of birth sample",
              ["Yes", "No"],
              _cordBloodWithin1hr == null
                  ? null
                  : (_cordBloodWithin1hr! ? "Yes" : "No"),
              (v) => setState(() {
                _cordBloodWithin1hr = v == "Yes";
                if (v != "Yes") {
                  _cordBloodSource = null;
                  _phCtrl.clear(); _beCtrl.clear(); _pco2Ctrl.clear();
                }
              }), c,
              showError: _submitted && _cordBloodWithin1hr == null),
        ],
        if (_cordBloodDone == false && _cordBloodWithin1hr == true)
          _pillRadio("53. Source",
              ["Capillary", "Venous"],
              _cordBloodSource,
              (v) => setState(() => _cordBloodSource = v), c,
              showError: _submitted && _cordBloodSource == null),
        if (_cordBloodDone == true ||
            (_cordBloodDone == false && _cordBloodWithin1hr == true)) ...[
          _textField("54. pH", _phCtrl, c,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true)),
          _textField("54. SBE", _beCtrl, c,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true)),
          _textField("54. pCO₂", _pco2Ctrl, c,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true)),
        ],

        _yesNo("55. Resuscitation failure",
            _resusFailure, (v) => _resusFailure = v, c),

        _textField("56. SpO₂ at exit from trial gas (%)", _spo2ExitCtrl, c),

        _textField("57. Total time (min)", _totalTimeCtrl, c,
            keyboardType: TextInputType.number),

        _pillRadio("58. Reason for resuscitation exit",
            [
              "Responded to resuscitation",
              "Required override to 100% O2 or CC",
              "Other",
            ],
            _exitReason, (v) {
              _exitReason = v;
              if (v != "Other") _exitOtherCtrl.clear();
            }, c,
            showError: _submitted && _exitReason == null),

        if (_exitReason == "Other")
          _textField("Specify", _exitOtherCtrl, c,
              keyboardType: TextInputType.text),

        // 64. PORTAL Blender Status
        _yesNo("59. Did the PORTAL blender stop suddenly during use?",
            _blenderStopped, (v) {
              _blenderStopped = v;
              if (v == false) _blenderStopDescCtrl.clear();
            }, c),
        if (_blenderStopped == true)
          _textField("If yes, describe", _blenderStopDescCtrl, c,
              keyboardType: TextInputType.multiline),
      ],
      c,
    );
  }
}