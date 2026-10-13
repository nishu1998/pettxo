import 'dart:async';

/// Serializes operating-system permission prompts during app startup.
///
/// Android and iOS can behave unpredictably when two plugins request different
/// permissions at the same time. Features still decide whether and why to ask;
/// this coordinator only prevents overlapping prompt flows.
class PermissionPromptCoordinator {
  PermissionPromptCoordinator._();

  static final PermissionPromptCoordinator instance =
      PermissionPromptCoordinator._();

  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final result = Completer<T>();
    _tail = () async {
      try {
        await previous;
      } catch (_) {
        // A previous prompt failure must not block later permission flows.
      }
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }();
    return result.future;
  }
}
