import 'package:flutter_test/flutter_test.dart';
import 'package:my_portal_app/utils/mobile_numbers.dart';

void main() {
  test('primary empty fails', () {
    final errors = mobilePairErrors('', '');
    expect(errors.primary, errMobileRequired);
    expect(errors.secondary, isNull);
  });

  test('primary only passes', () {
    final errors = mobilePairErrors('9876543210', '');
    expect(errors.primary, isNull);
    expect(errors.secondary, isNull);
  });

  test('both valid passes', () {
    final errors = mobilePairErrors('9876543210', '9123456780');
    expect(errors.primary, isNull);
    expect(errors.secondary, isNull);
  });

  test('secondary invalid fails', () {
    final errors = mobilePairErrors('9876543210', '12345');
    expect(errors.primary, isNull);
    expect(errors.secondary, errMobileDigits);
  });

  test('both the same fails', () {
    final errors = mobilePairErrors('9876543210', '9876543210');
    expect(errors.secondary, errMobileSame);
  });
}
