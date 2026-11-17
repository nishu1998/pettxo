import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_user_avatar.dart';
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

    repository.users = const [];
    repository.completeUnblock();
    await tester.pumpAndSettle();
    expect(find.text('Blocked Person'), findsNothing);
  });

  testWidgets('empty list (blocking gate off) shows a friendly empty state', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository();
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blocked accounts'), findsOneWidget);
    expect(find.text("You haven't blocked anyone."), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a raw load failure never reaches the screen', (tester) async {
    final repository = _FakeBlockingRepository(
      loadError: StateError('FIRESTORE INTERNAL ASSERTION FAILED: raw detail'),
    );
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load blocked accounts right now.'), findsOne);
    expect(find.textContaining('FIRESTORE'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated list shows name, username and photo per account', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository(users: _twoUsers);
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('First Blocked'), findsOneWidget);
    expect(find.text('@first.blocked'), findsOneWidget);
    expect(find.text('Second Blocked'), findsOneWidget);
    expect(find.text('@second'), findsOneWidget);
    expect(find.byType(AppUserAvatar), findsNWidgets(2));
    final avatar = tester.widget<AppUserAvatar>(
      find.byType(AppUserAvatar).first,
    );
    expect(avatar.imageUrl, 'https://example.invalid/first.jpg');
    expect(find.text('Unblock'), findsNWidgets(2));
  });

  testWidgets('cancelling the confirmation does not call the backend', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository(users: _twoUsers);
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unblock').first);
    await tester.pumpAndSettle();
    expect(find.text('Unblock this user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.unblockCalls, 0);
    expect(repository.loadCalls, 1);
    expect(find.text('First Blocked'), findsOneWidget);
  });

  testWidgets('confirmed unblock calls the backend, then reloads the list', (
    tester,
  ) async {
    // AppSnackbar drops an identical message shown within 1.2s of wall-clock
    // time; an earlier test in this file shows the same success message.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1300)),
    );
    final repository = _FakeBlockingRepository(users: _twoUsers);
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    repository.users = [_twoUsers.last];
    await tester.tap(find.text('Unblock').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock User'));
    await tester.pumpAndSettle();

    expect(repository.unblockedUids, ['outgoing-1']);
    expect(repository.loadCalls, 2);
    expect(find.text('User unblocked successfully.'), findsOneWidget);
    expect(find.text('First Blocked'), findsNothing);
    expect(find.text('Second Blocked'), findsOneWidget);
  });

  testWidgets('unblock failure keeps the account and shows a clear message', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository(
      users: _twoUsers,
      unblockError: const BlockingException(BlockingFailureKind.unavailable),
    );
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unblock').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock User'));
    await tester.pumpAndSettle();

    expect(repository.unblockCalls, 1);
    expect(repository.loadCalls, 1);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('First Blocked'), findsOneWidget);
    expect(find.text('Unblock'), findsNWidgets(2));
  });

  testWidgets('an unexpected unblock error never shows raw details', (
    tester,
  ) async {
    final repository = _FakeBlockingRepository(
      users: _twoUsers,
      unblockError: StateError('raw internal detail'),
    );
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unblock').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock User'));
    await tester.pumpAndSettle();

    expect(
      find.text('We could not update this relationship right now.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw internal detail'), findsNothing);
    expect(find.text('First Blocked'), findsOneWidget);
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

const _twoUsers = [
  BlockedUserSummary(
    uid: 'outgoing-1',
    displayName: 'First Blocked',
    username: 'first.blocked',
    photoUrl: 'https://example.invalid/first.jpg',
  ),
  BlockedUserSummary(
    uid: 'outgoing-2',
    displayName: 'Second Blocked',
    username: '@second',
    photoUrl: '',
  ),
];

class _FakeBlockingRepository extends BlockedRelationshipRepository {
  _FakeBlockingRepository({
    this.users = const [],
    this.loadError,
    this.unblockError,
    this.pendingUnblock = false,
  }) : super(functions: _NoopFunctions(), currentUidOverride: () => 'caller-1');

  List<BlockedUserSummary> users;
  final Object? loadError;
  final Object? unblockError;
  final bool pendingUnblock;
  final List<String> unblockedUids = <String>[];
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
    if (unblockError case final error?) return Future.error(error);
    unblockedUids.add(targetUid);
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
