import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../providers/auth_provider.dart';

import '../models/crf.dart';
import '../models/birth_resuscitation.dart';
import '../screens/screening_form.dart';
import '../navigation/route_observer.dart';
import '../services/api_service.dart';
import '../services/forms_api_service.dart';
import '../services/pdf_service.dart';
import 'package:open_filex/open_filex.dart';
import '../screens/form_b_birth_resuscitation.dart';
import '../screens/helper_fio2_auc.dart';
import '../screens/helper_form5_minimal_monitoring.dart';
import '../screens/helper_form2_resp_cv_neuro.dart';
import '../screens/helper_form3_infect_gi_hema.dart';
import '../screens/helper_form4_metab_renal_vasc_eye.dart';
import '../services/screening_api_service.dart';
import '../utils/screening_status.dart';
import '../widgets/shimmer_loader.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RouteAware {
  List<CRF> _crfList = [];
  List<Map<String, dynamic>> _drafts = [];

  bool _showDrafts = true;
  bool _showScreened = true;
  bool _isRefreshing = false;
  bool _isInitialLoad = true; // true only until the very first _refresh() finishes

  String _searchQuery = "";
  String _filterStatus = "All";

  // ── Warm Slate Blue Theme ──────────────────────────────────────────────────
  // Background: soft blue-grey gradient feel
  static const _bg          = Color(0xFFEFF3FB);  // cool blue-tinted page bg
  static const _bgGradTop   = Color(0xFFDDE6F5);  // slightly richer top
  static const _surface     = Color(0xFFFFFFFF);
  static const _surfaceAlt  = Color(0xFFF4F7FC);
  static const _border      = Color(0xFFD4DCF0);
  static const _borderLight = Color(0xFFE8EDF8);

  // Primary palette — slate blue
  static const _primary     = Color(0xFF3B6FE0);  // vivid slate blue
  static const _primaryDark = Color(0xFF2554C7);
  static const _primarySoft = Color(0xFFDDE6F5);

  // Semantic
  static const _success     = Color(0xFF0F9D58);
  static const _successSoft = Color(0xFFE6F4EA);
  static const _danger      = Color(0xFFE53935);
  static const _dangerSoft  = Color(0xFFFDECEC);
  static const _warning     = Color(0xFFF59E0B);
  static const _warningSoft = Color(0xFFFFF8E1);
  static const _purple      = Color(0xFF7C3AED);
  static const _purpleSoft  = Color(0xFFF3EEFF);
  static const _grey        = Color(0xFF6B7280);
  static const _greySoft    = Color(0xFFF3F4F6);

  // Text
  static const _textPrimary   = Color(0xFF1A2340);
  static const _textSecondary = Color(0xFF4A5578);
  static const _textTertiary  = Color(0xFF8A95B0);

  // ================= LIFECYCLE =================

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => _refresh();

  // ================= LOAD =================

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await _loadCrfs();
    await _loadDrafts();
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _isInitialLoad = false;
      });
    }
  }

  Future<void> _loadCrfs() async {
    // Prefer shared site-scoped API list (same as web ViewEntries)
    // so eligibility banners match screening_status from the backend.
    try {
      final patients = await ScreeningApiService.instance.getPatients(limit: 200);
      final piiIds = patients
          .map((p) => p['screening_id']?.toString() ?? '')
          .where((sid) => sid.isNotEmpty)
          .toList();
      Map<String, Map<String, dynamic>> piiById = {};
      if (piiIds.isNotEmpty) {
        try {
          piiById = await ScreeningApiService.instance.getPiiBatch(piiIds);
        } catch (_) {}
      }
      final list = patients.map((p) {
        final sid = p['screening_id']?.toString() ?? '';
        final pii = piiById[sid] ?? const <String, dynamic>{};
        final mapped = {
          "identification": {
            'screeningId': p['screening_id'] ?? '',
            'site': p['site_name'] ?? '',
            'siteId': p['site_id'] ?? '',
            'screeningDateTime': p['screening_datetime'] ?? '',
            'screenedBy': p['screened_by'] ?? '',
          },
          "maternal": {
            'motherFirstName': pii['mother_first_name'] ?? p['mother_first_name'] ?? '',
            'motherSurname': pii['mother_surname'] ?? p['mother_surname'] ?? '',
            'husbandFirstName': pii['husband_first_name'] ?? p['husband_first_name'] ?? '',
            'husbandSurname': pii['husband_surname'] ?? p['husband_surname'] ?? '',
            'motherPhone': '',
            'husbandPhone': '',
            'maternalUid': pii['maternal_uid'] ?? '',
            'hospitalNo': pii['hospital_admission_number'] ?? '',
          },
          "gestation": {
            'weeks': p['gestation_weeks'] ?? 0,
            'days': p['gestation_days'] ?? 0,
            'method': p['gestation_method'] ?? '',
            'expectedDeliveryDate': p['expected_delivery_date'] ?? '',
            'gestationKnownInWeeks': p['gestation_weeks'] != null,
            'eddKnown': p['expected_delivery_date'] != null,
          },
          "exclusion": {
            'present': p['exclusion_present'] ?? false,
            'reason': p['exclusion_reasons'] ?? '',
            'anomalyDetails': p['major_structural_anomalies_if_yes'] ?? '',
          },
          "finalDecision": {
            'eligibilityStatus': p['screening_status'] ?? '',
            'consentStatus': p['consent_given'] ?? '',
            'consentRefusalReason': p['reason_for_consent_refusal'] ?? '',
            'relationshipToParticipant':
                p['relationship_to_participant'] ?? '',
            'relationshipOther': p['relationship_other'] ?? '',
            'consentTakenBy': p['consent_taken_by'] ?? '',
          },
          'enrollmentId': p['enrollment_id'] ?? '',
        };
        return CRF.fromJson(mapped);
      }).toList();
      if (!mounted) return;
      setState(() => _crfList = _ownSiteOnly(list));
      return;
    } catch (_) {}
    final list = await ApiService().loadAllCRFs();
    if (!mounted) return;
    setState(() => _crfList = _ownSiteOnly(list.reversed.toList()));
  }

  List<CRF> _ownSiteOnly(List<CRF> list) {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.role.isGlobal) return list;
    final site = (user.siteName ?? '').trim();
    if (site.isEmpty) return list;
    return list.where((c) => c.site == site).toList();
  }

  Future<void> _loadDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList("screening_draft_keys") ?? [];

    // Remove drafts that have already been submitted
    final submittedIds = _crfList.map((c) => c.screeningId).toSet();
    final List<Map<String, dynamic>> drafts = [];
    final List<String> validKeys = [];

    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final screeningId = data["screeningId"] as String? ?? "";

      if (screeningId.isNotEmpty && submittedIds.contains(screeningId)) {
        await prefs.remove(key);
        continue;
      }
      validKeys.add(key);
      drafts.add({
        "key": key,
        "screeningId": screeningId.isEmpty ? "Draft" : screeningId,
        "motherName":
            "${data["motherFirstName"] ?? ""} ${data["motherSurname"] ?? ""}",
      });
    }
    await prefs.setStringList("screening_draft_keys", validKeys);
    if (!mounted) return;
    setState(() => _drafts = drafts);
  }

  // ================= HELPERS =================

  bool _isEligible(CRF c) =>
      normalizeScreeningStatus(c.eligibilityStatus) == "Eligible";

  bool _isNotEligible(CRF c) =>
      normalizeScreeningStatus(c.eligibilityStatus) == "Not Eligible";

  bool _isScreenFailure(CRF c) =>
      normalizeScreeningStatus(c.eligibilityStatus) == "Screen Failure";

  bool _isPending(CRF c) =>
      normalizeScreeningStatus(c.eligibilityStatus) == "Pending";

  bool _isExcluded(CRF c) => _isNotEligible(c) || _isScreenFailure(c);

  String _babyOfLabel(CRF c) {
    final first = c.motherFirstName.trim();
    final upper = first.toUpperCase();
    if (first.isEmpty || upper == 'DRAFT' || upper == 'NAME PENDING') {
      return c.enrollmentId.isNotEmpty ? c.enrollmentId : c.screeningId;
    }
    return 'B/o $first';
  }

  List<CRF> get _filteredCrfs {
    var list = _crfList.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.screeningId.toLowerCase().contains(q) ||
          c.motherFirstName.toLowerCase().contains(q) ||
          c.enrollmentId.toLowerCase().contains(q) ||
          c.maternalUid.toLowerCase().contains(q);
    }).toList();

    switch (_filterStatus) {
      case "Eligible":
        return list.where(_isEligible).toList();
      case "Not Eligible":
        return list.where(_isNotEligible).toList();
      case "Screen Failure":
        return list.where(_isScreenFailure).toList();
      case "Pending":
        return list.where(_isPending).toList();
      case "Excluded": // legacy
        return list.where(_isExcluded).toList();
      case "Incomplete": // legacy
        return list.where(_isPending).toList();
      default:
        return list;
    }
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    final total      = _crfList.length;
    final eligible   = _crfList.where(_isEligible).length;
    final excluded   = _crfList.where(_isExcluded).length;
    final incomplete = _crfList.where(_isPending).length;

    final Map<String, int> exclusionMap = {};
    for (final crf in _crfList) {
      if (_isExcluded(crf)) {
        for (var r in (crf.exclusionReason ?? "").split(";")) {
          final clean = r.trim();
          if (clean.isNotEmpty) {
            exclusionMap[clean] = (exclusionMap[clean] ?? 0) + 1;
          }
        }
      }
    }
    final consentRefused =
        _crfList.where((c) => c.consentStatus == "No").length;
    final notApproached = _crfList
        .where((c) => c.consentStatus.toLowerCase().contains("not approached"))
        .length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      floatingActionButton: _buildFAB(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgGradTop, _bg],
            stops: [0.0, 0.35],
          ),
        ),
        child: RefreshIndicator(
          color: _primary,
          backgroundColor: _surface,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (_isRefreshing)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    color: _primary,
                    backgroundColor: _primarySoft,
                    minHeight: 3,
                  ),
                ),
              const SizedBox(height: 6),

              _buildStatsRow(total, eligible, excluded, incomplete,
                  exclusionMap, consentRefused, notApproached),
              const SizedBox(height: 14),

              _buildFilterChips(),
              const SizedBox(height: 14),

              _buildSearch(),
              const SizedBox(height: 22),

              if (_drafts.isNotEmpty) ...[
                _sectionHeader(
                  "Pending Drafts", _drafts.length, _warning,
                  () => setState(() => _showDrafts = !_showDrafts),
                  _showDrafts,
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _showDrafts
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Column(children: _drafts.map(_draftCard).toList()),
                  secondChild: const SizedBox.shrink(),
                ),
                const SizedBox(height: 22),
              ],

              _sectionHeader(
                "Screened Patients", _filteredCrfs.length, _primary,
                () => setState(() => _showScreened = !_showScreened),
                _showScreened,
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _showScreened
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: _isInitialLoad
                    ? const SkeletonPatientList()
                    : (_filteredCrfs.isEmpty
                        ? _emptyState()
                        : Column(children: _filteredCrfs.map(_screenedCard).toList())),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      toolbarHeight: 66,
      automaticallyImplyLeading: false,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _borderLight),
      ),
      title: Row(children: [
        // Logo container with blue tint
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primary, _primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: _primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset("assets/images/logo.png",
                fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 11),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text("PORTAL",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: _textPrimary)),
          const SizedBox(height: 1),
          Text("Screening Dashboard",
              style: TextStyle(
                  fontSize: 11,
                  color: _primary.withOpacity(0.7),
                  fontWeight: FontWeight.w500)),
        ]),
        const Spacer(),
        _appBarBtn(
          icon: Icons.sync_rounded,
          color: _textSecondary,
          bg: _surfaceAlt,
          border: _border,
          onTap: _refresh,
        ),
        const SizedBox(width: 8),
        _appBarBtn(
          icon: Icons.logout_rounded,
          color: _danger,
          bg: _dangerSoft,
          border: _danger.withOpacity(0.2),
          onTap: _confirmLogout,
        ),
      ]),
    );
  }

  Widget _appBarBtn({
    required IconData icon,
    required Color color,
    required Color bg,
    required Color border,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Logout",
            style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text("Are you sure you want to logout?",
            style: TextStyle(color: _textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel",
                  style: TextStyle(color: _textTertiary, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Logout",
                  style: TextStyle(color: _danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      // AuthGate in main.dart watches auth.status and shows LoginScreen automatically
    }
  }

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [_primary, _primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        backgroundColor: Colors.transparent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
        label: const Text("New Screening",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: .3)),
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ScreeningForm(loadDraft: false)));
          await _loadCrfs();
        },
      ),
    );
  }

  // ── STATS ROW ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow(
    int total, int eligible, int excluded, int incomplete,
    Map<String, int> exclusionMap, int consentRefused, int notApproached,
  ) {
    return Row(children: [
      Expanded(child: _statCard("Total",    total,      _primary, Icons.people_alt_rounded,      null)),
      const SizedBox(width: 9),
      Expanded(child: _statCard("Eligible", eligible,   _success, Icons.check_circle_rounded,    null)),
      const SizedBox(width: 9),
      Expanded(child: _statCard("Excluded", excluded,   _danger,  Icons.block_rounded,
          () => _showExcludedBreakdown(exclusionMap, consentRefused, notApproached))),
      const SizedBox(width: 9),
      Expanded(child: _statCard("Pending",  incomplete, _warning, Icons.pending_rounded,         null)),
    ]);
  }

  Widget _statCard(String label, int count, Color color, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 13),
            ),
            if (onTap != null) ...[
              const Spacer(),
              Icon(Icons.info_outline_rounded,
                  color: color.withOpacity(0.4), size: 13),
            ],
          ]),
          const SizedBox(height: 8),
          Text("$count",
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                  color: _textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .3)),
          const SizedBox(height: 7),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── FILTER CHIPS ──────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    final filters = [
      ("All",            _primary, Icons.grid_view_rounded),
      ("Eligible",       _success, Icons.check_circle_outline_rounded),
      ("Not Eligible",   _warning, Icons.warning_amber_rounded),
      ("Screen Failure", _danger,  Icons.block_outlined),
      ("Pending",        _warning, Icons.pending_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final selected = _filterStatus == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filterStatus = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? f.$2 : _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? f.$2 : _border,
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: f.$2.withOpacity(0.22),
                          blurRadius: 8, offset: const Offset(0, 3))]
                      : [],
                ),
                child: Row(children: [
                  Icon(f.$3,
                      size: 13,
                      color: selected ? Colors.white : _textTertiary),
                  const SizedBox(width: 5),
                  Text(f.$1,
                      style: TextStyle(
                          color: selected ? Colors.white : _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── SEARCH ────────────────────────────────────────────────────────────────

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: _textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: "Search by ID, mother name, or baby UID…",
          hintStyle: const TextStyle(color: _textTertiary, fontSize: 13),
          filled: false,
          prefixIcon: const Icon(Icons.search_rounded, color: _textTertiary, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: _textTertiary, size: 17),
                  onPressed: () => setState(() => _searchQuery = ""),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  // ── SECTION HEADER ────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, int count, Color color,
      VoidCallback onTap, bool expanded) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 4, height: 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Text("$count",
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ),
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: _textTertiary, size: 20),
          ),
        ]),
      ),
    );
  }

  // ── EMPTY STATE ───────────────────────────────────────────────────────────

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _primarySoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.search_off_rounded,
              color: _primary, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          _searchQuery.isNotEmpty
              ? "No results for \"$_searchQuery\""
              : "No patients in this category",
          style: const TextStyle(
              color: _textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  // ── DRAFT CARD ────────────────────────────────────────────────────────────

  Widget _draftCard(Map<String, dynamic> draft) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _warning.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: _warning.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: _warningSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _warning.withOpacity(0.25)),
          ),
          child: const Icon(Icons.pending_actions_rounded,
              color: _warning, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(draft["screeningId"],
                style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 2),
            Text(draft["motherName"] ?? "",
                style: const TextStyle(color: _textTertiary, fontSize: 11)),
          ]),
        ),
        GestureDetector(
          onTap: () async {
            await Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => ScreeningForm(
                        loadDraft: true, draftKey: draft["key"])));
            await _refresh();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: _warningSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _warning.withOpacity(0.35)),
            ),
            child: Row(children: const [
              Icon(Icons.edit_rounded, color: _warning, size: 14),
              SizedBox(width: 5),
              Text("Resume",
                  style: TextStyle(
                      color: _warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── SCREENED CARD ─────────────────────────────────────────────────────────

  Widget _screenedCard(CRF crf) {
    final eligible = _isEligible(crf);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: eligible ? _success.withOpacity(0.3) : _border,
        ),
        boxShadow: [
          BoxShadow(
            color: eligible
                ? _success.withOpacity(0.07)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(children: [

        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
          child: Row(children: [

            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: eligible
                      ? [_success, const Color(0xFF34A853)]
                      : [_primary, _primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (eligible ? _success : _primary).withOpacity(0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  crf.motherFirstName.isNotEmpty
                      ? crf.motherFirstName[0].toUpperCase()
                      : "?",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_babyOfLabel(crf),
                    style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _primarySoft,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(crf.screeningId,
                        style: const TextStyle(
                            color: _primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text("${crf.gestationWeeks}w ${crf.gestationDays}d",
                      style: const TextStyle(color: _textTertiary, fontSize: 11)),
                ]),
              ]),
            ),

            _statusChip(crf.eligibilityStatus),
          ]),
        ),

        // ── Divider ──
        Container(height: 1, color: _borderLight, margin: const EdgeInsets.symmetric(horizontal: 13)),

        // ── Actions ──
        Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
          child: Row(children: [

            _actionBtn(
              icon: Icons.picture_as_pdf_rounded,
              label: "PDF",
              color: _danger,
              softColor: _dangerSoft,
              onTap: () => _generatePdf(crf),
            ),

            const SizedBox(width: 7),

            if (eligible) ...[
              _actionBtn(
                icon: Icons.monitor_heart_rounded,
                label: "Helpers",
                color: _warning,
                softColor: _warningSoft,
                onTap: () => _showHelperSheet(crf),
              ),
              const SizedBox(width: 7),
              _actionBtn(
                icon: Icons.baby_changing_station_rounded,
                label: "Form B1",
                color: _success,
                softColor: _successSoft,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => FormBBirthResuscitation(
                          screeningId: crf.screeningId,
                          maternalUid: crf.maternalUid,
                          motherName: "${crf.motherFirstName} ${crf.motherSurname}",
                          motherPhone: crf.motherPhone,
                          husbandPhone: crf.husbandPhone,
                          gestWeeks: crf.gestationWeeks,
                          gestDays: crf.gestationDays,
                          siteId: crf.site.isNotEmpty ? crf.site : crf.siteId,
                          screeningDateTime: crf.screeningDateTime,
                        ))),
              ),
            ],

            if (!eligible) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Icon(Icons.lock_outline_rounded, color: _textTertiary, size: 13),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text("Helpers for eligible patients only",
                          style: TextStyle(color: _textTertiary, fontSize: 10),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 7),
              _actionBtn(
                icon: Icons.edit_note_rounded,
                label: "Edit",
                color: _grey,
                softColor: _greySoft,
                onTap: () async {},
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Action button ─────────────────────────────────────────────────────────

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color softColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(
            color: softColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HELPER BOTTOM SHEET ──────────────────────────────────────────────────

  void _showHelperSheet(CRF crf) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _warningSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warning.withOpacity(0.3)),
              ),
              child: const Icon(Icons.monitor_heart_rounded, color: _warning, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Daily Helper Forms",
                  style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
              Text(_babyOfLabel(crf),
                  style: const TextStyle(color: _textSecondary, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 16),
          const Divider(color: _borderLight),
          const SizedBox(height: 8),
          _helperTile("fio2", Icons.air_rounded,
              "Helper Form 1 — FiO₂ AUC", "Supplemental O₂ days from Helper Form 2",
              const Color(0xFF0284C7), crf),
          _helperTile("resp", Icons.favorite_outline_rounded,
              "Helper Form 2 — Resp / CV / Neuro", "Respiratory, cardiac & neurological",
              _success, crf),
          _helperTile("infect", Icons.biotech_outlined,
              "Helper Form 3 — Infect / GI / Hema", "Infection, feeds & haematology",
              _danger, crf),
          _helperTile("metab", Icons.science_outlined,
              "Helper Form 4 — Metab / Renal / Vasc / Eye", "Metabolic, renal, lines & ROP",
              _warning, crf),
          _helperTile("minimal_monitoring", Icons.monitor_heart_outlined,
              "Helper Form 5 — Minimal Monitoring", "Same-day CV/resp/metab/GI/neuro/hema scratchpad",
              const Color(0xFF7C3AED), crf),
        ]),
      ),
    );
  }

  Widget _helperTile(String value, IconData icon, String title,
      String subtitle, Color color, CRF crf) {
    return GestureDetector(
      onTap: () { Navigator.pop(context); _openHelper(value, crf); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: _textSecondary, fontSize: 11)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withOpacity(0.5), size: 13),
        ]),
      ),
    );
  }

  // ── HELPER NAVIGATION ────────────────────────────────────────────────────

  void _openHelper(String value, CRF crf) {
    // Helpers are keyed by enrollment_id on the backend/web — never screeningId.
    final enrollment = crf.enrollmentId.trim();
    if (enrollment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Enrollment ID required for helper forms — complete Form B1 randomisation first.'),
      ));
      return;
    }
    final gestation  = "${crf.gestationWeeks}w ${crf.gestationDays}d";
    final motherName = "${crf.motherFirstName} ${crf.motherSurname}";
    final babyUid    = crf.maternalUid;

    Widget? screen;
    switch (value) {
      case "fio2":
        screen = HelperFiO2AUC(enrollmentId: enrollment, gestation: gestation,
            motherName: motherName, babyUid: babyUid); break;
      case "resp":
        screen = HelperForm2RespCvNeuro(enrollmentId: enrollment, gestation: gestation,
            motherName: motherName, babyUid: babyUid); break;
      case "infect":
        screen = HelperForm3InfectGIHema(enrollmentId: enrollment, gestation: gestation,
            motherName: motherName, babyUid: babyUid); break;
      case "metab":
        screen = HelperForm4MetabRenalVascEye(enrollmentId: enrollment, gestation: gestation,
            motherName: motherName, babyUid: babyUid); break;
      case "minimal_monitoring":
        screen = HelperForm5MinimalMonitoring(enrollmentId: enrollment, gestation: gestation,
            motherName: motherName, babyUid: babyUid); break;
    }
    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    }
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Future<void> _generatePdf(CRF crf) async {
    try {
      final apiService = ApiService();
      final formB = await apiService.loadFormB(crf.screeningId);
      final formC = await apiService.loadFormC(crf.screeningId);

      BirthResuscitationData? birth;
      final eid = (formB?.enrollmentId.trim().isNotEmpty == true)
          ? formB!.enrollmentId.trim()
          : crf.enrollmentId.trim();
      if (eid.isNotEmpty) {
        try {
          final remote =
              await FormsApiService.instance.loadBirthResuscitation(eid);
          if (remote != null) {
            birth = BirthResuscitationData.fromJson(remote);
          }
        } catch (_) {}
      }

      final file = await PdfService.generateFullTrialPdf(
        crf: crf,
        formB: formB,
        formC: formC,
        birth: birth,
      );
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("PDF error: $e"),
          backgroundColor: _danger,
        ));
      }
    }
  }

  // ── STATUS CHIP ───────────────────────────────────────────────────────────

  Widget _statusChip(String eligibilityRaw) {
    final label = normalizeScreeningStatus(eligibilityRaw);
    final color = screeningStatusColor(label);
    final soft = color.withOpacity(0.12);
    final icon = switch (label) {
      'Eligible' => Icons.check_circle_rounded,
      'Screen Failure' => Icons.block_rounded,
      'Not Eligible' => Icons.warning_amber_rounded,
      _ => Icons.pending_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── EXCLUDED BREAKDOWN ────────────────────────────────────────────────────

  void _showExcludedBreakdown(Map<String, int> exclusionMap,
      int consentRefusedCount, int notApproachedCount) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: const [
          Icon(Icons.bar_chart_rounded, color: _danger, size: 20),
          SizedBox(width: 10),
          Text("Excluded Breakdown",
              style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ...exclusionMap.entries.map((e) => _breakdownRow(e.key, e.value, _danger)),
            if (exclusionMap.isNotEmpty) const Divider(color: _borderLight),
            _breakdownRow("Consent Refused", consentRefusedCount, _purple),
            _breakdownRow("Not Approached", notApproachedCount, _grey),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close",
                style: TextStyle(color: _primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withOpacity(0.7))),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(color: _textSecondary, fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Text("$count",
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ]),
    );
  }
}