// lib/screens/dashboards/nurse_dashboard.dart — CLEAN REWRITE
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/crf.dart';
import '../../models/form_b.dart';
import '../../models/form_c.dart';
import '../../models/birth_resuscitation.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/pdf_service.dart';
import '../../services/screening_api_service.dart';
import '../../services/forms_api_service.dart';
import '../admin/user_management_screen.dart';
import '../screening_form.dart';
import '../form_b_birth_resuscitation.dart';
import '../form_c_resuscitation.dart';
import '../helper_form2_resp_cv_neuro.dart';
import '../helper_form3_infect_gi_hema.dart';
import '../helper_form4_metab_renal_vasc_eye.dart';
import '../helper_fio2_auc.dart';
import '_dashboard_shell.dart';
import '../../navigation/route_observer.dart';

const _kPrimary = Color(0xFF3B6FE0);
const _kPrimaryDark = Color(0xFF2C56C4);
const _kSurface = Color(0xFFFFFFFF);
const _kBg      = Color(0xFFEFF3FB);
const _kBorder  = Color(0xFFD4DCF0);
const _kText1   = Color(0xFF1A2340);
const _kText3   = Color(0xFF8A95B0);
const _kSuccess = Color(0xFF0F9D58);
const _kWarning = Color(0xFFF59E0B);
const _kDanger  = Color(0xFFE53935);

// ── ADMIN DASHBOARD ──────────────────────────────────────────────────────────
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(
      user: user,
      pages: [_AdminHome(user: user), _UserMgmtPage(user: user),
              _ph('Sites'), _ph('Audit')],
      navItems: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people_rounded), label: 'Users'),
        BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined),
            activeIcon: Icon(Icons.location_on_rounded), label: 'Sites'),
        BottomNavigationBarItem(icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history_rounded), label: 'Audit'),
      ],
    );
  }
}

class _AdminHome extends StatefulWidget {
  final UserProfile user;
  const _AdminHome({required this.user});
  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  int _screened = 0, _enrolled = 0;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final s = await ScreeningApiService.instance.getStats();
      if (mounted) setState(() {
        _screened = s['total'] ?? 0; _enrolled = s['enrolled'] ?? 0;
      });
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16,16,16,32),
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF0B1829),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PORTAL Administration',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 3),
              Text(widget.user.fullName, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal:8, vertical:3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Super Admin · All Sites',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
              ),
            ])),
          const Icon(Icons.shield_rounded, color: _kPrimary, size: 40),
        ]),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 2.2,
        children: [
          ('6','Active Sites',_kPrimary),('41','Total Users',_kSuccess),
          ('$_screened','Screened',const Color(0xFF7C3AED)),
          ('$_enrolled','Enrolled',_kWarning),
        ].map((it) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (it.$3 as Color).withOpacity(0.2))),
          child: Row(children: [
            Text(it.$1 as String, style: TextStyle(fontSize:24,
                fontWeight:FontWeight.w800, color: it.$3 as Color)),
            const SizedBox(width:8),
            Text(it.$2 as String, style: const TextStyle(
                fontSize:11, color:_kText3, height:1.3)),
          ]),
        )).toList(),
      ),
      const SizedBox(height: 14),
      const Text('System actions', style: TextStyle(fontSize:13,
          fontWeight:FontWeight.w700, color:_kText1)),
      const SizedBox(height: 8),
      for (final item in [
        (Icons.person_add_rounded,'Create new user','Add PI, Scientist, Nurse or DEO',_kPrimary),
        (Icons.domain_add_rounded,'Add new site','Register a trial centre',_kSuccess),
        (Icons.lock_reset_rounded,'Reset user password','Admin-initiated password reset',_kWarning),
        (Icons.history_rounded,'View audit log','Full action history',const Color(0xFF7C3AED)),
      ])
        GestureDetector(
          onTap: () { if (item.$2 == 'Create new user') Navigator.push(context,
              MaterialPageRoute(builder:(_)=>const UserManagementScreen())); },
          child: Container(
            margin: const EdgeInsets.only(bottom:8),
            padding: const EdgeInsets.symmetric(horizontal:12, vertical:11),
            decoration: BoxDecoration(color:_kSurface,
                borderRadius:BorderRadius.circular(12),
                border:Border.all(color:_kBorder)),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color:(item.$4 as Color).withOpacity(0.1),
                    borderRadius:BorderRadius.circular(9)),
                child: Icon(item.$1 as IconData, color:item.$4 as Color, size:18)),
              const SizedBox(width:12),
              Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,
                children: [
                  Text(item.$2 as String, style: const TextStyle(
                      fontWeight:FontWeight.w700, fontSize:12, color:_kText1)),
                  Text(item.$3 as String, style: const TextStyle(
                      fontSize:10, color:_kText3)),
                ])),
              Icon(Icons.chevron_right_rounded,
                  color:_kText3.withOpacity(0.6), size:18),
            ]),
          ),
        ),
    ],
  );
}

class _UserMgmtPage extends StatelessWidget {
  final UserProfile user;
  const _UserMgmtPage({required this.user});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.people_rounded, size:56, color:_kPrimary),
    const SizedBox(height:14),
    const Text('User Management', style:TextStyle(fontSize:18,
        fontWeight:FontWeight.w700, color:_kText1)),
    const SizedBox(height:6),
    const Text('Create, edit and manage all system users',
        style:TextStyle(fontSize:12, color:_kText3)),
    const SizedBox(height:24),
    ElevatedButton.icon(
      onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder:(_)=>const UserManagementScreen())),
      icon: const Icon(Icons.open_in_new_rounded, size:18),
      label: const Text('Open User Management',
          style:TextStyle(fontWeight:FontWeight.w700)),
      style: ElevatedButton.styleFrom(backgroundColor:_kPrimary,
          foregroundColor:Colors.white,
          padding:const EdgeInsets.symmetric(horizontal:24, vertical:14),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
    ),
  ]));
}

// ── NURSE DASHBOARD ──────────────────────────────────────────────────────────
class NurseDashboard extends StatefulWidget {
  const NurseDashboard({super.key});
  @override
  State<NurseDashboard> createState() => _NurseDashboardState();
}

class _NurseDashboardState extends State<NurseDashboard> {
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  final ValueNotifier<String> _patientFilter = ValueNotifier<String>('All');

  @override
  void dispose() {
    _tabIndex.dispose();
    _patientFilter.dispose();
    super.dispose();
  }

  void _openPatients({String filter = 'All'}) {
    _patientFilter.value = filter;
    _tabIndex.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(
      user: user,
      tabIndex: _tabIndex,
      pages: [
        _NurseHome(user: user, onOpenPatients: _openPatients),
        _NursePatientsPage(user: user, filterNotifier: _patientFilter),
      ],
      navItems: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded),
            activeIcon: Icon(Icons.people_rounded), label: 'Patients'),
      ],
      fab: Builder(builder: (ctx) => FloatingActionButton.extended(
        backgroundColor: _kPrimary, foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded, size:20),
        label: const Text('New Screening',
            style:TextStyle(fontWeight:FontWeight.w700, fontSize:13)),
        onPressed: () => Navigator.push(ctx, MaterialPageRoute(
            builder:(_)=>const ScreeningForm(loadDraft:false))),
      )),
    );
  }
}

class _NurseHome extends StatefulWidget {
  final UserProfile user;
  final void Function({String filter}) onOpenPatients;
  const _NurseHome({required this.user, required this.onOpenPatients});
  @override
  State<_NurseHome> createState() => _NurseHomeState();
}

// ── Shared: fetch all patients (site-scoped) with PII merged in ────────────
// Used by both the nurse Home tab (top-5 preview) and the full Patients tab,
// so both screens always show identical, correctly-merged data instead of
// two copies of this logic drifting apart.
//
// `piiLimit`: PII is fetched in batch for display names. When set, only the
// first `piiLimit` patients get PII — API returns newest-first
// (`created_at.desc`), so that is the latest N shown on Home / pickers.
// Pass null to fetch PII for everyone (Patients tab search-by-name).
Future<List<CRF>> fetchPatientCrfs({int? piiLimit}) async {
  try {
    // Same site-scoped list webforms uses — raise limit so AWS patients
    // created on web appear here (and vice versa). Newest first from API.
    final patients = await ScreeningApiService.instance.getPatients(limit: 200);

    // Newest-first: PII for the first N rows (the ones actually shown).
    final piiCount = piiLimit == null
        ? patients.length
        : piiLimit.clamp(0, patients.length);
    final piiIds = <String>[];
    for (var i = 0; i < piiCount; i++) {
      final sid = patients[i]['screening_id']?.toString() ?? '';
      if (sid.isNotEmpty) piiIds.add(sid);
    }

    Map<String, Map<String, dynamic>> piiById = {};
    if (piiIds.isNotEmpty) {
      try {
        // One round-trip instead of N × GET /pii/screening/{id}
        piiById = await ScreeningApiService.instance.getPiiBatch(piiIds);
      } catch (_) {
        // Fallback for older backends without /pii/batch
        final pairs = await Future.wait(piiIds.map((sid) async {
          try {
            final pii = await ScreeningApiService.instance.getPii(sid);
            return MapEntry(sid, pii ?? const <String, dynamic>{});
          } catch (_) {
            return MapEntry(sid, const <String, dynamic>{});
          }
        }));
        piiById = {
          for (final e in pairs)
            if (e.value.isNotEmpty) e.key: e.value,
        };
      }
    }

    return List.generate(patients.length, (i) {
      final p = patients[i];
      final sid = p['screening_id']?.toString() ?? '';
      final pii = (i < piiCount && sid.isNotEmpty)
          ? (piiById[sid] ?? const <String, dynamic>{})
          : const <String, dynamic>{};
      final mapped = {
        "identification": {
          'screeningId'       : p['screening_id'] ?? '',
          'site'              : p['site_name'] ?? '',
          'siteId'            : p['site_id'] ?? '',
          'screeningDateTime' : p['screening_datetime'] ?? '',
          'screenedBy'        : p['screened_by'] ?? '',
        },
        "maternal": {
          'motherFirstName' : pii['mother_first_name'] ?? p['mother_first_name'] ?? '',
          'motherSurname'   : pii['mother_surname'] ?? p['mother_surname'] ?? '',
          'husbandFirstName': pii['husband_first_name'] ?? p['husband_first_name'] ?? '',
          'husbandSurname'  : pii['husband_surname'] ?? p['husband_surname'] ?? '',
          'motherPhone'     : pii['mother_contact'] ?? pii['mother_phone'] ??
              p['mother_contact'] ?? p['mother_phone'] ?? '',
          'husbandPhone'    : pii['husband_contact'] ?? pii['husband_phone'] ??
              p['husband_contact'] ?? p['husband_phone'] ?? '',
          'maternalUid'     : pii['maternal_uid'] ?? p['maternal_uid'] ?? '',
          'hospitalNo'      : pii['hospital_admission_number'] ?? pii['hospital_no'] ??
              p['hospital_admission_number'] ?? p['hospital_no'] ?? '',
        },
        "gestation": {
          'weeks'                : p['gestation_weeks'] ?? 0,
          'days'                 : p['gestation_days'] ?? 0,
          'method'               : p['gestation_method'] ?? '',
          'expectedDeliveryDate' : p['expected_delivery_date'] ?? '',
          'gestationKnownInWeeks': p['gestation_weeks'] != null,
          'eddKnown'             : p['expected_delivery_date'] != null,
        },
        "exclusion": {
          'present'       : p['exclusion_present'] ?? false,
          'reason'        : p['exclusion_reasons'] ?? '',
          'anomalyDetails': p['major_structural_anomalies_if_yes'] ?? '',
        },
        "finalDecision": {
          'eligibilityStatus'        : p['screening_status'] ?? '',
          'consentStatus'            : p['consent_given'] ?? '',
          'consentRefusalReason'     : p['reason_for_consent_refusal'] ?? '',
          'relationshipToParticipant': p['relationship_to_participant'] ?? '',
          'relationshipOther'        : p['relationship_other'] ?? '',
          'consentTakenBy'           : p['consent_taken_by'] ?? '',
        },
        'enrollmentId': p['enrollment_id'] ?? '',
      };
      return CRF.fromJson(mapped);
    });
  } catch (_) {
    // Only use device cache when the server is unreachable — never prefer
    // local-only data over a successful empty site list (that hid AWS /
    // webform patients).
    return ApiService().loadAllCRFs();
  }
}

// ── Shared patient status helpers ───────────────────────────────────────────
// Mirrors backend/main.py's compute_screening_status() exactly:
//   Screen Failure -> failed gestation/exclusion criteria (genuinely excluded)
//   Eligible       -> passed criteria AND consent_given == "Yes" (enrolled)
//   Not Eligible   -> passed criteria but consent isn't "Yes" YET (pending/
//                     not-approached) — this is NOT the same as excluded!
// FIX: previously any status other than "Eligible" (including "Not Eligible",
// which really just means "not confirmed enrolled yet") was shown as red
// "Excluded" — so a clinically-eligible patient whose consent was still
// pending showed up as wrongly excluded. Now only a real Screen Failure or
// an explicit consent refusal ("No") counts as Excluded; anything else that
// isn't yet Enrolled shows as "Incomplete" (pending), matching what the
// backend is actually telling us.
bool _isEnrolled(CRF c) => c.eligibilityStatus == 'Eligible';
bool _isExcluded(CRF c) =>
    c.eligibilityStatus == 'Screen Failure' || c.consentStatus == 'No';
Color patientStatusColor(CRF c) =>
    _isEnrolled(c) ? _kSuccess : (_isExcluded(c) ? _kDanger : _kWarning);
String patientStatusLabel(CRF c) =>
    _isEnrolled(c) ? 'Enrolled' : (_isExcluded(c) ? 'Excluded' : 'Incomplete');

// ── Shared patient card widget — used by both the Home tab preview and the
// full Patients tab so a patient looks and behaves identically everywhere.
Widget buildPatientCard(CRF c, VoidCallback onTap) {
  final col = patientStatusColor(c);
  final label = patientStatusLabel(c);
  final fullName = '${c.motherFirstName} ${c.motherSurname}'.trim();
  final hasName = fullName.isNotEmpty;
  return Container(
    margin:const EdgeInsets.only(bottom:9),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(16),
        boxShadow:[BoxShadow(color:_kText1.withOpacity(0.06),
            blurRadius:12, offset:const Offset(0,4))]),
    child: Material(color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children:[
            Container(width:42,height:42,
              decoration:BoxDecoration(
                  gradient: LinearGradient(
                    colors: [col.withOpacity(0.85), col],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius:BorderRadius.circular(12),
                  boxShadow:[BoxShadow(color:col.withOpacity(0.3),
                      blurRadius:6, offset:const Offset(0,2))]),
              child:Center(child:Text(
                hasName ? fullName[0].toUpperCase() : '?',
                style:const TextStyle(color:Colors.white,
                    fontWeight:FontWeight.w800,fontSize:17)))),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(hasName ? fullName : 'Name pending',
                    style: TextStyle(
                        color: hasName ? _kText1 : _kText3,
                        fontWeight: FontWeight.w700,
                        fontStyle: hasName ? FontStyle.normal : FontStyle.italic,
                        fontSize:13)),
                const SizedBox(height:3),
                Text('${c.screeningId} · ${c.gestationWeeks}w ${c.gestationDays}d',
                    style:const TextStyle(color:_kText3,fontSize:10.5,
                        fontWeight:FontWeight.w500)),
              ])),
            const SizedBox(width:8),
            Container(
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
              decoration:BoxDecoration(color:col.withOpacity(0.12),
                  borderRadius:BorderRadius.circular(7)),
              child:Text(label,
                  style:TextStyle(color:col,fontSize:10.5,fontWeight:FontWeight.w700))),
            const SizedBox(width:4),
            Icon(Icons.chevron_right_rounded, color:_kText3.withOpacity(0.6), size:19),
          ]),
        ),
      ),
    ),
  );
}

// ── Shared patient actions menu.
// Gate: until Form B is saved → only Form B open.
// After Form B (PPV required + randomised) → only Form C open.
// After Form C saved → helper forms unlock; Form B/C remain viewable.
Future<void> showPatientActionsSheet(BuildContext context, CRF c) async {
  final api = ApiService();
  final formB = await api.loadFormB(c.screeningId);
  final formC = await api.loadFormC(c.screeningId);

  final formBDone = formB != null;
  final formCDone = formC != null;
  final needsFormC = formBDone &&
      formB!.requiredResuscitation == true &&
      formB.randomized == true;
  final hasEnrollment = c.enrollmentId.isNotEmpty ||
      (formB?.enrollmentId.isNotEmpty == true);

  // Until Form C is the required next step, Form B stays available.
  // While Form C is pending, only Form C is open.
  final formBOpen = !(needsFormC && !formCDone);
  final formCOpen = needsFormC;
  final helpersEnabled = formCDone && hasEnrollment;

  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: _kSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(
                '${c.motherFirstName} ${c.motherSurname}'.trim().isEmpty
                    ? c.screeningId : '${c.motherFirstName} ${c.motherSurname}',
                style: const TextStyle(color: _kText1, fontWeight: FontWeight.w800, fontSize: 15))),
              Text(c.screeningId, style: const TextStyle(color: _kText3, fontSize: 11)),
            ]),
          ),
          const Divider(height: 20),
          _buildActionTile(ctx, 'Export PDF', Icons.picture_as_pdf_rounded, true,
            () => exportPatientPdf(context, c)),
          _buildActionTile(
            ctx,
            'View filled forms',
            Icons.visibility_rounded,
            formBDone || formCDone,
            () => showFilledFormsSheet(context, c, formB: formB, formC: formC),
          ),
          _buildActionTile(
            ctx,
            formBDone
                ? 'Form B — Birth & Resuscitation ✓'
                : 'Form B — Birth & Resuscitation',
            Icons.child_care_rounded,
            formBOpen,
            () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => FormBBirthResuscitation(
                  screeningId: c.screeningId,
                  maternalUid: c.maternalUid,
                  motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  motherPhone: c.motherPhone,
                  husbandPhone: c.husbandPhone,
                  gestWeeks: c.gestationWeeks,
                  gestDays: c.gestationDays,
                  siteId: c.siteId,
                )))),
          _buildActionTile(
            ctx,
            formCDone
                ? 'Form C — Resuscitation Details ✓'
                : 'Form C — Resuscitation Details',
            Icons.monitor_heart_rounded,
            formCOpen,
            () async {
              BirthResuscitationData? shared;
              final eid = formB?.enrollmentId.trim() ?? '';
              if (eid.isNotEmpty) {
                try {
                  final remote = await FormsApiService.instance
                      .loadBirthResuscitation(eid);
                  if (remote != null) {
                    shared = BirthResuscitationData.fromJson(remote);
                  }
                } catch (_) {}
              }
              if (!context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => FormCResuscitationDetails(
                    screeningId: c.screeningId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                    babyUid: formB?.babyUid.isNotEmpty == true
                        ? formB!.babyUid
                        : c.maternalUid,
                    formB: formB,
                    shared: shared,
                  )));
            }),
          _buildActionTile(ctx, 'Helper Form 2 — Resp/CV/Neuro', Icons.favorite_rounded, helpersEnabled,
            () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm2RespCvNeuro(
                  enrollmentId: c.enrollmentId.isNotEmpty
                      ? c.enrollmentId
                      : (formB?.enrollmentId ?? ''),
                  gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                  motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  babyUid: formB?.babyUid.isNotEmpty == true
                      ? formB!.babyUid
                      : c.maternalUid,
                  site: c.site.isNotEmpty ? c.site : 'PGIMER',
                )))),
          _buildActionTile(ctx, 'Helper Form 3 — Infection/GI/Hema', Icons.bloodtype_rounded, helpersEnabled,
            () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm3InfectGIHema(
                  enrollmentId: c.enrollmentId.isNotEmpty
                      ? c.enrollmentId
                      : (formB?.enrollmentId ?? ''),
                  gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                  motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  babyUid: formB?.babyUid.isNotEmpty == true
                      ? formB!.babyUid
                      : c.maternalUid,
                )))),
          _buildActionTile(ctx, 'Helper Form 4 — Metab/Renal/Vasc/Eye', Icons.visibility_rounded, helpersEnabled,
            () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm4MetabRenalVascEye(
                  enrollmentId: c.enrollmentId.isNotEmpty
                      ? c.enrollmentId
                      : (formB?.enrollmentId ?? ''),
                  gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                  motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  babyUid: formB?.babyUid.isNotEmpty == true
                      ? formB!.babyUid
                      : c.maternalUid,
                )))),
          _buildActionTile(ctx, 'Helper Form — FiO2 / AUC', Icons.air_rounded, helpersEnabled,
            () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperFiO2AUC(
                  enrollmentId: c.enrollmentId.isNotEmpty
                      ? c.enrollmentId
                      : (formB?.enrollmentId ?? ''),
                  gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                  motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  babyUid: formB?.babyUid.isNotEmpty == true
                      ? formB!.babyUid
                      : c.maternalUid,
                )))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              !formBDone
                  ? 'Complete Form B first — other forms stay locked.'
                  : (needsFormC && !formCDone)
                      ? 'Form B saved — open Form C next. Other forms stay locked until Form C is submitted.'
                      : formCDone
                          ? 'Form C submitted — helper forms are unlocked.'
                          : 'Form B complete — no Form C required for this case.',
              style: const TextStyle(color: _kText3, fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

Widget _buildActionTile(BuildContext ctx, String label, IconData icon, bool enabled, VoidCallback onTap) {
  return ListTile(
    enabled: enabled,
    leading: Icon(icon, color: enabled ? _kPrimary : _kText3),
    title: Text(label, style: TextStyle(
        color: enabled ? _kText1 : _kText3, fontWeight: FontWeight.w600, fontSize: 13)),
    trailing: Icon(Icons.chevron_right_rounded, color: enabled ? _kText3 : _kText3.withOpacity(0.4)),
    onTap: enabled ? () { Navigator.pop(ctx); onTap(); } : null,
  );
}

/// Lists previously saved forms and opens them in read-only mode.
Future<void> showFilledFormsSheet(
  BuildContext context,
  CRF c, {
  FormB? formB,
  FormC? formC,
}) async {
  final formBDone = formB != null;
  final formCDone = formC != null;
  if (!formBDone && !formCDone) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No filled forms yet for this patient.')),
    );
    return;
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: _kSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Previously filled forms',
                  style: TextStyle(
                      color: _kText1, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          const Divider(height: 20),
          if (formBDone)
            ListTile(
              leading: const Icon(Icons.child_care_rounded, color: _kPrimary),
              title: const Text('Form B — Birth & Resuscitation',
                  style: TextStyle(
                      color: _kText1, fontWeight: FontWeight.w600, fontSize: 13)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FormBBirthResuscitation(
                        screeningId: c.screeningId,
                        maternalUid: c.maternalUid,
                        motherName:
                            '${c.motherFirstName} ${c.motherSurname}'.trim(),
                        motherPhone: c.motherPhone,
                        husbandPhone: c.husbandPhone,
                        gestWeeks: c.gestationWeeks,
                        gestDays: c.gestationDays,
                        siteId: c.siteId,
                        viewOnly: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          if (formCDone)
            ListTile(
              leading: const Icon(Icons.monitor_heart_rounded, color: _kPrimary),
              title: const Text('Form C — Resuscitation Details',
                  style: TextStyle(
                      color: _kText1, fontWeight: FontWeight.w600, fontSize: 13)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FormCResuscitationDetails(
                        screeningId: c.screeningId,
                        gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                        motherName:
                            '${c.motherFirstName} ${c.motherSurname}'.trim(),
                        babyUid: formB?.babyUid.isNotEmpty == true
                            ? formB!.babyUid
                            : c.maternalUid,
                        formB: formB,
                        viewOnly: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

Future<void> exportPatientPdf(BuildContext context, CRF c) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
  );
  try {
    final api = ApiService();
    final formB = await api.loadFormB(c.screeningId);
    final formC = await api.loadFormC(c.screeningId);
    final File file = (formB != null && formC != null)
        ? await PdfService.generateFullTrialPdf(crf: c, formB: formB, formC: formC)
        : await PdfService.generateCrfPdf(c);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await OpenFilex.open(file.path);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF error: $e'), backgroundColor: _kDanger),
      );
    }
  }
}

// ── NURSE: full "Patients" tab — every patient at this site, searchable and
// filterable, with the same actions menu available from the Home tab.
class _NursePatientsPage extends StatefulWidget {
  final UserProfile user;
  final ValueNotifier<String>? filterNotifier;
  const _NursePatientsPage({required this.user, this.filterNotifier});
  @override
  State<_NursePatientsPage> createState() => _NursePatientsPageState();
}

class _NursePatientsPageState extends State<_NursePatientsPage> with RouteAware {
  List<CRF> _all = [];
  bool _loading = true;
  String _query = '';
  String _filter = 'All'; // All / Enrolled / Excluded / Incomplete

  @override void initState() {
    super.initState();
    _filter = widget.filterNotifier?.value ?? 'All';
    widget.filterNotifier?.addListener(_onExternalFilter);
    _load();
  }
  void _onExternalFilter() {
    final next = widget.filterNotifier?.value ?? 'All';
    if (next != _filter && mounted) setState(() => _filter = next);
  }
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }
  @override void dispose() {
    widget.filterNotifier?.removeListener(_onExternalFilter);
    routeObserver.unsubscribe(this);
    super.dispose();
  }
  @override void didPopNext() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final crfs = await fetchPatientCrfs();
    if (!mounted) return;
    setState(() { _all = crfs; _loading = false; });
  }

  List<CRF> get _filtered {
    return _all.where((c) {
      final matchesFilter = switch (_filter) {
        'Enrolled'   => _isEnrolled(c),
        'Excluded'   => _isExcluded(c),
        'Incomplete' => !_isEnrolled(c) && !_isExcluded(c),
        _            => true,
      };
      if (!matchesFilter) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      final name = '${c.motherFirstName} ${c.motherSurname}'.toLowerCase();
      return name.contains(q) || c.screeningId.toLowerCase().contains(q);
    }).toList();
  }

  Widget _chip(String label, Color color) {
    final selected = _filter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w700,
            color: selected ? Colors.white : color)),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = label);
          widget.filterNotifier?.value = label;
        },
        selectedColor: color,
        backgroundColor: color.withOpacity(0.10),
        side: BorderSide(color: color.withOpacity(selected ? 0 : 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16,16,16,100),
          children: [
            Text('All patients', style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: _kText1)),
            const SizedBox(height: 3),
            Text('${_all.length} total · site-scoped', style: const TextStyle(
                fontSize: 11.5, color: _kText3)),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: _kSurface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: _kText1.withOpacity(0.05),
                      blurRadius: 8, offset: const Offset(0,3))]),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13, color: _kText1),
                decoration: InputDecoration(
                  hintText: 'Search by name or screening ID',
                  hintStyle: const TextStyle(fontSize: 12.5, color: _kText3),
                  prefixIcon: const Icon(Icons.search_rounded, color: _kText3, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('All', _kPrimary),
                _chip('Enrolled', _kSuccess),
                _chip('Excluded', _kDanger),
                _chip('Incomplete', _kWarning),
              ]),
            ),
            const SizedBox(height: 16),
            if (_loading) const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator(color: _kPrimary)))
            else if (results.isEmpty) Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: _kSurface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: _kText1.withOpacity(0.05),
                      blurRadius: 10, offset: const Offset(0,4))]),
              child: Column(children: [
                Container(width:56, height:56,
                  decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.search_off_rounded, size: 26, color: _kPrimary)),
                const SizedBox(height: 12),
                Text(_all.isEmpty ? 'No patients screened yet' : 'No matches',
                    style: const TextStyle(color: _kText1, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_all.isEmpty
                        ? 'New screenings will show up here'
                        : 'Try a different search or filter',
                    style: const TextStyle(color: _kText3, fontSize: 11)),
              ]),
            )
            else ...results.map((c) => buildPatientCard(c, () => showPatientActionsSheet(context, c))),
          ],
      ),
    );
  }
}

class _NurseHomeState extends State<_NurseHome> with RouteAware {
  List<CRF> _crfs = [];
  List<Map<String,dynamic>> _drafts = [];
  bool _loading = true;
  int _total=0, _enrolled2=0, _excluded2=0;

  @override void initState() { super.initState(); _load(); }
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }
  @override void dispose() { routeObserver.unsubscribe(this); super.dispose(); }
  @override void didPopNext() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);

    // ── Load drafts from local SharedPreferences ───────────────────────
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getStringList('screening_draft_keys') ?? [];

    // Screening IDs already on the server (web + mobile share this list).
    // Used to drop stale local drafts for cases that are already complete online.
    Set<String> serverIds = {};
    try {
      final patients = await ScreeningApiService.instance.getPatients(limit: 200);
      serverIds = patients
          .map((p) => p['screening_id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {}

    final drafts = <Map<String,dynamic>>[];
    final vkeys  = <String>[];
    for (final k in keys) {
      final raw = prefs.getString(k); if (raw==null) continue;
      final d = jsonDecode(raw) as Map<String,dynamic>;
      final sid = d['screeningId'] as String? ?? '';
      final consent = (d['consentStatus'] ?? '').toString().trim();
      final consentDone = consent.isNotEmpty && consent != 'Select';
      final onServer = sid.isNotEmpty && serverIds.contains(sid);
      // Same case already perfect on web → don't keep a ghost "Draft" card.
      if (onServer && consentDone) {
        await prefs.remove(k);
        continue;
      }
      vkeys.add(k);
      drafts.add({'key':k,'screeningId':sid.isEmpty?'Draft':sid,
          'motherName':'${d['motherFirstName']??d['motherFirst']??''} ${d['motherSurname']??''}'});
    }
    await prefs.setStringList('screening_draft_keys', vkeys);

    // ── Load patients from BACKEND (site-isolated), PII merged in ──────
    // Home only ever shows the 5 most recent patients — API is newest-first,
    // so piiLimit: 5 loads names for the top of the list.
    final crfs = await fetchPatientCrfs(piiLimit: 5);

    if (!mounted) return;
    setState(() { _crfs=crfs; _drafts=drafts; _loading=false; });

    // ── Load stats from backend ────────────────────────────────────────
    try {
      final s = await ScreeningApiService.instance.getStats();
      if (mounted) setState(() {
        _total    = s['total']    ?? _crfs.length;
        _enrolled2= s['enrolled'] ?? 0;
        _excluded2= s['excluded'] ?? 0;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final enrolled = _crfs.where(_isEnrolled).length;
    final excluded = _crfs.where(_isExcluded).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,100),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPrimary, _kPrimaryDark],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                color: _kPrimary.withOpacity(0.28),
                blurRadius: 18, offset: const Offset(0, 8),
              )],
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,
                children: [
                  Text('Good ${_g()},', style:const TextStyle(
                      color:Colors.white70, fontSize:12, fontWeight:FontWeight.w500)),
                  const SizedBox(height:3),
                  Text(widget.user.fullName.split(' ').first,
                      style:const TextStyle(color:Colors.white,
                          fontWeight:FontWeight.w800, fontSize:21)),
                  if (widget.user.siteName!=null) ...[
                    const SizedBox(height:6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal:8, vertical:3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(widget.user.siteName!, style:const TextStyle(
                          color:Colors.white, fontSize:11, fontWeight:FontWeight.w600)),
                    ),
                  ],
                ])),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.health_and_safety_rounded,
                    color:Colors.white, size:28),
              ),
            ]),
          ),
          const SizedBox(height:18),
          Row(children: [
            _st('Total',_total>0?_total:_crfs.length,_kPrimary,Icons.people_alt_rounded,
                () => widget.onOpenPatients(filter: 'All')),
            const SizedBox(width:10),
            _st('Enrolled',_enrolled2>0?_enrolled2:enrolled,_kSuccess,Icons.check_circle_rounded,
                () => widget.onOpenPatients(filter: 'Enrolled')),
            const SizedBox(width:10),
            _st('Excluded',_excluded2>0?_excluded2:excluded,_kDanger,Icons.block_rounded,
                () => widget.onOpenPatients(filter: 'Excluded')),
            const SizedBox(width:10),
            _st('Drafts',_drafts.length,_kWarning,Icons.pending_rounded, _showDraftsSheet),
          ]),
          const SizedBox(height:20),
          const Text('Quick actions', style:TextStyle(fontSize:14,
              fontWeight:FontWeight.w800, color:_kText1)),
          const SizedBox(height:10),
          Row(children: [
            _ac(Icons.person_add_alt_1_rounded,'New\nScreening',_kPrimary,
                ()=>Navigator.push(context,MaterialPageRoute(
                    builder:(_)=>const ScreeningForm(loadDraft:false)))),
            const SizedBox(width:10),
            _ac(Icons.pending_actions_rounded,'My\nDrafts',_kWarning, _showDraftsSheet),
            const SizedBox(width:10),
            _ac(Icons.calendar_today_rounded,'Visit\nSchedule',_kSuccess, _showVisitSchedule),
            const SizedBox(width:10),
            _ac(Icons.picture_as_pdf_rounded,'Export\nPDF',_kDanger, _showExportPdfPicker),
          ]),
          const SizedBox(height:22),
          if (_drafts.isNotEmpty) ...[
            Text('Drafts (${_drafts.length})', style:const TextStyle(
                fontSize:14, fontWeight:FontWeight.w800, color:_kText1)),
            const SizedBox(height:10),
            ..._drafts.map((d) => _draftCard(d)),
            const SizedBox(height:18),
          ],
          Text('Recent patients (${_crfs.take(5).length})',
              style:const TextStyle(fontSize:14,
                  fontWeight:FontWeight.w800, color:_kText1)),
          const SizedBox(height:10),
          if (_loading) const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child:CircularProgressIndicator(color: _kPrimary)))
          else if (_crfs.isEmpty) _empty()
          else ..._crfs.take(5).map(_crfCard),
        ],
      ),
    );
  }

  String _g(){ final h=DateTime.now().hour;
    if(h<12)return 'morning'; if(h<17)return 'afternoon'; return 'evening'; }

  Future<void> _showDraftsSheet() async {
    if (_drafts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No drafts yet. Start a new screening to create one.'),
      ));
      return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.pending_actions_rounded, color: _kWarning, size: 20),
              const SizedBox(width: 8),
              Text('My Drafts (${_drafts.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kText1)),
            ]),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _drafts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = _drafts[i];
                  final name = (d['motherName'] as String? ?? '').trim();
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _kBorder),
                    ),
                    leading: const Icon(Icons.description_outlined, color: _kWarning),
                    title: Text('${d['screeningId']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _kText1)),
                    subtitle: Text(name.isEmpty ? 'No name entered yet' : name,
                        style: const TextStyle(fontSize: 11, color: _kText3)),
                    trailing: const Text('Resume',
                        style: TextStyle(color: _kWarning, fontWeight: FontWeight.w700, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ScreeningForm(loadDraft: true, draftKey: d['key']),
                      ));
                      await _load();
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showVisitSchedule() async {
    // Fetch fuller list — Home only keeps top-5 in memory for speed.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
    );
    List<CRF> all;
    try {
      all = await fetchPatientCrfs(piiLimit: 40);
    } catch (_) {
      all = _crfs;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    // Work queue: drafts + patients needing Form B + enrolled follow-ups.
    final needFormB = all.where((c) {
      final consent = c.consentStatus.trim().toLowerCase();
      return !_isExcluded(c) &&
          c.enrollmentId.isEmpty &&
          (consent == 'yes' || consent.contains('trial'));
    }).take(15).toList();
    final enrolled = all.where(_isEnrolled).take(10).toList();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: ListView(shrinkWrap: true, children: [
              const Row(children: [
                Icon(Icons.calendar_today_rounded, color: _kSuccess, size: 20),
                SizedBox(width: 8),
                Text('Visit Schedule',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kText1)),
              ]),
              const SizedBox(height: 4),
              const Text('Pending work at your site',
                  style: TextStyle(fontSize: 11.5, color: _kText3)),
              const SizedBox(height: 14),
              if (_drafts.isEmpty && needFormB.isEmpty && enrolled.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('Nothing pending right now',
                      style: TextStyle(color: _kText3, fontSize: 13))),
                ),
              if (_drafts.isNotEmpty) ...[
                const Text('Drafts to resume',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _kText1)),
                const SizedBox(height: 8),
                ..._drafts.map((d) {
                  final name = (d['motherName'] as String? ?? '').trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pending_actions_rounded, color: _kWarning),
                    title: Text('${d['screeningId']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: Text(name.isEmpty ? 'Draft screening' : name,
                        style: const TextStyle(fontSize: 11, color: _kText3)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kText3),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ScreeningForm(loadDraft: true, draftKey: d['key']),
                      ));
                      await _load();
                    },
                  );
                }),
                const SizedBox(height: 10),
              ],
              if (needFormB.isNotEmpty) ...[
                const Text('Ready for Form B',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _kText1)),
                const SizedBox(height: 8),
                ...needFormB.map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.child_care_rounded, color: _kPrimary),
                      title: Text(
                        '${c.motherFirstName} ${c.motherSurname}'.trim().isEmpty
                            ? c.screeningId
                            : '${c.motherFirstName} ${c.motherSurname}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      subtitle: Text('${c.screeningId} · consent obtained',
                          style: const TextStyle(fontSize: 11, color: _kText3)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: _kText3),
                      onTap: () {
                        Navigator.pop(ctx);
                        showPatientActionsSheet(context, c);
                      },
                    )),
                const SizedBox(height: 10),
              ],
              if (enrolled.isNotEmpty) ...[
                const Text('Enrolled — continue forms',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _kText1)),
                const SizedBox(height: 8),
                ...enrolled.map((c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_rounded, color: _kSuccess),
                      title: Text(
                        '${c.motherFirstName} ${c.motherSurname}'.trim().isEmpty
                            ? c.screeningId
                            : '${c.motherFirstName} ${c.motherSurname}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      subtitle: Text('${c.screeningId} · enrolled',
                          style: const TextStyle(fontSize: 11, color: _kText3)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: _kText3),
                      onTap: () {
                        Navigator.pop(ctx);
                        showPatientActionsSheet(context, c);
                      },
                    )),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onOpenPatients(filter: 'All');
                },
                child: const Text('Open all patients',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showExportPdfPicker() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _kPrimary)),
    );
    List<CRF> all;
    try {
      all = await fetchPatientCrfs(piiLimit: 40);
    } catch (_) {
      all = _crfs;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No patients to export yet.'),
      ));
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Row(children: [
              Icon(Icons.picture_as_pdf_rounded, color: _kDanger, size: 20),
              SizedBox(width: 8),
              Text('Export PDF',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _kText1)),
            ]),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose a patient to generate their CRF PDF',
                  style: TextStyle(fontSize: 11.5, color: _kText3)),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.55,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: all.length.clamp(0, 40),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = all[i];
                  final name = '${c.motherFirstName} ${c.motherSurname}'.trim();
                  return ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined, color: _kDanger),
                    title: Text(name.isEmpty ? c.screeningId : name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _kText1)),
                    subtitle: Text(c.screeningId,
                        style: const TextStyle(fontSize: 11, color: _kText3)),
                    trailing: const Icon(Icons.download_rounded, color: _kText3, size: 18),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await exportPatientPdf(context, c);
                    },
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onOpenPatients(filter: 'All');
              },
              child: const Text('Browse all patients',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _st(String l,int v,Color c,IconData i, VoidCallback onTap) => Expanded(child:
    Material(color:_kSurface, borderRadius:BorderRadius.circular(16),
      child:InkWell(onTap:onTap, borderRadius:BorderRadius.circular(16),
        child:Container(
    padding:const EdgeInsets.fromLTRB(11,12,11,12),
    decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(16),
        boxShadow:[BoxShadow(color:c.withOpacity(0.12),
            blurRadius:10, offset:const Offset(0,4))]),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(
        width:26, height:26,
        decoration:BoxDecoration(color:c.withOpacity(0.12),
            borderRadius:BorderRadius.circular(8)),
        child:Icon(i,color:c,size:14),
      ),
      const SizedBox(height:8),
      Text('$v',style:TextStyle(color:_kText1,fontSize:20,
          fontWeight:FontWeight.w800,height:1)),
      const SizedBox(height:2),
      Text(l,style:const TextStyle(color:_kText3,fontSize:9,
          fontWeight:FontWeight.w600)),
    ]),
  ))));

  Widget _ac(IconData i,String l,Color c,VoidCallback t) => Expanded(child:
    Material(color:_kSurface, borderRadius:BorderRadius.circular(16),
      child:InkWell(onTap:t, borderRadius:BorderRadius.circular(16),
        child:Container(
        padding:const EdgeInsets.symmetric(vertical:14),
        decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(16),
            boxShadow:[BoxShadow(color:_kText1.withOpacity(0.05),
                blurRadius:8, offset:const Offset(0,3))]),
        child:Column(children:[
          Container(
            width:38, height:38,
            decoration:BoxDecoration(color:c.withOpacity(0.12),
                borderRadius:BorderRadius.circular(11)),
            child:Icon(i,color:c,size:20),
          ),
          const SizedBox(height:8),
          Text(l,textAlign:TextAlign.center,style:const TextStyle(
              color:_kText1,fontSize:10,fontWeight:FontWeight.w600,height:1.3)),
        ]),
      ))));

  Widget _empty() => Container(
    padding:const EdgeInsets.all(32),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(18),
        boxShadow:[BoxShadow(color:_kText1.withOpacity(0.05),
            blurRadius:10, offset:const Offset(0,4))]),
    child:Column(children:[
      Container(
        width:56, height:56,
        decoration:BoxDecoration(color:_kPrimary.withOpacity(0.08),
            shape:BoxShape.circle),
        child:const Icon(Icons.person_search_rounded,size:26,color:_kPrimary),
      ),
      const SizedBox(height:12),
      const Text('No patients screened yet',
          style:TextStyle(color:_kText1,fontSize:13,fontWeight:FontWeight.w600)),
      const SizedBox(height:4),
      const Text('New screenings will show up here',
          style:TextStyle(color:_kText3,fontSize:11)),
    ]));

  Widget _draftCard(Map<String,dynamic> d) => Container(
    margin:const EdgeInsets.only(bottom:9),
    padding:const EdgeInsets.symmetric(horizontal:13,vertical:11),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(15),
        boxShadow:[BoxShadow(color:_kWarning.withOpacity(0.10),
            blurRadius:10, offset:const Offset(0,4))]),
    child:Row(children:[
      Container(
        width:34, height:34,
        decoration:BoxDecoration(color:_kWarning.withOpacity(0.12),
            borderRadius:BorderRadius.circular(10)),
        child:const Icon(Icons.pending_actions_rounded,color:_kWarning,size:18),
      ),
      const SizedBox(width:11),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(d['screeningId'],style:const TextStyle(
            color:_kText1,fontWeight:FontWeight.w700,fontSize:12)),
        Text((d['motherName'] as String? ?? '').trim().isEmpty
                ? 'No name entered yet' : (d['motherName'] as String).trim(),
            style:const TextStyle(color:_kText3,fontSize:10)),
      ])),
      Material(color:const Color(0xFFFFF8E1), borderRadius:BorderRadius.circular(9),
        child:InkWell(borderRadius:BorderRadius.circular(9),
          onTap:()async{
            await Navigator.push(context,MaterialPageRoute(builder:(_)=>
                ScreeningForm(loadDraft:true,draftKey:d['key'])));
            await _load();
          },
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:11,vertical:7),
            child:const Text('Resume',style:TextStyle(
                color:_kWarning,fontSize:11,fontWeight:FontWeight.w700)),
          ))),
    ]));

  Widget _crfCard(CRF c) => buildPatientCard(c, () => showPatientActionsSheet(context, c));

}

// ── PI DASHBOARD ─────────────────────────────────────────────────────────────
class PIDashboard extends StatelessWidget {
  const PIDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(user:user,
      pages:[_SD(user:user,title:'PI Dashboard',
        subtitle:'Approve forms, view site data and reports',
        color:_kSuccess,
        actions:['Forms to approve','Open queries','Site report','Verify forms']),
        _ph('Patients'), _ph('Reports')],
      navItems:const[
        BottomNavigationBarItem(icon:Icon(Icons.home_outlined),
            activeIcon:Icon(Icons.home_rounded),label:'Home'),
        BottomNavigationBarItem(icon:Icon(Icons.people_outline),
            activeIcon:Icon(Icons.people_rounded),label:'Patients'),
        BottomNavigationBarItem(icon:Icon(Icons.assessment_outlined),
            activeIcon:Icon(Icons.assessment_rounded),label:'Reports'),
      ]);
  }
}

// ── SCIENTIST DASHBOARD ───────────────────────────────────────────────────────
class ScientistDashboard extends StatelessWidget {
  const ScientistDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(user:user,
      pages:[_SD(user:user,title:'Scientist Dashboard',
        subtitle:'Monitor data quality and generate reports',
        color:const Color(0xFF534AB7),
        actions:['Review Form B','Missing Helper Form 3',
                 'Download site report','Raise query']),
        _ph('Quality'), _ph('Reports')],
      navItems:const[
        BottomNavigationBarItem(icon:Icon(Icons.home_outlined),
            activeIcon:Icon(Icons.home_rounded),label:'Home'),
        BottomNavigationBarItem(icon:Icon(Icons.analytics_outlined),
            activeIcon:Icon(Icons.analytics_rounded),label:'Quality'),
        BottomNavigationBarItem(icon:Icon(Icons.description_outlined),
            activeIcon:Icon(Icons.description_rounded),label:'Reports'),
      ]);
  }
}

// ── DEO DASHBOARD ─────────────────────────────────────────────────────────────
class DEODashboard extends StatelessWidget {
  const DEODashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(user:user,
      pages:[_SD(user:user,title:'DEO Dashboard',
        subtitle:'Data entry queue for your site',
        color:_kWarning,
        actions:['Form A (Priority)','Helper Form 2',
                 'Form B','Form C (Fix required)']),
        _ph('Queue'), _ph('Done')],
      navItems:const[
        BottomNavigationBarItem(icon:Icon(Icons.home_outlined),
            activeIcon:Icon(Icons.home_rounded),label:'Home'),
        BottomNavigationBarItem(icon:Icon(Icons.inbox_outlined),
            activeIcon:Icon(Icons.inbox_rounded),label:'Queue'),
        BottomNavigationBarItem(icon:Icon(Icons.check_circle_outline),
            activeIcon:Icon(Icons.check_circle_rounded),label:'Done'),
      ]);
  }
}

// ── MONITOR DASHBOARD ─────────────────────────────────────────────────────────
class MonitorDashboard extends StatelessWidget {
  const MonitorDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(user:user,
      pages:[_SD(user:user,title:'Monitor Dashboard',
        subtitle:'Read-only view across all trial sites',
        color:const Color(0xFF5F5E5A),
        actions:['Query — PGIMER','SDV review — Aurangabad',
                 'Protocol deviation','Schedule site visit']),
        _ph('Queries'), _ph('SDV'), _ph('Audit')],
      navItems:const[
        BottomNavigationBarItem(icon:Icon(Icons.home_outlined),
            activeIcon:Icon(Icons.home_rounded),label:'Home'),
        BottomNavigationBarItem(icon:Icon(Icons.flag_outlined),
            activeIcon:Icon(Icons.flag_rounded),label:'Queries'),
        BottomNavigationBarItem(icon:Icon(Icons.fact_check_outlined),
            activeIcon:Icon(Icons.fact_check_rounded),label:'SDV'),
        BottomNavigationBarItem(icon:Icon(Icons.history_outlined),
            activeIcon:Icon(Icons.history_rounded),label:'Audit'),
      ]);
  }
}

// ── SHARED SIMPLE DASHBOARD ───────────────────────────────────────────────────
class _SD extends StatefulWidget {
  final UserProfile user;
  final String title, subtitle;
  final Color color;
  final List<String> actions;
  const _SD({required this.user,required this.title,required this.subtitle,
    required this.color,required this.actions});
  @override
  State<_SD> createState() => _SDState();
}

class _SDState extends State<_SD> {
  Map<String,dynamic> _stats = {};
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final s = await ScreeningApiService.instance.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final t=_stats['total']??0; final e=_stats['enrolled']??0;
    final x=_stats['excluded']??0; final p=_stats['pending']??0;
    final stats = _stats.isEmpty
        ? [('--','Screened'),('--','Enrolled'),('--','Excluded'),('--','Pending')]
        : [('$t','Screened'),('$e','Enrolled'),('$x','Excluded'),('$p','Pending')];
    return ListView(padding:const EdgeInsets.fromLTRB(16,16,16,40),children:[
      Container(
        padding:const EdgeInsets.all(16),
        decoration:BoxDecoration(color:widget.color,
            borderRadius:BorderRadius.circular(16)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.title,style:const TextStyle(color:Colors.white,
              fontWeight:FontWeight.w700,fontSize:16)),
          const SizedBox(height:4),
          Text(widget.subtitle,style:const TextStyle(
              color:Colors.white70,fontSize:11)),
          const SizedBox(height:10),
          if (widget.user.siteName!=null)
            Container(
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
              decoration:BoxDecoration(
                  color:Colors.white.withOpacity(0.15),
                  borderRadius:BorderRadius.circular(6)),
              child:Text(widget.user.siteName!,
                  style:const TextStyle(color:Colors.white,fontSize:10))),
        ])),
      const SizedBox(height:14),
      GridView.count(
        crossAxisCount:2,shrinkWrap:true,
        physics:const NeverScrollableScrollPhysics(),
        crossAxisSpacing:9,mainAxisSpacing:9,childAspectRatio:2.0,
        children:stats.map((s)=>Container(
          padding:const EdgeInsets.all(12),
          decoration:BoxDecoration(color:_kSurface,
              borderRadius:BorderRadius.circular(12),
              border:Border.all(color:widget.color.withOpacity(0.2))),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,
            mainAxisAlignment:MainAxisAlignment.center,children:[
            Text(s.$1,style:TextStyle(fontSize:22,
                fontWeight:FontWeight.w800,color:widget.color)),
            Text(s.$2,style:const TextStyle(fontSize:10,color:_kText3)),
          ]),
        )).toList()),
      const SizedBox(height:14),
      const Text('Action items',style:TextStyle(fontSize:13,
          fontWeight:FontWeight.w700,color:_kText1)),
      const SizedBox(height:8),
      ...widget.actions.map((a)=>Container(
        margin:const EdgeInsets.only(bottom:8),
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
        decoration:BoxDecoration(color:_kSurface,
            borderRadius:BorderRadius.circular(12),
            border:Border.all(color:_kBorder)),
        child:Row(children:[
          Container(width:6,height:6,decoration:BoxDecoration(
              color:widget.color,shape:BoxShape.circle)),
          const SizedBox(width:10),
          Expanded(child:Text(a,style:const TextStyle(
              fontSize:12,color:_kText1))),
          const Icon(Icons.chevron_right_rounded,color:_kText3,size:16),
        ]))),
    ]);
  }
}

Widget _ph(String l) => Center(child:Text(l,
    style:const TextStyle(color:_kText3,fontSize:16)));