// lib/screens/login_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Fully redesigned login screen.
// - Email/username + password (no site dropdown — that was the old shared-creds
//   model; now the server assigns a site per user account)
// - Show/hide password toggle
// - Remember me (persists username in SharedPreferences)
// - Forgot Password link
// - Session timeout warning banner
// - Matches existing Warm Slate Blue palette
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl   = TextEditingController();

  bool _obscure      = true;
  bool _rememberMe   = false;
  bool _submitting   = false;

  // ── Palette (matches existing Warm Slate Blue theme) ─────────────────────
  static const _navy    = Color(0xFF0B1829);
  static const _primary = Color(0xFF3B6FE0);
  static const _primaryD= Color(0xFF2554C7);
  static const _surface = Color(0xFFFFFFFF);
  static const _bg      = Color(0xFFEFF3FB);
  static const _border  = Color(0xFFD4DCF0);
  static const _danger  = Color(0xFFE53935);
  static const _text1   = Color(0xFF1A2340);
  static const _text2   = Color(0xFF4A5578);
  static const _text3   = Color(0xFF8A95B0);
  static const _pSoft   = Color(0xFFDDE6F5);

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
  }

  Future<void> _loadSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_username');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _identifierCtrl.text = saved;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final auth = context.read<AuthProvider>();
    auth.clearError();

    if (_rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', _identifierCtrl.text.trim());
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_username');
    }

    await auth.login(
      emailOrUsername: _identifierCtrl.text.trim(),
      password:        _passwordCtrl.text,
    );
    // AuthGate in main.dart reacts to auth.status change — no push needed.

    if (mounted) setState(() => _submitting = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth  = context.watch<AuthProvider>();
    final error = auth.error;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 40,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // ── Logo & branding ──────────────────────────────────────
                Center(
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primary, _primaryD],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset('assets/app_icon/app_icon.png',
                          fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('PORTAL', textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        letterSpacing: 2.4, color: _text1)),
                const SizedBox(height: 4),
                const Text('Clinical Trial Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _text3, letterSpacing: .5)),

                const SizedBox(height: 36),

                // ── Card ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withOpacity(0.06),
                        blurRadius: 20, offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Sign in', style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: _text1)),
                      const SizedBox(height: 4),
                      const Text('Use your institutional account',
                          style: TextStyle(fontSize: 12, color: _text3)),
                      const SizedBox(height: 20),

                      // Error banner
                      if (error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _danger.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded,
                                color: _danger, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(error,
                                style: const TextStyle(
                                    color: _danger, fontSize: 12))),
                          ]),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Email / username
                      _field(
                        controller: _identifierCtrl,
                        label: 'Username or Email',
                        hint: 'rn.pgimer01 or email@site.org',
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),

                      // Password
                      _field(
                        controller: _passwordCtrl,
                        label: 'Password',
                        hint: 'Enter your password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: _text3, size: 19,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Remember me + Forgot
                      Row(children: [
                        GestureDetector(
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 18, height: 18,
                              decoration: BoxDecoration(
                                color: _rememberMe ? _primary : _surface,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                    color: _rememberMe ? _primary : _border,
                                    width: 1.5),
                              ),
                              child: _rememberMe
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 12)
                                  : null,
                            ),
                            const SizedBox(width: 7),
                            const Text('Remember me',
                                style: TextStyle(
                                    fontSize: 12, color: _text2)),
                          ]),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/forgot-password'),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text('Forgot password?',
                              style: TextStyle(
                                  fontSize: 12, color: _primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // Login button
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_submitting || auth.loading) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _primary.withOpacity(0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: (_submitting || auth.loading)
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Sign in',
                                  style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700,
                                      letterSpacing: .3)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Security note
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _pSoft.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: Row(children: const [
                    Icon(Icons.shield_outlined, color: _primary, size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Secured with JWT · 30 min session timeout · ICH-GCP compliant',
                        style: TextStyle(fontSize: 11, color: _text2),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),
                const Text('PORTAL CRF v1.0 · PGIMER Chandigarh',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: _text3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Field builder ─────────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _text2)),
      const SizedBox(height: 5),
      TextFormField(
        controller:    controller,
        obscureText:   obscure,
        keyboardType:  keyboardType,
        autocorrect:   false,
        style: const TextStyle(fontSize: 14, color: _text1),
        validator:     validator,
        decoration: InputDecoration(
          hintText:      hint,
          hintStyle:     const TextStyle(color: _text3, fontSize: 13),
          prefixIcon:    Icon(icon, color: _text3, size: 18),
          suffixIcon:    suffix,
          filled:        true,
          fillColor:     _bg,
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
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _danger)),
        ),
      ),
    ]);
  }
}
