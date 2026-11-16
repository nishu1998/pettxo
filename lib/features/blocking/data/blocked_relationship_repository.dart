import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum BlockingFailureKind {
  unauthenticated,
  invalidTarget,
  protectedBooking,
  paymentReconciliation,
  supportRequired,
  notFound,
  permissionDenied,
  unavailable,
  timeout,
  unexpected,
}

class BlockingException implements Exception {
  const BlockingException(this.kind);

  final BlockingFailureKind kind;
}

class UserRelationshipState {
  const UserRelationshipState({
    required this.relationshipBlocked,
    required this.blockedByCaller,
    required this.canBlock,
    required this.reasonCode,
    required this.acceptedUnpaidBookingCount,
  });

  final bool relationshipBlocked;
  final bool blockedByCaller;
  final bool canBlock;
  final String reasonCode;
  final int acceptedUnpaidBookingCount;

  bool get blockedByOther => relationshipBlocked && !blockedByCaller;
}

class BlockUserResult {
  const BlockUserResult({
    required this.relationshipBlocked,
    required this.blockedByCaller,
    required this.cancelledBookingCount,
    required this.idempotentReplay,
  });

  final bool relationshipBlocked;
  final bool blockedByCaller;
  final int cancelledBookingCount;
  final bool idempotentReplay;
}

class UnblockUserResult {
  const UnblockUserResult({
    required this.relationshipBlocked,
    required this.blockedByCaller,
    required this.idempotentReplay,
  });

  final bool relationshipBlocked;
  final bool blockedByCaller;
  final bool idempotentReplay;
}

class BlockedUserSummary {
  const BlockedUserSummary({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
}

class OutgoingBlockedUsersPage {
  const OutgoingBlockedUsersPage({
    required this.users,
    required this.cursor,
    required this.hasMore,
  });

  final List<BlockedUserSummary> users;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Read-only Stage 1B view of directed block records. Mutations must go
/// through blockUserV1/unblockUserV1 so booking protection cannot be bypassed.
class BlockedRelationshipRepository {
  BlockedRelationshipRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    Duration timeout = const Duration(seconds: 15),
    String Function()? currentUidOverride,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _timeout = timeout,
       _currentUidOverride = currentUidOverride;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final FirebaseFunctions _functions;
  final Duration _timeout;
  final String Function()? _currentUidOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String get _uid =>
      _currentUidOverride?.call().trim() ?? _auth.currentUser?.uid.trim() ?? '';

  Future<Set<String>> loadEffectiveBlockedUserIds() async {
    final uid = _uid;
    if (uid.isEmpty) return const <String>{};

    final snapshots = await Future.wait([
      _firestore
          .collection('userBlocks')
          .where('ownerUserId', isEqualTo: uid)
          .get(),
      _firestore
          .collection('userBlocks')
          .where('blockedUserId', isEqualTo: uid)
          .get(),
    ]);
    final blocked = <String>{};
    for (final doc in snapshots[0].docs) {
      final data = doc.data();
      final owner = (data['ownerUserId'] as String? ?? '').trim();
      final target = (data['blockedUserId'] as String? ?? '').trim();
      if (owner == uid && target.isNotEmpty && target != uid) {
        blocked.add(target);
      }
    }
    for (final doc in snapshots[1].docs) {
      final data = doc.data();
      final owner = (data['ownerUserId'] as String? ?? '').trim();
      final target = (data['blockedUserId'] as String? ?? '').trim();
      if (target == uid && owner.isNotEmpty && owner != uid) blocked.add(owner);
    }
    return blocked;
  }

  Future<bool> isEffectivelyBlocked(String otherUserId) async {
    final uid = _uid;
    final other = otherUserId.trim();
    if (uid.isEmpty || other.isEmpty || uid == other) return false;
    final snapshots = await Future.wait([
      _firestore.collection('userBlocks').doc('${uid}_$other').get(),
      _firestore.collection('userBlocks').doc('${other}_$uid').get(),
    ]);
    return snapshots.any((snapshot) => snapshot.exists);
  }

  Future<UserRelationshipState> getRelationshipState(String targetUid) async {
    final data = await _call('getUserRelationshipStateV1', targetUid);
    return UserRelationshipState(
      relationshipBlocked: _requiredBool(data, 'relationshipBlocked'),
      blockedByCaller: _requiredBool(data, 'blockedByCaller'),
      canBlock: _requiredBool(data, 'canBlock'),
      reasonCode: (data['reasonCode'] as String? ?? '').trim(),
      acceptedUnpaidBookingCount:
          (data['acceptedUnpaidBookingCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<BlockUserResult> blockUser(String targetUid) async {
    final data = await _call('blockUserV1', targetUid);
    final cancelled = data['cancelledBookingIds'];
    return BlockUserResult(
      relationshipBlocked: _requiredBool(data, 'relationshipBlocked'),
      blockedByCaller: _requiredBool(data, 'blockedByCaller'),
      cancelledBookingCount: cancelled is List ? cancelled.length : 0,
      idempotentReplay: _requiredBool(data, 'idempotentReplay'),
    );
  }

  Future<UnblockUserResult> unblockUser(String targetUid) async {
    final data = await _call('unblockUserV1', targetUid);
    return UnblockUserResult(
      relationshipBlocked: _requiredBool(data, 'relationshipBlocked'),
      blockedByCaller: _requiredBool(data, 'blockedByCaller'),
      idempotentReplay: _requiredBool(data, 'idempotentReplay'),
    );
  }

  Future<OutgoingBlockedUsersPage> loadOutgoingBlockedUsers({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw const BlockingException(BlockingFailureKind.unauthenticated);
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('userBlocks')
        .where('ownerUserId', isEqualTo: uid)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snapshot = await query.get();
    final targetUids = snapshot.docs
        .map((doc) => (doc.data()['blockedUserId'] as String? ?? '').trim())
        .where((targetUid) => targetUid.isNotEmpty && targetUid != uid)
        .toSet()
        .toList(growable: false);
    final profiles = <String, Map<String, dynamic>>{};
    for (var offset = 0; offset < targetUids.length; offset += 30) {
      final end = (offset + 30).clamp(0, targetUids.length);
      final chunk = targetUids.sublist(offset, end);
      if (chunk.isEmpty) continue;
      final users = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final user in users.docs) {
        profiles[user.id] = user.data();
      }
    }
    final summaries = targetUids
        .map((targetUid) {
          final profile = profiles[targetUid] ?? const <String, dynamic>{};
          final name =
              (profile['displayName'] as String? ??
                      profile['name'] as String? ??
                      '')
                  .trim();
          return BlockedUserSummary(
            uid: targetUid,
            displayName: name.isEmpty ? 'Pettxo user' : name,
            username: (profile['username'] as String? ?? '').trim(),
            photoUrl:
                (profile['profileImageUrl'] as String? ??
                        profile['photoUrl'] as String? ??
                        '')
                    .trim(),
          );
        })
        .toList(growable: false);
    return OutgoingBlockedUsersPage(
      users: summaries,
      cursor: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<Map<String, dynamic>> _call(
    String callableName,
    String targetUid,
  ) async {
    final uid = _uid;
    final target = targetUid.trim();
    if (uid.isEmpty) {
      throw const BlockingException(BlockingFailureKind.unauthenticated);
    }
    if (target.isEmpty || target == uid || target.contains('/')) {
      throw const BlockingException(BlockingFailureKind.invalidTarget);
    }
    try {
      final response = await _functions
          .httpsCallable(callableName)
          .call<dynamic>(<String, dynamic>{'targetUid': target})
          .timeout(_timeout);
      final raw = response.data;
      if (raw is! Map) {
        throw const BlockingException(BlockingFailureKind.unexpected);
      }
      return raw.map((key, value) => MapEntry(key.toString(), value));
    } on BlockingException {
      rethrow;
    } on TimeoutException {
      throw const BlockingException(BlockingFailureKind.timeout);
    } on FirebaseFunctionsException catch (error) {
      throw BlockingException(_failureKind(error));
    } catch (_) {
      throw const BlockingException(BlockingFailureKind.unexpected);
    }
  }

  bool _requiredBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is bool) return value;
    throw const BlockingException(BlockingFailureKind.unexpected);
  }

  BlockingFailureKind _failureKind(FirebaseFunctionsException error) {
    final details = error.details;
    final detailCode = details is Map ? details['code']?.toString() ?? '' : '';
    switch (detailCode.trim().toUpperCase()) {
      case 'PROTECTED_BOOKING_EXISTS':
        return BlockingFailureKind.protectedBooking;
      case 'PAYMENT_RECONCILIATION_REQUIRED':
      case 'INVALID_CANONICAL_BOOKING':
      case 'BLOCK_CANCELLATION_TRANSITION_REJECTED':
        return BlockingFailureKind.paymentReconciliation;
      case 'PAIR_BOOKING_LIMIT_EXCEEDED':
        return BlockingFailureKind.supportRequired;
      case 'TARGET_USER_NOT_FOUND':
        return BlockingFailureKind.notFound;
      case 'SELF_BLOCK_NOT_ALLOWED':
      case 'INVALID_TARGET_USER':
        return BlockingFailureKind.invalidTarget;
    }
    switch (error.code.trim().toLowerCase()) {
      case 'unauthenticated':
        return BlockingFailureKind.unauthenticated;
      case 'permission-denied':
        return BlockingFailureKind.permissionDenied;
      case 'not-found':
        return BlockingFailureKind.notFound;
      case 'unavailable':
      case 'network-request-failed':
        return BlockingFailureKind.unavailable;
      case 'deadline-exceeded':
        return BlockingFailureKind.timeout;
      case 'invalid-argument':
        return BlockingFailureKind.invalidTarget;
      case 'failed-precondition':
        return BlockingFailureKind.supportRequired;
      default:
        return BlockingFailureKind.unexpected;
    }
  }
}
