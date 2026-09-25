import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/data/repositories/profile_repository.dart';

void main() {
  test('username search normalizes exact, prefix, case, and at-sign forms', () {
    expect(normalizeProfileSearchQuery('nishu2908'), 'nishu2908');
    expect(normalizeProfileSearchQuery('nishu'), 'nishu');
    expect(normalizeProfileSearchQuery('nish'), 'nish');
    expect(normalizeProfileSearchQuery('NISHU2908'), 'nishu2908');
    expect(normalizeProfileSearchQuery('Nishu2908'), 'nishu2908');
    expect(normalizeProfileSearchQuery(' @Nishu2908 '), 'nishu2908');
  });

  test('profile search identity comes from the canonical document id', () {
    final profile =
        profileFromSearchDocument('canonical-uid', <String, dynamic>{
          'uid': 'stale-embedded-uid',
          'username': 'nishu2908',
          'usernameLowercase': 'nishu2908',
          'displayName': 'Nishant Gautam',
          'name': 'Nishant Gautam',
          'photoUrl': 'https://example.com/avatar.jpg',
          'role': 'serviceProvider',
        });

    expect(profile.uid, 'canonical-uid');
    expect(profile.username, 'nishu2908');
    expect(profile.displayName, 'Nishant Gautam');
    expect(profile.photoUrl, 'https://example.com/avatar.jpg');
    expect(profile.role, 'serviceProvider');
  });

  test(
    'supported display-name contract is a case-insensitive leading prefix',
    () {
      final profile = profileFromSearchDocument('uid', <String, dynamic>{
        'username': 'nishu2908',
        'usernameLowercase': 'nishu2908',
        'displayName': 'Nishant Gautam',
        'name': 'Nishant Gautam',
      });

      expect(profileMatchesSearchPrefix(profile, 'nishant gautam'), isTrue);
      expect(profileMatchesSearchPrefix(profile, 'nishant'), isTrue);
      expect(profileMatchesSearchPrefix(profile, 'gautam'), isFalse);
    },
  );

  test('deleted and deactivated profiles remain non-public', () {
    final deleted = profileFromSearchDocument('deleted', <String, dynamic>{
      'username': 'deleted',
      'usernameLowercase': 'deleted',
      'isDeleted': true,
    });
    final deactivated =
        profileFromSearchDocument('deactivated', <String, dynamic>{
          'username': 'deactivated',
          'usernameLowercase': 'deactivated',
          'accountStatus': 'deactivated',
        });

    expect(deleted.isPubliclyVisible, isFalse);
    expect(deactivated.isPubliclyVisible, isFalse);
  });
}
