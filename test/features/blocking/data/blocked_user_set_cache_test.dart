import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/application/blocking_change_coordinator.dart';
import 'package:pettexo/features/blocking/data/blocked_relationship_repository.dart';
import 'package:pettexo/features/blocking/data/blocked_user_set_cache.dart';

import '../../../helpers/fake_app_services.dart';
import '../../../helpers/in_memory_firestore.dart';

const _me = 'alice';
const _other = 'bob';
const _third = 'carol';

class _Harness {
  _Harness() {
    cache = BlockedUserSetCache(changes: changes.stream, now: () => now);
    repository = BlockedRelationshipRepository(
      firestore: db,
      auth: auth,
      blockedUserSetCache: cache,
    );
  }

  final InMemoryFirestore db = InMemoryFirestore();
  final FakeAuth auth = FakeAuth(_me);
  final StreamController<BlockingChange> changes =
      StreamController<BlockingChange>.broadcast(sync: true);
  DateTime now = DateTime(2026, 11, 22, 12);
  late final BlockedUserSetCache cache;
  late final BlockedRelationshipRepository repository;

  void block(String owner, String blocked) {
    db.seed('userBlocks/${owner}_$blocked', <String, dynamic>{
      'ownerUserId': owner,
      'blockedUserId': blocked,
    });
  }

  int get loads => db.queriesOn('userBlocks').length ~/ 2;

  Future<void> dispose() async {
    await cache.dispose();
    await changes.close();
  }
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test('empty when there are no blocks', () async {
    expect(await h.repository.loadCachedEffectiveBlockedUserIds(), isEmpty);
    expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
  });

  test('contains the other user for a block in either direction', () async {
    h.block(_me, _other);
    h.block(_third, _me);
    expect(await h.repository.loadCachedEffectiveBlockedUserIds(), <String>{
      _other,
      _third,
    });
    expect(await h.repository.isEffectivelyBlocked(_other), isTrue);
    expect(await h.repository.isEffectivelyBlocked(_third), isTrue);
    expect(await h.repository.isEffectivelyBlocked('dave'), isFalse);
  });

  test('uses the two list queries and never point-gets userBlocks', () async {
    h.block(_other, _me);
    await h.repository.isEffectivelyBlocked(_other);
    await h.repository.isEffectivelyBlocked(_third);
    expect(h.db.pointGetsOn('userBlocks'), isEmpty);
    expect(h.db.queriesOn('userBlocks'), <String>[
      'query userBlocks ownerUserId == $_me',
      'query userBlocks blockedUserId == $_me',
    ]);
  });

  test('serves repeated checks from the cache', () async {
    await h.repository.isEffectivelyBlocked(_other);
    await h.repository.isEffectivelyBlocked(_other);
    await h.repository.isEffectivelyBlocked(_third);
    expect(h.loads, 1);
  });

  test('a blocking change invalidates the cache', () async {
    expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
    h.block(_me, _other);
    expect(await h.repository.isEffectivelyBlocked(_other), isFalse);

    h.changes.add(
      const BlockingChange(
        targetUid: _other,
        relationshipBlocked: true,
        blockedByCaller: true,
      ),
    );
    expect(await h.repository.isEffectivelyBlocked(_other), isTrue);
    expect(h.loads, 2);
  });

  test('a user change discards the previous user set', () async {
    h.block(_me, _other);
    expect(await h.repository.isEffectivelyBlocked(_other), isTrue);

    h.auth.signInAs(_third);
    expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
    expect(
      h.db.queriesOn('userBlocks').last,
      'query userBlocks blockedUserId == $_third',
    );

    h.auth.signInAs(null);
    expect(await h.repository.loadCachedEffectiveBlockedUserIds(), isEmpty);
    expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
  });

  test(
    'reloads after the TTL so blocks made by the other user appear',
    () async {
      expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
      h.block(_other, _me);

      h.now = h.now.add(const Duration(minutes: 4, seconds: 59));
      expect(await h.repository.isEffectivelyBlocked(_other), isFalse);
      expect(h.loads, 1);

      h.now = h.now.add(const Duration(seconds: 2));
      expect(await h.repository.isEffectivelyBlocked(_other), isTrue);
      expect(h.loads, 2);
    },
  );

  test(
    'a failed load throws, is not cached, and is never "not blocked"',
    () async {
      h.db.queryErrors['userBlocks'] = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      await expectLater(
        h.repository.isEffectivelyBlocked(_other),
        throwsA(isA<FirebaseException>()),
      );

      h.db.queryErrors.clear();
      h.block(_me, _other);
      expect(await h.repository.isEffectivelyBlocked(_other), isTrue);
    },
  );

  test('self and empty ids are never blocked and need no load', () async {
    expect(await h.repository.isEffectivelyBlocked(_me), isFalse);
    expect(await h.repository.isEffectivelyBlocked('  '), isFalse);
    expect(h.db.log, isEmpty);
  });

  test('the shared instance listens to BlockingChangeCoordinator', () async {
    var loads = 0;
    Future<Set<String>> loader() async {
      loads++;
      return <String>{_other};
    }

    final cache = BlockedUserSetCache.instance..invalidate();
    await cache.get(_me, loader);
    await cache.get(_me, loader);
    expect(loads, 1);
    BlockingChangeCoordinator.instance.publish(
      const BlockingChange(
        targetUid: _other,
        relationshipBlocked: false,
        blockedByCaller: false,
      ),
    );
    await cache.get(_me, loader);
    expect(loads, 2);
    cache.invalidate();
  });
}
