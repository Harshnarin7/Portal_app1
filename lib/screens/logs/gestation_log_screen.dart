import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/logs_api_service.dart';
import '../../utils/ga_check_seed.dart';
import '../../utils/maternal_uid.dart';
import '../screening_form.dart';

String _ddmmyyyy(dynamic raw) {
  final s = (raw ?? '').toString().trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return s.isEmpty ? '—' : s;
  return '${m[3]}-${m[2]}-${m[1]}';
}

const _kPrimary = Color(0xFF3B6FE0);
const _kSurface = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFD4DCF0);
const _kText1 = Color(0xFF1A2340);
const _kText2 = Color(0xFF4A5578);
const _kText3 = Color(0xFF8A95B0);
const _kBg = Color(0xFFEFF3FB);
const _kDanger = Color(0xFFE53935);
const _kWarning = Color(0xFFF59E0B);
const _kSuccess = Color(0xFF2E7D32);

const _kReliable = 'Reliable';
const _kDefaultIdType = 'Checked at triage';
const _kMissedIdType = 'Missed - identified retrospectively';
const _kIdentificationTypes = [_kDefaultIdType, _kMissedIdType];
const _kGestationSources = [_kReliable, 'Unknown/Unreliable'];
const _kGestationMethods = [
  ('LMP', 'LMP'),
  ('Early USG', 'Early USG (<24w)'),
  ('Fundal Height', 'Fundal Height'),
];
const _kSiteOrder = [
  'PGIMER',
  'GMCH',
  'IOG',
  'AFMC',
  'GMCH-A',
  'AMC',
];

class GestationLogScreen extends StatefulWidget {
  const GestationLogScreen({super.key});

  @override
  State<GestationLogScreen> createState() => _GestationLogScreenState();
}

class _GestationLogScreenState extends State<GestationLogScreen> {
  final _nameCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();
  final _weeksCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();

  String _siteName = '';
  String _identificationType = _kDefaultIdType;
  String _gaSource = '';
  String _gestationMethod = '';

  bool _saving = false;
  int? _editingId;
  String _saveError = '';
  final _scrollCtrl = ScrollController();
  bool _foundIufd = false;
  Map<String, dynamic>? _lastResult;

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _gapEntries = [];
  bool _loading = true;
  String _loadError = '';

  bool get _isSiteLocked {
    final user = context.read<AuthProvider>().user;
    if (user == null) return false;
    return !user.role.isGlobal && (user.siteName?.isNotEmpty == true);
  }

  bool get _isReliable => !_foundIufd && _gaSource == _kReliable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user != null &&
          !user.role.isGlobal &&
          (user.siteName?.isNotEmpty == true)) {
        setState(() => _siteName = user.siteName!);
      }
      _load();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _uidCtrl.dispose();
    _weeksCtrl.dispose();
    _scrollCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = '';
    });
    try {
      final results = await Future.wait([
        LogsApiService.instance.listGaChecks(),
        LogsApiService.instance.listGaCheckGap(),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0];
        _gapEntries = results[1];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.statusCode == 403
            ? "You don't have access to this log."
            : 'Could not load the screening log.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load the screening log.';
        _loading = false;
      });
    }
  }

  void _setSource(String value) {
    setState(() {
      _gaSource = value;
      if (value != _kReliable) {
        _gestationMethod = '';
        _weeksCtrl.clear();
        _daysCtrl.clear();
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final uid = _uidCtrl.text.trim();
    if (!_isSiteLocked && _siteName.isEmpty) {
      setState(() => _saveError = 'Select a site.');
      return;
    }
    final uidError = MaternalUid.saveError(_siteName, uid);
    if (uidError.isNotEmpty) {
      setState(() => _saveError = uidError);
      return;
    }
    if (name.isEmpty && uid.isEmpty) {
      setState(() => _saveError = "Enter at least the mother's name or UID.");
      return;
    }
    if (!_foundIufd && _gaSource.isEmpty) {
      setState(() => _saveError = 'Select a gestation source.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = '';
    });

    final weeks = int.tryParse(_weeksCtrl.text.trim());
    final days = int.tryParse(_daysCtrl.text.trim());
    final payload = <String, dynamic>{
      'site_name': _siteName.isEmpty ? null : _siteName,
      'identification_type':
          _identificationType.isEmpty ? _kDefaultIdType : _identificationType,
      'mother_name': name.isEmpty ? null : name,
      'mother_uid': uid.isEmpty ? null : uid,
      'ga_source': _foundIufd ? null : _gaSource,
      'found_iufd': _foundIufd,
      'gestation_method':
          _isReliable && _gestationMethod.isNotEmpty ? _gestationMethod : null,
      'gestation_weeks': _isReliable ? weeks : null,
      'gestation_days': _isReliable ? days : null,
    };

    try {
      final Map<String, dynamic> res;
      if (_editingId != null) {
        res = await LogsApiService.instance.updateGaCheck(_editingId!, payload);
      } else {
        res = await LogsApiService.instance.createGaCheck(payload);
      }
      if (!mounted) return;
      final wasEditing = _editingId != null;
      setState(() {
        _lastResult = wasEditing ? null : res;
        _editingId = null;
        _nameCtrl.clear();
        _uidCtrl.clear();
        _weeksCtrl.clear();
        _daysCtrl.clear();
        _identificationType = _kDefaultIdType;
        _gaSource = '';
        _gestationMethod = '';
        _foundIufd = false;
        if (!_isSiteLocked) _siteName = '';
        _saving = false;
      });
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Save failed.';
        _saving = false;
      });
    }
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _saveError = '';
      _nameCtrl.clear();
      _uidCtrl.clear();
      _weeksCtrl.clear();
      _daysCtrl.clear();
      _identificationType = _kDefaultIdType;
      _gaSource = '';
      _gestationMethod = '';
      _foundIufd = false;
      if (!_isSiteLocked) _siteName = '';
    });
  }

  void _startEdit(Map<String, dynamic> entry) {
    final foundIufd = entry['found_iufd'] == true;
    final source = foundIufd ? '' : (entry['ga_source'] ?? '').toString();
    final reliable = !foundIufd && source == _kReliable;
    final id = entry['id'];
    setState(() {
      _editingId = id is int ? id : int.tryParse('$id');
      _lastResult = null;
      _saveError = '';
      _siteName = (entry['site_name'] ?? _siteName).toString();
      _identificationType =
          (entry['identification_type'] ?? _kDefaultIdType).toString();
      _nameCtrl.text = (entry['mother_name'] ?? '').toString();
      _uidCtrl.text = (entry['mother_uid'] ?? '').toString();
      _gaSource = source;
      _gestationMethod =
          reliable ? (entry['gestation_method'] ?? '').toString() : '';
      _weeksCtrl.text =
          reliable ? (entry['gestation_weeks']?.toString() ?? '') : '';
      _daysCtrl.text =
          reliable ? (entry['gestation_days']?.toString() ?? '') : '';
      _foundIufd = foundIufd;
    });
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _continueToFormA(Map<String, dynamic> entry) {
    GaCheckSeedStore.setFromEntry(entry);
    setState(() => _lastResult = null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScreeningForm(key: UniqueKey(), loadDraft: false),
      ),
    ).then((_) => _load());
  }

  String _methodLabel(String? value) {
    if (value == null || value.isEmpty) return '—';
    for (final m in _kGestationMethods) {
      if (m.$1 == value) return m.$2;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final total = _entries.length;
    final eligible = _entries.where((e) => e['eligible'] == true).length;
    final continued =
        _entries.where((e) => e['continued_to_screening'] == true).length;
    final gap = _gapEntries.length;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: _kText1,
        elevation: 0,
        title: const Text(
          'Gestation (Inclusion Criteria) Screening Log',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Text(
              'Log every woman checked for gestational age at antenatal clinic or delivery-room triage — not just the ones who turn out preterm.',
              style: TextStyle(fontSize: 12, color: _kText2, height: 1.4),
            ),
            if (gap > 0) ...[
              const SizedBox(height: 12),
              _banner(
                color: _kWarning,
                child: Text(
                  '$gap eligible check${gap == 1 ? '' : 's'} logged with no Form A ever started — review below.',
                  style: const TextStyle(fontSize: 12, color: _kText1),
                ),
              ),
            ],
            if (_lastResult != null) ...[
              const SizedBox(height: 12),
              _resultBanner(_lastResult!),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _stat('$total', 'Total logged')),
              const SizedBox(width: 8),
              Expanded(child: _stat('$eligible', 'Eligible (<32wk)')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _stat('$continued', 'Continued to Form A')),
              const SizedBox(width: 8),
              Expanded(
                  child: _stat('$gap', 'Eligible, no Form A yet', warn: true)),
            ]),
            const SizedBox(height: 16),
            _card(
              title: _editingId == null
                  ? 'Log a gestation check'
                  : 'Edit gestation check',
              trailing: _editingId == null
                  ? null
                  : TextButton(
                      onPressed: _resetForm,
                      child: const Text('Cancel edit'),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('Site'),
                  if (_isSiteLocked)
                    TextFormField(
                      initialValue: _siteName,
                      enabled: false,
                      decoration: _inputDeco(),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _siteName.isEmpty ? null : _siteName,
                      decoration: _inputDeco(),
                      items: _kSiteOrder
                          .map((s) =>
                              DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _siteName = v ?? '';
                        _uidCtrl.text = MaternalUid.sanitize(_siteName, _uidCtrl.text);
                      }),
                    ),
                  const SizedBox(height: 12),
                  _label('How identified'),
                  DropdownButtonFormField<String>(
                    value: _identificationType,
                    decoration: _inputDeco(),
                    items: _kIdentificationTypes
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(
                        () => _identificationType = v ?? _kDefaultIdType),
                  ),
                  const SizedBox(height: 12),
                  _label("Mother's Name"),
                  TextField(controller: _nameCtrl, decoration: _inputDeco()),
                  const SizedBox(height: 12),
                  _label("Mother's UHID / CR Number"),
                  TextField(
                    controller: _uidCtrl,
                    keyboardType: _siteName == 'PGIMER'
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: MaternalUid.formatters(_siteName),
                    decoration: _inputDeco(
                      hint: MaternalUid.placeholder(_siteName),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (MaternalUid.liveError(_siteName, _uidCtrl.text).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        MaternalUid.liveError(_siteName, _uidCtrl.text),
                        style: const TextStyle(color: _kDanger, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _label('Gestation Source'),
                  DropdownButtonFormField<String>(
                    value: _gaSource.isEmpty ? null : _gaSource,
                    decoration: _inputDeco(),
                    items: _kGestationSources
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: _foundIufd ? null : (v) => _setSource(v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _foundIufd,
                    title: const Text(
                      'Found to be IUFD',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: _kText1),
                    ),
                    onChanged: (v) => setState(() {
                      _foundIufd = v ?? false;
                      if (_foundIufd) {
                        _gaSource = '';
                        _gestationMethod = '';
                        _weeksCtrl.clear();
                        _daysCtrl.clear();
                      }
                    }),
                  ),
                  if (_foundIufd)
                    const Text(
                      'Found to be IUFD — this entry will be logged but can never trigger Form A.',
                      style: TextStyle(fontSize: 12, color: _kText3),
                    ),
                  const SizedBox(height: 12),
                  _label('Method of Assessment'),
                  DropdownButtonFormField<String>(
                    value:
                        _gestationMethod.isEmpty ? null : _gestationMethod,
                    decoration: _inputDeco(),
                    items: _kGestationMethods
                        .map((m) => DropdownMenuItem(
                            value: m.$1, child: Text(m.$2)))
                        .toList(),
                    onChanged: _isReliable
                        ? (v) =>
                            setState(() => _gestationMethod = v ?? '')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _label('Gestation (completed)'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _weeksCtrl,
                        enabled: _isReliable,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hint: 'wks'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _daysCtrl,
                        enabled: _isReliable,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hint: 'days'),
                      ),
                    ),
                  ]),
                  if (!_foundIufd && _gaSource.isNotEmpty && !_isReliable) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Source is Unknown/Unreliable — this entry will be logged but can never trigger Form A.',
                      style: TextStyle(fontSize: 12, color: _kText3),
                    ),
                  ],
                  if (_saveError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_saveError,
                        style:
                            const TextStyle(color: _kDanger, fontSize: 12)),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _saving
                          ? 'Saving…'
                          : _editingId != null
                              ? 'Save changes'
                              : 'Log check',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              title:
                  'Recent checks${user?.siteName != null ? ' — ${user!.siteName}' : ''}',
              child: Column(
                children: [
                  if (_loadError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_loadError,
                          style: const TextStyle(
                              color: _kDanger, fontSize: 12)),
                    ),
                  if (!_loading && _entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No checks logged yet.',
                          style: TextStyle(color: _kText3)),
                    ),
                  ..._entries.map(_entryCard),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultBanner(Map<String, dynamic> r) {
    final eligible = r['eligible'] == true;
    final weeks = r['gestation_weeks'];
    final days = r['gestation_days'] ?? 0;
    final source = (r['ga_source'] ?? '').toString();
    late final String text;
    if (r['found_iufd'] == true) {
      text = 'Logged — not eligible for the trial (found to be IUFD).';
    } else if (eligible) {
      text =
          'Logged — gestation ${weeks}w ${days}d, under 32 weeks. Continue to Form A?';
    } else if (source.isNotEmpty && source != _kReliable) {
      text =
          'Logged — not eligible for the trial (gestation source unreliable).';
    } else if (weeks != null) {
      text =
          'Logged — not eligible for the trial (gestation ${weeks}w ${days}d).';
    } else {
      text =
          'Logged — not eligible for the trial (gestation not captured).';
    }
    return _banner(
      color: eligible ? _kWarning : _kSuccess,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 13, color: _kText1)),
          const SizedBox(height: 10),
          Row(children: [
            if (eligible)
              ElevatedButton(
                onPressed: () => _continueToFormA(r),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continue to Form A'),
              ),
            if (eligible) const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _lastResult = null),
              child: Text(eligible ? 'Not now' : 'Dismiss'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final foundIufd = e['found_iufd'] == true;
    final isGap = !foundIufd &&
        e['eligible'] == true &&
        e['continued_to_screening'] != true;
    final unreliable = (e['ga_source']?.toString().isNotEmpty == true) &&
        e['ga_source'] != _kReliable;
    final weeks = e['gestation_weeks'];
    final days = e['gestation_days'] ?? 0;
    final idType = (e['identification_type'] ?? '').toString();

    String outcome;
    Color outcomeColor = _kText3;
    if (foundIufd) {
      outcome = 'IUFD';
      outcomeColor = _kText2;
    } else if (e['continued_to_screening'] == true) {
      final sid = e['screening_id'];
      outcome = sid != null ? 'Form A started — $sid' : 'Form A started';
      outcomeColor = _kSuccess;
    } else if (e['eligible'] == true) {
      outcome = 'Eligible, no Form A';
      outcomeColor = _kWarning;
    } else if (e['eligible'] == false) {
      outcome = 'Not eligible';
      outcomeColor = _kText2;
    } else if (unreliable) {
      outcome = 'Unreliable source';
    } else {
      outcome = 'Gestation unknown';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isGap ? _kWarning.withValues(alpha: 0.08) : _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isGap ? _kWarning.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${e['mother_name'] ?? '—'}  ·  ${e['mother_uid'] ?? '—'}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: _kText1),
          ),
          const SizedBox(height: 4),
          Text(
            '${_ddmmyyyy(e['check_date'])}  ·  ${e['site_name'] ?? '—'}',
            style: const TextStyle(fontSize: 12, color: _kText3),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(idType == _kMissedIdType
                  ? 'Missed — retrospective'
                  : 'Checked at triage'),
              _chip(foundIufd ? '—' : (e['ga_source']?.toString().isNotEmpty == true
                  ? e['ga_source'].toString()
                  : '—')),
              _chip(_methodLabel(e['gestation_method']?.toString())),
              _chip(weeks != null ? '${weeks}w ${days}d' : '—'),
              _chip(outcome, color: outcomeColor),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _startEdit(e),
                child: const Text('Edit'),
              ),
              if (isGap) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                onPressed: () => _continueToFormA(e),
                style: FilledButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Continue to Form A'),
              ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? _kText3).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: color ?? _kText2,
                fontWeight: FontWeight.w600)),
      );

  Widget _stat(String value, String label, {bool warn = false}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: warn ? _kWarning.withValues(alpha: 0.45) : _kBorder),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A2340).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 3,
              decoration: BoxDecoration(
                color: warn ? _kWarning : _kPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: warn ? _kWarning : _kText1,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11, color: _kText3, height: 1.25)),
          ],
        ),
      );

  Widget _banner({required Color color, required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: child,
      );

  Widget _card({
    required String title,
    Widget? trailing,
    required Widget child,
  }) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A2340).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kText1)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _kText2)),
      );

  InputDecoration _inputDeco({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: _kBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
      );
}
