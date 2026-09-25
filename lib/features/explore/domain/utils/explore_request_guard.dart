bool isCurrentExploreRequest({
  required int requestGeneration,
  required int currentGeneration,
  required String requestUid,
  required String currentUid,
}) {
  return requestGeneration == currentGeneration && requestUid == currentUid;
}

bool canRestoreExploreCache({
  required String cacheOwnerUid,
  required String currentUid,
}) {
  final normalizedCurrentUid = currentUid.trim();
  return normalizedCurrentUid.isNotEmpty &&
      cacheOwnerUid.trim() == normalizedCurrentUid;
}
