import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../models/form_c.dart';
import '../models/birth_resuscitation.dart';
import '../models/form_b.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/required_asterisk.dart';

String? blenderLetterFromEnrollmentId(String? enrollmentId) {
  final parts = (enrollmentId ?? "").trim().toUpperCase().split("-");
  if (parts.length >= 2 && const ["A", "B", "C", "D"].contains(parts[1])) {
    return parts[1];
  }
  return null;
}

class FormCResuscitationDetails extends StatefulWidget {
  final String screeningId;
  final FormB?  formB;
  final String  gestation;
  final String  motherName;
  final String  babyUid;
  // Shared birth-resuscitation payload, already populated in Form B1 with
  // B1–B3 fields. Form B2 fills B4–B6 into the same object and re-saves so
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
  final _cordClampTimeCtrl = TextEditingController();
  final _timeToRespCtrl    = TextEditingController();
  final _timeToSpo2Ctrl    = TextEditingController();
  final _spo2At5Ctrl       = TextEditingController();
  final _spo2ExitCtrl      = TextEditingController();
  final _totalTimeCtrl     = TextEditingController();
  final _exitOtherCtrl     = TextEditingController();
  final _phCtrl            = TextEditingController();
  final _beCtrl            = TextEditingController();
  final _pco2Ctrl          = TextEditingController();
  final _sibPeepValueCtrl   = TextEditingController();   // 29a. cmH₂O
  final _tpiecePipCtrl      = TextEditingController();   // 29b. PIP
  final _tpiecePeepCtrl     = TextEditingController();   // 29b. PEEP
  final _tpieceFlowCtrl     = TextEditingController();   // 29b. Flow
  final _fluidBolusDosesCtrl= TextEditingController();   // 39.
  final _fluidBolusCumCtrl  = TextEditingController();   // 40.
  final _blenderStopDescCtrl  = TextEditingController(); // 59.

  // Cord clamp — managed as plain string, NOT a TextEditingController
  String _cordClampedAtDisplay      = "";
  int?   _cordClampedAtTotalSeconds;
  /// 9. Time of Birth from Form B1 / shared birth record (HH:MM[:SS]).
  String _timeOfBirth = "";

  // ── State ─────────────────────────────────────────────────────────────────
  // Form B2 is only reached when Form B1 Q23 = Required → PPV path.
  String? _device;
  bool?   _sibPeep;
  String? _sibPeepWith;         // 29a. Yes / No
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
  bool?   _cordBloodWithin1hr;  // 52.
  String? _cordBloodSource;     // 53.
  bool?   _resusFailure;
  String? _exitReason;
  bool?   _blenderStopped;      // 59.
  List<String> _blenderInterruptReasons = []; // 60.
  String? _blenderLetter;       // 61. A/B/C/D

  bool _submitted = false;

  // Live range errors for cord blood gases (match web BirthResuscitationForm).
  String? _phLiveError;
  String? _sbeLiveError;
  String? _pco2LiveError;

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
    _timeOfBirth = (widget.formB?.timeOfBirth ?? "").trim();
    if (_timeOfBirth.isEmpty) {
      _timeOfBirth = (widget.shared?.timeOfBirth ?? "").trim();
    }
    // Always merge: server/shared first, then local Form B2 draft overlays
    // so Save for Later never loses fields when reopening via Form B1 handoff.
    _hydrateAll();
    _ensureBirthTime();
  }

  Future<void> _hydrateAll() async {
    if (widget.shared != null) {
      _applyBirthData(widget.shared!);
    } else {
      await _hydrateFromServerOrSkip();
    }
    await _overlayLocalFormC();
  }

  Future<void> _hydrateFromServerOrSkip() async {
    final eid = _resolveFormCEnrollmentId();
    if (eid.isEmpty) return;
    try {
      final remote =
          await FormsApiService.instance.loadBirthResuscitation(eid);
      if (remote != null && mounted) {
        _applyBirthData(BirthResuscitationData.fromJson(remote));
      }
    } catch (_) {}
  }

  Future<void> _overlayLocalFormC() async {
    final existing = await _api.loadFormC(widget.screeningId);
    if (existing == null || !mounted) return;
    setState(() => _applyLocalFormC(existing, overlayOnly: true));
  }

  void _applyLocalFormC(FormC existing, {bool overlayOnly = false}) {
    void setText(TextEditingController c, String v) {
      if (!overlayOnly || v.trim().isNotEmpty) c.text = v;
    }

    if (!overlayOnly || existing.device.isNotEmpty) {
      _device = existing.device.isEmpty ? _device : existing.device;
    }
    if (!overlayOnly || existing.sibPeep != null) {
      _sibPeep = existing.sibPeep ?? _sibPeep;
    }
    if (!overlayOnly ||
        (existing.sibPeepWith != null && existing.sibPeepWith!.isNotEmpty)) {
      _sibPeepWith = existing.sibPeepWith ?? _sibPeepWith;
    } else if (!overlayOnly && existing.sibPeep != null) {
      _sibPeepWith = existing.sibPeep! ? "Yes" : "No";
    }
    setText(_sibPeepValueCtrl, existing.sibPeepCmh2o);
    setText(_tpiecePipCtrl, existing.tpiecePip);
    setText(_tpiecePeepCtrl, existing.tpiecePeep);
    setText(_tpieceFlowCtrl, existing.tpieceFlow);
    if (!overlayOnly || existing.interface.isNotEmpty) {
      _interface =
          existing.interface.isEmpty ? _interface : existing.interface;
    }
    setText(_ventDurationCtrl, existing.ventilationDuration);
    if (!overlayOnly || existing.intubation != null) {
      _intubation = existing.intubation ?? _intubation;
    }
    if (!overlayOnly || existing.chestCompression != null) {
      _chestCompression = existing.chestCompression ?? _chestCompression;
    }
    setText(_ccDurationCtrl, existing.chestCompressionDuration);
    if (!overlayOnly || existing.epinephrine != null) {
      _epinephrine = existing.epinephrine ?? _epinephrine;
    }
    if (!overlayOnly ||
        (existing.adrenalineDilution != null &&
            existing.adrenalineDilution!.isNotEmpty)) {
      _adrenalineDilution =
          existing.adrenalineDilution ?? _adrenalineDilution;
    }
    if (!overlayOnly ||
        (existing.adrenalineRoute != null &&
            existing.adrenalineRoute!.isNotEmpty)) {
      _adrenalineRoute = existing.adrenalineRoute ?? _adrenalineRoute;
    }
    if (!overlayOnly || existing.fluidBolus != null) {
      _fluidBolus = existing.fluidBolus ?? _fluidBolus;
    }
    setText(_fluidBolusDosesCtrl, existing.fluidBolusDoses);
    setText(_fluidBolusCumCtrl, existing.fluidBolusCumulative);
    if (!overlayOnly || existing.placentalTransfusion != null) {
      _placentalTransfusion =
          existing.placentalTransfusion ?? _placentalTransfusion;
    }
    if (!overlayOnly || existing.placentalMethod.isNotEmpty) {
      _placentalMethod = existing.placentalMethod.isEmpty
          ? _placentalMethod
          : existing.placentalMethod;
    }
    if (!overlayOnly || existing.cordClampedAt.isNotEmpty) {
      _cordClampedAtDisplay = existing.cordClampedAt.isEmpty
          ? _cordClampedAtDisplay
          : existing.cordClampedAt;
      _cordClampedAtTotalSeconds =
          _clockTimeToSeconds(_cordClampedAtDisplay);
    }
    setText(_cordClampTimeCtrl, existing.cordClampTime);
    if (_cordClampTimeCtrl.text.trim().isEmpty &&
        _cordClampedAtDisplay.isNotEmpty) {
      _recalcCordClampTime();
    }
    setText(_timeToRespCtrl, existing.timeToRespiration);
    setText(_timeToSpo2Ctrl, existing.timeToSpo2Above80);
    setText(_spo2At5Ctrl, existing.spo2At5Min);
    setText(_totalTimeCtrl, existing.totalTime);
    setText(_spo2ExitCtrl, existing.spo2Exit);
    setText(_phCtrl, existing.ph);
    setText(_beCtrl, existing.be);
    setText(_pco2Ctrl, existing.pco2);
    _phLiveError = _phLiveMessage(_phCtrl.text);
    _sbeLiveError = _sbeLiveMessage(_beCtrl.text);
    _pco2LiveError = _pco2LiveMessage(_pco2Ctrl.text);
    if (!overlayOnly || existing.cordBloodDone != null) {
      _cordBloodDone = existing.cordBloodDone ?? _cordBloodDone;
    }
    if (!overlayOnly || existing.cordBloodWithin1hr != null) {
      _cordBloodWithin1hr =
          existing.cordBloodWithin1hr ?? _cordBloodWithin1hr;
    }
    if (!overlayOnly ||
        (existing.cordBloodSource != null &&
            existing.cordBloodSource!.isNotEmpty)) {
      _cordBloodSource = existing.cordBloodSource ?? _cordBloodSource;
    }
    if (!overlayOnly || existing.resusFailure != null) {
      _resusFailure = existing.resusFailure ?? _resusFailure;
    }
    if (!overlayOnly || existing.exitReason.isNotEmpty) {
      final exit = existing.exitReason;
      const exitOpts = [
        "Responded to resuscitation",
        "Required override to 100% O2 or CC",
        "Other",
      ];
      if (exit.isEmpty) {
        if (!overlayOnly) _exitReason = null;
      } else if (exitOpts.contains(exit)) {
        _exitReason = exit;
      } else {
        _exitReason = "Other";
        _exitOtherCtrl.text = exit;
      }
    }
    if (!overlayOnly || existing.blenderStopped != null) {
      _blenderStopped = existing.blenderStopped ?? _blenderStopped;
    }
    if (!overlayOnly || existing.blenderInterruptReasons.isNotEmpty) {
      _blenderInterruptReasons = List<String>.from(existing.blenderInterruptReasons);
      if (_blenderInterruptReasons.isEmpty &&
          _blenderStopped == true &&
          existing.blenderStoppedDescription.trim().isNotEmpty) {
        _blenderInterruptReasons = [kBlenderAbruptReason];
      }
    }
    setText(_blenderStopDescCtrl, existing.blenderStoppedDescription);
    if (!overlayOnly || existing.blenderLetter.isNotEmpty) {
      final letter = existing.blenderLetter.trim().toUpperCase();
      if (["A", "B", "C", "D"].contains(letter)) {
        _blenderLetter = letter;
      }
    }
    _syncBlenderFromEnrollment();

    for (final row in _timelineRows) {
      final saved = existing.timelineChecks[row];
      if (saved == null) continue;
      for (final m in _timelineMins) {
        if (!saved.containsKey(m)) continue;
        final v = saved[m]!.trim();
        if (v.isEmpty) continue;
        _timeline[row]![m] = v;
      }
    }
    for (final e in existing.apgarScores.entries) {
      if (!overlayOnly || e.value.trim().isNotEmpty) {
        _apgarCtrls[e.key]?.text = e.value;
      }
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
      if ((d.timeOfBirth ?? "").trim().isNotEmpty) {
        _timeOfBirth = d.timeOfBirth!.trim();
      }
      _cordClampedAtDisplay = (d.cordClampTimestamp ?? "").trim();
      _cordClampedAtTotalSeconds = _clockTimeToSeconds(_cordClampedAtDisplay);
      if (d.cordClampTime != null) {
        _cordClampTimeCtrl.text = "${d.cordClampTime} sec";
      } else if (_cordClampedAtDisplay.isNotEmpty) {
        _recalcCordClampTime();
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
      _phLiveError = _phLiveMessage(_phCtrl.text);
      _sbeLiveError = _sbeLiveMessage(_beCtrl.text);
      _pco2LiveError = _pco2LiveMessage(_pco2Ctrl.text);
      _resusFailure = d.resusFailure;
      if (d.spo2ExitTrialGas != null) {
        _spo2ExitCtrl.text = d.spo2ExitTrialGas.toString();
      }
      if (d.totalResusTime != null && d.totalResusTime!.trim().isNotEmpty) {
        _totalTimeCtrl.text = normalizeTotalResusTimeMmSs(d.totalResusTime) ?? '';
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
      _blenderInterruptReasons = List<String>.from(d.blenderInterruptReasons);
      if (_blenderInterruptReasons.isEmpty &&
          d.blenderStopped == true &&
          (d.blenderStoppedDescription ?? "").trim().isNotEmpty) {
        _blenderInterruptReasons = [kBlenderAbruptReason];
      }
      if (d.blenderStoppedDescription != null) {
        _blenderStopDescCtrl.text = d.blenderStoppedDescription!;
      }
      final letter = (d.blenderLetter ?? "").trim().toUpperCase();
      _blenderLetter = ["A", "B", "C", "D"].contains(letter) ? letter : null;
      _syncBlenderFromEnrollment();
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

  bool _isFormCEmpty() {
    final hasTimeline = _timeline.values.any(
        (m) => m.values.any((v) => (v ?? "").toString().trim().isNotEmpty));
    final hasApgar =
        _apgarCtrls.values.any((c) => c.text.trim().isNotEmpty);
    return _device == null &&
        _interface == null &&
        _ventDurationCtrl.text.trim().isEmpty &&
        _intubation == null &&
        _chestCompression == null &&
        _epinephrine == null &&
        _fluidBolus == null &&
        _placentalTransfusion == null &&
        _cordClampedAtDisplay.isEmpty &&
        _timeToRespCtrl.text.trim().isEmpty &&
        _spo2At5Ctrl.text.trim().isEmpty &&
        _phCtrl.text.trim().isEmpty &&
        _cordBloodDone == null &&
        _resusFailure == null &&
        _exitReason == null &&
        _blenderStopped == null &&
        _blenderInterruptReasons.isEmpty &&
        _blenderLetter == null &&
        !hasTimeline &&
        !hasApgar;
  }

  @override
  void dispose() {
    if (!widget.viewOnly && !_isFormCEmpty()) {
      _api.saveFormC(_snapshotFormC());
    }
    for (final c in [
      _ventDurationCtrl, _ccDurationCtrl,
      _cordClampTimeCtrl, _timeToRespCtrl, _timeToSpo2Ctrl,
      _spo2At5Ctrl, _spo2ExitCtrl,
      _totalTimeCtrl, _exitOtherCtrl, _phCtrl, _beCtrl, _pco2Ctrl,
      _sibPeepValueCtrl, _tpiecePipCtrl, _tpiecePeepCtrl, _tpieceFlowCtrl,
      _fluidBolusDosesCtrl, _fluidBolusCumCtrl,
      _blenderStopDescCtrl,
    ]) { c.dispose(); }
    for (final c in _apgarCtrls.values) c.dispose();
    super.dispose();
  }

  // ── Cord clamp auto-calc (same formula as web Form B1 fields 43 → 44) ─────
  /// Clock HH:MM[:SS] → seconds since midnight.
  int? _clockTimeToSeconds(String? value) {
    if (value == null) return null;
    final s = value.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'(?:T|\s|^)(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?')
        .firstMatch(s);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!) ?? 0;
    final min = int.tryParse(m.group(2)!) ?? 0;
    final sec = int.tryParse(m.group(3) ?? '0') ?? 0;
    if (h > 23 || min > 59 || sec > 59) return null;
    return h * 3600 + min * 60 + sec;
  }

  Future<void> _ensureBirthTime() async {
    if (_timeOfBirth.trim().isNotEmpty) return;
    try {
      final local = await _api.loadFormB(widget.screeningId);
      final t = (local?.timeOfBirth ?? "").trim();
      if (t.isNotEmpty && mounted) {
        setState(() {
          _timeOfBirth = t;
          if (_cordClampedAtDisplay.isNotEmpty) _recalcCordClampTime();
        });
        return;
      }
    } catch (_) {}
    final eid = widget.formB?.enrollmentId.trim() ??
        widget.shared?.enrollmentId?.trim() ??
        '';
    if (eid.isEmpty) return;
    try {
      final remote = await FormsApiService.instance.loadBirthResuscitation(eid);
      final t = (remote?['time_of_birth'] ?? "").toString().trim();
      if (t.isNotEmpty && mounted) {
        setState(() {
          _timeOfBirth = t;
          if (_cordClampedAtDisplay.isNotEmpty) _recalcCordClampTime();
        });
      }
    } catch (_) {}
  }

  void _recalcCordClampTime() {
    final clampSec = _cordClampedAtTotalSeconds ??
        _clockTimeToSeconds(_cordClampedAtDisplay);
    if (clampSec == null) return;
    _cordClampedAtTotalSeconds = clampSec;

    final birthSec = _clockTimeToSeconds(_timeOfBirth);
    if (birthSec == null) {
      _cordClampTimeCtrl.text = _timeOfBirth.trim().isEmpty
          ? "Enter Time of Birth in Form B1 first"
          : "—";
      return;
    }
    var elapsed = clampSec - birthSec;
    if (elapsed < 0) elapsed += 86400; // wrap past midnight (same as web)
    if (elapsed > 300) {
      _cordClampTimeCtrl.text = "Must be ≤ 300 sec";
      return;
    }
    _cordClampTimeCtrl.text = "$elapsed sec";
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

  // ── Draft / Save ──────────────────────────────────────────────────────────
  FormC _snapshotFormC() {
    // Preserve Y / N / NR (and skip unanswered cells).
    final timelineForModel = <String, Map<int, String>>{};
    _timeline.forEach((row, minMap) {
      final cells = <int, String>{};
      minMap.forEach((min, val) {
        final s = (val ?? "").trim();
        if (s.isNotEmpty) cells[min] = s;
      });
      if (cells.isNotEmpty) timelineForModel[row] = cells;
    });
    return FormC(
      screeningId: widget.screeningId,
      ventilation: true,
      device: _device ?? "",
      sibPeep: _sibPeep,
      sibPeepWith: _sibPeepWith,
      sibPeepCmh2o: _sibPeepValueCtrl.text.trim(),
      tpiecePip: _tpiecePipCtrl.text.trim(),
      tpiecePeep: _tpiecePeepCtrl.text.trim(),
      tpieceFlow: _tpieceFlowCtrl.text.trim(),
      interface: _interface ?? "",
      ventilationDuration: _ventDurationCtrl.text.trim(),
      intubation: _intubation,
      chestCompression: _chestCompression,
      chestCompressionDuration: _ccDurationCtrl.text.trim(),
      epinephrine: _epinephrine,
      epinephrineDoses: "",
      adrenalineDilution: _adrenalineDilution,
      adrenalineRoute: _adrenalineRoute,
      fluidBolus: _fluidBolus,
      fluidBolusDoses: _fluidBolusDosesCtrl.text.trim(),
      fluidBolusCumulative: _fluidBolusCumCtrl.text.trim(),
      placentalTransfusion: _placentalTransfusion,
      placentalMethod: _placentalTransfusion == true ? (_placentalMethod ?? "") : "",
      cordClampedAt: _cordClampedAtDisplay,
      cordClampTime: _cordClampTimeCtrl.text.trim(),
      timeToRespiration: _timeToRespCtrl.text.trim(),
      timeToSpo2Above80: _timeToSpo2Ctrl.text.trim(),
      spo2At5Min: _spo2At5Ctrl.text.trim(),
      fio2Exit: "",
      spo2Exit: _spo2ExitCtrl.text.trim(),
      totalTime: _totalTimeCtrl.text.trim(),
      ph: _phCtrl.text.trim(),
      be: _beCtrl.text.trim(),
      pco2: _pco2Ctrl.text.trim(),
      cordBloodDone: _cordBloodDone,
      cordBloodWithin1hr: _cordBloodWithin1hr,
      cordBloodSource: _cordBloodSource,
      resusFailure: _resusFailure,
      exitReason: _exitReason == "Other"
          ? _exitOtherCtrl.text.trim()
          : _exitReason ?? "",
      blenderStopped: _blenderStopped,
      blenderInterruptReasons: List<String>.from(_blenderInterruptReasons),
      blenderStoppedDescription: _blenderStopDescCtrl.text.trim(),
      blenderLetter: blenderLetterFromEnrollmentId(_resolveFormCEnrollmentId()) ??
          _blenderLetter ??
          "",
      timelineChecks: timelineForModel,
      apgarScores: _apgarCtrls.map(
          (key, ctrl) => MapEntry(key, ctrl.text.trim())),
    );
  }

  String _resolveFormCEnrollmentId() {
    final fromB = widget.formB?.enrollmentId.trim() ?? '';
    if (fromB.isNotEmpty) return fromB;
    final fromShared = widget.shared?.enrollmentId?.trim() ?? '';
    if (fromShared.isNotEmpty) return fromShared;
    return '';
  }

  void _syncBlenderFromEnrollment() {
    final letter = blenderLetterFromEnrollmentId(_resolveFormCEnrollmentId());
    if (letter != null) _blenderLetter = letter;
  }

  Future<void> _saveDraft({bool popAfter = true}) async {
    if (_isFormCEmpty()) {
      if (popAfter && mounted) Navigator.of(context).pop(false);
      return;
    }
    final formC = _snapshotFormC();
    await _api.saveFormC(formC);

    final eid = _resolveFormCEnrollmentId();
    if (eid.isNotEmpty) {
      try {
        final data = widget.shared ??
            BirthResuscitationData()
          ..screeningId = widget.screeningId
          ..enrollmentId = eid;
        data.screeningId = widget.screeningId;
        data.enrollmentId = eid;
        data.devicePpv = _device;
        data.sibPeepWith = _sibPeepWith;
        data.sibPeepCmh2o = double.tryParse(_sibPeepValueCtrl.text.trim());
        data.tpiecePip = double.tryParse(_tpiecePipCtrl.text.trim());
        data.tpiecePeep = double.tryParse(_tpiecePeepCtrl.text.trim());
        data.tpieceFlow = double.tryParse(_tpieceFlowCtrl.text.trim());
        data.interfaceUsed = _interface;
        data.ppvDuration = int.tryParse(_ventDurationCtrl.text.trim());
        data.intubation = _intubation;
        data.chestCompression = _chestCompression;
        data.ccDuration = int.tryParse(_ccDurationCtrl.text.trim());
        data.adrenaline = _epinephrine;
        data.adrenalineDilution =
            _epinephrine == true ? _adrenalineDilution : null;
        data.adrenalineRoute =
            _epinephrine == true ? _adrenalineRoute : null;
        data.fluidBolus = _fluidBolus;
        data.fluidBolusDoses =
            int.tryParse(_fluidBolusDosesCtrl.text.trim());
        data.fluidBolusCumulative =
            double.tryParse(_fluidBolusCumCtrl.text.trim());
        data.placentalTransfusion = _placentalTransfusion;
        data.transfusionMethod =
            _placentalTransfusion == true ? _placentalMethod : null;
        data.cordClampTimestamp =
            _cordClampedAtDisplay.isNotEmpty ? _cordClampedAtDisplay : null;
        data.cordClampTime = _elapsedCordClampSeconds();
        data.timeToRespiration = _hmsToSeconds(_timeToRespCtrl.text);
        data.spo25min = int.tryParse(_spo2At5Ctrl.text.trim());
        data.timeToSpo280 = _hmsToSeconds(_timeToSpo2Ctrl.text);
        data.cordBloodDone = _cordBloodDone;
        data.cordBloodWithin1hr =
            _cordBloodDone == false ? _cordBloodWithin1hr : null;
        data.cordBloodSource =
            (_cordBloodDone == false && _cordBloodWithin1hr == true)
                ? _cordBloodSource
                : null;
        data.cordPh = double.tryParse(_phCtrl.text.trim());
        data.cordSbe = double.tryParse(_beCtrl.text.trim());
        data.cordPco2 = double.tryParse(_pco2Ctrl.text.trim());
        data.resusFailure = _resusFailure;
        data.spo2ExitTrialGas = double.tryParse(_spo2ExitCtrl.text.trim());
        data.totalResusTime = normalizeTotalResusTimeMmSs(_totalTimeCtrl.text);
        data.reasonExitTrialGas = _exitReason;
        data.reasonExitTrialGasOther =
            _exitReason == "Other" ? _exitOtherCtrl.text.trim() : null;
        data.blenderStopped = _blenderStopped;
        data.blenderInterruptReasons = _blenderStopped == true
            ? List<String>.from(_blenderInterruptReasons)
            : [];
        data.blenderStoppedDescription = _blenderStopped == true &&
                _blenderInterruptReasons.contains(kBlenderAbruptReason)
            ? _blenderStopDescCtrl.text.trim()
            : null;
        data.blenderLetter =
            blenderLetterFromEnrollmentId(eid) ?? _blenderLetter;
        final ynMap = <String, Map<String, String>>{};
        const rowKey = {"Oxygen": "oxygen", "CPAP": "cpap"};
        const ynOut = {
          "Y": "Yes",
          "N": "No",
          "NR": "NR",
          "Yes": "Yes",
          "No": "No"
        };
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
        await FormsApiService.instance
            .saveBirthResuscitation(data.toJson());
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Draft saved"),
      backgroundColor: AppTheme.of(context).success,
      behavior: SnackBarBehavior.floating,
    ));
    if (popAfter) Navigator.of(context).pop(true);
  }

  void _saveFormC() async {
    setState(() {
      _submitted = true;
      _phLiveError = _phLiveMessage(_phCtrl.text);
      _sbeLiveError = _sbeLiveMessage(_beCtrl.text);
      _pco2LiveError = _pco2LiveMessage(_pco2Ctrl.text);
      _syncBlenderFromEnrollment();
    });
    if (!_formKey.currentState!.validate()) return;
    if (_phLiveError != null ||
        _sbeLiveError != null ||
        _pco2LiveError != null) {
      _showMsg(_phLiveError ?? _sbeLiveError ?? _pco2LiveError!);
      return;
    }

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
      [_placentalTransfusion == true && _placentalMethod == null,
                                                                "Please select transfusion method (42.)"],
      [_cordClampedAtTotalSeconds == null,
                                                                "Please select cord clamped time (43.)"],
      [_cordBloodDone == null,                                  "Please select cord blood status (51.)"],
      [_cordBloodDone == false && _cordBloodWithin1hr == null,  "Please answer within 1hr of birth (52.)"],
      [_cordBloodDone == false && _cordBloodWithin1hr == true && _cordBloodSource == null,
                                                                "Please select cord blood source (53.)"],
      [_resusFailure == null,                                   "Please select resuscitation failure (55.)"],
      [_exitReason == null,                                     "Please select reason for exit (58.)"],
      [_blenderStopped == null,                                 "Please answer whether the PORTAL blender was interrupted before 30 minutes (59.)"],
      [_blenderStopped == true && _blenderInterruptReasons.isEmpty,
                                                                "Please select the reason the blender was interrupted (60.)"],
      [_blenderStopped == true &&
          _blenderInterruptReasons.contains(kBlenderAbruptReason) &&
          _blenderStopDescCtrl.text.trim().isEmpty,
                                                                "Please describe the abrupt blender stop (60.)"],
      [_blenderLetter == null,                                  "Blender Unit ID is taken from Enrollment ID — complete Form B1 first."],
      [_spontaneousExceedsApgar(),
        "Time to spontaneous respiratory efforts (45.) must be ≤ total time from APGAR timer (57.)"],
    ];

    for (final check in checks) {
      if (check[0] as bool) { _showMsg(check[1] as String); return; }
    }

    // Merge with existing backend / shared Form B1 record so B1–B3 is not wiped.
    final eid = _resolveFormCEnrollmentId();
    if (eid.isEmpty) {
      _showMsg("Missing enrollment ID — complete Form B1 randomisation first.");
      return;
    }

    BirthResuscitationData data;
    if (widget.shared != null) {
      data = widget.shared!;
    } else {
      data = BirthResuscitationData();
      try {
        final remote =
            await FormsApiService.instance.loadBirthResuscitation(eid);
        if (remote != null) {
          data = BirthResuscitationData.fromJson(remote);
        }
      } catch (_) {
        // Fall through with empty base — still save B4–B6 keys.
      }
      data
        ..screeningId ??= widget.screeningId
        ..babyUid ??= widget.babyUid;
    }
    data.screeningId ??= widget.screeningId;
    data.enrollmentId = eid;

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
      ..fluidBolus          = _fluidBolus
      ..fluidBolusDoses     = int.tryParse(_fluidBolusDosesCtrl.text.trim())
      ..fluidBolusCumulative= double.tryParse(_fluidBolusCumCtrl.text.trim())
      ..placentalTransfusion= _placentalTransfusion
      ..transfusionMethod   = _placentalTransfusion == true ? _placentalMethod : null
      ..cordClampTimestamp  = _cordClampedAtDisplay.isNotEmpty
          ? _cordClampedAtDisplay : null
      ..cordClampTime       = _elapsedCordClampSeconds()
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
      // Field 57 stores MM:SS string (from APGAR timer).
      ..totalResusTime      = normalizeTotalResusTimeMmSs(_totalTimeCtrl.text)
      ..reasonExitTrialGas  = _exitReason
      ..reasonExitTrialGasOther = _exitReason == "Other"
          ? _exitOtherCtrl.text.trim() : null
      ..blenderStopped      = _blenderStopped
      ..blenderInterruptReasons = _blenderStopped == true
          ? List<String>.from(_blenderInterruptReasons) : <String>[]
      ..blenderStoppedDescription = _blenderStopped == true &&
              _blenderInterruptReasons.contains(kBlenderAbruptReason)
          ? _blenderStopDescCtrl.text.trim() : null
      ..blenderLetter       =
          blenderLetterFromEnrollmentId(eid) ?? _blenderLetter;

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

    final formC = _snapshotFormC();

    try {
      // Legacy local cache
      await _api.saveFormC(formC);
      // Backend save — merged Form B1 + B2 payload via shared model
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
        content: const Text("Form B2 saved successfully"),
        backgroundColor: AppTheme.of(context).success,
      ));
      // Return to dashboard (pop Form B2; Form B1 also pops when result == true).
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

  /// Field 45 must not exceed field 57 (APGAR timer total).
  bool _spontaneousExceedsApgar() {
    final resp = _hmsToSeconds(_timeToRespCtrl.text);
    final total = _parseMmSs(_totalTimeCtrl.text)?.inSeconds;
    return resp != null && total != null && resp > total;
  }

  /// Elapsed cord-clamp seconds (0–300), matching web `cord_clamp_time`.
  int? _elapsedCordClampSeconds() {
    final t = _cordClampTimeCtrl.text.trim();
    final m = RegExp(r'^(\d+)\s*sec', caseSensitive: false).firstMatch(t);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n == null || n < 0 || n > 300) return null;
      return n;
    }
    final clampSec = _cordClampedAtTotalSeconds ??
        _clockTimeToSeconds(_cordClampedAtDisplay);
    final birthSec = _clockTimeToSeconds(_timeOfBirth);
    if (clampSec == null || birthSec == null) return null;
    var elapsed = clampSec - birthSec;
    if (elapsed < 0) elapsed += 86400;
    if (elapsed < 0 || elapsed > 300) return null;
    return elapsed;
  }

  String _fmtMmSs(Duration d) {
    final totalSec = d.inSeconds;
    final mm = totalSec ~/ 60;
    final ss = totalSec % 60;
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  Duration? _parseMmSs(String raw) {
    final s = normalizeTotalResusTimeMmSs(raw);
    if (s == null) return null;
    final m = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(s);
    if (m == null) return null;
    return Duration(
      minutes: int.tryParse(m.group(1)!) ?? 0,
      seconds: int.tryParse(m.group(2)!) ?? 0,
    );
  }

  /// MM:SS duration picker for field 57 (Total time from APGAR timer).
  Future<Duration?> _pickDurationMmSs(BuildContext context, {Duration? initial}) {
    int mm = (initial?.inMinutes ?? 0).clamp(0, 99);
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
            Text("Select Duration (MM:SS)",
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
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
                  child: _spinner(mm, 0, 99, c, (v) => setDlg(() => mm = v))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":",
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                  child: _spinner(ss, 0, 59, c, (v) => setDlg(() => ss = v))),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () =>
                  Navigator.pop(ctx, Duration(minutes: mm, seconds: ss)),
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
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

  InputDecoration _inputDec(String label, AppColors c, {String? hint}) {
    final labelStyle = TextStyle(color: c.textSecondary, fontSize: 13);
    return InputDecoration(
      label         : requiredLabel(label, style: labelStyle),
      hintText      : hint,
      hintStyle     : TextStyle(color: c.textTertiary, fontSize: 13),
      labelStyle    : labelStyle,
      floatingLabelStyle: labelStyle,
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
  }

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
      requiredLabel(
        title,
        style: TextStyle(
            color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
      ),
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
      {bool showError = false, bool enabled = true}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      requiredLabel(
        title,
        style: TextStyle(
            color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: options.map((opt) {
        final sel = value == opt;
        return GestureDetector(
          onTap: enabled ? () => setState(() => onChanged(opt)) : null,
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
      requiredLabel(
        "Cord clamped at (HH:MM:SS) *",
        style: TextStyle(
            color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
      ),
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
    String emptyHint = "Tap to select (HH:MM:SS)",
    String Function(Duration d)? formatDuration,
    String? errorText,
  }) {
    final filled    = ctrl.text.isNotEmpty;
    final showError = errorText != null || (_submitted && isRequired && !filled);
    final fmt = formatDuration ?? _fmtDuration;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      requiredLabel(
        label,
        style: TextStyle(
            color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        required: isRequired,
      ),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () async {
          final dur = await onPick();
          if (dur != null) setState(() => ctrl.text = fmt(dur));
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
                filled ? ctrl.text : emptyHint,
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
            child: Text(errorText ?? "Required",
                style: TextStyle(color: c.danger, fontSize: 11))),
      const SizedBox(height: 14),
    ]);
  }

  Widget _autoField(
    String label,
    TextEditingController ctrl,
    AppColors c, {
    String? note,
  }) {
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
      if (note != null && note.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(note,
            style: TextStyle(color: c.textTertiary, fontSize: 11)),
      ],
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
          Expanded(
            child: Text(ctrl.text.isEmpty ? "—" : ctrl.text,
                style: TextStyle(
                    color: ctrl.text.isEmpty ? c.textTertiary : c.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
    ]);
  }

  // Live messages match web BirthResuscitationForm.jsx field-error behaviour.
  String? _phLiveMessage(String v) {
    final t = v.trim();
    if (t.isEmpty || t == "." || t.endsWith(".")) return null;
    final n = double.tryParse(t);
    if (n == null) return null;
    if (n < 6.8 || n > 7.8) return "pH must be 6.8-7.8";
    return null;
  }

  String? _sbeLiveMessage(String v) {
    final t = v.trim();
    if (t.isEmpty || t == "-" || t == "." || t == "-." || t.endsWith(".")) {
      return null;
    }
    final n = double.tryParse(t);
    if (n == null) return "Enter a valid number";
    if (n < -30 || n > 30) return "SBE must be -30 to +30";
    return null;
  }

  String? _pco2LiveMessage(String v) {
    final t = v.trim();
    if (t.isEmpty || t == "." || t.endsWith(".")) return null;
    final n = double.tryParse(t);
    if (n == null) return "Enter a valid number";
    if (n < 0 || n > 200) return "pCO₂ must be 0–200";
    return null;
  }

  /// Cord-gas field with web-style live error under the input.
  Widget _liveCordGasField({
    required String label,
    required TextEditingController ctrl,
    required AppColors c,
    required String hint,
    required String? liveError,
    required ValueChanged<String> onChanged,
    required List<TextInputFormatter> inputFormatters,
    required TextInputType keyboardType,
    required bool requiredValidator,
    required double rangeMin,
    required double rangeMax,
    required String rangeMsg,
  }) {
    final hasLive = liveError != null && liveError.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: ctrl,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(color: c.textPrimary),
            decoration: _inputDec(label, c, hint: hint).copyWith(
              errorText: hasLive ? null : null, // live shown below
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasLive ? c.danger : c.border,
                  width: hasLive ? 1.5 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasLive ? c.danger : c.primary,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: onChanged,
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) {
                return requiredValidator ? "Required" : null;
              }
              final n = double.tryParse(t);
              if (n == null) return "Enter a valid number";
              if (n < rangeMin || n > rangeMax) return rangeMsg;
              return null;
            },
          ),
          if (hasLive)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                liveError,
                style: TextStyle(
                  color: c.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// [min]/[max] mirror the backend `@field_validator` ranges in
  /// `BirthResuscitationCreate` (schemas.py) — enforced client-side here so
  /// mobile rejects the same out-of-range values the backend would 422 on.
  /// Range is checked whenever a value is present, even if [required] is
  /// false (optional fields still must be in-range if the nurse fills them).
  Widget _textField(String label, TextEditingController ctrl, AppColors c,
      {bool required = true,
       TextInputType keyboardType = TextInputType.number,
       double? min,
       double? max,
       String? rangeLabel,
       String? hint,
       List<TextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller  : ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style       : TextStyle(color: c.textPrimary),
        decoration  : _inputDec(label, c, hint: hint),
        validator   : (v) {
          final t = v?.trim() ?? '';
          if (t.isEmpty) {
            return required ? "Required" : null;
          }
          if (min != null || max != null) {
            final n = double.tryParse(t);
            if (n == null) return "Enter a valid number";
            if (min != null && n < min) {
              return "Must be ${rangeLabel ?? '≥ $min'}";
            }
            if (max != null && n > max) {
              return "Must be ${rangeLabel ?? '≤ $max'}";
            }
          }
          return null;
        },
      ),
    );
  }

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
                child: Text(
                    rowName == "Oxygen"
                        ? "48. Oxygen"
                        : (rowName == "CPAP" ? "49. CPAP" : rowName),
                    style: TextStyle(
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
                child: Text("50. Apgar score", style: TextStyle(
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
                    LengthLimitingTextInputFormatter(2),
                    _ApgarOneToTenFormatter(),
                  ],
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense    : true,
                    filled     : true,
                    fillColor  : c.surfaceAlt,
                    hintText   : "1–10",
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
                        child: Text("View only — previously filled Form B2",
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
        Text("Form B2: Birth & Resuscitation (29–59)",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: c.textPrimary, letterSpacing: .3)),
        const SizedBox(height: 2),
        Text("B4–B6 · continues from Form B1",
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
    // SafeArea keeps buttons above tablet/system nav bars.
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
              icon: const Icon(Icons.check_circle_outline_rounded,
                  size: 16, color: Colors.white),
              label: const Text("Save",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              onPressed: _saveFormC,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.success,
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

  // ── Section 1 ─────────────────────────────────────────────────────────────
  Widget _buildResuscitationSection(AppColors c) {
    return _section(
      "B4 · Resuscitation Details",
      Icons.monitor_heart_rounded,
      c.danger,
      [
        // Web: 29. PPV (Ventilation) → Device used, then 29a/29b…
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text("29. PPV (Ventilation)",
              style: TextStyle(
                  color: c.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ),
        _pillRadio("Device used *",
              ["T-piece", "Self-inflating bag", "Both"],
              _device, (v) => setState(() => _device = v), c,
              showError: _submitted && _device == null),

          if (_device == "Self-inflating bag" || _device == "Both") ...[
            _pillRadio("29a. If SIB *",
                ["With PEEP valve", "Without PEEP valve"],
                _sibPeepWith == "Yes"
                    ? "With PEEP valve"
                    : (_sibPeepWith == "No" ? "Without PEEP valve" : null),
                (v) => setState(() {
                  _sibPeepWith = v == "With PEEP valve" ? "Yes" : "No";
                  _sibPeep = _sibPeepWith == "Yes";
                  if (_sibPeepWith == "No") _sibPeepValueCtrl.clear();
                }), c,
                showError: _submitted && _sibPeepWith == null),
            if (_sibPeepWith == "Yes")
              _textField("PEEP (cm H₂O) *",
                  _sibPeepValueCtrl, c,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],

          if (_device == "T-piece" || _device == "Both") ...[
            _textField("29b. If T-piece — PIP (cm H₂O) *",
                _tpiecePipCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _textField("PEEP (cm H₂O) *",
                _tpiecePeepCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _textField("Flow rate (L/min) *",
                _tpieceFlowCtrl, c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],

          _pillRadio("30. Interface *",
              ["Mask", "LMA", "Mask + LMA", "Endotracheal tube"],
              _interface, (v) => setState(() => _interface = v), c,
              showError: _submitted && _interface == null),
          _textField("31. Duration of PPV (sec) *",
              _ventDurationCtrl, c),

        _yesNo("32. Endotracheal intubation",
            _intubation, (v) => _intubation = v, c),
        _yesNo("33. Chest compressions",
            _chestCompression, (v) => _chestCompression = v, c),
        if (_chestCompression == true)
          _textField("34. Duration of CC (sec) *", _ccDurationCtrl, c),

        _yesNo("35. Epinephrine", _epinephrine, (v) => _epinephrine = v, c),
        if (_epinephrine == true) ...[
          _pillRadio("36. Dilution *",
              ["1:10000", "1:1000"],
              _adrenalineDilution,
              (v) => setState(() => _adrenalineDilution = v), c,
              showError: _submitted && _adrenalineDilution == null),
          _pillRadio("37. Route *",
              ["Umbilical vein", "Peripheral vein", "Intratracheal"],
              _adrenalineRoute,
              (v) => setState(() => _adrenalineRoute = v), c,
              showError: _submitted && _adrenalineRoute == null),
        ],

        _yesNo("38. Fluid bolus", _fluidBolus, (v) => _fluidBolus = v, c),
        if (_fluidBolus == true) ...[
          _textField("39. Doses *", _fluidBolusDosesCtrl, c),
          _textField("40. Cumulative (ml/mg) *",
              _fluidBolusCumCtrl, c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ],

        _yesNo("41. Placental transfusion",
            _placentalTransfusion, (v) {
              _placentalTransfusion = v;
              if (v != true) _placentalMethod = null;
            }, c),
        if (_placentalTransfusion == true)
          _pillRadio("42. Method *",
              ["Deferred clamping", "Intact cord milking"],
              _placentalMethod,
              (v) => setState(() => _placentalMethod = v), c,
              showError: _submitted && _placentalMethod == null),
        _cordClampTile(c),
        _autoField(
          "44. Cord clamping time from birth (sec)",
          _cordClampTimeCtrl,
          c,
          note: _timeOfBirth.trim().isEmpty
              ? "Needs 9. Time of Birth from Form B1"
              : "Auto from Time of Birth + Cord clamped at",
        ),

        _durationTile(
          label   : "45. Time to spontaneous respiratory efforts (HH:MM:SS)",
          ctrl    : _timeToRespCtrl,
          c       : c,
          onPick  : () => _pickDuration(context),
          errorText: _spontaneousExceedsApgar()
              ? "Must be ≤ 57. Total time from APGAR timer"
              : null,
        ),
        _textField("46. SpO₂ at 5 min (%)", _spo2At5Ctrl, c,
            required: false,
            min: 1,
            max: 100,
            rangeLabel: "1–100",
            inputFormatters: [_Spo2OneToHundredFormatter()],
            hint: "1–100"),
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
      "B5 · Intervention",
      Icons.timeline_rounded,
      c.warning,
      [_timelineTable(c)],
      c,
    );
  }

  // ── Section 3 ─────────────────────────────────────────────────────────────
  Widget _buildCordBloodSection(AppColors c) {
    return _section(
      "B6 · Cord Blood & Resuscitation Exit",
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
              _phLiveError = null;
              _sbeLiveError = null;
              _pco2LiveError = null;
            }, c),
        if (_cordBloodDone == false) ...[
          _pillRadio("52. If no, within 1 hr of birth sample *",
              ["Yes", "No"],
              _cordBloodWithin1hr == null
                  ? null
                  : (_cordBloodWithin1hr! ? "Yes" : "No"),
              (v) => setState(() {
                _cordBloodWithin1hr = v == "Yes";
                if (v != "Yes") {
                  _cordBloodSource = null;
                  _phCtrl.clear();
                  _beCtrl.clear();
                  _pco2Ctrl.clear();
                  _phLiveError = null;
                  _sbeLiveError = null;
                  _pco2LiveError = null;
                }
              }), c,
              showError: _submitted && _cordBloodWithin1hr == null),
        ],
        if (_cordBloodDone == false && _cordBloodWithin1hr == true)
          _pillRadio("53. Source *",
              ["Capillary", "Venous"],
              _cordBloodSource,
              (v) => setState(() => _cordBloodSource = v), c,
              showError: _submitted && _cordBloodSource == null),
        if (_cordBloodDone == true ||
            (_cordBloodDone == false && _cordBloodWithin1hr == true)) ...[
          _liveCordGasField(
            label: "54. pH *",
            ctrl: _phCtrl,
            c: c,
            hint: "6.8–7.8",
            liveError: _phLiveError,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_PhInputFormatter()],
            onChanged: (v) => setState(() => _phLiveError = _phLiveMessage(v)),
            requiredValidator: true,
            rangeMin: 6.8,
            rangeMax: 7.8,
            rangeMsg: "pH must be 6.8-7.8",
          ),
          _liveCordGasField(
            label: "54. SBE *",
            ctrl: _beCtrl,
            c: c,
            hint: "-30 to +30",
            liveError: _sbeLiveError,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            inputFormatters: [_SbeInputFormatter()],
            onChanged: (v) => setState(() => _sbeLiveError = _sbeLiveMessage(v)),
            requiredValidator: true,
            rangeMin: -30,
            rangeMax: 30,
            rangeMsg: "SBE must be -30 to +30",
          ),
          _liveCordGasField(
            label: "54. pCO₂ *",
            ctrl: _pco2Ctrl,
            c: c,
            hint: "0–200",
            liveError: _pco2LiveError,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_Pco2InputFormatter()],
            onChanged: (v) =>
                setState(() => _pco2LiveError = _pco2LiveMessage(v)),
            requiredValidator: true,
            rangeMin: 0,
            rangeMax: 200,
            rangeMsg: "pCO₂ must be 0–200",
          ),
        ],

        _yesNo("55. Resuscitation failure",
            _resusFailure, (v) => _resusFailure = v, c),

        _textField("56. SpO₂ at exit from trial gas (%)", _spo2ExitCtrl, c,
            required: false,
            min: 1,
            max: 100,
            rangeLabel: "1–100",
            inputFormatters: [_Spo2OneToHundredFormatter()],
            hint: "1–100"),

        _durationTile(
          label: "57. Total time (MM:SS) from APGAR timer",
          ctrl: _totalTimeCtrl,
          c: c,
          emptyHint: "Tap to select (MM:SS)",
          formatDuration: _fmtMmSs,
          onPick: () => _pickDurationMmSs(
            context,
            initial: _parseMmSs(_totalTimeCtrl.text),
          ),
        ),

        _pillRadio("58. Reason for resuscitation exit *",
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
          _textField("Specify *", _exitOtherCtrl, c,
              keyboardType: TextInputType.text),

        _yesNo("59. Was the PORTAL blender interrupted before 30 minutes?",
            _blenderStopped, (v) {
              _blenderStopped = v;
              if (v == false) {
                _blenderInterruptReasons = [];
                _blenderStopDescCtrl.clear();
              }
            }, c),
        if (_blenderStopped == true) ...[
          requiredLabel(
            "60. If yes, select reason *",
            style: TextStyle(
                color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...kBlenderInterruptReasons.map((opt) {
            final sel = _blenderInterruptReasons.contains(opt);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (sel) {
                    _blenderInterruptReasons.remove(opt);
                    if (opt == kBlenderAbruptReason) _blenderStopDescCtrl.clear();
                  } else {
                    _blenderInterruptReasons.add(opt);
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
                      opt == kBlenderAbruptReason
                          ? "Blender stopped abruptly, describe"
                          : opt,
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
          if (_blenderInterruptReasons.contains(kBlenderAbruptReason))
            _textField("Describe *", _blenderStopDescCtrl, c,
                keyboardType: TextInputType.multiline),
          const SizedBox(height: 8),
        ],
        _pillRadio("61. Blender Unit ID * (auto, from Enrollment ID)",
            ["A", "B", "C", "D"],
            _blenderLetter,
            (v) => setState(() => _blenderLetter = v), c,
            showError: _submitted && _blenderLetter == null,
            enabled: false),
      ],
      c,
    );
  }
}

/// Apgar score: digits only, values 1–10 (allows "01"–"09"; blocks 0 / >10).
class _ApgarOneToTenFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d{1,2}$').hasMatch(t)) return oldValue;
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 10) return oldValue;
    return newValue;
  }
}

/// SpO₂ at 5 min: digits only, values 1–100 (allows "01"–"09"; blocks 0 / >100).
class _Spo2OneToHundredFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d{1,3}$').hasMatch(t)) return oldValue;
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 100) return oldValue;
    return newValue;
  }
}

/// Web: /^\d*\.?\d{0,2}$/ — up to 2 decimal places (pH live-checked 6.8–7.8).
class _PhInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(t)) return oldValue;
    return newValue;
  }
}

/// Web: /^-?\d*\.?\d{0,1}$/ and value in [-30, 30] (allows "-" while typing).
class _SbeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || t == "-" || t == "." || t == "-.") return newValue;
    if (!RegExp(r'^-?\d*\.?\d{0,1}$').hasMatch(t)) return oldValue;
    final n = double.tryParse(t);
    if (n != null && (n < -30 || n > 30)) return oldValue;
    return newValue;
  }
}

/// Web: /^\d{0,3}(\.\d{0,1})?$/ and Number <= 200 (allows "." while typing).
class _Pco2InputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || t == ".") return newValue;
    if (!RegExp(r'^\d{0,3}(\.\d{0,1})?$').hasMatch(t)) return oldValue;
    final n = double.tryParse(t);
    if (n != null && n > 200) return oldValue;
    return newValue;
  }
}