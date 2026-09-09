// lib/screens/helper_form4_metab_renal_vasc_eye.dart
//
// Helper Form 4 — Metab / Renal / Vasc / Eye Daily Log
// Parity with web MetabRenalVascEyeLog.jsx + Form 2 day-shell UX.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/metab_renal_vasc_eye_day.dart';
import '../services/forms_api_service.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';

const _glucoseLowMax = 45.0;
const _glucoseHighMin = 180.0;

/// Helper 5 `met_a[].glucose` → readings (web `parseMetAGlucoseReadings`).
/// Flat `glucose` is only used when `entries_json` is missing (legacy).
List<double> _parseHelper5Glucose(Map<String, dynamic> data) {
  dynamic entries = data['entries_json'];
  if (entries is String) {
    try {
      entries = jsonDecode(entries);
    } catch (_) {
      entries = null;
    }
  }
  if (entries is Map && entries['met_a'] is List) {
    final out = <double>[];
    for (final row in entries['met_a'] as List) {
      if (row is! Map) continue;
      final raw = row['glucose'];
      if (raw == null || raw.toString().trim().isEmpty) continue;
      final n = double.tryParse(raw.toString());
      if (n != null) out.add(n);
    }
    // Empty met_a is valid — do not fall back to a stale flat column.
    return out;
  }
  final flat = data['glucose'];
  if (flat != null && flat.toString().trim().isNotEmpty) {
    final n = double.tryParse(flat.toString());
    if (n != null) return [n];
  }
  return [];
}

/// Same rules as web: &lt;45 low, 45–180 normal, &gt;180 high.
Map<String, String> _computeGlucoseAutofill(List<double> readings) {
  if (readings.isEmpty) {
    return {
      'lowest_glucose': 'Not Tested',
      'hypoglycemia_episodes': '0',
      'highest_glucose': 'Not Tested',
    };
  }
  final lows = readings.where((v) => v < _glucoseLowMax).toList();
  final highs = readings.where((v) => v > _glucoseHighMin).toList();
  String fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';
  return {
    'lowest_glucose':
        lows.isEmpty ? 'Not Low' : fmt(lows.reduce((a, b) => a < b ? a : b)),
    'hypoglycemia_episodes': '${lows.length}',
    'highest_glucose':
        highs.isEmpty ? 'Not High' : fmt(highs.reduce((a, b) => a > b ? a : b)),
  };
}

bool _isEmptyGlucoseField(String? v) =>
    v == null || v.trim().isEmpty;

class HelperForm4MetabRenalVascEye extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  final String site;

  const HelperForm4MetabRenalVascEye({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.site = 'PGIMER',
  });

  @override
  State<HelperForm4MetabRenalVascEye> createState() =>
      _HelperForm4MetabRenalVascEyeState();
}

class _HelperForm4MetabRenalVascEyeState
    extends State<HelperForm4MetabRenalVascEye> {
  static const _lateGraceHour = 11;

  final _api = FormsApiService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _dayLoading = false;
  bool _glucoseRefreshing = false;
  String? _banner;
  bool _bannerError = false;

  DateTime? _day1Date;
  bool _day1Locked = false;
  int _totalDays = 14;
  int _activeDay = 1;
  int _todayNicuDay = 1;

  final Map<int, String> _dayStatus = {};
  final Map<int, int> _dayPct = {};

  bool _recordExists = false;
  bool _isEditing = true;
  bool _isSubmitted = false;
  /// Site-monitor override expiry for the active day (mirrors web's
  /// `overrideUntil` — reopens an otherwise-submitted/locked day for a
  /// limited window). Parsed from `override_unlocked_until`.
  DateTime? _overrideUntil;
  bool _dayLoadFailed = false;
  int _loadGen = 0;

  MetabRenalVascEyeDay _model = MetabRenalVascEyeDay(
    enrollmentId: '',
    nicuDay: 1,
  );

  final Map<String, bool> _glucoseAutofilled = {
    'lowest_glucose': false,
    'hypoglycemia_episodes': false,
    'highest_glucose': false,
  };

  int? _glucoseAutoDoneDay;

  final _lowGlucoseCtrl = TextEditingController();
  final _hypoEpisodesCtrl = TextEditingController();
  final _highGlucoseCtrl = TextEditingController();
  final _creatinineCtrl = TextEditingController();
  final _axillaryCtrl = TextEditingController();
  final _urine8am2pmCtrl = TextEditingController();
  final _urine2pm8pmCtrl = TextEditingController();
  final _urine8pm8amCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [
      _lowGlucoseCtrl,
      _hypoEpisodesCtrl,
      _highGlucoseCtrl,
      _creatinineCtrl,
      _axillaryCtrl,
      _urine8am2pmCtrl,
      _urine2pm8pmCtrl,
      _urine8pm8amCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in [
      _lowGlucoseCtrl,
      _hypoEpisodesCtrl,
      _highGlucoseCtrl,
      _creatinineCtrl,
      _axillaryCtrl,
      _urine8am2pmCtrl,
      _urine2pm8pmCtrl,
      _urine8pm8amCtrl,
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

  String? get _activeDayYmd {
    final cal = _calendarForDay(_activeDay);
    if (cal == null) return null;
    return '${cal.year.toString().padLeft(4, '0')}-'
        '${cal.month.toString().padLeft(2, '0')}-'
        '${cal.day.toString().padLeft(2, '0')}';
  }

  String get _todayYmd {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  bool get _isActiveDayToday =>
      _activeDayYmd != null && _activeDayYmd == _todayYmd;

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

      final summary = await _api.loadMetabRenalVascEyeSummary(eid);
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

  MetabRenalVascEyeDay _buildModel() {
    final m = MetabRenalVascEyeDay(
      enrollmentId: widget.enrollmentId.trim(),
      nicuDay: _activeDay,
    );
    m.lowestGlucose =
        _lowGlucoseCtrl.text.trim().isEmpty ? null : _lowGlucoseCtrl.text.trim();
    m.hypoglycemiaEpisodes = _hypoEpisodesCtrl.text.trim().isEmpty
        ? null
        : _hypoEpisodesCtrl.text.trim();
    m.hypoglycemiaRx = _model.hypoglycemiaRx;
    m.highestGlucose = _highGlucoseCtrl.text.trim().isEmpty
        ? null
        : _highGlucoseCtrl.text.trim();
    m.insulin = _model.insulin;
    m.osteopeniaSuspected = _model.osteopeniaSuspected;
    m.phReadings = _model.phReadings
        .map((r) => MrveReading(
            id: r.id, date: r.date, time: r.time, value: r.value))
        .toList();
    m.sodiumReadings = _model.sodiumReadings
        .map((r) => MrveReading(
            id: r.id, date: r.date, time: r.time, value: r.value))
        .toList();
    m.potassiumReadings = _model.potassiumReadings
        .map((r) => MrveReading(
            id: r.id, date: r.date, time: r.time, value: r.value))
        .toList();
    m.calciumReadings = _model.calciumReadings
        .map((r) => MrveReading(
            id: r.id, date: r.date, time: r.time, value: r.value))
        .toList();
    m.akiSuspected = _model.akiSuspected;
    m.creatinineValue = _creatinineCtrl.text.trim().isEmpty
        ? null
        : _creatinineCtrl.text.trim();
    m.urineOutput8am2pm = double.tryParse(_urine8am2pmCtrl.text.trim());
    m.urineOutput2pm8pm = double.tryParse(_urine2pm8pmCtrl.text.trim());
    m.urineOutput8pm8am = double.tryParse(_urine8pm8amCtrl.text.trim());
    m.dialysisCrrt = _model.dialysisCrrt;
    m.axillaryTemperature =
        _axillaryCtrl.text.trim().isEmpty ? null : _axillaryCtrl.text.trim();
    m.piccInSitu = _model.piccInSitu;
    m.uvcInSitu = _model.uvcInSitu;
    m.uacInSitu = _model.uacInSitu;
    m.peripheralIv = _model.peripheralIv;
    m.peripheralArterial = _model.peripheralArterial;
    m.extravasationInjury = _model.extravasationInjury;
    m.lineComplication = _model.lineComplication;
    m.ropScreeningDue = _model.ropScreeningDue;
    m.ropScreened = _model.ropScreened;
    m.ropDetected = _model.ropDetected;
    m.ropStage = _model.ropStage;
    m.plusDisease = _model.plusDisease;
    m.ropTreatment = _model.ropTreatment;
    m.location = _model.location;
    m.survivedTheDay = _model.survivedTheDay;
    m.recomputeDerived();
    return m;
  }

  MetabRenalVascEyeCompletion get _completion =>
      MetabRenalVascEyeCompletion.compute(_buildModel());

  bool get _canSubmit =>
      _completion.percent == 100 &&
      (!_isSubmitted || _isOverrideActive) &&
      !_isFutureDay;

  double get _hypoEpisodes =>
      double.tryParse(_hypoEpisodesCtrl.text.trim()) ?? 0;

  bool get _hypoRxRequired => _hypoEpisodes > 0;

  bool get _hyperRxRequired =>
      MetabRenalVascEyeDay.isNumericHighGlucose(_highGlucoseCtrl.text);

  bool get _extravasationRequired =>
      _model.peripheralIv == true || _model.peripheralArterial == true;

  bool get _ropDue => _model.ropScreeningDue == true;
  bool get _ropScreenedYes => _model.ropScreened == true;
  bool get _ropYes => _model.ropDetected == true;

  MrveReading _blankReading({String value = ''}) {
    final now = DateTime.now();
    return MrveReading(
      date: '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}',
      time: '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
      value: value,
    );
  }

  List<MrveReading> _ensureReadings(List<MrveReading> list) =>
      list.isEmpty ? [_blankReading()] : list;

  Future<void> _loadActiveDay() async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return;
    final day = _activeDay;
    final gen = ++_loadGen;
    setState(() => _dayLoading = true);
    _glucoseAutofilled.updateAll((_, __) => false);
    try {
      final raw = await _api.loadMetabRenalVascEyeDay(eid, day);
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      if (raw == null) {
        _clearForm();
        _recordExists = false;
        _isEditing = true;
        _isSubmitted = false;
        _overrideUntil = null;
        _dayLoadFailed = false;
        if (_isActiveDayToday && _glucoseAutoDoneDay != day) {
          _glucoseAutoDoneDay = day;
          await _applyGlucoseAutofill(force: false);
        }
      } else {
        _applyDay(MetabRenalVascEyeDay.fromJson(raw));
        _recordExists = true;
        _isSubmitted = raw['submission_status']?.toString() == 'submitted';
        _overrideUntil = _parseUtc(raw['override_unlocked_until']);
        _isEditing = _isOverrideActive;
        _dayLoadFailed = false;
        if (_isActiveDayToday && _glucoseAutoDoneDay != day) {
          _glucoseAutoDoneDay = day;
          await _applyGlucoseAutofill(force: false);
        }
      }
    } catch (e) {
      if (!mounted || gen != _loadGen || day != _activeDay) return;
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
    _lowGlucoseCtrl.clear();
    _hypoEpisodesCtrl.clear();
    _highGlucoseCtrl.clear();
    _creatinineCtrl.clear();
    _axillaryCtrl.clear();
    _urine8am2pmCtrl.clear();
    _urine2pm8pmCtrl.clear();
    _urine8pm8amCtrl.clear();
    _model = MetabRenalVascEyeDay(
      enrollmentId: widget.enrollmentId.trim(),
      nicuDay: _activeDay,
    );
    _model.phReadings = [_blankReading()];
    _model.sodiumReadings = [_blankReading()];
    _model.potassiumReadings = [_blankReading()];
    _model.calciumReadings = [_blankReading()];
    _glucoseAutofilled.updateAll((_, __) => false);
  }

  void _applyDay(MetabRenalVascEyeDay d) {
    // Do NOT recomputeDerived on load — that wiped stored metabolic_acidosis
    // when ph_readings_json was empty (legacy / summary-only rows).
    _model = d;
    _model.nicuDay = _activeDay;
    _model.phReadings = _ensureReadings(d.phReadings);
    _model.sodiumReadings = _ensureReadings(d.sodiumReadings);
    _model.potassiumReadings = _ensureReadings(d.potassiumReadings);
    _model.calciumReadings = _ensureReadings(d.calciumReadings);
    _lowGlucoseCtrl.text = d.lowestGlucose ?? '';
    _hypoEpisodesCtrl.text = d.hypoglycemiaEpisodes ?? '';
    _highGlucoseCtrl.text = d.highestGlucose ?? '';
    _creatinineCtrl.text = d.creatinineValue ?? '';
    _axillaryCtrl.text = d.axillaryTemperature ?? '';
    _urine8am2pmCtrl.text = d.urineOutput8am2pm?.toString() ?? '';
    _urine2pm8pmCtrl.text = d.urineOutput2pm8pm?.toString() ?? '';
    _urine8pm8amCtrl.text = d.urineOutput8pm8am?.toString() ?? '';
  }

  Future<bool> _applyGlucoseAutofill({required bool force}) async {
    // Web: only when this NICU day is calendar-today, and Helper 5
    // record_date matches that same calendar date (boundary_hour=11 on API).
    if (!_isActiveDayToday || _activeDayYmd == null) return false;
    try {
      final data =
          await _api.loadMinimalMonitoringToday(widget.enrollmentId.trim());
      final recordDate = data['record_date']?.toString();
      if (recordDate != null &&
          recordDate.isNotEmpty &&
          recordDate.substring(0, 10) != _activeDayYmd) {
        return false;
      }

      final computed = _computeGlucoseAutofill(_parseHelper5Glucose(data));
      final flags = <String, bool>{
        'lowest_glucose': false,
        'hypoglycemia_episodes': false,
        'highest_glucose': false,
      };

      if (force || _isEmptyGlucoseField(_lowGlucoseCtrl.text)) {
        _lowGlucoseCtrl.text = computed['lowest_glucose']!;
        flags['lowest_glucose'] = true;
      }
      if (force || _isEmptyGlucoseField(_hypoEpisodesCtrl.text)) {
        _hypoEpisodesCtrl.text = computed['hypoglycemia_episodes']!;
        flags['hypoglycemia_episodes'] = true;
      }
      if (force || _isEmptyGlucoseField(_highGlucoseCtrl.text)) {
        _highGlucoseCtrl.text = computed['highest_glucose']!;
        flags['highest_glucose'] = true;
      }

      final changed = flags.values.any((v) => v);
      if (!changed) return false;

      final ep = double.tryParse(_hypoEpisodesCtrl.text.trim()) ?? 0;
      if (ep <= 0) _model.hypoglycemiaRx = null;
      if (!MetabRenalVascEyeDay.isNumericHighGlucose(_highGlucoseCtrl.text)) {
        _model.insulin = null;
      }
      _model.lowestGlucose = _lowGlucoseCtrl.text.trim();
      _model.hypoglycemiaEpisodes = _hypoEpisodesCtrl.text.trim();
      _model.highestGlucose = _highGlucoseCtrl.text.trim();

      if (mounted) {
        setState(() {
          for (final e in flags.entries) {
            if (e.value) {
              _glucoseAutofilled[e.key] = true;
            } else if (force) {
              _glucoseAutofilled[e.key] = false;
            }
          }
          _isEditing = true;
        });
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshGlucoseFromHelper5() async {
    if (!_isFieldEditable || !_isActiveDayToday) return;
    setState(() => _glucoseRefreshing = true);
    try {
      final ok = await _applyGlucoseAutofill(force: true);
      _toast(ok
          ? 'Glucose fields refreshed from Helper 5'
          : 'No matching Helper 5 glucose sheet for today',
          error: !ok);
    } finally {
      if (mounted) setState(() => _glucoseRefreshing = false);
    }
  }

  void _applyClearGating(MetabRenalVascEyeDay m) {
    final ep = double.tryParse(m.hypoglycemiaEpisodes?.trim() ?? '') ?? 0;
    if (ep <= 0) m.hypoglycemiaRx = null;
    if (!MetabRenalVascEyeDay.isNumericHighGlucose(m.highestGlucose)) {
      m.insulin = null;
    }
    if (m.peripheralIv != true && m.peripheralArterial != true) {
      m.extravasationInjury = null;
    }
    if (m.ropScreeningDue != true) {
      m.ropScreened = null;
      m.ropDetected = null;
      m.ropStage = null;
      m.plusDisease = null;
      m.ropTreatment = null;
    } else if (m.ropScreened != true) {
      m.ropDetected = null;
      m.ropStage = null;
      m.plusDisease = null;
      m.ropTreatment = null;
    } else if (m.ropDetected != true) {
      m.ropStage = null;
      m.plusDisease = null;
      m.ropTreatment = null;
    }
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
      final raw = await _api.loadMetabRenalVascEyeDay(
          widget.enrollmentId.trim(), _activeDay - 1);
      if (raw == null) {
        _toast('No data on Day ${_activeDay - 1} to copy', error: true);
        return;
      }
      final src = MetabRenalVascEyeDay.fromJson(raw);
      final cur = _buildModel()..copyClinicalFrom(src);
      setState(() {
        _applyDay(cur);
        _recordExists = false;
        _isEditing = true;
        _glucoseAutofilled.updateAll((_, __) => false);
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
      _applyClearGating(model);
      model.recomputeDerived();

      final body = model.toJson(
        submissionStatus: 'draft',
        savedAt: now,
        savedBy: name,
      );
      await _api.saveMetabRenalVascEyeDay(body, alreadyExists: _recordExists);
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
      final saved = await _save(force: true);
      if (!saved) {
        setState(() {
          _banner = 'Submit cancelled — save current day data first';
          _bannerError = true;
        });
        return;
      }
      final name = await _nurseName();
      await _api.submitMetabRenalVascEyeDay(
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

  void _updateReading(List<MrveReading> list, int i, String field, String v) {
    if (!_isFieldEditable) return;
    setState(() {
      if (field == 'date') list[i].date = v;
      if (field == 'time') list[i].time = v;
      if (field == 'value') list[i].value = v;
      final m = _buildModel();
      _model.metabolicAcidosis = m.metabolicAcidosis;
      _model.sodiumValue = m.sodiumValue;
      _model.potassiumValue = m.potassiumValue;
      _model.ionizedCalciumValue = m.ionizedCalciumValue;
    });
  }

  void _addReading(List<MrveReading> list) {
    if (!_isFieldEditable) return;
    setState(() => list.add(_blankReading()));
  }

  void _removeReading(List<MrveReading> list, int i) {
    if (!_isFieldEditable || list.length <= 1) return;
    setState(() {
      list.removeAt(i);
      final m = _buildModel();
      _model.metabolicAcidosis = m.metabolicAcidosis;
      _model.sodiumValue = m.sodiumValue;
      _model.potassiumValue = m.potassiumValue;
      _model.ionizedCalciumValue = m.ionizedCalciumValue;
    });
  }

  String get _urineTotalDisplay {
    final m = _buildModel();
    return m.urineOutputTotal ?? '—';
  }

  String get _acidosisDisplay {
    final v = _buildModel().metabolicAcidosis;
    if (v == true) return 'Yes';
    if (v == false) return 'No';
    return '—';
  }

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
                          _section(
                            c,
                            title: '4.1 Metabolic',
                            icon: Icons.bolt_rounded,
                            color: c.warning,
                            headerAction: _isActiveDayToday
                                ? TextButton.icon(
                                    onPressed: (!_glucoseRefreshing && editable)
                                        ? _refreshGlucoseFromHelper5
                                        : null,
                                    icon: _glucoseRefreshing
                                        ? SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: c.primary,
                                            ),
                                          )
                                        : const Icon(Icons.refresh, size: 16),
                                    label: Text(_glucoseRefreshing
                                        ? 'Refreshing…'
                                        : 'Refresh from Helper 5'),
                                  )
                                : null,
                            children: _metabolicFields(c, editable),
                          ),
                          _section(
                            c,
                            title: '4.2 Renal',
                            icon: Icons.water_drop_outlined,
                            color: c.primary,
                            children: _renalFields(c, editable),
                          ),
                          _section(
                            c,
                            title: '4.3 Thermoregulation',
                            icon: Icons.thermostat_outlined,
                            color: c.danger,
                            children: _thermoFields(c, editable),
                          ),
                          _section(
                            c,
                            title: '4.4 Vascular Access',
                            icon: Icons.medical_services_outlined,
                            color: c.purple,
                            children: _vascularFields(c, editable),
                          ),
                          _section(
                            c,
                            title: '4.5 Ophthalmology (ROP)',
                            icon: Icons.visibility_outlined,
                            color: c.success,
                            children: _eyeFields(c, editable),
                          ),
                          _section(
                            c,
                            title: '4.6 Location',
                            icon: Icons.place_outlined,
                            color: c.primary,
                            children: [
                              _fieldCard(
                                c,
                                number: '',
                                label: 'Location',
                                hint: 'Select all that apply',
                                child: _pillsMulti(
                                  MetabRenalVascEyeDay.locationOptions,
                                  _model.location,
                                  editable,
                                  (v) => setState(() => _model.location = v),
                                  c,
                                ),
                              ),
                            ],
                          ),
                          _section(
                            c,
                            title: '4.7 Survived the Day',
                            icon: Icons.check_circle_outline,
                            color: c.success,
                            children: [
                              _yn('Survived the day', _model.survivedTheDay,
                                  editable, (v) {
                                setState(() => _model.survivedTheDay = v);
                              }, c),
                            ],
                          ),
                        ],
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(c),
    );
  }

  List<Widget> _metabolicFields(AppColors c, bool editable) {
    return [
      _glucoseField(c, '1', 'Lowest glucose reading (if <45 mg/dL)',
          _lowGlucoseCtrl, editable, 'mg/dL', _glucoseAutofilled['lowest_glucose']!),
      _glucoseField(c, '2', 'No of episodes of hypoglycemia', _hypoEpisodesCtrl,
          editable, null, _glucoseAutofilled['hypoglycemia_episodes']!),
      if (_hypoRxRequired)
        _yn('3. Hypoglycemia Rx', _model.hypoglycemiaRx, editable, (v) {
          setState(() => _model.hypoglycemiaRx = v);
        }, c),
      _glucoseField(c, '4', 'Highest glucose reading (if >180 mg/dL)',
          _highGlucoseCtrl, editable, 'mg/dL', _glucoseAutofilled['highest_glucose']!),
      if (_hyperRxRequired)
        _yn('5. Hyperglycemia Rx (Insulin)', _model.insulin, editable, (v) {
          setState(() => _model.insulin = v);
        }, c),
      _readingsBlock(
        c,
        title: '6. Metabolic acidosis (pH<7.2) — enter readings',
        code: 'pH',
        readings: _model.phReadings,
        editable: editable,
        unit: '',
      ),
      _fieldCard(
        c,
        number: '',
        label: 'Metabolic acidosis (auto)',
        child: Text(_acidosisDisplay,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: c.textPrimary)),
      ),
      _readingsBlock(
        c,
        title: '7. Sodium value (<135 or >142)',
        code: 'Na',
        readings: _model.sodiumReadings,
        editable: editable,
        unit: 'mmol/L',
      ),
      if (_model.sodiumValue?.trim().isNotEmpty ?? false)
        _summaryChip(c, 'Latest Na: ${_model.sodiumValue} mmol/L'),
      _readingsBlock(
        c,
        title: '8. Potassium value (<3.5 or >6)',
        code: 'K',
        readings: _model.potassiumReadings,
        editable: editable,
        unit: 'mmol/L',
      ),
      if (_model.potassiumValue?.trim().isNotEmpty ?? false)
        _summaryChip(c, 'Latest K: ${_model.potassiumValue} mmol/L'),
      _readingsBlock(
        c,
        title: '9. Ionized Calcium value (<0.9 or >1.2)',
        code: 'iCa',
        readings: _model.calciumReadings,
        editable: editable,
        unit: 'mmol/L',
      ),
      if (_model.ionizedCalciumValue?.trim().isNotEmpty ?? false)
        _summaryChip(c, 'Latest iCa: ${_model.ionizedCalciumValue} mmol/L'),
      _yn('10. Osteopenia suspected', _model.osteopeniaSuspected, editable,
          (v) => setState(() => _model.osteopeniaSuspected = v), c),
    ];
  }

  List<Widget> _renalFields(AppColors c, bool editable) {
    return [
      // KDIGO stage removed to match web — only AKI suspected Y/N is
      // captured now (MetabRenalVascEyeLog.jsx no longer collects it).
      _yn('11. AKI suspected', _model.akiSuspected, editable,
          (v) => setState(() => _model.akiSuspected = v), c),
      _fieldCard(
        c,
        number: '12',
        label: 'Serum Creatinine',
        hint: 'value / Not Tested / Awaited',
        child: _textField(_creatinineCtrl, c,
            enabled: editable, hint: 'mg/dL'),
      ),
      _fieldCard(
        c,
        number: '13a',
        label: 'Urine output 8am → 2pm',
        child: _textField(_urine8am2pmCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: 'ml/kg/hr'),
      ),
      _fieldCard(
        c,
        number: '13b',
        label: 'Urine output 2pm → 8pm',
        child: _textField(_urine2pm8pmCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: 'ml/kg/hr'),
      ),
      _fieldCard(
        c,
        number: '13c',
        label: 'Urine output 8pm → 8am',
        child: _textField(_urine8pm8amCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: 'ml/kg/hr'),
      ),
      _fieldCard(
        c,
        number: '13',
        label: 'Urine output total (sum)',
        child: Text('$_urineTotalDisplay ml/kg/hr',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: c.textSecondary)),
      ),
      _yn('14. Dialysis/CRRT', _model.dialysisCrrt, editable,
          (v) => setState(() => _model.dialysisCrrt = v), c),
    ];
  }

  List<Widget> _thermoFields(AppColors c, bool editable) {
    return [
      _fieldCard(
        c,
        number: '15',
        label: 'Axillary Temperature (<36.5 or >37.5)',
        child: _textField(_axillaryCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '°C'),
      ),
    ];
  }

  List<Widget> _vascularFields(AppColors c, bool editable) {
    return [
      _yn('16. PICC in situ', _model.piccInSitu, editable,
          (v) => setState(() => _model.piccInSitu = v), c),
      _yn('17. UVC in situ', _model.uvcInSitu, editable,
          (v) => setState(() => _model.uvcInSitu = v), c),
      _yn('18. UAC in situ', _model.uacInSitu, editable,
          (v) => setState(() => _model.uacInSitu = v), c),
      _yn('19. Peripheral IV', _model.peripheralIv, editable, (v) {
        setState(() {
          _model.peripheralIv = v;
          if (v != true && _model.peripheralArterial != true) {
            _model.extravasationInjury = null;
          }
        });
      }, c),
      _yn('20. Peripheral arterial', _model.peripheralArterial, editable, (v) {
        setState(() {
          _model.peripheralArterial = v;
          if (v != true && _model.peripheralIv != true) {
            _model.extravasationInjury = null;
          }
        });
      }, c),
      if (_extravasationRequired)
        _yn('21. Extravasation injury', _model.extravasationInjury, editable,
            (v) => setState(() => _model.extravasationInjury = v), c),
      _yn('22. Line complication', _model.lineComplication, editable,
          (v) => setState(() => _model.lineComplication = v), c),
    ];
  }

  List<Widget> _eyeFields(AppColors c, bool editable) {
    return [
      _yn('23. ROP screening due', _model.ropScreeningDue, editable, (v) {
        setState(() {
          _model.ropScreeningDue = v;
          if (v != true) {
            _model.ropScreened = null;
            _model.ropDetected = null;
            _model.ropStage = null;
            _model.plusDisease = null;
            _model.ropTreatment = null;
          }
        });
      }, c),
      if (_ropDue)
        _yn('24. ROP screened', _model.ropScreened, editable, (v) {
          setState(() {
            _model.ropScreened = v;
            if (v != true) {
              _model.ropDetected = null;
              _model.ropStage = null;
              _model.plusDisease = null;
              _model.ropTreatment = null;
            }
          });
        }, c),
      if (_ropDue && _ropScreenedYes)
        _yn('25. ROP detected', _model.ropDetected, editable, (v) {
          setState(() {
            _model.ropDetected = v;
            if (v != true) {
              _model.ropStage = null;
              _model.plusDisease = null;
              _model.ropTreatment = null;
            }
          });
        }, c),
      if (_ropYes) ...[
        _yn('Plus Disease', _model.plusDisease, editable,
            (v) => setState(() => _model.plusDisease = v), c),
        _yn('ROP Treatment', _model.ropTreatment, editable,
            (v) => setState(() => _model.ropTreatment = v), c),
      ],
    ];
  }

  Widget _glucoseField(
    AppColors c,
    String number,
    String label,
    TextEditingController ctrl,
    bool editable,
    String? unit,
    bool autofilled,
  ) {
    return _fieldCard(
      c,
      number: number,
      label: label,
      hint: autofilled ? 'Auto-filled from Helper 5' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (autofilled)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Auto-filled from Helper 5',
                style: TextStyle(
                  color: c.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _textField(ctrl, c,
                    enabled: editable,
                    hint: 'Not Low / Not High / Not Tested / number'),
              ),
              if (unit != null) ...[
                const SizedBox(width: 8),
                Text(unit,
                    style: TextStyle(color: c.textTertiary, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _readingsBlock(
    AppColors c, {
    required String title,
    required String code,
    required List<MrveReading> readings,
    required bool editable,
    required String unit,
  }) {
    return _fieldCard(
      c,
      number: '',
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < readings.length; i++)
            _ReadingEntryRow(
              key: ValueKey(readings[i].id),
              code: code,
              index: i,
              reading: readings[i],
              unit: unit,
              editable: editable,
              canDelete: readings.length > 1,
              colors: c,
              onChanged: (field, v) => _updateReading(readings, i, field, v),
              onDelete: () => _removeReading(readings, i),
            ),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addReading(readings),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add reading'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(AppColors c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: c.textSecondary, fontStyle: FontStyle.italic)),
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
            widget.babyUid.isEmpty ? 'HELPER FORM 4' : widget.babyUid,
            style: TextStyle(
              color: c.primary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          Text(
            'Metab / Renal / Vasc / Eye · ${widget.motherName.isEmpty ? widget.enrollmentId : widget.motherName}',
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

  Widget _section(
    AppColors c, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
    Widget? headerAction,
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
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: c.textPrimary)),
                ),
                if (headerAction != null) headerAction,
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
            border: Border.all(color: active ? activeColor : c.border),
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

  Widget _singlePills(
    List<String> options,
    String? selected,
    bool enabled,
    ValueChanged<String?> onChanged,
    AppColors c,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final sel = selected == o;
        return FilterChip(
          label: Text(o),
          selected: sel,
          onSelected: !enabled
              ? null
              : (_) => onChanged(sel ? null : o),
        );
      }).toList(),
    );
  }

  /// Multi-select pills (e.g. Location) — matches web's PillMulti.
  Widget _pillsMulti(
    List<String> options,
    List<String> selected,
    bool enabled,
    ValueChanged<List<String>> onChanged,
    AppColors c,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final sel = selected.contains(o);
        return FilterChip(
          label: Text(o),
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
    TextInputType? keyboard,
  }) {
    return TextField(
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

class _ReadingEntryRow extends StatefulWidget {
  final String code;
  final int index;
  final MrveReading reading;
  final String unit;
  final bool editable;
  final bool canDelete;
  final AppColors colors;
  final void Function(String field, String value) onChanged;
  final VoidCallback onDelete;

  const _ReadingEntryRow({
    super.key,
    required this.code,
    required this.index,
    required this.reading,
    required this.unit,
    required this.editable,
    required this.canDelete,
    required this.colors,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ReadingEntryRow> createState() => _ReadingEntryRowState();
}

class _ReadingEntryRowState extends State<_ReadingEntryRow> {
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _valueCtrl;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: widget.reading.date);
    _timeCtrl = TextEditingController(text: widget.reading.time);
    _valueCtrl = TextEditingController(text: widget.reading.value);
  }

  @override
  void didUpdateWidget(covariant _ReadingEntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final r = widget.reading;
    final o = oldWidget.reading;
    if (o.id != r.id ||
        o.date != r.date ||
        o.time != r.time ||
        o.value != r.value) {
      _dateCtrl.text = r.date;
      _timeCtrl.text = r.time;
      _valueCtrl.text = r.value;
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.index > 0 || widget.canDelete)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Text('${widget.code} #${widget.index + 1}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: c.textTertiary)),
                const Spacer(),
                if (widget.canDelete && widget.editable)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
                    onPressed: widget.onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _dateCtrl,
                enabled: widget.editable,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  isDense: true,
                ),
                onChanged: (v) => widget.onChanged('date', v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _timeCtrl,
                enabled: widget.editable,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  isDense: true,
                ),
                onChanged: (v) => widget.onChanged('time', v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _valueCtrl,
                enabled: widget.editable,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.code,
                  isDense: true,
                  suffixText: widget.unit.isEmpty ? null : widget.unit,
                ),
                onChanged: (v) => widget.onChanged('value', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}