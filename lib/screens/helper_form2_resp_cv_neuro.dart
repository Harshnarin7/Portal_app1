// lib/screens/helper_form2_resp_cv_neuro.dart
//
// Helper Form 2 — Resp / CV / Neuro Daily Log
// Parity with web RespCVNeuroLog.jsx: fields 2.1 + 1–37, same sequence,
// same validations, same /resp-cv-neuro/ API (NICU day, not calendar blob).

import 'package:flutter/material.dart';
import '../models/resp_cv_neuro_day.dart';
import '../services/forms_api_service.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';

class HelperForm2RespCvNeuro extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  final String site;

  const HelperForm2RespCvNeuro({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.site = 'PGIMER',
  });

  @override
  State<HelperForm2RespCvNeuro> createState() =>
      _HelperForm2RespCvNeuroState();
}

class _HelperForm2RespCvNeuroState extends State<HelperForm2RespCvNeuro> {
  static const _lateGraceHour = 11;

  final _api = FormsApiService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _dayLoading = false;
  String? _banner;
  bool _bannerError = false;

  DateTime? _day1Date;
  bool _day1Locked = false;
  int _totalDays = 14;
  int _activeDay = 1;
  int _todayNicuDay = 1;

  final Map<int, String> _dayStatus = {}; // empty|draft|complete|submitted|late
  final Map<int, int> _dayPct = {};

  bool _recordExists = false;
  bool _isEditing = true;
  bool _isSubmitted = false;
  /// Site-monitor override expiry for the active day (mirrors web's
  /// `overrideUntil` — reopens an otherwise-submitted/locked day for a
  /// limited window). Parsed from `override_unlocked_until` on the day
  /// record returned by the backend.
  DateTime? _overrideUntil;
  /// Set when day GET fails — blocks save so prior-day values aren't written
  /// onto the wrong NICU day.
  bool _dayLoadFailed = false;
  int _loadGen = 0;

  // Controllers
  final _weightCtrl = TextEditingController();
  final _mapCpapCtrl = TextEditingController();
  final _mapCpapSecCtrl = TextEditingController();
  final _maxFio2Ctrl = TextEditingController();
  final _maxFlowCtrl = TextEditingController();
  final _phCtrl = TextEditingController();
  final _pao2LowCtrl = TextEditingController();
  final _pao2HighCtrl = TextEditingController();
  final _paco2LowCtrl = TextEditingController();
  final _paco2HighCtrl = TextEditingController();
  final _apneaCtrl = TextEditingController();
  final _desatCtrl = TextEditingController();
  final _severeDesatCtrl = TextEditingController();
  final _fluidBolusCtrl = TextEditingController();

  bool? _respiratorySupport;
  bool? _endotrachealIntubation;
  List<String> _supportModes = [];
  bool? _suppO2;
  bool _pao2NotDone = false;
  bool _paco2NotDone = false;
  bool? _surfactant;
  bool? _caffeine;
  bool? _extubAttempted;
  bool? _extubFailure;
  bool? _pulmHemorrhage;
  bool? _pneumothorax;
  bool? _chestDrain;
  bool? _pphn;
  bool? _postnatalSteroids;

  bool? _pdaSuspected;
  bool? _echoDone;
  bool? _hsPda;
  bool? _shock;
  bool? _vasoactiveSupport;
  List<String> _vasoactiveDrugs = [];

  bool? _cranialUsg;
  bool? _ivh;
  String? _ivhGrade;
  bool? _cpvlConfirmed;
  bool? _ventriculomegaly;
  bool? _clinicalSeizures;
  bool? _eegSeizures;
  bool? _aedsGiven;
  bool? _nonIvhIch;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _weightCtrl,
      _mapCpapCtrl,
      _mapCpapSecCtrl,
      _maxFio2Ctrl,
      _maxFlowCtrl,
      _phCtrl,
      _pao2LowCtrl,
      _pao2HighCtrl,
      _paco2LowCtrl,
      _paco2HighCtrl,
      _apneaCtrl,
      _desatCtrl,
      _severeDesatCtrl,
      _fluidBolusCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in [
      _weightCtrl,
      _mapCpapCtrl,
      _mapCpapSecCtrl,
      _maxFio2Ctrl,
      _maxFlowCtrl,
      _phCtrl,
      _pao2LowCtrl,
      _pao2HighCtrl,
      _paco2LowCtrl,
      _paco2HighCtrl,
      _apneaCtrl,
      _desatCtrl,
      _severeDesatCtrl,
      _fluidBolusCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String> _nurseName() async {
    final p = await TokenStorage.getProfile();
    final name = (p?['full_name'] ?? p?['username'] ?? 'Nurse').toString();
    return name.trim().isEmpty ? 'Nurse' : name.trim();
  }

  Future<void> _bootstrap() async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) {
      setState(() {
        _loading = false;
        _banner = 'No enrollment ID — open from a randomised patient.';
        _bannerError = true;
      });
      return;
    }
    try {
      try {
        final d1 = await _api.loadDay1Date(eid);
        final raw = d1['day1_date']?.toString();
        if (raw != null && raw.isNotEmpty) {
          _day1Date = DateTime.tryParse(raw.substring(0, 10));
        }
        _day1Locked = d1['locked'] == true;
      } catch (e) {
        _banner =
            'Could not load Day 1 Date from server — set it before saving: $e';
        _bannerError = true;
      }

      final summary = await _api.loadRespCvNeuroSummary(eid);
      var maxDay = 14;
      for (final row in summary) {
        final n = row['nicu_day'];
        final day = n is int ? n : int.tryParse('$n') ?? 0;
        if (day < 1) continue;
        if (day > maxDay) maxDay = day;
        final st = (row['submission_status'] ?? 'empty').toString();
        final pct = row['completion_pct'];
        _dayStatus[day] = st;
        _dayPct[day] = pct is int ? pct : int.tryParse('$pct') ?? 0;
        if (st != 'empty' && st.isNotEmpty) _day1Locked = true;
      }
      _totalDays = maxDay < 14 ? 14 : maxDay;
      _recomputeTodayNicuDay();
      _activeDay = _defaultActiveDay();
    } catch (e) {
      _banner = 'Could not load day summary: $e';
      _bannerError = true;
    }
    if (mounted) {
      setState(() => _loading = false);
      await _loadActiveDay();
    }
  }

  void _recomputeTodayNicuDay() {
    if (_day1Date == null) {
      _todayNicuDay = 1;
      return;
    }
    final now = DateTime.now();
    final d1 = DateTime(_day1Date!.year, _day1Date!.month, _day1Date!.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d1).inDays + 1;
    _todayNicuDay = diff < 1 ? 1 : diff;
  }

  int _defaultActiveDay() {
    if (_day1Date == null) return 1;
    final hour = DateTime.now().hour;
    if (hour < _lateGraceHour && _todayNicuDay > 1) {
      return _todayNicuDay - 1;
    }
    return _todayNicuDay;
  }

  DateTime? _calendarForDay(int day) {
    if (_day1Date == null) return null;
    return DateTime(_day1Date!.year, _day1Date!.month, _day1Date!.day)
        .add(Duration(days: day - 1));
  }

  bool get _isFutureDay =>
      _day1Date != null && _activeDay > _todayNicuDay;

  /// Informational only — a past day's calendar date no longer forces the
  /// record read-only on its own. Locking is manual, via Submit & Lock
  /// (mirrors web's `isPastActiveDay`).
  bool get _isPastActiveDay =>
      _day1Date != null && _activeDay < _todayNicuDay;

  /// Site-monitor override reopens an otherwise-locked day for a limited
  /// window (mirrors web's `isOverrideActiveDay`).
  bool get _isOverrideActive =>
      _overrideUntil != null && DateTime.now().toUtc().isBefore(_overrideUntil!);

  bool get _isFieldEditable {
    if (_isSubmitted && !_isOverrideActive) return false;
    if (_isFutureDay) return false;
    if (_recordExists && !_isEditing) return false;
    return true;
  }

  /// Parses a backend timestamp as UTC even when it lacks an explicit
  /// timezone suffix (matches web's `parseUtcTimestamp`).
  static DateTime? _parseUtc(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    if (s.isEmpty) return null;
    final hasTz = RegExp(r'[Zz]|[+-]\d{2}:?\d{2}$').hasMatch(s);
    try {
      return DateTime.parse(hasTz ? s : '${s}Z').toUtc();
    } catch (_) {
      return null;
    }
  }

  RespCvNeuroCompletion get _completion => RespCvNeuroCompletion.compute(
        weightKg: _weightCtrl.text,
        respiratorySupport: _respiratorySupport,
        endotrachealIntubation: _endotrachealIntubation,
        supportModes: _supportModes,
        mapCpap: _mapCpapCtrl.text,
        mapCpapSecondary: _mapCpapSecCtrl.text,
        maxFio2: _maxFio2Ctrl.text,
        maxFlow: _maxFlowCtrl.text,
        suppO2: _suppO2,
        lowestPh: _phCtrl.text,
        pao2NotDone: _pao2NotDone,
        pao2Low: _pao2LowCtrl.text,
        pao2High: _pao2HighCtrl.text,
        paco2NotDone: _paco2NotDone,
        paco2Low: _paco2LowCtrl.text,
        paco2High: _paco2HighCtrl.text,
        surfactant: _surfactant,
        caffeine: _caffeine,
        apneaCount: _apneaCtrl.text,
        desatCount: _desatCtrl.text,
        severeDesatCount: _severeDesatCtrl.text,
        extubAttempted: _extubAttempted,
        extubFailure: _extubFailure,
        pulmHemorrhage: _pulmHemorrhage,
        pneumothorax: _pneumothorax,
        chestDrain: _chestDrain,
        pphn: _pphn,
        postnatalSteroids: _postnatalSteroids,
        pdaSuspected: _pdaSuspected,
        echoDone: _echoDone,
        hsPda: _hsPda,
        shock: _shock,
        vasoactiveSupport: _vasoactiveSupport,
        vasoactiveDrugs: _vasoactiveDrugs,
        fluidBolus: _fluidBolusCtrl.text,
        cranialUsg: _cranialUsg,
        ivh: _ivh,
        ivhGrade: _ivhGrade,
        cpvlConfirmed: _cpvlConfirmed,
        ventriculomegaly: _ventriculomegaly,
        clinicalSeizures: _clinicalSeizures,
        eegSeizures: _eegSeizures,
        aedsGiven: _aedsGiven,
        nonIvhIch: _nonIvhIch,
      );

  bool get _canSubmit =>
      _completion.percent == 100 &&
      (!_isSubmitted || _isOverrideActive) &&
      !_isFutureDay;

  Future<void> _loadActiveDay() async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return;
    final day = _activeDay;
    final gen = ++_loadGen;
    setState(() => _dayLoading = true);
    try {
      final raw = await _api.loadRespCvNeuroDay(eid, day);
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      if (raw == null) {
        _clearForm();
        _recordExists = false;
        _isEditing = true;
        _isSubmitted = false;
        _overrideUntil = null;
        _dayLoadFailed = false;
      } else {
        _applyDay(RespCvNeuroDay.fromJson(raw));
        _recordExists = true;
        _isSubmitted = (raw['submission_status']?.toString() == 'submitted');
        _overrideUntil = _parseUtc(raw['override_unlocked_until']);
        // A reload/revisit during a still-active override window must not
        // silently re-lock the fields.
        _isEditing = _isOverrideActive;
        _dayLoadFailed = false;
      }
    } catch (e) {
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      // Never keep previous day's values in the form on a failed load.
      _clearForm();
      _recordExists = false;
      _isEditing = false;
      _isSubmitted = false;
      _overrideUntil = null;
      _dayLoadFailed = true;
      _banner =
          'Could not load Day $day — save disabled until reload succeeds: $e';
      _bannerError = true;
    } finally {
      if (mounted && gen == _loadGen) setState(() => _dayLoading = false);
    }
  }

  void _clearForm() {
    for (final c in [
      _weightCtrl,
      _mapCpapCtrl,
      _mapCpapSecCtrl,
      _maxFio2Ctrl,
      _maxFlowCtrl,
      _phCtrl,
      _pao2LowCtrl,
      _pao2HighCtrl,
      _paco2LowCtrl,
      _paco2HighCtrl,
      _apneaCtrl,
      _desatCtrl,
      _severeDesatCtrl,
      _fluidBolusCtrl,
    ]) {
      c.clear();
    }
    _respiratorySupport = null;
    _endotrachealIntubation = null;
    _supportModes = [];
    _suppO2 = null;
    _pao2NotDone = false;
    _paco2NotDone = false;
    _surfactant = null;
    _caffeine = null;
    _extubAttempted = null;
    _extubFailure = null;
    _pulmHemorrhage = null;
    _pneumothorax = null;
    _chestDrain = null;
    _pphn = null;
    _postnatalSteroids = null;
    _pdaSuspected = null;
    _echoDone = null;
    _hsPda = null;
    _shock = null;
    _vasoactiveSupport = null;
    _vasoactiveDrugs = [];
    _cranialUsg = null;
    _ivh = null;
    _ivhGrade = null;
    _cpvlConfirmed = null;
    _ventriculomegaly = null;
    _clinicalSeizures = null;
    _eegSeizures = null;
    _aedsGiven = null;
    _nonIvhIch = null;
  }

  void _applyDay(RespCvNeuroDay d) {
    _weightCtrl.text = d.weightKg ?? '';
    _respiratorySupport = d.respiratorySupport;
    _endotrachealIntubation = d.endotrachealIntubation;
    _supportModes = List.of(d.supportModes);
    _mapCpapCtrl.text = d.mapCpap?.toString() ?? '';
    _mapCpapSecCtrl.text = d.mapCpapSecondary?.toString() ?? '';
    _maxFio2Ctrl.text = d.maxFio2?.toString() ?? '';
    _maxFlowCtrl.text = d.maxFlow?.toString() ?? '';
    _suppO2 = d.suppO2;
    _phCtrl.text = d.lowestPh ?? '';
    final pa = RespCvNeuroValidators.parseRange(d.pao2Range);
    _pao2NotDone = pa.notDone;
    _pao2LowCtrl.text = pa.low;
    _pao2HighCtrl.text = pa.high;
    final pc = RespCvNeuroValidators.parseRange(d.paco2Range);
    _paco2NotDone = pc.notDone;
    _paco2LowCtrl.text = pc.low;
    _paco2HighCtrl.text = pc.high;
    _surfactant = d.surfactant;
    _caffeine = d.caffeine;
    _apneaCtrl.text = d.apneaCount ?? '';
    _desatCtrl.text = d.desaturationCount ?? '';
    _severeDesatCtrl.text = d.severeDesaturationCount ?? '';
    _extubAttempted = d.extubAttempted;
    _extubFailure = d.extubFailure;
    _pulmHemorrhage = d.pulmHemorrhage;
    _pneumothorax = d.pneumothorax;
    _chestDrain = d.chestDrain;
    _pphn = d.pphn;
    _postnatalSteroids = d.postnatalSteroids;
    _pdaSuspected = d.pdaSuspected;
    _echoDone = d.echoDone;
    _hsPda = d.hsPda;
    _shock = d.shock;
    _vasoactiveSupport = d.vasoactiveSupport;
    _vasoactiveDrugs = List.of(d.vasoactiveDrugs);
    _fluidBolusCtrl.text = d.fluidBolus ?? '';
    _cranialUsg = d.cranialUsg;
    _ivh = d.ivh;
    _ivhGrade = d.ivhGrade;
    _cpvlConfirmed = d.cpvlConfirmed;
    _ventriculomegaly = d.ventriculomegaly;
    _clinicalSeizures = d.clinicalSeizures;
    _eegSeizures = d.eegSeizures;
    _aedsGiven = d.aedsGiven;
    _nonIvhIch = d.nonIvhIch;
  }

  RespCvNeuroDay _buildModel() {
    final d = RespCvNeuroDay(
      enrollmentId: widget.enrollmentId.trim(),
      nicuDay: _activeDay,
    );
    d.weightKg = _weightCtrl.text.trim().isEmpty ? null : _weightCtrl.text.trim();
    d.respiratorySupport = _respiratorySupport;
    d.endotrachealIntubation = _endotrachealIntubation;
    d.supportModes = List.of(_supportModes);
    d.mapCpap = double.tryParse(_mapCpapCtrl.text.trim());
    d.mapCpapSecondary = double.tryParse(_mapCpapSecCtrl.text.trim());
    d.maxFio2 = double.tryParse(_maxFio2Ctrl.text.trim());
    d.maxFlow = double.tryParse(_maxFlowCtrl.text.trim());
    d.suppO2 = _suppO2;
    d.lowestPh = _phCtrl.text.trim().isEmpty ? null : _phCtrl.text.trim();
    d.pao2Range = RespCvNeuroValidators.combineRange(
        _pao2LowCtrl.text, _pao2HighCtrl.text, _pao2NotDone);
    d.paco2Range = RespCvNeuroValidators.combineRange(
        _paco2LowCtrl.text, _paco2HighCtrl.text, _paco2NotDone);
    d.surfactant = _surfactant;
    d.caffeine = _caffeine;
    d.apneaCount = _apneaCtrl.text.trim().isEmpty ? null : _apneaCtrl.text.trim();
    d.desaturationCount =
        _desatCtrl.text.trim().isEmpty ? null : _desatCtrl.text.trim();
    d.severeDesaturationCount = _severeDesatCtrl.text.trim().isEmpty
        ? null
        : _severeDesatCtrl.text.trim();
    d.extubAttempted = _extubAttempted;
    d.extubFailure = _extubFailure;
    d.pulmHemorrhage = _pulmHemorrhage;
    d.pneumothorax = _pneumothorax;
    d.chestDrain = _chestDrain;
    d.pphn = _pphn;
    d.postnatalSteroids = _postnatalSteroids;
    d.pdaSuspected = _pdaSuspected;
    d.echoDone = _echoDone;
    d.hsPda = _hsPda;
    d.shock = _shock;
    d.vasoactiveSupport = _vasoactiveSupport;
    d.vasoactiveDrugs = List.of(_vasoactiveDrugs);
    d.fluidBolus =
        _fluidBolusCtrl.text.trim().isEmpty ? null : _fluidBolusCtrl.text.trim();
    d.cranialUsg = _cranialUsg;
    d.ivh = _ivh;
    d.ivhGrade = _ivhGrade;
    d.cpvlConfirmed = _cpvlConfirmed;
    d.ventriculomegaly = _ventriculomegaly;
    d.clinicalSeizures = _clinicalSeizures;
    d.eegSeizures = _eegSeizures;
    d.aedsGiven = _aedsGiven;
    d.nonIvhIch = _nonIvhIch;
    return d;
  }

  Future<void> _selectDay1Date() async {
    if (_day1Locked) {
      _toast('Day 1 Date is locked once daily logs exist', error: true);
      return;
    }
    final picked = await showModernDatePicker(
      context: context,
      initialDate: _day1Date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    final ymd =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    try {
      await _api.saveDay1Date(widget.enrollmentId.trim(), ymd);
      setState(() {
        _day1Date = DateTime(picked.year, picked.month, picked.day);
        _recomputeTodayNicuDay();
        _activeDay = _defaultActiveDay();
      });
      await _loadActiveDay();
    } catch (e) {
      _toast('Could not save Day 1 Date: $e', error: true);
    }
  }

  Future<void> _switchDay(int day) async {
    if (day == _activeDay) return;
    if (_day1Date != null && day > _todayNicuDay) {
      _toast('Day $day is not available yet');
      return;
    }
    setState(() => _activeDay = day);
    await _loadActiveDay();
  }

  Future<void> _addDay() async {
    setState(() => _totalDays += 1);
  }

  Future<void> _copyPrevious() async {
    if (!_isFieldEditable || _activeDay <= 1) return;
    try {
      final raw = await _api.loadRespCvNeuroDay(
          widget.enrollmentId.trim(), _activeDay - 1);
      if (raw == null) {
        _toast('No data on Day ${_activeDay - 1} to copy', error: true);
        return;
      }
      final src = RespCvNeuroDay.fromJson(raw);
      final cur = _buildModel()..copyClinicalFrom(src);
      setState(() {
        _applyDay(cur);
        _recordExists = false; // force re-save as draft for this day
        _isEditing = true;
      });
      _toast('Copied clinical fields from Day ${_activeDay - 1}');
    } catch (e) {
      _toast('Copy failed: $e', error: true);
    }
  }

  Future<bool> _save({bool forLater = false, bool force = false}) async {
    if (_dayLoadFailed) {
      _toast('Day failed to load — switch day or reopen form before saving',
          error: true);
      return false;
    }
    if (!force && !_isFieldEditable && !_isEditing) return false;
    if (_isFutureDay || (_isSubmitted && !_isOverrideActive)) return false;
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return false;
    if (_day1Date == null) {
      _toast('Set Day 1 Date first', error: true);
      return false;
    }

    setState(() => _saving = true);
    try {
      final name = await _nurseName();
      final now = DateTime.now().toUtc().toIso8601String();
      final model = _buildModel();
      // Clear gated children only when parent is explicitly No (not unanswered).
      // Matches web toggle clears; avoids wiping web orphans when parent is null.
      if (model.respiratorySupport == false) {
        model.supportModes = [];
        model.mapCpap = null;
        model.mapCpapSecondary = null;
        model.maxFio2 = null;
        model.maxFlow = null;
        model.suppO2 = null;
      }
      if (model.extubAttempted == false) model.extubFailure = null;
      if (model.vasoactiveSupport == false) model.vasoactiveDrugs = [];
      if (model.cranialUsg == false) {
        model.ivh = null;
        model.ivhGrade = null;
        model.cpvlConfirmed = null;
        model.ventriculomegaly = null;
      } else if (model.ivh == false) {
        model.ivhGrade = null;
      }
      final mode = RespCvNeuroValidators.mapCpapMode(model.supportModes);
      if (mode == 'NA') {
        model.mapCpap = null;
        model.mapCpapSecondary = null;
      } else if (mode != 'BOTH') {
        model.mapCpapSecondary = null;
      }

      final body = model.toJson(
        submissionStatus: 'draft',
        savedAt: now,
        savedBy: name,
      );
      await _api.saveRespCvNeuroDay(body, alreadyExists: _recordExists);
      final pct = _completion.percent;
      setState(() {
        _recordExists = true;
        _isEditing = false;
        _dayStatus[_activeDay] = pct == 100 ? 'complete' : 'draft';
        _dayPct[_activeDay] = pct;
        _day1Locked = true;
        _banner = forLater
            ? 'Day $_activeDay saved for later'
            : 'Day $_activeDay saved successfully';
        _bannerError = false;
      });
      return true;
    } catch (e) {
      setState(() {
        _banner = 'Save failed: $e';
        _bannerError = true;
      });
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Submit Day $_activeDay Data'),
        content: Text(
          'This will lock the record for Day $_activeDay.\n\n'
          'Completion: ${_completion.percent}%\n'
          'After submission, nurses cannot edit this day.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit & Lock')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      // Always persist current edits before locking (force bypasses read-only
      // "saved draft" view so Submit after Save still re-saves latest values).
      final saved = await _save(force: true);
      if (!saved) {
        setState(() {
          _banner = 'Submit cancelled — save current day data first';
          _bannerError = true;
        });
        return;
      }
      final name = await _nurseName();
      await _api.submitRespCvNeuroDay(
        enrollmentId: widget.enrollmentId.trim(),
        nicuDay: _activeDay,
        submittedBy: name,
      );
      setState(() {
        _isSubmitted = true;
        _isEditing = false;
        // Re-locking (even mid-override) ends the override immediately —
        // mirrors backend clearing override_unlocked_until on submit.
        _overrideUntil = null;
        _dayStatus[_activeDay] = 'submitted';
        _banner = 'Day $_activeDay submitted and locked';
        _bannerError = false;
      });
    } catch (e) {
      setState(() {
        _banner = 'Submit failed: $e';
        _bannerError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.of(context).danger : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: _appBar(c),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final editable = _isFieldEditable;
    final mapMode = RespCvNeuroValidators.mapCpapMode(_supportModes);
    final supportYes = _respiratorySupport == true;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _appBar(c),
      body: Column(
        children: [
          _day1Bar(c),
          _dayChips(c),
          _statusBanner(c),
          if (_banner != null) _messageBanner(c),
          Expanded(
            child: _dayLoading
                ? const Center(child: CircularProgressIndicator())
                : _isFutureDay
                    ? _lockedPanel(c, 'Not Available Yet',
                        'Day $_activeDay is in the future.')
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _progressHeader(c),
                          if (_isPastActiveDay && !_isSubmitted)
                            _infoChip(c, 'Past day — still editable', c.warning),
                          if (_isSubmitted && !_isOverrideActive)
                            _infoChip(c, 'Submitted — locked', c.success),
                          if (_isSubmitted && _isOverrideActive)
                            _infoChip(c, 'Locked — override active', c.warning),
                          if (_recordExists &&
                              !_isEditing &&
                              (!_isSubmitted || _isOverrideActive))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _isEditing = true),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: Text('Edit Day $_activeDay'),
                              ),
                            ),
                          if (editable && _activeDay > 1)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _copyPrevious,
                                icon: const Icon(Icons.copy_all_outlined,
                                    size: 18),
                                label: const Text('Copy from previous day'),
                              ),
                            ),
                          _weightField(c, editable),
                          _section(
                            c,
                            title: 'Respiratory Assessment',
                            icon: Icons.air_rounded,
                            color: c.primary,
                            children: _respiratoryFields(
                                c, editable, supportYes, mapMode),
                          ),
                          _section(
                            c,
                            title: 'Cardiovascular Assessment',
                            icon: Icons.favorite_rounded,
                            color: c.danger,
                            children: _cvFields(c, editable),
                          ),
                          _section(
                            c,
                            title: 'Neurological Assessment',
                            icon: Icons.psychology_rounded,
                            color: c.purple,
                            children: _neuroFields(c, editable),
                          ),
                        ],
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(c),
    );
  }

  AppBar _appBar(AppColors c) {
    return AppBar(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 66,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.borderLight),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.babyUid.isEmpty ? 'HELPER FORM 2' : widget.babyUid,
            style: TextStyle(
              color: c.primary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          Text(
            'Resp / CV / Neuro Daily Log · ${widget.motherName.isEmpty ? widget.enrollmentId : widget.motherName}',
            style: TextStyle(color: c.textTertiary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
    );
  }

  Widget _day1Bar(AppColors c) {
    final label = _day1Date == null
        ? 'Not set'
        : '${_day1Date!.day.toString().padLeft(2, '0')} '
            '${_month(_day1Date!.month)} ${_day1Date!.year}';
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text('Day 1 Date',
              style: TextStyle(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _day1Locked ? null : _selectDay1Date,
              child: Text(label),
            ),
          ),
          if (_day1Locked)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.lock_outline, size: 18, color: c.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _dayChips(AppColors c) {
    return Container(
      color: c.surface,
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _totalDays + 1,
        itemBuilder: (_, i) {
          if (i == _totalDays) {
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ActionChip(
                label: const Text('+ Day'),
                onPressed: _addDay,
              ),
            );
          }
          final day = i + 1;
          final selected = day == _activeDay;
          final future = _day1Date != null && day > _todayNicuDay;
          final st = _dayStatus[day] ?? 'empty';
          final cal = _calendarForDay(day);
          final dateLabel = cal == null
              ? ''
              : '${cal.day} ${_month(cal.month)}';
          Color dot;
          switch (st) {
            case 'submitted':
              dot = c.success;
              break;
            case 'complete':
              dot = c.primary;
              break;
            case 'draft':
            case 'late':
              dot = c.warning;
              break;
            default:
              dot = c.border;
          }
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              selected: selected,
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text('D$day',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                      if (future) ...[
                        const SizedBox(width: 2),
                        const Icon(Icons.lock, size: 12),
                      ],
                    ],
                  ),
                  if (dateLabel.isNotEmpty)
                    Text(dateLabel,
                        style: TextStyle(
                            fontSize: 9, color: c.textTertiary)),
                ],
              ),
              onSelected: future ? null : (_) => _switchDay(day),
            ),
          );
        },
      ),
    );
  }

  Widget _statusBanner(AppColors c) {
    if (_day1Date == null) {
      return Container(
        width: double.infinity,
        color: c.warningSoft,
        padding: const EdgeInsets.all(10),
        child: Text('Set Day 1 Date to enable NICU day logging.',
            style: TextStyle(color: c.warning, fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _messageBanner(AppColors c) {
    return Container(
      width: double.infinity,
      color: _bannerError ? c.dangerSoft : c.successSoft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(_banner!,
          style: TextStyle(
              color: _bannerError ? c.danger : c.success, fontSize: 12)),
    );
  }

  Widget _progressHeader(AppColors c) {
    final pct = _completion.percent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: pct / 100,
                  strokeWidth: 5,
                  backgroundColor: c.borderLight,
                  color: pct == 100 ? c.success : c.primary,
                ),
                Text('$pct%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Day $_activeDay',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: c.textPrimary)),
                Text(
                  '${_completion.answered}/${_completion.total} fields · Gestation ${widget.gestation}',
                  style: TextStyle(color: c.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(AppColors c, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _lockedPanel(AppColors c, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined, size: 48, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: c.textPrimary)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _weightField(AppColors c, bool editable) {
    final err = RespCvNeuroValidators.weightEntries(_weightCtrl.text);
    return _fieldCard(
      c,
      number: '2.1',
      label: 'Weight',
      hint: '(all measured weights of the day, chronologically)',
      child: _textField(_weightCtrl, c,
          enabled: editable,
          hint: 'e.g. 1250g, 1245g or 1.25kg',
          error: err),
    );
  }

  List<Widget> _respiratoryFields(
    AppColors c,
    bool editable,
    bool supportYes,
    String? mapMode,
  ) {
    final isBoth = mapMode == 'BOTH';
    final isNa = mapMode == 'NA';
    final mapFieldLabel = isBoth
        ? 'Max MAP'
        : mapMode == 'MAP'
            ? 'Max MAP'
            : mapMode == 'CPAP'
                ? 'Max CPAP'
                : 'Max CPAP/MAP';
    final mapErr = isNa
        ? null
        : RespCvNeuroValidators.mapCpap(
            _mapCpapCtrl.text, isBoth ? 'MAP' : mapMode);
    final mapSecErr = isBoth
        ? RespCvNeuroValidators.mapCpap(_mapCpapSecCtrl.text, 'CPAP')
        : null;

    final severeErr = RespCvNeuroValidators.count(_severeDesatCtrl.text,
            max: 50, label: 'Severe desaturation count') ??
        ((_desatCtrl.text.trim().isNotEmpty &&
                _severeDesatCtrl.text.trim().isNotEmpty &&
                (double.tryParse(_severeDesatCtrl.text) ?? 0) >
                    (double.tryParse(_desatCtrl.text) ?? 0))
            ? "Severe desaturations can't exceed total desaturations (#14)"
            : null);

    return [
      _yn('1. Respiratory support', _respiratorySupport, editable, (v) {
        setState(() {
          _respiratorySupport = v;
          if (v != true) {
            _supportModes = [];
            _mapCpapCtrl.clear();
            _mapCpapSecCtrl.clear();
            _maxFio2Ctrl.clear();
            _maxFlowCtrl.clear();
            _suppO2 = null;
          }
        });
      }, c),
      _yn('2. Endotracheally intubated', _endotrachealIntubation, editable,
          (v) => setState(() => _endotrachealIntubation = v), c),
      _fieldCard(
        c,
        number: '3',
        label: 'Mode',
        hint: supportYes
            ? 'NC, HFNC, CPAP, NIPPV, SIMV, A/C, PSV, HFOV — select all that apply'
            : 'Enabled once Respiratory support (#1) is Yes',
        child: _pills(
          RespCvNeuroDay.supportModeOptions,
          _supportModes,
          editable && supportYes,
          (next) {
            setState(() {
              _supportModes = next;
              final m = RespCvNeuroValidators.mapCpapMode(next);
              if (m == 'NA') _mapCpapCtrl.clear();
              if (m != 'BOTH') _mapCpapSecCtrl.clear();
            });
          },
          c,
          labels: const {
            'AC': 'A/C',
          },
        ),
      ),
      if (isNa)
        _fieldCard(c,
            number: '4',
            label: 'Max CPAP/MAP',
            child: Text('NA — mode doesn\'t generate pressure',
                style: TextStyle(color: c.textTertiary, fontSize: 13)))
      else ...[
        if (isBoth)
          _fieldCard(
            c,
            number: '4',
            label: 'Max CPAP',
            child: _textField(_mapCpapSecCtrl, c,
                enabled: editable && supportYes,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                hint: 'cm H₂O',
                error: mapSecErr),
          ),
        _fieldCard(
          c,
          number: isBoth ? '4b' : '4',
          label: mapFieldLabel,
          child: _textField(_mapCpapCtrl, c,
              enabled: editable && supportYes,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              hint: 'cm H₂O',
              error: mapErr),
        ),
      ],
      _fieldCard(
        c,
        number: '5',
        label: 'Max FiO₂',
        child: _textField(_maxFio2Ctrl, c,
            enabled: editable && supportYes,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '21',
            error: supportYes
                ? RespCvNeuroValidators.maxFio2(_maxFio2Ctrl.text)
                : null),
      ),
      _fieldCard(
        c,
        number: '6',
        label: 'Max Gas Flow',
        child: _textField(_maxFlowCtrl, c,
            enabled: editable && supportYes,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: 'L/min',
            error: supportYes
                ? RespCvNeuroValidators.maxFlow(_maxFlowCtrl.text)
                : null),
      ),
      _yn('7. Supplemental O₂ >21% (any)', _suppO2, editable && supportYes,
          (v) => setState(() => _suppO2 = v), c,
          hint: supportYes ? null : 'Enabled once #1 is Yes'),
      _fieldCard(
        c,
        number: '8',
        label: 'pH',
        hint: '(lowest of the day)',
        child: _textField(_phCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '7.25',
            error: RespCvNeuroValidators.ph(_phCtrl.text)),
      ),
      _bloodGasField(
        c,
        number: '9',
        label: 'PaO₂',
        unit: '(mmHg)',
        low: _pao2LowCtrl,
        high: _pao2HighCtrl,
        notDone: _pao2NotDone,
        editable: editable,
        min: 20,
        max: 600,
        onNotDone: (v) => setState(() {
          _pao2NotDone = v;
          if (v) {
            _pao2LowCtrl.clear();
            _pao2HighCtrl.clear();
          }
        }),
      ),
      _bloodGasField(
        c,
        number: '10',
        label: 'PaCO₂',
        unit: '(mmHg)',
        low: _paco2LowCtrl,
        high: _paco2HighCtrl,
        notDone: _paco2NotDone,
        editable: editable,
        min: 15,
        max: 150,
        onNotDone: (v) => setState(() {
          _paco2NotDone = v;
          if (v) {
            _paco2LowCtrl.clear();
            _paco2HighCtrl.clear();
          }
        }),
      ),
      _yn('11. Surfactant given', _surfactant, editable,
          (v) => setState(() => _surfactant = v), c),
      _yn('12. Caffeine', _caffeine, editable,
          (v) => setState(() => _caffeine = v), c),
      _fieldCard(
        c,
        number: '13',
        label: 'No of Apnea episodes',
        child: _textField(_apneaCtrl, c,
            enabled: editable,
            keyboard: TextInputType.number,
            error: RespCvNeuroValidators.count(_apneaCtrl.text,
                max: 50, label: 'Apnea episode count')),
      ),
      _fieldCard(
        c,
        number: '14',
        label: 'No of Desaturations (<91%)',
        child: _textField(_desatCtrl, c,
            enabled: editable,
            keyboard: TextInputType.number,
            error: RespCvNeuroValidators.count(_desatCtrl.text,
                max: 50, label: 'Desaturation count')),
      ),
      _fieldCard(
        c,
        number: '15',
        label: 'No of severe desaturations (<80%)',
        child: _textField(_severeDesatCtrl, c,
            enabled: editable,
            keyboard: TextInputType.number,
            error: severeErr),
      ),
      _yn('16. Extubation attempted', _extubAttempted, editable, (v) {
        setState(() {
          _extubAttempted = v;
          if (v != true) _extubFailure = null;
        });
      }, c),
      _yn(
        '17. Extubation failure (<72h from extubation)',
        _extubFailure,
        editable && _extubAttempted == true,
        (v) => setState(() => _extubFailure = v),
        c,
        hint: _extubAttempted == true
            ? null
            : 'Enabled once Extubation attempted (#16) is Yes',
      ),
      _yn('18. Pulmonary hemorrhage', _pulmHemorrhage, editable,
          (v) => setState(() => _pulmHemorrhage = v), c),
      _yn('19. Pneumothorax', _pneumothorax, editable,
          (v) => setState(() => _pneumothorax = v), c),
      _yn('20. Chest drain in situ', _chestDrain, editable,
          (v) => setState(() => _chestDrain = v), c),
      _yn('21. Pulmonary HTN (PPHN)', _pphn, editable,
          (v) => setState(() => _pphn = v), c),
      _yn('22. Postnatal steroids', _postnatalSteroids, editable,
          (v) => setState(() => _postnatalSteroids = v), c),
    ];
  }

  List<Widget> _cvFields(AppColors c, bool editable) {
    return [
      _yn('23. PDA suspected/confirmed', _pdaSuspected, editable,
          (v) => setState(() => _pdaSuspected = v), c),
      _yn('24. Echo done', _echoDone, editable,
          (v) => setState(() => _echoDone = v), c),
      _yn('25. HS-PDA', _hsPda, editable, (v) => setState(() => _hsPda = v),
          c),
      _yn('26. Shock', _shock, editable, (v) => setState(() => _shock = v),
          c),
      _yn('27. Vasoactives', _vasoactiveSupport, editable, (v) {
        setState(() {
          _vasoactiveSupport = v;
          if (v != true) _vasoactiveDrugs = [];
        });
      }, c),
      if (_vasoactiveSupport == true)
        _fieldCard(
          c,
          number: '28',
          label: 'Vasoactive type (select all that apply)',
          child: _pills(
            RespCvNeuroDay.vasoactiveDrugOptions,
            _vasoactiveDrugs,
            editable,
            (next) => setState(() => _vasoactiveDrugs = next),
            c,
          ),
        ),
      _fieldCard(
        c,
        number: '29',
        label: 'Fluid bolus',
        child: _textField(_fluidBolusCtrl, c,
            enabled: editable,
            hint: 'e.g. 10ml/kg NS',
            error: RespCvNeuroValidators.fluidBolus(_fluidBolusCtrl.text)),
      ),
    ];
  }

  List<Widget> _neuroFields(AppColors c, bool editable) {
    final usgYes = _cranialUsg == true;
    return [
      _yn('30. Cranial USG done', _cranialUsg, editable, (v) {
        setState(() {
          _cranialUsg = v;
          if (v != true) {
            _ivh = null;
            _ivhGrade = null;
            _cpvlConfirmed = null;
            _ventriculomegaly = null;
          }
        });
      }, c),
      if (usgYes) ...[
        _yn('31. IVH (any grade)', _ivh, editable, (v) {
          setState(() {
            _ivh = v;
            if (v != true) _ivhGrade = null;
          });
        }, c),
        if (_ivh == true)
          _fieldCard(
            c,
            number: '',
            label: 'IVH Grade',
            child: Wrap(
              spacing: 8,
              children: RespCvNeuroDay.ivhGradeOptions.map((g) {
                final sel = _ivhGrade == g;
                return ChoiceChip(
                  label: Text(g),
                  selected: sel,
                  onSelected: !editable
                      ? null
                      : (_) => setState(
                          () => _ivhGrade = sel ? null : g),
                );
              }).toList(),
            ),
          ),
        _yn('32. cPVL (any grade)', _cpvlConfirmed, editable,
            (v) => setState(() => _cpvlConfirmed = v), c),
        _yn('33. Ventriculomegaly', _ventriculomegaly, editable,
            (v) => setState(() => _ventriculomegaly = v), c),
      ],
      _yn('34. Seizures (clinical)', _clinicalSeizures, editable,
          (v) => setState(() => _clinicalSeizures = v), c),
      _yn('35. Seizures (EEG confirmed)', _eegSeizures, editable,
          (v) => setState(() => _eegSeizures = v), c),
      _yn('36. AEDs given', _aedsGiven, editable,
          (v) => setState(() => _aedsGiven = v), c),
      _yn('37. Non-IVH ICH', _nonIvhIch, editable,
          (v) => setState(() => _nonIvhIch = v), c),
    ];
  }

  Widget _bottomBar(AppColors c) {
    final canEdit = _isFieldEditable ||
        (_recordExists &&
            (!_isSubmitted || _isOverrideActive) &&
            !_isFutureDay);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.borderLight)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_saving || !canEdit || (_isSubmitted && !_isOverrideActive))
                    ? null
                    : () {
                        setState(() => _isEditing = true);
                        _save(forLater: true);
                      },
                child: const Text('Save for Later'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: (_saving || !canEdit || (_isSubmitted && !_isOverrideActive))
                    ? null
                    : () {
                        setState(() => _isEditing = true);
                        _save();
                      },
                style: ElevatedButton.styleFrom(backgroundColor: c.primary),
                child: Text(
                  _saving ? 'Saving…' : 'Save',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_canSubmit) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: c.success),
                  child: Text(
                    _submitting ? '…' : 'Submit',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Small widgets ────────────────────────────────────────────────────────

  Widget _section(
    AppColors c, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: c.textPrimary)),
              ],
            ),
          ),
          Divider(height: 1, color: c.borderLight),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _fieldCard(
    AppColors c, {
    required String number,
    required String label,
    String? hint,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number.isEmpty ? label : '$number. $label',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: c.textPrimary),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: TextStyle(fontSize: 11, color: c.textTertiary)),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _yn(
    String label,
    bool? value,
    bool enabled,
    ValueChanged<bool?> onChanged,
    AppColors c, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: c.textPrimary)),
                if (hint != null)
                  Text(hint,
                      style:
                          TextStyle(fontSize: 11, color: c.textTertiary)),
              ],
            ),
          ),
          _ynToggle(value, enabled, onChanged, c),
        ],
      ),
    );
  }

  Widget _ynToggle(
    bool? value,
    bool enabled,
    ValueChanged<bool?> onChanged,
    AppColors c,
  ) {
    Widget btn(String text, bool? target, Color activeColor) {
      final active = value == target;
      return InkWell(
        onTap: !enabled
            ? null
            : () => onChanged(active ? null : target),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? activeColor : c.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? activeColor : c.border),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : c.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn('Yes', true, c.success),
        const SizedBox(width: 6),
        btn('No', false, c.danger),
      ],
    );
  }

  Widget _pills(
    List<String> options,
    List<String> selected,
    bool enabled,
    ValueChanged<List<String>> onChanged,
    AppColors c, {
    Map<String, String> labels = const {},
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final sel = selected.contains(o);
        return FilterChip(
          label: Text(labels[o] ?? o),
          selected: sel,
          onSelected: !enabled
              ? null
              : (v) {
                  final next = List<String>.from(selected);
                  if (v) {
                    next.add(o);
                  } else {
                    next.remove(o);
                  }
                  onChanged(next);
                },
        );
      }).toList(),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    AppColors c, {
    bool enabled = true,
    String? hint,
    String? error,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: enabled ? c.surfaceAlt : c.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.border),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error,
              style: TextStyle(color: c.warning, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _bloodGasField(
    AppColors c, {
    required String number,
    required String label,
    required String unit,
    required TextEditingController low,
    required TextEditingController high,
    required bool notDone,
    required bool editable,
    required double min,
    required double max,
    required ValueChanged<bool> onNotDone,
  }) {
    final lowErr = notDone
        ? null
        : RespCvNeuroValidators.bloodGasValue(low.text,
            min: min, max: max, label: '$label lowest');
    final highErr = notDone
        ? null
        : RespCvNeuroValidators.bloodGasValue(high.text,
            min: min, max: max, label: '$label highest');
    final orderErr =
        notDone ? null : RespCvNeuroValidators.rangeOrder(low.text, high.text);
    final err = lowErr ?? highErr ?? orderErr;

    return _fieldCard(
      c,
      number: number,
      label: '$label $unit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _textField(low, c,
                    enabled: editable && !notDone,
                    hint: 'Lowest',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('–', style: TextStyle(color: c.textSecondary)),
              ),
              Expanded(
                child: _textField(high, c,
                    enabled: editable && !notDone,
                    hint: 'Highest',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilterChip(
            label: const Text('Not Done'),
            selected: notDone,
            onSelected: !editable ? null : (v) => onNotDone(v),
          ),
          if (err != null) ...[
            const SizedBox(height: 4),
            Text(err, style: TextStyle(color: c.warning, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  static String _month(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return names[m - 1];
  }
}