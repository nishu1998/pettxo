import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/utils/password_validation.dart';

void main() {
  group('validateAccountSecurityPassword', () {
    test('rejects weak passwords', () {
      expect(validateAccountSecurityPassword(''), 'Password cannot be empty');
      expect(
        validateAccountSecurityPassword('12345'),
        'Password must be at least 6 characters',
      );
      expect(
        validateAccountSecurityPassword('pass word'),
        'Password cannot contain spaces',
      );
    });

    test('accepts valid password', () {
      expect(validateAccountSecurityPassword('pettxo123'), isNull);
    });
  });

  group('validatePasswordConfirmation', () {
    test('rejects confirmation mismatch', () {
      expect(
        validatePasswordConfirmation(
          password: 'pettxo123',
          confirmation: 'pettxo999',
        ),
        'Passwords do not match',
      );
    });

    test('accepts matching confirmation', () {
      expect(
        validatePasswordConfirmation(
          password: 'pettxo123',
          confirmation: 'pettxo123',
        ),
        isNull,
      );
    });
  });
}
