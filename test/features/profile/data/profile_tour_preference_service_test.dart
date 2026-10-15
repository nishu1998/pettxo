import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/data/profile_tour_preference_service.dart';

void main() {
  setUp(ProfileTourPreferenceService.clearSessionCompletionsForTesting);

  test('uses a versioned per-UID Profile key', () {
    final service = ProfileTourPreferenceService(
      store: _MemoryProfileTourStore(),
    );

    expect(service.keyForUid(' user-a '), 'profile_tour_v1_user-a');
  });

  test('completion remains independent per UID and from other tours', () async {
    final store = _MemoryProfileTourStore();
    final service = ProfileTourPreferenceService(store: store);
    store.values.addAll(<String, bool>{
      'home_tour_v1_user-a': true,
      'explore_tour_v1_user-a': true,
      'services_tour_v1_user-a': true,
    });

    await service.markCompleted('user-a');

    expect(await service.isCompleted('user-a'), isTrue);
    expect(await service.isCompleted('user-b'), isFalse);
    expect(store.values['home_tour_v1_user-a'], isTrue);
    expect(store.values['explore_tour_v1_user-a'], isTrue);
    expect(store.values['services_tour_v1_user-a'], isTrue);
  });

  test('blank UIDs are ineligible and never write storage', () async {
    final store = _MemoryProfileTourStore();
    final service = ProfileTourPreferenceService(store: store);

    expect(await service.isCompleted('  '), isTrue);
    await service.markCompleted('  ');

    expect(store.values, isEmpty);
  });

  test('persisted completion survives service recreation', () async {
    final store = _MemoryProfileTourStore();
    await ProfileTourPreferenceService(store: store).markCompleted('user-a');
    ProfileTourPreferenceService.clearSessionCompletionsForTesting();

    expect(
      await ProfileTourPreferenceService(store: store).isCompleted('user-a'),
      isTrue,
    );
  });

  test('failed write suppresses repeats during the current session', () async {
    final service = ProfileTourPreferenceService(
      store: _FailingProfileTourStore(),
    );

    await expectLater(service.markCompleted('user-a'), throwsStateError);
    expect(
      await ProfileTourPreferenceService(
        store: _FailingProfileTourStore(),
      ).isCompleted('user-a'),
      isTrue,
    );
  });
}

class _FailingProfileTourStore implements ProfileTourCompletionStore {
  @override
  Future<bool> read(String key) async => false;

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}

class _MemoryProfileTourStore implements ProfileTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}
