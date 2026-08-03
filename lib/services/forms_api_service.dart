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
  // Flow: first save (no enrollment_id yet, e.g. from Form B before
  // randomization) -> POST. Every save after enrollment_id exists -> the
  // backend's POST handler itself upserts by enrollment_id, so POST is
  // safe to call repeatedly; PUT is available if you already know the
  // enrollment_id and want an explicit update-only call.

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
      'fio2_logs'        : blocks,
    };
    if (hasExistingRecord) {
      await ApiClient.instance.put('/fio2-auc/$enrollmentId', body: body);
    } else {
      await ApiClient.instance.post('/fio2-auc/', body: body);
    }
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
}