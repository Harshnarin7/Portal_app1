import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/logs_api_service.dart';
import '../../utils/maternal_uid.dart';

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

const _kModesOfDelivery = [
  'Emergency LSCS',
  'Elective LSCS',
  'NVD',
  'Instrumental',
  'Other',
];

const _kNotApproachedReasons = [
  'No time to approach to screen',
  'Nurse on leave',
  'Parent not available',
  'Missed screening',
  'Other',
];

String _canonicalReason(String raw) {
  final s = raw.trim();
  if (s == 'Insufficient time') return 'No time to approach to screen';
  return s;
}

class BirthLogScreen extends StatefulWidget {
  const BirthLogScreen({super.key});

  @override
  State<BirthLogScreen> createState() => _BirthLogScreenState();
}

class _BirthLogScreenState extends State<BirthLogScreen> {
  final _uidCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _husbandCtrl = TextEditingController();
  final _weeksCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _otherReasonCtrl = TextEditingController();

  String _dateOfBirth = '';
  String _timeOfBirth = '';
  String _modeOfDelivery = '';
  String _resuscitation = '';
  String _ppv = '';
  final Set<String> _reasons = {};

  int? _editingId;
  bool _saving = false;
  bool _showReasonSection = false;
  String _saveError = '';

  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _uidCtrl.dispose();
    _nameCtrl.dispose();
    _husbandCtrl.dispose();
    _weeksCtrl.dispose();
    _daysCtrl.dispose();
    _weightCtrl.dispose();
    _otherReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = '';
    });
    try {
      final list = await LogsApiService.instance.listBirths();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.statusCode == 403
            ? "You don't have access to this log."
            : 'Could not load the birth log.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load the birth log.';
        _loading = false;
      });
    }
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _uidCtrl.clear();
      _nameCtrl.clear();
      _husbandCtrl.clear();
      _weeksCtrl.clear();
      _daysCtrl.clear();
      _weightCtrl.clear();
      _otherReasonCtrl.clear();
      _dateOfBirth = '';
      _timeOfBirth = '';
      _modeOfDelivery = '';
      _resuscitation = '';
      _ppv = '';
      _reasons.clear();
      _saveError = '';
      _showReasonSection = false;
    });
  }

  bool? _yn(String v) {
    if (v == 'Yes') return true;
    if (v == 'No') return false;
    return null;
  }

  String _ynLabel(dynamic v) {
    if (v == true) return 'Yes';
    if (v == false) return 'No';
    return '';
  }

  void _startEdit(Map<String, dynamic> entry) {
    final reasonRaw = (entry['reason_not_approached'] ?? '').toString();
    final reasonList = reasonRaw.isEmpty
        ? <String>[]
        : reasonRaw
            .split(',')
            .map(_canonicalReason)
            .where((s) => s.isNotEmpty)
            .toList();
    setState(() {
      _editingId = entry['id'] as int?;
      _uidCtrl.text = (entry['mother_uid'] ?? '').toString();
      _nameCtrl.text = (entry['mother_name'] ?? '').toString();
      _husbandCtrl.text = (entry['husband_name'] ?? '').toString();
      _dateOfBirth = (entry['date_of_birth'] ?? '').toString();
      _timeOfBirth = (entry['time_of_birth'] ?? '').toString();
      if (_timeOfBirth.length >= 5) {
        _timeOfBirth = _timeOfBirth.substring(0, 5);
      }
      _weeksCtrl.text = entry['gestation_weeks']?.toString() ?? '';
      _daysCtrl.text = entry['gestation_days']?.toString() ?? '';
      _modeOfDelivery = (entry['mode_of_delivery'] ?? '').toString();
      _weightCtrl.text = entry['birth_weight_grams']?.toString() ?? '';
      _resuscitation = _ynLabel(entry['resuscitation_required']);
      _ppv = _ynLabel(entry['ppv_required']);
      _reasons
        ..clear()
        ..addAll(reasonList);
      _otherReasonCtrl.text = reasonList.contains('Other')
          ? (entry['reason_not_approached_other'] ?? '').toString()
          : '';
      _saveError = '';
      _showReasonSection = reasonList.isNotEmpty;
    });
  }

  void _startAddReason(Map<String, dynamic> entry) {
    _startEdit(entry);
    setState(() => _showReasonSection = true);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateOfBirth.isNotEmpty
        ? DateTime.tryParse(_dateOfBirth) ?? now
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _dateOfBirth =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    if (_timeOfBirth.length >= 5) {
      final parts = _timeOfBirth.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        initial = TimeOfDay(hour: h, minute: m);
      }
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _timeOfBirth =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save() async {
    final uid = _uidCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final site = context.read<AuthProvider>().user?.siteName;
    final uidError = MaternalUid.saveError(site, uid);
    if (uidError.isNotEmpty) {
      setState(() => _saveError = uidError);
      return;
    }
    if (uid.isEmpty && name.isEmpty) {
      setState(() => _saveError =
          "Enter at least the Mother's UHID/CR Number or Name.");
      return;
    }
    if (_dateOfBirth.isEmpty) {
      setState(() => _saveError = 'Date of birth is required.');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = '';
    });

    final weeks = int.tryParse(_weeksCtrl.text.trim());
    final days = int.tryParse(_daysCtrl.text.trim());
    final weight = num.tryParse(_weightCtrl.text.trim());
    final payload = <String, dynamic>{
      'mother_uid': uid.isEmpty ? null : uid,
      'mother_name': name.isEmpty ? null : name,
      'husband_name':
          _husbandCtrl.text.trim().isEmpty ? null : _husbandCtrl.text.trim(),
      'date_of_birth': _dateOfBirth,
      'time_of_birth': _timeOfBirth.isEmpty ? null : _timeOfBirth,
      'gestation_weeks': weeks,
      'gestation_days': days,
      'mode_of_delivery': _modeOfDelivery.isEmpty ? null : _modeOfDelivery,
      'birth_weight_grams': weight,
      'resuscitation_required': _yn(_resuscitation),
      'ppv_required': _yn(_ppv),
      'reason_not_approached':
          _reasons.isEmpty ? null : _reasons.join(', '),
      'reason_not_approached_other': _reasons.contains('Other')
          ? (_otherReasonCtrl.text.trim().isEmpty
              ? null
              : _otherReasonCtrl.text.trim())
          : null,
    };

    try {
      if (_editingId != null) {
        await LogsApiService.instance.updateBirth(_editingId!, payload);
      } else {
        await LogsApiService.instance.createBirth(payload);
      }
      if (!mounted) return;
      _resetForm();
      setState(() => _saving = false);
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

  int get _alertCount => _entries
      .where((e) =>
          e['match_status'] == 'in_range_no_match' || e['ga_log_missing'] == true)
      .length;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: _kText1,
        elevation: 0,
        title: const Text(
          'Log of All Births',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Text(
              'Completed for every birth at this hospital, not just trial-enrolled ones — catches a GA-eligible (25w0d–31w6d) delivery with no matching Form A on file.',
              style: TextStyle(fontSize: 12, color: _kText2, height: 1.4),
            ),
            if (_alertCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: _kWarning.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$_alertCount entr${_alertCount == 1 ? 'y needs' : 'ies need'} review — "Not filled Form A" and/or "Never Checked GA log" below.',
                  style: const TextStyle(fontSize: 12, color: _kText1),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _card(
              title: _editingId != null ? 'Edit entry' : 'Add a birth',
              trailing: _editingId != null
                  ? TextButton(
                      onPressed: _resetForm,
                      child: const Text('Cancel edit'))
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label("Mother's UHID / CR Number"),
                  TextField(
                    controller: _uidCtrl,
                    keyboardType: user?.siteName == 'PGIMER'
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: MaternalUid.formatters(user?.siteName),
                    decoration: _inputDeco(
                      hint: MaternalUid.placeholder(user?.siteName),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (MaternalUid.liveError(user?.siteName, _uidCtrl.text).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        MaternalUid.liveError(user?.siteName, _uidCtrl.text),
                        style: const TextStyle(color: _kDanger, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _label("Mother's Name"),
                  TextField(controller: _nameCtrl, decoration: _inputDeco()),
                  const SizedBox(height: 12),
                  _label("Husband's Name"),
                  TextField(
                      controller: _husbandCtrl, decoration: _inputDeco()),
                  const SizedBox(height: 12),
                  _label('Date of Birth *'),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: _inputDeco(),
                      child: Text(
                        _dateOfBirth.isEmpty ? 'Select date' : _dateOfBirth,
                        style: TextStyle(
                          color:
                              _dateOfBirth.isEmpty ? _kText3 : _kText1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('Time of Birth'),
                  InkWell(
                    onTap: _pickTime,
                    child: InputDecorator(
                      decoration: _inputDeco(),
                      child: Text(
                        _timeOfBirth.isEmpty ? 'Select time' : _timeOfBirth,
                        style: TextStyle(
                          color:
                              _timeOfBirth.isEmpty ? _kText3 : _kText1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('Gestation (completed)'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _weeksCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hint: 'wks'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _daysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _inputDeco(hint: 'days'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _label('Mode of Delivery'),
                  DropdownButtonFormField<String>(
                    value: _modeOfDelivery.isEmpty ? null : _modeOfDelivery,
                    decoration: _inputDeco(),
                    items: _kModesOfDelivery
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _modeOfDelivery = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  _label('Birth Weight (g)'),
                  TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco(),
                  ),
                  const SizedBox(height: 12),
                  _label('Resuscitation required?'),
                  DropdownButtonFormField<String>(
                    value: _resuscitation.isEmpty ? null : _resuscitation,
                    decoration: _inputDeco(),
                    items: const [
                      DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                      DropdownMenuItem(value: 'No', child: Text('No')),
                    ],
                    onChanged: (v) =>
                        setState(() => _resuscitation = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  _label('PPV required?'),
                  DropdownButtonFormField<String>(
                    value: _ppv.isEmpty ? null : _ppv,
                    decoration: _inputDeco(),
                    items: const [
                      DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                      DropdownMenuItem(value: 'No', child: Text('No')),
                    ],
                    onChanged: (v) => setState(() => _ppv = v ?? ''),
                  ),
                  const SizedBox(height: 14),
                  if (_showReasonSection) ...[
                    const Text(
                      'If no matching Form A is found, reason not approached',
                      style: TextStyle(fontSize: 12, color: _kText2),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kNotApproachedReasons.map((opt) {
                      final checked = _reasons.contains(opt);
                      return FilterChip(
                        label: Text(opt),
                        selected: checked,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _reasons.add(opt);
                            } else {
                              _reasons.remove(opt);
                              if (opt == 'Other') {
                                _otherReasonCtrl.clear();
                              }
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (_reasons.contains('Other')) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otherReasonCtrl,
                      decoration: _inputDeco(hint: 'Please specify…'),
                    ),
                  ],
                  ],
                  if (_saveError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_saveError,
                        style:
                            const TextStyle(color: _kDanger, fontSize: 12)),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : _editingId != null
                              ? 'Save changes'
                              : 'Add entry',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              title:
                  'Entries${user?.siteName != null ? ' — ${user!.siteName}' : ''}',
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
                      child: Text('No births logged yet.',
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

  Widget _entryCard(Map<String, dynamic> e) {
    final alert = e['match_status'] == 'in_range_no_match' ||
        e['ga_log_missing'] == true;
    final canAddReason = e['match_status'] == 'in_range_no_match' &&
        (e['reason_not_approached'] ?? '').toString().trim().isEmpty;
    final weeks = e['gestation_weeks'];
    final days = e['gestation_days'] ?? 0;
    final date = _ddmmyyyy(e['date_of_birth']);
    final time = e['time_of_birth'];
    final timeStr = time == null || time.toString().isEmpty
        ? ''
        : ' ${time.toString().length >= 5 ? time.toString().substring(0, 5) : time}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert ? _kWarning.withValues(alpha: 0.08) : _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: alert ? _kWarning.withValues(alpha: 0.4) : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '$date$timeStr',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: _kText1),
              ),
            ),
            TextButton(
              onPressed: () => _startEdit(e),
              child: const Text('Edit'),
            ),
          ]),
          Text(
            '${e['mother_name'] ?? '—'}  ·  ${e['mother_uid'] ?? '—'}',
            style: const TextStyle(fontSize: 13, color: _kText2),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(weeks != null ? '${weeks}w ${days}d' : '—'),
              _chip(e['mode_of_delivery']?.toString() ?? '—'),
              _chip('${e['birth_weight_grams'] ?? '—'} g'),
              _chip(
                  'Resus. ${_ynLabel(e['resuscitation_required']).isEmpty ? '—' : _ynLabel(e['resuscitation_required'])}'),
              _chip(
                  'PPV ${_ynLabel(e['ppv_required']).isEmpty ? '—' : _ynLabel(e['ppv_required'])}'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _matchBadges(
              e['match_status']?.toString(),
              e['matched_screening_id']?.toString(),
              e['ga_log_missing'] == true,
            ),
          ),
          if ((e['reason_not_approached'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason not approached: ${(e['reason_not_approached'] ?? '').toString().split(',').map(_canonicalReason).where((s) => s.isNotEmpty).join(', ')}',
              style: const TextStyle(fontSize: 12, color: _kText3),
            ),
          ] else if (canAddReason) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _startAddReason(e),
                child: const Text('+ Add reason'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _matchBadges(String? status, String? screeningId, bool gaLogMissing) {
    final badges = <Widget>[];
    String label;
    Color color;
    switch (status) {
      case 'matched':
        label = screeningId != null && screeningId.isNotEmpty
            ? 'Matched — $screeningId'
            : 'Matched';
        color = _kSuccess;
        break;
      case 'in_range_no_match':
        label = 'Not filled Form A';
        color = _kWarning;
        break;
      case 'ga_unknown':
        label = 'GA unknown';
        color = _kText3;
        break;
      default:
        label = 'Out of range';
        color = _kText3;
    }
    badges.add(_chip(label, color: color));
    if (gaLogMissing) {
      badges.add(_chip('Never Checked GA log', color: _kDanger));
    }
    return badges;
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
                fontWeight: FontWeight.w600,
                color: color ?? _kText2)),
      );

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) =>
      Container(
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
            Row(children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kText1)),
              ),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 12),
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
