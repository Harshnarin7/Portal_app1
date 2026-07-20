import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/forms_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';

// ─── MODEL ────────────────────────────────────────────────────────────────────

class FiO2Entry {
  final double fio2;
  final double hours;
  final String mode;

  const FiO2Entry({
    required this.fio2,
    required this.hours,
    this.mode = '',
  });

  Map<String, dynamic> toJson() => {
        'fio2' : fio2,
        'hours': hours,
        'mode' : mode,
      };

  factory FiO2Entry.fromJson(Map<String, dynamic> j) => FiO2Entry(
        fio2 : (j['fio2']  as num).toDouble(),
        hours: (j['hours'] as num).toDouble(),
        mode : (j['mode']  as String? ?? ''),
      );
}

class BlockData {
  List<FiO2Entry> entries;

  BlockData({List<FiO2Entry>? entries}) : entries = entries ?? [];

  double get totalHours =>
      entries.fold(0.0, (s, e) => s + e.hours);

  bool get isComplete =>
      entries.isNotEmpty &&
      (totalHours - 12).abs() < 0.01 &&
      entries.every((e) => e.mode.isNotEmpty);

  double get auc => entries.fold(0.0, (s, e) {
        final fio2 = e.mode == 'RA' ? 0.21 : (e.fio2 / 100.0);
        return s + fio2 * e.hours;
      });

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory BlockData.fromJson(Map<String, dynamic> j) => BlockData(
        entries: (j['entries'] as List)
            .map((e) => FiO2Entry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ─── STORAGE ──────────────────────────────────────────────────────────────────

class _FiO2Storage {
  static String _key(String uid) => 'fio2_auc_$uid';

  static Future<Map<String, BlockData>> load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key(uid));
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) =>
          MapEntry(k, BlockData.fromJson(v as Map<String, dynamic>)));
    } catch (_) { return {}; }
  }

  static Future<void> save(String uid, Map<String, BlockData> blocks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid),
          jsonEncode(blocks.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
  }
}

// ─── CONSTANTS ────────────────────────────────────────────────────────────────

const _kModes  = ['RA', 'NC', 'HFNC', 'CPAP', 'NIPPV', 'SIMV', 'HFOV', 'HFO'];
const _kDays   = 7;
const _kBlocks = ['0–12 h', '12–24 h'];

// ─── WIDGET ───────────────────────────────────────────────────────────────────

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

class _HelperFiO2AUCState extends State<HelperFiO2AUC>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;
  bool _isLoading = true;

  // "day-block" → BlockData  (day: 1..7, block: 0 or 1)
  Map<String, BlockData> _blocks = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _kDays, vsync: this);
    _initBlocks();
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _initBlocks() {
    for (int d = 1; d <= _kDays; d++) {
      for (int b = 0; b < 2; b++) {
        _blocks.putIfAbsent('$d-$b', () => BlockData());
      }
    }
  }

  Future<void> _loadData() async {
    Map<String, BlockData> saved = {};
    try {
      final remote = await FormsApiService.instance.loadFiO2(widget.babyUid);
      final raw = remote['blocks'] as Map<String, dynamic>? ?? {};
      if (raw.isNotEmpty) {
        saved = raw.map((k, v) =>
            MapEntry(k, BlockData.fromJson(v as Map<String, dynamic>)));
      } else {
        saved = await _FiO2Storage.load(widget.babyUid);
      }
    } catch (_) {
      saved = await _FiO2Storage.load(widget.babyUid);
    }
    if (!mounted) return;
    setState(() {
      for (final k in saved.keys) _blocks[k] = saved[k]!;
      _isLoading = false;
    });
  }

  Future<void> _persist() async {
    await _FiO2Storage.save(widget.babyUid, _blocks);
    try {
      final blocksMap = _blocks.map((k, v) => MapEntry(k, v.toJson()));
      await FormsApiService.instance.saveFiO2(
        babyUid: widget.babyUid,
        blocks : blocksMap,
      );
    } catch (e) {
      debugPrint('FiO2 backend sync failed: $e');
    }
  }

  // ── Calculations ──────────────────────────────────────────────────────────

  double _dayAUC(int day) =>
      _blocks['$day-0']!.auc + _blocks['$day-1']!.auc;

  double _totalAUC() {
    double s = 0;
    for (int d = 1; d <= _kDays; d++) s += _dayAUC(d);
    return s;
  }

  double _meanFiO2()  => (_totalAUC() / 168.0) * 100.0;
  double _excessO2()  => _totalAUC() - (0.21 * 168.0);

  bool _isDayComplete(int day) =>
      _blocks['$day-0']!.isComplete && _blocks['$day-1']!.isComplete;

  int get _completedDays {
    int c = 0;
    for (int d = 1; d <= _kDays; d++) if (_isDayComplete(d)) c++;
    return c;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(child: CircularProgressIndicator(
            color: c.primary, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _buildAppBar(c),
      body: Column(children: [
        _buildDayTabs(c),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: List.generate(_kDays, (i) => _buildDayTab(i + 1, c)),
          ),
        ),
      ]),
      bottomNavigationBar: _buildBottomBar(c),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.babyUid,
              style: TextStyle(color: c.primary, fontSize: 13,
                  fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          Text(
            "${widget.motherName}  |  "
            "${widget.enrollmentId}  |  ${widget.gestation}",
            style: TextStyle(color: c.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        // Progress chip
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _completedDays == _kDays
                ? c.successSoft : c.primarySoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _completedDays == _kDays
                  ? c.success.withOpacity(0.4) : c.primary.withOpacity(0.3),
            ),
          ),
          child: Text(
            "$_completedDays / $_kDays days",
            style: TextStyle(
              color: _completedDays == _kDays ? c.success : c.primary,
              fontWeight: FontWeight.bold, fontSize: 12,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
    );
  }

  // ── Day tabs ──────────────────────────────────────────────────────────────

  Widget _buildDayTabs(AppColors c) {
    return Container(
      color: c.surface,
      child: TabBar(
        controller         : _tabCtrl,
        isScrollable       : true,
        indicatorColor     : c.primary,
        indicatorWeight    : 2,
        labelColor         : c.primary,
        unselectedLabelColor: c.textTertiary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: List.generate(_kDays, (i) {
          final done = _isDayComplete(i + 1);
          return Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text("Day ${i + 1}"),
              const SizedBox(width: 5),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c.success : c.border,
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  // ── Day tab body ──────────────────────────────────────────────────────────

  Widget _buildDayTab(int day, AppColors c) {
    final dayAuc  = _dayAUC(day);
    final meanDay = (dayAuc / 24.0) * 100.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Day summary strip
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDayComplete(day)
                  ? c.success.withOpacity(0.3) : c.border,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            _miniMetric("Day AUC",   dayAuc.toStringAsFixed(2), c.primary, c),
            const SizedBox(width: 10),
            _miniMetric("Mean FiO₂", "${meanDay.toStringAsFixed(1)}%", c.purple, c),
            const SizedBox(width: 10),
            _miniMetric(
              "Status",
              _isDayComplete(day) ? "Complete" : "Pending",
              _isDayComplete(day) ? c.success : c.warning, c,
            ),
          ]),
        ),

        const SizedBox(height: 20),

        ...[0, 1].map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildBlockCard(day, b, c),
            )),
      ]),
    );
  }

  // ── Block card ────────────────────────────────────────────────────────────

  Widget _buildBlockCard(int day, int blockIdx, AppColors c) {
    final key   = '$day-$blockIdx';
    final block = _blocks[key]!;
    final label = _kBlocks[blockIdx];

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: block.isComplete
              ? c.success.withOpacity(0.3) : c.border,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Block header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: c.borderLight)),
          ),
          child: Row(children: [
            Container(width: 3, height: 18,
                decoration: BoxDecoration(
                    color: c.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: c.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            // AUC badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.purple.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.purple.withOpacity(0.3)),
              ),
              child: Text("AUC: ${block.auc.toStringAsFixed(2)}",
                  style: TextStyle(color: c.purple,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: block.isComplete
                    ? c.successSoft : c.warningSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: block.isComplete
                      ? c.success.withOpacity(0.3) : c.warning.withOpacity(0.3),
                ),
              ),
              child: Text(
                block.isComplete ? "✓ Done" : "Pending",
                style: TextStyle(
                  color: block.isComplete ? c.success : c.warning,
                  fontSize: 11, fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _buildHoursBar(block, c),
            const SizedBox(height: 14),

            // Column headers
            if (block.entries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(flex: 3, child: Text("FiO₂ %",
                      style: TextStyle(color: c.textTertiary,
                          fontSize: 11, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: Text("Duration (h)",
                      style: TextStyle(color: c.textTertiary,
                          fontSize: 11, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: Center(child: Text("AUC",
                      style: TextStyle(color: c.textTertiary,
                          fontSize: 11, fontWeight: FontWeight.w600)))),
                  const SizedBox(width: 42), // delete button space
                ]),
              ),
            ],

            ...block.entries.asMap().entries.map(
                (e) => _buildEntryRow(key, block, e.key, c)),

            const SizedBox(height: 4),
            _buildAddEntryRow(key, block, c),
          ]),
        ),
      ]),
    );
  }

  // ── Hours bar ─────────────────────────────────────────────────────────────

  Widget _buildHoursBar(BlockData block, AppColors c) {
    final hours = block.totalHours.clamp(0.0, 12.0);
    final pct   = hours / 12.0;
    final over  = block.totalHours > 12.0;
    final exact = (block.totalHours - 12.0).abs() < 0.01;
    final color = over ? c.danger : exact ? c.success : c.primary;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text("Hours logged: ",
            style: TextStyle(color: c.textTertiary, fontSize: 12)),
        Text("${block.totalHours.toStringAsFixed(1)} / 12 h",
            style: TextStyle(color: color,
                fontWeight: FontWeight.bold, fontSize: 12)),
        if (over) ...[
          const SizedBox(width: 8),
          Text("(${(block.totalHours - 12).toStringAsFixed(1)}h over)",
              style: TextStyle(color: c.danger, fontSize: 11)),
        ],
        if (exact) ...[
          const SizedBox(width: 8),
          Text("Complete!",
              style: TextStyle(color: c.success, fontSize: 11)),
        ],
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct, minHeight: 5,
          backgroundColor: c.border,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }

  // ── Entry row ─────────────────────────────────────────────────────────────

  Widget _buildEntryRow(String key, BlockData block, int idx, AppColors c) {
    final entry = block.entries[idx];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceAlt.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.borderLight),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Row 1: FiO₂ | Duration | AUC | Delete ────────────────
            Row(children: [

              // FiO₂
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("FiO₂ %", style: TextStyle(
                        color: c.textTertiary, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: entry.fio2 == 0
                          ? "" : entry.fio2.toStringAsFixed(0),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(color: c.textPrimary, fontSize: 14),
                      decoration: _inputDec("21–100", c).copyWith(
                        suffixText: "%",
                        suffixStyle: TextStyle(color: c.primary),
                      ),
                      onChanged: (v) {
                        final val = double.tryParse(v) ?? 21.0;
                        setState(() {
                          block.entries[idx] = FiO2Entry(
                            fio2 : val.clamp(21, 100),
                            hours: entry.hours,
                            mode : entry.mode,
                          );
                        });
                        _persist();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Duration
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Duration (h)", style: TextStyle(
                        color: c.textTertiary, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: entry.hours == 0
                          ? "" : entry.hours.toStringAsFixed(
                              entry.hours % 1 == 0 ? 0 : 1),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: TextStyle(color: c.textPrimary, fontSize: 14),
                      decoration: _inputDec("e.g. 3.5", c).copyWith(
                        suffixText: "h",
                        suffixStyle: TextStyle(color: c.primary),
                      ),
                      onChanged: (v) {
                        final val = double.tryParse(v) ?? 0;
                        setState(() {
                          block.entries[idx] = FiO2Entry(
                            fio2 : entry.fio2,
                            hours: val,
                            mode : entry.mode,
                          );
                        });
                        _persist();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // AUC
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text("AUC", style: TextStyle(
                        color: c.textTertiary, fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: c.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.purple.withOpacity(0.2)),
                      ),
                      child: Center(
                        child: Text(
                          (() {
                            final fio2 = entry.mode == 'RA'
                                ? 0.21 : (entry.fio2 / 100.0);
                            return (fio2 * entry.hours).toStringAsFixed(2);
                          })(),
                          style: TextStyle(color: c.purple,
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // Delete
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: GestureDetector(
                  onTap: () {
                    setState(() => block.entries.removeAt(idx));
                    _persist();
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: c.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.danger.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.remove_rounded,
                        color: c.danger, size: 18),
                  ),
                ),
              ),
            ]),

            // ── Row 2: Mode dropdown ──────────────────────────────────
            const SizedBox(height: 10),
            Row(children: [
              Text("Mode",
                  style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: entry.mode.isNotEmpty
                        ? c.primary.withOpacity(0.07) : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: entry.mode.isNotEmpty
                          ? c.primary.withOpacity(0.4) : c.border,
                      width: entry.mode.isNotEmpty ? 1.5 : 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: entry.mode.isEmpty ? null : entry.mode,
                      hint: Text("Select respiratory mode",
                          style: TextStyle(
                              color: c.textTertiary, fontSize: 12)),
                      dropdownColor: c.surface,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: entry.mode.isNotEmpty
                              ? c.primary : c.textTertiary,
                          size: 20),
                      isExpanded: true,
                      items: _kModes.map((m) {
                        final isSel = m == entry.mode;
                        return DropdownMenuItem(
                          value: m,
                          child: Row(children: [
                            if (isSel)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(Icons.check_circle_rounded,
                                    color: c.primary, size: 16),
                              ),
                            Text(m,
                                style: TextStyle(
                                  color: isSel ? c.primary : c.textPrimary,
                                  fontWeight: isSel
                                      ? FontWeight.bold : FontWeight.normal,
                                )),
                          ]),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          block.entries[idx] = FiO2Entry(
                            fio2 : entry.fio2,
                            hours: entry.hours,
                            mode : val,
                          );
                        });
                        _persist();
                      },
                    ),
                  ),
                ),
              ),
              // Selected mode pill
              if (entry.mode.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: entry.mode == 'RA'
                        ? c.success : c.primary,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: (entry.mode == 'RA' ? c.success : c.primary)
                            .withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(entry.mode,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ] else ...[
                // Missing mode warning chip
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.warningSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.warning.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded,
                        color: c.warning, size: 14),
                    const SizedBox(width: 4),
                    Text("Required",
                        style: TextStyle(
                            color: c.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),

            // RA info banner (inline, compact)
            if (entry.mode == 'RA') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: c.successSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.success.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.air_rounded, color: c.success, size: 16),
                  const SizedBox(width: 8),
                  Text("Room Air — FiO₂ fixed at 21%",
                      style: TextStyle(
                          color: c.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Add entry row ─────────────────────────────────────────────────────────

  Widget _buildAddEntryRow(String key, BlockData block, AppColors c) {
    final remaining = 12.0 - block.totalHours;
    final canAdd    = block.entries.length < 8 && block.totalHours < 12.0;

    return GestureDetector(
      onTap: canAdd
          ? () {
              setState(() {
                block.entries.add(FiO2Entry(
                  fio2 : 21,
                  hours: remaining > 0 ? remaining.clamp(0, 12) : 0,
                  mode : '',
                ));
              });
              _persist();
            }
          : null,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: canAdd ? c.successSoft : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canAdd
                ? c.success.withOpacity(0.3) : c.border,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            canAdd
                ? Icons.add_circle_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: canAdd ? c.success : c.textTertiary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            canAdd
                ? "Add FiO₂ entry  (${remaining.toStringAsFixed(1)}h remaining)"
                : block.totalHours >= 12
                    ? "12 h complete"
                    : "Max entries reached",
            style: TextStyle(
              color: canAdd ? c.success : c.textTertiary,
              fontSize: 13, fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(AppColors c) {
    final totalAuc = _totalAUC();
    final mean     = _meanFiO2();
    final excess   = _excessO2();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderLight)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        Row(children: [
          Expanded(child: _summaryMetric(
              "Total AUC", totalAuc.toStringAsFixed(2), c.primary, c)),
          const SizedBox(width: 8),
          Expanded(child: _summaryMetric(
              "Mean FiO₂", "${mean.toStringAsFixed(1)}%", c.purple, c)),
          const SizedBox(width: 8),
          Expanded(child: _summaryMetric(
              "Excess O₂", excess.toStringAsFixed(2),
              excess > 0 ? c.danger : c.success, c)),
        ]),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: Icon(
              _completedDays == _kDays
                  ? Icons.check_circle_outline_rounded
                  : Icons.save_outlined,
              size: 18, color: Colors.white,
            ),
            label: Text(
              _completedDays == _kDays
                  ? "Save & Continue"
                  : "Save Progress  ($_completedDays/$_kDays days done)",
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: _completedDays == _kDays
                  ? c.success : c.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Metric helpers ────────────────────────────────────────────────────────

  Widget _miniMetric(String label, String value,
      Color color, AppColors c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(
              color: color.withOpacity(0.8), fontSize: 10)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _summaryMetric(String label, String value,
      Color color, AppColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
    );
  }

  InputDecoration _inputDec(String hint, AppColors c) => InputDecoration(
    hintText      : hint,
    hintStyle     : TextStyle(color: c.textTertiary, fontSize: 13),
    filled        : true,
    fillColor     : c.surfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary, width: 1.5)),
  );

  // ── Save ──────────────────────────────────────────────────────────────────

  void _handleSave() async {
    await _persist();
    if (!mounted) return;
    final c = AppTheme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior       : SnackBarBehavior.floating,
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.success.withOpacity(0.4))),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(children: [
          Icon(Icons.check_circle_outline, color: c.success),
          const SizedBox(width: 10),
          Text("Saved successfully",
              style: TextStyle(color: c.textPrimary)),
        ]),
        duration: const Duration(seconds: 2),
      ));
  }
}