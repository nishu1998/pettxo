import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/services/data/services_tour_preference_service.dart';

void main() {
  setUp(ServicesTourPreferenceService.clearSessionCompletionsForTesting);

  test('uses a versioned per-UID Services key', () {
    final service = ServicesTourPreferenceService(
      store: _MemoryServicesTourStore(),
    );

    expect(service.keyForUid(' user-a '), 'services_tour_v1_user-a');
  });

  test('completion remains independent per UID and from other tours', () async {
    final store = _MemoryServicesTourStore();
    final service = ServicesTourPreferenceService(store: store);
    store.values['home_tour_v1_user-a'] = true;
    store.values['explore_tour_v1_user-a'] = true;

    await service.markCompleted('user-a');

    expect(await service.isCompleted('user-a'), isTrue);
    expect(await service.isCompleted('user-b'), isFalse);
    expect(store.values['home_tour_v1_user-a'], isTrue);
    expect(store.values['explore_tour_v1_user-a'], isTrue);
  });

  test('blank UIDs are treated as ineligible without storage writes', () async {
    final store = _MemoryServicesTourStore();
    final service = ServicesTourPreferenceService(store: store);

    expect(await service.isCompleted('  '), isTrue);
    await service.markCompleted('  ');

    expect(store.values, isEmpty);
  });

  test('persisted completion survives service recreation', () async {
    final store = _MemoryServicesTourStore();
    await ServicesTourPreferenceService(store: store).markCompleted('user-a');
    ServicesTourPreferenceService.clearSessionCompletionsForTesting();

    expect(
      await ServicesTourPreferenceService(store: store).isCompleted('user-a'),
      isTrue,
    );
  });

  test('failed write suppresses repeats during the current session', () async {
    final service = ServicesTourPreferenceService(
      store: _FailingServicesTourStore(),
    );

    await expectLater(service.markCompleted('user-a'), throwsStateError);
    expect(
      await ServicesTourPreferenceService(
        store: _FailingServicesTourStore(),
      ).isCompleted('user-a'),
      isTrue,
    );
  });
}

class _FailingServicesTourStore implements ServicesTourCompletionStore {
  @override
  Future<bool> read(String key) async => false;

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}

class _MemoryServicesTourStore implements ServicesTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}
