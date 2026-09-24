// List/card name for a screening — same rules as web View Entries
// `formatParticipantListName`:
//   Form A only → mother's first name
//   Form B started (draft or saved) → "B/o {mother first name}"
// Mobile treats a linked screening.enrollment_id as Form B started
// (enrollment is assigned when B1 begins).

bool isPlaceholderPatientName(String? first, [String? surname]) {
  final f = (first ?? '').trim().toUpperCase();
  final s = (surname ?? '').trim().toUpperCase();
  if (f == 'DRAFT' || f == 'NAME PENDING') return true;
  if (s == 'DRAFT') return true;
  return false;
}

String participantListName({
  required String motherFirstName,
  String motherSurname = '',
  String screeningId = '',
  bool formBStarted = false,
}) {
  if (isPlaceholderPatientName(motherFirstName, motherSurname)) {
    final sid = screeningId.trim();
    return sid.isNotEmpty ? sid : 'Name pending';
  }
  final first = motherFirstName.trim();
  if (first.isEmpty) {
    final surname = motherSurname.trim();
    if (surname.isEmpty) {
      final sid = screeningId.trim();
      return sid.isNotEmpty ? sid : 'Name pending';
    }
    return formBStarted ? 'B/o $surname' : surname;
  }
  return formBStarted ? 'B/o $first' : first;
}
