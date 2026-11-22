import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_user_set_cache.dart';
import 'package:pettexo/features/services/data/repositories/services_repository.dart';

import '../../../helpers/fake_app_services.dart';
import '../../../helpers/in_memory_firestore.dart';

const _me = 'alice';
const _owner = 'bob';
const _serviceId = 's1';

void main() {
  late InMemoryFirestore db;
  late ServicesRepository repository;

  setUp(() {
    BlockedUserSetCache.instance.invalidate();
    db = InMemoryFirestore()
      ..seed('services/$_serviceId', <String, dynamic>{
        'ownerUserId': _owner,
        'title': 'Dog Walking',
        'status': 'active',
        'isActive': true,
        'isDeleted': false,
        'isPaused': false,
        'isVisibleToMarketplace': true,
      });
    repository = ServicesRepository(
      firestore: db,
      auth: FakeAuth(_me),
      storage: FakeStorage(),
      profileRepository: FakeProfileRepository(_me),
    );
  });

  tearDown(() => BlockedUserSetCache.instance.invalidate());

  test(
    'fetchServiceById for a non-owner without a block returns the service',
    () async {
      final service = await repository.fetchServiceById(_serviceId);
      expect(service, isNotNull);
      expect(service!.ownerUserId, _owner);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
      expect(db.queriesOn('userBlocks'), hasLength(2));
    },
  );

  for (final pair in <List<String>>[
    <String>[_me, _owner],
    <String>[_owner, _me],
  ]) {
    test(
      'fetchServiceById returns null with block ${pair[0]}_${pair[1]}',
      () async {
        db.seed('userBlocks/${pair[0]}_${pair[1]}', <String, dynamic>{
          'ownerUserId': pair[0],
          'blockedUserId': pair[1],
        });
        expect(await repository.fetchServiceById(_serviceId), isNull);
        expect(db.pointGetsOn('userBlocks'), isEmpty);
      },
    );
  }
}
