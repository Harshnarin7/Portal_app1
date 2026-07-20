// lib/services/screening_api_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Talks to the PORTAL backend's real `/screenings/` endpoints — the exact
// same REST resource the web portal's ScreeningForm.jsx uses. The payload
// keys below intentionally mirror ScreeningForm.jsx's buildPayloadFrom() /
// backend/schemas.py ScreeningCreate so that a screening created on mobile
// looks identical, field-for-field, to one created on the web portal and
// both sides can read/update the same record.
// ─────────────────────────────────────────────────────────────────────────────

import 'api_client.dart';

class ScreeningApiService {
  ScreeningApiService._();
  static final ScreeningApiService instance = ScreeningApiService._();

  // ── Create or update a screening record on the real backend ───────────────
  // Pass `existingScreeningId` (the server-assigned screening_id, e.g.
  // "01-0007") to PUT/update an existing record; leave it null to POST/create
  // a new one. The backend auto-generates the screening_id on create if none
  // is supplied — same behaviour as the web portal.
  //
  // Returns the decoded JSON response, which includes the authoritative
  // `screening_id` and `enrollment_id` assigned by the server.
  Future<Map<String, dynamic>> syncScreening({
    required Map<String, dynamic> payload,
    String? existingScreeningId,
  }) async {
    if (existingScreeningId != null && existingScreeningId.isNotEmpty) {
      return ApiClient.instance.put('/screenings/$existingScreeningId', body: payload);
    }
    return ApiClient.instance.post('/screenings/', body: payload);
  }

  // ── Fetch an existing screening by its screening_id ────────────────────────
  Future<Map<String, dynamic>?> getScreening(String screeningId) async {
    try {
      return await ApiClient.instance.get('/screenings/$screeningId');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── Fetch PII (name/contact/UID) for a screening ────────────────────────
  // /screenings/ and /screenings/{id} BOTH return ScreeningClinicalOut,
  // which is deliberately de-identified — the backend stores mother/husband
  // name, phone, maternal UID, and hospital admission number in a SEPARATE
  // participant_pii table (DPDP/ICMR pseudonymisation — see backend
  // pii_service.py) and only ever returns them from /pii/screening/{id}.
  // Returns null on 403 (user not authorized to view PII for this site) or
  // 404 (no PII record saved for this screening yet) instead of throwing,
  // so the caller can just fall back to blank/"?" for that one patient.
  Future<Map<String, dynamic>?> getPii(String screeningId) async {
    try {
      return await ApiClient.instance.get('/pii/screening/$screeningId');
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 403) return null;
      rethrow;
    }
  }

  // ── Get all patients for current user's site ──────────────────────────────
  // FIX: was calling /screening/patients, which doesn't exist on the backend
  // — every call silently failed and fell back to local-only device storage,
  // meaning the dashboard never showed real screenings from the server at
  // all. /screenings/ is the real, working, site-scoped list endpoint.
  Future<List<Map<String, dynamic>>> getPatients() async {
    final data = await ApiClient.instance.getList('/screenings/');
    return data.cast<Map<String, dynamic>>();
  }

  // ── Get dashboard stats ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats() async {
    return ApiClient.instance.get('/screening/stats');
  }
}