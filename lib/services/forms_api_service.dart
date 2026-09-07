// lib/services/forms_api_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Replaces SharedPreferences for Form B, Form C, and Helper Forms 2/3/4.
// All data saved to the PORTAL backend — visible to all nurses on same site.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'api_client.dart';

class FormsApiService {
  FormsApiService._();
  static final FormsApiService instance = FormsApiService._();

  // ── Form B + Form C — Birth & Resuscitation ────────────────────────────
  // IMPORTANT: on the web portal, Form B and Form C are ONE form
  // (BirthResuscitationForm.jsx / `birth_resuscitation` table). Our app
  // splits the same record across two screens for UX reasons, but BOTH
  // screens must read/write the same backend endpoint below, or data
  // entered on one screen will never appear on the web portal.
  //
  // `body` must contain exact snake_case backend keys — build it with
  // BirthResuscitationData.toJson() from models/birth_resuscitation.dart.
  //
  // Flow: randomised saves use the nurse-entered enrollment_id.
  // Not-randomised / no-PPV saves use NR-{screening_id} so they still
  // land in birth_resuscitation and appear on the web form.

  Future<Map<String, dynamic>> saveBirthResuscitation(
    Map<String, dynamic> body,
  ) async {
    return await ApiClient.instance.post('/birth-resuscitation/', body: body);
  }

  Future<Map<String, dynamic>> updateBirthResuscitation(
    String enrollmentId,
    Map<String, dynamic> body,
  ) async {
    return await ApiClient.instance
        .put('/birth-resuscitation/$enrollmentId', body: body);
  }

  Future<Map<String, dynamic>?> loadBirthResuscitation(
    String enrollmentId,
  ) async {
    try {
      return await ApiClient.instance.get('/birth-resuscitation/$enrollmentId');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // Deprecated aliases kept only so old call sites don't break the build
  // while screens are migrated — remove once form_b/form_c screens are
  // updated to call saveBirthResuscitation() directly.
  @Deprecated('Use saveBirthResuscitation() — this endpoint does not exist on the backend')
  Future<void> saveFormB({required String screeningId}) async {
    throw UnimplementedError(
      'saveFormB() is removed — call FormsApiService.instance.saveBirthResuscitation() '
      'with a BirthResuscitationData().toJson() payload instead.',
    );
  }

  @Deprecated('Use saveBirthResuscitation() — this endpoint does not exist on the backend')
  Future<void> saveFormC({required String screeningId, required Map<String, dynamic> formData}) async {
    throw UnimplementedError(
      'saveFormC() is removed — call FormsApiService.instance.saveBirthResuscitation() '
      'with a BirthResuscitationData().toJson() payload instead.',
    );
  }

  // ── Helper Forms (2, 3, 4) ────────────────────────────────────────────────
  // form_type values:
  //   'resp_cv_neuro'         → Helper Form 2
  //   'infect_gi_hema'        → Helper Form 3
  //   'metab_renal_vasc_eye'  → Helper Form 4

  Future<void> saveHelperForm({
    required String babyUid,
    required String formType,
    required Map<String, dynamic> records,
    String? updatedBy,
  }) async {
    await ApiClient.instance.post('/forms/helper/save', body: {
      'baby_uid'    : babyUid,
      'form_type'   : formType,
      'records_json': jsonEncode(records),
      'updated_by'  : updatedBy,
    });
  }

  Future<Map<String, dynamic>> loadHelperForm({
    required String babyUid,
    required String formType,
  }) async {
    try {
      return await ApiClient.instance.get('/forms/helper/$babyUid/$formType');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return {'records': {}};
      rethrow;
    }
  }

  // ── FiO2 AUC Helper Form ─────────────────────────────────────────────────
  // FIX: was calling /forms/fio2/save and /forms/fio2/{babyUid} — neither
  // exists on the backend at all. Every save silently 404'd and fell back
  // to local-only storage; this form has never actually synced to the
  // server. Real endpoints are POST/PUT /fio2-auc/, keyed by enrollmentId
  // (not babyUid — the backend's FiO2AUC table has no baby_uid column at
  // all, only enrollment_id), and expect pre-computed summary values
  // (total_auc, mean_daily_fio2, excess_o2_auc) plus the raw log data.

  Future<void> saveFiO2({
    required String enrollmentId,
    required List<Map<String, dynamic>> blocks,
    required double totalAuc,
    required double meanDailyFio2,
    required double excessO2Auc,
    bool hasExistingRecord = false,
  }) async {
    final body = {
      'enrollment_id'    : enrollmentId,
      'total_auc'        : totalAuc,
      'mean_daily_fio2'  : meanDailyFio2,
      'excess_o2_auc'    : excessO2Auc,
      // Same shape as web FiO2AUC.jsx:
      // [{ day, block: "0-12h"|"12-24h", start_time, entries:[{fio2,dur}] }]
      'fio2_logs'        : blocks,
    };
    // Always PUT — backend upserts the latest row (creates if missing).
    // Avoids POST creating a second row when web already saved for this
    // enrollment (GET returns newest-first, which would desync the other client).
    try {
      await ApiClient.instance.put('/fio2-auc/$enrollmentId', body: body);
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        await ApiClient.instance.post('/fio2-auc/', body: body);
        return;
      }
      rethrow;
    }
  }

  // ── Helper Form 5 — Minimal Monitoring Log ──────────────────────────────
  // Dedicated structured endpoints (NOT the generic /forms/helper/save blob —
  // MinimalMonitoringDayLog has real typed columns, mirrored in
  // models/minimal_monitoring.dart / MinimalMonitoringDayCreate on the
  // backend). One row per (enrollment_id, record_date); the "today" sheet
  // clears automatically after 8am local time (server-side boundary_hour),
  // matching MinimalMonitoringLog.jsx. GET never creates a row; PUT
  // upserts it — same pattern as the web portal's persist().

  Future<Map<String, dynamic>> loadMinimalMonitoringToday(
    String enrollmentId,
  ) async {
    // Match web MinimalMonitoringLog.jsx — before 08:00 local, "today"
    // is still the previous calendar date.
    return await ApiClient.instance.get(
      '/minimal-monitoring/$enrollmentId/today?boundary_hour=8',
    );
  }

  Future<Map<String, dynamic>> saveMinimalMonitoringToday(
    String enrollmentId,
    Map<String, dynamic> body,
  ) async {
    return await ApiClient.instance.put(
      '/minimal-monitoring/$enrollmentId/today?boundary_hour=8',
      body: body,
    );
  }

  Future<Map<String, dynamic>?> loadFiO2(String enrollmentId) async {
    try {
      // Backend returns a LIST (most recent first) — most callers just
      // want the latest entry, matching update_fio2_auc's own "most
      // recent record" semantics.
      final list = await ApiClient.instance.getList('/fio2-auc/$enrollmentId');
      if (list.isEmpty) return null;
      return list.first as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Helper Form 2 day summary — FiO₂ AUC builds days from supp_o2=Yes rows
  /// (same as web FiO2AUC.jsx syncDaysFromHelper2).
  Future<List<Map<String, dynamic>>> loadRespCvNeuroSummary(
    String enrollmentId,
  ) async {
    try {
      final list = await ApiClient.instance
          .getList('/resp-cv-neuro/$enrollmentId/summary');
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  // ── Helper Form 2 — Resp / CV / Neuro (NICU day log) ─────────────────────
  // Real endpoints match RespCVNeuroLog.jsx — NOT the dead /forms/helper blob.

  Future<Map<String, dynamic>?> loadRespCvNeuroDay(
    String enrollmentId,
    int nicuDay,
  ) async {
    try {
      return await ApiClient.instance
          .get('/resp-cv-neuro/$enrollmentId/$nicuDay');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST upserts if the day already exists (backend create_resp_cv_neuro_day).
  Future<Map<String, dynamic>> saveRespCvNeuroDay(
    Map<String, dynamic> body, {
    bool alreadyExists = false,
  }) async {
    final eid = body['enrollment_id']?.toString() ?? '';
    final day = body['nicu_day'];
    if (alreadyExists && eid.isNotEmpty && day != null) {
      try {
        return await ApiClient.instance
            .put('/resp-cv-neuro/$eid/$day', body: body);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    return await ApiClient.instance.post('/resp-cv-neuro/', body: body);
  }

  Future<Map<String, dynamic>> submitRespCvNeuroDay({
    required String enrollmentId,
    required int nicuDay,
    required String submittedBy,
    DateTime? submittedAt,
  }) async {
    return await ApiClient.instance.patch(
      '/resp-cv-neuro/$enrollmentId/$nicuDay/submit',
      body: {
        'submission_status': 'submitted',
        'submitted_at': (submittedAt ?? DateTime.now().toUtc()).toIso8601String(),
        'submitted_by': submittedBy,
      },
    );
  }

  Future<Map<String, dynamic>> loadDay1Date(String enrollmentId) async {
    return await ApiClient.instance
        .get('/nicu-admission/$enrollmentId/day1-date');
  }

  Future<Map<String, dynamic>> saveDay1Date(
    String enrollmentId,
    String day1DateYmd,
  ) async {
    return await ApiClient.instance.put(
      '/nicu-admission/$enrollmentId/day1-date',
      body: {'day1_date': day1DateYmd},
    );
  }

  // ── Helper Form 3 — Infect / GI / Hema ───────────────────────────────────

  Future<List<Map<String, dynamic>>> loadInfectGiHemaSummary(
    String enrollmentId,
  ) async {
    try {
      final list = await ApiClient.instance
          .getList('/infect-gi-hema/$enrollmentId/summary');
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadInfectGiHemaDay(
    String enrollmentId,
    int nicuDay,
  ) async {
    try {
      return await ApiClient.instance
          .get('/infect-gi-hema/$enrollmentId/$nicuDay');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveInfectGiHemaDay(
    Map<String, dynamic> body, {
    bool alreadyExists = false,
  }) async {
    final eid = body['enrollment_id']?.toString() ?? '';
    final day = body['nicu_day'];
    if (alreadyExists && eid.isNotEmpty && day != null) {
      try {
        return await ApiClient.instance
            .put('/infect-gi-hema/$eid/$day', body: body);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    return await ApiClient.instance.post('/infect-gi-hema/', body: body);
  }

  Future<Map<String, dynamic>> submitInfectGiHemaDay({
    required String enrollmentId,
    required int nicuDay,
    required String submittedBy,
    DateTime? submittedAt,
  }) async {
    return await ApiClient.instance.patch(
      '/infect-gi-hema/$enrollmentId/$nicuDay/submit',
      body: {
        'submission_status': 'submitted',
        'submitted_at':
            (submittedAt ?? DateTime.now().toUtc()).toIso8601String(),
        'submitted_by': submittedBy,
      },
    );
  }

  // ── Helper Form 4 — Metab / Renal / Vasc / Eye ───────────────────────────

  Future<List<Map<String, dynamic>>> loadMetabRenalVascEyeSummary(
    String enrollmentId,
  ) async {
    try {
      final list = await ApiClient.instance
          .getList('/metab-renal-vasc-eye/$enrollmentId/summary');
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadMetabRenalVascEyeDay(
    String enrollmentId,
    int nicuDay,
  ) async {
    try {
      // Backend returns JSON null (200) for empty days — not 404.
      return await ApiClient.instance
          .getNullable('/metab-renal-vasc-eye/$enrollmentId/$nicuDay');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveMetabRenalVascEyeDay(
    Map<String, dynamic> body, {
    bool alreadyExists = false,
  }) async {
    final eid = body['enrollment_id']?.toString() ?? '';
    final day = body['nicu_day'];
    if (alreadyExists && eid.isNotEmpty && day != null) {
      try {
        return await ApiClient.instance
            .put('/metab-renal-vasc-eye/$eid/$day', body: body);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    return await ApiClient.instance
        .post('/metab-renal-vasc-eye/', body: body);
  }

  Future<Map<String, dynamic>> submitMetabRenalVascEyeDay({
    required String enrollmentId,
    required int nicuDay,
    required String submittedBy,
    DateTime? submittedAt,
  }) async {
    return await ApiClient.instance.patch(
      '/metab-renal-vasc-eye/$enrollmentId/$nicuDay/submit',
      body: {
        'submission_status': 'submitted',
        'submitted_at':
            (submittedAt ?? DateTime.now().toUtc()).toIso8601String(),
        'submitted_by': submittedBy,
      },
    );
  }
}