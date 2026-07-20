// lib/screens/admin/user_management_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Admin-only screen: list users, create user, disable/enable, reset password.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // ── Palette ────────────────────────────────────────────────────────────────
  static const _primary = Color(0xFF3B6FE0);
  static const _bg      = Color(0xFFEFF3FB);
  static const _surface = Color(0xFFFFFFFF);
  static const _border  = Color(0xFFD4DCF0);
  static const _text1   = Color(0xFF1A2340);
  static const _text2   = Color(0xFF4A5578);
  static const _text3   = Color(0xFF8A95B0);
  static const _danger  = Color(0xFFE53935);
  static const _success = Color(0xFF0F9D58);
  static const _warning = Color(0xFFF59E0B);

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _sites = [];
  bool _loading = true;
  String _searchQuery = '';
  String _roleFilter = 'ALL';

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get('/users/?page_size=100');
      final siteRes = await ApiClient.instance.get('/sites/');
      setState(() {
        _users    = List<Map<String, dynamic>>.from(res['users'] ?? []);
        _sites    = List<Map<String, dynamic>>.from(siteRes['sites'] ?? []);
        _loading  = false;
      });
      _applyFilter();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load users: $e'),
              backgroundColor: _danger),
        );
      }
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _users.where((u) {
        final matchRole = _roleFilter == 'ALL' || u['role'] == _roleFilter;
        final q = _searchQuery.toLowerCase();
        final matchSearch = q.isEmpty ||
            (u['full_name'] ?? '').toLowerCase().contains(q) ||
            (u['username']  ?? '').toLowerCase().contains(q) ||
            (u['email']     ?? '').toLowerCase().contains(q);
        return matchRole && matchSearch;
      }).toList();
    });
  }

  String _siteName(String? siteId) {
    if (siteId == null) return 'All Sites';
    final site = _sites.firstWhere(
        (s) => s['id'] == siteId, orElse: () => {});
    return site['site_name'] ?? siteId;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _toggleUser(Map<String, dynamic> user) async {
    final isActive = user['is_active'] as bool? ?? true;
    final action   = isActive ? 'disable' : 'enable';
    final confirm  = await _confirm(
        '${isActive ? 'Disable' : 'Enable'} user',
        'Are you sure you want to $action ${user['full_name']}?');
    if (!confirm) return;

    try {
      if (isActive) {
        await ApiClient.instance.post('/users/${user['id']}/disable');
      } else {
        await ApiClient.instance.patch('/users/${user['id']}',
            body: {'is_active': true});
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('User ${isActive ? 'disabled' : 'enabled'} successfully'),
          backgroundColor: _success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: _danger));
      }
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final confirm = await _confirm('Reset password',
        'Send a temporary password to ${user['email']}?');
    if (!confirm) return;

    try {
      await ApiClient.instance.post('/users/${user['id']}/reset-password');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Temporary password sent. Check backend terminal.'),
          backgroundColor: _success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: _danger));
      }
    }
  }

  Future<void> _unlockUser(Map<String, dynamic> user) async {
    try {
      await ApiClient.instance.post('/users/${user['id']}/unlock');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account unlocked'),
          backgroundColor: _success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: _danger));
      }
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: _text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm',
                style: TextStyle(color: _primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showCreateUserSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateUserSheet(
        sites: _sites,
        onCreated: () { Navigator.pop(context); _load(); },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _text1, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('User Management',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: _text1)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _primary),
            onPressed: _load,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _showCreateUserSheet,
              icon: const Icon(Icons.person_add_rounded,
                  size: 16, color: _primary),
              label: const Text('Add User',
                  style: TextStyle(color: _primary,
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // ── Search + filter ────────────────────────────────────────────────
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(children: [
            // Search
            TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _searchQuery = v;
                _applyFilter();
              },
              decoration: InputDecoration(
                hintText: 'Search by name, username or email...',
                hintStyle: const TextStyle(color: _text3, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: _text3, size: 18),
                filled: true, fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: _primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 8),
            // Role filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final role in [
                  'ALL', 'ADMIN', 'PI', 'SCIENTIST', 'NURSE', 'DEO', 'MONITOR'
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        _roleFilter = role;
                        _applyFilter();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _roleFilter == role
                              ? _primary : _bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _roleFilter == role
                                ? _primary : _border,
                          ),
                        ),
                        child: Text(role,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _roleFilter == role
                                  ? Colors.white : _text2,
                            )),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),

        // ── Stats bar ─────────────────────────────────────────────────────
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(children: [
            _statChip('Total', _users.length, _primary),
            const SizedBox(width: 8),
            _statChip('Active',
                _users.where((u) => u['is_active'] == true).length,
                _success),
            const SizedBox(width: 8),
            _statChip('Disabled',
                _users.where((u) => u['is_active'] == false).length,
                _danger),
            const SizedBox(width: 8),
            _statChip('Locked',
                _users.where((u) => u['status'] == 'locked').length,
                _warning),
          ]),
        ),

        Container(height: 1, color: _border),

        // ── User list ─────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.people_outline_rounded,
                              size: 48, color: _border),
                          const SizedBox(height: 10),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No users found'
                                : 'No results for "$_searchQuery"',
                            style: const TextStyle(
                                color: _text3, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _userCard(_filtered[i]),
                      ),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserSheet,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded, size: 18),
        label: const Text('Add User',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$count', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(
          fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _userCard(Map<String, dynamic> user) {
    final isActive = user['is_active'] as bool? ?? true;
    final isLocked = user['status'] == 'locked';
    final role     = user['role'] as String? ?? '';

    final roleColors = {
      'ADMIN':     (const Color(0xFF0C447C), const Color(0xFFE6F1FB)),
      'PI':        (const Color(0xFF085041), const Color(0xFFE1F5EE)),
      'SCIENTIST': (const Color(0xFF3C3489), const Color(0xFFEEEDFE)),
      'NURSE':     (const Color(0xFF633806), const Color(0xFFFAEEDA)),
      'DEO':       (const Color(0xFF712B13), const Color(0xFFFAECE7)),
      'MONITOR':   (const Color(0xFF444441), const Color(0xFFF1EFE8)),
    };
    final (fg, bg) = roleColors[role] ??
        (const Color(0xFF444441), const Color(0xFFF1EFE8));

    // Get initials
    final name   = user['full_name'] as String? ?? '?';
    final parts  = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: !isActive ? _danger.withOpacity(0.3)
              : isLocked ? _warning.withOpacity(0.3) : _border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Avatar
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isActive ? bg : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(initials,
                style: TextStyle(
                    color: isActive ? fg : _text3,
                    fontWeight: FontWeight.w800, fontSize: 15))),
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: isActive ? _text1 : _text3),
                  overflow: TextOverflow.ellipsis)),
              if (isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('LOCKED',
                      style: TextStyle(fontSize: 9,
                          color: _warning, fontWeight: FontWeight.w700)),
                ),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('DISABLED',
                      style: TextStyle(fontSize: 9,
                          color: _danger, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 2),
            Text('@${user['username'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: _text3)),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(5)),
                child: Text(role,
                    style: TextStyle(fontSize: 9,
                        color: fg, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(
                _siteName(user['site_id'] as String?),
                style: const TextStyle(fontSize: 10, color: _text3),
                overflow: TextOverflow.ellipsis,
              )),
            ]),
          ])),

          // Actions menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: _text3, size: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            onSelected: (action) {
              if (action == 'toggle')  _toggleUser(user);
              if (action == 'reset')   _resetPassword(user);
              if (action == 'unlock')  _unlockUser(user);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'toggle',
                child: Row(children: [
                  Icon(isActive
                      ? Icons.block_rounded
                      : Icons.check_circle_rounded,
                      size: 16,
                      color: isActive ? _danger : _success),
                  const SizedBox(width: 8),
                  Text(isActive ? 'Disable user' : 'Enable user',
                      style: const TextStyle(fontSize: 13)),
                ])),
              const PopupMenuItem(value: 'reset',
                child: Row(children: [
                  Icon(Icons.lock_reset_rounded, size: 16, color: _warning),
                  SizedBox(width: 8),
                  Text('Reset password', style: TextStyle(fontSize: 13)),
                ])),
              if (isLocked)
                const PopupMenuItem(value: 'unlock',
                  child: Row(children: [
                    Icon(Icons.lock_open_rounded, size: 16,
                        color: _success),
                    SizedBox(width: 8),
                    Text('Unlock account',
                        style: TextStyle(fontSize: 13)),
                  ])),
            ],
          ),
        ]),
      ),
    );
  }
}


// ── Create User Bottom Sheet ─────────────────────────────────────────────────

class _CreateUserSheet extends StatefulWidget {
  final List<Map<String, dynamic>> sites;
  final VoidCallback onCreated;
  const _CreateUserSheet({required this.sites, required this.onCreated});
  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  static const _primary = Color(0xFF3B6FE0);
  static const _bg      = Color(0xFFEFF3FB);
  static const _border  = Color(0xFFD4DCF0);
  static const _text1   = Color(0xFF1A2340);
  static const _text2   = Color(0xFF4A5578);
  static const _text3   = Color(0xFF8A95B0);
  static const _danger  = Color(0xFFE53935);
  static const _success = Color(0xFF0F9D58);

  final _formKey      = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _mobileCtrl   = TextEditingController();

  String _role    = 'NURSE';
  String? _siteId;
  bool _loading   = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role != 'ADMIN' && _siteId == null) {
      setState(() => _error = 'Please select a site for this user');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await ApiClient.instance.post('/users/', body: {
        'username' : _usernameCtrl.text.trim().toLowerCase(),
        'email'    : _emailCtrl.text.trim().toLowerCase(),
        'full_name': _nameCtrl.text.trim(),
        'mobile'   : _mobileCtrl.text.trim().isEmpty
            ? null : _mobileCtrl.text.trim(),
        'role'     : _role,
        'site_id'  : _siteId,
      });
      widget.onCreated();
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),

              const Text('Create New User',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700, color: _text1)),
              const SizedBox(height: 4),
              const Text(
                'A temporary password will be shown in the backend terminal.',
                style: TextStyle(fontSize: 11, color: _text3)),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: _danger, fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],

              _field(_nameCtrl,     'Full Name',    'e.g. Dr. Ramesh Sharma',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              _field(_usernameCtrl, 'Username',     'e.g. pi.pgimer',
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              _field(_emailCtrl,    'Email',        'institutional email',
                  keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    if (v!.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Enter valid email';
                    return null;
                  }),
              const SizedBox(height: 10),
              _field(_mobileCtrl,   'Mobile (optional)', '+91-XXXXXXXXXX',
                  keyboard: TextInputType.phone),
              const SizedBox(height: 10),

              // Role
              _label('Role'),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: _inputDec(),
                items: ['ADMIN','PI','SCIENTIST','NURSE','DEO','MONITOR']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r,
                        style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 10),

              // Site
              if (_role != 'ADMIN' && _role != 'MONITOR') ...[
                _label('Site'),
                DropdownButtonFormField<String>(
                  value: _siteId,
                  hint: const Text('Select site',
                      style: TextStyle(fontSize: 13,
                          color: _text3)),
                  decoration: _inputDec(),
                  items: widget.sites.map((s) =>
                      DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(s['site_name'] as String,
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                  onChanged: (v) => setState(() => _siteId = v),
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 6),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create User',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: _text2)),
  );

  InputDecoration _inputDec() => InputDecoration(
    filled: true, fillColor: _bg,
    contentPadding: const EdgeInsets.symmetric(
        horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primary, width: 1.5)),
  );

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(label),
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        validator: validator,
        style: const TextStyle(fontSize: 13, color: _text1),
        decoration: _inputDec().copyWith(hintText: hint,
            hintStyle: const TextStyle(color: _text3, fontSize: 12)),
      ),
    ]);
}
