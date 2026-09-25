import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/domain/utils/explore_request_guard.dart';

void main() {
  test('stale request cannot overwrite a newer refresh', () {
    expect(
      isCurrentExploreRequest(
        requestGeneration: 1,
        currentGeneration: 2,
        requestUid: 'viewer-a',
        currentUid: 'viewer-a',
      ),
      isFalse,
    );
  });

  test('account change invalidates requests and cached Explore state', () {
    expect(
      isCurrentExploreRequest(
        requestGeneration: 2,
        currentGeneration: 2,
        requestUid: 'viewer-a',
        currentUid: 'viewer-b',
      ),
      isFalse,
    );
    expect(
      canRestoreExploreCache(cacheOwnerUid: 'viewer-a', currentUid: 'viewer-b'),
      isFalse,
    );
    expect(
      canRestoreExploreCache(cacheOwnerUid: 'viewer-b', currentUid: 'viewer-b'),
      isTrue,
    );
  });
}
