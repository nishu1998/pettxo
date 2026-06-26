import 'package:cloud_firestore/cloud_firestore.dart';

const String providerVerificationNotSubmitted = 'notSubmitted';
const String providerVerificationPending = 'pending';
const String providerVerificationApproved = 'approved';
const String providerVerificationRejected = 'rejected';

const String providerBankDetailsNotSubmitted = 'notSubmitted';
const String providerBankDetailsSubmitted = 'submitted';
const String providerBankDetailsNeedsUpdate = 'needsUpdate';

class ProviderVerificationRecord {
  final String userId;
  final String status;
  final String documentType;
  final String documentFrontUrl;
  final String documentBackUrl;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String rejectionReason;
  final DateTime? firstServiceListedAt;
  final DateTime? gracePeriodEndsAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProviderVerificationRecord({
    required this.userId,
    required this.status,
    required this.documentType,
    required this.documentFrontUrl,
    required this.documentBackUrl,
    required this.submittedAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.rejectionReason,
    required this.firstServiceListedAt,
    required this.gracePeriodEndsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProviderVerificationRecord.empty(String userId) {
    return ProviderVerificationRecord(
      userId: userId,
      status: providerVerificationNotSubmitted,
      documentType: '',
      documentFrontUrl: '',
      documentBackUrl: '',
      submittedAt: null,
      reviewedAt: null,
      reviewedBy: '',
      rejectionReason: '',
      firstServiceListedAt: null,
      gracePeriodEndsAt: null,
      createdAt: null,
      updatedAt: null,
    );
  }

  factory ProviderVerificationRecord.fromMap(
    String userId,
    Map<String, dynamic> data,
  ) {
    return ProviderVerificationRecord(
      userId: (data['userId'] as String? ?? userId).trim(),
      status: (data['status'] as String? ?? providerVerificationNotSubmitted)
          .trim(),
      documentType: (data['documentType'] as String? ?? '').trim(),
      documentFrontUrl: (data['documentFrontUrl'] as String? ?? '').trim(),
      documentBackUrl: (data['documentBackUrl'] as String? ?? '').trim(),
      submittedAt: _readDate(data['submittedAt']),
      reviewedAt: _readDate(data['reviewedAt']),
      reviewedBy: (data['reviewedBy'] as String? ?? '').trim(),
      rejectionReason: (data['rejectionReason'] as String? ?? '').trim(),
      firstServiceListedAt: _readDate(data['firstServiceListedAt']),
      gracePeriodEndsAt: _readDate(data['gracePeriodEndsAt']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  bool get isSubmitted => status != providerVerificationNotSubmitted;
  bool get isPending => status == providerVerificationPending;
  bool get isApproved => status == providerVerificationApproved;
  bool get isRejected => status == providerVerificationRejected;

  bool get graceExpired {
    final graceEnd = gracePeriodEndsAt;
    if (graceEnd == null) return false;
    return DateTime.now().isAfter(graceEnd);
  }

  String get statusMessage {
    if (isApproved) return 'Your provider verification is approved.';
    if (isRejected) {
      return 'Your verification was rejected. Please update your documents and submit again.';
    }
    if (isPending && graceExpired) {
      return 'Your services are paused until provider verification is approved.';
    }
    if (isPending) {
      return 'Your verification is under review. This usually takes 24–72 hours.';
    }
    return 'Submit your identity proof to start receiving bookings as a provider.';
  }
}

class ProviderBankDetailsRecord {
  final String userId;
  final String accountHolderName;
  final String bankName;
  final String accountNumberMasked;
  final String ifscCode;
  final String upiId;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProviderBankDetailsRecord({
    required this.userId,
    required this.accountHolderName,
    required this.bankName,
    required this.accountNumberMasked,
    required this.ifscCode,
    required this.upiId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProviderBankDetailsRecord.empty(String userId) {
    return ProviderBankDetailsRecord(
      userId: userId,
      accountHolderName: '',
      bankName: '',
      accountNumberMasked: '',
      ifscCode: '',
      upiId: '',
      status: providerBankDetailsNotSubmitted,
      createdAt: null,
      updatedAt: null,
    );
  }

  factory ProviderBankDetailsRecord.fromMap(
    String userId,
    Map<String, dynamic> data,
  ) {
    return ProviderBankDetailsRecord(
      userId: (data['userId'] as String? ?? userId).trim(),
      accountHolderName: (data['accountHolderName'] as String? ?? '').trim(),
      bankName: (data['bankName'] as String? ?? '').trim(),
      accountNumberMasked: (data['accountNumberMasked'] as String? ?? '')
          .trim(),
      ifscCode: (data['ifscCode'] as String? ?? '').trim(),
      upiId: (data['upiId'] as String? ?? '').trim(),
      status: (data['status'] as String? ?? providerBankDetailsNotSubmitted)
          .trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  bool get isSubmitted =>
      status == providerBankDetailsSubmitted && accountNumberMasked.isNotEmpty;
}

class ProviderOnboardingSnapshot {
  final ProviderVerificationRecord verification;
  final ProviderBankDetailsRecord bankDetails;
  final bool hasListedService;

  const ProviderOnboardingSnapshot({
    required this.verification,
    required this.bankDetails,
    required this.hasListedService,
  });

  bool get needsVerificationSubmission => !verification.isSubmitted;
  bool get needsBankDetails => !bankDetails.isSubmitted;

  bool get canCreateServiceNow {
    if (verification.isApproved) return bankDetails.isSubmitted;
    if (!bankDetails.isSubmitted) return false;
    if (!verification.isSubmitted) return false;
    return !verification.graceExpired;
  }

  String? get blockingMessage {
    if (!verification.isSubmitted) {
      return 'Complete provider verification before publishing your first service.';
    }
    if (!bankDetails.isSubmitted) {
      return 'Add your bank details before publishing this service.';
    }
    if (verification.isApproved) return null;
    if (verification.graceExpired) {
      return 'Your services are paused until provider verification is approved.';
    }
    return null;
  }
}

DateTime? _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
