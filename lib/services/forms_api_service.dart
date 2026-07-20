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

  Future<void> saveFiO2({
    required String babyUid,
    required Map<String, dynamic> blocks,
    String? updatedBy,
  }) async {
    await ApiClient.instance.post('/forms/fio2/save', body: {
      'baby_uid'   : babyUid,
      'blocks_json': jsonEncode(blocks),
      'updated_by' : updatedBy,
    });
  }

  Future<Map<String, dynamic>> loadFiO2(String babyUid) async {
    try {
      return await ApiClient.instance.get('/forms/fio2/$babyUid');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return {'blocks': {}};
      rethrow;
    }
  }
}