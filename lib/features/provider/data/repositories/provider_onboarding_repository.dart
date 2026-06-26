import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../domain/models/provider_onboarding_models.dart';

class ProviderOnboardingRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  ProviderOnboardingRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  String get _currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _verificationDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('providerVerification')
        .doc('main');
  }

  DocumentReference<Map<String, dynamic>> _bankDetailsDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('providerBankDetails')
        .doc('main');
  }

  CollectionReference<Map<String, dynamic>> get _services =>
      _firestore.collection('services');

  Future<ProviderVerificationRecord> fetchCurrentVerification() async {
    final uid = _currentUid;
    final snapshot = await _verificationDoc(uid).get();
    if (!snapshot.exists) return ProviderVerificationRecord.empty(uid);
    return ProviderVerificationRecord.fromMap(uid, snapshot.data() ?? {});
  }

  Future<ProviderBankDetailsRecord> fetchCurrentBankDetails() async {
    final uid = _currentUid;
    final snapshot = await _bankDetailsDoc(uid).get();
    if (!snapshot.exists) return ProviderBankDetailsRecord.empty(uid);
    return ProviderBankDetailsRecord.fromMap(uid, snapshot.data() ?? {});
  }

  Future<ProviderOnboardingSnapshot> fetchCurrentOnboarding() async {
    final uid = _currentUid;
    final results = await Future.wait([
      _verificationDoc(uid).get(),
      _bankDetailsDoc(uid).get(),
      _services
          .where('ownerUserId', isEqualTo: uid)
          .where('isDeleted', isEqualTo: false)
          .limit(1)
          .get(),
    ]);

    final verificationSnapshot =
        results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final bankSnapshot = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final servicesSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;

    final verification = verificationSnapshot.exists
        ? ProviderVerificationRecord.fromMap(
            uid,
            verificationSnapshot.data() ?? {},
          )
        : ProviderVerificationRecord.empty(uid);
    final bankDetails = bankSnapshot.exists
        ? ProviderBankDetailsRecord.fromMap(uid, bankSnapshot.data() ?? {})
        : ProviderBankDetailsRecord.empty(uid);

    return ProviderOnboardingSnapshot(
      verification: verification,
      bankDetails: bankDetails,
      hasListedService: servicesSnapshot.docs.isNotEmpty,
    );
  }

  Future<void> submitVerification({
    required String documentType,
    required File frontImage,
    File? backImage,
  }) async {
    final uid = _currentUid;
    final normalizedDocumentType = _normalizeDocumentType(documentType);
    if (normalizedDocumentType == null) {
      throw Exception('Invalid document type');
    }

    final frontUrl = await _uploadIdentityImage(
      userId: uid,
      image: frontImage,
      suffix: 'front',
    );
    final backUrl = backImage == null
        ? ''
        : await _uploadIdentityImage(
            userId: uid,
            image: backImage,
            suffix: 'back',
          );

    final docRef = _verificationDoc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final payload = <String, dynamic>{
        'userId': uid,
        'status': providerVerificationPending,
        'documentType': normalizedDocumentType,
        'documentFrontUrl': frontUrl,
        'documentBackUrl': backUrl,
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'rejectionReason': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snapshot.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.set(docRef, payload, SetOptions(merge: true));
    });
  }

  Future<void> saveBankDetails({
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String ifscCode,
    String? upiId,
  }) async {
    final uid = _currentUid;
    final docRef = _bankDetailsDoc(uid);
    final sanitizedAccountNumber = accountNumber.replaceAll(' ', '').trim();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final payload = <String, dynamic>{
        'userId': uid,
        'accountHolderName': accountHolderName.trim(),
        'bankName': bankName.trim(),
        'accountNumberMasked': _maskAccountNumber(sanitizedAccountNumber),
        'ifscCode': ifscCode.trim().toUpperCase(),
        'upiId': (upiId ?? '').trim(),
        'status': providerBankDetailsSubmitted,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snapshot.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.set(docRef, payload, SetOptions(merge: true));
    });
    // TODO: Move bank detail encryption/tokenization to a Cloud Function before
    // production payouts so the client never handles or writes full account
    // numbers beyond the immediate submission flow.
  }

  Future<void> markFirstServiceListedIfNeeded({
    required DateTime gracePeriodEndsAt,
  }) async {
    final uid = _currentUid;
    final docRef = _verificationDoc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? const {};
      if (data['firstServiceListedAt'] != null) return;
      transaction.set(docRef, {
        'firstServiceListedAt': FieldValue.serverTimestamp(),
        'gracePeriodEndsAt': Timestamp.fromDate(gracePeriodEndsAt),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> syncServicesForCurrentVerificationStatus() async {
    final onboarding = await fetchCurrentOnboarding();
    final verification = onboarding.verification;
    final shouldPause =
        !verification.isApproved &&
        verification.gracePeriodEndsAt != null &&
        verification.graceExpired;

    final snapshot = await _services
        .where('ownerUserId', isEqualTo: _currentUid)
        .where('isDeleted', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(doc.reference, {
        'providerVerificationStatus': verification.status,
        'providerVerificationGraceEndsAt':
            verification.gracePeriodEndsAt == null
            ? null
            : Timestamp.fromDate(verification.gracePeriodEndsAt!),
        'isPausedByVerification': shouldPause,
        'pauseReason': shouldPause ? 'Provider verification pending' : '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<String> _uploadIdentityImage({
    required String userId,
    required File image,
    required String suffix,
  }) async {
    final bytes = await image.readAsBytes();
    final compressedBytes = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 82,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
    );
    final uploadBytes = Uint8List.fromList(compressedBytes);
    final ref = _storage.ref().child(
      'providerVerification/$userId/identity/${DateTime.now().millisecondsSinceEpoch}_$suffix.jpg',
    );
    await ref.putData(uploadBytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    final visiblePart = accountNumber.substring(accountNumber.length - 4);
    return 'XXXX$visiblePart';
  }

  String? _normalizeDocumentType(String documentType) {
    final normalized = documentType.trim();
    if (normalized == 'aadhaar' ||
        normalized == 'drivingLicense' ||
        normalized == 'voterId') {
      return normalized;
    }
    return null;
  }
}
