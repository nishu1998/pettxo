import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/identity/username_utils.dart';

void main() {
  test('normalizeUsername trims, strips @, and lowercases', () {
    expect(normalizeUsername('  @Pet.TxO_123  '), 'pet.txo_123');
    expect(normalizeUsername('Pettxo'), 'pettxo');
    expect(normalizeUsername('PETTXO'), 'pettxo');
    expect(normalizeUsername(' pettxo '), 'pettxo');
  });

  test('validateNormalizedUsername accepts allowed usernames', () {
    expect(validateNormalizedUsername('pet.txo_123'), isNull);
  });

  test('validateNormalizedUsername rejects invalid usernames', () {
    expect(
      validateNormalizedUsername('ab'),
      'Use 3-20 lowercase letters, numbers, dots, or underscores',
    );
    expect(
      validateNormalizedUsername('PetToxo'),
      'Use 3-20 lowercase letters, numbers, dots, or underscores',
    );
    expect(
      validateNormalizedUsername('pet-toxo'),
      'Use 3-20 lowercase letters, numbers, dots, or underscores',
    );
    expect(
      validateNormalizedUsername('.pettxo'),
      'Username cannot start or end with a dot',
    );
    expect(
      validateNormalizedUsername('pettxo.'),
      'Username cannot start or end with a dot',
    );
    expect(
      validateNormalizedUsername('pet..txo'),
      'Username cannot contain consecutive dots',
    );
    expect(validateNormalizedUsername('admin'), 'This username is reserved');
    expect(validateNormalizedUsername('pettxo'), 'This username is reserved');
    expect(validateNormalizedUsername('pet\u200Btxo'), isNotNull);
    expect(validateNormalizedUsername('pèttxo'), isNotNull);
  });

  test('official protected username is submitted for server authorization', () {
    expect(validateUsernameClaimInput('pettxo'), isNull);
    expect(
      normalizeAndValidateUsernameClaimInput(' @Pettxo ').normalized,
      'pettxo',
    );
    expect(validateUsernameClaimInput('admin'), 'This username is reserved');
  });
}
