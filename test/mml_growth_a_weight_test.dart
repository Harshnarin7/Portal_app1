import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/models/minimal_monitoring.dart';
import 'package:my_portal_app/utils/mml_helper_linkages.dart';

void main() {
  group('DMS 5.7.A growth_a hydrate/persist', () {
    test('hydrate keeps web growth_a weight_g instead of dropping it', () {
      final json = {
        'enrollment_id': 'E1',
        'record_date': '2026-09-18',
        'weight_frequency_hours': 12,
        'entries_json': jsonEncode({
          'growth_a': [
            {
              'id': 'w1',
              'date': '2026-09-18',
              'time': '08:00',
              'slot_time': '08:00',
              'weight_g': '1250',
            },
          ],
        }),
      };
      final sheet = MinimalMonitoringSheet.fromJson(json);
      expect(sheet.weightFrequencyHours, 12);
      final rows = sheet.entries['growth_a'] ?? [];
      expect(rows, isNotEmpty);
      expect(rows.first['weight_g']?.toString(), '1250');
      expect(rows.first.hasClinicalData(), isTrue);
    });

    test('slot_time alone is not clinical data', () {
      final e = MmlEntry(fields: {'slot_time': '08:00', 'weight_g': ''});
      expect(e.hasClinicalData(), isFalse);
    });

    test('persist writes growth_a so a mobile save cannot wipe web weights', () {
      final sheet = MinimalMonitoringSheet.fromJson({
        'enrollment_id': 'E1',
        'record_date': '2026-09-18',
        'entries_json': jsonEncode({
          'growth_a': [
            {
              'id': 'w1',
              'date': '2026-09-18',
              'time': '08:00',
              'weight_g': '1100',
            },
          ],
        }),
      });
      final body = sheet.toJson(savedBy: 'test', sheetRecordDate: '2026-09-18');
      expect(body['weight_frequency_hours'], 24);
      final parsed = jsonDecode(body['entries_json'] as String) as Map;
      final growth = parsed['growth_a'] as List;
      expect(growth, isNotEmpty);
      expect(growth.first['weight_g']?.toString(), '1100');
    });

    test('blank trailing draft is not persisted', () {
      final sheet = MinimalMonitoringSheet(enrollmentId: 'E1');
      final map = sheet.entriesMapForPersist();
      expect(map['growth_a'], isEmpty);
    });
  });

  group('Helper 4 #15 ml/kg/d effective weight', () {
    test('uses birth weight while DMS is still below birth', () {
      expect(
        effectiveFeedWeightKg(dmsWeightKg: 1.1, birthWeightGrams: 1250),
        1.25,
      );
    });

    test('uses DMS weight once recovered to/past birth weight', () {
      expect(
        effectiveFeedWeightKg(dmsWeightKg: 1.3, birthWeightGrams: 1250),
        1.3,
      );
    });

    test('falls back to whichever weight exists', () {
      expect(
        effectiveFeedWeightKg(dmsWeightKg: 1.2, birthWeightGrams: null),
        1.2,
      );
      expect(
        effectiveFeedWeightKg(dmsWeightKg: null, birthWeightGrams: 1250),
        1.25,
      );
    });

    test('117 ml ÷ 1.25 kg = 93.6 ml/kg/d', () {
      final w = effectiveFeedWeightKg(
        dmsWeightKg: 1.1,
        birthWeightGrams: 1250,
      );
      final calc = feedVolumeMlPerKgDay(117, w);
      expect(calc, 93.6);
      expect(formatFeedVolumeMlPerKgDay(calc!), '93.6');
    });

    test('whole-number calc formats without a trailing .0', () {
      expect(formatFeedVolumeMlPerKgDay(100.0), '100');
      expect(feedVolumeMlPerKgDay(125, 1.25), 100.0);
    });
  });
}
