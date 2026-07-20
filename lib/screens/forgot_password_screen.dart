// lib/screens/forgot_password_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _primary = Color(0xFF3B6FE0);
  static const _bg      = Color(0xFFEFF3FB);
  static const _surface = Color(0xFFFFFFFF);
  static const _border  = Color(0xFFD4DCF0);
  static const _text1   = Color(0xFF1A2340);
  static const _text2   = Color(0xFF4A5578);
  static const _text3   = Color(0xFF8A95B0);
  static const _danger  = Color(0xFFE53935);
  static const _success = Color(0xFF0F9D58);

  int    _step       = 0; // 0=email 1=otp 2=newpw 3=done
  bool   _loading    = false;
  String? _error;
  String? _resetToken;
  String  _email     = '';

  final _emailCtrl   = TextEditingController();
  final _otpCtrls    = List.generate(6, (_) => TextEditingController());
  final _pw1Ctrl     = TextEditingController();
  final _pw2Ctrl     = TextEditingController();
  final _formKey     = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    _pw1Ctrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.requestOtp(_emailCtrl.text.trim());
      _email = _emailCtrl.text.trim();
      setState(() => _step = 1);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrls.map((c) => c.text).join();
    if (otp.length < 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      _resetToken = await AuthService.instance.verifyOtp(email: _email, otp: otp);
      setState(() => _step = 2);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.resetPassword(
        resetToken:      _resetToken!,
        newPassword:     _pw1Ctrl.text,
        confirmPassword: _pw2Ctrl.text,
      );
      setState(() => _step = 3);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _text1, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _stepIcon(),
              const SizedBox(height: 20),
              _stepTitle(),
              const SizedBox(height: 8),
              _stepSubtitle(),
              const SizedBox(height: 28),
              if (_error != null) ...[
                _errorBanner(_error!),
                const SizedBox(height: 16),
              ],
              _stepBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIcon() {
    final icons  = [Icons.lock_open_rounded, Icons.email_outlined,
                    Icons.lock_rounded, Icons.check_circle_rounded];
    final colors = [_primary, _primary, _primary, _success];
    return Center(
      child: Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: colors[_step].withOpacity(0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors[_step].withOpacity(0.3)),
        ),
        child: Icon(icons[_step], color: colors[_step], size: 30),
      ),
    );
  }

  Widget _stepTitle() {
    const titles = ['Forgot password?', 'Check your email',
                    'Set new password',  'Password updated!'];
    return Text(titles[_step],
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
            color: _text1));
  }

  String _maskEmail(String email) {
    if (email.isEmpty) return 'your email';
    final at = email.indexOf('@');
    if (at < 0) return email;
    if (at <= 3) return email;
    return '${email.substring(0, 3)}***${email.substring(at)}';
  }

  Widget _stepSubtitle() {
    final subs = [
      'Enter your registered email. We\'ll send a 6-digit OTP.',
      'Enter the 6-digit code sent to ${_maskEmail(_email)}',
      'Min 8 characters · 1 uppercase · 1 number · 1 special character',
      'Your password has been changed. All active sessions have been terminated.',
    ];
    return Text(subs[_step],
        style: const TextStyle(fontSize: 13, color: _text2, height: 1.5));
  }

  Widget _errorBanner(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _danger.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: _danger, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: const TextStyle(color: _danger, fontSize: 12))),
    ]),
  );

  Widget _stepBody() {
    switch (_step) {
      case 0: return _emailStep();
      case 1: return _otpStep();
      case 2: return _newPasswordStep();
      case 3: return _doneStep();
      default: return const SizedBox();
    }
  }

  Widget _emailStep() => Column(children: [
    _inputField(
      controller: _emailCtrl,
      label: 'Email address',
      hint: 'your.name@site.org',
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
    ),
    const SizedBox(height: 20),
    _primaryBtn('Send OTP', _loading ? null : _requestOtp),
    const SizedBox(height: 12),
    _secNote('OTP expires in 10 minutes · Maximum 3 OTPs per hour'),
  ]);

  Widget _otpStep() => Column(children: [
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => _otpBox(i)),
    ),
    const SizedBox(height: 20),
    _primaryBtn('Verify OTP', _loading ? null : _verifyOtp),
    const SizedBox(height: 12),
    TextButton(
      onPressed: _loading ? null : () => setState(() => _step = 0),
      child: const Text('← Back to email',
          style: TextStyle(color: _primary, fontSize: 13)),
    ),
  ]);

  Widget _otpBox(int i) {
    return SizedBox(
      width: 44, height: 52,
      child: TextFormField(
        controller:    _otpCtrls[i],
        maxLength:     1,
        textAlign:     TextAlign.center,
        keyboardType:  TextInputType.number,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
            color: _text1),
        decoration: InputDecoration(
          counterText: '',
          filled: true, fillColor: _surface,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.5)),
        ),
        onChanged: (v) {
          if (v.length == 1 && i < 5) {
            FocusScope.of(context).nextFocus();
          }
        },
      ),
    );
  }

  Widget _newPasswordStep() => Form(
    key: _formKey,
    child: Column(children: [
      _inputField(
        controller: _pw1Ctrl,
        label: 'New password',
        hint: 'Min 8 chars, 1 uppercase, 1 number',
        icon: Icons.lock_outline_rounded,
        obscure: true,
        validator: (v) {
          if (v == null || v.isEmpty) return 'Required';
          if (v.length < 8) return 'Minimum 8 characters';
          if (!v.contains(RegExp(r'[A-Z]'))) return 'Need 1 uppercase letter';
          if (!v.contains(RegExp(r'[0-9]'))) return 'Need 1 number';
          return null;
        },
      ),
      const SizedBox(height: 12),
      _inputField(
        controller: _pw2Ctrl,
        label: 'Confirm password',
        hint: 'Re-enter new password',
        icon: Icons.lock_outline_rounded,
        obscure: true,
        validator: (v) =>
            v != _pw1Ctrl.text ? 'Passwords do not match' : null,
      ),
      const SizedBox(height: 20),
      _primaryBtn('Update password', _loading ? null : _resetPassword),
    ]),
  );

  Widget _doneStep() => Column(children: [
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4EA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _success.withOpacity(0.3)),
      ),
      child: Column(children: const [
        Icon(Icons.check_circle_outline_rounded, color: _success, size: 48),
        SizedBox(height: 12),
        Text('All existing sessions have been terminated for security.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF1E6E3B), fontSize: 13, height: 1.5)),
      ]),
    ),
    const SizedBox(height: 24),
    _primaryBtn('Back to login', () => Navigator.of(context)
        .pushNamedAndRemoveUntil('/login', (_) => false)),
  ]);

  Widget _primaryBtn(String label, VoidCallback? onPressed) => SizedBox(
    width: double.infinity, height: 50,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _primary.withOpacity(0.4),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: _loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700)),
    ),
  );

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: _text2)),
    const SizedBox(height: 5),
    TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: _text1),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _text3, fontSize: 13),
        prefixIcon: Icon(icon, color: _text3, size: 18),
        filled: true, fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _primary, width: 1.5)),
      ),
    ),
  ]);

  Widget _secNote(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFDDE6F5).withOpacity(0.6),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: _border),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: _primary, size: 14),
      const SizedBox(width: 7),
      Flexible(child: Text(text,
          style: const TextStyle(fontSize: 11, color: _text2))),
    ]),
  );
}
