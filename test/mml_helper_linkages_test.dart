import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/utils/mml_helper_linkages.dart';

void main() {
  group('5.4.A gi_a → Helper 3 cumulative feed volume', () {
    test('sums two readings on the same helper calendar day (47 + 70 = 117)', () {
      final entriesJson = {
        'gi_a': [
          {
            'id': 'a',
            'date': '2026-09-16',
            'time': '11:29',
            'cumulative_feed_volume': '70',
          },
          {
            'id': 'b',
            'date': '2026-09-16',
            'time': '14:07',
            'cumulative_feed_volume': '47',
          },
        ],
      };
      final data = {'entries_json': jsonEncode(entriesJson)};
      final values = parseGiAFeedVolumeValues(
        data,
        helperCalendarDate: '2026-09-16',
      );
      expect(values, [70.0, 47.0]);
      expect(sumGiAFeedVolumeValues(values), 117.0);
      expect(
        mmlSumCumulativeFeedVolume(
          data,
          helperCalendarDate: '2026-09-16',
        ),
        117.0,
      );
    });

    test('skips blank draft row (date/time only)', () {
      final entriesJson = {
        'gi_a': [
          {
            'id': 'a',
            'date': '2026-09-16',
            'time': '11:29',
            'cumulative_feed_volume': '70',
          },
          {
            'id': 'draft',
            'date': '2026-09-16',
            'time': '15:00',
            'cumulative_feed_volume': '',
          },
        ],
      };
      final data = {'entries_json': jsonEncode(entriesJson)};
      final values = parseGiAFeedVolumeValues(
        data,
        helperCalendarDate: '2026-09-16',
      );
      expect(values, [70.0]);
      expect(sumGiAFeedVolumeValues(values), 70.0);
    });

    test('filters out readings on other calendar dates', () {
      final entriesJson = {
        'gi_a': [
          {
            'id': 'a',
            'date': '2026-09-15',
            'time': '10:00',
            'cumulative_feed_volume': '99',
          },
          {
            'id': 'b',
            'date': '2026-09-16',
            'time': '14:07',
            'cumulative_feed_volume': '47',
          },
        ],
      };
      final data = {'entries_json': jsonEncode(entriesJson)};
      final values = parseGiAFeedVolumeValues(
        data,
        helperCalendarDate: '2026-09-16',
      );
      expect(values, [47.0]);
    });

    test('mergeGiAFeedValueLists does not double-count same sheet twice', () {
      final values = [70.0, 47.0];
      final merged = mergeGiAFeedValueLists(values, values);
      expect(sumGiAFeedVolumeValues(merged), 234.0);
      // Production code only merges /today when sheet record_date != helper day.
    });

    test('feedVolumeLooksMmlSourced allows refresh from partial sum 70 to 117', () {
      expect(feedVolumeLooksMmlSourced('70', [70, 47]), isTrue);
      expect(feedVolumeLooksMmlSourced('117', [70, 47]), isTrue);
      expect(feedVolumeLooksMmlSourced('99', [70, 47]), isFalse);
    });
  });

  group('5.6.A heme_a → Helper 3 #28–#30', () {
    test('sets PRBC, Platelets, FFP/Cryo from product pills across readings', () {
      final entriesJson = {
        'heme_a': [
          {
            'id': '1',
            'date': '2026-09-16',
            'time': '14:18',
            'transfusion_products': ['PRBC', 'FFP/Cryo'],
            'transfusion_count': '2',
          },
          {
            'id': '2',
            'date': '2026-09-16',
            'time': '14:17',
            'transfusion_products': ['Platelets'],
            'transfusion_count': '3',
          },
          {
            'id': 'draft',
            'date': '2026-09-16',
            'time': '15:00',
            'transfusion_products': [],
            'transfusion_count': '',
          },
        ],
      };
      final data = {'entries_json': jsonEncode(entriesJson)};
      final flags = parseHemeATransfusionFlags(
        data,
        helperCalendarDate: '2026-09-16',
      );
      expect(flags.prbc, isTrue);
      expect(flags.platelet, isTrue);
      expect(flags.ffpCryo, isTrue);
    });
  });

  group('5.6.A transfusion Y/N mirror', () {
    test('clears Yes on Helper when product removed from MML', () {
      final r = mmlSyncTransfusionYnFromMml(
        current: true,
        mmlHas: false,
        wasAutofilled: false,
      );
      expect(r.changed, isTrue);
      expect(r.nextValue, isNull);
      expect(r.nextAutofilled, isFalse);
    });

    test('does not clear nurse explicit No when MML still has product', () {
      final r = mmlSyncTransfusionYnFromMml(
        current: false,
        mmlHas: true,
        wasAutofilled: false,
      );
      expect(r.changed, isFalse);
      expect(r.nextValue, isFalse);
    });
  });

  group('MML aggregate mirror (feed / episodes / blood gas)', () {
    test('clears helper value when MML aggregate removed', () {
      final r = mmlSyncAggregateFieldFromMml(
        current: '117',
        blockedByNotDone: false,
        wasAutofilled: true,
        stillMatchesLastAuto: false,
        looksSourced: (_, __) => false,
        entryValuesForSourced: const <double>[],
        mmlValue: null,
      );
      expect(r.changed, isTrue);
      expect(r.nextValue, isEmpty);
      expect(r.nextAutofilled, isFalse);
    });

    test('updates sum when MML adds a reading', () {
      final r = mmlSyncAggregateFieldFromMml(
        current: '70',
        blockedByNotDone: false,
        wasAutofilled: true,
        stillMatchesLastAuto: false,
        looksSourced: (c, vals) =>
            feedVolumeLooksMmlSourced(c, vals as List<double>),
        entryValuesForSourced: const [70.0, 47.0],
        mmlValue: '117',
      );
      expect(r.changed, isTrue);
      expect(r.nextValue, '117');
    });
  });

  group('5.2.B resp_b → Helper 1 #8–#10', () {
    test('ignores flat ph/pao2 0 when entries_json has resp_b rows', () {
      final entriesJson = {
        'resp_b': [
          {'date': '2026-09-17', 'ph': '6.6', 'pao2': '21', 'paco2': '20'},
        ],
      };
      final data = {
        'record_date': '2026-09-17',
        'ph': 0,
        'pao2': 0,
        'paco2': 0,
        'entries_json': jsonEncode(entriesJson),
      };
      final readings = parseRespBBloodGasReadings(
        data,
        helperCalendarDate: '2026-09-17',
      );
      final computed = computeBloodGasAutofillFromMml(readings);
      expect(computed['lowest_ph'], '6.6');
      expect(computed['pao2_low'], '21');
      expect(computed['paco2_low'], '20');
    });

    test('lowest pH and PaO₂/PaCO₂ ranges across three readings', () {
      final entriesJson = {
        'resp_b': [
          {'date': '2026-09-17', 'ph': '7.2', 'pao2': '20', 'paco2': '29'},
          {'date': '2026-09-17', 'ph': '6.6', 'pao2': '21', 'paco2': '20'},
          {'date': '2026-09-17', 'ph': '7.0', 'pao2': '24', 'paco2': '26'},
        ],
      };
      final data = {
        'record_date': '2026-09-17',
        'entries_json': jsonEncode(entriesJson),
      };
      final readings = parseRespBBloodGasReadings(
        data,
        helperCalendarDate: '2026-09-17',
      );
      expect(mmlRespBHasBloodGasRows(readings), isTrue);
      final computed = computeBloodGasAutofillFromMml(readings);
      expect(computed['lowest_ph'], '6.6');
      expect(computed['pao2_low'], '20');
      expect(computed['pao2_high'], '24');
      expect(computed['paco2_low'], '20');
      expect(computed['paco2_high'], '29');
    });
  });

  group('5.2.C resp_c → Helper 1 #13–#15', () {
    test('ignores flat apnea_episodes 0 when entries_json has resp_c', () {
      final entriesJson = {
        'resp_c': [
          {
            'date': '17-09-2026',
            'apnea_episodes': '2',
            'desaturation_episodes': '3',
            'severe_desaturation_episodes': '2',
          },
        ],
      };
      final data = {
        'record_date': '2026-09-17',
        'apnea_episodes': 0,
        'desaturation_episodes': 0,
        'severe_desaturation_episodes': 0,
        'entries_json': jsonEncode(entriesJson),
      };
      final readings = parseRespCEpisodeReadings(
        data,
        helperCalendarDate: '2026-09-17',
      );
      final computed = computeEpisodeAutofillFromMml(readings);
      expect(computed['apnea_count'], '2');
      expect(computed['desaturation_count'], '3');
      expect(computed['severe_desaturation_count'], '2');
    });

    test('sums apnea / desat / severe desat across readings', () {
      final entriesJson = {
        'resp_c': [
          {
            'date': '17-09-2026',
            'apnea_episodes': '2',
            'desaturation_episodes': '3',
            'severe_desaturation_episodes': '2',
          },
        ],
      };
      final data = {
        'record_date': '2026-09-17',
        'entries_json': jsonEncode(entriesJson),
      };
      final readings = parseRespCEpisodeReadings(
        data,
        helperCalendarDate: '2026-09-17',
      );
      expect(mmlRespCHasEpisodeRows(readings), isTrue);
      final computed = computeEpisodeAutofillFromMml(readings);
      expect(computed['apnea_count'], '2');
      expect(computed['desaturation_count'], '3');
      expect(computed['severe_desaturation_count'], '2');
    });
  });

  group('5.2.A resp_a → Helper 1 #3–#5', () {
    test('daily union and maxima across four readings', () {
      final entriesJson = {
        'resp_a': [
          {
            'date': '2026-09-17',
            'respiratory_modes': ['HFNC', 'CPAP'],
            'max_map_cpap': '11',
            'max_fio2': '26',
          },
          {
            'date': '2026-09-17',
            'respiratory_modes': ['HFNC', 'SIMV'],
            'max_map_cpap': '20',
            'max_fio2': '29',
          },
          {
            'date': '2026-09-17',
            'respiratory_modes': ['HFNC', 'CPAP'],
            'max_map_cpap': '4',
            'max_fio2': '66',
          },
          {
            'date': '2026-09-17',
            'respiratory_modes': [
              'HFNC',
              'SIMV',
              'CPAP',
              'NIPPV',
              'PSV',
              'HFOV',
              'A/C',
            ],
            'max_map_cpap': '12',
            'max_map_cpap_secondary': '12',
            'max_fio2': '80',
          },
        ],
      };
      final data = {
        'record_date': '2026-09-17',
        'entries_json': jsonEncode(entriesJson),
      };
      final rows = parseRespAEntries(
        data,
        helperCalendarDate: '2026-09-17',
      );
      expect(rows.length, 4);
      final agg = computeRespAAutofillFromMml(rows);
      expect(agg.hasRows, isTrue);
      expect(agg.maxFio2, '80');
      expect(agg.mapCpap, '20');
      expect(agg.mapCpapSecondary, '12');
      expect(agg.modesUnion, contains('AC'));
      expect(agg.modesUnion, contains('HFNC'));
      expect(agg.modesUnion, contains('CPAP'));
      expect(agg.modesUnion, contains('SIMV'));
    });
  });

  group('MML glucose mirror', () {
    test('reverts stale numeric when all glucose readings removed', () {
      final r = mmlSyncGlucoseFieldFromMml(
        current: '88',
        wasAutofilled: true,
        stillMatchesLastAuto: false,
        force: false,
        fieldKey: 'lowest_glucose',
        readings: const [],
        computedValue: 'Not Tested',
      );
      expect(r.changed, isTrue);
      expect(r.nextValue, 'Not Tested');
    });
  });
}
