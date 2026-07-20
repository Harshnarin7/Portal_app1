// lib/widgets/theme_toggle_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ThemeNotifier>();
    final c        = AppTheme.of(context);
    final isDark   = notifier.isDark;

    return GestureDetector(
      onTap: notifier.toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 54,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color : isDark ? c.primary : c.primarySoft,
          border: Border.all(
            color: isDark ? c.primary.withOpacity(0.5) : c.border,
          ),
        ),
        child: Stack(
          children: [
            // Track icons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.light_mode_rounded,
                      size: 13,
                      color: isDark ? c.textTertiary : c.primary),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(Icons.dark_mode_rounded,
                      size: 13,
                      color: isDark ? Colors.white : c.textTertiary),
                ),
              ],
            ),
            // Sliding thumb
            AnimatedAlign(
              duration : const Duration(milliseconds: 280),
              curve    : Curves.easeInOut,
              alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
              child    : Container(
                width : 20,
                height: 20,
                decoration: BoxDecoration(
                  shape    : BoxShape.circle,
                  color    : isDark ? c.surface : c.primary,
                  boxShadow: [
                    BoxShadow(
                      color : Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size : 11,
                  color: isDark ? c.primary : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}