import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/helper_dob_day1.dart';

class HelperRecentDayStrip extends StatelessWidget {
  const HelperRecentDayStrip({
    super.key,
    required this.visibleDays,
    required this.activeDay,
    required this.todayNicuDay,
    required this.day1Date,
    required this.dayStatus,
    required this.onSelect,
    required this.onAddDay,
    this.dischargeDay,
    this.showAddDay = true,
    this.canShowEarlier = false,
    this.onShowEarlier,
    this.missedDays = const [],
  });

  final List<int> visibleDays;
  final int activeDay;
  final int todayNicuDay;
  final DateTime? day1Date;
  final Map<int, String> dayStatus;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddDay;
  final int? dischargeDay;
  final bool showAddDay;
  final bool canShowEarlier;
  final VoidCallback? onShowEarlier;
  final List<int> missedDays;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missedDays.isNotEmpty)
          Container(
            width: double.infinity,
            color: c.warning.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              'Missed days in this window: ${missedDays.map((d) => 'D$d').join(', ')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.warning,
              ),
            ),
          ),
        Container(
          color: c.surface,
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              if (canShowEarlier && onShowEarlier != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: const Text('Earlier'),
                    onPressed: onShowEarlier,
                  ),
                ),
              ...visibleDays.map((day) => _chip(c, day)),
              if (showAddDay)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ActionChip(
                    label: const Text('+ Day'),
                    onPressed: onAddDay,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(AppColors c, int day) {
    final selected = day == activeDay;
    final future = day1Date != null && day > todayNicuDay;
    final discharged = dischargeDay != null && day > dischargeDay!;
    final locked = future || discharged;
    final st = dayStatus[day] ?? 'empty';
    final cal = calendarDateForNicuDay(day1Date, day);
    final dateLabel = cal == null ? '' : '${cal.day} ${_month(cal.month)}';
    Color dot;
    switch (st) {
      case 'submitted':
        dot = c.success;
        break;
      case 'complete':
        dot = c.primary;
        break;
      case 'draft':
      case 'late':
        dot = c.warning;
        break;
      default:
        dot = c.border;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text('D$day',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12)),
                if (locked) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.lock, size: 12),
                ],
              ],
            ),
            if (dateLabel.isNotEmpty)
              Text(dateLabel,
                  style: TextStyle(fontSize: 9, color: c.textTertiary)),
          ],
        ),
        onSelected: locked ? null : (_) => onSelect(day),
      ),
    );
  }

  static String _month(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[m - 1];
  }
}
