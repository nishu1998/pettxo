import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/utils/password_reset_utils.dart';

void main() {
  test('normalizePasswordResetEmail trims and lowercases', () {
    expect(
      normalizePasswordResetEmail('  Person@Example.COM '),
      'person@example.com',
    );
  });

  test('validatePasswordResetEmail rejects invalid emails', () {
    expect(validatePasswordResetEmail(''), 'Email is required.');
    expect(
      validatePasswordResetEmail('not-an-email'),
      'Enter a valid email address.',
    );
    expect(validatePasswordResetEmail('person@example.com'), isNull);
  });
}
