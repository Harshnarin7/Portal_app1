import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'navigation/route_observer.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/dashboards/admin_dashboard.dart';
import 'screens/dashboards/pi_dashboard.dart';
import 'screens/dashboards/scientist_dashboard.dart';
import 'screens/dashboards/nurse_dashboard.dart';
import 'screens/dashboards/deo_dashboard.dart';
import 'screens/dashboards/monitor_dashboard.dart';
import 'models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadSavedTheme();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>.value(value: themeNotifier),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: const PortalApp(),
    ),
  );
}

class PortalApp extends StatelessWidget {
  const PortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeNotifier>();
    return MaterialApp(
      navigatorObservers:         [routeObserver],
      title:                      'PORTAL CRF',
      debugShowCheckedModeBanner: false,
      theme:     AppTheme.lightThemeData(),
      darkTheme: AppTheme.darkThemeData(),
      themeMode: theme.mode,
      home:      const RootScreen(),
      routes: {
        '/login':           (_) => const LoginScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/change-password': (_) => const ChangePasswordScreen(),
      },
    );
  }
}

// ── RootScreen ───────────────────────────────────────────────────────────────
// Shows splash for 2.5 seconds, then hands off to AuthGate.
// Splash and auth load in parallel — whichever takes longer wins.

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    // Show splash for exactly 2.5 seconds, then reveal the real screen
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always show splash for first 2.5 seconds
    if (!_splashDone) return const SplashScreen();

    // After 2.5 seconds — hand off to AuthGate
    return const AuthGate();
  }
}

// ── AuthGate ─────────────────────────────────────────────────────────────────
// Pure reactive widget — watches AuthProvider and routes instantly.

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Auth still loading (should finish within 5 sec timeout in AuthProvider)
    if (auth.status == AuthStatus.unknown) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Not logged in
    if (auth.status == AuthStatus.unauthenticated) {
      return const LoginScreen();
    }

    // Force password change on first login
    if (auth.user?.mustChangePassword == true) {
      return const ChangePasswordScreen();
    }

    // Route to role dashboard
    return _dashboardForRole(auth.user!.role);
  }

  Widget _dashboardForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:     return const AdminDashboard();
      case UserRole.pi:        return const PIDashboard();
      case UserRole.scientist: return const ScientistDashboard();
      case UserRole.nurse:     return const NurseDashboard();
      case UserRole.deo:       return const DEODashboard();
      case UserRole.monitor:   return const MonitorDashboard();
    }
  }
}
