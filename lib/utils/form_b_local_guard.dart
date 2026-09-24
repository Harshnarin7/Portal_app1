// Guards device-cached Form B so a reused screening ID (server wipe, re-fill
// of Form A) cannot paint another baby's B1 fields onto a new patient.

import '../models/form_b.dart';

/// True when [local] is safe to show for this screening / mother.
bool localFormBIsForPatient({
  required FormB local,
  required String screeningId,
  String maternalUid = '',
  String motherFirstName = '',
  DateTime? screeningCreatedAt,
  bool serverHasBirthLink = false,
}) {
  if (local.screeningId.isNotEmpty && local.screeningId != screeningId) {
    return false;
  }

  final localUid = local.maternalUid.trim();
  final widgetUid = maternalUid.trim();
  if (localUid.isNotEmpty &&
      widgetUid.isNotEmpty &&
      localUid != widgetUid) {
    return false;
  }

  final localFirst = local.motherFirstName.trim().toLowerCase();
  final widgetFirst = motherFirstName.trim().toLowerCase();
  if (localFirst.isNotEmpty &&
      widgetFirst.isNotEmpty &&
      localFirst != widgetFirst) {
    return false;
  }

  final saved = local.savedAt;
  if (screeningCreatedAt != null && saved != null) {
    // Cached B1 is older than this screening row → leftover after ID reuse.
    if (screeningCreatedAt.isAfter(saved.add(const Duration(seconds: 5)))) {
      return false;
    }
  }

  // Form A-only (web Form B still empty): ignore leftover device cache unless
  // this APK actually started B1 after the screening existed.
  if (!serverHasBirthLink && saved == null) {
    return false;
  }

  // Legacy cache (no identity, no timestamp): cannot prove it belongs to a
  // newly created screening after a wipe that reused 01-0001. Drop it; a
  // server birth_resuscitation row still loads via GET.
  if (saved == null &&
      localUid.isEmpty &&
      localFirst.isEmpty &&
      screeningCreatedAt != null) {
    return false;
  }

  return true;
}

/// Only the enrollment already stored on the screening row (same as web).
/// Never invents `NR-{screeningId}` — that pulled another baby's Form B when
/// Form A had not linked enrollment yet.
String linkedBirthEnrollmentId(String screeningEnrollment) =>
    screeningEnrollment.trim();

/// Server birth row belongs to this Form A screening.
bool remoteBirthRowIsForScreening({
  required String? remoteScreeningId,
  required String screeningId,
}) {
  final remote = (remoteScreeningId ?? '').trim();
  if (remote.isEmpty) return true;
  return remote == screeningId.trim();
}

/// Helpers (DMS + 2–5) open with the screening's linked enrollment, or a
/// birth row already verified for this screening. Never leftover Form B.
String linkedHelperEnrollmentId({
  required String screeningEnrollment,
  String remoteEnrollmentId = '',
}) {
  final linked = screeningEnrollment.trim();
  if (linked.isNotEmpty) return linked;
  return remoteEnrollmentId.trim();
}

/// GET /birth-resuscitation/{eid} is safe to use for this Form A.
bool helperBirthRowMatchesScreening({
  required Map<String, dynamic>? birth,
  required String screeningId,
}) {
  if (screeningId.trim().isEmpty) return true;
  return remoteBirthRowIsForScreening(
    remoteScreeningId: birth?['screening_id']?.toString(),
    screeningId: screeningId,
  );
}

/// Device helper/FiO₂ draft is safe to paint for this screening.
///
/// [serverConfirmedEmpty]: GET returned 404 / empty (web has no row). Drop
/// legacy drafts that have no screening_id — those are leftover after an ID
/// reuse. Keep drafts stamped with this screening (unsynced work).
bool helperLocalDraftIsForScreening({
  required Map<String, dynamic> draft,
  required String screeningId,
  required bool serverConfirmedEmpty,
}) {
  final draftSid = (draft['screening_id'] ?? '').toString().trim();
  final sid = screeningId.trim();
  if (sid.isNotEmpty && draftSid.isNotEmpty && draftSid != sid) {
    return false;
  }
  if (serverConfirmedEmpty && draftSid.isEmpty) {
    return false;
  }
  return true;
}
