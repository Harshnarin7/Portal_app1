// Helper Form 5 — Minimal Monitoring Log
// Parity with web MinimalMonitoringLog.jsx:
//   multi-entry blocks + entries_json dual-write + boundary_hour=11
//   Sheet date rolls at 11:00 local — form auto-refreshes to a new blank day.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/minimal_monitoring.dart';
import '../services/forms_api_service.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_date_picker.dart';
import '../widgets/theme_toggle_widget.dart';

class HelperForm5MinimalMonitoring extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;

  const HelperForm5MinimalMonitoring({
    super.key,
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
  });

  @override
  State<HelperForm5MinimalMonitoring> createState() =>
      _HelperForm5MinimalMonitoringState();
}

class _HelperForm5MinimalMonitoringState
    extends State<HelperForm5MinimalMonitoring> with WidgetsBindingObserver {
  final _api = FormsApiService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _sheetDate;
  String? _banner;
  bool _bannerError = false;
  Timer? _boundaryTimer;

  late MinimalMonitoringSheet _sheet;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, bool> _open = {
    '5.1': true,
    '5.2': true,
    '5.3': true,
    '5.4': true,
    '5.5': true,
    '5.6': true,
  };

  static const _shifts = ['Morning', 'Evening', 'Night'];
  static const _vasoactive = [
    'Dopamine',
    'Dobutamine',
    'Epinephrine',
    'Milrinone',
    'Vasopressin',
    'Norepinephrine',
  ];
  static const _pda = ['Indo', 'Ibu', 'PCM'];
  static const _respModes = [
    'NC',
    'HFNC',
    'CPAP',
    'NIPPV',
    'SIMV',
    'A/C',
    'PSV',
    'HFOV',
  ];
  static const _steroids = [
    'Hydrocortisone',
    'Dexamethasone',
    'Budesonide',
    'Other',
  ];
  static const _electrolytes = ['Na', 'K', 'Ionized Ca'];
  static const _transfuse = ['PRBC', 'Platelets', 'FFP/Cryo'];
  static const _ventSev = ['Mild', 'Moderate', 'Severe'];
  static const _vasoUnits = ['mg/kg/min', 'mcg/kg/min', 'U/kg/min'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheet = MinimalMonitoringSheet(enrollmentId: widget.enrollmentId);
    _loadToday();
    _scheduleBoundaryRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _boundaryTimer?.cancel();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSheetRollover(showBanner: true);
    }
  }

  /// Schedule reload at the next 11:00 local boundary (and each day after).
  void _scheduleBoundaryRefresh() {
    _boundaryTimer?.cancel();
    final next = mmlNextBoundary();
    final wait = next.difference(DateTime.now());
    // Tiny buffer so server clock / second rounding is past the boundary.
    final delay = wait.isNegative
        ? const Duration(seconds: 1)
        : wait + const Duration(seconds: 2);
    _boundaryTimer = Timer(delay, () async {
      if (!mounted) return;
      await _checkSheetRollover(showBanner: true);
      if (mounted) _scheduleBoundaryRefresh();
    });
  }

  /// If local sheet date no longer matches the loaded row, refresh to the new day.
  Future<void> _checkSheetRollover({bool showBanner = false}) async {
    final expected = mmlSheetDate();
    if (_sheetDate == null || _sheetDate == expected) {
      // Still same day — keep schedule; if we never got a date, reload once.
      if (_sheetDate == null && !_loading && !_loadFailed) {
        await _loadToday(quiet: true);
      }
      return;
    }
    await _loadToday(quiet: true);
    if (!mounted) return;
    if (showBanner) {
      setState(() {
        _banner =
            "New day's sheet started — previous values cleared after 11:00 AM";
        _bannerError = false;
      });
    }
  }

  // ── Controllers ─────────────────────────────────────────────────────────

  String _ck(String block, int i, String field) => '$block.$i.$field';

  TextEditingController _c(String block, int i, String field) {
    final key = _ck(block, i, field);
    final raw = _sheet.entries[block]![i][field];
    final text = raw == null ? '' : raw.toString();
    final existing = _ctrls[key];
    if (existing == null) {
      final c = TextEditingController(text: text);
      _ctrls[key] = c;
      return c;
    }
    if (existing.text != text && !existing.selection.isValid) {
      existing.text = text;
    }
    return existing;
  }

  void _disposeBlockCtrls(String block) {
    final prefix = '$block.';
    final keys = _ctrls.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _ctrls.remove(k)?.dispose();
    }
  }

  void _setField(String block, int i, String field, dynamic value) {
    setState(() {
      _sheet.entries[block]![i][field] = value;
    });
  }

  void _onText(String block, int i, String field, String value) {
    _sheet.entries[block]![i][field] = value;
  }

  List<String> _listOf(MmlEntry e, String field) {
    final v = e[field];
    if (v is List) {
      return v.map((x) => x.toString()).toList();
    }
    return const [];
  }

  void _addEntry(String block, Map<String, dynamic> blankFields) {
    setState(() {
      _sheet.entries[block] =
          List<MmlEntry>.from(_sheet.entries[block] ?? const [])
            ..add(MinimalMonitoringSheet.fresh(blankFields));
    });
  }

  void _removeEntry(String block, int index) {
    final list = _sheet.entries[block];
    if (list == null || list.length <= 1) return;
    setState(() {
      _disposeBlockCtrls(block);
      list.removeAt(index);
      _sheet.entries[block] = List<MmlEntry>.from(list);
    });
  }

  Future<void> _pickDate(String block, int i) async {
    final e = _sheet.entries[block]![i];
    final parsed = DateTime.tryParse(e.date);
    final initial = parsed ?? DateTime.now();
    final picked = await showModernDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      e.date =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickTime(String block, int i) async {
    final e = _sheet.entries[block]![i];
    final parts = e.time.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );
    if (picked == null) return;
    setState(() {
      e.time =
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  List<String> _splitTimeRange(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return ['', ''];
    final parts = s
        .split(RegExp(r'\s*[–—−-]\s*|\s+to\s+', caseSensitive: false))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    String toHm(String t) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$', caseSensitive: false)
          .firstMatch(t);
      if (m == null) return '';
      var h = int.tryParse(m.group(1)!) ?? 0;
      final min = (int.tryParse(m.group(2)!) ?? 0).clamp(0, 59);
      final ap = (m.group(3) ?? '').toUpperCase();
      if (ap == 'PM' && h < 12) h += 12;
      if (ap == 'AM' && h == 12) h = 0;
      return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    }

    if (parts.length == 1) return [toHm(parts[0]), ''];
    return [toHm(parts[0]), toHm(parts[1])];
  }

  String _joinTimeRange(String from, String to) {
    if (from.isNotEmpty && to.isNotEmpty) return '$from–$to';
    return from.isNotEmpty ? from : to;
  }

  String _fmtHmAmPm(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return hhmm.isEmpty ? '' : hhmm;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return hhmm;
    return TimeOfDay(hour: h, minute: m).format(context);
  }

  Future<void> _pickRangeTime(String block, int i, bool isFrom) async {
    final raw = (_sheet.entries[block]![i]['time_range'] ?? '').toString();
    final parts = _splitTimeRange(raw);
    final seed = isFrom ? parts[0] : parts[1];
    final sp = seed.split(':');
    final initial = TimeOfDay(
      hour: sp.isNotEmpty ? int.tryParse(sp[0]) ?? TimeOfDay.now().hour : TimeOfDay.now().hour,
      minute: sp.length > 1 ? int.tryParse(sp[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final hm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final from = isFrom ? hm : parts[0];
    final to = isFrom ? parts[1] : hm;
    _setField(block, i, 'time_range', _joinTimeRange(from, to));
  }

  Widget _timeRangeField(String block, int i) {
    final raw = (_sheet.entries[block]![i]['time_range'] ?? '').toString();
    final parts = _splitTimeRange(raw);
    final c = AppTheme.of(context);
    Widget chip(String label, String value, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              prefixIcon: const Icon(Icons.access_time_rounded, size: 18),
            ),
            child: Text(
              value.isEmpty ? label : _fmtHmAmPm(value),
              style: TextStyle(
                color: value.isEmpty ? c.textTertiary : c.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        chip('From', parts[0], () => _pickRangeTime(block, i, true)),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          child: Text('to', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w700)),
        ),
        chip('To', parts[1], () => _pickRangeTime(block, i, false)),
      ],
    );
  }

  // ── Load / Save ─────────────────────────────────────────────────────────

  Future<void> _loadToday({bool quiet = false}) async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      if (!quiet) _banner = null;
    });
    try {
      final data =
          await _api.loadMinimalMonitoringToday(widget.enrollmentId.trim());
      if (!mounted) return;
      final loaded = MinimalMonitoringSheet.fromJson({
        ...data,
        'enrollment_id': widget.enrollmentId.trim(),
      });
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      setState(() {
        _sheet = loaded;
        final cvA = loaded.entries['cv_a'];
        _sheetDate = data['record_date']?.toString() ??
            (cvA != null && cvA.isNotEmpty ? cvA.first.date : null) ??
            mmlSheetDate();
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      setState(() {
        _sheet = MinimalMonitoringSheet(enrollmentId: widget.enrollmentId);
        _sheetDate = null;
        _loadFailed = true;
        _loading = false;
        _banner = "Could not load today's sheet. Please try again.";
        _bannerError = true;
      });
    }
  }

  Future<void> _save() async {
    if (_loadFailed) {
    setState(() {
        _banner = 'Reload the sheet before saving.';
        _bannerError = true;
      });
      return;
    }
    // If 11:00 AM already passed while the form stayed open, start a new day
    // instead of writing into yesterday's sheet.
    final expected = mmlSheetDate();
    if (_sheetDate != null && _sheetDate != expected) {
      await _checkSheetRollover(showBanner: true);
      return;
    }
    final err = _sheet.validate();
    if (err != null) {
      setState(() {
        _banner = err;
        _bannerError = true;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await TokenStorage.getProfile();
      final savedBy = (profile?['full_name'] ?? profile?['username'] ?? 'Nurse')
          .toString()
          .trim();
      final by = savedBy.isEmpty ? 'Nurse' : savedBy;
      final result = await _api.saveMinimalMonitoringToday(
        widget.enrollmentId.trim(),
        _sheet.toJson(savedBy: by),
      );
      if (!mounted) return;
      setState(() {
        _sheetDate = result['record_date']?.toString() ?? _sheetDate;
        _banner = "Today's sheet saved";
        _bannerError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _banner = 'Error saving. Please try again.';
        _bannerError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI primitives ───────────────────────────────────────────────────────

  Widget _section({
    required String code,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final c = AppTheme.of(context);
    final open = _open[code] ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open[code] = !open),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: c.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$code $title',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryBlock({
    required String code,
    required String block,
    required Map<String, dynamic> Function() blankFactory,
    required List<Widget> Function(MmlEntry e, int i) fields,
  }) {
    final c = AppTheme.of(context);
    final list = _sheet.entries[block] ?? const <MmlEntry>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                code,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _addEntry(block, blankFactory()),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add values'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: c.primary,
                ),
              ),
            ],
          ),
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) Divider(color: c.border),
            Row(
              children: [
                if (list.length > 1)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
                      color: c.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                  fontWeight: FontWeight.w700,
                        color: c.primary,
          ),
        ),
      ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(block, i),
                    child: Text(
                      'Date ${list[i].date.isEmpty ? '—' : list[i].date}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (block != 'resp_a') ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(block, i),
                      child: Text(
                        'Time ${list[i].time.isEmpty ? '—' : list[i].time}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (list.length > 1)
                  IconButton(
                    onPressed: () => _removeEntry(block, i),
                    icon: Icon(Icons.delete_outline, color: c.danger),
                    tooltip: 'Remove',
                  ),
              ],
            ),
        const SizedBox(height: 8),
            ...fields(list[i], i),
          ],
        ],
      ),
    );
  }

  Widget _item(int n, String label, Widget child, {String? sub}) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text.rich(
            TextSpan(
      children: [
                TextSpan(
                  text: '$n. ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: c.primary,
                  ),
                ),
                TextSpan(
                  text: label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    fontSize: 13,
                  ),
                ),
                if (sub != null)
                  TextSpan(
                    text: '  $sub',
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _numField(
    String block,
    int i,
    String field, {
    String? unit,
    String? hint,
    bool integer = false,
  }) {
    final c = AppTheme.of(context);
    return TextField(
      controller: _c(block, i, field),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        if (integer)
          FilteringTextInputFormatter.digitsOnly
        else
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (v) => _onText(block, i, field, v),
      decoration: InputDecoration(
        hintText: hint ?? '0',
        isDense: true,
        suffixText: unit,
      filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _textField(
    String block,
    int i,
    String field, {
    String? hint,
  }) {
    final c = AppTheme.of(context);
    return TextField(
      controller: _c(block, i, field),
      onChanged: (v) => _onText(block, i, field, v),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _pillSingle(
    List<String> options,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final sel = value == o;
        return ChoiceChip(
          label: Text(o),
          selected: sel,
          onSelected: (_) => onChanged(sel ? '' : o),
            );
          }).toList(),
    );
  }

  Widget _pillMulti(
    List<String> options,
    List<String> selected,
    ValueChanged<List<String>> onChanged,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final sel = selected.contains(o);
            return FilterChip(
          label: Text(o),
              selected: sel,
              onSelected: (v) {
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

  Widget _yn(bool? value, ValueChanged<bool?> onChanged) {
    final c = AppTheme.of(context);
    Widget btn(String label, bool v, Color active) {
      final on = value == v;
      return Expanded(
        child: OutlinedButton(
          onPressed: () => onChanged(on ? null : v),
          style: OutlinedButton.styleFrom(
            backgroundColor: on ? active.withOpacity(0.15) : null,
            foregroundColor: on ? active : c.textPrimary,
            side: BorderSide(color: on ? active : c.border),
          ),
          child: Text(label),
        ),
      );
    }

    return Row(
      children: [
        btn('Yes', true, c.success),
        const SizedBox(width: 6),
        btn('No', false, c.danger),
      ],
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Helper Form 5 — Minimal Monitoring'),
        actions: const [ThemeToggle()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: c.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.motherName.isEmpty
                            ? 'Enrollment ${widget.enrollmentId}'
                            : widget.motherName,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        () {
                          final parts = <String>[];
                          if (widget.babyUid.isNotEmpty) {
                            parts.add('UID ${widget.babyUid}');
                          }
                          if (widget.gestation.isNotEmpty) {
                            parts.add(widget.gestation);
                          }
                          return parts.join(' · ');
                        }(),
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sheetDate != null && _sheetDate!.isNotEmpty
                            ? "Today's sheet ($_sheetDate) — clears automatically after 11:00 AM"
                            : "Today's sheet — clears automatically after 11:00 AM",
                        style: TextStyle(
                          color: c.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_banner != null)
                  MaterialBanner(
                    content: Text(
                      _banner!,
                      style: TextStyle(
                        color: _bannerError ? c.danger : c.success,
                      ),
                    ),
                    backgroundColor: (_bannerError ? c.danger : c.success)
                        .withOpacity(0.08),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _banner = null),
                        child: const Text('Dismiss'),
                      ),
                      if (_loadFailed)
                        TextButton(
                          onPressed: _loadToday,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _section(
                        code: '5.1',
                        title: 'Cardiovascular',
                        icon: Icons.favorite_outline,
                        children: [
                          _entryBlock(
                            code: '5.1.A',
                            block: 'cv_a',
                            blankFactory: () => {
                              'shift': '',
                              'axillary_temp': '',
                              'sbp': '',
                              'dbp': '',
                              'map_value': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Select Shift',
                                _pillSingle(
                                  _shifts,
                                  e['shift']?.toString(),
                                  (v) => _setField('cv_a', i, 'shift', v ?? ''),
                                ),
                              ),
                              _item(
                                2,
                                'Axillary Temp',
                                _numField('cv_a', i, 'axillary_temp',
                                    unit: '°C'),
                              ),
                              _item(
                                3,
                                'SBP',
                                _numField('cv_a', i, 'sbp', unit: 'mm Hg'),
                              ),
                              _item(
                                4,
                                'DBP',
                                _numField('cv_a', i, 'dbp', unit: 'mm Hg'),
                              ),
                              _item(
                                5,
                                'MAP',
                                _numField('cv_a', i, 'map_value',
                                    unit: 'mm Hg'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.1.B',
                            block: 'cv_b',
                            blankFactory: () => {'fluid_bolus_given': ''},
                            fields: (e, i) => [
                              _item(
                                1,
                                'Fluid Bolus given',
                                _textField(
                                  'cv_b',
                                  i,
                                  'fluid_bolus_given',
                                  hint: 'e.g. 10ml/kg NS',
                                ),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.1.C',
                            block: 'cv_c',
                            blankFactory: () => {
                              'vasoactive_drugs': <String>[],
                              'vasoactive_dose': '',
                              'vasoactive_unit': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Vasoactive given',
                                _pillMulti(
                                  _vasoactive,
                                  _listOf(e, 'vasoactive_drugs'),
                                  (v) => _setField(
                                      'cv_c', i, 'vasoactive_drugs', v),
                                ),
                              ),
                              _item(
                                2,
                                'Dose administered',
                                _textField('cv_c', i, 'vasoactive_dose'),
                              ),
                              _item(
                                3,
                                'Unit',
                                _pillSingle(
                                  _vasoUnits,
                                  e['vasoactive_unit']?.toString(),
                                  (v) => _setField(
                                      'cv_c', i, 'vasoactive_unit', v ?? ''),
                                ),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.1.D',
                            block: 'cv_d',
                            blankFactory: () => {
                              'pda_agent': <String>[],
                              'pda_dose': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Agent for Medical Rx of PDA',
                                _pillMulti(
                                  _pda,
                                  _listOf(e, 'pda_agent'),
                                  (v) =>
                                      _setField('cv_d', i, 'pda_agent', v),
                                ),
                              ),
                              _item(
                                2,
                                'Dose administered',
                                _numField('cv_d', i, 'pda_dose',
                                    unit: 'mg/kg'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _section(
                        code: '5.2',
                        title: 'Respiratory',
                        icon: Icons.air,
                        children: [
                          _entryBlock(
                            code: '5.2.A',
                            block: 'resp_a',
                            blankFactory: () => {
                              'time_range': '',
                              'respiratory_modes': <String>[],
                              'max_map_cpap': '',
                              'max_fio2': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Time: Btw',
                                _timeRangeField('resp_a', i),
                                sub: 'AM/PM range',
                              ),
                              _item(
                                2,
                                'Mode',
                                _pillMulti(
                                  _respModes,
                                  _listOf(e, 'respiratory_modes'),
                                  (v) => _setField(
                                      'resp_a', i, 'respiratory_modes', v),
                                ),
                              ),
                              _item(
                                3,
                                'Max MAP/CPAP of the hour',
                                _numField('resp_a', i, 'max_map_cpap',
                                    unit: 'cm H₂O'),
                              ),
                              _item(
                                4,
                                'Max FiO₂ of the hour',
                                _numField('resp_a', i, 'max_fio2', unit: '%'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.2.B',
                            block: 'resp_b',
                            blankFactory: () =>
                                {'ph': '', 'pao2': '', 'paco2': ''},
                            fields: (e, i) => [
                              _item(
                                  1, 'pH', _numField('resp_b', i, 'ph')),
                              _item(
                                2,
                                'PaO₂',
                                _numField('resp_b', i, 'pao2', unit: 'mmHg'),
                              ),
                              _item(
                                3,
                                'PaCO₂',
                                _numField('resp_b', i, 'paco2', unit: 'mmHg'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.2.C',
                            block: 'resp_c',
                            blankFactory: () => {
                              'shift': '',
                              'apnea_episodes': '',
                              'desaturation_episodes': '',
                              'severe_desaturation_episodes': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Select Shift',
                                _pillSingle(
                                  _shifts,
                                  e['shift']?.toString(),
                                  (v) =>
                                      _setField('resp_c', i, 'shift', v ?? ''),
                                ),
                              ),
                              _item(
                                2,
                                'Apnea Episodes',
                                _numField('resp_c', i, 'apnea_episodes',
                                    integer: true),
                              ),
                              _item(
                                3,
                                'Desaturation episodes',
                                _numField(
                                    'resp_c', i, 'desaturation_episodes',
                                    integer: true),
                              ),
                              _item(
                                4,
                                'Sev. desaturation episodes',
                                _numField('resp_c', i,
                                    'severe_desaturation_episodes',
                                    integer: true),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.2.D',
                            block: 'resp_d',
                            blankFactory: () => {
                              'postnatal_steroids': <String>[],
                              'steroid_dose': '',
                              'steroid_other': '',
                            },
                            fields: (e, i) {
                              final steroids =
                                  _listOf(e, 'postnatal_steroids');
                              return [
                                _item(
                                  1,
                                  'Postnatal steroids',
                                  _pillMulti(
                                    _steroids,
                                    steroids,
                                    (v) => _setField(
                                        'resp_d', i, 'postnatal_steroids', v),
                                  ),
                                ),
                                _item(
                                  2,
                                  'Dose administered',
                                  _numField('resp_d', i, 'steroid_dose',
                                      unit: 'mg/kg'),
                                ),
                                if (steroids.contains('Other'))
                                  _item(
                                    3,
                                    'If Other, specify',
                                    _textField(
                                      'resp_d',
                                      i,
                                      'steroid_other',
                                      hint: 'Other steroid name',
                                    ),
                                  ),
                              ];
                            },
                          ),
                        ],
                      ),
                      _section(
                        code: '5.3',
                        title: 'Metabolic',
                        icon: Icons.science_outlined,
                        children: [
                          _entryBlock(
                            code: '5.3.A',
                            block: 'met_a',
                            blankFactory: () => {'glucose': ''},
                            fields: (e, i) => [
                              _item(
                                1,
                                'Glucose',
                                _numField('met_a', i, 'glucose',
                                    unit: 'mg/dL'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.3.B',
                            block: 'met_b',
                            blankFactory: () => {
                              'alp': '',
                              'total_calcium': '',
                              'phosphorus': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'ALP',
                                _numField('met_b', i, 'alp', unit: 'IU/L'),
                              ),
                              _item(
                                2,
                                'Total Ca',
                                _numField('met_b', i, 'total_calcium',
                                    unit: 'mg/dL'),
                              ),
                              _item(
                                3,
                                'Phosphorus P',
                                _numField('met_b', i, 'phosphorus',
                                    unit: 'mg/dL'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.3.C',
                            block: 'met_c',
                            blankFactory: () => {
                              'electrolyte_abnormality': null,
                              'electrolytes': <String>[],
                              'hypo_hyper': '',
                              'symptomatic_status': '',
                              'symptomatic_detail': '',
                            },
                            fields: (e, i) {
                              final abn = e['electrolyte_abnormality'];
                              final status =
                                  e['symptomatic_status']?.toString();
                              return [
                                _item(
                                  1,
                                  'Electrolyte abnormality',
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _yn(
                                        abn is bool ? abn : null,
                                        (v) => _setField('met_c', i,
                                            'electrolyte_abnormality', v),
                                      ),
                                      if (abn == true) ...[
                                        const SizedBox(height: 8),
                                        _pillMulti(
                                          _electrolytes,
                                          _listOf(e, 'electrolytes'),
                                          (v) => _setField(
                                              'met_c', i, 'electrolytes', v),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                _item(
                                  2,
                                  'Hypo/Hyper',
                                  _pillSingle(
                                    const ['Hypo', 'Hyper'],
                                    e['hypo_hyper']?.toString(),
                                    (v) => _setField(
                                        'met_c', i, 'hypo_hyper', v ?? ''),
                                  ),
                                ),
                                _item(
                                  3,
                                  'Symptomatic/asymptomatic',
                                  _pillSingle(
                                    const ['symptomatic', 'asymptomatic'],
                                    status,
                                    (v) => _setField('met_c', i,
                                        'symptomatic_status', v ?? ''),
                                  ),
                                ),
                                if (status == 'symptomatic')
                                  _item(
                                    4,
                                    'If symptomatic',
                                    _textField(
                                        'met_c', i, 'symptomatic_detail'),
                                  ),
                              ];
                            },
                          ),
                        ],
                      ),
                      _section(
                        code: '5.4',
                        title: 'Gastrointestinal',
                        icon: Icons.restaurant_outlined,
                        children: [
                          _entryBlock(
                            code: '5.4.A',
                            block: 'gi_a',
                            blankFactory: () => {
                              'shift': '',
                              'cumulative_feed_volume': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Select Shift',
                                _pillSingle(
                                  _shifts,
                                  e['shift']?.toString(),
                                  (v) =>
                                      _setField('gi_a', i, 'shift', v ?? ''),
                                ),
                              ),
                              _item(
                                2,
                                'Cumulative feed volume',
                                _numField(
                                    'gi_a', i, 'cumulative_feed_volume',
                                    unit: 'ml'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.4.B',
                            block: 'gi_b',
                            blankFactory: () => {'direct_bilirubin': ''},
                            fields: (e, i) => [
                              _item(
                                1,
                                'Direct Bilirubin',
                                _numField('gi_b', i, 'direct_bilirubin',
                                    unit: 'mg/dL'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _section(
                        code: '5.5',
                        title: 'Neurological',
                        icon: Icons.psychology_outlined,
                        children: [
                          _entryBlock(
                            code: '5.5.A',
                            block: 'neuro_a',
                            blankFactory: () => {
                              'ventriculomegaly_severity': '',
                              'vi': '',
                              'ahw': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Severity of Ventriculomegaly',
                                _pillSingle(
                                  _ventSev,
                                  e['ventriculomegaly_severity']?.toString(),
                                  (v) => _setField('neuro_a', i,
                                      'ventriculomegaly_severity', v ?? ''),
                                ),
                              ),
                              _item(
                                2,
                                'VI',
                                _numField('neuro_a', i, 'vi', unit: 'mm'),
                              ),
                              _item(
                                3,
                                'AHW',
                                _numField('neuro_a', i, 'ahw', unit: 'mm'),
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.5.B',
                            block: 'neuro_b',
                            blankFactory: () =>
                                {'tod': '', 'aca_ri': '', 'mca_ri': ''},
                            fields: (e, i) => [
                              _item(
                                1,
                                'TOD',
                                _numField('neuro_b', i, 'tod', unit: 'mm'),
                              ),
                              _item(
                                2,
                                'ACA RI',
                                _numField('neuro_b', i, 'aca_ri'),
                              ),
                              _item(
                                3,
                                'MCA RI',
                                _numField('neuro_b', i, 'mca_ri'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _section(
                        code: '5.6',
                        title: 'Hematology',
                        icon: Icons.water_drop_outlined,
                        children: [
                          _entryBlock(
                            code: '5.6.A',
                            block: 'heme_a',
                            blankFactory: () => {
                              'transfusion_products': <String>[],
                              'transfusion_count': '',
                              'prbc_volume': '',
                            },
                            fields: (e, i) {
                              final products =
                                  _listOf(e, 'transfusion_products');
                              return [
                                _item(
                                  1,
                                  'Transfusion',
                                  _pillMulti(
                                    _transfuse,
                                    products,
                                    (v) => _setField(
                                        'heme_a', i, 'transfusion_products', v),
                                  ),
                                ),
                                _item(
                                  2,
                                  'No. of transfusions',
                                  _numField(
                                      'heme_a', i, 'transfusion_count',
                                      integer: true),
                                ),
                                if (products.contains('PRBC'))
                                  _item(
                                    3,
                                    'If PRBC, volume',
                                    _numField('heme_a', i, 'prbc_volume',
                                        unit: 'ml/kg'),
                                  ),
                              ];
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_saving || _loading || _loadFailed) ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}