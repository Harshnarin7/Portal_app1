import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/forms_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Helper Form 1 — FiO₂ AUC
// Parity with web frontend-app/src/FiO2AUC.jsx
// ═══════════════════════════════════════════════════════════════════════════

class _FiO2Row {
  final String id;
  String fio2;
  String dur;

  _FiO2Row({String? id, this.fio2 = '', this.dur = ''})
      : id = id ?? UniqueKey().toString();

  double get rowAuc {
    final f = double.tryParse(fio2) ?? 0;
    final d = double.tryParse(dur) ?? 0;
    return (f / 100.0) * d;
  }

  Map<String, dynamic> toEntryJson() => {'fio2': fio2, 'dur': dur};
}

class _FiO2Day {
  final int day;
  bool expanded;
  String start1;
  String start2;
  List<_FiO2Row> w1;
  List<_FiO2Row> w2;

  _FiO2Day({
    required this.day,
    this.expanded = false,
    this.start1 = '',
    this.start2 = '',
    List<_FiO2Row>? w1,
    List<_FiO2Row>? w2,
  })  : w1 = w1 ?? [_FiO2Row(dur: '12')],
        w2 = w2 ?? [_FiO2Row(dur: '12')];

  double windowHours(List<_FiO2Row> rows) =>
      rows.fold(0.0, (s, r) => s + (double.tryParse(r.dur) ?? 0));

  double windowAuc(List<_FiO2Row> rows) =>
      rows.fold(0.0, (s, r) => s + r.rowAuc);

  double get dayAuc => windowAuc(w1) + windowAuc(w2);

  bool get isComplete {
    final h1 = windowHours(w1);
    final h2 = windowHours(w2);
    // Default row duration is 12h for data-entry speed — hours alone must
    // NOT count as complete, or the card collapses on the first FiO₂ keystroke.
    if ((h1 - 12).abs() >= 0.01 || (h2 - 12).abs() >= 0.01) return false;
    bool hasFio2(List<_FiO2Row> rows) =>
        rows.isNotEmpty && rows.every((r) => r.fio2.trim().isNotEmpty);
    return hasFio2(w1) && hasFio2(w2);
  }

  /// Hours-only check (for progress bars / snackbars).
  bool get hoursComplete {
    final h1 = windowHours(w1);
    final h2 = windowHours(w2);
    return (h1 - 12).abs() < 0.01 && (h2 - 12).abs() < 0.01;
  }

  bool get hasEnteredData {
    if (w1.length > 1 || w2.length > 1) return true;
    bool hasFio2(List<_FiO2Row> rows) =>
        rows.any((r) => r.fio2.trim().isNotEmpty);
    return hasFio2(w1) || hasFio2(w2);
  }
}

class HelperFiO2AUC extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;

  const HelperFiO2AUC({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
  });

  @override
  State<HelperFiO2AUC> createState() => _HelperFiO2AUCState();
}

class _HelperFiO2AUCState extends State<HelperFiO2AUC> {
  final _api = FormsApiService.instance;
  List<_FiO2Day> _days = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _saving = false;
  bool _hasExistingRecord = false;
  bool _dirty = false;
  /// False until FiO₂ GET succeeds — blocks server autosave so a failed load
  /// cannot PUT empty stubs over good web data.
  bool _serverLoadOk = false;
  /// Last known server fio2_logs — merged on save so days not currently shown
  /// (e.g. Supplemental O₂ flipped to No) are not wiped.
  List<Map<String, dynamic>> _lastServerLogs = [];
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_dirty && !_saving && _serverLoadOk) {
        _persist(silent: true, validate: false);
      }
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_dirty &&
        _serverLoadOk &&
        widget.enrollmentId.trim().isNotEmpty) {
      _persist(silent: true, validate: false);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    await _syncDaysFromHelper2(preserveLocal: false, showToast: false);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncDaysFromHelper2({
    bool preserveLocal = true,
    bool showToast = false,
  }) async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) {
      if (mounted) setState(() => _days = []);
      return;
    }
    if (showToast) setState(() => _refreshing = true);

    try {
      final summary = await _api.loadRespCvNeuroSummary(eid);
      // FiO₂ AUC days = Helper Form 2 days with Supplemental O₂ = Yes
      // (not Surfactant — that was the incorrect gate).
      final oxygenDays = summary
          .where((s) => _isTruthyFlag(s['supp_o2']))
          .map((s) => _asInt(s['nicu_day']))
          .whereType<int>()
          .where((n) => n >= 1)
          .toSet();

      // Never treat GET failure as "empty record" — that enabled wipe-on-autosave.
      final record = await _api.loadFiO2(eid);
      final serverLogs = (record?['fio2_logs'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      _lastServerLogs =
          serverLogs.map((e) => Map<String, dynamic>.from(e)).toList();
      _serverLoadOk = true;
      if (record != null) _hasExistingRecord = true;

      // Merge local draft under server: fill empty server stubs from local;
      // keep server when it already has FiO₂ values (web is source of truth).
      final localLogs = await _loadLocalLogs(eid);
      final mergedLogs = <Map<String, dynamic>>[
        ...serverLogs.map((e) => Map<String, dynamic>.from(e)),
      ];
      for (final l in localLogs) {
        final day = _asInt(l['day']);
        final block = (l['block']?.toString() ?? '');
        if (day == null || block.isEmpty) continue;
        final idx = mergedLogs.indexWhere((m) =>
            _asInt(m['day']) == day &&
            (m['block']?.toString() ?? '') == block);
        if (idx < 0) {
          if (_logHasFio2(l)) mergedLogs.add(Map<String, dynamic>.from(l));
        } else if (_logHasFio2(l) && !_logHasFio2(mergedLogs[idx])) {
          mergedLogs[idx] = Map<String, dynamic>.from(l);
        }
      }

      // Union: Helper 2 Supplemental O₂=Yes days + any day that already has
      // FiO₂ values (so flipping O₂ to No never hides/drops entered AUC).
      final dayNums = <int>{...oxygenDays};
      for (final l in mergedLogs) {
        if (!_logHasFio2(l)) continue;
        final d = _asInt(l['day']);
        if (d != null && d >= 1) dayNums.add(d);
      }
      final sortedDays = dayNums.toList()..sort();

      final prevByDay = {
        for (final d in _days) d.day: d,
      };

      final built = <_FiO2Day>[];
      for (var i = 0; i < sortedDays.length; i++) {
        final n = sortedDays[i];
        if (preserveLocal &&
            prevByDay[n] != null &&
            prevByDay[n]!.hasEnteredData) {
          // Keep the nurse's expand/collapse state — do not force day 1 open.
          built.add(prevByDay[n]!);
          continue;
        }
        final expand = !preserveLocal
            ? i == 0
            : (prevByDay[n]?.expanded ?? (i == 0 && built.every((d) => !d.expanded)));
        built.add(_dayFromLogs(n, mergedLogs, expand: expand));
      }

      // Ensure at least one unlocked incomplete day stays open after sync.
      if (built.isNotEmpty && !built.any((d) => d.expanded)) {
        final firstOpen = built.indexWhere((d) => !d.isComplete);
        built[firstOpen >= 0 ? firstOpen : 0].expanded = true;
      }

      if (mounted) {
    setState(() {
          _days = built;
          _refreshing = false;
        });
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(sortedDays.isEmpty
                ? 'No Supplemental O₂ days in Helper Form 2 yet'
                : 'Synced ${sortedDays.length} day'
                    '${sortedDays.length == 1 ? '' : 's'} for FiO₂ AUC'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      _serverLoadOk = false;
      if (mounted) {
        setState(() => _refreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not load FiO₂ / Helper 2 data — server save disabled until refresh succeeds: $e'),
          backgroundColor: AppTheme.of(context).danger,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  static bool _isTruthyFlag(dynamic v) {
    if (v == true || v == 1) return true;
    final s = v?.toString().trim().toLowerCase() ?? '';
    return s == 'true' || s == 'yes' || s == '1';
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static bool _logHasFio2(Map<String, dynamic> log) {
    final entries = log['entries'];
    if (entries is! List || entries.isEmpty) return false;
    for (final e in entries) {
      if (e is! Map) continue;
      final fio2 = e['fio2']?.toString().trim() ?? '';
      if (fio2.isNotEmpty) return true;
    }
    return false;
  }

  _FiO2Day _dayFromLogs(int dayNum, List<Map<String, dynamic>> logs,
      {required bool expand}) {
    Map<String, dynamic>? w1Log;
    Map<String, dynamic>? w2Log;
    for (final l in logs) {
      if (_asInt(l['day']) != dayNum) continue;
      final block = (l['block'] ?? '').toString();
      // Web: "0-12h" / "12-24h". Legacy mobile: "1-0" / "1-1".
      if (block.startsWith('0') ||
          block.endsWith('-0') ||
          block.contains('0-12')) {
        w1Log = l;
      } else if (block.startsWith('12') ||
          block.endsWith('-1') ||
          block.contains('12-24')) {
        w2Log = l;
      }
    }
    w1Log ??= logs.cast<Map<String, dynamic>?>().firstWhere(
          (l) => l != null && l['block']?.toString() == '$dayNum-0',
          orElse: () => null,
        );
    w2Log ??= logs.cast<Map<String, dynamic>?>().firstWhere(
          (l) => l != null && l['block']?.toString() == '$dayNum-1',
          orElse: () => null,
        );

    return _FiO2Day(
      day: dayNum,
      expanded: expand,
      start1: (w1Log?['start_time'] ?? '').toString(),
      start2: (w2Log?['start_time'] ?? '').toString(),
      w1: _restoreEntries(w1Log),
      w2: _restoreEntries(w2Log),
    );
  }

  List<_FiO2Row> _restoreEntries(Map<String, dynamic>? log) {
    if (log == null) return [_FiO2Row(dur: '12')];
    final entries = log['entries'];
    if (entries is! List || entries.isEmpty) return [_FiO2Row(dur: '12')];
    return entries.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      // Web: dur; legacy mobile: hours
      final dur = m['dur'] ?? m['hours'] ?? '';
      final fio2 = m['fio2'] ?? '';
      return _FiO2Row(
        fio2: fio2.toString(),
        dur: dur.toString(),
      );
    }).toList();
  }

  // ── KPIs (match web hours-logged formulas) ────────────────────────────────

  double get _hoursLogged => _days.fold(
      0.0, (s, d) => s + d.windowHours(d.w1) + d.windowHours(d.w2));

  double get _grandTotal =>
      _days.fold(0.0, (s, d) => s + d.dayAuc);

  double get _meanFiO2 {
    final h = _hoursLogged;
    if (h <= 0) return 0;
    return (_grandTotal / h) * 100;
  }

  double get _excessO2 {
    final h = _hoursLogged;
    return (_grandTotal - 0.21 * h).clamp(0.0, double.infinity);
  }

  int get _daysComplete => _days.where((d) => d.isComplete).length;

  // ── Mutations ─────────────────────────────────────────────────────────────

  void _markDirty() => _dirty = true;

  void _toggleDay(int dayNum) {
    setState(() {
      for (final d in _days) {
        if (d.day == dayNum) d.expanded = !d.expanded;
      }
    });
  }

  bool _isDayLocked(int index) {
    if (index <= 0) return false;
    return !_days[index - 1].isComplete;
  }

  void _addRow(_FiO2Day day, bool isW1) {
    if (_isDayLocked(_days.indexOf(day))) return;
    setState(() {
      final rows = isW1 ? day.w1 : day.w2;
      final last = rows.isNotEmpty ? rows.last : null;
      final remaining =
          (12 - day.windowHours(rows)).clamp(0.0, 12.0);
      rows.add(_FiO2Row(
        fio2: last?.fio2 ?? '',
        dur: remaining > 0 ? remaining.toStringAsFixed(
            remaining == remaining.roundToDouble() ? 0 : 2) : '',
      ));
      _markDirty();
    });
  }

  void _delRow(_FiO2Day day, bool isW1, String id) {
    setState(() {
      final rows = isW1 ? day.w1 : day.w2;
      if (rows.length <= 1) return;
      rows.removeWhere((r) => r.id == id);
      _markDirty();
    });
  }

  void _updateRow(_FiO2Day day, bool isW1, String id, String field, String value) {
    final rows = isW1 ? day.w1 : day.w2;
    final prevHrs = day.windowHours(rows);
    final wasComplete = day.isComplete;
    setState(() {
      for (final r in rows) {
        if (r.id != id) continue;
        if (field == 'fio2') r.fio2 = value;
        if (field == 'dur') r.dur = value;
      }
      _markDirty();

      final newHrs = day.windowHours(rows);
      final justHitTwelve =
          (newHrs - 12).abs() < 0.01 && (prevHrs - 12).abs() >= 0.01;
      if (justHitTwelve && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Day ${day.day} · ${isW1 ? '1–12h' : '13–24h'} window complete (12 h)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }

      // Auto-collapse only when the day *newly* becomes complete (FiO₂ filled
      // in both 12h windows) — never on the first keystroke of a blank card.
      if (!wasComplete && day.isComplete) {
        final idx = _days.indexOf(day);
        day.expanded = false;
        if (idx >= 0 && idx < _days.length - 1) {
          _days[idx + 1].expanded = true;
        }
      }
    });
  }

  void _updateStart(_FiO2Day day, bool isStart1, TimeOfDay? t) {
    if (t == null) return;
    setState(() {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      final value = '$hh:$mm';
      if (isStart1) {
        day.start1 = value;
        if (day.start2.trim().isEmpty) {
          final total = (t.hour * 60 + t.minute + 12 * 60) % (24 * 60);
          day.start2 =
              '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
        }
      } else {
        day.start2 = value;
      }
      _markDirty();
    });
  }

  // ── Persist (web-shaped fio2_logs) ────────────────────────────────────────

  List<Map<String, dynamic>> _buildLogs() {
    final out = <Map<String, dynamic>>[];
    for (final d in _days) {
      out.add({
        'day': d.day,
        'block': '0-12h',
        'start_time': d.start1,
        'entries': d.w1.map((r) => r.toEntryJson()).toList(),
      });
      out.add({
        'day': d.day,
        'block': '12-24h',
        'start_time': d.start2,
        'entries': d.w2.map((r) => r.toEntryJson()).toList(),
      });
    }
    return out;
  }

  /// Upsert UI day/blocks onto last server logs so hidden days are preserved.
  List<Map<String, dynamic>> _mergeLogsForSave(
      List<Map<String, dynamic>> uiLogs) {
    final merged = _lastServerLogs
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final u in uiLogs) {
      final day = _asInt(u['day']);
      final block = (u['block']?.toString() ?? '');
      if (day == null || block.isEmpty) continue;
      final idx = merged.indexWhere((m) =>
          _asInt(m['day']) == day && (m['block']?.toString() ?? '') == block);
      if (idx < 0) {
        merged.add(Map<String, dynamic>.from(u));
      } else {
        merged[idx] = Map<String, dynamic>.from(u);
      }
    }
    return merged;
  }

  Future<void> _saveLocal(List<Map<String, dynamic>> logs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'fio2_auc_${widget.enrollmentId}', jsonEncode(logs));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadLocalLogs(String eid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('fio2_auc_$eid');
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String? _validate() {
    for (final day in _days) {
      for (final win in [day.w1, day.w2]) {
        final label = identical(win, day.w1) ? '0-12h' : '12-24h';
        for (final row in win) {
          if (row.fio2.trim().isNotEmpty) {
            final f = double.tryParse(row.fio2);
            if (f == null || f < 0 || f > 100) {
              return 'FiO₂ must be 0–100 (Day ${day.day}, $label)';
            }
          }
          if (row.dur.trim().isNotEmpty) {
            final d = double.tryParse(row.dur);
            if (d == null || d <= 0 || d > 12) {
              return 'Duration must be 0–12 h (Day ${day.day}, $label)';
            }
          }
        }
        if (day.windowHours(win) > 12.01) {
          return '$label window exceeds 12 hours on Day ${day.day}';
        }
      }
    }
    return null;
  }

  Future<bool> _persist({
    required bool silent,
    required bool validate,
    bool popAfter = false,
  }) async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enrollment ID missing'),
        ));
      }
      return false;
    }
    if (!_serverLoadOk) {
      // Keep draft locally only — never overwrite server after a failed GET.
      final localOnly = _buildLogs();
      await _saveLocal(localOnly);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Server data not loaded yet — draft kept on device. Tap Refresh, then Save.'),
          backgroundColor: AppTheme.of(context).warning,
        ));
      }
      return false;
    }
    if (validate) {
      final err = _validate();
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.of(context).danger,
          ));
        }
        return false;
      }
    }

    setState(() => _saving = true);
    final uiLogs = _buildLogs();
    final logs = _mergeLogsForSave(uiLogs);
    await _saveLocal(logs);

    final total = double.parse(_grandTotal.toStringAsFixed(3));
    final mean = double.parse(_meanFiO2.toStringAsFixed(1));
    final excess = double.parse(_excessO2.toStringAsFixed(2));

    try {
      await _api.saveFiO2(
        enrollmentId: eid,
        blocks: logs,
        totalAuc: total,
        meanDailyFio2: mean,
        excessO2Auc: excess,
        hasExistingRecord: true, // PUT upsert — shared row with web
      );
      _hasExistingRecord = true;
      _lastServerLogs =
          logs.map((e) => Map<String, dynamic>.from(e)).toList();
      _dirty = false;
      if (!mounted) return true;
      setState(() => _saving = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(validate ? 'FiO₂ data saved' : 'Draft saved'),
          backgroundColor: AppTheme.of(context).success,
          behavior: SnackBarBehavior.floating,
        ));
      }
      if (popAfter) Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed (kept locally): $e'),
          backgroundColor: AppTheme.of(context).warning,
        ));
      }
      if (popAfter) Navigator.of(context).pop(true);
      return false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text('Helper Form 1 — FiO₂ AUC',
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          Text(
              widget.enrollmentId.isEmpty
                  ? 'No enrollment'
                  : widget.enrollmentId,
            style: TextStyle(color: c.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
          IconButton(
            tooltip: 'Refresh from Helper 2',
            onPressed: _refreshing
                ? null
                : () => _syncDaysFromHelper2(
                    preserveLocal: true, showToast: true),
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: c.primary))
                : Icon(Icons.refresh_rounded, color: c.primary),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 8),
              child: Center(child: ThemeToggle())),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(c),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary))
          : _days.isEmpty
              ? _emptyState(c)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    // Header meta matches web: Enrollment ID + Gestation only
                    // (no mother name / baby UID — those are not on web FiO2AUC).
                    _headerMeta(c),
                    const SizedBox(height: 12),
                    _kpiStrip(c),
                    const SizedBox(height: 14),
                    ...List.generate(_days.length, (i) {
                      final day = _days[i];
                      final locked = _isDayLocked(i);
                      return _dayCard(c, day, locked);
                    }),
                    const SizedBox(height: 10),
                    _formulaInfo(c),
                  ],
                ),
    );
  }

  Widget _emptyState(AppColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.air_rounded, size: 48, color: c.textTertiary),
          const SizedBox(height: 14),
          Text('No Supplemental O₂ days yet',
              style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'FiO₂ AUC days come from Helper Form 2 days where Supplemental O₂ = Yes.\n'
            'Complete those days in Helper Form 2, then tap Refresh.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () =>
                _syncDaysFromHelper2(preserveLocal: true, showToast: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh from Helper 2'),
              ),
            ]),
      ),
    );
  }

  Widget _headerMeta(AppColors c) {
    Widget badge(String label, String value) {
      return Container(
        margin: const EdgeInsets.only(right: 8, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value.isEmpty ? '—' : value,
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ],
        ),
      );
    }

    return Wrap(children: [
      badge('Enrollment ID', widget.enrollmentId),
      if (widget.gestation.trim().isNotEmpty)
        badge('Gestation', widget.gestation),
    ]);
  }

  Widget _kpiStrip(AppColors c) {
    Widget cell(String label, String value, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.borderLight),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textTertiary, fontSize: 9)),
          ]),
        ),
      );
    }

    return Row(children: [
      cell('Total AUC', _grandTotal.toStringAsFixed(3), c.primary),
      cell('Excess O₂', _excessO2.toStringAsFixed(2), c.warning),
      cell('Mean FiO₂ %', _meanFiO2.toStringAsFixed(1), c.success),
      cell('Days done', '$_daysComplete / ${_days.length}', c.textPrimary),
    ]);
  }

  Widget _formulaInfo(AppColors c) {
    // Same copy as web FiO2AUC.jsx info-card.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logging Rules & Formulas',
              style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            '• Daily Cumulative AUC = Sum of (FiO₂ × Hours) for the full 24h period.\n'
            '• Excess O₂ AUC = Total Cumulative AUC − (21% × 24 hours).\n'
            '• Record actual FiO₂ delivered, even if it differs from the prescribed set point.\n'
            '• If FiO₂ changed within a 12h block, add a new row to record the duration of each FiO₂ level.',
            style:
                TextStyle(color: c.textSecondary, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(AppColors c, _FiO2Day day, bool locked) {
    final meanDay = (day.dayAuc / 24) * 100;
    final excessDay = (day.dayAuc - 0.21 * 24).clamp(0.0, double.infinity);

    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: day.isComplete
                ? c.success.withOpacity(0.45)
                : c.borderLight,
          ),
        ),
        child: Column(children: [
          InkWell(
            onTap: locked ? null : () => _toggleDay(day.day),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
              decoration: BoxDecoration(
                    color: day.isComplete ? c.successSoft : c.primarySoft,
                borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${day.day}',
                      style: TextStyle(
                          color: day.isComplete ? c.success : c.primary,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Day ${day.day}',
                style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                      Text(
                        locked
                            ? 'Complete Day ${_days[_days.indexOf(day) - 1].day} first'
                            : day.isComplete
                                ? 'VALIDATED · AUC ${day.dayAuc.toStringAsFixed(2)}'
                                : day.expanded
                                    ? 'Incomplete'
                                    : 'AUC ${day.dayAuc.toStringAsFixed(2)} · Mean ${((day.dayAuc / 24) * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            color: c.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (day.isComplete)
                  Icon(Icons.check_circle_rounded,
                      color: c.success, size: 20)
                else if (locked)
                  Icon(Icons.lock_rounded, color: c.textTertiary, size: 18)
                else
                  Icon(
                    day.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: c.textSecondary,
            ),
          ]),
        ),
          ),
          if (day.expanded && !locked) ...[
            Divider(height: 1, color: c.borderLight),
        Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: _timeField(
                            c,
                            'Start timing hour of life — 1–12hr',
                            day.start1, () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _parseTod(day.start1) ??
                            const TimeOfDay(hour: 8, minute: 0),
                      );
                      _updateStart(day, true, t);
                    })),
                  const SizedBox(width: 10),
                    Expanded(
                        child: _timeField(
                            c,
                            'Start timing hour of life — 13–24h',
                            day.start2, () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _parseTod(day.start2) ??
                            const TimeOfDay(hour: 20, minute: 0),
                      );
                      _updateStart(day, false, t);
                    })),
                  ]),
                  const SizedBox(height: 12),
                  _windowCard(c, day, true),
                  const SizedBox(height: 10),
                  _windowCard(c, day, false),
                  const SizedBox(height: 12),
                  Row(children: [
                    _miniMetric(c, 'Daily AUC', day.dayAuc.toStringAsFixed(2)),
                    _miniMetric(c, 'Mean Daily FiO₂',
                        '${meanDay.toStringAsFixed(1)}%'),
                    _miniMetric(
                        c, 'Excess O₂ AUC', excessDay.toStringAsFixed(2)),
                  ]),
                ],
              ),
            ),
          ],
          ]),
        ),
    );
  }

  Widget _windowCard(AppColors c, _FiO2Day day, bool isW1) {
    final rows = isW1 ? day.w1 : day.w2;
    final hrs = day.windowHours(rows);
    final auc = day.windowAuc(rows);
    final title = isW1 ? 'WINDOW: 1 – 12 HOURS' : 'WINDOW: 13 – 24 HOURS';
    final remaining = (12 - hrs).clamp(0.0, 12.0);
    final over = hrs > 12.01;
    final done = (hrs - 12).abs() < 0.01;

    return Container(
      padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.borderLight),
        ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
          Text(title,
              style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          const Spacer(),
          Text('Window AUC ${auc.toStringAsFixed(3)}',
              style: TextStyle(
                  color: c.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
              Expanded(
              child: Text('FiO₂ (%)',
                  style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600))),
              Expanded(
              child: Text('Duration (hr)',
                  style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600))),
          const SizedBox(
              width: 52,
              child: Text('AUC',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600))),
          const SizedBox(width: 36),
        ]),
                    const SizedBox(height: 4),
        ...rows.map((row) {
          final fioErr = row.fio2.isNotEmpty &&
              ((double.tryParse(row.fio2) ?? -1) < 21 ||
                  (double.tryParse(row.fio2) ?? 999) > 100);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${row.id}-fio2'),
                  initialValue: row.fio2,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '21–100',
                    errorText: fioErr ? '21–100' : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) =>
                      _updateRow(day, isW1, row.id, 'fio2', v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextFormField(
                  key: ValueKey('${row.id}-dur'),
                  initialValue: row.dur,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0–12',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) =>
                      _updateRow(day, isW1, row.id, 'dur', v),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  row.rowAuc > 0 ? row.rowAuc.toStringAsFixed(2) : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.close_rounded,
                      size: 18,
                      color: rows.length <= 1
                          ? c.textTertiary
                          : c.danger),
                  onPressed: rows.length <= 1
                      ? null
                      : () => _delRow(day, isW1, row.id),
                ),
              ),
                          ]),
                        );
        }),
        TextButton.icon(
          onPressed: () => _addRow(day, isW1),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add FiO₂ Change',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (hrs / 12).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: c.borderLight,
            color: over
                ? c.danger
                : done
                    ? c.success
                    : c.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          over
              ? '${hrs.toStringAsFixed(1)} / 12 h — exceeds 12h'
              : done
                  ? '${hrs.toStringAsFixed(1)} / 12 h'
                  : '${hrs.toStringAsFixed(1)} / 12 h — ${remaining.toStringAsFixed(1)}h remaining',
          style: TextStyle(
            color: over
                ? c.danger
                : done
                    ? c.success
                    : c.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }

  Widget _timeField(
      AppColors c, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        child: Text(
          value.isEmpty ? 'HH:MM' : value,
                      style: TextStyle(
            color: value.isEmpty ? c.textTertiary : c.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(AppColors c, String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderLight),
        ),
        child: Column(children: [
          Text(value,
            style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
          Text(label,
              style: TextStyle(color: c.textTertiary, fontSize: 9)),
        ]),
      ),
    );
  }

  TimeOfDay? _parseTod(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Widget _buildBottomBar(AppColors c) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderLight)),
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.save_outlined, size: 15, color: c.warning),
              label: Text('Save for Later',
                  style: TextStyle(
                      color: c.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              onPressed: _saving
                  ? null
                  : () => _persist(
                      silent: false, validate: false, popAfter: true),
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
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline_rounded,
                      size: 16, color: Colors.white),
              label: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              onPressed: _saving
                  ? null
                  : () => _persist(silent: false, validate: true),
            style: ElevatedButton.styleFrom(
                backgroundColor: c.success,
                padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
        ]),
      ),
    );
  }
}
