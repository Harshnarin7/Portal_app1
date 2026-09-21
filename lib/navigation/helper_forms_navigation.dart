import 'package:flutter/material.dart';

import '../screens/helper_fio2_auc.dart';
import '../screens/helper_form2_resp_cv_neuro.dart';
import '../screens/helper_form3_infect_gi_hema.dart';
import '../screens/helper_form4_metab_renal_vasc_eye.dart';
import '../screens/helper_form5_minimal_monitoring.dart';

/// Shared patient context for all five NICU helper forms (same baby / enrollment).
class HelperFormPatientContext {
  final String enrollmentId;
  final String gestation;
  final String motherName;
  final String babyUid;
  final String site;
  final String screeningId;

  const HelperFormPatientContext({
    required this.enrollmentId,
    required this.gestation,
    required this.motherName,
    required this.babyUid,
    this.site = 'PGIMER',
    this.screeningId = '',
  });

  String get keySuffix {
    final sid = screeningId.trim();
    final eid = enrollmentId.trim();
    return sid.isNotEmpty ? '$eid-$sid' : eid;
  }
}

enum HelperFormKind {
  minimalMonitoring,
  respCvNeuro,
  fio2Auc,
  infectGiHema,
  metabRenalVascEye,
}

extension HelperFormKindMeta on HelperFormKind {
  int get number => switch (this) {
        HelperFormKind.minimalMonitoring => 1,
        HelperFormKind.respCvNeuro => 2,
        HelperFormKind.fio2Auc => 3,
        HelperFormKind.infectGiHema => 4,
        HelperFormKind.metabRenalVascEye => 5,
      };

  String get shortTitle => switch (this) {
        HelperFormKind.minimalMonitoring => 'Daily Monitoring Sheet',
        HelperFormKind.respCvNeuro => 'Resp / CV / Neuro',
        HelperFormKind.fio2Auc => 'FiO₂ Logging',
        HelperFormKind.infectGiHema => 'Infection / GI / Hema',
        HelperFormKind.metabRenalVascEye => 'Metab / Renal / Eye',
      };

  String get menuLabel => switch (this) {
        HelperFormKind.minimalMonitoring => 'Daily Monitoring Sheet (DMS)',
        _ => 'Helper $number — $shortTitle',
      };

  IconData get icon => switch (this) {
        HelperFormKind.respCvNeuro => Icons.favorite_rounded,
        HelperFormKind.fio2Auc => Icons.air_rounded,
        HelperFormKind.infectGiHema => Icons.bloodtype_rounded,
        HelperFormKind.metabRenalVascEye => Icons.visibility_rounded,
        HelperFormKind.minimalMonitoring => Icons.monitor_heart_outlined,
      };
}

Widget buildHelperFormScreen(
  HelperFormKind kind,
  HelperFormPatientContext ctx,
) {
  final eid = ctx.enrollmentId.trim();
  final k = ctx.keySuffix;
  switch (kind) {
    case HelperFormKind.respCvNeuro:
      return HelperForm2RespCvNeuro(
        key: ValueKey('rcn-$k'),
        enrollmentId: eid,
        gestation: ctx.gestation,
        motherName: ctx.motherName,
        babyUid: ctx.babyUid,
        site: ctx.site,
      );
    case HelperFormKind.fio2Auc:
      return HelperFiO2AUC(
        key: ValueKey('fio2-$k'),
        enrollmentId: eid,
        gestation: ctx.gestation,
        motherName: ctx.motherName,
        babyUid: ctx.babyUid,
      );
    case HelperFormKind.infectGiHema:
      return HelperForm3InfectGIHema(
        key: ValueKey('igh-$k'),
        enrollmentId: eid,
        gestation: ctx.gestation,
        motherName: ctx.motherName,
        babyUid: ctx.babyUid,
      );
    case HelperFormKind.metabRenalVascEye:
      return HelperForm4MetabRenalVascEye(
        key: ValueKey('mrve-$k'),
        enrollmentId: eid,
        gestation: ctx.gestation,
        motherName: ctx.motherName,
        babyUid: ctx.babyUid,
      );
    case HelperFormKind.minimalMonitoring:
      return HelperForm5MinimalMonitoring(
        key: ValueKey('mm-$k'),
        enrollmentId: eid,
        gestation: ctx.gestation,
        motherName: ctx.motherName,
        babyUid: ctx.babyUid,
      );
  }
}

void switchHelperForm(
  BuildContext context, {
  required HelperFormKind target,
  required HelperFormKind current,
  required HelperFormPatientContext patient,
}) {
  if (target == current) return;
  Navigator.pushReplacement(
    context,
    MaterialPageRoute<void>(
      builder: (_) => buildHelperFormScreen(target, patient),
    ),
  );
}

void showHelperFormSwitcherSheet(
  BuildContext context, {
  required HelperFormKind current,
  required HelperFormPatientContext patient,
}) {
  final c = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Switch helper form',
              style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (patient.enrollmentId.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                patient.enrollmentId.trim(),
                style: TextStyle(
                  color: c.onSurface.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ),
          ...HelperFormKind.values.map((kind) {
            final selected = kind == current;
            return ListTile(
              leading: Icon(
                kind.icon,
                color: selected ? c.primary : c.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                kind.menuLabel,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              trailing: selected
                  ? Icon(Icons.check_circle_rounded, color: c.primary, size: 22)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: selected
                  ? null
                  : () {
                      Navigator.pop(sheetCtx);
                      switchHelperForm(
                        context,
                        target: kind,
                        current: current,
                        patient: patient,
                      );
                    },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// App bar control — opens the helper 1–5 picker (replaces current route).
class HelperFormSwitcherButton extends StatelessWidget {
  const HelperFormSwitcherButton({
    super.key,
    required this.current,
    required this.patient,
  });

  final HelperFormKind current;
  final HelperFormPatientContext patient;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Switch helper form',
      icon: const Icon(Icons.swap_horiz_rounded),
      onPressed: () => showHelperFormSwitcherSheet(
        context,
        current: current,
        patient: patient,
      ),
    );
  }
}
