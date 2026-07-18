import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/utils/auth_onboarding_resolver.dart';
import 'auth_service.dart';

class AuthOnboardingService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthService _authService;

  AuthOnboardingService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthService? authService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _authService = authService ?? AuthService();

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
    final snapshots = await Future.wait([publicRef.get(), privateRef.get()]);
    final publicSnapshot = snapshots[0];
    final privateSnapshot = snapshots[1];
    final publicData = publicSnapshot.data();
    final privateData = privateSnapshot.data();

    ProfileCompletionSnapshot? profile;
    if (publicData != null) {
      final normalizedUsername =
          (publicData['usernameLowercase'] as String? ??
                  publicData['username'] as String? ??
                  '')
              .trim();
      var usernameReservationMatchesUid = false;

      if (normalizedUsername.isNotEmpty) {
        final usernameSnapshot = await _firestore
            .collection('usernames')
            .doc(normalizedUsername)
            .get();
        final reservedUid = (usernameSnapshot.data()?['uid'] as String? ?? '')
            .trim();
        usernameReservationMatchesUid = reservedUid == user.uid;
      }

      profile = ProfileCompletionSnapshot(
        uid: (publicData['uid'] as String? ?? '').trim(),
        role: (publicData['role'] as String? ?? '').trim(),
        displayName:
            (publicData['displayName'] as String? ??
                    publicData['name'] as String? ??
                    '')
                .trim(),
        username: (publicData['username'] as String? ?? '').trim(),
        usernameLowercase: (publicData['usernameLowercase'] as String? ?? '')
            .trim(),
        state: (publicData['state'] as String? ?? '').trim(),
        city: (publicData['city'] as String? ?? '').trim(),
        usernameReservationMatchesUid: usernameReservationMatchesUid,
        accountStatus:
            (publicData['accountStatus'] as String? ??
                    privateData?['accountStatus'] as String? ??
                    'active')
                .trim(),
        scheduledDeletionAt: privateData?['scheduledDeletionAt'] is Timestamp
            ? (privateData!['scheduledDeletionAt'] as Timestamp).toDate()
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

    return resolveAuthOnboardingState(auth: authSnapshot, profile: profile);
  }
}
