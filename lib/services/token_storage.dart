// lib/services/token_storage.dart
// Uses SharedPreferences for emulator testing.
// Replace with flutter_secure_storage for production physical devices.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  TokenStorage._();

  static const _kAccess   = 'portal_access_token';
  static const _kRefresh  = 'portal_refresh_token';
  static const _kProfile  = 'portal_user_profile';
  static const _kDeviceId = 'portal_device_id';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  // ── Tokens ────────────────────────────────────────────────────────────────

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final p = await _prefs;
    await Future.wait([
      p.setString(_kAccess,  accessToken),
      p.setString(_kRefresh, refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() async {
    final p = await _prefs;
    return p.getString(_kAccess);
  }

  static Future<String?> getRefreshToken() async {
    final p = await _prefs;
    return p.getString(_kRefresh);
  }

  // ── Profile cache ─────────────────────────────────────────────────────────

  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    final p = await _prefs;
    await p.setString(_kProfile, jsonEncode(profile));
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    final p = await _prefs;
    final raw = p.getString(_kProfile);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // ── Device ID ─────────────────────────────────────────────────────────────

  static Future<String> getOrCreateDeviceId() async {
    final p = await _prefs;
    String? id = p.getString(_kDeviceId);
    if (id == null) {
      id = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
      await p.setString(_kDeviceId, id);
    }
    return id;
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    final p = await _prefs;
    await Future.wait([
      p.remove(_kAccess),
      p.remove(_kRefresh),
      p.remove(_kProfile),
    ]);
  }

  static Future<bool> hasValidTokens() async {
    final access = await getAccessToken();
    return access != null && access.isNotEmpty;
  }
}
