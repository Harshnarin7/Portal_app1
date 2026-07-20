// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../services/api_client.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  // Change password
  bool _showChangePw  = false;
  bool _obscure1 = true, _obscure2 = true, _obscure3 = true;
  bool _saving   = false;
  String? _pwError, _pwSuccess;
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // Session info
  Map<String, dynamic> _sessions = {};
  bool _loadingSessions = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    // Just get current user info for last login
    setState(() => _loadingSessions = false);
  }

  Future<void> _changePassword() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _pwError = 'Passwords do not match');
      return;
    }
    if (_newCtrl.text.length < 8) {
      setState(() => _pwError = 'Minimum 8 characters required');
      return;
    }
    if (!_newCtrl.text.contains(RegExp(r'[A-Z]'))) {
      setState(() => _pwError = 'Need at least 1 uppercase letter');
      return;
    }
    if (!_newCtrl.text.contains(RegExp(r'[0-9]'))) {
      setState(() => _pwError = 'Need at least 1 number');
      return;
    }

    setState(() { _saving = true; _pwError = null; _pwSuccess = null; });

    final err = await context.read<AuthProvider>().changePassword(
      current: _currentCtrl.text,
      newPw:   _newCtrl.text,
      confirm: _confirmCtrl.text,
    );

    if (mounted) {
      setState(() {
        _saving = false;
        if (err == null) {
          _pwSuccess = 'Password changed successfully!';
          _pwError   = null;
          _currentCtrl.clear();
          _newCtrl.clear();
          _confirmCtrl.clear();
          _showChangePw = false;
        } else {
          _pwError = err;
        }
      });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: _text3))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout', style: TextStyle(
                  color: _danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;

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
        title: const Text('My Profile', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: _text1)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar card ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B6FE0), Color(0xFF2554C7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(children: [
                // Avatar circle
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                  ),
                  child: Center(child: Text(user.initials,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 26, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(height: 12),
                Text(user.fullName, style: const TextStyle(
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('@${user.username}', style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 10),
                // Role badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(user.role.displayName,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // ── Account info ─────────────────────────────────────────────
            _section('Account Information', [
              _infoRow(Icons.email_outlined,     'Email',     user.email),
              _infoRow(Icons.person_outline,      'Username',  user.username),
              _infoRow(Icons.phone_outlined,      'Mobile',
                  user.mobile ?? 'Not set'),
              _infoRow(Icons.location_on_outlined,'Site',
                  user.siteName ?? 'All Sites'),
              _infoRow(Icons.shield_outlined,     'Role',
                  user.role.displayName),
              if (user.lastLoginAt != null)
                _infoRow(Icons.access_time_rounded, 'Last login',
                    _formatDate(user.lastLoginAt!)),
            ]),

            const SizedBox(height: 12),

            // ── Permissions ───────────────────────────────────────────────
            _section('Your Permissions', [
              _permRow('View own site data',     true),
              _permRow('Add new participants',
                  user.role.canAddParticipant),
              _permRow('Fill & submit forms',
                  user.role == UserRole.nurse || user.role == UserRole.deo ||
                  user.role == UserRole.admin),
              _permRow('Approve & lock forms',   user.role.canApprove),
              _permRow('View all sites',         user.role.isGlobal),
              _permRow('User management',
                  user.role == UserRole.admin),
            ]),

            const SizedBox(height: 12),

            // ── Security ──────────────────────────────────────────────────
            _sectionHeader('Security'),
            const SizedBox(height: 8),

            // Change password toggle
            GestureDetector(
              onTap: () => setState(() => _showChangePw = !_showChangePw),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock_reset_rounded,
                        color: _primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Change Password', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: _text1)),
                      Text('Update your login password',
                          style: TextStyle(fontSize: 11, color: _text3)),
                    ],
                  )),
                  Icon(_showChangePw
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      color: _text3),
                ]),
              ),
            ),

            // Change password form
            if (_showChangePw) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(children: [
                  if (_pwError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: _danger, size: 15),
                        const SizedBox(width: 7),
                        Expanded(child: Text(_pwError!,
                            style: const TextStyle(
                                color: _danger, fontSize: 12))),
                      ]),
                    ),
                  if (_pwSuccess != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline,
                            color: _success, size: 15),
                        const SizedBox(width: 7),
                        Text(_pwSuccess!,
                            style: const TextStyle(
                                color: _success, fontSize: 12)),
                      ]),
                    ),
                  _pwField(_currentCtrl, 'Current password', _obscure1,
                      () => setState(() => _obscure1 = !_obscure1)),
                  const SizedBox(height: 10),
                  _pwField(_newCtrl, 'New password', _obscure2,
                      () => setState(() => _obscure2 = !_obscure2)),
                  const SizedBox(height: 10),
                  _pwField(_confirmCtrl, 'Confirm new password', _obscure3,
                      () => setState(() => _obscure3 = !_obscure3)),
                  const SizedBox(height: 14),
                  // Password requirements
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Requirements:',
                            style: TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w700, color: _text2)),
                        const SizedBox(height: 4),
                        for (final r in [
                          'At least 8 characters',
                          'At least 1 uppercase letter',
                          'At least 1 number',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              const Icon(Icons.check_rounded,
                                  color: _primary, size: 12),
                              const SizedBox(width: 5),
                              Text(r, style: const TextStyle(
                                  fontSize: 11, color: _text2)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity, height: 46,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Update Password',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 12),

            // ── App info ──────────────────────────────────────────────────
            _section('App Information', [
              _infoRow(Icons.info_outline_rounded, 'Version',   'PORTAL CRF v1.0'),
              _infoRow(Icons.business_rounded,     'System',    'PORTAL Clinical Trial'),
              _infoRow(Icons.security_rounded,     'Compliance','ICH-GCP · CDSCO · ICMR'),
            ]),

            const SizedBox(height: 16),

            // ── Logout button ─────────────────────────────────────────────
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Logout',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFDECEC),
                  foregroundColor: _danger,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                      side: BorderSide(color: _danger.withOpacity(0.3))),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: _text1));

  Widget _section(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(title),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(children: rows.asMap().entries.map((e) {
          final isLast = e.key == rows.length - 1;
          return Column(children: [
            e.value,
            if (!isLast)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, color: _border),
              ),
          ]);
        }).toList()),
      ),
    ],
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(children: [
      Icon(icon, color: _primary, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 10, color: _text3, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(
            fontSize: 13, color: _text1, fontWeight: FontWeight.w500)),
      ])),
      GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label copied'),
                duration: const Duration(seconds: 1),
                backgroundColor: _success),
          );
        },
        child: const Icon(Icons.copy_rounded, size: 14, color: _text3),
      ),
    ]),
  );

  Widget _permRow(String label, bool allowed) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    child: Row(children: [
      Icon(allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: allowed ? _success : _text3, size: 18),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(
          fontSize: 13,
          color: allowed ? _text1 : _text3,
          fontWeight: allowed ? FontWeight.w500 : FontWeight.w400)),
    ]),
  );

  Widget _pwField(TextEditingController ctrl, String label,
      bool obscure, VoidCallback toggle) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: _text2)),
      const SizedBox(height: 5),
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14, color: _text1),
        decoration: InputDecoration(
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
          suffixIcon: IconButton(
            icon: Icon(obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
                color: _text3, size: 18),
            onPressed: toggle,
          ),
        ),
      ),
    ]);

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inHours < 1)    return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)     return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
