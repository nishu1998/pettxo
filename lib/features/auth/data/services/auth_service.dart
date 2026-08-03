import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/firebase_app_scope.dart';
import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/push_notification_service.dart';
import 'pending_email_change_service.dart';
import '../../domain/models/auth_action_exception.dart';
import '../../domain/models/password_reset_request_result.dart';
import '../../domain/utils/auth_error_utils.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import '../../domain/utils/password_reset_request_flow.dart';
import '../../domain/utils/phone_login_eligibility_utils.dart';
import '../../domain/models/auth_result.dart';

class AccountDeletionScheduleResult {
  final String status;
  final DateTime? scheduledDeletionAt;

  const AccountDeletionScheduleResult({
    required this.status,
    required this.scheduledDeletionAt,
  });
}

enum PhoneLoginEligibilityStatus {
  active,
  invalidPhone,
  notFound,
  incompleteSignup,
  blocked,
  accountRecoveryRequired,
  rateLimited,
  networkError,
  unknownError,
}

class PhoneLoginEligibilityResult {
  final PhoneLoginEligibilityStatus status;
  final String normalizedPhoneNumber;
  final String message;
  final bool exists;
  final bool canLogin;
  final String reason;
  final PhoneLoginEligibilityDecision decision;

  const PhoneLoginEligibilityResult({
    required this.status,
    required this.normalizedPhoneNumber,
    required this.message,
    required this.exists,
    required this.canLogin,
    required this.reason,
    required this.decision,
  });

  bool get isApproved =>
      canLogin && status == PhoneLoginEligibilityStatus.active;
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final PendingEmailChangeService _pendingEmailChangeService;
  final Future<Map<String, dynamic>> Function(String normalizedEmail)?
  _passwordResetApprovalRequester;
  final Future<void> Function(String normalizedEmail)?
  _passwordResetEmailSender;
  Future<PasswordResetRequestResult>? _pendingPasswordResetRequest;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    PendingEmailChangeService? pendingEmailChangeService,
    Future<Map<String, dynamic>> Function(String normalizedEmail)?
    passwordResetApprovalRequester,
    Future<void> Function(String normalizedEmail)? passwordResetEmailSender,
  }) : _auth = auth ?? FirebaseAppScope.auth(),
       _functions = functions ?? FirebaseAppScope.functions(),
       _pendingEmailChangeService =
           pendingEmailChangeService ?? const PendingEmailChangeService(),
       _passwordResetApprovalRequester = passwordResetApprovalRequester,
       _passwordResetEmailSender = passwordResetEmailSender;

  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _logAuthenticatedUserState(
        context: 'signUp',
        user: credential.user,
        forceRefreshToken: false,
      );
      await credential.user?.sendEmailVerification();
      await syncTrustedAuthIdentity();
      await _syncNotificationsSafely('sign-up');

      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e), errorCode: e.code);
    } catch (_) {
      return AuthResult(error: "Unexpected error occurred.");
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _logAuthenticatedUserState(
        context: 'login',
        user: credential.user,
        forceRefreshToken: false,
      );
      await syncTrustedAuthIdentity();
      await _syncNotificationsSafely('login');

      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e), errorCode: e.code);
    } catch (_) {
      return AuthResult(error: "Unexpected login error.");
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return;
      }
      throw mapFirebaseAuthException(e);
    }
  }

  Future<PhoneLoginEligibilityResult> checkPhoneLoginEligibility(
    String phoneNumber,
  ) async {
    final normalizedPhoneNumber = phoneNumber.trim();
    final maskedPhoneNumber = maskPhoneNumberForLogs(normalizedPhoneNumber);
    _debugLog(
      'checkPhoneLoginEligibility:prepared '
      'phone=$maskedPhoneNumber region=asia-south1',
    );
    try {
      final callable = _functions.httpsCallable('checkPhoneLoginEligibility');
      _debugLog('checkPhoneLoginEligibility:requestStarted');
      final result = await callable.call<Map<String, dynamic>>({
        'phoneNumber': normalizedPhoneNumber,
      });
      _debugLog(
        'checkPhoneLoginEligibility:resultType=${result.data.runtimeType}',
      );
      final parsed = parsePhoneLoginEligibilityResponse(result.data);
      _debugLog(
        'checkPhoneLoginEligibility:safeResponse '
        'exists=${_safeLogValue(result.data, 'exists')} '
        'canLogin=${_safeLogValue(result.data, 'canLogin')} '
        'reason=${_safeLogValue(result.data, 'reason')}',
      );
      _debugLog(
        'checkPhoneLoginEligibility:parsed '
        'exists=${parsed.exists} canLogin=${parsed.canLogin} '
        'reason=${phoneLoginReasonToWire(parsed.reason)} '
        'malformed=${parsed.isMalformed}',
      );
      final decision = phoneLoginDecisionForParsedResult(parsed);
      _debugLog(
        'checkPhoneLoginEligibility:decision=${_phoneLoginDecisionLabel(decision)}',
      );
      return _resultFromParsedEligibility(
        normalizedPhoneNumber: normalizedPhoneNumber,
        parsed: parsed,
        decision: decision,
      );
    } on FirebaseFunctionsException catch (error) {
      _logFirebaseFunctionsException(
        'checkPhoneLoginEligibility:failed',
        error,
      );
      return _mapPhoneLoginEligibilityFunctionsError(
        error,
        normalizedPhoneNumber: normalizedPhoneNumber,
      );
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'checkPhoneLoginEligibility:unexpected',
        error,
        stackTrace,
      );
      return PhoneLoginEligibilityResult(
        status: PhoneLoginEligibilityStatus.unknownError,
        normalizedPhoneNumber: normalizedPhoneNumber,
        message: 'Unable to verify this phone number right now.',
        exists: false,
        canLogin: false,
        reason: 'technical_failure',
        decision: PhoneLoginEligibilityDecision.showNetworkError,
      );
    }
  }

  Future<PasswordResetRequestResult> requestPasswordReset(String email) {
    final inFlight = _pendingPasswordResetRequest;
    if (inFlight != null) return inFlight;

    final request = _requestPasswordResetInternal(email);
    _pendingPasswordResetRequest = request;
    return request.whenComplete(() {
      if (identical(_pendingPasswordResetRequest, request)) {
        _pendingPasswordResetRequest = null;
      }
    });
  }

  Future<PasswordResetRequestResult> _requestPasswordResetInternal(
    String email,
  ) async {
    return runPasswordResetRequestFlow(
      email: email,
      approveRequest: (normalizedEmail) async {
        if (_passwordResetApprovalRequester != null) {
          await _passwordResetApprovalRequester(normalizedEmail);
          return;
        }
        final callable = _functions.httpsCallable('requestPasswordReset');
        await callable.call<Map<String, dynamic>>({'email': normalizedEmail});
      },
      sendResetEmail: (normalizedEmail) async {
        if (_passwordResetEmailSender != null) {
          await _passwordResetEmailSender(normalizedEmail);
          return;
        }
        await _auth.sendPasswordResetEmail(email: normalizedEmail);
      },
      mapError: (error, _, normalizedEmail) {
        if (error is FirebaseFunctionsException) {
          return _mapPasswordResetFunctionsError(
            error,
            normalizedEmail: normalizedEmail,
          );
        }
        if (error is FirebaseAuthException) {
          return _mapPasswordResetAuthError(
            error,
            normalizedEmail: normalizedEmail,
          );
        }
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.unknownError,
          normalizedEmail: normalizedEmail,
          message: 'Unable to request a password reset right now.',
        );
      },
    );
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Future<void> Function(PhoneAuthCredential credential)
    verificationCompleted,
    required Future<void> Function(String verificationId, int? resendToken)
    codeSent,
    required Future<void> Function(String message) verificationFailed,
    Future<void> Function(String verificationId)? codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    try {
      _debugLog(
        'verifyPhoneNumber:start phone=${_redactPhoneNumber(phoneNumber)} '
        'forceResendingTokenPresent=${forceResendingToken != null}',
      );
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (credential) async {
          _debugLog(
            'verifyPhoneNumber:verificationCompleted '
            'phone=${_redactPhoneNumber(phoneNumber)}',
          );
          await verificationCompleted(credential);
        },
        verificationFailed: (e) async {
          _logFirebaseAuthException('verifyPhoneNumber:verificationFailed', e);
          final message = _mapFirebaseError(e);
          await verificationFailed(message);
        },
        codeSent: (verificationId, resendToken) async {
          _debugLog(
            'verifyPhoneNumber:codeSent '
            'phone=${_redactPhoneNumber(phoneNumber)} '
            'verificationIdLength=${verificationId.length} '
            'resendTokenPresent=${resendToken != null}',
          );
          await codeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (verificationId) async {
          _debugLog(
            'verifyPhoneNumber:codeAutoRetrievalTimeout '
            'phone=${_redactPhoneNumber(phoneNumber)} '
            'verificationIdLength=${verificationId.length}',
          );
          if (codeAutoRetrievalTimeout != null) {
            await codeAutoRetrievalTimeout(verificationId);
          }
        },
      );
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('verifyPhoneNumber:threw', e);
      final message = _mapFirebaseError(e);
      await verificationFailed(message);
    } catch (error, stackTrace) {
      _logUnexpectedError('verifyPhoneNumber:unexpected', error, stackTrace);
      await verificationFailed("Unable to verify phone number right now.");
    }
  }

  Future<UserCredential> signInWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      _debugLog(
        'signInWithPhoneCredential:start '
        'verificationIdLength=${verificationId.length} '
        'smsCodeLength=${smsCode.length}',
      );
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final result = await _auth.signInWithCredential(credential);
      await _logAuthenticatedUserState(
        context: 'phone-otp-login',
        user: result.user,
        forceRefreshToken: true,
      );
      await syncTrustedAuthIdentity();
      await _syncNotificationsSafely('phone-otp-login');
      return result;
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('signInWithPhoneCredential:failed', e);
      throw Exception(_mapFirebaseError(e));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'signInWithPhoneCredential:unexpected',
        error,
        stackTrace,
      );
      throw Exception('Unable to verify the OTP right now.');
    }
  }

  Future<UserCredential> signInWithCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      _debugLog('signInWithCredential:start provider=phone');
      final result = await _auth.signInWithCredential(credential);
      await _logAuthenticatedUserState(
        context: 'phone-auto-login',
        user: result.user,
        forceRefreshToken: true,
      );
      await syncTrustedAuthIdentity();
      await _syncNotificationsSafely('phone-auto-login');
      return result;
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('signInWithCredential:failed', e);
      throw Exception(_mapFirebaseError(e));
    } catch (error, stackTrace) {
      _logUnexpectedError('signInWithCredential:unexpected', error, stackTrace);
      throw Exception('Unable to complete phone sign-in right now.');
    }
  }

  Future<UserCredential> linkCurrentUserWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return linkCurrentUserWithCredential(credential);
  }

  Future<UserCredential> linkCurrentUserWithCredential(
    PhoneAuthCredential credential,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be signed in before linking a phone number.');
    }

    final expectedUid = currentUser.uid;
    try {
      final result = await currentUser.linkWithCredential(credential);
      final linkedUser = result.user;
      if (linkedUser == null ||
          !linkedUidRemainsUnchanged(
            expectedUid: expectedUid,
            actualUid: linkedUser.uid,
          )) {
        throw Exception(
          'Phone linking did not stay on the same Pettxo account. Please try again.',
        );
      }

      await syncTrustedAuthIdentity();
      await _syncNotificationsSafely('phone-link');
      return result;
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('linkCurrentUserWithCredential:failed', e);
      throw Exception(_mapFirebaseError(e));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'linkCurrentUserWithCredential:unexpected',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<void> sendCurrentUserEmailVerification() async {
    final currentUser = _requireCurrentUser();
    try {
      await currentUser.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw mapFirebaseAuthException(e);
    }
  }

  Future<void> linkCurrentUserWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final currentUser = _requireCurrentUser();
    final expectedUid = currentUser.uid;

    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      final result = await currentUser.linkWithCredential(credential);
      final linkedUser = result.user;
      if (linkedUser == null ||
          !linkedUidRemainsUnchanged(
            expectedUid: expectedUid,
            actualUid: linkedUser.uid,
          )) {
        throw const AuthActionException(
          code: 'uid-mismatch',
          message:
              'Pettxo could not safely link this email to your current account.',
        );
      }

      await linkedUser.sendEmailVerification();
      await reloadCurrentUser(syncTrustedIdentity: true);
      final refreshedUser = _requireCurrentUser();
      if (!linkedUidRemainsUnchanged(
        expectedUid: expectedUid,
        actualUid: refreshedUser.uid,
      )) {
        throw const AuthActionException(
          code: 'uid-mismatch',
          message:
              'Pettxo detected an unexpected account change after linking.',
        );
      }
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('linkCurrentUserWithEmailPassword:failed', e);
      throw mapFirebaseAuthException(e);
    } on AuthActionException {
      rethrow;
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'linkCurrentUserWithEmailPassword:unexpected',
        error,
        stackTrace,
      );
      throw const AuthActionException(
        code: 'link-failed',
        message: 'Unable to link email and password right now.',
      );
    }
  }

  Future<void> changeCurrentUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await reauthenticateCurrentUserWithPassword(
        currentPassword: currentPassword,
      );
      final currentUser = _requireCurrentUser();
      await currentUser.updatePassword(newPassword);
      await reloadCurrentUser();
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('changeCurrentUserPassword:failed', e);
      throw mapFirebaseAuthException(e);
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'changeCurrentUserPassword:unexpected',
        error,
        stackTrace,
      );
      throw const AuthActionException(
        code: 'password-update-failed',
        message: 'Unable to change your password right now.',
      );
    }
  }

  Future<void> reauthenticateCurrentUserWithPassword({
    required String currentPassword,
  }) async {
    final currentUser = _requireCurrentUser();
    final email = (currentUser.email ?? '').trim();
    if (email.isEmpty) {
      throw const AuthActionException(
        code: 'missing-email',
        message: 'No verified email is linked to this account yet.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await currentUser.reauthenticateWithCredential(credential);
      await reloadCurrentUser();
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException(
        'reauthenticateCurrentUserWithPassword:failed',
        e,
      );
      throw mapFirebaseAuthException(e);
    }
  }

  Future<void> reauthenticateCurrentUserWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await reauthenticateCurrentUserWithPhoneAuthCredential(credential);
  }

  Future<void> reauthenticateCurrentUserWithPhoneAuthCredential(
    PhoneAuthCredential credential,
  ) async {
    final currentUser = _requireCurrentUser();
    final expectedUid = currentUser.uid;

    try {
      final result = await currentUser.reauthenticateWithCredential(credential);
      final reauthenticatedUser = result.user;
      if (reauthenticatedUser == null ||
          !linkedUidRemainsUnchanged(
            expectedUid: expectedUid,
            actualUid: reauthenticatedUser.uid,
          )) {
        throw const AuthActionException(
          code: 'uid-mismatch',
          message:
              'Pettxo could not confirm that this phone verification belongs to your current account.',
        );
      }
      await reloadCurrentUser();
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException(
        'reauthenticateCurrentUserWithPhoneCredential:failed',
        e,
      );
      throw mapFirebaseAuthException(e);
    }
  }

  Future<String> changeUsername({required String username}) async {
    try {
      final callable = _functions.httpsCallable('changeUsername');
      final result = await callable.call<Map<String, dynamic>>({
        'username': username,
      });
      final data = Map<String, dynamic>.from(result.data);
      return (data['username'] as String? ?? '').trim();
    } on FirebaseFunctionsException catch (e) {
      throw mapFunctionsActionException(e);
    }
  }

  Future<String> completeOnboardingProfile({
    required String role,
    required String displayName,
    required String username,
    required String state,
    required String city,
    required bool acceptedTerms,
    required bool acceptedPrivacy,
    required bool acceptedProviderAgreement,
  }) async {
    try {
      final callable = _functions.httpsCallable('completeOnboardingProfile');
      final result = await callable.call<Map<String, dynamic>>({
        'role': role,
        'displayName': displayName,
        'username': username,
        'state': state,
        'city': city,
        'acceptedTerms': acceptedTerms,
        'acceptedPrivacy': acceptedPrivacy,
        'acceptedProviderAgreement': acceptedProviderAgreement,
      });
      final data = Map<String, dynamic>.from(result.data);
      return (data['username'] as String? ?? '').trim();
    } on FirebaseFunctionsException catch (e) {
      throw mapFunctionsActionException(e);
    }
  }

  Future<void> beginCurrentUserEmailChange({required String newEmail}) async {
    final currentUser = _requireCurrentUser();
    final expectedUid = currentUser.uid;

    try {
      final dynamic user = currentUser;
      await user.verifyBeforeUpdateEmail(newEmail.trim());
      await reloadCurrentUser();
      final refreshedUser = _requireCurrentUser();
      if (!linkedUidRemainsUnchanged(
        expectedUid: expectedUid,
        actualUid: refreshedUser.uid,
      )) {
        throw const AuthActionException(
          code: 'uid-mismatch',
          message: 'Pettxo detected an unexpected account change.',
        );
      }
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('beginCurrentUserEmailChange:failed', e);
      throw mapFirebaseAuthException(e);
    }
  }

  Future<void> updateCurrentUserPhoneNumber({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await updateCurrentUserPhoneNumberWithCredential(credential);
  }

  Future<void> updateCurrentUserPhoneNumberWithCredential(
    PhoneAuthCredential credential,
  ) async {
    final currentUser = _requireCurrentUser();
    final expectedUid = currentUser.uid;

    try {
      await currentUser.updatePhoneNumber(credential);
      await reloadCurrentUser(syncTrustedIdentity: true);
      final refreshedUser = _requireCurrentUser();
      if (!linkedUidRemainsUnchanged(
        expectedUid: expectedUid,
        actualUid: refreshedUser.uid,
      )) {
        throw const AuthActionException(
          code: 'uid-mismatch',
          message:
              'Pettxo detected an unexpected account change after updating your phone number.',
        );
      }
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('updateCurrentUserPhoneNumber:failed', e);
      throw mapFirebaseAuthException(e);
    }
  }

  Future<User?> reloadCurrentUser({bool syncTrustedIdentity = false}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;
    await currentUser.reload();
    if (syncTrustedIdentity) {
      await syncTrustedAuthIdentity();
    }
    return _auth.currentUser;
  }

  Future<void> syncTrustedAuthIdentity() async {
    if (_auth.currentUser == null) return;
    try {
      FirebaseAppScope.debugLogPair(
        context: 'syncTrustedAuthIdentity',
        auth: _auth,
        functions: _functions,
      );
      final callable = _functions.httpsCallable('syncAuthIdentity');
      await callable.call<Map<String, dynamic>>();
      _debugLog(
        'syncTrustedAuthIdentity:success uid=${_auth.currentUser?.uid ?? ''}',
      );
    } catch (error, stackTrace) {
      _logUnexpectedError('syncTrustedAuthIdentity:failed', error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid.trim();
    try {
      await PushNotificationService.instance
          .unregisterCurrentDeviceTokenForLogout();
    } catch (_) {
      // Token cleanup should not block sign-out.
    }
    if (uid != null && uid.isNotEmpty) {
      await _pendingEmailChangeService.clearPendingEmail(uid);
    }
    LegalAcceptanceSessionService.instance.clearSignupConsent();
    await _auth.signOut();
  }

  Future<AccountDeletionScheduleResult> requestAccountDeletion({
    String reason = '',
  }) async {
    final callable = _functions.httpsCallable('requestAccountDeletion');
    final result = await callable.call<Map<String, dynamic>>({
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    final data = Map<String, dynamic>.from(result.data);
    final rawDate = (data['scheduledDeletionAt'] as String? ?? '').trim();
    return AccountDeletionScheduleResult(
      status: (data['status'] as String? ?? 'pendingDeletion').trim(),
      scheduledDeletionAt: rawDate.isEmpty
          ? null
          : DateTime.tryParse(rawDate)?.toLocal(),
    );
  }

  Future<void> restoreAccount() async {
    final callable = _functions.httpsCallable('restoreAccount');
    await callable.call<Map<String, dynamic>>();
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _logAuthenticatedUserState({
    required String context,
    required User? user,
    required bool forceRefreshToken,
  }) async {
    if (!kDebugMode) return;
    final uid = user?.uid.trim() ?? '';
    final providerIds = (user?.providerData ?? const <UserInfo>[])
        .map((provider) => provider.providerId.trim())
        .where((providerId) => providerId.isNotEmpty)
        .toList(growable: false);
    var tokenSuccess = false;
    try {
      final token = await user?.getIdToken(forceRefreshToken);
      tokenSuccess = token?.trim().isNotEmpty == true;
    } catch (_) {
      tokenSuccess = false;
    }
    _debugLog(
      'Auth login debug -> context=$context uid=$uid tokenSuccess=$tokenSuccess providers=${providerIds.join(',')}',
    );
  }

  User _requireCurrentUser() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw const AuthActionException(
        code: 'no-current-user',
        message: 'You must be signed in to continue.',
      );
    }
    return currentUser;
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    return mapFirebaseAuthErrorCode(e.code);
  }

  PasswordResetRequestResult _mapPasswordResetFunctionsError(
    FirebaseFunctionsException error, {
    required String normalizedEmail,
  }) {
    String code = error.code;
    final details = error.details;
    if (details is Map) {
      final appCode = details['appCode'];
      if (appCode is String && appCode.trim().isNotEmpty) {
        code = appCode.trim();
      }
    }

    switch (code) {
      case 'invalid-email':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.invalidEmail,
          normalizedEmail: normalizedEmail,
          message: 'Enter a valid email address.',
        );
      case 'account-not-found':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.accountNotFound,
          normalizedEmail: normalizedEmail,
          message:
              'We couldn’t find a password-enabled Pettxo account with this email.',
        );
      case 'phone-only-account':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.phoneOnlyAccount,
          normalizedEmail: normalizedEmail,
          message:
              'This account does not have a password. Sign in using your phone number.',
        );
      case 'account-pending-deletion':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.accountPendingDeletion,
          normalizedEmail: normalizedEmail,
          message:
              'This account is in recovery mode. Sign in normally to continue account recovery.',
        );
      case 'account-disabled':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.accountDisabled,
          normalizedEmail: normalizedEmail,
          message: 'This account cannot reset its password right now.',
        );
      case 'rate-limited':
      case 'resource-exhausted':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.rateLimited,
          normalizedEmail: normalizedEmail,
          message:
              'Please wait a moment before requesting another reset email.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.networkError,
          normalizedEmail: normalizedEmail,
          message: 'Network error. Please try again.',
        );
      default:
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.unknownError,
          normalizedEmail: normalizedEmail,
          message: 'Unable to request a password reset right now.',
        );
    }
  }

  PasswordResetRequestResult _mapPasswordResetAuthError(
    FirebaseAuthException error, {
    required String normalizedEmail,
  }) {
    switch (error.code) {
      case 'invalid-email':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.invalidEmail,
          normalizedEmail: normalizedEmail,
          message: 'Enter a valid email address.',
        );
      case 'network-request-failed':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.networkError,
          normalizedEmail: normalizedEmail,
          message: 'Network error. Please try again.',
        );
      case 'too-many-requests':
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.rateLimited,
          normalizedEmail: normalizedEmail,
          message:
              'Please wait a moment before requesting another reset email.',
        );
      default:
        return PasswordResetRequestResult(
          status: PasswordResetRequestStatus.unknownError,
          normalizedEmail: normalizedEmail,
          message: 'Unable to request a password reset right now.',
        );
    }
  }

  PhoneLoginEligibilityResult _mapPhoneLoginEligibilityFunctionsError(
    FirebaseFunctionsException error, {
    required String normalizedPhoneNumber,
  }) {
    String code = error.code;
    final details = error.details;
    if (details is Map) {
      final appCode = details['appCode'];
      if (appCode is String && appCode.trim().isNotEmpty) {
        code = appCode.trim();
      }
    }

    switch (code) {
      case 'invalid-phone':
        return PhoneLoginEligibilityResult(
          status: PhoneLoginEligibilityStatus.invalidPhone,
          normalizedPhoneNumber: normalizedPhoneNumber,
          message: 'Enter a valid phone number.',
          exists: false,
          canLogin: false,
          reason: 'invalid_phone',
          decision: PhoneLoginEligibilityDecision.showNetworkError,
        );
      case 'rate-limited':
      case 'resource-exhausted':
        return PhoneLoginEligibilityResult(
          status: PhoneLoginEligibilityStatus.rateLimited,
          normalizedPhoneNumber: normalizedPhoneNumber,
          message: 'Please wait a moment before trying again.',
          exists: false,
          canLogin: false,
          reason: 'rate_limited',
          decision: PhoneLoginEligibilityDecision.showNetworkError,
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return PhoneLoginEligibilityResult(
          status: PhoneLoginEligibilityStatus.networkError,
          normalizedPhoneNumber: normalizedPhoneNumber,
          message: 'Network error. Please try again.',
          exists: false,
          canLogin: false,
          reason: 'network_error',
          decision: PhoneLoginEligibilityDecision.showNetworkError,
        );
      default:
        return PhoneLoginEligibilityResult(
          status: PhoneLoginEligibilityStatus.unknownError,
          normalizedPhoneNumber: normalizedPhoneNumber,
          message: 'Unable to verify this phone number right now.',
          exists: false,
          canLogin: false,
          reason: 'technical_failure',
          decision: PhoneLoginEligibilityDecision.showNetworkError,
        );
    }
  }

  PhoneLoginEligibilityResult _resultFromParsedEligibility({
    required String normalizedPhoneNumber,
    required ParsedPhoneLoginEligibility parsed,
    required PhoneLoginEligibilityDecision decision,
  }) {
    return PhoneLoginEligibilityResult(
      status: _statusFromParsedEligibility(parsed),
      normalizedPhoneNumber: normalizedPhoneNumber,
      message: phoneLoginMessageForParsedResult(parsed),
      exists: parsed.exists,
      canLogin: parsed.canLogin,
      reason: phoneLoginReasonToWire(parsed.reason),
      decision: decision,
    );
  }

  PhoneLoginEligibilityStatus _statusFromParsedEligibility(
    ParsedPhoneLoginEligibility parsed,
  ) {
    if (parsed.isMalformed) return PhoneLoginEligibilityStatus.unknownError;
    switch (parsed.reason) {
      case PhoneLoginEligibilityReason.active:
        return parsed.canLogin
            ? PhoneLoginEligibilityStatus.active
            : PhoneLoginEligibilityStatus.unknownError;
      case PhoneLoginEligibilityReason.notFound:
        return PhoneLoginEligibilityStatus.notFound;
      case PhoneLoginEligibilityReason.incompleteSignup:
        return PhoneLoginEligibilityStatus.incompleteSignup;
      case PhoneLoginEligibilityReason.blocked:
        return PhoneLoginEligibilityStatus.blocked;
      case PhoneLoginEligibilityReason.accountRecoveryRequired:
        return PhoneLoginEligibilityStatus.accountRecoveryRequired;
      case PhoneLoginEligibilityReason.technicalFailure:
        return PhoneLoginEligibilityStatus.unknownError;
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('AuthService $message');
    }
  }

  void _logFirebaseFunctionsException(
    String context,
    FirebaseFunctionsException error,
  ) {
    if (!kDebugMode) return;
    debugPrint(
      'AuthService $context code=${error.code} '
      'message=${error.message ?? error.toString()} details=${error.details}',
    );
    debugPrintStack(stackTrace: error.stackTrace);
  }

  void _logFirebaseAuthException(String context, FirebaseAuthException error) {
    if (!kDebugMode) return;
    debugPrint(
      'AuthService $context code=${error.code} '
      'message=${error.message ?? error.toString()}',
    );
    if (error.stackTrace != null) {
      debugPrintStack(stackTrace: error.stackTrace);
    }
  }

  void _logUnexpectedError(
    String context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint('AuthService $context error=$error');
    debugPrintStack(stackTrace: stackTrace);
  }

  String _redactPhoneNumber(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.length <= 4) return trimmed;
    final suffix = trimmed.substring(trimmed.length - 4);
    return '***$suffix';
  }

  String _phoneLoginDecisionLabel(PhoneLoginEligibilityDecision decision) {
    switch (decision) {
      case PhoneLoginEligibilityDecision.startOtp:
        return 'startOtp';
      case PhoneLoginEligibilityDecision.showNotFound:
        return 'showNotFound';
      case PhoneLoginEligibilityDecision.showBlocked:
        return 'showBlocked';
      case PhoneLoginEligibilityDecision.showRecovery:
        return 'showRecovery';
      case PhoneLoginEligibilityDecision.showNetworkError:
        return 'showNetworkError';
    }
  }

  Object? _safeLogValue(Object? value, String key) {
    if (value is Map) return value[key];
    return null;
  }

  Future<void> _syncNotificationsSafely(String reason) async {
    try {
      await PushNotificationService.instance.forceSyncCurrentUser(
        reason: reason,
      );
    } catch (error, stackTrace) {
      _logUnexpectedError('notificationSync:$reason', error, stackTrace);
    }
  }
}
