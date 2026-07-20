// lib/services/auth_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// REPLACED: the old hardcoded-credential Map is gone entirely.
// Now uses real JWT authentication against the PORTAL FastAPI backend.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user.dart';
import 'api_client.dart';
import 'token_storage.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Returns the authenticated [UserProfile] on success.
  /// Throws [ApiException] with a human-readable [message] on failure.
  Future<UserProfile> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final deviceId = await TokenStorage.getOrCreateDeviceId();

    // NOTE: do NOT lowercase this — the backend matches User.username with a
    // case-sensitive `==`. Lowercasing here would break login for any
    // account whose username contains uppercase letters. Only trim.
    final data = await ApiClient.instance.post('/auth/login', body: {
      'email_or_username': emailOrUsername.trim(),
      'password':          password,
      'device_id':         deviceId,
      'device_name':       'Flutter Android',
      'device_os':         'Android',
      'app_version':       '1.0.0',
    });

    // Persist tokens in Android Keystore
    await TokenStorage.saveTokens(
      accessToken:  data['access_token']  as String,
      refreshToken: data['refresh_token'] as String,
    );

    final userJson = data['user'] as Map<String, dynamic>;
    final profile  = UserProfile.fromJson(userJson);

    // Cache profile for fast boot next time
    await TokenStorage.saveProfile(userJson);

    return profile;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await ApiClient.instance.post('/auth/logout');
    } catch (_) {
      // Even if the server call fails, clear local tokens
    }
    await TokenStorage.clearAll();
  }

  // ── Restore session from secure storage ──────────────────────────────────

  /// Called on app boot. Returns [UserProfile] if a valid session exists.
  Future<UserProfile?> restoreSession() async {
    final hasTokens = await TokenStorage.hasValidTokens();
    if (!hasTokens) return null;

    try {
      final data = await ApiClient.instance.get('/auth/me');
      final profile = UserProfile.fromJson(data);
      await TokenStorage.saveProfile(data);
      return profile;
    } catch (_) {
      await TokenStorage.clearAll();
      return null;
    }
  }

  // ── Change password (authenticated) ──────────────────────────────────────

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await ApiClient.instance.post('/auth/change-password', body: {
      'current_password':  currentPassword,
      'new_password':      newPassword,
      'confirm_password':  confirmPassword,
    });
  }

  // ── Forgot password — step 1: request OTP ────────────────────────────────

  Future<void> requestOtp(String email) async {
    await ApiClient.instance.post('/auth/forgot-password', body: {
      'email': email.trim().toLowerCase(),
    });
  }

  // ── Forgot password — step 2: verify OTP ─────────────────────────────────

  /// Returns the reset_token on success.
  Future<String> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final data = await ApiClient.instance.post('/auth/verify-otp', body: {
      'email': email.trim().toLowerCase(),
      'otp':   otp.trim(),
    });
    return data['reset_token'] as String;
  }

  // ── Forgot password — step 3: reset password ─────────────────────────────

  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await ApiClient.instance.post('/auth/reset-password', body: {
      'reset_token':      resetToken,
      'new_password':     newPassword,
      'confirm_password': confirmPassword,
    });
  }
}
