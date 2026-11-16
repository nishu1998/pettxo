import 'dart:async';

class BlockingChange {
  const BlockingChange({
    required this.targetUid,
    required this.relationshipBlocked,
    required this.blockedByCaller,
  });

  final String targetUid;
  final bool relationshipBlocked;
  final bool blockedByCaller;
}

/// Process-local invalidation signal. It carries no relationship cache and
/// causes active screens to re-read their existing authoritative repositories.
class BlockingChangeCoordinator {
  BlockingChangeCoordinator._();

  static final BlockingChangeCoordinator instance =
      BlockingChangeCoordinator._();

  final StreamController<BlockingChange> _changes =
      StreamController<BlockingChange>.broadcast(sync: true);

  Stream<BlockingChange> get changes => _changes.stream;

  void publish(BlockingChange change) => _changes.add(change);
}
