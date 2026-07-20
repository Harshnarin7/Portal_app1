// lib/screens/dashboards/nurse_dashboard.dart — CLEAN REWRITE
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/crf.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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
class NurseDashboard extends StatelessWidget {
  const NurseDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().user!;
    return DashboardShell(
      user: user,
      pages: [_NurseHome(user: user), _ph('Patients')],
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
  const _NurseHome({required this.user});
  @override
  State<_NurseHome> createState() => _NurseHomeState();
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
    final drafts = <Map<String,dynamic>>[];
    final vkeys  = <String>[];
    for (final k in keys) {
      final raw = prefs.getString(k); if (raw==null) continue;
      final d = jsonDecode(raw) as Map<String,dynamic>;
      final sid = d['screeningId'] as String? ?? '';
      vkeys.add(k);
      drafts.add({'key':k,'screeningId':sid.isEmpty?'Draft':sid,
          'motherName':'${d['motherFirstName']??''} ${d['motherSurname']??''}'});
    }
    await prefs.setStringList('screening_draft_keys', vkeys);

    // ── Load patients from BACKEND (site-isolated) ─────────────────────
    List<CRF> crfs = [];
    try {
      final patients = await ScreeningApiService.instance.getPatients();
      crfs = patients.map((p) {
        // Map backend field names to CRF model field names.
        // FIX: previous keys (eligibility_status, consent_status, site,
        // site_code, screening_date_time, mother_first_name, etc.) don't
        // exist on the real backend response at all — this is why
        // "Continue to Form B" never appeared: eligibilityStatus/
        // consentStatus always fell back to "", so _isEligible() was
        // always false regardless of the patient's actual status.
        //
        // NOTE: GET /screenings/ is deliberately the de-identified
        // "clinical view" (per backend's own ScreeningClinicalOut
        // docstring) — it does NOT include PII (mother/husband name,
        // phone, hospital no, maternal UID). Those fields will show
        // blank here until/unless a per-record PII fetch (GET
        // /screening/{screening_id}) is merged in separately — that's a
        // separate, bigger piece of work, not attempted in this fix.
        // CRF.fromJson expects a NESTED structure (identification/maternal/
        // gestation/exclusion/finalDecision groups) — this used to build a
        // FLAT map instead, which meant even with correct field names,
        // every value still came out empty (json["identification"] didn't
        // exist, so it always fell back to {}). This was the second half of
        // why "Continue to Form B" never worked — nesting it correctly now.
        final mapped = {
          "identification": {
            'screeningId'       : p['screening_id'] ?? '',
            'site'              : p['site_name'] ?? '',
            'siteId'            : p['site_id'] ?? '',
            'screeningDateTime' : p['screening_datetime'] ?? '',
            'screenedBy'        : p['screened_by'] ?? '',
          },
          "maternal": {
            'motherFirstName' : p['mother_first_name'] ?? '',
            'motherSurname'   : p['mother_surname'] ?? '',
            'husbandFirstName': p['husband_first_name'] ?? '',
            'husbandSurname'  : p['husband_surname'] ?? '',
            'motherPhone'     : p['mother_phone'] ?? '',
            'husbandPhone'    : p['husband_phone'] ?? '',
            'maternalUid'     : p['maternal_uid'] ?? '',
            'hospitalNo'      : p['hospital_no'] ?? '',
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
          // Not part of the original CRF.fromJson shape — read directly by
          // the patient actions menu below to decide which forms are
          // available (Helper Forms need a real enrollment_id).
          'enrollmentId': p['enrollment_id'] ?? '',
        };
        return CRF.fromJson(mapped);
      }).toList();
    } catch (_) {
      // Fallback to local if backend unreachable
      crfs = await ApiService().loadAllCRFs();
    }

    if (!mounted) return;
    setState(() { _crfs=crfs.reversed.toList(); _drafts=drafts; _loading=false; });

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
    final enrolled = _crfs.where((c)=>
        c.eligibilityStatus=='Eligible'&&c.consentStatus=='Yes').length;
    final excluded = _crfs.where((c)=>
        c.eligibilityStatus=='Not Eligible'||c.consentStatus=='No').length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16,16,16,100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color:_kPrimary,
                borderRadius:BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,
                children: [
                  Text('Good ${_g()},', style:const TextStyle(
                      color:Colors.white70, fontSize:12)),
                  const SizedBox(height:2),
                  Text(widget.user.fullName.split(' ').first,
                      style:const TextStyle(color:Colors.white,
                          fontWeight:FontWeight.w700, fontSize:18)),
                  if (widget.user.siteName!=null)
                    Text(widget.user.siteName!, style:const TextStyle(
                        color:Colors.white70, fontSize:11)),
                ])),
              const Icon(Icons.health_and_safety_rounded,
                  color:Colors.white, size:32),
            ]),
          ),
          const SizedBox(height:14),
          Row(children: [
            _st('Total',_total>0?_total:_crfs.length,_kPrimary,Icons.people_alt_rounded),
            const SizedBox(width:9),
            _st('Enrolled',_enrolled2>0?_enrolled2:enrolled,_kSuccess,Icons.check_circle_rounded),
            const SizedBox(width:9),
            _st('Excluded',_excluded2>0?_excluded2:excluded,_kDanger,Icons.block_rounded),
            const SizedBox(width:9),
            _st('Drafts',_drafts.length,_kWarning,Icons.pending_rounded),
          ]),
          const SizedBox(height:14),
          const Text('Quick actions', style:TextStyle(fontSize:13,
              fontWeight:FontWeight.w700, color:_kText1)),
          const SizedBox(height:8),
          Row(children: [
            _ac(Icons.person_add_alt_1_rounded,'New\nScreening',_kPrimary,
                ()=>Navigator.push(context,MaterialPageRoute(
                    builder:(_)=>const ScreeningForm(loadDraft:false)))),
            const SizedBox(width:9),
            _ac(Icons.pending_actions_rounded,'My\nDrafts',_kWarning,(){}),
            const SizedBox(width:9),
            _ac(Icons.calendar_today_rounded,'Visit\nSchedule',_kSuccess,(){}),
            const SizedBox(width:9),
            _ac(Icons.picture_as_pdf_rounded,'Export\nPDF',_kDanger,(){}),
          ]),
          const SizedBox(height:18),
          if (_drafts.isNotEmpty) ...[
            Text('Drafts (${_drafts.length})', style:const TextStyle(
                fontSize:13, fontWeight:FontWeight.w700, color:_kText1)),
            const SizedBox(height:8),
            ..._drafts.map((d) => _draftCard(d)),
            const SizedBox(height:14),
          ],
          Text('Recent patients (${_crfs.take(5).length})',
              style:const TextStyle(fontSize:13,
                  fontWeight:FontWeight.w700, color:_kText1)),
          const SizedBox(height:8),
          if (_loading) const Center(child:CircularProgressIndicator())
          else if (_crfs.isEmpty) _empty()
          else ..._crfs.take(5).map(_crfCard),
        ],
      ),
    );
  }

  String _g(){ final h=DateTime.now().hour;
    if(h<12)return 'morning'; if(h<17)return 'afternoon'; return 'evening'; }

  Widget _st(String l,int v,Color c,IconData i) => Expanded(child:Container(
    padding:const EdgeInsets.fromLTRB(10,11,10,11),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(14),
        border:Border.all(color:c.withOpacity(0.2))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(i,color:c,size:16), const SizedBox(height:6),
      Text('$v',style:TextStyle(color:c,fontSize:20,
          fontWeight:FontWeight.w800,height:1)),
      const SizedBox(height:2),
      Text(l,style:const TextStyle(color:_kText3,fontSize:9,
          fontWeight:FontWeight.w600)),
    ]),
  ));

  Widget _ac(IconData i,String l,Color c,VoidCallback t) => Expanded(child:
    GestureDetector(onTap:t, child:Container(
      padding:const EdgeInsets.symmetric(vertical:14),
      decoration:BoxDecoration(color:_kSurface,
          borderRadius:BorderRadius.circular(14),
          border:Border.all(color:_kBorder)),
      child:Column(children:[
        Icon(i,color:c,size:24), const SizedBox(height:6),
        Text(l,textAlign:TextAlign.center,style:const TextStyle(
            color:_kText1,fontSize:10,fontWeight:FontWeight.w600,height:1.3)),
      ]),
    )));

  Widget _empty() => Container(
    padding:const EdgeInsets.all(28),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(14),
        border:Border.all(color:_kBorder)),
    child:const Column(children:[
      Icon(Icons.person_search_rounded,size:36,color:_kBorder),
      SizedBox(height:10),
      Text('No patients screened yet',
          style:TextStyle(color:_kText3,fontSize:13)),
    ]));

  Widget _draftCard(Map<String,dynamic> d) => Container(
    margin:const EdgeInsets.only(bottom:8),
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
    decoration:BoxDecoration(color:_kSurface,
        borderRadius:BorderRadius.circular(13),
        border:Border.all(color:_kWarning.withOpacity(0.35))),
    child:Row(children:[
      const Icon(Icons.pending_actions_rounded,color:_kWarning,size:20),
      const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(d['screeningId'],style:const TextStyle(
            color:_kText1,fontWeight:FontWeight.w700,fontSize:12)),
        Text(d['motherName']??'',style:const TextStyle(
            color:_kText3,fontSize:10)),
      ])),
      GestureDetector(
        onTap:()async{
          await Navigator.push(context,MaterialPageRoute(builder:(_)=>
              ScreeningForm(loadDraft:true,draftKey:d['key'])));
          await _load();
        },
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
          decoration:BoxDecoration(color:const Color(0xFFFFF8E1),
              borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_kWarning.withOpacity(0.35))),
          child:const Text('Resume',style:TextStyle(
              color:_kWarning,fontSize:11,fontWeight:FontWeight.w700)),
        )),
    ]));

  Widget _crfCard(CRF c) {
    final ok = c.eligibilityStatus=='Eligible'&&c.consentStatus=='Yes';
    final col = ok?_kSuccess:_kDanger;
    return GestureDetector(
      onTap: () => _openPatientActions(c),
      child: Container(
      margin:const EdgeInsets.only(bottom:8),
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:_kSurface,
          borderRadius:BorderRadius.circular(14),
          border:Border.all(color:col.withOpacity(0.2))),
      child:Row(children:[
        Container(width:38,height:38,
          decoration:BoxDecoration(color:col.withOpacity(0.1),
              borderRadius:BorderRadius.circular(10)),
          child:Center(child:Text(
            c.motherFirstName.isNotEmpty?c.motherFirstName[0].toUpperCase():'?',
            style:TextStyle(color:col,fontWeight:FontWeight.w800,fontSize:16)))),
        const SizedBox(width:10),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text('${c.motherFirstName} ${c.motherSurname}',style:const TextStyle(
                color:_kText1,fontWeight:FontWeight.w700,fontSize:12)),
            const SizedBox(height:2),
            Text('${c.screeningId} · ${c.gestationWeeks}w ${c.gestationDays}d',
                style:const TextStyle(color:_kText3,fontSize:10)),
          ])),
        Container(
          padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
          decoration:BoxDecoration(color:col.withOpacity(0.1),
              borderRadius:BorderRadius.circular(6)),
          child:Text(ok?'Enrolled':'Excluded',
              style:TextStyle(color:col,fontSize:10,fontWeight:FontWeight.w700))),
        const SizedBox(width:6),
        Icon(Icons.chevron_right_rounded, color:_kText3, size:18),
      ])),
    );
  }

  // ── Patient actions menu — lists every form actually built into this app.
  // Helper Forms are enrollment-scoped (need a real enrollment_id from Form
  // B's randomization step), so they're disabled with an explanatory note
  // until that exists — rather than silently crashing on a missing ID.
  void _openPatientActions(CRF c) {
    final hasEnrollment = c.enrollmentId.isNotEmpty;
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
            _actionTile(ctx, 'Form B — Birth & Resuscitation', Icons.child_care_rounded, true,
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
            _actionTile(ctx, 'Form C — Resuscitation Details', Icons.monitor_heart_rounded, true,
              () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => FormCResuscitationDetails(
                    screeningId: c.screeningId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                    babyUid: c.maternalUid,
                  )))),
            _actionTile(ctx, 'Helper Form 2 — Resp/CV/Neuro', Icons.favorite_rounded, hasEnrollment,
              () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm2RespCvNeuro(
                    enrollmentId: c.enrollmentId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                    babyUid: c.maternalUid,
                    site: c.site.isNotEmpty ? c.site : 'PGIMER',
                  )))),
            _actionTile(ctx, 'Helper Form 3 — Infection/GI/Hema', Icons.bloodtype_rounded, hasEnrollment,
              () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm3InfectGIHema(
                    enrollmentId: c.enrollmentId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                    babyUid: c.maternalUid,
                  )))),
            _actionTile(ctx, 'Helper Form 4 — Metab/Renal/Vasc/Eye', Icons.visibility_rounded, hasEnrollment,
              () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperForm4MetabRenalVascEye(
                    enrollmentId: c.enrollmentId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                    babyUid: c.maternalUid,
                  )))),
            _actionTile(ctx, 'Helper Form — FiO2 / AUC', Icons.air_rounded, hasEnrollment,
              () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => HelperFiO2AUC(
                    enrollmentId: c.enrollmentId,
                    gestation: '${c.gestationWeeks}w ${c.gestationDays}d',
                    motherName: '${c.motherFirstName} ${c.motherSurname}'.trim(),
                  )))),
            if (!hasEnrollment) Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Helper Forms unlock after Form B is randomized (enrollment ID assigned).',
                  style: TextStyle(color: _kText3, fontSize: 11)),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _actionTile(BuildContext ctx, String label, IconData icon, bool enabled, VoidCallback onTap) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? _kPrimary : _kText3),
      title: Text(label, style: TextStyle(
          color: enabled ? _kText1 : _kText3, fontWeight: FontWeight.w600, fontSize: 13)),
      trailing: Icon(Icons.chevron_right_rounded, color: enabled ? _kText3 : _kText3.withOpacity(0.4)),
      onTap: enabled ? () { Navigator.pop(ctx); onTap(); } : null,
    );
  }
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
