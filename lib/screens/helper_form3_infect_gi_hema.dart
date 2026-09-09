// lib/screens/helper_form3_infect_gi_hema.dart
//
// Helper Form 3 — Infection / GI / Hematology Daily Log
// Parity with web InfectGIHemaLog.jsx: fields 1–30, same sequence,
// same validations, same /infect-gi-hema/ API (NICU day, not calendar blob).

import 'package:flutter/material.dart';
import '../models/infect_gi_hema_day.dart';
import '../services/forms_api_service.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';

class HelperForm3InfectGIHema extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  final String site;

  const HelperForm3InfectGIHema({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.site = 'PGIMER',
  });

  @override
  State<HelperForm3InfectGIHema> createState() =>
      _HelperForm3InfectGIHemaState();
}

class _HelperForm3InfectGIHemaState extends State<HelperForm3InfectGIHema> {
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

  // Controllers
  final _cumulativeFeedCtrl = TextEditingController();
  final _feedVolumeCtrl = TextEditingController();
  final _hbCtrl = TextEditingController();
  final _peakTsbCtrl = TextEditingController();

  // Infection 1–9
  bool? _sepsisSuspected;
  bool? _bloodCultureSent;
  bool? _bloodCulturePositive;
  bool? _antibiotics;
  bool? _lpDone;
  bool? _meningitis;
  String? _meningitisType;
  bool? _clabsi;
  bool? _vap;

  // GI 10–22
  bool? _npo;
  bool? _men;
  bool? _enteralFeedsReceived;
  List<String> _feedType = [];
  bool? _ivFluids;
  bool? _parenteralNutrition;
  bool? _probiotic;
  bool? _feedIntolerance;
  bool? _necSuspected;
  String? _necConfirmedStage;
  bool? _cholestasis;

  // Hema 23–30
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
    _bootstrap();
  }

  @override
  void dispose() {
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

      final summary = await _api.loadInfectGiHemaSummary(eid);
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
    try {
      final raw = await _api.loadInfectGiHemaDay(eid, day);
      if (!mounted || gen != _loadGen || day != _activeDay) return;
      if (raw == null) {
        _clearForm();
        _recordExists = false;
        _isEditing = true;
        _isSubmitted = false;
        _overrideUntil = null;
        _dayLoadFailed = false;
      } else {
        _applyDay(InfectGiHemaDay.fromJson(raw));
        _recordExists = true;
        _isSubmitted = (raw['submission_status']?.toString() == 'submitted');
        _overrideUntil = _parseUtc(raw['override_unlocked_until']);
        _isEditing = _isOverrideActive;
        _dayLoadFailed = false;
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
    _cumulativeFeedCtrl.clear();
    _feedVolumeCtrl.clear();
    _hbCtrl.clear();
    _peakTsbCtrl.clear();
    _sepsisSuspected = null;
    _bloodCultureSent = null;
    _bloodCulturePositive = null;
    _antibiotics = null;
    _lpDone = null;
    _meningitis = null;
    _meningitisType = null;
    _clabsi = null;
    _vap = null;
    _npo = null;
    _men = null;
    _enteralFeedsReceived = null;
    _feedType = [];
    _ivFluids = null;
    _parenteralNutrition = null;
    _probiotic = null;
    _feedIntolerance = null;
    _necSuspected = null;
    _necConfirmedStage = null;
    _cholestasis = null;
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
    _antibiotics = d.antibiotics;
    _lpDone = d.lpDone;
    _meningitis = d.meningitis;
    _meningitisType = d.meningitisType;
    _clabsi = d.clabsi;
    _vap = d.vap;
    _npo = d.npo;
    _men = d.men;
    _enteralFeedsReceived = d.enteralFeedsReceived;
    _feedType = List.of(d.feedType);
    _cumulativeFeedCtrl.text =
        d.cumulativeFeedVolume?.toString() ?? '';
    _feedVolumeCtrl.text = d.feedVolume?.toString() ?? '';
    _ivFluids = d.ivFluids;
    _parenteralNutrition = d.parenteralNutrition;
    _probiotic = d.probiotic;
    _feedIntolerance = d.feedIntolerance;
    _necSuspected = d.necSuspected;
    _necConfirmedStage = d.necConfirmedStage;
    _cholestasis = d.cholestasis;
    _hbCtrl.text = d.hbValue?.toString() ?? '';
    _jaundice = d.jaundice;
    _phototherapy = d.phototherapy;
    _peakTsbCtrl.text = d.peakTsb?.toString() ?? '';
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
    d.antibiotics = _antibiotics;
    d.lpDone = _lpDone;
    d.meningitis = _meningitis;
    d.meningitisType = _meningitisType;
    d.clabsi = _clabsi;
    d.vap = _vap;
    d.npo = _npo;
    d.men = _men;
    d.enteralFeedsReceived = _enteralFeedsReceived;
    d.feedType = List.of(_feedType);
    d.cumulativeFeedVolume =
        double.tryParse(_cumulativeFeedCtrl.text.trim());
    d.feedVolume = double.tryParse(_feedVolumeCtrl.text.trim());
    d.ivFluids = _ivFluids;
    d.parenteralNutrition = _parenteralNutrition;
    d.probiotic = _probiotic;
    d.feedIntolerance = _feedIntolerance;
    d.necSuspected = _necSuspected;
    d.necConfirmedStage = _necConfirmedStage;
    d.cholestasis = _cholestasis;
    d.hbValue = double.tryParse(_hbCtrl.text.trim());
    d.jaundice = _jaundice;
    d.phototherapy = _phototherapy;
    d.peakTsb = double.tryParse(_peakTsbCtrl.text.trim());
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
    } else if (model.bloodCultureSent == false) {
      model.bloodCulturePositive = null;
    }
    if (model.meningitis == false) model.meningitisType = null;
    if (model.npo == true) {
      model.men = null;
      model.enteralFeedsReceived = null;
      model.feedType = [];
      model.cumulativeFeedVolume = null;
      model.feedVolume = null;
    } else if (model.enteralFeedsReceived == false) {
      model.feedType = [];
    }
    if (model.necSuspected == false) model.necConfirmedStage = null;
    if (model.jaundice == false) model.phototherapy = null;
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
      final raw = await _api.loadInfectGiHemaDay(
          widget.enrollmentId.trim(), _activeDay - 1);
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
    // Block invalid numeric text so tryParse→null cannot wipe a good server value.
    for (final entry in [
      ('Cumulative feed volume', _cumulativeFeedCtrl.text),
      ('Feed volume', _feedVolumeCtrl.text),
      ('Hb', _hbCtrl.text),
      ('Peak TSB', _peakTsbCtrl.text),
    ]) {
      final t = entry.$2.trim();
      if (t.isNotEmpty && double.tryParse(t) == null) {
        _toast('${entry.$1} is not a valid number — fix before saving',
            error: true);
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
        submissionStatus: 'draft',
        savedAt: now,
        savedBy: name,
      );
      await _api.saveInfectGiHemaDay(body, alreadyExists: _recordExists);
      final pct = _completion.percent;
      setState(() {
        _applyDay(model);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.of(context).danger : null,
      behavior: SnackBarBehavior.floating,
    ));
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
                            title: 'Infection Assessment',
                            icon: Icons.coronavirus_rounded,
                            color: c.primary,
                            children: _infectionFields(
                              c,
                              editable,
                              sepsisYes: sepsisYes,
                              cultureSentYes: cultureSentYes,
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
            widget.babyUid.isEmpty ? 'HELPER FORM 3' : widget.babyUid,
            style: TextStyle(
              color: c.primary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          Text(
            'Infection / GI / Hema Daily Log · ${widget.motherName.isEmpty ? widget.enrollmentId : widget.motherName}',
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

  List<Widget> _infectionFields(
    AppColors c,
    bool editable, {
    required bool sepsisYes,
    required bool cultureSentYes,
    required bool meningitisYes,
  }) {
    return [
      _yn('1. Sepsis Suspected', _sepsisSuspected, editable, (v) {
        setState(() {
          _sepsisSuspected = v;
          if (v != true) {
            _bloodCultureSent = null;
            _bloodCulturePositive = null;
          }
        });
      }, c),
      if (sepsisYes) ...[
        _yn('2. Blood Culture Sent', _bloodCultureSent, editable, (v) {
          setState(() {
            _bloodCultureSent = v;
            if (v != true) _bloodCulturePositive = null;
          });
        }, c),
        if (cultureSentYes)
          _yn('3. Blood Culture Positive', _bloodCulturePositive, editable,
              (v) => setState(() => _bloodCulturePositive = v), c),
      ],
      _yn('4. Antibiotics', _antibiotics, editable,
          (v) => setState(() => _antibiotics = v), c),
      _yn('5. LP Done', _lpDone, editable,
          (v) => setState(() => _lpDone = v), c),
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
      _yn('8. CLABSI', _clabsi, editable,
          (v) => setState(() => _clabsi = v), c),
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
          }
        });
      }, c),
      if (npoNo) ...[
        _yn('11. MEN (Minimal Enteral Nutrition)', _men, editable,
            (v) => setState(() => _men = v), c),
        _yn('12. Enteral Feeds Received', _enteralFeedsReceived, editable,
            (v) {
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
          child: _textField(_cumulativeFeedCtrl, c,
              enabled: editable,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              hint: '0',
              error: InfectGiHemaValidators.cumulativeFeedVolume(
                  _cumulativeFeedCtrl.text)),
        ),
        _fieldCard(
          c,
          number: '15',
          label: 'Feed Volume',
          hint: 'ml/kg/d',
          child: _textField(_feedVolumeCtrl, c,
              enabled: editable,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              hint: '0',
              error: InfectGiHemaValidators.feedVolume(_feedVolumeCtrl.text)),
        ),
      ],
      _yn('16. IV Fluids', _ivFluids, editable,
          (v) => setState(() => _ivFluids = v), c),
      _yn('17. Parenteral Nutrition', _parenteralNutrition, editable,
          (v) => setState(() => _parenteralNutrition = v), c),
      _yn('18. Probiotic', _probiotic, editable,
          (v) => setState(() => _probiotic = v), c),
      _yn('19. Feed Intolerance', _feedIntolerance, editable,
          (v) => setState(() => _feedIntolerance = v), c),
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
      _yn('22. Cholestasis', _cholestasis, editable,
          (v) => setState(() => _cholestasis = v), c),
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
        child: _textField(_hbCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '0.0',
            error: InfectGiHemaValidators.hb(_hbCtrl.text)),
      ),
      _yn('24. Jaundice', _jaundice, editable, (v) {
        setState(() {
          _jaundice = v;
          if (v != true) _phototherapy = null;
        });
      }, c),
      if (jaundiceYes)
        _yn('25. Phototherapy', _phototherapy, editable,
            (v) => setState(() => _phototherapy = v), c),
      _fieldCard(
        c,
        number: '26',
        label: 'Peak TSB',
        hint: 'mg/dL',
        child: _textField(_peakTsbCtrl, c,
            enabled: editable,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            hint: '0.0',
            error: InfectGiHemaValidators.peakTsb(_peakTsbCtrl.text)),
      ),
      _yn('27. Exchange Transfusion', _exchangeTransfusion, editable,
          (v) => setState(() => _exchangeTransfusion = v), c),
      _yn('28. PRBC Transfusion', _prbcTransfusion, editable,
          (v) => setState(() => _prbcTransfusion = v), c),
      _yn('29. Platelet Transfusion', _plateletTransfusion, editable,
          (v) => setState(() => _plateletTransfusion = v), c),
      _yn('30. FFP / Cryo Transfusion', _ffpCryo, editable,
          (v) => setState(() => _ffpCryo = v), c),
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
          onSelected: !enabled
              ? null
              : (_) => onChanged(sel ? null : opt),
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
      'Dec'
    ];
    return names[m - 1];
  }
}