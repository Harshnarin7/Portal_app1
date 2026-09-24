import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/models/form_b.dart';
import 'package:my_portal_app/utils/form_b_local_guard.dart';

FormB _b({
  String screeningId = '01-0001',
  String maternalUid = '',
  String motherFirstName = '',
  DateTime? savedAt,
  String babyUid = '123',
}) {
  return FormB(
    screeningId: screeningId,
    babyUid: babyUid,
    birthWeight: '1200',
    dateOfBirth: '01-01-2026',
    timeOfBirth: '12:00:00',
    indication: 'PTL',
    delivery: 'Vaginal',
    labor: 'Spontaneous',
    gender: 'Female',
    enrollmentId: '01-A-001',
    maternalUid: maternalUid,
    motherFirstName: motherFirstName,
    savedAt: savedAt,
  );
}

void main() {
  group('localFormBIsForPatient', () {
    test('accepts a cache that matches screening + mother UID', () {
      expect(
        localFormBIsForPatient(
          local: _b(maternalUid: '111', motherFirstName: 'Anita'),
          screeningId: '01-0001',
          maternalUid: '111',
          motherFirstName: 'Anita',
          serverHasBirthLink: true,
        ),
        isTrue,
      );
    });

    test('rejects leftover B1 cache when Form A has no enrollment link yet', () {
      expect(
        localFormBIsForPatient(
          local: _b(maternalUid: '111', motherFirstName: 'Anita'),
          screeningId: '01-0001',
          maternalUid: '111',
          motherFirstName: 'Anita',
          serverHasBirthLink: false,
        ),
        isFalse,
      );
    });

    test('rejects a leftover cache for a different mother UID', () {
      expect(
        localFormBIsForPatient(
          local: _b(maternalUid: '111'),
          screeningId: '01-0001',
          maternalUid: '999',
        ),
        isFalse,
      );
    });

    test('rejects a leftover cache for a different screening ID', () {
      expect(
        localFormBIsForPatient(
          local: _b(screeningId: '01-0007'),
          screeningId: '01-0001',
        ),
        isFalse,
      );
    });

    test('rejects cache saved before this screening was created (ID reuse)', () {
      expect(
        localFormBIsForPatient(
          local: _b(
            maternalUid: '111',
            savedAt: DateTime(2026, 1, 1),
          ),
          screeningId: '01-0001',
          maternalUid: '111',
          screeningCreatedAt: DateTime(2026, 9, 22),
        ),
        isFalse,
      );
    });

    test('accepts an in-progress B1 draft saved after this Form A', () {
      expect(
        localFormBIsForPatient(
          local: _b(
            maternalUid: '111',
            savedAt: DateTime(2026, 9, 22, 12),
          ),
          screeningId: '01-0001',
          maternalUid: '111',
          screeningCreatedAt: DateTime(2026, 9, 22, 10),
          serverHasBirthLink: false,
        ),
        isTrue,
      );
    });

    test('linkedBirthEnrollmentId does not invent NR- ids', () {
      expect(linkedBirthEnrollmentId(''), isEmpty);
      expect(linkedBirthEnrollmentId(' 01-A-001 '), '01-A-001');
    });
  });

  group('remoteBirthRowIsForScreening', () {
    test('accepts a matching screening_id', () {
      expect(
        remoteBirthRowIsForScreening(
          remoteScreeningId: '01-0001',
          screeningId: '01-0001',
        ),
        isTrue,
      );
    });

    test('rejects another patient\'s birth row', () {
      expect(
        remoteBirthRowIsForScreening(
          remoteScreeningId: '01-0007',
          screeningId: '01-0001',
        ),
        isFalse,
      );
    });
  });

  group('linkedHelperEnrollmentId', () {
    test('uses screening enrollment and never leftover Form B', () {
      expect(
        linkedHelperEnrollmentId(screeningEnrollment: ' 01-A-001 '),
        '01-A-001',
      );
      expect(
        linkedHelperEnrollmentId(screeningEnrollment: ''),
        isEmpty,
      );
      expect(
        linkedHelperEnrollmentId(
          screeningEnrollment: '',
          remoteEnrollmentId: '01-A-009',
        ),
        '01-A-009',
      );
    });
  });

  group('helperLocalDraftIsForScreening', () {
    test('drops leftover draft with no screening_id when web day is empty', () {
      expect(
        helperLocalDraftIsForScreening(
          draft: {'weight': '1100'},
          screeningId: '01-0001',
          serverConfirmedEmpty: true,
        ),
        isFalse,
      );
    });

    test('keeps unsynced draft stamped with this screening', () {
      expect(
        helperLocalDraftIsForScreening(
          draft: {'screening_id': '01-0001', 'weight': '1100'},
          screeningId: '01-0001',
          serverConfirmedEmpty: true,
        ),
        isTrue,
      );
    });

    test('rejects a draft stamped for another screening', () {
      expect(
        helperLocalDraftIsForScreening(
          draft: {'screening_id': '01-0007'},
          screeningId: '01-0001',
          serverConfirmedEmpty: false,
        ),
        isFalse,
      );
    });
  });
}
