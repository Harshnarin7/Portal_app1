// lib/screens/dashboards/_dashboard_shell.dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared scaffold used by every role dashboard.
// Provides: top bar with name/role/site, session timer, bottom nav, logout.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../profile_screen.dart';

/// Lets child pages switch the bottom-nav tab (e.g. Home → Patients).
class DashboardNavigator extends InheritedWidget {
  final int currentIndex;
  final void Function(int index) goToTab;

  const DashboardNavigator({
    super.key,
    required this.currentIndex,
    required this.goToTab,
    required super.child,
  });

  static DashboardNavigator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardNavigator>();

  static DashboardNavigator of(BuildContext context) {
    final nav = maybeOf(context);
    assert(nav != null, 'DashboardNavigator not found in context');
    return nav!;
  }

  @override
  bool updateShouldNotify(DashboardNavigator oldWidget) =>
      currentIndex != oldWidget.currentIndex;
}

class DashboardShell extends StatefulWidget {
  final UserProfile user;
  final List<Widget> pages;
  final List<BottomNavigationBarItem> navItems;
  final Widget? fab;
  /// Optional external tab index control (e.g. nurse Home → Patients).
  final ValueNotifier<int>? tabIndex;

  const DashboardShell({
    super.key,
    required this.user,
    required this.pages,
    required this.navItems,
    this.fab,
    this.tabIndex,
  });

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _idx = 0;

  // Session countdown (display only — actual timeout in AuthProvider)
  static const _sessionMinutes = 30;
  late int _secondsLeft;
  Timer? _countdownTimer;

  static const _primary  = Color(0xFF3B6FE0);
  static const _surface  = Color(0xFFFFFFFF);
  static const _border   = Color(0xFFD4DCF0);
  static const _text1    = Color(0xFF1A2340);
  static const _text2    = Color(0xFF4A5578);
  static const _text3    = Color(0xFF8A95B0);
  static const _danger   = Color(0xFFE53935);
  static const _warning  = Color(0xFFF59E0B);
  static const _bg       = Color(0xFFEFF3FB);

  @override
  void initState() {
    super.initState();
    _secondsLeft = _sessionMinutes * 60;
    _startCountdown();
    widget.tabIndex?.addListener(_onExternalTab);
    if (widget.tabIndex != null) {
      _idx = widget.tabIndex!.value.clamp(0, widget.pages.length - 1);
    }
  }

  void _onExternalTab() {
    final next = widget.tabIndex?.value;
    if (next == null || !mounted) return;
    final clamped = next.clamp(0, widget.pages.length - 1);
    if (clamped != _idx) setState(() => _idx = clamped);
  }

  void _goToTab(int index) {
    final clamped = index.clamp(0, widget.pages.length - 1);
    if (widget.tabIndex != null) {
      widget.tabIndex!.value = clamped;
    }
    if (clamped != _idx) setState(() => _idx = clamped);
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
          context.read<AuthProvider>().touchActivity(); // reset real timer on activity
        }
      });
    });
  }

  @override
  void dispose() {
    widget.tabIndex?.removeListener(_onExternalTab);
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _timeLeft {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor =>
      _secondsLeft < 300 ? _danger : (_secondsLeft < 600 ? _warning : _text3);

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Logout',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: _text3, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout',
                style: TextStyle(color: _danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashboardNavigator(
      currentIndex: _idx,
      goToTab: _goToTab,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        body: IndexedStack(index: _idx, children: widget.pages),
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButton: widget.fab,
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      toolbarHeight: 60,
      automaticallyImplyLeading: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
      // User name + role in title
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.user.fullName,
              style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: _text1),
              overflow: TextOverflow.ellipsis),
          Row(children: [
            _roleBadge(widget.user.role),
            if (widget.user.siteName != null) ...[
              const SizedBox(width: 5),
              Flexible(child: Text('· ${widget.user.siteName}',
                  style: const TextStyle(fontSize: 10, color: _text3),
                  overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ],
      ),
      // Actions: timer + profile avatar + logout
      actions: [
        // Session timer
        Center(child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _timerColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _timerColor.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined, color: _timerColor, size: 12),
            const SizedBox(width: 3),
            Text(_timeLeft, style: TextStyle(fontSize: 11,
                color: _timerColor, fontWeight: FontWeight.w700)),
          ]),
        )),
        // Profile avatar button — reliable IconButton tap area
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            tooltip: 'My Profile',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ProfileScreen())),
            icon: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primary, Color(0xFF2554C7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(widget.user.initials,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 13))),
            ),
          ),
        ),
        // Logout button
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _danger.withOpacity(0.2)),
              ),
              child: const Icon(Icons.logout_rounded, color: _danger, size: 17),
            ),
          ),
        ),
      ],
    );
  }

  BottomNavigationBar _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _idx,
      onTap: _goToTab,
      backgroundColor: _surface,
      selectedItemColor: _primary,
      unselectedItemColor: _text3,
      selectedLabelStyle: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      items: widget.navItems,
    );
  }

  Widget _roleBadge(UserRole role) {
    final colours = {
      UserRole.admin:     (const Color(0xFF0C447C), const Color(0xFFE6F1FB)),
      UserRole.pi:        (const Color(0xFF085041), const Color(0xFFE1F5EE)),
      UserRole.scientist: (const Color(0xFF3C3489), const Color(0xFFEEEDFE)),
      UserRole.nurse:     (const Color(0xFF633806), const Color(0xFFFAEEDA)),
      UserRole.deo:       (const Color(0xFF712B13), const Color(0xFFFAECE7)),
      UserRole.monitor:   (const Color(0xFF444441), const Color(0xFFF1EFE8)),
    };
    final (fg, bg) = colours[role] ?? (const Color(0xFF444441), const Color(0xFFF1EFE8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(role.displayName,
          style: TextStyle(fontSize: 9, color: fg, fontWeight: FontWeight.w700)),
    );
  }
}
