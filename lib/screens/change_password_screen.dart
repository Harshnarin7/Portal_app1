// lib/screens/change_password_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _primary = Color(0xFF3B6FE0);
  static const _bg      = Color(0xFFEFF3FB);
  static const _surface = Color(0xFFFFFFFF);
  static const _border  = Color(0xFFD4DCF0);
  static const _text1   = Color(0xFF1A2340);
  static const _text2   = Color(0xFF4A5578);
  static const _text3   = Color(0xFF8A95B0);
  static const _danger  = Color(0xFFE53935);
  static const _warning = Color(0xFFF59E0B);

  final _formKey     = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure1 = true, _obscure2 = true, _obscure3 = true;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final auth = context.read<AuthProvider>();
    final err  = await auth.changePassword(
      current: _currentCtrl.text,
      newPw:   _newCtrl.text,
      confirm: _confirmCtrl.text,
    );

    if (mounted) {
      setState(() { _loading = false; _error = err; });
      // On success auth.user.mustChangePassword becomes false →
      // AuthGate rebuilds and navigates to the correct dashboard automatically.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _warning.withOpacity(0.4)),
                ),
                child: Row(children: const [
                  Icon(Icons.warning_amber_rounded, color: _warning, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You must set a new password before continuing. '
                      'This is required on first login.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A5200), height: 1.5),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              // Icon
              Center(
                child: Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: _primary, size: 28),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Set new password',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                      color: _text1)),
              const SizedBox(height: 4),
              const Text('Choose a strong password for your account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _text3)),
              const SizedBox(height: 28),

              // Form card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEC),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: _danger, size: 15),
                          const SizedBox(width: 7),
                          Expanded(child: Text(_error!,
                              style: const TextStyle(
                                  color: _danger, fontSize: 12))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],

                    _pwField(_currentCtrl, 'Current password',
                        _obscure1, () => setState(() => _obscure1 = !_obscure1),
                        (v) => v!.isEmpty ? 'Required' : null),
                    const SizedBox(height: 12),
                    _pwField(_newCtrl, 'New password',
                        _obscure2, () => setState(() => _obscure2 = !_obscure2),
                        (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v.length < 8) return 'Minimum 8 characters';
                          if (!v.contains(RegExp(r'[A-Z]')))
                            return 'Need at least 1 uppercase letter';
                          if (!v.contains(RegExp(r'[0-9]')))
                            return 'Need at least 1 number';
                          if (!v.contains(RegExp(r'[!@#\$%^&*]')))
                            return 'Need at least 1 special character';
                          return null;
                        }),
                    const SizedBox(height: 12),
                    _pwField(_confirmCtrl, 'Confirm new password',
                        _obscure3, () => setState(() => _obscure3 = !_obscure3),
                        (v) => v != _newCtrl.text ? 'Passwords do not match' : null),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13)),
                        ),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Update password',
                                style: TextStyle(fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 16),
              // Password policy hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE6F5).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Password requirements:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: _text2)),
                    const SizedBox(height: 6),
                    for (final req in [
                      'At least 8 characters',
                      'At least 1 uppercase letter (A–Z)',
                      'At least 1 number (0–9)',
                      'At least 1 special character (!@#\$%)',
                      'Cannot reuse your last 5 passwords',
                    ]) _reqRow(req),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.read<AuthProvider>().logout(),
                child: const Text('Logout instead',
                    style: TextStyle(color: _text3, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pwField(
    TextEditingController ctrl,
    String label,
    bool obscure,
    VoidCallback toggle,
    String? Function(String?) validator,
  ) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: _text2)),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          obscureText: obscure,
          validator: validator,
          style: const TextStyle(fontSize: 14, color: _text1),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: _text3, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                color: _text3, size: 18,
              ),
              onPressed: toggle,
            ),
            filled: true, fillColor: _bg,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _primary, width: 1.5)),
          ),
        ),
      ]);

  Widget _reqRow(String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(children: [
      const Icon(Icons.check_rounded, color: _primary, size: 13),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 11, color: _text2)),
    ]),
  );
}
