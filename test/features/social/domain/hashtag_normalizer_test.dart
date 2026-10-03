import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/domain/hashtag_normalizer.dart';

void main() {
  test('accepts an individual hashtag with exactly 30 characters', () {
    final tag = 'a' * 30;
    expect(validatePostHashtags([tag]), [tag]);
  });

  test('rejects typed or pasted hashtags longer than 30 characters', () {
    final oversized = 'a' * 31;
    expect(
      () => validatePostHashtags([oversized]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validatePostHashtags(['  #$oversized  ']),
      throwsA(isA<FormatException>()),
    );
  });

  test('preserves the existing five hashtag maximum', () {
    expect(validatePostHashtags(['one', 'two', 'three', 'four', 'five']), [
      'one',
      'two',
      'three',
      'four',
      'five',
    ]);
    expect(
      () =>
          validatePostHashtags(['one', 'two', 'three', 'four', 'five', 'six']),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'normalization and search-compatible canonical values are unchanged',
    () {
      expect(validatePostHashtags(['#Pettxo', ' Pets_India ']), [
        'pettxo',
        'pets_india',
      ]);
      expect(normalizeHashtag('#Pettxo'), 'pettxo');
    },
  );
}
