// lib/services/api_client.dart
// ─────────────────────────────────────────────────────────────────────────────
// Centralised HTTP client for the PORTAL backend.
// Automatically attaches the Bearer token to every request.
// On 401, silently attempts a token refresh before retrying once.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'token_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // ── Base URL: switch between dev and prod ────────────────────────────────
  // For local development:
  //   - Android emulator talking to a backend on the SAME machine: 10.0.2.2
  //     (Android's special loopback alias for the host machine's localhost)
  //   - Physical phone on the same Wi-Fi as your dev machine: use your
  //     machine's LAN IP instead, e.g. http://192.168.1.42:8000
  // NOTE: no "/api/v1" — the FastAPI backend mounts all routers at the root
  // (e.g. /auth/login, /screenings/...), not under a versioned prefix.
  static const String _base =
      String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000');

  bool _refreshing = false;

  // ── Core request method ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    final token    = await TokenStorage.getAccessToken();
    final deviceId = await TokenStorage.getOrCreateDeviceId();

    final headers = {
      'Content-Type': 'application/json',
      'X-Device-ID':  deviceId,
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$_base$path');
    http.Response resp;

    switch (method.toUpperCase()) {
      case 'GET':
        resp = await http.get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
        break;
      case 'POST':
        resp = await http.post(uri, headers: headers,
            body: body != null ? jsonEncode(body) : null)
            .timeout(const Duration(seconds: 30));
        break;
      case 'PUT':
        resp = await http.put(uri, headers: headers,
            body: body != null ? jsonEncode(body) : null)
            .timeout(const Duration(seconds: 30));
        break;
      case 'PATCH':
        resp = await http.patch(uri, headers: headers,
            body: body != null ? jsonEncode(body) : null)
            .timeout(const Duration(seconds: 30));
        break;
      case 'DELETE':
        resp = await http.delete(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
        break;
      default:
        throw ApiException(0, 'Unknown method $method');
    }

    // 401 → attempt silent token refresh then retry once.
    // Exception: never do this for the auth endpoints themselves —
    // /auth/login and /auth/refresh returning 401 means "wrong password" /
    // "invalid refresh token", not "your session expired". Let those fall
    // through to _parse() below so the real backend message (e.g. "Invalid
    // credentials", "Account is deactivated") reaches the user instead of
    // being masked as "Session expired".
    final isAuthEndpoint = path.startsWith('/auth/login') || path.startsWith('/auth/refresh');
    if (resp.statusCode == 401 && retry && !_refreshing && !isAuthEndpoint) {
      final refreshed = await _silentRefresh();
      if (refreshed) {
        return request(method, path, body: body, retry: false);
      }
      throw const ApiException(401, 'Session expired. Please log in again.');
    }

    return _parse(resp);
  }

  // ── Convenience shorthands ────────────────────────────────────────────────

  Future<Map<String, dynamic>> get(String path) =>
      request('GET', path);

  // For endpoints that return a raw JSON array (e.g. GET /screenings/)
  // rather than an object — get() above can't be reused here since it's
  // hard-typed to Map and would throw a cast error on a List response.
  Future<List<dynamic>> getList(String path) async {
    Future<Map<String, String>> buildHeaders() async {
      final token    = await TokenStorage.getAccessToken();
      final deviceId = await TokenStorage.getOrCreateDeviceId();
      return {
        'Content-Type': 'application/json',
        'X-Device-ID':  deviceId,
        if (token != null) 'Authorization': 'Bearer $token',
      };
    }

    final uri = Uri.parse('$_base$path');
    var resp = await http.get(uri, headers: await buildHeaders())
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 401 && !_refreshing) {
      final refreshed = await _silentRefresh();
      if (refreshed) {
        resp = await http.get(uri, headers: await buildHeaders())
            .timeout(const Duration(seconds: 30));
      } else {
        throw const ApiException(401, 'Session expired. Please log in again.');
      }
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return [];
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw ApiException(resp.statusCode, 'Request failed (${resp.statusCode})');
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) =>
      request('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) =>
      request('PUT', path, body: body);

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) =>
      request('PATCH', path, body: body);

  // ── Parse response ────────────────────────────────────────────────────────

  Map<String, dynamic> _parse(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    String detail = resp.statusCode == 429
        ? 'Too many attempts. Please wait a few minutes and try again.'
        : 'Request failed (${resp.statusCode})';
    try {
      final err = jsonDecode(resp.body);
      if (err is Map) {
        // Different backend error shapes use different keys — check the
        // common ones instead of assuming 'detail' is always present
        // (e.g. rate-limit responses used to use 'error'/'message' only).
        final d = err['detail'] ?? err['message'] ?? err['error'];
        if (d != null) detail = d.toString();
      }
    } catch (_) {}
    throw ApiException(resp.statusCode, detail);
  }

  // ── Silent token refresh ──────────────────────────────────────────────────

  Future<bool> _silentRefresh() async {
    _refreshing = true;
    try {
      final refreshToken = await TokenStorage.getRefreshToken();
      if (refreshToken == null) return false;

      final uri  = Uri.parse('$_base/auth/refresh');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        await TokenStorage.saveTokens(
          accessToken:  data['access_token']  as String,
          refreshToken: data['refresh_token'] as String,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }
}
