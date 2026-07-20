import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/forms_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_toggle_widget.dart';

// ─── FIELD VALUE ──────────────────────────────────────────────────────────────

class FieldValue {
  final String   value;
  final String   filledBy;
  final DateTime filledAt;

  const FieldValue({
    required this.value,
    required this.filledBy,
    required this.filledAt,
  });

  Map<String, dynamic> toJson() => {
        'value'   : value,
        'filledBy': filledBy,
        'filledAt': filledAt.toIso8601String(),
      };

  factory FieldValue.fromJson(Map<String, dynamic> j) => FieldValue(
        value   : j['value']    as String,
        filledBy: j['filledBy'] as String,
        filledAt: DateTime.parse(j['filledAt'] as String),
      );
}

// ─── DAY RECORD ───────────────────────────────────────────────────────────────

class DayRecord {
  final DateTime date;
  final Map<String, FieldValue> fields;

  DayRecord({required this.date}) : fields = {};
  DayRecord._withFields({required this.date, required this.fields});

  bool    get isEmpty             => fields.isEmpty;
  String? valueOf(String key)     => fields[key]?.value;
  bool    isFilled(String key)    => fields.containsKey(key);

  Map<String, dynamic> toJson() => {
        'date'  : date.toIso8601String(),
        'fields': fields.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory DayRecord.fromJson(Map<String, dynamic> j) {
    final rawFields = (j['fields'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, FieldValue.fromJson(v as Map<String, dynamic>)),
    );
    return DayRecord._withFields(
      date  : DateTime.parse(j['date'] as String),
      fields: rawFields,
    );
  }
}

// ─── FIELD TYPES ──────────────────────────────────────────────────────────────

enum FieldType { yesNo, chips, number, text }

class FieldDef {
  final String        key;
  final FieldType     type;
  final List<String>? options;
  final int?          maxValue;
  final String?       unit;
  final String?       enabledWhen;
  final String?       enabledWhenValue;

  const FieldDef(
    this.key,
    this.type, {
    this.options,
    this.maxValue,
    this.unit,
    this.enabledWhen,
    this.enabledWhenValue,
  });
}

// ─── SCHEMA ───────────────────────────────────────────────────────────────────

const Map<String, List<FieldDef>> kIghSections = {
  "INFECTION": [
    FieldDef("Sepsis suspected", FieldType.yesNo),
    FieldDef("Blood culture sent", FieldType.yesNo),
    FieldDef("Blood culture positive", FieldType.yesNo),
    FieldDef("EOS (<72h)", FieldType.yesNo),
    FieldDef("LOS (>72h)", FieldType.yesNo),
    FieldDef("Antibiotics", FieldType.yesNo),
    FieldDef("Antibiotic day", FieldType.number, maxValue: 999, unit: "day"),
    FieldDef("LP done", FieldType.yesNo),
    FieldDef("CSF culture positive", FieldType.yesNo),
    FieldDef("CLABSI", FieldType.yesNo),
    FieldDef("VAP", FieldType.yesNo),
  ],
  "GASTROINTESTINAL": [
    FieldDef("NPO", FieldType.yesNo),
    FieldDef("Enteral feeds started", FieldType.yesNo),
    FieldDef(
      "Feed type",
      FieldType.chips,
      options          : ["PDHM", "EBM", "FM"],
      enabledWhen      : "Enteral feeds started",
      enabledWhenValue : "Yes",
    ),
    FieldDef(
      "Feed volume (ml/kg/d)",
      FieldType.number,
      maxValue         : 300,
      unit             : "ml/kg/d",
      enabledWhen      : "Enteral feeds started",
      enabledWhenValue : "Yes",
    ),
    FieldDef("Full feeds (150ml/kg)", FieldType.yesNo),
    FieldDef("Parenteral nutrition", FieldType.yesNo),
    FieldDef("Probiotic", FieldType.yesNo),
    FieldDef("Feed intolerance", FieldType.yesNo),
    FieldDef("NEC suspected", FieldType.yesNo),
    FieldDef(
      "NEC confirmed (stage)",
      FieldType.chips,
      options          : ["1A", "1B", "2A", "2B", "3A", "3B"],
      enabledWhen      : "NEC suspected",
      enabledWhenValue : "Yes",
    ),
    FieldDef("NEC surgery", FieldType.yesNo),
    FieldDef("Cholestasis", FieldType.yesNo),
  ],
  "HEMATOLOGY": [
    FieldDef("Jaundice", FieldType.yesNo),
    FieldDef("Phototherapy", FieldType.yesNo),
    FieldDef("Peak TSB (mg/dL)", FieldType.number, maxValue: 50, unit: "mg/dL"),
    FieldDef("Exchange transfusion", FieldType.yesNo),
    FieldDef("PRBC transfusion", FieldType.yesNo),
    FieldDef("Platelet transfusion", FieldType.yesNo),
    FieldDef("FFP/Cryo transfusion", FieldType.yesNo),
  ],
};

final List<String> kIghAllFields =
    kIghSections.values.expand((f) => f.map((d) => d.key)).toList();

// ─── SITE-WISE NURSE ROSTER (same map as Form A & Form 2) ─────────────────────

const Map<String, List<String>> kIghNursesBySite = {
  "PGIMER": [
    "Mannat Guliani", "Shalini Dhiman", "Navkiran Kaur",
    "Geetika", "Priyanka Thakur", "Seemran Kaur",
    "Tanvi Saini", "Yashvi Jolly",
  ],
  "GMCH"  : ["Nurse GMCH-1",   "Nurse GMCH-2"],
  "IOG"   : ["Nurse IOG-1",    "Nurse IOG-2"],
  "AFMC"  : ["Nurse AFMC-1",   "Nurse AFMC-2"],
  "GMCH-A": ["Nurse GMCH-A-1"],
  "AMC"   : ["Nurse AMC-1"],
};

// ─── STORAGE HELPER ───────────────────────────────────────────────────────────

class _IghStorage {
  static String _prefsKey(String babyUid) => 'nicu_igh_records_$babyUid';
  static const  _lastNurseKey             = 'nicu_last_nurse';

  static Future<Map<String, DayRecord>> load(String babyUid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefsKey(babyUid));
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, DayRecord.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) { return {}; }
  }

  static Future<void> save(
      String babyUid, Map<String, DayRecord> records) async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final encoded = jsonEncode(records.map((k, v) => MapEntry(k, v.toJson())));
      await prefs.setString(_prefsKey(babyUid), encoded);
    } catch (_) {}
  }

  static Future<String> loadLastNurse() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastNurseKey) ?? '';
  }

  static Future<void> saveLastNurse(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNurseKey, name);
  }
}

// ─── MAIN WIDGET ──────────────────────────────────────────────────────────────

class HelperForm3InfectGIHema extends StatefulWidget {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  /// Site string (e.g. "PGIMER") drives the nurse dropdown list.
  /// Defaults to 'PGIMER' so existing call sites without this param compile.
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

class _HelperForm3InfectGIHemaState extends State<HelperForm3InfectGIHema>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  Map<String, String>    _draft         = {};
  bool                   _isSaving      = false;
  bool                   _isLoading     = true;
  Map<String, DayRecord> _records       = {};
  String                 _selectedNurse = 'Select';
  late List<String>      _siteNurses;

  // ── Init / Dispose ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _siteNurses    = kIghNursesBySite[widget.site] ?? [];
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    Map<String, DayRecord> records;
    try {
      final remote = await FormsApiService.instance.loadHelperForm(
        babyUid: widget.babyUid, formType: 'infect_gi_hema');
      final raw = remote['records'] as Map<String, dynamic>? ?? {};
      records = raw.isNotEmpty
          ? raw.map((k,v) => MapEntry(k, DayRecord.fromJson(v as Map<String,dynamic>)))
          : await _IghStorage.load(widget.babyUid);
    } catch (_) { records = await _IghStorage.load(widget.babyUid); }
    final lastNurse = await _IghStorage.loadLastNurse();
    if (!mounted) return;
    setState(() {
      _records    = records;
      _isLoading  = false;
      _selectedNurse = (_siteNurses.contains(lastNurse) && lastNurse.isNotEmpty)
          ? lastNurse : 'Select';
    });
  }

  Future<void> _persistRecords() async =>
      _IghStorage.save(widget.babyUid, _records);

  // ── Date helpers ───────────────────────────────────────────────────────────

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-"
      "${d.day.toString().padLeft(2, '0')}";

  DayRecord get _todayRecord {
    final key = _dateKey(DateTime.now());
    _records.putIfAbsent(key, () => DayRecord(date: _dateOnly(DateTime.now())));
    return _records[key]!;
  }

  // ── Field logic ────────────────────────────────────────────────────────────

  bool    _isLocked(String key)    => _todayRecord.isFilled(key);
  String  _displayValue(String key) {
    if (_isLocked(key)) return _todayRecord.valueOf(key) ?? '';
    return _draft[key] ?? '';
  }

  bool _isFieldEnabled(FieldDef fd) {
    if (fd.enabledWhen == null) return true;
    return _displayValue(fd.enabledWhen!) == fd.enabledWhenValue;
  }

  void _setDraft(String key, String val) {
    if (_isLocked(key)) return;
    setState(() {
      _draft[key] = val;
      for (final section in kIghSections.values) {
        for (final fd in section) {
          if (fd.enabledWhen == key && val != fd.enabledWhenValue) {
            if (!_isLocked(fd.key)) _draft[fd.key] = '';
          }
        }
      }
    });
  }

  /// Only includes non-locked, enabled, non-empty fields — same fix as Form 2.
  Map<String, String> get _filledDraft {
    final out = <String, String>{};
    for (final section in kIghSections.values) {
      for (final fd in section) {
        if (_isLocked(fd.key)) continue;
        if (!_isFieldEnabled(fd)) continue;   // skip disabled children
        final v = _draft[fd.key] ?? '';
        if (v.isNotEmpty) out[fd.key] = v;
      }
    }
    return out;
  }

  int get _totalFilled => _todayRecord.fields.length;

  /// Progress only counts currently-enabled fields — disabled children
  /// never count as "missing".
  double _dayProgress() {
    final lockable = <String>[];
    for (final section in kIghSections.values) {
      for (final fd in section) {
        if (_isFieldEnabled(fd)) lockable.add(fd.key);
      }
    }
    if (lockable.isEmpty) return 0;
    return lockable.where((k) => _isLocked(k)).length / lockable.length;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save(AppColors c) async {
    if (_selectedNurse == 'Select' || _selectedNurse.isEmpty) {
      _showSimpleDialog(
        title    : "Select your name",
        body     : "Please choose your name from the dropdown before saving.",
        icon     : Icons.badge_outlined,
        iconColor: c.warning,
        c        : c,
      );
      return;
    }

    final toSave = _filledDraft;
    if (toSave.isEmpty) {
      _showSimpleDialog(
        title    : "Nothing to save",
        body     : "Please fill in at least one field before saving.",
        icon     : Icons.info_outline,
        iconColor: c.primary,
        c        : c,
      );
      return;
    }

    setState(() => _isSaving = true);

    final now    = DateTime.now();
    final record = _todayRecord;
    toSave.forEach((key, val) {
      record.fields[key] = FieldValue(
        value   : val,
        filledBy: _selectedNurse,
        filledAt: now,
      );
    });

    await _persistRecords();
    await _IghStorage.saveLastNurse(_selectedNurse);
    try {
      final recordsMap = _records.map((k, v) => MapEntry(k, v.toJson()));
      await FormsApiService.instance.saveHelperForm(
        babyUid  : widget.babyUid,
        formType : 'infect_gi_hema',
        records  : recordsMap,
        updatedBy: _selectedNurse,
      );
    } catch (e) { debugPrint('Helper form backend sync failed: $e'); }

    if (!mounted) return;
    setState(() { _draft = {}; _isSaving = false; });

    _toast("${toSave.length} field(s) saved by $_selectedNurse",
        ok: true, c: c);
    _tabController.animateTo(1);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: c.primary, strokeWidth: 2),
            const SizedBox(height: 16),
            Text("Loading records...",
                style: TextStyle(color: c.textTertiary, fontSize: 13)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: _buildAppBar(c),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFillTab(c), _buildHistoryTab(c)],
      ),
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(AppColors c) {
    final progress = _dayProgress();
    return AppBar(
      backgroundColor : c.surface,
      elevation       : 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing    : 16,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.babyUid,
            style: TextStyle(color: c.primary, fontSize: 13,
                fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        Text(
          "${widget.motherName}  |  ${widget.enrollmentId}  |  ${widget.gestation}",
          style: TextStyle(color: c.textTertiary, fontSize: 11),
        ),
      ]),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Center(child: ThemeToggle()),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value          : progress,
                    minHeight      : 5,
                    backgroundColor: c.border,
                    valueColor     : AlwaysStoppedAnimation(
                        progress == 1.0 ? c.success : c.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text("$_totalFilled filled today",
                  style: TextStyle(
                      color: progress == 1.0 ? c.success : c.textTertiary,
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          Container(
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.borderLight))),
            child: TabBar(
              controller          : _tabController,
              indicatorColor      : c.primary,
              indicatorWeight     : 2,
              labelColor          : c.primary,
              unselectedLabelColor: c.textTertiary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.edit_note_rounded, size: 17),
                  const SizedBox(width: 6),
                  const Text("Fill Form"),
                  if (_filledDraft.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.warning.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("${_filledDraft.length}",
                          style: TextStyle(color: c.warning,
                              fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history_edu_rounded, size: 17),
                  const SizedBox(width: 6),
                  const Text("History"),
                  if (_records.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("${_records.length}",
                          style: TextStyle(color: c.primary,
                              fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── FILL TAB ───────────────────────────────────────────────────────────────

  Widget _buildFillTab(AppColors c) {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBanner(c),
              _buildNurseCard(c),
              const SizedBox(height: 6),
              ...kIghSections.entries.map((e) => _buildSection(e.key, e.value, c)),
            ],
          ),
        ),
      ),
      _buildSaveBar(c),
    ]);
  }

  // ── Status banner ──────────────────────────────────────────────────────────

  Widget _buildStatusBanner(AppColors c) {
    final filled = _todayRecord.fields.length;
    final total  = kIghAllFields.length;

    if (filled == 0) {
      return _infoBanner(Icons.wb_sunny_outlined, c.primary,
          "No fields filled yet today. Be the first to add data.", c);
    }

    final contributors = _todayRecord.fields.values
        .map((v) => v.filledBy).toSet().toList();

    if (filled >= total) {
      return _infoBanner(Icons.check_circle_outline, c.success,
          "All fields complete for today. Filled by: ${contributors.join(', ')}", c);
    }

    return _infoBanner(Icons.pending_outlined, c.warning,
        "$filled / $total fields filled today by ${contributors.join(', ')}. "
        "${total - filled} remaining.", c);
  }

  // ── Nurse dropdown card ────────────────────────────────────────────────────

  Widget _buildNurseCard(AppColors c) {
    final nurseSelected = _selectedNurse != 'Select' && _selectedNurse.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Label + site chip
        Row(children: [
          Icon(Icons.badge_outlined, color: c.primary, size: 16),
          const SizedBox(width: 8),
          Text("Your name (required before saving)",
              style: TextStyle(color: c.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.primary.withOpacity(0.3)),
            ),
            child: Text(widget.site,
                style: TextStyle(color: c.primary,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),

        // Dropdown
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: nurseSelected ? c.primary.withOpacity(0.5) : c.border,
              width: nurseSelected ? 1.5 : 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value        : _selectedNurse,
              dropdownColor: c.surface,
              style        : TextStyle(color: c.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w600),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: nurseSelected ? c.primary : c.textTertiary, size: 20),
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'Select',
                  child: Text("Select your name",
                      style: TextStyle(color: c.textTertiary, fontSize: 13)),
                ),
                ..._siteNurses.map((name) {
                  final isSel = name == _selectedNurse;
                  return DropdownMenuItem(
                    value: name,
                    child: Row(children: [
                      if (isSel)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.check_circle_rounded,
                              color: c.primary, size: 16),
                        ),
                      Text(name,
                          style: TextStyle(
                            color: isSel ? c.primary : c.textPrimary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          )),
                    ]),
                  );
                }),
              ],
              onChanged: (val) async {
                if (val == null || val == 'Select') return;
                setState(() => _selectedNurse = val);
                await _IghStorage.saveLastNurse(val);
              },
            ),
          ),
        ),

        // Empty roster warning
        if (_siteNurses.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.warning.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: c.warning, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(
                "No nurses configured for site \"${widget.site}\". "
                "Update kIghNursesBySite in the source file.",
                style: TextStyle(color: c.textSecondary, fontSize: 11),
              )),
            ]),
          ),
        ],

        // Unsaved counter
        if (_filledDraft.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.warning.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.warning.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.edit_note_rounded, color: c.warning, size: 16),
              const SizedBox(width: 8),
              Text("${_filledDraft.length} field(s) ready to save",
                  style: TextStyle(color: c.warning,
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Section card ───────────────────────────────────────────────────────────

  Widget _buildSection(String title, List<FieldDef> fields, AppColors c) {
    final sectionColor  = _sectionColor(title, c);
    final enabledFields = fields.where(_isFieldEnabled).toList();
    final locked        = enabledFields.where((fd) => _isLocked(fd.key)).length;
    final total         = enabledFields.length;
    final allDone       = total > 0 && locked >= total;
    final draftedHere   = fields
        .where((fd) =>
            !_isLocked(fd.key) &&
            _isFieldEnabled(fd) &&
            (_draft[fd.key] ?? '').isNotEmpty)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sectionColor.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: sectionColor.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: sectionColor.withOpacity(0.12))),
          ),
          child: Row(children: [
            Container(width: 3, height: 18,
                decoration: BoxDecoration(color: sectionColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(title,
                style: TextStyle(color: sectionColor,
                    fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8)),
            const Spacer(),
            if (draftedHere > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: c.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text("$draftedHere unsaved",
                    style: TextStyle(color: c.warning,
                        fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: allDone ? c.successSoft : sectionColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text("$locked / $total",
                  style: TextStyle(
                      color: allDone ? c.success : sectionColor,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
              children: fields
                  .map((fd) => _buildFieldRow(fd, sectionColor, c))
                  .toList()),
        ),
      ]),
    );
  }

  // ── Field row ──────────────────────────────────────────────────────────────

  Widget _buildFieldRow(FieldDef fd, Color sectionColor, AppColors c) {
    final locked   = _isLocked(fd.key);
    final enabled  = _isFieldEnabled(fd);
    final hasDraft = !locked && (_draft[fd.key] ?? '').isNotEmpty;
    final lockedBy = locked ? _todayRecord.fields[fd.key]!.filledBy : null;
    final lockedAt = locked ? _todayRecord.fields[fd.key]!.filledAt : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: locked ? c.success : hasDraft ? c.warning : c.border,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fd.key,
                style: TextStyle(
                    color: locked
                        ? c.textPrimary
                        : enabled
                            ? c.textSecondary
                            : c.textTertiary.withOpacity(0.5),
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          if (locked && lockedBy != null)
            _lockedBadge(lockedBy, lockedAt!, c),
        ]),
        const SizedBox(height: 8),
        if (!enabled && !locked)
          _disabledPlaceholder(fd.enabledWhen ?? '', c)
        else
          _buildInputWidget(fd, sectionColor, locked, c),
      ]),
    );
  }

  Widget _lockedBadge(String nurse, DateTime at, AppColors c) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.successSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.success.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline_rounded,
            size: 10, color: c.success.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text("$nurse  $h:$m",
            style: TextStyle(color: c.success.withOpacity(0.8),
                fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _disabledPlaceholder(String parentKey, AppColors c) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: c.surfaceAlt.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderLight),
      ),
      child: Center(
        child: Text("Fill '$parentKey' first",
            style: TextStyle(
                color: c.textTertiary.withOpacity(0.5), fontSize: 11)),
      ),
    );
  }

  Widget _buildInputWidget(
      FieldDef fd, Color sectionColor, bool locked, AppColors c) {
    switch (fd.type) {
      case FieldType.yesNo:
        return _buildYesNo(fd.key, locked, c);
      case FieldType.chips:
        return _buildChips(fd.key, fd.options!, sectionColor, locked, c);
      case FieldType.number:
        return _buildNumberField(fd, locked, c);
      case FieldType.text:
        return TextFormField(
          initialValue: _displayValue(fd.key),
          enabled: !locked,
          style: TextStyle(color: locked ? c.textTertiary : c.textPrimary),
          decoration: _inputDec(fd.key, c),
          onChanged: (v) => _setDraft(fd.key, v),
        );
    }
  }

  Widget _buildYesNo(String key, bool locked, AppColors c) {
    final val = _displayValue(key);
    return Row(children: [
      Expanded(child: _toggleButton("Yes", Icons.check_rounded,
          val == "Yes", c.success, locked, c, () => _setDraft(key, "Yes"))),
      const SizedBox(width: 8),
      Expanded(child: _toggleButton("No", Icons.close_rounded,
          val == "No", c.danger, locked, c, () => _setDraft(key, "No"))),
    ]);
  }

  Widget _toggleButton(String label, IconData icon, bool selected,
      Color selColor, bool locked, AppColors c, VoidCallback onTap) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? selColor.withOpacity(locked ? 0.06 : 0.12) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? selColor.withOpacity(locked ? 0.35 : 0.8) : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14,
              color: selected
                  ? selColor.withOpacity(locked ? 0.5 : 1.0) : c.textTertiary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: selected
                      ? selColor.withOpacity(locked ? 0.5 : 1.0) : c.textTertiary,
                  fontWeight: FontWeight.bold, fontSize: 13)),
          if (locked && selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline_rounded,
                size: 10, color: selColor.withOpacity(0.4)),
          ],
        ]),
      ),
    );
  }

  Widget _buildChips(String key, List<String> options,
      Color sectionColor, bool locked, AppColors c) {
    final cur = _displayValue(key);
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.map((opt) {
        final sel = cur == opt;
        return GestureDetector(
          onTap: locked ? null : () => _setDraft(key, opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: sel
                  ? sectionColor.withOpacity(locked ? 0.06 : 0.12) : c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel
                    ? sectionColor.withOpacity(locked ? 0.35 : 0.8) : c.border,
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(opt,
                  style: TextStyle(
                      color: sel
                          ? sectionColor.withOpacity(locked ? 0.5 : 1.0)
                          : c.textTertiary,
                      fontWeight: FontWeight.bold, fontSize: 13)),
              if (locked && sel) ...[
                const SizedBox(width: 5),
                Icon(Icons.lock_outline_rounded,
                    size: 10, color: sectionColor.withOpacity(0.4)),
              ],
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNumberField(FieldDef fd, bool locked, AppColors c) {
    final ctrl = TextEditingController(text: _displayValue(fd.key));
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    return TextFormField(
      controller  : ctrl,
      enabled     : !locked,
      keyboardType: TextInputType.number,
      style       : TextStyle(color: locked ? c.textTertiary : c.textPrimary),
      decoration  : _inputDec("Enter value", c).copyWith(
        suffixText : fd.unit,
        suffixStyle: TextStyle(color: c.primary),
        suffixIcon : locked
            ? Icon(Icons.lock_outline_rounded,
                size: 16, color: c.success.withOpacity(0.4))
            : null,
      ),
      onChanged: (v) {
        if (fd.maxValue != null) {
          final n = double.tryParse(v) ?? 0;
          if (n > fd.maxValue!) {
            ctrl.text = fd.maxValue.toString();
            ctrl.selection =
                TextSelection.collapsed(offset: ctrl.text.length);
            _setDraft(fd.key, fd.maxValue.toString());
            return;
          }
        }
        _setDraft(fd.key, v);
      },
    );
  }

  // ── Save bar ───────────────────────────────────────────────────────────────

  Widget _buildSaveBar(AppColors c) {
    final count = _filledDraft.length;
    final ready = count > 0 &&
        _selectedNurse != 'Select' && _selectedNurse.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderLight)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _draft = {}),
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Icon(Icons.refresh_rounded, color: c.textTertiary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _isSaving ? null : () => _save(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                color: ready ? c.success : c.primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(count > 0
                            ? Icons.save_outlined : Icons.edit_outlined,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          count > 0
                              ? "Save $count field(s)" : "Fill fields above",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── HISTORY TAB ────────────────────────────────────────────────────────────

  Widget _buildHistoryTab(AppColors c) {
    final sortedKeys = _records.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    if (sortedKeys.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history_edu_rounded, color: c.border, size: 56),
          const SizedBox(height: 14),
          Text("No entries yet",
              style: TextStyle(color: c.textSecondary,
                  fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text("Fill fields and save to see history here",
              style: TextStyle(color: c.textTertiary, fontSize: 12)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 32),
      itemCount: sortedKeys.length,
      itemBuilder: (_, i) {
        final record = _records[sortedKeys[i]]!;
        return _IghHistoryDayCard(
          record : record,
          isToday: i == 0 &&
              _dateOnly(record.date) == _dateOnly(DateTime.now()),
          c      : c,
        );
      },
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Color _sectionColor(String title, AppColors c) {
    switch (title) {
      case "INFECTION":        return c.danger;
      case "GASTROINTESTINAL": return c.success;
      case "HEMATOLOGY":       return c.warning;
      default:                 return c.primary;
    }
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
    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.borderLight)),
  );

  Widget _infoBanner(IconData icon, Color color, String msg, AppColors c) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: TextStyle(color: color.withOpacity(0.9), fontSize: 12))),
        ]),
      );

  void _toast(String msg, {required bool ok, required AppColors c}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior       : SnackBarBehavior.floating,
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: (ok ? c.success : c.danger).withOpacity(0.4))),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            color: ok ? c.success : c.danger),
        const SizedBox(width: 10),
        Expanded(child: Text(msg,
            style: TextStyle(color: c.textPrimary))),
      ]),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showSimpleDialog({
    required String title,
    required String body,
    required IconData icon,
    required Color iconColor,
    required AppColors c,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
              style: TextStyle(color: c.textPrimary,
                  fontWeight: FontWeight.bold))),
        ]),
        content: Text(body, style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK", style: TextStyle(color: c.primary)),
          ),
        ],
      ),
    );
  }
}

// ─── HISTORY DAY CARD ─────────────────────────────────────────────────────────

class _IghHistoryDayCard extends StatefulWidget {
  final DayRecord record;
  final bool      isToday;
  final AppColors c;

  const _IghHistoryDayCard({
    required this.record,
    required this.isToday,
    required this.c,
  });

  @override
  State<_IghHistoryDayCard> createState() => _IghHistoryDayCardState();
}

class _IghHistoryDayCardState extends State<_IghHistoryDayCard> {
  bool _open = false;

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dateLabel(DateTime d) {
    final now  = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return "Today";
    if (diff == 1) return "Yesterday";
    return "${d.day} ${_months[d.month]}";
  }

  String _time(DateTime d) =>
      "${d.hour.toString().padLeft(2, '0')}:"
      "${d.minute.toString().padLeft(2, '0')}";

  Map<String, int> _contributors() {
    final map = <String, int>{};
    for (final fv in widget.record.fields.values) {
      map[fv.filledBy] = (map[fv.filledBy] ?? 0) + 1;
    }
    return map;
  }

  Color _sectionColor(String title, AppColors c) {
    switch (title) {
      case "INFECTION":        return c.danger;
      case "GASTROINTESTINAL": return c.success;
      case "HEMATOLOGY":       return c.warning;
      default:                 return c.primary;
    }
  }

  List<_IghFlag> _flags(AppColors c) {
    final get = (String k) => widget.record.fields[k]?.value ?? '';
    final flags = <_IghFlag>[];

    if (get("Sepsis suspected") == "Yes")
      flags.add(_IghFlag("SEPSIS",   c.danger));
    if (get("Blood culture positive") == "Yes")
      flags.add(_IghFlag("BCx+",     c.danger));
    if (get("EOS (<72h)") == "Yes")
      flags.add(_IghFlag("EOS",      c.warning));
    if (get("LOS (>72h)") == "Yes")
      flags.add(_IghFlag("LOS",      c.warning));
    if (get("CLABSI") == "Yes")
      flags.add(_IghFlag("CLABSI",   c.danger));
    if (get("VAP") == "Yes")
      flags.add(_IghFlag("VAP",      c.danger));
    if (get("NEC suspected") == "Yes") {
      final stage = get("NEC confirmed (stage)");
      flags.add(_IghFlag(
          "NEC${stage.isEmpty ? '?' : ' $stage'}", c.danger));
    }
    if (get("NEC surgery") == "Yes")
      flags.add(_IghFlag("NEC Sx",   c.danger));
    if (get("Cholestasis") == "Yes")
      flags.add(_IghFlag("CHOLEST.", c.warning));
    if (get("Exchange transfusion") == "Yes")
      flags.add(_IghFlag("EXCH TX",  c.warning));
    if (get("PRBC transfusion") == "Yes")
      flags.add(_IghFlag("PRBC",     c.purple));
    if (get("Platelet transfusion") == "Yes")
      flags.add(_IghFlag("PLT TX",   c.purple));

    if (flags.isEmpty) flags.add(_IghFlag("Stable", c.success));
    return flags;
  }

  @override
  Widget build(BuildContext context) {
    final c            = widget.c;
    final r            = widget.record;
    final label        = _dateLabel(r.date);
    final isToday      = label == "Today";
    final filled       = r.fields.length;
    final total        = kIghAllFields.length;
    final pct          = filled / total;
    final contributors = _contributors();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday ? c.primary.withOpacity(0.3) : c.border,
          width: isToday ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [

        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [

              // Date badge
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: isToday ? c.primary.withOpacity(0.1) : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isToday ? c.primary.withOpacity(0.3) : c.border),
                ),
                child: Center(
                  child: Text(
                    label == "Today"     ? "TODAY"
                    : label == "Yesterday" ? "YEST."
                    : "${r.date.day}\n${_months[r.date.month]}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isToday ? c.primary : c.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: isToday ? 8 : 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value          : pct,
                            minHeight      : 4,
                            backgroundColor: c.border,
                            valueColor     : AlwaysStoppedAnimation(
                                pct == 1.0 ? c.success : c.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text("$filled/$total",
                          style: TextStyle(
                              color: pct == 1.0 ? c.success : c.textTertiary,
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: contributors.entries.map((e) =>
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.person_outline_rounded,
                                size: 11, color: c.textTertiary),
                            const SizedBox(width: 4),
                            Text("${e.key} (${e.value})",
                                style: TextStyle(
                                    color: c.textSecondary, fontSize: 10)),
                          ]),
                        ),
                      ).toList(),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: _flags(c)
                          .map((f) => _flagChip(f.label, f.color))
                          .toList(),
                    ),
                  ],
                ),
              ),

              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down,
                    color: c.textTertiary, size: 20),
              ),
            ]),
          ),
        ),

        if (_open) ...[
          Divider(height: 1, color: c.borderLight),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildFullDetail(c),
          ),
        ],
      ]),
    );
  }

  Widget _buildFullDetail(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: kIghSections.entries.map((sec) {
        final secColor = _sectionColor(sec.key, c);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 3, height: 14,
                  decoration: BoxDecoration(color: secColor,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text(sec.key,
                  style: TextStyle(color: secColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11, letterSpacing: 0.8)),
            ]),
            const SizedBox(height: 10),
            ...sec.value.map((fd) {
              final fv  = widget.record.fields[fd.key];
              final val = fv?.value ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4,
                        child: Text(fd.key,
                            style: TextStyle(
                                color: fv != null
                                    ? c.textSecondary : c.textTertiary,
                                fontSize: 12))),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: Text(
                        val.isEmpty ? "-" : val,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: val.isEmpty
                              ? c.textTertiary.withOpacity(0.4)
                              : fd.type == FieldType.yesNo
                                  ? (val == "Yes" ? c.success : c.textSecondary)
                                  : c.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: fv != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(fv.filledBy,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: c.success.withOpacity(0.8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                                Text(_time(fv.filledAt),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: c.textTertiary, fontSize: 10)),
                              ],
                            )
                          : Align(
                              alignment: Alignment.centerRight,
                              child: Text("not filled",
                                  style: TextStyle(
                                      color: c.textTertiary.withOpacity(0.4),
                                      fontSize: 10)),
                            ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
        );
      }).toList(),
    );
  }

  Widget _flagChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(color: color,
                fontSize: 10, fontWeight: FontWeight.bold)),
      );
}

class _IghFlag {
  final String label;
  final Color  color;
  const _IghFlag(this.label, this.color);
}