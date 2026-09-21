// Daily Monitoring Sheet (DMS) — Minimal Monitoring Log
// Parity with web MinimalMonitoringLog.jsx:
//   multi-entry blocks + entries_json dual-write
//   Sheet date dropdown (8:00 cutoff) + GET/PUT .../on/{date}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/minimal_monitoring.dart';
import '../models/resp_cv_neuro_day.dart';
import '../utils/mml_resp_sync_bus.dart';
import '../utils/mml_table_fields.dart';
import '../utils/mml_validation_hints.dart';
import '../widgets/field_validation_info.dart';
import '../services/forms_api_service.dart';
import '../services/helper_day_draft_storage.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../navigation/helper_forms_navigation.dart';
import '../widgets/helper_patient_header.dart';
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

class _HelperForm5MinimalMonitoringState extends State<HelperForm5MinimalMonitoring> {
  static const _kMmDraftKey = 'mm5';

  final _api = FormsApiService.instance;

  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  bool _dirty = false;
  String? _sheetDate;
  String? _banner;
  bool _bannerError = false;

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
    _sheet = MinimalMonitoringSheet(enrollmentId: widget.enrollmentId);
    _loadSheetForDate(mmlDefaultSheetDate());
  }

  void _markDirty() => _dirty = true;

  @override
  void dispose() {
    unawaited(_stashMmDraft());
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Controllers ─────────────────────────────────────────────────────────

  String _ck(String block, int i, String field) => '$block.$i.$field';

  TextEditingController _c(String block, int i, String field) {
    final key = _ck(block, i, field);
    final raw = _sheet.entries[block]![i][field];
    var text = raw == null ? '' : raw.toString();
    if (block == 'cv_b' && field == 'fluid_bolus_given') {
      text = mmlNormalizeFluidBolusValue(text);
    }
    final existing = _ctrls[key];
    if (existing == null) {
      final c = TextEditingController(text: text);
      _ctrls[key] = c;
      return c;
    }
    if (existing.text != text) {
      final composing = existing.value.composing;
      final inIme = composing.isValid && !composing.isCollapsed;
      if (!inIme) {
        existing.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
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
    _markDirty();
    setState(() {
      final entry = _sheet.entries[block]![i];
      entry[field] = value;
      if (block == 'resp_c') {
        mmlApplyRespCEpisodeConstraints(entry);
      }
    });
  }

  void _onText(String block, int i, String field, String value) {
    _markDirty();
    setState(() {
      final entry = _sheet.entries[block]![i];
      if (block == 'cv_b' && field == 'fluid_bolus_given') {
        entry[field] = mmlNormalizeFluidBolusValue(value);
      } else {
        entry[field] = value;
      }
      if (block == 'resp_c') {
        mmlApplyRespCEpisodeConstraints(entry);
        if (field == 'desaturation_episodes') {
          final severeKey = _ck(block, i, 'severe_desaturation_episodes');
          final ctrl = _ctrls[severeKey];
          final severeText =
              entry['severe_desaturation_episodes']?.toString() ?? '';
          if (ctrl != null && ctrl.text != severeText) {
            ctrl.text = severeText;
          }
        }
      }
    });
  }

  List<String> _listOf(MmlEntry e, String field) {
    final v = e[field];
    if (v is List) {
      return v.map((x) => x.toString()).toList();
    }
    return const [];
  }

  void _logAnotherReading(
    String block,
    Map<String, dynamic> Function() blankFactory,
  ) {
    _markDirty();
    setState(() {
      _disposeBlockCtrls(block);
      final list = List<MmlEntry>.from(_sheet.entries[block] ?? const []);
      final e = MinimalMonitoringSheet.fresh(blankFactory());
      if (_sheetDate != null) e.date = _sheetDate!;
      list.add(e);
      _sheet.entries[block] = list;
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
    final dateYmd = _sheetDate ?? e.date;
    var hm =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    hm = mmlClampTimeHm(dateYmd, hm);
    if (mmlIsFutureDateTime(dateYmd, hm)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time cannot be in the future')),
        );
      }
      return;
    }
    setState(() {
      e.time = hm;
      _markDirty();
    });
  }

  void _removeEntry(String block, int index) {
    final list = _sheet.entries[block];
    if (list == null || list.length <= 1) return;
    _markDirty();
    setState(() {
      _disposeBlockCtrls(block);
      list.removeAt(index);
      _sheet.entries[block] = List<MmlEntry>.from(list);
      _ensureAllTrailingDrafts();
    });
  }

  /// Each block keeps a blank draft row at the end (web `openBlock` / EntryBlock).
  void _ensureAllTrailingDrafts() {
    final templates = MinimalMonitoringSheet.emptyEntries();
    for (final block in kMmlBlockKeys) {
      var list = _sheet.entries[block];
      if (list == null || list.isEmpty) {
        _sheet.entries[block] = List<MmlEntry>.from(templates[block] ?? const []);
        list = _sheet.entries[block];
      }
      if (_sheetDate != null) {
        for (final e in list!) {
          e.date = _sheetDate!;
        }
      }
      if (list!.last.hasClinicalData()) {
        final blank = templates[block]!.first.copy();
        if (_sheetDate != null) blank.date = _sheetDate!;
        list.add(blank);
      }
    }
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
    final entry = _sheet.entries[block]![i];
    final dateYmd = _sheetDate ?? entry.date;
    var hm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    hm = mmlClampTimeHm(dateYmd, hm);
    if (mmlIsFutureDateTime(dateYmd, hm)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Time cannot be in the future')),
        );
      }
      return;
    }
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

  Future<void> _stashMmDraft() async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return;
    final date = _sheetDate ?? mmlDefaultSheetDate();
    await HelperDayDraftStorage.saveBySheetDate(
      _kMmDraftKey,
      eid,
      date,
      {
        'record_date': date,
        'sheet': _sheet.toJson(savedBy: 'local-draft'),
      },
    );
  }

  Future<bool> _tryRestoreMmDraft(String sheetDate) async {
    final eid = widget.enrollmentId.trim();
    if (eid.isEmpty) return false;
    final raw = await HelperDayDraftStorage.loadBySheetDate(
      _kMmDraftKey,
      eid,
      sheetDate,
    );
    if (raw == null) return false;
    final sheetMap = raw['sheet'];
    if (sheetMap is! Map) return false;
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _sheet = MinimalMonitoringSheet.fromJson({
      ...Map<String, dynamic>.from(sheetMap),
      'enrollment_id': eid,
    });
    _sheetDate = raw['record_date']?.toString() ?? sheetDate;
    _ensureAllTrailingDrafts();
    return true;
  }

  Future<void> _requestSheetDateChange(String? nextYmd) async {
    if (nextYmd == null || nextYmd.isEmpty || nextYmd == _sheetDate) return;
    if (_dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved changes on this date. Switch anyway? Unsaved edits will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _banner = null);
    await _loadSheetForDate(nextYmd);
  }

  Future<void> _loadSheetForDate(String ymd, {bool quiet = false}) async {
    if (!_loading && (_sheetDate != null || _ctrls.isNotEmpty)) {
      await _stashMmDraft();
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
      if (!quiet) _banner = null;
    });
    try {
      final data = await _api.loadMinimalMonitoringOnDate(
        widget.enrollmentId.trim(),
        ymd,
      );
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
        _sheetDate = data['record_date']?.toString() ?? ymd;
        mmlSanitizeFluidBolusEntries(_sheet.entries);
        _ensureAllTrailingDrafts();
        _loading = false;
        _loadFailed = false;
        _dirty = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (await _tryRestoreMmDraft(ymd)) {
        setState(() {
          _loadFailed = false;
          _loading = false;
          _dirty = false;
          _banner =
              'Restored unsaved draft (could not reach server). Tap Save when online.';
          _bannerError = false;
        });
        return;
      }
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      setState(() {
        _sheet = MinimalMonitoringSheet(enrollmentId: widget.enrollmentId);
        _sheetDate = ymd;
        mmlSanitizeFluidBolusEntries(_sheet.entries);
        _ensureAllTrailingDrafts();
        _loadFailed = true;
        _loading = false;
        _dirty = false;
        _banner = 'Could not load sheet for this date. Please try again.';
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
    if (_sheetDate == null || _sheetDate!.isEmpty) {
      setState(() {
        _banner = 'Select a sheet date before saving.';
        _bannerError = true;
      });
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
    final sheetYmd = _sheetDate!;
    setState(() {
      _saving = true;
    });
    try {
      final profile = await TokenStorage.getProfile();
      final savedBy = (profile?['full_name'] ?? profile?['username'] ?? 'Nurse')
          .toString()
          .trim();
      final by = savedBy.isEmpty ? 'Nurse' : savedBy;
      final result = await _api.saveMinimalMonitoringOnDate(
        widget.enrollmentId.trim(),
        sheetYmd,
        _sheet.toJson(savedBy: by, sheetRecordDate: sheetYmd),
      );
      if (!mounted) return;
      final savedDate =
          result['record_date']?.toString() ?? sheetYmd;
      if (result.isNotEmpty) {
        for (final c in _ctrls.values) {
          c.dispose();
        }
        _ctrls.clear();
        _sheet = MinimalMonitoringSheet.fromJson({
          ...result,
          'enrollment_id': widget.enrollmentId.trim(),
        });
        mmlSanitizeFluidBolusEntries(_sheet.entries);
        _ensureAllTrailingDrafts();
      }
      await HelperDayDraftStorage.clearBySheetDate(
        _kMmDraftKey,
        widget.enrollmentId.trim(),
        savedDate,
      );
      if (!mounted) return;
      MmlRespSyncBus.notifySaved(
        enrollmentId: widget.enrollmentId.trim(),
        sheetYmd: savedDate,
      );
      setState(() {
        _sheetDate = savedDate;
        _banner = 'Sheet saved (${mmlFormatDisplayDateYmd(savedDate)}). This reading stays on the form — use Log another reading to start a new one.';
        _bannerError = false;
        _dirty = false;
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

  Widget _readingsTable(
    String block,
    List<MmlEntry> list,
    int draftIdx,
  ) {
    final c = AppTheme.of(context);
    final cols = mmlTableFieldsForBlock(block);
    final showStampTime = block != 'resp_a';
    final tableRows = <({MmlEntry entry, int idx, bool isDraft})>[];
    for (var i = 0; i < list.length; i++) {
      if (i != draftIdx && list[i].hasClinicalData()) {
        tableRows.add((entry: list[i], idx: i, isDraft: false));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Readings (${tableRows.length})',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          if (tableRows.isEmpty)
            Text(
              'No entries yet for this field today.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 56,
                columns: [
                  const DataColumn(label: Text('Date')),
                  if (showStampTime) const DataColumn(label: Text('Time')),
                  ...cols.map((f) => DataColumn(label: Text(f.label))),
                  const DataColumn(label: Text('')),
                ],
                rows: tableRows.reversed.map((row) {
                  return DataRow(
                    color: row.isDraft
                        ? MaterialStateProperty.all(
                            c.primary.withOpacity(0.06),
                          )
                        : null,
                    cells: [
                      DataCell(Text(
                        row.entry.date.isEmpty ? '—' : row.entry.date,
                      )),
                      if (showStampTime)
                        DataCell(Text(
                          row.entry.time.isEmpty ? '—' : row.entry.time,
                        )),
                      ...cols.map(
                        (f) => DataCell(
                          Text(mmlFormatTableCell(f, row.entry)),
                        ),
                      ),
                      DataCell(
                        row.isDraft
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: c.danger,
                                ),
                                tooltip: 'Remove reading',
                                onPressed: () =>
                                    _removeEntry(block, row.idx),
                              ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryBlock({
    String? code,
    String? subsectionTitle,
    required String block,
    required Map<String, dynamic> Function() blankFactory,
    required List<Widget> Function(MmlEntry e, int i) fields,
  }) {
    final c = AppTheme.of(context);
    final list = _sheet.entries[block] ?? const <MmlEntry>[];
    if (list.isEmpty) {
      return const SizedBox.shrink();
    }
    final draftIdx = list.length - 1;
    final draft = list[draftIdx];
    final sheetDate = _sheetDate ?? draft.date;
    final showStampTime = block != 'resp_a';
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
          if (subsectionTitle != null || (code != null && code.isNotEmpty))
            Row(
              children: [
                Text(
                  subsectionTitle ?? code!,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: c.primary,
                    fontSize: subsectionTitle != null ? 14 : 13,
                  ),
                ),
              ],
            ),
          if (subsectionTitle != null || (code != null && code.isNotEmpty))
            const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        draft.hasClinicalData() ? 'Current reading' : 'New reading',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Date',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                          ),
                        ),
                        const FieldValidationInfo(hint: kMmlDateStampHint),
                        const SizedBox(width: 4),
                        Text(
                          sheetDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (showStampTime) ...[
                      const SizedBox(width: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Time',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                            ),
                          ),
                          const FieldValidationInfo(hint: kMmlTimeStampHint),
                          const SizedBox(width: 4),
                          OutlinedButton(
                            onPressed: () => _pickTime(block, draftIdx),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                            ),
                            child: Text(
                              draft.time.isEmpty ? 'Set time' : draft.time,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (draft.hasClinicalData())
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          _logAnotherReading(block, blankFactory),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Log another reading'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: c.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ...fields(draft, draftIdx),
              ],
            ),
          ),
          _readingsTable(block, list, draftIdx),
        ],
      ),
    );
  }

  Widget _item(
    Object n,
    String label,
    Widget child, {
    String? sub,
    String? validationHint,
  }) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
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
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (validationHint != null)
                FieldValidationInfo(hint: validationHint),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  List<Widget> _respAMapCpapItems(MmlEntry e, int i) {
    final modes = _listOf(e, 'respiratory_modes');
    final mode = RespCvNeuroValidators.mapCpapMode(modes);
    final c = AppTheme.of(context);
    if (mode == 'NA') {
      return [
        _item(
          3,
          'Max MAP/CPAP of the hour',
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Text(
              'NA — mode doesn\'t generate pressure',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ),
        ),
      ];
    }
    if (mode == 'BOTH') {
      return [
        _item(
          3,
          'Max CPAP of the hour',
          _numField('resp_a', i, 'max_map_cpap_secondary', unit: 'cm H₂O'),
        ),
        _item(
          '3b',
          'Max MAP of the hour',
          _numField('resp_a', i, 'max_map_cpap', unit: 'cm H₂O'),
        ),
      ];
    }
    final label = mode == 'CPAP'
        ? 'Max CPAP of the hour'
        : mode == 'MAP'
            ? 'Max MAP of the hour'
            : 'Max MAP/CPAP of the hour';
    return [
      _item(
        3,
        label,
        _numField('resp_a', i, 'max_map_cpap', unit: 'cm H₂O'),
      ),
    ];
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
        title: const Text('Daily Monitoring Sheet (DMS)'),
        actions: [
          HelperFormSwitcherButton(
            current: HelperFormKind.minimalMonitoring,
            patient: HelperFormPatientContext(
              enrollmentId: widget.enrollmentId,
              gestation: widget.gestation,
              motherName: widget.motherName,
              babyUid: widget.babyUid,
            ),
          ),
          const ThemeToggle(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: c.surface,
                  child: HelperPatientHeader(
                    formBadge: 'DAILY MONITORING SHEET (DMS)',
                    formName: 'Minimal Monitoring',
                    subtitle:
                        'Sheet date — before $kMmlDropdownCutoffHour:00 you can choose yesterday or today; '
                        'from $kMmlDropdownCutoffHour:00 onward only today.',
                    enrollmentId: widget.enrollmentId,
                    gestation: widget.gestation,
                    babyUid: widget.babyUid,
                    showBoCard: false,
                    showMotherCard: true,
                    motherName: widget.motherName,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Builder(
                    builder: (context) {
                      final opts = mmlDropdownDateOptions();
                      if (opts.length > 1) {
                        final selected = _sheetDate != null &&
                                opts.any((o) => o.value == _sheetDate)
                            ? _sheetDate!
                            : opts.last.value;
                        return Row(
                          children: [
                            Text(
                              'Date',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: selected,
                              onChanged: _loading
                                  ? null
                                  : (v) => _requestSheetDateChange(v),
                              items: opts
                                  .map(
                                    (o) => DropdownMenuItem(
                                      value: o.value,
                                      child: Text(o.label),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        );
                      }
                      return Text(
                        _sheetDate != null && _sheetDate!.isNotEmpty
                            ? mmlFormatDisplayDateYmd(_sheetDate!)
                            : '—',
                        style: TextStyle(
                          color: c.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
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
                          onPressed: () => _loadSheetForDate(
                            _sheetDate ?? mmlDefaultSheetDate(),
                          ),
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
                              'axillary_temp': '',
                              'sbp': '',
                              'dbp': '',
                              'map_value': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Axillary Temp',
                                _numField('cv_a', i, 'axillary_temp',
                                    unit: '°C'),
                              ),
                              _item(
                                2,
                                'SBP',
                                _numField('cv_a', i, 'sbp', unit: 'mm Hg'),
                              ),
                              _item(
                                3,
                                'DBP',
                                _numField('cv_a', i, 'dbp', unit: 'mm Hg'),
                              ),
                              _item(
                                4,
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
                                _numField(
                                  'cv_b',
                                  i,
                                  'fluid_bolus_given',
                                  hint: 'e.g. 10',
                                  integer: true,
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
                              'max_map_cpap_secondary': '',
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
                                  (v) {
                                    final prevMode = RespCvNeuroValidators
                                        .mapCpapMode(
                                            _listOf(e, 'respiratory_modes'));
                                    final nextMode =
                                        RespCvNeuroValidators.mapCpapMode(v);
                                    _setField(
                                        'resp_a', i, 'respiratory_modes', v);
                                    if (prevMode == 'CPAP' &&
                                        nextMode == 'BOTH') {
                                      _setField(
                                          'resp_a',
                                          i,
                                          'max_map_cpap_secondary',
                                          e['max_map_cpap'] ?? '');
                                      _setField(
                                          'resp_a', i, 'max_map_cpap', '');
                                    } else if (prevMode == 'BOTH' &&
                                        nextMode == 'CPAP') {
                                      _setField(
                                          'resp_a',
                                          i,
                                          'max_map_cpap',
                                          e['max_map_cpap_secondary'] ?? '');
                                      _setField('resp_a', i,
                                          'max_map_cpap_secondary', '');
                                    } else if (nextMode == 'NA') {
                                      _setField('resp_a', i, 'max_map_cpap', '');
                                      _setField(
                                          'resp_a', i, 'max_map_cpap_secondary', '');
                                    } else if (nextMode != 'BOTH') {
                                      _setField(
                                          'resp_a', i, 'max_map_cpap_secondary', '');
                                    }
                                  },
                                ),
                              ),
                              ..._respAMapCpapItems(e, i),
                              _item(
                                4,
                                'Max FiO₂ of the hour',
                                _numField('resp_a', i, 'max_fio2', unit: '%'),
                                validationHint: kMmlHintMaxFio2,
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
                                1,
                                'pH',
                                _numField('resp_b', i, 'ph'),
                                validationHint: kMmlHintPh,
                              ),
                              _item(
                                2,
                                'PaO₂',
                                _numField('resp_b', i, 'pao2', unit: 'mmHg'),
                                validationHint: kMmlHintPao2,
                              ),
                              _item(
                                3,
                                'PaCO₂',
                                _numField('resp_b', i, 'paco2', unit: 'mmHg'),
                                validationHint: kMmlHintPaco2,
                              ),
                            ],
                          ),
                          _entryBlock(
                            code: '5.2.C',
                            block: 'resp_c',
                            blankFactory: () => {
                              'apnea_episodes': '',
                              'desaturation_episodes': '',
                              'severe_desaturation_episodes': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
                                'Apnea Episodes',
                                _numField('resp_c', i, 'apnea_episodes',
                                    integer: true),
                                validationHint: kMmlHintEpisodeCount,
                              ),
                              _item(
                                2,
                                'Desaturation episodes',
                                _numField(
                                    'resp_c', i, 'desaturation_episodes',
                                    integer: true),
                                validationHint: kMmlHintEpisodeCount,
                              ),
                              _item(
                                3,
                                'Sev. desaturation episodes',
                                _numField('resp_c', i,
                                    'severe_desaturation_episodes',
                                    integer: true),
                                validationHint: kMmlHintSevereDesat,
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
                                    validationHint: kMmlHintSteroidOther,
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
                                    validationHint: kMmlHintSymptomaticDetail,
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
                              'cumulative_feed_volume': '',
                            },
                            fields: (e, i) => [
                              _item(
                                1,
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
                            subsectionTitle: 'Ventriculomegaly',
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
                            subsectionTitle: 'Doppler',
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
                                  validationHint: kMmlHintTransfusionCount,
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