import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/utils/ga_check_search.dart';

void main() {
  const entries = <Map<String, dynamic>>[
    {'mother_name': 'Aisha Khatun', 'mother_uid': '202604773481'},
    {'mother_name': '  Rina   Das ', 'mother_uid': '998877'},
  ];

  test('name match ignores case and extra spaces', () {
    final found = filterGaChecks(entries, '  aisha   khatun ');
    expect(found, hasLength(1));
    expect(found.single['mother_uid'], '202604773481');
  });

  test('ID match is a partial, case-insensitive match', () {
    final found = filterGaChecks(entries, '773481');
    expect(found, hasLength(1));
    expect(found.single['mother_name'], 'Aisha Khatun');
  });

  test('no match returns an empty list', () {
    expect(filterGaChecks(entries, 'nobody'), isEmpty);
  });

  test('empty query returns every check', () {
    expect(filterGaChecks(entries, '   '), entries);
  });
}
