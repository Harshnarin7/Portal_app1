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

