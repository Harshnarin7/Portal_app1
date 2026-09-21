import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/helper_session.dart';

/// Web-parity patient cards for Helpers 2 / 4 / 5 (no mother's name).
class HelperPatientHeader extends StatelessWidget {
  const HelperPatientHeader({
    super.key,
    required this.formBadge,
    required this.formName,
    required this.subtitle,
    required this.enrollmentId,
    required this.gestation,
    required this.babyUid,
    this.babyName,
    this.showBoCard = true,
    this.showMotherCard = false,
    this.motherName,
  });

  final String formBadge;
  final String formName;
  final String subtitle;
  final String enrollmentId;
  final String gestation;
  final String babyUid;
  final String? babyName;
  final bool showBoCard;
  final bool showMotherCard;
  final String? motherName;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final bo = formatBoBabyName(babyName);
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formBadge,
            style: TextStyle(
              color: c.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formName,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(color: c.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _card(c, '🪪', 'Enrolment ID', enrollmentId),
              _card(c, '🧬', 'Gestation', gestation),
              _card(c, '🏷️', 'Baby UID', babyUid),
              if (showBoCard) _card(c, '👶', 'B/O', bo),
              if (showMotherCard)
                _card(c, '👩', "Mother's Name", motherName ?? ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(AppColors c, String emoji, String label, String value) {
    final v = value.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.textTertiary)),
                  Text(
                    v.isEmpty ? '—' : v,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HelperDmsAutofillTag extends StatelessWidget {
  const HelperDmsAutofillTag({super.key, this.label = 'from DMS'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: c.primary,
        ),
      ),
    );
  }
}
