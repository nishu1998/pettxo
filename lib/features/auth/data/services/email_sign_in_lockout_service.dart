import 'package:shared_preferences/shared_preferences.dart';

class EmailSignInLockoutState {
  final int failedAttempts;
  final DateTime? lockedUntil;

  const EmailSignInLockoutState({
    required this.failedAttempts,
    required this.lockedUntil,
  });

  static const int maxFailedAttemptsBeforeLockout = 5;
  static const Duration lockoutDuration = Duration(minutes: 30);

  bool get isLocked {
    final deadline = lockedUntil;
    if (deadline == null) return false;
    return deadline.isAfter(DateTime.now());
  }

  Duration get remainingLockoutDuration {
    final deadline = lockedUntil;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  int get remainingAttemptsBeforeLockout {
    final remaining = maxFailedAttemptsBeforeLockout - failedAttempts;
    return remaining < 0 ? 0 : remaining;
  }
}

class EmailSignInLockoutService {
  static const String _failedAttemptsPrefix =
      'auth_email_sign_in_failed_attempts_';
  static const String _lockedUntilPrefix = 'auth_email_sign_in_locked_until_';

  Future<EmailSignInLockoutState> getState(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) {
      return const EmailSignInLockoutState(
        failedAttempts: 0,
        lockedUntil: null,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final failedAttempts =
        prefs.getInt('$_failedAttemptsPrefix$normalizedEmail') ?? 0;
    final lockedUntilMillis = prefs.getInt(
      '$_lockedUntilPrefix$normalizedEmail',
    );
    final lockedUntil = lockedUntilMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lockedUntilMillis);

    final state = EmailSignInLockoutState(
      failedAttempts: failedAttempts,
      lockedUntil: lockedUntil,
    );

    if (!state.isLocked && lockedUntil != null) {
      await clear(email);
      return const EmailSignInLockoutState(
        failedAttempts: 0,
        lockedUntil: null,
      );
    }

    return state;
  }

  Future<EmailSignInLockoutState> registerWrongPassword(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) {
      return const EmailSignInLockoutState(
        failedAttempts: 0,
        lockedUntil: null,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final currentState = await getState(email);
    if (currentState.isLocked) {
      return currentState;
    }

    final nextFailedAttempts = currentState.failedAttempts + 1;
    DateTime? nextLockedUntil;
    if (nextFailedAttempts >
        EmailSignInLockoutState.maxFailedAttemptsBeforeLockout) {
      nextLockedUntil = DateTime.now().add(
        EmailSignInLockoutState.lockoutDuration,
      );
    }

    await prefs.setInt(
      '$_failedAttemptsPrefix$normalizedEmail',
      nextFailedAttempts,
    );
    if (nextLockedUntil != null) {
      await prefs.setInt(
        '$_lockedUntilPrefix$normalizedEmail',
        nextLockedUntil.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove('$_lockedUntilPrefix$normalizedEmail');
    }

    return EmailSignInLockoutState(
      failedAttempts: nextFailedAttempts,
      lockedUntil: nextLockedUntil,
    );
  }

  Future<void> clear(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_failedAttemptsPrefix$normalizedEmail');
    await prefs.remove('$_lockedUntilPrefix$normalizedEmail');
  }

  String _normalizeEmail(String email) {
    return Uri.encodeComponent(email.trim().toLowerCase());
  }
}
