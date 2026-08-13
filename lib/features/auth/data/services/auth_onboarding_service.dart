import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/firestore_cache_service.dart';
import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import 'auth_service.dart';

class AuthOnboardingService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthService _authService;
  final LegalAcceptanceSessionService _legalAcceptanceSessionService;

  AuthOnboardingService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthService? authService,
    LegalAcceptanceSessionService? legalAcceptanceSessionService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authService = authService ?? AuthService(),
       _legalAcceptanceSessionService =
           legalAcceptanceSessionService ??
           LegalAcceptanceSessionService.instance;

  Future<AuthOnboardingResolution> resolveCurrentState({
    bool reloadUser = false,
  }) async {
    var user = _auth.currentUser;
    if (user != null && reloadUser) {
      await user.reload();
      user = _auth.currentUser;
    }

    if (user == null) {
      return resolveAuthOnboardingState(auth: null, profile: null);
    }

    await _authService.syncTrustedAuthIdentity();

    final publicRef = _firestore.collection('users').doc(user.uid);
    final privateRef = _firestore.collection('userPrivate').doc(user.uid);
    final snapshots = await Future.wait([
      FirestoreCacheService.getDocCacheFirst(publicRef),
      FirestoreCacheService.getDocCacheFirst(privateRef),
    ]);
    final publicSnapshot = snapshots[0];
    final privateSnapshot = snapshots[1];
    final publicData = publicSnapshot.data();
    final privateData = privateSnapshot.data();
    final publicMap = publicData ?? const <String, dynamic>{};
    final privateMap = privateData ?? const <String, dynamic>{};
    final hasPendingSignupConsent = await _legalAcceptanceSessionService
        .readPendingSignupConsent(uid: user.uid);

    ProfileCompletionSnapshot? profile;
    if (publicSnapshot.exists || privateSnapshot.exists) {
      final normalizedUsername =
          (publicMap['usernameLowercase'] as String? ??
                  publicMap['username'] as String? ??
                  '')
              .trim();
      var usernameReservationMatchesUid = false;

      if (normalizedUsername.isNotEmpty) {
        try {
          final usernameSnapshot = await FirestoreCacheService.getDocCacheFirst(
            _firestore.collection('usernames').doc(normalizedUsername),
          );
          final reservedUid = (usernameSnapshot.data()?['uid'] as String? ?? '')
              .trim();
          usernameReservationMatchesUid = reservedUid == user.uid;
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              'AuthRouteResolver username reservation lookup skipped uid=${user.uid} username=$normalizedUsername error=$error',
            );
          }
        }
      }

      profile = ProfileCompletionSnapshot(
        uid: (publicMap['uid'] as String? ?? user.uid).trim(),
        role: (publicMap['role'] as String? ?? '').trim(),
        displayName:
            (publicMap['displayName'] as String? ??
                    publicMap['name'] as String? ??
                    '')
                .trim(),
        username: (publicMap['username'] as String? ?? '').trim(),
        usernameLowercase: (publicMap['usernameLowercase'] as String? ?? '')
            .trim(),
        state: (publicMap['state'] as String? ?? '').trim(),
        city: (publicMap['city'] as String? ?? '').trim(),
        address: (publicMap['address'] as String? ?? '').trim(),
        legacyLocation: (publicMap['location'] as String? ?? '').trim(),
        usernameReservationMatchesUid: usernameReservationMatchesUid,
        hasPublicProfile: publicSnapshot.exists,
        hasPrivateProfile: privateSnapshot.exists,
        accountStatus:
            (publicMap['accountStatus'] as String? ??
                    privateMap['accountStatus'] as String? ??
                    'active')
                .trim(),
        scheduledDeletionAt: privateMap['scheduledDeletionAt'] is Timestamp
            ? (privateMap['scheduledDeletionAt'] as Timestamp).toDate()
            : null,
        acceptedTermsAt: privateMap['acceptedTermsAt'] is Timestamp
            ? (privateMap['acceptedTermsAt'] as Timestamp).toDate()
            : null,
        acceptedPrivacyAt: privateMap['acceptedPrivacyAt'] is Timestamp
            ? (privateMap['acceptedPrivacyAt'] as Timestamp).toDate()
            : null,
        acceptedProviderAgreementAt:
            privateMap['acceptedProviderAgreementAt'] is Timestamp
            ? (privateMap['acceptedProviderAgreementAt'] as Timestamp).toDate()
            : null,
      );
    }

    final authSnapshot = AuthIdentitySnapshot(
      uid: user.uid,
      email: (user.email ?? '').trim(),
      phoneNumber: (user.phoneNumber ?? '').trim(),
      emailVerified: user.emailVerified,
      providerIds: normalizeProviderIds(
        user.providerData.map((provider) => provider.providerId),
      ),
    );

    final resolution = resolveAuthOnboardingState(
      auth: authSnapshot,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
    );
    if (resolution.state == AuthOnboardingState.authenticated &&
        (hasPendingSignupConsent || resolution.ignoredStaleOnboardingState)) {
      clearObsoleteSignupState();
    }
    if (kDebugMode) {
      debugPrint(
        'AuthRouteResolver uid=${authSnapshot.uid} firebaseAuthenticated=true '
        'userDocState=${publicSnapshot.exists ? 'exists' : 'missing'} '
        'userPrivateState=${privateSnapshot.exists ? 'exists' : 'missing'} '
        'persistedAccountComplete=${resolution.persistedAccountComplete} '
        'pendingSignupConsent=$hasPendingSignupConsent '
        'ignoredStaleOnboardingState=${resolution.ignoredStaleOnboardingState} '
        'accountState=${resolution.state.name} '
        'reason=${resolution.reason}',
      );
    }
    return resolution;
  }

  void clearObsoleteSignupState() {
    _legalAcceptanceSessionService.clearSignupConsent(
      uid: _auth.currentUser?.uid,
    );
  }
}
