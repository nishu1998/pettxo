import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/data/home_tour_preference_service.dart';

void main() {
  setUp(HomeTourPreferenceService.clearSessionCompletionsForTesting);

  test('uses a versioned per-UID completion key', () async {
    final store = _MemoryHomeTourStore();
    final service = HomeTourPreferenceService(store: store);

    expect(service.keyForUid(' user-a '), 'home_tour_v1_user-a');
    expect(await service.isCompleted('user-a'), isFalse);

    await service.markCompleted('user-a');

    expect(await service.isCompleted('user-a'), isTrue);
    expect(await service.isCompleted('user-b'), isFalse);
  });

  test('empty UIDs are ineligible and are never persisted', () async {
    final store = _MemoryHomeTourStore();
    final service = HomeTourPreferenceService(store: store);

    expect(await service.isCompleted('  '), isTrue);
    await service.markCompleted('');

    expect(store.values, isEmpty);
  });

  test('persisted completion survives service recreation', () async {
    final store = _MemoryHomeTourStore();
    await HomeTourPreferenceService(store: store).markCompleted('user-a');
    HomeTourPreferenceService.clearSessionCompletionsForTesting();

    expect(
      await HomeTourPreferenceService(store: store).isCompleted('user-a'),
      isTrue,
    );
  });

  test('failed write stays completed only for the current session', () async {
    final service = HomeTourPreferenceService(store: _FailingHomeTourStore());

    await expectLater(service.markCompleted('user-a'), throwsStateError);
    expect(
      await HomeTourPreferenceService(
        store: _FailingHomeTourStore(),
      ).isCompleted('user-a'),
      isTrue,
    );
  });
}

class _FailingHomeTourStore implements HomeTourCompletionStore {
  @override
  Future<bool> read(String key) async => false;

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}

class _MemoryHomeTourStore implements HomeTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}
