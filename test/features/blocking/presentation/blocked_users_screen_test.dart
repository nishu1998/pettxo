import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_relationship_repository.dart';
import 'package:pettexo/features/blocking/presentation/screens/blocked_users_screen.dart';

void main() {
  testWidgets(
    'shows only the outgoing blocked-user page and empty-safe profile data',
    (tester) async {
      final repository = _FakeBlockingRepository(
        users: const [
          BlockedUserSummary(
            uid: 'outgoing-1',
            displayName: 'Blocked Person',
            username: 'blocked.person',
            photoUrl: '',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: BlockedUsersScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Blocked Person'), findsOneWidget);
      expect(find.text('@blocked.person'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);
      expect(repository.loadCalls, 1);
    },
  );

  testWidgets('unblock confirmation prevents duplicate submissions', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository(
      users: const [
        BlockedUserSummary(
          uid: 'outgoing-1',
          displayName: 'Blocked Person',
          username: '',
          photoUrl: '',
        ),
      ],
      pendingUnblock: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock User'));
    await tester.pump();

    expect(find.text('Unblocking...'), findsOneWidget);
    await tester.tap(find.text('Unblocking...'));
    expect(repository.unblockCalls, 1);

    repository.completeUnblock();
    await tester.pumpAndSettle();
    expect(find.text('Blocked Person'), findsNothing);
  });

  testWidgets('signed-out load has a safe retry state', (tester) async {
    final repository = _FakeBlockingRepository(
      loadError: const BlockingException(BlockingFailureKind.unauthenticated),
    );
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Please sign in and try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _FakeBlockingRepository extends BlockedRelationshipRepository {
  _FakeBlockingRepository({
    this.users = const [],
    this.loadError,
    this.pendingUnblock = false,
  }) : super(functions: _NoopFunctions(), currentUidOverride: () => 'caller-1');

  final List<BlockedUserSummary> users;
  final Object? loadError;
  final bool pendingUnblock;
  final Completer<UnblockUserResult> _unblockCompleter =
      Completer<UnblockUserResult>();
  int loadCalls = 0;
  int unblockCalls = 0;

  @override
  Future<OutgoingBlockedUsersPage> loadOutgoingBlockedUsers({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    loadCalls += 1;
    if (loadError case final error?) throw error;
    return OutgoingBlockedUsersPage(users: users, cursor: null, hasMore: false);
  }

  @override
  Future<UnblockUserResult> unblockUser(String targetUid) {
    unblockCalls += 1;
    if (pendingUnblock) return _unblockCompleter.future;
    return Future.value(
      const UnblockUserResult(
        relationshipBlocked: false,
        blockedByCaller: false,
        idempotentReplay: false,
      ),
    );
  }

  void completeUnblock() {
    _unblockCompleter.complete(
      const UnblockUserResult(
        relationshipBlocked: false,
        blockedByCaller: false,
        idempotentReplay: false,
      ),
    );
  }
}

class _NoopFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
