// lib/screens/helper_form3_infect_gi_hema.dart
//
// NAMING TRAP: this file / class is Helper Form 3 on mobile, but it is
// web sidebar Helper 4 (Infect / GI / Hema). Do not rename without a
// coordinated navigation pass.
//
// Helper Form 4 — Infection / GI / Hematology Daily Log
// Parity with web InfectGIHemaLog.jsx: fields 1–30, same sequence,
// same validations, same /infect-gi-hema/ API (NICU day, not calendar blob).
// #15 ml/kg/d = cumulative ml ÷ effective weight (DMS 5.7.A if recovered
// to/past Form B birth_weight, else birth_weight).

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/infect_gi_hema_day.dart';
import '../services/api_client.dart';
import '../services/forms_api_service.dart';
import '../services/helper_day_draft_storage.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../utils/form_b_local_guard.dart';
import '../utils/helper_day_strip.dart';
import '../utils/helper_dob_day1.dart';
import '../utils/helper_session.dart';
import '../utils/mml_helper_linkages.dart';
import '../utils/mml_resp_sync_bus.dart';
import '../navigation/helper_forms_navigation.dart';
import '../widgets/helper_patient_header.dart';
import '../widgets/helper_recent_day_strip.dart';
import '../widgets/theme_toggle_widget.dart';

const _kIghDraftKey = 'infect_gi_hema';

class HelperForm3InfectGIHema extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  final String site;
  final String screeningId;

  const HelperForm3InfectGIHema({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.site = 'PGIMER',
    this.screeningId = '',
  });

  @override
  State<HelperForm3InfectGIHema> createState() =>
      _HelperForm3InfectGIHemaState();
}

class _HelperForm3InfectGIHemaState extends State<HelperForm3InfectGIHema> {
  final _api = FormsApiService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _dayLoading = false;
  String? _banner;
  bool _bannerError = false;

  DateTime? _day1Date;
  int _totalDays = 14;
  int _activeDay = 1;
  int _todayNicuDay = 1;
  int _stripStart = 1;
  int? _dischargeDay;
  String _babyName = '';
  StreamSubscription<MmlRespSavedEvent>? _mmlSavedSub;
  Timer? _mmlPollTimer;

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

  /// Guards against day-chip race: only the latest load may apply UI state.
  int _loadGen = 0;
  String? _serverUpdatedAt;

  String? _lastFeedAutoDate;
  double? _lastFeedAutoValue;
  bool _feedVolumeAutofilled = false;
  String? _lastFeedVolCalcAutoDate;
  String? _lastFeedVolCalcAutoValue;
  bool _feedVolumeCalcAutofilled = false;
  double? _birthWeightGrams;
  bool _hemaPrbcAutofilled = false;
  bool _hemaPlateletAutofilled = false;
  bool _hemaFfpAutofilled = false;

  // Controllers
  final _cumulativeFeedCtrl = TextEditingController();
  final _feedVolumeCtrl = TextEditingController();
  final _hbCtrl = TextEditingController();
  final _peakTsbCtrl = TextEditingController();

  // Infection 1–9
  bool? _sepsisSuspected;
  bool? _bloodCultureSent;
  bool? _bloodCulturePositive;
  String? _bloodCultureStatus;
  bool? _antibiotics;
  bool? _lpDone;
  bool? _meningitis;
  String? _meningitisType;
  bool? _clabsi;
  bool? _vap;
  // Not part of the original numbered CRF sequence — sepsis screen gate +
  // repeatable entries (mirrors web's sepsis_screen_sent / sepsis_screens).
  bool? _sepsisScreenSent;
  List<SepsisScreenEntry> _sepsisScreens = [SepsisScreenEntry.blank()];

  // GI 10–22
  bool? _npo;
  bool? _men;
  bool? _enteralFeedsReceived;
  List<String> _feedType = [];
  String? _cumulativeFeedVolumeStatus;
  String? _feedVolumeStatus;
  bool? _ivFluids;
  bool? _parenteralNutrition;
  bool? _probiotic;
  bool? _feedIntolerance;
  bool? _necSuspected;
  String? _necConfirmedStage;
  bool? _cholestasis;

  // Hema 23–30
  String? _hbValueStatus;
  String? _peakTsbStatus;
  bool? _jaundice;
  bool? _phototherapy;
  bool? _exchangeTransfusion;
  bool? _prbcTransfusion;
  bool? _plateletTransfusion;
  bool? _ffpCryo;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _cumulativeFeedCtrl,
      _feedVolumeCtrl,
      _hbCtrl,
      _peakTsbCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _mmlSavedSub = MmlRespSyncBus.stream.listen((e) {
      if (e.enrollmentId != widget.enrollmentId.trim()) return;
      unawaited(_applyMmlAutofillFromHelper5());
    });
    _mmlPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || !_isFieldEditable) return;
      unawaited(_applyMmlAutofillFromHelper5());
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _mmlSavedSub?.cancel();
    _mmlPollTimer?.cancel();
    unawaited(_stashCurrentDayDraft());
    for (final c in [
      _cumulativeFeedCtrl,
      _feedVolumeCtrl,
      _hbCtrl,
      _peakTsbCtrl,
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
        final birth = await _api.loadBirthResuscitation(eid);
        if (!helperBirthRowMatchesScreening(
          birth: birth,
          screeningId: widget.screeningId,
        )) {
          if (mounted) {
            setState(() {
              _loading = false;
              _banner =
                  'This enrollment belongs to a different screening. Helper data was not loaded.';
              _bannerError = true;
            });
          }
          return;
        }
        final raw = birth?['date_of_birth']?.toString();
        _babyName = (birth?['baby_name'] ?? '').toString();
        final bw = birth?['birth_weight'];
        _birthWeightGrams = bw == null
            ? null
            : (bw is num ? bw.toDouble() : double.tryParse(bw.toString().trim()));
        if (_birthWeightGrams != null && _birthWeightGrams! <= 0) {
          _birthWeightGrams = null;
        }
        if (raw != null && raw.isNotEmpty) {
          _day1Date = parseIsoDateOnly(raw);
          _dischargeDay = helperDischargeNicuDay(
            _day1Date,
            birth?['discharge_date']?.toString(),
          );
        } else {
          _banner =
              'Day 1 Date unavailable — Date of Birth not yet recorded in Form B.';
          _bannerError = true;
        }
      } catch (e) {
        _banner = 'Could not load Date of Birth from Form B: $e';
        _bannerError = true;
      }

      final summary = await _api.loadInfectGiHemaSummary(eid);
      var maxDay = 14;
      for (final row in summary) {
        final n = row['nicu_day'];
        final day = n is int ? n : int.tryParse('$n') ?? 0;
        if (day < 1) continue;
        if (day > maxDay) maxDay = day;
        final pct = row['completion_pct'];
        final parsedPct = pct is int ? pct : int.tryParse('$pct') ?? 0;
        _dayStatus[day] = helperDayDisplayStatus(
          (row['submission_status'] ?? 'empty').toString(),
          parsedPct,
        );
        _dayPct[day] = parsedPct;
      }
      _recomputeTodayNicuDay();
      _totalDays = maxDay < 14 ? 14 : maxDay;
      if (_todayNicuDay > _totalDays) _totalDays = _todayNicuDay;
      if (_dischargeDay != null && _totalDays > _dischargeDay!) {
        _totalDays = _dischargeDay!;
      }
      final remembered = await readRememberedActiveDay(
        helperSessionKeyInfectGiHema,
        eid,
      );
      _activeDay =
          remembered != null &&
              remembered >= 1 &&
              remembered <= _todayNicuDay &&
              (_dischargeDay == null || remembered <= _dischargeDay!)
          ? remembered
          : _defaultActiveDay();
      _stripStart = helperDefaultStripStart(_todayNicuDay);
      if (_activeDay < _stripStart) {
        _stripStart = helperDefaultStripStart(_activeDay);
      }
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
    _todayNicuDay = nicuDayNumberFromDay1(_day1Date);
  }

  int _defaultActiveDay() => _todayNicuDay;

  DateTime? _calendarForDay(int day) {
    if (_day1Date == null) return null;
    return DateTime(
      _day1Date!.year,
      _day1Date!.month,
      _day1Date!.day,
    ).add(Duration(days: day - 1));
  }

  String? get _activeDayYmd {
    final cal = _calendarForDay(_activeDay);
    if (cal == null) return null;
    return formatNicuCalendarYmd(cal);
  }

  bool get _isFutureDay =>
      _day1Date != null &&
      (_activeDay > _todayNicuDay ||
          (_dischargeDay != null && _activeDay > _dischargeDay!));

  /// Informational only — a past day's calendar date no longer forces the
  /// record read-only on its own. Locking is manual, via Submit & Lock
  /// (mirrors web's `isPastActiveDay`).
  bool get _isPastActiveDay => _day1Date != null && _activeDay < _todayNicuDay;

  /// Site-monitor override reopens an otherwise-locked day for a limited
  /// window (mirrors web's `isOverrideActiveDay`).
  bool get _isOverrideActive =>
      _overrideUntil != null &&
      DateTime.now().toUtc().isBefore(_overrideUntil!);

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

  InfectGiHemaCompletion get _completion =>
      InfectGiHemaCompletion.compute(_buildModel());

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
    _lastFeedAutoDate = null;
    _lastFeedAutoValue = null;
    _feedVolumeAutofilled = false;
    _lastFeedVolCalcAutoDate = null;
    _lastFeedVolCalcAutoValue = null;
    _feedVolumeCalcAutofilled = false;
    _hemaPrbcAutofilled = false;
    _hemaPlateletAutofilled = false;
    _hemaFfpAutofilled = false;
    try {
      final raw = await _api.loadInfectGiHemaDay(eid, day);
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      if (raw == null) {
        if (!await _applyLocalDraftIfAny(day, serverConfirmedEmpty: true)) {
          _clearForm();
          _recordExists = false;
          _isEditing = true;
          _isSubmitted = false;
          _overrideUntil = null;
          _dayLoadFailed = false;
          _serverUpdatedAt = null;
        } else {
          _recordExists = false;
          _isEditing = true;
          _isSubmitted = false;
          _overrideUntil = null;
          _dayLoadFailed = false;
          _serverUpdatedAt = null;
        }
      } else {
        _applyDay(InfectGiHemaDay.fromJson(raw));
        _recordExists = true;
        _isSubmitted = (raw['submission_status']?.toString() == 'submitted');
        _overrideUntil = _parseUtc(raw['override_unlocked_until']);
        _isEditing = !_isSubmitted || _isOverrideActive;
        _dayLoadFailed = false;
        _serverUpdatedAt = raw['updated_at']?.toString();
      }
    } catch (e) {
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      if (await _applyLocalDraftIfAny(day)) {
        _recordExists = false;
        _isEditing = true;
        _isSubmitted = false;
        _overrideUntil = null;
        _dayLoadFailed = true;
        _banner =
            'Could not reach server — showing on-device draft for Day $day. Save when online.';
        _bannerError = true;
      } else {
        _clearForm();
        _recordExists = false;
        _isEditing = false;
        _isSubmitted = false;
        _overrideUntil = null;
        _dayLoadFailed = true;
        _banner =
            'Could not load Day $day — save disabled until reload succeeds: $e';
        _bannerError = true;
      }
    } finally {
      if (mounted && gen == _loadGen) setState(() => _dayLoading = false);
    }
    if (mounted && gen == _loadGen && day == _activeDay) {
      await _applyMmlAutofillFromHelper5();
    }
  }

  Future<MmlHemeTransfusionFlags> _loadMmlHemeTransfusionFlagsForHelperDay(
    String eid,
    String recordDate,
  ) async {
    var merged = const MmlHemeTransfusionFlags();
    try {
      final on = await _api.loadMinimalMonitoringOnDate(eid, recordDate);
      merged = merged.merge(
        parseHemeATransfusionFlags(on, helperCalendarDate: recordDate),
      );
    } catch (_) {}
    if (merged.any) return merged;
    try {
      final today = await _api.loadMinimalMonitoringToday(eid);
      final rd = today['record_date']?.toString() ?? '';
      if (rd.isNotEmpty && !rd.startsWith(recordDate)) {
        merged = merged.merge(
          parseHemeATransfusionFlags(today, helperCalendarDate: recordDate),
        );
      } else if (rd.isNotEmpty && rd.startsWith(recordDate)) {
        merged = parseHemeATransfusionFlags(
          today,
          helperCalendarDate: recordDate,
        );
      }
    } catch (_) {}
    return merged;
  }

  Future<void> _applyTransfusionFlagsFromMml() async {
    final eid = widget.enrollmentId.trim();
    final recordDate = _activeDayYmd;
    if (eid.isEmpty || recordDate == null) return;
    if (_isFutureDay) return;
    if (_isSubmitted && !_isOverrideActive) return;
    try {
      final flags = await _loadMmlHemeTransfusionFlagsForHelperDay(
        eid,
        recordDate,
      );
      if (!mounted || _activeDayYmd != recordDate) return;

      var changed = false;
      void sync(
        bool mmlHas,
        bool wasAf,
        bool? current,
        void Function(bool?) setVal,
        void Function(bool) setAf,
      ) {
        final r = mmlSyncTransfusionYnFromMml(
          current: current,
          mmlHas: mmlHas,
          wasAutofilled: wasAf,
        );
        if (r.changed) {
          setVal(r.nextValue);
          setAf(r.nextAutofilled);
          changed = true;
        }
      }

      sync(
        flags.prbc,
        _hemaPrbcAutofilled,
        _prbcTransfusion,
        (v) => _prbcTransfusion = v,
        (a) => _hemaPrbcAutofilled = a,
      );
      sync(
        flags.platelet,
        _hemaPlateletAutofilled,
        _plateletTransfusion,
        (v) => _plateletTransfusion = v,
        (a) => _hemaPlateletAutofilled = a,
      );
      sync(
        flags.ffpCryo,
        _hemaFfpAutofilled,
        _ffpCryo,
        (v) => _ffpCryo = v,
        (a) => _hemaFfpAutofilled = a,
      );

      if (changed && mounted) {
        setState(() => _isEditing = true);
      }
    } catch (_) {
      // DMS optional
    }
  }

  Future<void> _applyMmlAutofillFromHelper5() async {
    await _applyFeedVolumeFromMml();
    // Must run after cumulative ml settles — #15 = #14 ÷ effective weight.
    await _applyFeedVolumeCalcFromWeight();
    await _applyTransfusionFlagsFromMml();
  }

  Future<List<double>> _loadMmlGiAFeedValuesForHelperDay(
    String eid,
    String recordDate,
  ) async {
    var merged = <double>[];
    try {
      final on = await _api.loadMinimalMonitoringOnDate(eid, recordDate);
      merged = mergeGiAFeedValueLists(
        merged,
        parseGiAFeedVolumeValues(on, helperCalendarDate: recordDate),
      );
    } catch (_) {}
    if (merged.isNotEmpty) return merged;
    try {
      final today = await _api.loadMinimalMonitoringToday(eid);
      final rd = today['record_date']?.toString() ?? '';
      if (rd.isNotEmpty && !rd.startsWith(recordDate)) {
        merged = mergeGiAFeedValueLists(
          merged,
          parseGiAFeedVolumeValues(today, helperCalendarDate: recordDate),
        );
      } else if (rd.isNotEmpty && rd.startsWith(recordDate)) {
        // Same sheet date but /on/ missed — use today row once (no double-count).
        merged = parseGiAFeedVolumeValues(
          today,
          helperCalendarDate: recordDate,
        );
      }
    } catch (_) {}
    return merged;
  }

  Future<void> _applyFeedVolumeFromMml() async {
    final eid = widget.enrollmentId.trim();
    final recordDate = _activeDayYmd;
    if (eid.isEmpty || recordDate == null) return;
    if (_isFutureDay) return;
    if (_isSubmitted && !_isOverrideActive) return;
    try {
      final entryValues = await _loadMmlGiAFeedValuesForHelperDay(
        eid,
        recordDate,
      );
      if (!mounted || _activeDayYmd != recordDate) return;
      final vol = sumGiAFeedVolumeValues(entryValues);
      if (_npo == true) return;

      final current = _cumulativeFeedCtrl.text.trim();
      final stillMatchesLastAuto =
          _lastFeedAutoDate == recordDate &&
          _lastFeedAutoValue != null &&
          current == _formatFeedVol(_lastFeedAutoValue!);
      final sync = mmlSyncAggregateFieldFromMml(
        current: current.isEmpty ? null : current,
        blockedByNotDone: false,
        wasAutofilled: _feedVolumeAutofilled,
        stillMatchesLastAuto: stillMatchesLastAuto,
        looksSourced: (c, _) =>
            feedVolumeLooksMmlSourced(c?.toString(), entryValues),
        entryValuesForSourced: entryValues,
        mmlValue: vol == null ? null : _formatFeedVol(vol),
      );

      if (!sync.changed) {
        if (sync.nextAutofilled && mounted && !_feedVolumeAutofilled) {
          setState(() => _feedVolumeAutofilled = true);
        }
        return;
      }

      if (vol != null) {
        _lastFeedAutoDate = recordDate;
        _lastFeedAutoValue = vol;
      } else {
        _lastFeedAutoDate = recordDate;
        _lastFeedAutoValue = null;
      }

      if (!mounted) return;
      setState(() {
        _cumulativeFeedCtrl.text = sync.nextValue;
        _feedVolumeAutofilled = sync.nextAutofilled;
        _isEditing = true;
      });
    } catch (_) {
      // DMS optional
    }
  }

  /// #15 Feed Volume (ml/kg/d) = #14 Cumulative ÷ effective weight.
  /// Effective weight is latest DMS 5.7.A (kg) once recovered to/past birth
  /// weight; otherwise birth weight. Fill-if-blank unless [force].
  Future<void> _applyFeedVolumeCalcFromWeight({bool force = false}) async {
    final eid = widget.enrollmentId.trim();
    final recordDate = _activeDayYmd;
    if (eid.isEmpty || recordDate == null) return;
    if (_isFutureDay) return;
    if (_isSubmitted && !_isOverrideActive) return;
    try {
      final dmsWeightKg = await _api.loadLatestWeightKg(eid, recordDate);
      if (!mounted || _activeDayYmd != recordDate) return;
      final effective = effectiveFeedWeightKg(
        dmsWeightKg: dmsWeightKg,
        birthWeightGrams: _birthWeightGrams,
      );
      if (effective == null || !(effective > 0)) return;

      final cumRaw = _cumulativeFeedCtrl.text.trim();
      final cumVol = cumRaw.isEmpty ? null : double.tryParse(cumRaw);
      final calc = feedVolumeMlPerKgDay(cumVol, effective);
      final calcStr = calc == null ? null : formatFeedVolumeMlPerKgDay(calc);

      final current = _feedVolumeCtrl.text.trim();
      final stillMatchesLastAuto =
          _lastFeedVolCalcAutoDate == recordDate &&
          _lastFeedVolCalcAutoValue != null &&
          current == _lastFeedVolCalcAutoValue;
      final sync = mmlSyncAggregateFieldFromMml(
        current: current.isEmpty ? null : current,
        blockedByNotDone: _feedVolumeStatus != null,
        wasAutofilled: _feedVolumeCalcAutofilled,
        stillMatchesLastAuto: stillMatchesLastAuto,
        looksSourced: (c, _) => false,
        entryValuesForSourced: const [],
        mmlValue: calcStr,
        force: force,
      );

      if (!sync.changed) {
        if (sync.nextAutofilled && mounted && !_feedVolumeCalcAutofilled) {
          setState(() => _feedVolumeCalcAutofilled = true);
        }
        return;
      }

      _lastFeedVolCalcAutoDate = recordDate;
      _lastFeedVolCalcAutoValue = calcStr;

      if (!mounted) return;
      setState(() {
        _feedVolumeCtrl.text = sync.nextValue;
        _feedVolumeCalcAutofilled = sync.nextAutofilled;
        _isEditing = true;
      });
    } catch (_) {
      // DMS weight optional
    }
  }

  Future<void> _confirmForceRefillFeedVolume() async {
    if (!_isFieldEditable) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalculate Feed Volume?'),
        content: const Text(
          'Recalculate Feed Volume (ml/kg/d) from the latest Cumulative Feed '
          'Volume and weight, overwriting whatever is currently in the field '
          '(including a manually-typed value)?\n\n'
          'Use this if the number looks wrong — e.g. it was calculated before '
          'a weight was corrected. If there is no weight or feed volume to '
          'calculate from, this will clear the field rather than guess.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _applyFeedVolumeCalcFromWeight(force: true);
  }

  static String _formatFeedVol(double vol) {
    return vol == vol.roundToDouble() ? '${vol.round()}' : '$vol';
  }

  Future<void> _stashCurrentDayDraft() async {
    if (_day1Date == null || _isFutureDay) return;
    if (_completion.percent == 0) return;
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return;
    final body = _buildModel().toJson(
      submissionStatus: 'draft',
      savedAt: DateTime.now().toUtc().toIso8601String(),
      savedBy: 'local-draft',
    );
    final sid = widget.screeningId.trim();
    if (sid.isNotEmpty) body['screening_id'] = sid;
    await HelperDayDraftStorage.save(_kIghDraftKey, eid, _activeDay, body);
  }

  Future<bool> _applyLocalDraftIfAny(
    int day, {
    bool serverConfirmedEmpty = false,
  }) async {
    final eid = widget.enrollmentId.trim();
    final raw = await HelperDayDraftStorage.load(
      _kIghDraftKey,
      eid,
      day,
    );
    if (raw == null) return false;
    if (!helperLocalDraftIsForScreening(
      draft: raw,
      screeningId: widget.screeningId,
      serverConfirmedEmpty: serverConfirmedEmpty,
    )) {
      await HelperDayDraftStorage.clear(_kIghDraftKey, eid, day);
      return false;
    }
    _applyDay(InfectGiHemaDay.fromJson(raw));
    return true;
  }

  void _clearForm() {
    _cumulativeFeedCtrl.clear();
    _feedVolumeCtrl.clear();
    _hbCtrl.clear();
    _peakTsbCtrl.clear();
    _sepsisSuspected = null;
    _bloodCultureSent = null;
    _bloodCulturePositive = null;
    _bloodCultureStatus = null;
    _antibiotics = null;
    _lpDone = null;
    _meningitis = null;
    _meningitisType = null;
    _clabsi = null;
    _vap = null;
    _sepsisScreenSent = null;
    _sepsisScreens = [SepsisScreenEntry.blank()];
    _npo = null;
    _men = null;
    _enteralFeedsReceived = null;
    _feedType = [];
    _cumulativeFeedVolumeStatus = null;
    _feedVolumeStatus = null;
    _ivFluids = null;
    _parenteralNutrition = null;
    _probiotic = null;
    _feedIntolerance = null;
    _necSuspected = null;
    _necConfirmedStage = null;
    _cholestasis = null;
    _hbValueStatus = null;
    _peakTsbStatus = null;
    _jaundice = null;
    _phototherapy = null;
    _exchangeTransfusion = null;
    _prbcTransfusion = null;
    _plateletTransfusion = null;
    _ffpCryo = null;
  }

  void _applyDay(InfectGiHemaDay d) {
    _sepsisSuspected = d.sepsisSuspected;
    _bloodCultureSent = d.bloodCultureSent;
    _bloodCulturePositive = d.bloodCulturePositive;
    _bloodCultureStatus = d.bloodCultureStatus;
    _antibiotics = d.antibiotics;
    _lpDone = d.lpDone;
    _meningitis = d.meningitis;
    _meningitisType = d.meningitisType;
    _clabsi = d.clabsi;
    _vap = d.vap;
    _sepsisScreenSent = d.sepsisScreenSent;
    _sepsisScreens = d.sepsisScreens.isEmpty
        ? [SepsisScreenEntry.blank()]
        : d.sepsisScreens
              .map((e) => SepsisScreenEntry.fromJson(e.toJson()))
              .toList();
    _npo = d.npo;
    _men = d.men;
    _enteralFeedsReceived = d.enteralFeedsReceived;
    _feedType = List.of(d.feedType);
    _cumulativeFeedCtrl.text = d.cumulativeFeedVolume?.toString() ?? '';
    _cumulativeFeedVolumeStatus = d.cumulativeFeedVolumeStatus;
    _feedVolumeCtrl.text = d.feedVolume?.toString() ?? '';
    _feedVolumeStatus = d.feedVolumeStatus;
    _ivFluids = d.ivFluids;
    _parenteralNutrition = d.parenteralNutrition;
    _probiotic = d.probiotic;
    _feedIntolerance = d.feedIntolerance;
    _necSuspected = d.necSuspected;
    _necConfirmedStage = d.necConfirmedStage;
    _cholestasis = d.cholestasis;
    _hbCtrl.text = d.hbValue?.toString() ?? '';
    _hbValueStatus = d.hbValueStatus;
    _jaundice = d.jaundice;
    _phototherapy = d.phototherapy;
    _peakTsbCtrl.text = d.peakTsb?.toString() ?? '';
    _peakTsbStatus = d.peakTsbStatus;
    _exchangeTransfusion = d.exchangeTransfusion;
    _prbcTransfusion = d.prbcTransfusion;
    _plateletTransfusion = d.plateletTransfusion;
    _ffpCryo = d.ffpCryo;
  }

  InfectGiHemaDay _buildModel() {
    final d = InfectGiHemaDay(
      enrollmentId: widget.enrollmentId.trim(),
      nicuDay: _activeDay,
    );
    d.sepsisSuspected = _sepsisSuspected;
    d.bloodCultureSent = _bloodCultureSent;
    d.bloodCulturePositive = _bloodCulturePositive;
    d.bloodCultureStatus = _bloodCultureStatus;
    d.antibiotics = _antibiotics;
    d.lpDone = _lpDone;
    d.meningitis = _meningitis;
    d.meningitisType = _meningitisType;
    d.clabsi = _clabsi;
    d.vap = _vap;
    d.sepsisScreenSent = _sepsisScreenSent;
    d.sepsisScreens = _sepsisScreens
        .map((e) => SepsisScreenEntry.fromJson(e.toJson()))
        .toList();
    d.npo = _npo;
    d.men = _men;
    d.enteralFeedsReceived = _enteralFeedsReceived;
    d.feedType = List.of(_feedType);
    d.cumulativeFeedVolume = double.tryParse(_cumulativeFeedCtrl.text.trim());
    d.cumulativeFeedVolumeStatus = _cumulativeFeedVolumeStatus;
    d.feedVolume = double.tryParse(_feedVolumeCtrl.text.trim());
    d.feedVolumeStatus = _feedVolumeStatus;
    d.ivFluids = _ivFluids;
    d.parenteralNutrition = _parenteralNutrition;
    d.probiotic = _probiotic;
    d.feedIntolerance = _feedIntolerance;
    d.necSuspected = _necSuspected;
    d.necConfirmedStage = _necConfirmedStage;
    d.cholestasis = _cholestasis;
    d.hbValue = double.tryParse(_hbCtrl.text.trim());
    d.hbValueStatus = _hbValueStatus;
    d.jaundice = _jaundice;
    d.phototherapy = _phototherapy;
    d.peakTsb = double.tryParse(_peakTsbCtrl.text.trim());
    d.peakTsbStatus = _peakTsbStatus;
    d.exchangeTransfusion = _exchangeTransfusion;
    d.prbcTransfusion = _prbcTransfusion;
    d.plateletTransfusion = _plateletTransfusion;
    d.ffpCryo = _ffpCryo;
    return d;
  }

  void _applyGatedClearsOnSave(InfectGiHemaDay model) {
    if (model.sepsisSuspected == false) {
      model.bloodCultureSent = null;
      model.bloodCulturePositive = null;
      model.bloodCultureStatus = null;
    } else if (model.bloodCultureSent == false) {
      model.bloodCulturePositive = null;
      model.bloodCultureStatus = null;
    }
    if (model.meningitis == false) model.meningitisType = null;
    if (model.npo == true) {
      model.men = null;
      model.enteralFeedsReceived = null;
      model.feedType = [];
      model.cumulativeFeedVolume = null;
      model.cumulativeFeedVolumeStatus = null;
      model.feedVolume = null;
      model.feedVolumeStatus = null;
    } else if (model.enteralFeedsReceived == false) {
      model.feedType = [];
    }
    if (model.necSuspected == false) model.necConfirmedStage = null;
    if (model.jaundice == false) model.phototherapy = null;
  }

  Future<void> _switchDay(int day) async {
    if (day == _activeDay) return;
    if (_day1Date != null && day > _todayNicuDay) {
      _toast('Day $day is not available yet');
      return;
    }
    if (_isFieldEditable && _completion.percent > 0) {
      final ok = await _save();
      if (!ok) return;
    }
    await _stashCurrentDayDraft();
    setState(() => _activeDay = day);
    unawaited(
      rememberActiveDay(helperSessionKeyInfectGiHema, widget.enrollmentId, day),
    );
    await _loadActiveDay();
  }

  Future<void> _addDay() async {
    if (_dischargeDay != null) {
      _toast('Baby is discharged — no further days');
      return;
    }
    final next = _totalDays + 1;
    if (_day1Date != null && next > _todayNicuDay) {
      setState(() => _totalDays = next);
      _toast('Day $next is not available yet');
      return;
    }
    setState(() => _totalDays = next);
    await _switchDay(next);
  }

  Future<void> _copyPrevious() async {
    if (!_isFieldEditable || _activeDay <= 1) return;
    try {
      final raw = await _api.loadInfectGiHemaDay(
        widget.enrollmentId.trim(),
        _activeDay - 1,
      );
      if (raw == null) {
        _toast('No data on Day ${_activeDay - 1} to copy', error: true);
        return;
      }
      final src = InfectGiHemaDay.fromJson(raw);
      final cur = _buildModel()..copyClinicalFrom(src);
      setState(() {
        _applyDay(cur);
        _recordExists = false;
        _isEditing = true;
      });
      _toast('Copied clinical fields from Day ${_activeDay - 1}');
    } catch (e) {
      _toast('Copy failed: $e', error: true);
    }
  }

  Future<bool> _save({bool forLater = false, bool force = false}) async {
    if (_dayLoadFailed) {
      _toast(
        'Day failed to load — switch day or reopen form before saving',
        error: true,
      );
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
    if (!force && _completion.percent == 0 && !_recordExists) {
      _toast('Nothing entered for this day yet', error: true);
      return false;
    }
    // Block invalid numeric text so tryParse→null cannot wipe a good server value.
    // Status sidecars count as the answer — skip the number check when set.
    for (final entry in [
      (
        'Cumulative feed volume',
        _cumulativeFeedCtrl.text,
        _cumulativeFeedVolumeStatus,
      ),
      ('Feed volume', _feedVolumeCtrl.text, _feedVolumeStatus),
      ('Hb', _hbCtrl.text, _hbValueStatus),
      ('Peak TSB', _peakTsbCtrl.text, _peakTsbStatus),
    ]) {
      if ((entry.$3 ?? '').trim().isNotEmpty) continue;
      final t = entry.$2.trim();
      if (t.isNotEmpty && double.tryParse(t) == null) {
        _toast(
          '${entry.$1} is not a valid number — fix before saving',
          error: true,
        );
        return false;
      }
    }

    setState(() => _saving = true);
    try {
      final name = await _nurseName();
      final now = DateTime.now().toUtc().toIso8601String();
      final model = _buildModel();
      _applyGatedClearsOnSave(model);

      final body = model.toJson(
        submissionStatus: helperDaySaveStatus(_completion.percent),
        savedAt: now,
        savedBy: name,
      );
      final saved = await _api.saveInfectGiHemaDay(
        body,
        alreadyExists: _recordExists,
        expectedUpdatedAt: _serverUpdatedAt,
      );
      await HelperDayDraftStorage.clear(_kIghDraftKey, eid, _activeDay);
      final pct = _completion.percent;
      setState(() {
        _applyDay(model);
        _recordExists = true;
        _isEditing = !_isSubmitted;
        _serverUpdatedAt = saved['updated_at']?.toString() ?? _serverUpdatedAt;
        _dayStatus[_activeDay] = pct == 100 ? 'complete' : 'draft';
        _dayPct[_activeDay] = pct;
        _banner = forLater
            ? 'Day $_activeDay saved for later'
            : 'Day $_activeDay saved successfully';
        _bannerError = false;
      });
      return true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) {
        setState(() {
          _banner = e.message;
          _bannerError = true;
        });
        await _loadActiveDay();
        return false;
      }
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit & Lock'),
          ),
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
      await _api.submitInfectGiHemaDay(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.of(context).danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    final sepsisYes = _sepsisSuspected == true;
    final cultureSentYes = _bloodCultureSent == true;
    final sepsisScreenSentYes = _sepsisScreenSent == true;
    final meningitisYes = _meningitis == true;
    final npoNo = _npo == false;
    final enteralYes = _enteralFeedsReceived == true;
    final necYes = _necSuspected == true;
    final jaundiceYes = _jaundice == true;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _appBar(c),
      body: Column(
        children: [
          HelperPatientHeader(
            formBadge: 'HELPER FORM 4',
            formName: 'Infect / GI / Hema Daily Log',
            subtitle: 'Daily infection, GI & hematology assessment',
            enrollmentId: widget.enrollmentId,
            gestation: widget.gestation,
            babyUid: widget.babyUid,
            babyName: _babyName,
          ),
          _day1Bar(c),
          _dayChips(c),
          _statusBanner(c),
          if (_banner != null) _messageBanner(c),
          Expanded(
            child: _dayLoading
                ? const Center(child: CircularProgressIndicator())
                : _isFutureDay
                ? _lockedPanel(
                    c,
                    'Not Available Yet',
                    'Day $_activeDay is in the future.',
                  )
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
                            onPressed: () => setState(() => _isEditing = true),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text('Edit Day $_activeDay'),
                          ),
                        ),
                      if (editable && _activeDay > 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _copyPrevious,
                            icon: const Icon(Icons.copy_all_outlined, size: 18),
                            label: const Text('Copy from previous day'),
                          ),
                        ),
                      _section(
                        c,
                        title: 'Infection Assessment',
                        icon: Icons.coronavirus_rounded,
                        color: c.primary,
                        children: _infectionFields(
                          c,
                          editable,
                          sepsisYes: sepsisYes,
                          cultureSentYes: cultureSentYes,
                          sepsisScreenSentYes: sepsisScreenSentYes,
                          meningitisYes: meningitisYes,
                        ),
                      ),
                      _section(
                        c,
                        title: 'Gastrointestinal Assessment',
                        icon: Icons.restaurant_rounded,
                        color: c.warning,
                        children: _giFields(
                          c,
                          editable,
                          npoNo: npoNo,
                          enteralYes: enteralYes,
                          necYes: necYes,
                        ),
                      ),
                      _section(
                        c,
                        title: 'Hematology Assessment',
                        icon: Icons.bloodtype_rounded,
                        color: c.danger,
                        children: _hemaFields(
                          c,
                          editable,
                          jaundiceYes: jaundiceYes,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(c),
    );
  }

  HelperFormPatientContext get _helperPatient => HelperFormPatientContext(
    enrollmentId: widget.enrollmentId,
    gestation: widget.gestation,
    motherName: widget.motherName,
    babyUid: widget.babyUid,
    screeningId: widget.screeningId,
  );

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
            widget.enrollmentId,
            style: TextStyle(color: c.textTertiary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        HelperFormSwitcherButton(
          current: HelperFormKind.infectGiHema,
          patient: _helperPatient,
        ),
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
    );
  }

  Widget _day1Bar(AppColors c) {
    final label = _day1Date != null
        ? formatDisplayDate(_day1Date!)
        : 'Awaiting Form B';
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text(
            'Day 1 Date',
            style: TextStyle(
              color: c.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayChips(AppColors c) {
    final visible = helperVisibleStripDays(
      stripStart: _stripStart,
      totalDays: _totalDays,
      todayNicuDay: _todayNicuDay,
      dischargeDay: _dischargeDay,
    );
    return HelperRecentDayStrip(
      visibleDays: visible,
      activeDay: _activeDay,
      todayNicuDay: _todayNicuDay,
      day1Date: _day1Date,
      dayStatus: {
        ..._dayStatus,
        _activeDay: helperDayDisplayStatus(
          _isSubmitted ? 'submitted' : (_dayStatus[_activeDay] ?? 'empty'),
          _completion.percent,
        ),
      },
      dischargeDay: _dischargeDay,
      showAddDay: _dischargeDay == null,
      canShowEarlier: _stripStart > 1,
      onShowEarlier: () {
        setState(() {
          _stripStart = (_stripStart - kMobileDayStripWindow) < 1
              ? 1
              : _stripStart - kMobileDayStripWindow;
        });
      },
      missedDays: helperMissedDaysInWindow(
        visibleDays: visible,
        todayNicuDay: _todayNicuDay,
        dayStatus: _dayStatus,
      ),
      onSelect: _switchDay,
      onAddDay: _addDay,
    );
  }

  Widget _statusBanner(AppColors c) {
    if (_day1Date == null) {
      return Container(
        width: double.infinity,
        color: c.warningSoft,
        padding: const EdgeInsets.all(10),
        child: Text(
          'Set Day 1 Date to enable NICU day logging.',
          style: TextStyle(color: c.warning, fontSize: 12),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _messageBanner(AppColors c) {
    return Container(
      width: double.infinity,
      color: _bannerError ? c.dangerSoft : c.successSoft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        _banner!,
        style: TextStyle(
          color: _bannerError ? c.danger : c.success,
          fontSize: 12,
        ),
      ),
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
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Day $_activeDay',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: c.textPrimary,
                  ),
                ),
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
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
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
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _updateSepsisScreen(int i, String field, String v) {
    if (!_isFieldEditable) return;
    setState(() {
      final e = _sepsisScreens[i];
      switch (field) {
        case 'date':
          e.date = v;
          break;
        case 'time':
          e.time = v;
          break;
        case 'type':
          e.type = v;
          break;
        case 'value':
          e.value = v;
          break;
        case 'result':
          e.result = v;
          break;
      }
    });
  }

  void _addSepsisScreen() {
    if (!_isFieldEditable) return;
    setState(() => _sepsisScreens.add(SepsisScreenEntry.blank()));
  }

  void _removeSepsisScreen(int i) {
    if (!_isFieldEditable || _sepsisScreens.length <= 1) return;
    setState(() => _sepsisScreens.removeAt(i));
  }

  Widget _sepsisScreensBlock(AppColors c, bool editable) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sepsis Screens',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _sepsisScreens.length; i++)
            _SepsisScreenEntryRow(
              key: ValueKey(_sepsisScreens[i].id),
              index: i,
              entry: _sepsisScreens[i],
              editable: editable,
              canDelete: _sepsisScreens.length > 1,
              colors: c,
              onChanged: (field, v) => _updateSepsisScreen(i, field, v),
              onDelete: () => _removeSepsisScreen(i),
            ),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addSepsisScreen,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add screen'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _infectionFields(
    AppColors c,
    bool editable, {
    required bool sepsisYes,
    required bool cultureSentYes,
    required bool sepsisScreenSentYes,
    required bool meningitisYes,
  }) {
    return [
      _yn('1. Sepsis Suspected', _sepsisSuspected, editable, (v) {
        setState(() {
          _sepsisSuspected = v;
          if (v != true) {
            _bloodCultureSent = null;
            _bloodCulturePositive = null;
            _bloodCultureStatus = null;
          }
        });
      }, c),
      if (sepsisYes) ...[
        _yn('2. Blood Culture Sent', _bloodCultureSent, editable, (v) {
          setState(() {
            _bloodCultureSent = v;
            if (v != true) {
              _bloodCulturePositive = null;
              _bloodCultureStatus = null;
            }
          });
        }, c),
        if (cultureSentYes)
          _yn(
            '3. Blood Culture Positive',
            _bloodCulturePositive,
            editable,
            (v) => setState(() {
              _bloodCulturePositive = v;
              if (v != null) _bloodCultureStatus = null;
            }),
            c,
            status: _bloodCultureStatus,
            allowAwaited: true,
            onStatus: (s) => setState(() {
              _bloodCultureStatus = s;
              if (s != null) _bloodCulturePositive = null;
            }),
          ),
        // Not part of the original numbered CRF sequence — mirrors web's
        // sepsis_screen_sent gate + repeatable sepsis_screens list, added
        // so Form H's Infection auto-fill can distinguish clinical vs.
        // screen-positive vs. culture-positive sepsis.
        _yn('Sepsis Screen Sent', _sepsisScreenSent, editable, (v) {
          setState(() {
            _sepsisScreenSent = v;
            if (v != true) _sepsisScreens = [SepsisScreenEntry.blank()];
          });
        }, c),
        if (sepsisScreenSentYes) _sepsisScreensBlock(c, editable),
      ],
      _yn(
        '4. Antibiotics',
        _antibiotics,
        editable,
        (v) => setState(() => _antibiotics = v),
        c,
      ),
      _yn(
        '5. LP Done',
        _lpDone,
        editable,
        (v) => setState(() => _lpDone = v),
        c,
      ),
      _yn('6. Meningitis (Y/N)', _meningitis, editable, (v) {
        setState(() {
          _meningitis = v;
          if (v != true) _meningitisType = null;
        });
      }, c),
      if (meningitisYes)
        _fieldCard(
          c,
          number: '7',
          label: 'Meningitis Type',
          child: _singleChoice(
            InfectGiHemaDay.meningitisTypeOptions,
            _meningitisType,
            editable,
            (v) => setState(() => _meningitisType = v),
            c,
          ),
        ),
      _yn(
        '8. CLABSI',
        _clabsi,
        editable,
        (v) => setState(() => _clabsi = v),
        c,
      ),
      _yn('9. VAP', _vap, editable, (v) => setState(() => _vap = v), c),
    ];
  }

  List<Widget> _giFields(
    AppColors c,
    bool editable, {
    required bool npoNo,
    required bool enteralYes,
    required bool necYes,
  }) {
    return [
      _yn('10. NPO', _npo, editable, (v) {
        setState(() {
          _npo = v;
          if (v != false) {
            _men = null;
            _enteralFeedsReceived = null;
            _feedType = [];
            _cumulativeFeedCtrl.clear();
            _feedVolumeCtrl.clear();
            _cumulativeFeedVolumeStatus = null;
            _feedVolumeStatus = null;
          }
        });
      }, c),
      if (npoNo) ...[
        _yn(
          '11. MEN (Minimal Enteral Nutrition)',
          _men,
          editable,
          (v) => setState(() => _men = v),
          c,
        ),
        _yn('12. Enteral Feeds Received', _enteralFeedsReceived, editable, (v) {
          setState(() {
            _enteralFeedsReceived = v;
            if (v != true) _feedType = [];
          });
        }, c),
        if (enteralYes)
          _fieldCard(
            c,
            number: '13',
            label: 'Feed Type',
            hint: 'Select all that apply',
            child: _pills(
              InfectGiHemaDay.feedTypeOptions,
              _feedType,
              editable,
              (next) => setState(() => _feedType = next),
              c,
            ),
          ),
        _fieldCard(
          c,
          number: '14',
          label: 'Cumulative Feed Volume',
          hint: 'ml',
          status: _cumulativeFeedVolumeStatus,
          allowNotDone: true,
          enabled: editable,
          onStatus: (s) => setState(() {
            _cumulativeFeedVolumeStatus = s;
            if (s != null) _cumulativeFeedCtrl.clear();
          }),
          child: _textField(
            _cumulativeFeedCtrl,
            c,
            enabled: editable && _cumulativeFeedVolumeStatus == null,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '0',
            error: InfectGiHemaValidators.cumulativeFeedVolume(
              _cumulativeFeedCtrl.text,
            ),
          ),
        ),
        _fieldCard(
          c,
          number: '15',
          label: 'Feed Volume',
          hint: 'ml/kg/d',
          status: _feedVolumeStatus,
          allowNotDone: true,
          enabled: editable,
          onStatus: (s) => setState(() {
            _feedVolumeStatus = s;
            if (s != null) _feedVolumeCtrl.clear();
          }),
          child: _textField(
            _feedVolumeCtrl,
            c,
            enabled: editable && _feedVolumeStatus == null,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '0',
            error: InfectGiHemaValidators.feedVolume(_feedVolumeCtrl.text),
          ),
        ),
        if (editable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _confirmForceRefillFeedVolume,
              child: const Text(
                'Force refill Feed Volume (overwrite existing answer)',
              ),
            ),
          ),
      ],
      _yn(
        '16. IV Fluids',
        _ivFluids,
        editable,
        (v) => setState(() => _ivFluids = v),
        c,
      ),
      _yn(
        '17. Parenteral Nutrition',
        _parenteralNutrition,
        editable,
        (v) => setState(() => _parenteralNutrition = v),
        c,
      ),
      _yn(
        '18. Probiotic',
        _probiotic,
        editable,
        (v) => setState(() => _probiotic = v),
        c,
      ),
      _yn(
        '19. Feed Intolerance',
        _feedIntolerance,
        editable,
        (v) => setState(() => _feedIntolerance = v),
        c,
      ),
      _yn('20. NEC Suspected', _necSuspected, editable, (v) {
        setState(() {
          _necSuspected = v;
          if (v != true) _necConfirmedStage = null;
        });
      }, c),
      if (necYes)
        _fieldCard(
          c,
          number: '21',
          label: 'NEC Confirmed Stage',
          child: _singleChoice(
            InfectGiHemaDay.necStageOptions,
            _necConfirmedStage,
            editable,
            (v) => setState(() => _necConfirmedStage = v),
            c,
          ),
        ),
      _yn(
        '22. Cholestasis',
        _cholestasis,
        editable,
        (v) => setState(() => _cholestasis = v),
        c,
      ),
    ];
  }

  List<Widget> _hemaFields(
    AppColors c,
    bool editable, {
    required bool jaundiceYes,
  }) {
    return [
      _fieldCard(
        c,
        number: '23',
        label: 'Hb Value',
        hint: 'g/dL',
        status: _hbValueStatus,
        allowAwaited: true,
        allowNotDone: true,
        enabled: editable,
        onStatus: (s) => setState(() {
          _hbValueStatus = s;
          if (s != null) _hbCtrl.clear();
        }),
        child: _textField(
          _hbCtrl,
          c,
          enabled: editable && _hbValueStatus == null,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          hint: '0.0',
          error: InfectGiHemaValidators.hb(_hbCtrl.text),
        ),
      ),
      _yn('24. Jaundice', _jaundice, editable, (v) {
        setState(() {
          _jaundice = v;
          if (v != true) _phototherapy = null;
        });
      }, c),
      if (jaundiceYes)
        _yn(
          '25. Phototherapy',
          _phototherapy,
          editable,
          (v) => setState(() => _phototherapy = v),
          c,
        ),
      _fieldCard(
        c,
        number: '26',
        label: 'Peak TSB',
        hint: 'mg/dL',
        status: _peakTsbStatus,
        allowAwaited: true,
        allowNotDone: true,
        enabled: editable,
        onStatus: (s) => setState(() {
          _peakTsbStatus = s;
          if (s != null) _peakTsbCtrl.clear();
        }),
        child: _textField(
          _peakTsbCtrl,
          c,
          enabled: editable && _peakTsbStatus == null,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          hint: '0.0',
          error: InfectGiHemaValidators.peakTsb(_peakTsbCtrl.text),
        ),
      ),
      _yn(
        '27. Exchange Transfusion',
        _exchangeTransfusion,
        editable,
        (v) => setState(() => _exchangeTransfusion = v),
        c,
      ),
      _yn('28. PRBC Transfusion', _prbcTransfusion, editable, (v) {
        setState(() {
          _hemaPrbcAutofilled = false;
          _prbcTransfusion = v;
        });
      }, c),
      _yn('29. Platelet Transfusion', _plateletTransfusion, editable, (v) {
        setState(() {
          _hemaPlateletAutofilled = false;
          _plateletTransfusion = v;
        });
      }, c),
      _yn('30. FFP / Cryo Transfusion', _ffpCryo, editable, (v) {
        setState(() {
          _hemaFfpAutofilled = false;
          _ffpCryo = v;
        });
      }, c),
    ];
  }

  Widget _bottomBar(AppColors c) {
    final canEdit =
        _isFieldEditable ||
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
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    (_saving ||
                        !canEdit ||
                        (_isSubmitted && !_isOverrideActive))
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
                onPressed:
                    (_saving ||
                        !canEdit ||
                        (_isSubmitted && !_isOverrideActive))
                    ? null
                    : () {
                        setState(() => _isEditing = true);
                        _save();
                      },
                style: ElevatedButton.styleFrom(backgroundColor: c.primary),
                child: Text(
                  _saving ? 'Saving…' : 'Save',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: c.textPrimary,
                  ),
                ),
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
    String? status,
    bool allowAwaited = false,
    bool allowNotDone = false,
    bool enabled = true,
    ValueChanged<String?>? onStatus,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  number.isEmpty ? label : '$number. $label',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (onStatus != null)
                _statusChips(
                  status: status,
                  enabled: enabled,
                  allowAwaited: allowAwaited,
                  allowNotDone: allowNotDone,
                  onChanged: onStatus,
                  c: c,
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 11, color: c.textTertiary)),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _statusChips({
    required String? status,
    required bool enabled,
    required bool allowAwaited,
    required bool allowNotDone,
    required ValueChanged<String?> onChanged,
    required AppColors c,
  }) {
    Widget chip(String label, String value) {
      final on = status == value;
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: InkWell(
          onTap: !enabled ? null : () => onChanged(on ? null : value),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: on ? c.warningSoft : c.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? c.warning : c.border),
            ),
            child: Text(
              on ? 'Undo' : label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: on ? c.warning : c.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      children: [
        if (allowAwaited)
          chip(InfectGiHemaDay.statusAwaited, InfectGiHemaDay.statusAwaited),
        if (allowNotDone)
          chip(InfectGiHemaDay.statusNotDone, InfectGiHemaDay.statusNotDone),
      ],
    );
  }

  Widget _yn(
    String label,
    bool? value,
    bool enabled,
    ValueChanged<bool?> onChanged,
    AppColors c, {
    String? hint,
    String? status,
    bool allowAwaited = false,
    ValueChanged<String?>? onStatus,
  }) {
    final sentinel = status != null && status.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: c.textPrimary,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: TextStyle(fontSize: 11, color: c.textTertiary),
                  ),
              ],
            ),
          ),
          if (onStatus != null)
            _statusChips(
              status: status,
              enabled: enabled,
              allowAwaited: allowAwaited,
              allowNotDone: false,
              onChanged: onStatus,
              c: c,
            ),
          _ynToggle(value, enabled && !sentinel, onChanged, c),
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
        onTap: !enabled ? null : () => onChanged(active ? null : target),
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

  Widget _singleChoice(
    List<String> options,
    String? selected,
    bool enabled,
    ValueChanged<String?> onChanged,
    AppColors c,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final sel = selected == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: sel,
          onSelected: !enabled ? null : (_) => onChanged(sel ? null : opt),
        );
      }).toList(),
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
          Text(error, style: TextStyle(color: c.warning, fontSize: 11)),
        ],
      ],
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
      'Dec',
    ];
    return names[m - 1];
  }
}

class _SepsisScreenEntryRow extends StatefulWidget {
  final int index;
  final SepsisScreenEntry entry;
  final bool editable;
  final bool canDelete;
  final AppColors colors;
  final void Function(String field, String value) onChanged;
  final VoidCallback onDelete;

  const _SepsisScreenEntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.editable,
    required this.canDelete,
    required this.colors,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_SepsisScreenEntryRow> createState() => _SepsisScreenEntryRowState();
}

class _SepsisScreenEntryRowState extends State<_SepsisScreenEntryRow> {
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _valueCtrl;

  static const _typeOptions = ['CRP', 'PCT', 'Hematological'];
  static const _resultOptions = ['Positive', 'Negative'];

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: widget.entry.date);
    _timeCtrl = TextEditingController(text: widget.entry.time);
    _valueCtrl = TextEditingController(text: widget.entry.value);
  }

  @override
  void didUpdateWidget(covariant _SepsisScreenEntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final e = widget.entry;
    final o = oldWidget.entry;
    if (o.id != e.id ||
        o.date != e.date ||
        o.time != e.time ||
        o.value != e.value) {
      _dateCtrl.text = e.date;
      _timeCtrl.text = e.time;
      _valueCtrl.text = e.value;
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Widget _choiceRow(
    String label,
    List<String> options,
    String? selected,
    ValueChanged<String> onSelect, {
    bool clearable = false,
  }) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: options.map((o) {
                final sel = selected == o;
                return ChoiceChip(
                  label: Text(o),
                  selected: sel,
                  onSelected: !widget.editable
                      ? null
                      : (_) => onSelect(clearable && sel ? '' : o),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.canDelete)
                Text(
                  '#${widget.index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: c.textTertiary,
                  ),
                ),
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
            ],
          ),
          const SizedBox(height: 8),
          _choiceRow(
            'Type',
            _typeOptions,
            widget.entry.type,
            (v) => widget.onChanged('type', v),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  'Value',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _valueCtrl,
                  enabled: widget.editable,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) => widget.onChanged('value', v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _choiceRow(
            'Result',
            _resultOptions,
            widget.entry.result.isEmpty ? null : widget.entry.result,
            (v) => widget.onChanged('result', v),
            clearable: true,
          ),
        ],
      ),
    );
  }
}
