import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/helper_dob_day1.dart';
import 'modern_date_picker.dart';

/// DOB is the only editable date; Day 1 mirrors DOB; optional active-day label.
class HelperDobDay1Bar extends StatelessWidget {
  const HelperDobDay1Bar({
    super.key,
    required this.patientDob,
    required this.day1Date,
    required this.dobLocked,
    required this.onPickDob,
    this.activeDay,
    this.activeDayDate,
  });

  final DateTime? patientDob;
  final DateTime? day1Date;
  final bool dobLocked;
  final VoidCallback? onPickDob;
  final int? activeDay;
  final DateTime? activeDayDate;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final dobLabel = patientDob != null
        ? formatDisplayDate(patientDob!)
        : (day1Date != null ? formatDisplayDate(day1Date!) : 'Not set');
    final day1Label =
        day1Date != null ? formatDisplayDate(day1Date!) : '—';
    final activeLabel = activeDayDate != null
        ? formatDisplayDate(activeDayDate!)
        : '—';

    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Date of birth',
                style: TextStyle(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: dobLocked ? null : onPickDob,
                  child: Text(dobLabel),
                ),
              ),
              if (dobLocked)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.lock_outline,
                      size: 18, color: c.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Day 1 (auto): $day1Label',
                  style: TextStyle(color: c.textTertiary, fontSize: 12),
                ),
              ),
              if (activeDay != null)
                Expanded(
                  child: Text(
                    'Day $activeDay (auto): $activeLabel',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: c.textTertiary, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick DOB and return normalized local date (no time).
Future<DateTime?> pickHelperPatientDob(
  BuildContext context, {
  DateTime? initial,
}) async {
  final picked = await showModernDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 1)),
  );
  if (picked == null) return null;
  return DateTime(picked.year, picked.month, picked.day);
}

String helperDobToYmd(DateTime d) => formatIsoDateOnly(d);
