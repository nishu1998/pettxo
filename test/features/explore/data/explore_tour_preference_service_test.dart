import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/data/explore_tour_preference_service.dart';

void main() {
  setUp(ExploreTourPreferenceService.clearSessionCompletionsForTesting);

  test('uses a versioned per-UID completion key', () async {
    final store = _MemoryExploreTourStore();
    final service = ExploreTourPreferenceService(store: store);

    expect(service.keyForUid(' user-a '), 'explore_tour_v1_user-a');
    expect(await service.isCompleted('user-a'), isFalse);

    await service.markCompleted('user-a');

    expect(store.values['explore_tour_v1_user-a'], isTrue);
    expect(await service.isCompleted('user-a'), isTrue);
    expect(await service.isCompleted('user-b'), isFalse);
  });

  test('empty UIDs are ineligible and are never persisted', () async {
    final store = _MemoryExploreTourStore();
    final service = ExploreTourPreferenceService(store: store);

    expect(await service.isCompleted('  '), isTrue);
    await service.markCompleted('  ');

    expect(store.values, isEmpty);
  });

  test('persisted completion survives service recreation', () async {
    final store = _MemoryExploreTourStore();
    await ExploreTourPreferenceService(store: store).markCompleted('user-a');
    ExploreTourPreferenceService.clearSessionCompletionsForTesting();

    expect(
      await ExploreTourPreferenceService(store: store).isCompleted('user-a'),
      isTrue,
    );
  });

  test('failed write suppresses repeats during the current session', () async {
    final service = ExploreTourPreferenceService(
      store: _FailingExploreTourStore(),
    );

    await expectLater(service.markCompleted('user-a'), throwsStateError);
    expect(
      await ExploreTourPreferenceService(
        store: _FailingExploreTourStore(),
      ).isCompleted('user-a'),
      isTrue,
    );
  });
}

class _FailingExploreTourStore implements ExploreTourCompletionStore {
  @override
  Future<bool> read(String key) async => false;

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}

class _MemoryExploreTourStore implements ExploreTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}
