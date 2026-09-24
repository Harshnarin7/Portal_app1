import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/models/birth_resuscitation.dart';
import 'package:my_portal_app/models/infect_gi_hema_day.dart';
import 'package:my_portal_app/utils/gestation_age.dart';
import 'package:my_portal_app/utils/helper_day_strip.dart';
import 'package:my_portal_app/utils/participant_name.dart';
import 'package:my_portal_app/utils/screening_status.dart';

void main() {
  group('Form B PII payload', () {
    test('sends the same PII keys as web when values are present', () {
      final d = BirthResuscitationData()
        ..screeningId = '01-0001'
        ..enrollmentId = '01-A-001';
      d.applyPii(
        motherFirst: 'Anita',
        motherSurname: 'Sharma',
        maternalUid: '123456789012',
        contactMother: '9876543210',
        contactHusband: '9123456789',
      );
      final json = d.toJson();
      expect(json['mother_name_first'], 'Anita');
      expect(json['mother_name_surname'], 'Sharma');
      expect(json['maternal_uid'], '123456789012');
      expect(json['contact_mother'], '9876543210');
      expect(json['contact_husband'], '9123456789');
    });

    test('omits empty PII so a mobile edit cannot wipe web values', () {
      final d = BirthResuscitationData()
        ..screeningId = '01-0001'
        ..enrollmentId = '01-A-001'
        ..motherNameFirst = ''
        ..maternalUid = null;
      final json = d.toJson();
      expect(json.containsKey('mother_name_first'), isFalse);
      expect(json.containsKey('mother_name_surname'), isFalse);
      expect(json.containsKey('maternal_uid'), isFalse);
      expect(json.containsKey('contact_mother'), isFalse);
      expect(json.containsKey('contact_husband'), isFalse);
    });

    test('fromJson round-trips PII keys', () {
      final loaded = BirthResuscitationData.fromJson({
        'screening_id': '01-0001',
        'enrollment_id': '01-A-001',
        'mother_name_first': 'Anita',
        'mother_name_surname': 'Sharma',
        'maternal_uid': '123456789012',
        'contact_mother': '9876543210',
        'contact_husband': '9123456789',
      });
      final json = loaded.toJson();
      expect(json['mother_name_first'], 'Anita');
      expect(json['maternal_uid'], '123456789012');
      expect(json['contact_husband'], '9123456789');
    });

    test('applyPii ignores empty strings so existing values stay', () {
      final d = BirthResuscitationData()
        ..motherNameFirst = 'Anita'
        ..maternalUid = '123456789012';
      d.applyPii(motherFirst: '', maternalUid: '  ');
      expect(d.motherNameFirst, 'Anita');
      expect(d.maternalUid, '123456789012');
    });
  });

  group('Form B Q60 blender reasons', () {
    test('maps old stored strings to new CRF wording on load', () {
      final mapped = parseBlenderInterruptReasons(
        'Blender stopped abruptly, Surfactant decision, Intubation, Early transfer, FiO₂ – 21 or 100%',
      );
      expect(mapped, kBlenderInterruptReasons);
    });

    test('saves the new strings', () {
      final d = BirthResuscitationData()
        ..screeningId = '01-0001'
        ..enrollmentId = '01-A-001'
        ..blenderStopped = true
        ..blenderInterruptReasons = List.of(kBlenderInterruptReasons);
      final json = d.toJson();
      expect(
        json['blender_interrupt_reasons'],
        kBlenderInterruptReasons.join(', '),
      );
    });

    test('does not send interrupt reasons when Q59 was not answered', () {
      final d = BirthResuscitationData()
        ..screeningId = '01-0001'
        ..enrollmentId = '01-A-001'
        ..blenderStopped = null
        ..blenderInterruptReasons = ['Blender stopped working abruptly'];
      final json = d.toJson();
      expect(json.containsKey('blender_interrupt_reasons'), isFalse);
    });
  });

  group('Form B SIB/T-piece integers', () {
    test('SIB/T-piece whole numbers save as JSON ints', () {
      final d = BirthResuscitationData()
        ..screeningId = '01-0001'
        ..enrollmentId = '01-A-001'
        ..sibPeepCmh2o = 5.0
        ..tpiecePip = 20.0
        ..tpiecePeep = 5.0
        ..tpieceFlow = 8.0;
      final json = d.toJson();
      expect(json['sib_peep_cmh2o'], 5);
      expect(json['tpiece_pip'], 20);
      expect(json['tpiece_peep'], 5);
      expect(json['tpiece_flow'], 8);
    });
  });

  group('Form B Q47 MM:SS', () {
    test('seconds round-trip through MM:SS', () {
      expect(secondsToMmSs(125), '02:05');
      expect(mmSsToSeconds('02:05'), 125);
    });
  });

  group('Form A GA as-of screening_datetime', () {
    test('LMP GA uses screening date, not today', () {
      final lmp = DateTime(2026, 1, 1);
      final screening = DateTime(2026, 3, 12);
      final ga = gestAgeFromLmp(lmp, screening)!;
      // 2026-01-01 → 2026-03-12 = 70 days = 10w0d
      expect(ga.weeks, 10);
      expect(ga.days, 0);
    });

    test('EDD GA uses screening date, not today', () {
      final edd = DateTime(2026, 10, 8); // Naegele from LMP 2026-01-01
      final screening = DateTime(2026, 3, 12);
      final ga = gestAgeFromEdd(edd, screening)!;
      expect(ga.weeks, 10);
      expect(ga.days, 0);
    });

    test('Naegele EDD is 9 calendar months + 7 days, not +280 days', () {
      // LMP 15 Mar 2026 → 15 Dec + 7 = 22 Dec. +280 days would be 20 Dec.
      expect(eddFromLmp(DateTime(2026, 3, 15)), DateTime(2026, 12, 22));
      expect(lmpFromEdd(DateTime(2026, 12, 22)), DateTime(2026, 3, 15));
    });

    test('Naegele Wikipedia example (LMP 9 Aug 2009 → 16 May 2010)', () {
      expect(eddFromLmp(DateTime(2009, 8, 9)), DateTime(2010, 5, 16));
    });

    test('same LMP yields different GA on a later as-of date', () {
      final lmp = DateTime(2026, 1, 1);
      final early = gestAgeFromLmp(lmp, DateTime(2026, 3, 12))!;
      final later = gestAgeFromLmp(lmp, DateTime(2026, 4, 12))!;
      expect(
        later.weeks * 7 + later.days,
        greaterThan(early.weeks * 7 + early.days),
      );
    });
  });

  group('Helper 4 *_status sidecars', () {
    test('load and save culture/feed/Hb status exactly as web', () {
      final loaded = InfectGiHemaDay.fromJson({
        'enrollment_id': '01-A-001',
        'nicu_day': 2,
        'blood_culture_status': InfectGiHemaDay.statusAwaited,
        'cumulative_feed_volume_status': InfectGiHemaDay.statusNotDone,
        'feed_volume_status': InfectGiHemaDay.statusNotDone,
        'hb_value_status': InfectGiHemaDay.statusAwaited,
        'peak_tsb_status': InfectGiHemaDay.statusNotDone,
      });
      expect(loaded.bloodCultureStatus, 'Result Awaited');
      expect(loaded.cumulativeFeedVolumeStatus, 'Not Recorded / Not Done');
      expect(loaded.hbValueStatus, 'Result Awaited');
      expect(loaded.peakTsbStatus, 'Not Recorded / Not Done');

      final json = loaded.toJson(submissionStatus: 'draft', savedBy: 'test');
      expect(json['blood_culture_status'], 'Result Awaited');
      expect(json['cumulative_feed_volume_status'], 'Not Recorded / Not Done');
      expect(json['feed_volume_status'], 'Not Recorded / Not Done');
      expect(json['hb_value_status'], 'Result Awaited');
      expect(json['peak_tsb_status'], 'Not Recorded / Not Done');
    });

    test('status counts as answered for completion', () {
      final d = InfectGiHemaDay(enrollmentId: '01-A-001', nicuDay: 1)
        ..sepsisSuspected = true
        ..bloodCultureSent = true
        ..bloodCultureStatus = InfectGiHemaDay.statusAwaited
        ..antibiotics = false
        ..lpDone = false
        ..meningitis = false
        ..clabsi = false
        ..vap = false
        ..sepsisScreenSent = false
        ..npo = true
        ..ivFluids = false
        ..parenteralNutrition = false
        ..probiotic = false
        ..feedIntolerance = false
        ..necSuspected = false
        ..cholestasis = false
        ..hbValueStatus = InfectGiHemaDay.statusNotDone
        ..jaundice = false
        ..peakTsbStatus = InfectGiHemaDay.statusAwaited
        ..exchangeTransfusion = false
        ..prbcTransfusion = false
        ..plateletTransfusion = false
        ..ffpCryo = false;
      final c = InfectGiHemaCompletion.compute(d);
      expect(c.percent, 100);
    });
  });

  group('Helper day strip status', () {
    test('100% draft shows complete, not orange partial', () {
      expect(helperDayDisplayStatus('draft', 100), 'complete');
      expect(helperDaySaveStatus(100), 'complete');
    });

    test('submitted stays submitted even at 100%', () {
      expect(helperDayDisplayStatus('submitted', 100), 'submitted');
    });

    test('started but incomplete stays draft', () {
      expect(helperDayDisplayStatus('draft', 80), 'draft');
      expect(helperDaySaveStatus(80), 'draft');
    });
  });

  group('participantListName', () {
    test('Form A only shows mother first name', () {
      expect(
        participantListName(motherFirstName: 'Poonam', formBStarted: false),
        'Poonam',
      );
    });

    test('Form B started shows B/o mother first name', () {
      expect(
        participantListName(motherFirstName: 'Poonam', formBStarted: true),
        'B/o Poonam',
      );
    });
  });

  group('gaInInclusionWindow', () {
    test('accepts 25w0d through 31w6d', () {
      expect(gaInInclusionWindow(25, 0), isTrue);
      expect(gaInInclusionWindow(31, 6), isTrue);
      expect(gaInInclusionWindow(28, 3), isTrue);
    });

    test('rejects below 25w0d and at/above 32w', () {
      expect(gaInInclusionWindow(24, 6), isFalse);
      expect(gaInInclusionWindow(32, 0), isFalse);
      expect(gaInInclusionWindow(36, 5), isFalse);
      expect(gaInInclusionWindow(null, 0), isFalse);
    });
  });
}
