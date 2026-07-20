import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';
import '../services/api_client.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus   _status = AuthStatus.unknown;
  UserProfile? _user;
  String?      _error;
  bool         _loading = false;

  AuthStatus   get status  => _status;
  UserProfile? get user    => _user;
  String?      get error   => _error;
  bool         get loading => _loading;
  bool         get isAuth  => _status == AuthStatus.authenticated;

  Timer? _sessionTimer;
  static const _sessionTimeout = Duration(minutes: 30);

  AuthProvider() { _init(); }

  Future<void> _init() async {
    try {
      final hasToken = await TokenStorage.hasValidTokens();
      if (!hasToken) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }

      // Try to verify token with server
      final profile = await AuthService.instance
          .restoreSession()
          .timeout(const Duration(seconds: 6));

      if (profile != null) {
        _user   = profile;
        _status = AuthStatus.authenticated;
        _startSessionTimer();
      } else {
        // Token invalid — clear and go to login
        await TokenStorage.clearAll();
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      // On any error (timeout, network) — check for cached profile
      try {
        final cached = await TokenStorage.getProfile();
        if (cached != null) {
          _user   = UserProfile.fromJson(cached);
          _status = AuthStatus.authenticated;
          _startSessionTimer();
        } else {
          await TokenStorage.clearAll();
          _status = AuthStatus.unauthenticated;
        }
      } catch (_) {
        await TokenStorage.clearAll();
        _status = AuthStatus.unauthenticated;
      }
    }
    notifyListeners();
  }

  Future<bool> login({
    required String emailOrUsername,
    required String password,
  }) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final profile = await AuthService.instance.login(
        emailOrUsername: emailOrUsername,
        password:        password,
      );
      _user   = profile;
      _status = AuthStatus.authenticated;
      _error  = null;
      _loading = false;
      _startSessionTimer();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error   = e.message;
      _status  = AuthStatus.unauthenticated;
      _loading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _error   = 'Network error. Check your connection.';
      _status  = AuthStatus.unauthenticated;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _sessionTimer?.cancel();
    try { await AuthService.instance.logout(); } catch (_) {}
    await TokenStorage.clearAll();
    _user    = null;
    _status  = AuthStatus.unauthenticated;
    _error   = null;
    notifyListeners();
  }

  Future<String?> changePassword({
    required String current,
    required String newPw,
    required String confirm,
  }) async {
    try {
      await AuthService.instance.changePassword(
        currentPassword: current,
        newPassword:     newPw,
        confirmPassword: confirm,
      );
      if (_user != null) {
        _user = _user!.copyWith(mustChangePassword: false);
        notifyListeners();
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Network error. Try again.';
    }
  }

  void touchActivity() => _resetSessionTimer();
  void clearError() { _error = null; notifyListeners(); }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_sessionTimeout, logout);
  }

  void _resetSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_sessionTimeout, logout);
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
