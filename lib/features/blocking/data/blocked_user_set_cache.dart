import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/blocking_change_coordinator.dart';

/// Process-wide, in-memory cache of the signed-in user's effective blocked-user
/// set (users they blocked plus users who blocked them).
///
/// It exists so per-action UX checks (like, comment, share, opening a service)
/// do not each read Firestore. It is UX only: Firestore Rules enforce blocks on
/// every write regardless of what this cache says.
///
/// - Keyed by UID: a different (or empty) UID discards the cached set.
/// - Cleared on every [BlockingChange] (block/unblock made on this device).
/// - Expires after [ttl] so blocks made by the other person are picked up.
/// - Failed loads are never cached; the error propagates to the caller.
class BlockedUserSetCache {
  BlockedUserSetCache({
    Stream<BlockingChange>? changes,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now {
    _subscription = changes?.listen((_) => invalidate());
  }

  static final BlockedUserSetCache instance = BlockedUserSetCache(
    changes: BlockingChangeCoordinator.instance.changes,
  );

  final Duration ttl;
  final DateTime Function() _now;
  StreamSubscription<BlockingChange>? _subscription;

  String _uid = '';
  Set<String>? _blockedUserIds;
  DateTime? _loadedAt;
  Future<Set<String>>? _inFlight;
  int _generation = 0;

  /// Returns the cached set for [uid], or loads it with [loader].
  Future<Set<String>> get(String uid, Future<Set<String>> Function() loader) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      invalidate();
      return Future.value(const <String>{});
    }
    if (normalizedUid != _uid) {
      invalidate();
      _uid = normalizedUid;
    }

    final cached = _blockedUserIds;
    final loadedAt = _loadedAt;
    if (cached != null &&
        loadedAt != null &&
        _now().difference(loadedAt) < ttl) {
      return Future.value(cached);
    }

    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final generation = _generation;
    final future = loader().then(
      (ids) {
        final frozen = Set<String>.unmodifiable(ids);
        if (generation == _generation && normalizedUid == _uid) {
          _blockedUserIds = frozen;
          _loadedAt = _now();
          _inFlight = null;
        }
        return frozen;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation == _generation) _inFlight = null;
        return Future<Set<String>>.error(error, stackTrace);
      },
    );
    _inFlight = future;
    return future;
  }

  /// Drops the cached set and any in-flight load result.
  void invalidate() {
    _generation++;
    _uid = '';
    _blockedUserIds = null;
    _loadedAt = null;
    _inFlight = null;
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
