import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/firebase_resilience_service.dart';
import '../mappers/booking_document_mapper.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/canonical_booking_cancellation_models.dart';
import '../../domain/models/canonical_booking_dispute_models.dart';
import '../../domain/models/canonical_booking_payout_models.dart';
import '../../domain/models/canonical_booking_private.dart';
import '../../domain/models/canonical_booking_refund_models.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/provider_earning_record.dart';
import '../../domain/models/service_slot_model.dart';

enum CanonicalPrivateDataLoadFailureKind {
  documentNotFound,
  permissionDenied,
  malformedDocument,
  network,
  unknown,
}

class BookingDisputeDraftEvidence {
  const BookingDisputeDraftEvidence({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

class UploadedBookingDisputeEvidence {
  const UploadedBookingDisputeEvidence({
    required this.evidenceId,
    required this.storagePath,
  });

  final String evidenceId;
  final String storagePath;

  Map<String, dynamic> toCallableMap() => <String, dynamic>{
    'evidenceId': evidenceId,
    'storagePath': storagePath,
  };
}

class CanonicalPrivateDataLoadException implements Exception {
  const CanonicalPrivateDataLoadException({
    required this.kind,
    required this.collection,
    required this.bookingId,
    this.cause,
  });

  final CanonicalPrivateDataLoadFailureKind kind;
  final String collection;
  final String bookingId;
  final Object? cause;
}

@visibleForTesting
Future<T> runCanonicalPaymentCallableWithAuthRecovery<T>({
  required String operationName,
  required Future<T> Function() invoke,
  User? Function()? currentUserProvider,
  Future<void> Function(User user)? refreshToken,
  void Function(String message)? debugLogger,
}) async {
  final logger =
      debugLogger ??
      (String message) {
        if (kDebugMode) {
          debugPrint(message);
        }
      };
  final loadCurrentUser =
      currentUserProvider ??
      () => Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser : null;
  final refreshCurrentToken =
      refreshToken ?? (User user) => user.getIdToken(true).then((_) {});

  try {
    return await invoke();
  } on FirebaseFunctionsException catch (error) {
    final currentUser = loadCurrentUser();
    final hasCurrentUser = currentUser != null;
    logger(
      '[CanonicalPaymentCallable] failure operation=$operationName code=${error.code} hasCurrentUser=$hasCurrentUser uid=${currentUser?.uid ?? ''}',
    );
    if (error.code != 'unauthenticated' || currentUser == null) {
      rethrow;
    }

    logger(
      '[CanonicalPaymentCallable] retry_after_unauthenticated operation=$operationName uid=${currentUser.uid}',
    );
    try {
      await refreshCurrentToken(currentUser);
      logger(
        '[CanonicalPaymentCallable] token_refresh_succeeded operation=$operationName uid=${currentUser.uid}',
      );
    } catch (refreshError) {
      logger(
        '[CanonicalPaymentCallable] token_refresh_failed operation=$operationName uid=${currentUser.uid} errorType=${refreshError.runtimeType}',
      );
    }

    try {
      return await invoke();
    } on FirebaseFunctionsException catch (retryError) {
      logger(
        '[CanonicalPaymentCallable] retry_failed operation=$operationName code=${retryError.code} uid=${currentUser.uid}',
      );
      rethrow;
    }
  }
}

@visibleForTesting
CanonicalBookingRequestException mapCanonicalBookingRequestFunctionsException(
  FirebaseFunctionsException error,
) {
  final details = error.details;
  Map<String, dynamic> detailMap = const <String, dynamic>{};
  if (details is Map) {
    detailMap = Map<String, dynamic>.from(details.cast<dynamic, dynamic>());
  }
  final detailCode = (detailMap['code'] as String? ?? '').trim().toUpperCase();
  final issuesRaw = detailMap['issues'];
  final issues = issuesRaw is List
      ? issuesRaw.map((entry) => '$entry').toList(growable: false)
      : const <String>[];

  CanonicalBookingRequestFailureCode code;
  switch (detailCode) {
    case 'CANONICAL_BOOKING_DISABLED':
      code = CanonicalBookingRequestFailureCode.canonicalBookingDisabled;
      break;
    case 'SERVICE_NOT_FOUND':
      code = CanonicalBookingRequestFailureCode.serviceNotFound;
      break;
    case 'SERVICE_INACTIVE':
      code = CanonicalBookingRequestFailureCode.serviceInactive;
      break;
    case 'SERVICE_PAUSED':
      code = CanonicalBookingRequestFailureCode.servicePaused;
      break;
    case 'PROVIDER_PAUSED':
    case 'PROVIDER_UNAVAILABLE':
      code = CanonicalBookingRequestFailureCode.providerUnavailable;
      break;
    case 'INVALID_BOOKING_TYPE':
      code = CanonicalBookingRequestFailureCode.invalidBookingType;
      break;
    case 'INVALID_SCHEDULE':
    case 'INVALID_SLOT_SELECTION':
    case 'INVALID_RANGE':
    case 'INVALID_NIGHTS':
    case 'INVALID_SLOT_RANGE':
    case 'INVALID_SLOT_COUNT':
    case 'INVALID_TOTAL_DURATION':
    case 'DUPLICATE_SLOT_SELECTION':
    case 'NON_CONTIGUOUS_DAILY_SLOTS':
    case 'NON_CONSECUTIVE_SERVICE_DATES':
    case 'TOO_MANY_SERVICE_DAYS':
    case 'OVERLAPPING_BOOKING_SEGMENTS':
    case 'MIXED_SERVICE_SLOT_SELECTION':
    case 'MIXED_SCHEDULING_MODE':
    case 'NON_CONTIGUOUS':
    case 'OVERLAPPING':
      code = CanonicalBookingRequestFailureCode.invalidSchedule;
      break;
    case 'RUNWAY_NOT_SATISFIED':
      code = CanonicalBookingRequestFailureCode.runwayNotSatisfied;
      break;
    case 'INVALID_TIMEZONE':
    case 'INVALID_WORKING_HOURS':
      code = CanonicalBookingRequestFailureCode.invalidTimezone;
      break;
    case 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD':
      code = CanonicalBookingRequestFailureCode.idempotencyConflict;
      break;
    default:
      switch (error.code) {
        case 'unauthenticated':
          code = CanonicalBookingRequestFailureCode.unauthenticated;
          break;
        case 'permission-denied':
          code = CanonicalBookingRequestFailureCode.permissionDenied;
          break;
        case 'not-found':
          code = CanonicalBookingRequestFailureCode.serviceNotFound;
          break;
        default:
          code = CanonicalBookingRequestFailureCode.unknown;
          break;
      }
      break;
  }

  return CanonicalBookingRequestException(
    code: code,
    message: canonicalBookingRequestMessage(code, error.message),
    issues: issues,
  );
}

@visibleForTesting
String canonicalBookingRequestMessage(
  CanonicalBookingRequestFailureCode code,
  String? fallback,
) {
  switch (code) {
    case CanonicalBookingRequestFailureCode.canonicalBookingDisabled:
      return 'This request flow is not available right now.';
    case CanonicalBookingRequestFailureCode.unauthenticated:
      return 'Please sign in again before sending your request.';
    case CanonicalBookingRequestFailureCode.serviceNotFound:
      return 'This service is no longer available.';
    case CanonicalBookingRequestFailureCode.serviceInactive:
      return 'This service is not active right now.';
    case CanonicalBookingRequestFailureCode.servicePaused:
      return 'This service is temporarily paused.';
    case CanonicalBookingRequestFailureCode.providerUnavailable:
      return 'This provider is temporarily unavailable.';
    case CanonicalBookingRequestFailureCode.invalidBookingType:
      return 'This booking type is not available right now.';
    case CanonicalBookingRequestFailureCode.invalidSchedule:
      return 'Please review your selected schedule and try again.';
    case CanonicalBookingRequestFailureCode.runwayNotSatisfied:
      return 'This schedule is too soon for the required booking window.';
    case CanonicalBookingRequestFailureCode.invalidTimezone:
      return 'We could not verify the provider schedule right now.';
    case CanonicalBookingRequestFailureCode.idempotencyConflict:
      return 'Your request changed while we were submitting it. Please review and try again.';
    case CanonicalBookingRequestFailureCode.permissionDenied:
      return 'You do not have permission to send this request.';
    case CanonicalBookingRequestFailureCode.unknown:
      final normalizedFallback = fallback?.trim() ?? '';
      if (normalizedFallback.isEmpty ||
          normalizedFallback.toLowerCase() == 'internal') {
        return 'We could not send your request right now.';
      }
      return normalizedFallback;
  }
}

class BookingRepository {
  final FirebaseFirestore? _providedFirestore;
  final FirebaseFunctions? _providedFunctions;
  final FirebaseStorage? _providedStorage;

  BookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _providedFirestore = firestore,
       _providedFunctions = functions,
       _providedStorage = storage;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      _providedFunctions ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  Stream<List<BookingReadModel>> watchReceivingBookingReadModels(
    String currentUserId, {
    int limit = 80,
  }) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    return FirebaseResilienceService.retryTransientStream<
      List<BookingReadModel>
    >(
      operationName: 'BookingRepository.watchReceivingBookingReadModels',
      streamFactory: () => _firestore
          .collection('bookings')
          .where('customerId', isEqualTo: userId)
          .orderBy('scheduledStartAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map(mapBookingDocumentSnapshot)
                .whereType<CanonicalBookingReadModel>()
                .toList(growable: false);
          }),
    );
  }

  Stream<List<BookingReadModel>> watchDeliveringBookingReadModels(
    String currentUserId, {
    int limit = 80,
  }) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    return FirebaseResilienceService.retryTransientStream<
      List<BookingReadModel>
    >(
      operationName: 'BookingRepository.watchDeliveringBookingReadModels',
      streamFactory: () => _firestore
          .collection('bookings')
          .where('serviceOwnerId', isEqualTo: userId)
          .orderBy('scheduledStartAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(mapBookingDocumentSnapshot)
                .toList(growable: false),
          ),
    );
  }

  Stream<List<CanonicalProviderBookingRequestView>>
  watchProviderCanonicalRequests(String currentUserId, {int limit = 80}) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    return FirebaseResilienceService.retryTransientStream<
      List<CanonicalProviderBookingRequestView>
    >(
      operationName: 'BookingRepository.watchProviderCanonicalRequests',
      streamFactory: () => _firestore
          .collection('bookings')
          .where('serviceOwnerId', isEqualTo: userId)
          .where(
            'stateQueryValue',
            whereIn: const [
              'REQUESTED',
              'PENDING_PROVIDER',
              'ACCEPTED_AWAITING_PAYMENT',
            ],
          )
          .limit(limit)
          .snapshots()
          .map((snapshot) {
            final requests = snapshot.docs
                .map(mapBookingDocumentSnapshot)
                .whereType<CanonicalBookingReadModel>()
                .map(
                  (readModel) =>
                      CanonicalProviderBookingRequestView.fromBooking(
                        readModel.bookingId,
                        readModel.booking,
                      ),
                )
                .toList(growable: false);
            requests.sort((left, right) {
              final leftTime =
                  left.timerStartsAt ??
                  left.acceptDeadlineAt ??
                  left.scheduledStartAt ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final rightTime =
                  right.timerStartsAt ??
                  right.acceptDeadlineAt ??
                  right.scheduledStartAt ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return rightTime.compareTo(leftTime);
            });
            return requests;
          }),
    );
  }

  Stream<BookingReadModel?> watchBookingReadModel(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);

    return _firestore
        .collection('bookings')
        .doc(id)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? mapBookingDocumentSnapshot(snapshot) : null,
        );
  }

  Future<BookingReadModel?> fetchBookingReadModel(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final snapshot = await _firestore.collection('bookings').doc(id).get();
    if (!snapshot.exists) return null;
    return mapBookingDocumentSnapshot(snapshot);
  }

  Stream<List<ServiceSlotModel>> watchServiceSlotsForDate({
    required String serviceId,
    required DateTime date,
  }) {
    final id = serviceId.trim();
    if (id.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('services')
        .doc(id)
        .collection('slots')
        .where('dateKey', isEqualTo: _dateKey(date))
        .orderBy('startAt')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ServiceSlotModel.fromDocument).toList(),
        );
  }

  Future<CanonicalBookingRequestResult> createBookingRequestV3({
    required CanonicalBookingRequestInput input,
  }) async {
    const callableName = 'createBookingRequestV3';
    final safeServiceId = input.serviceId.trim();
    final safeProviderId = input.slotRequest?.selection.slots.isNotEmpty == true
        ? input.slotRequest!.selection.slots.first.providerId
        : '';
    if (kDebugMode) {
      debugPrint(
        '[BookingCreateV3] start callable=$callableName serviceId=$safeServiceId providerId=$safeProviderId bookingType=${input.bookingType.name}',
      );
    }
    final callable = _functions.httpsCallable('createBookingRequestV3');
    try {
      final result = await callable.call<Map<String, dynamic>>(
        input.toCallableMap(),
      );
      final bookingResult = CanonicalBookingRequestResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] success callable=$callableName serviceId=$safeServiceId providerId=$safeProviderId bookingId=${bookingResult.bookingId} state=${bookingResult.state.name}',
        );
      }
      return bookingResult;
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] failed callable=$callableName serviceId=$safeServiceId providerId=$safeProviderId functionsCode=${error.code} message=${(error.message ?? '').trim()} detailsType=${error.details.runtimeType}',
        );
      }
      throw _mapCanonicalRequestError(error);
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] parse_error callable=$callableName serviceId=$safeServiceId providerId=$safeProviderId error=${error.message}',
        );
      }
      throw CanonicalBookingRequestException(
        code: CanonicalBookingRequestFailureCode.unknown,
        message:
            'We could not understand the booking response. Please try again.',
        issues: [error.message],
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] unexpected_error callable=$callableName serviceId=$safeServiceId providerId=$safeProviderId error=$error',
        );
      }
      rethrow;
    }
  }

  Future<CanonicalBookingCommandResult> markBookingViewedByProviderV3({
    required String bookingId,
  }) async {
    return _invokeCanonicalCommand(
      callableName: 'markBookingViewedByProviderV3',
      bookingId: bookingId,
    );
  }

  Future<CanonicalBookingCommandResult> acceptBookingRequestV3({
    required String bookingId,
  }) async {
    return _invokeCanonicalCommand(
      callableName: 'acceptBookingRequestV3',
      bookingId: bookingId,
    );
  }

  Future<CanonicalBookingCommandResult> declineBookingRequestV3({
    required String bookingId,
  }) async {
    return _invokeCanonicalCommand(
      callableName: 'declineBookingRequestV3',
      bookingId: bookingId,
    );
  }

  Future<CanonicalBookingCommandResult> cancelBookingRequestByParentV3({
    required String bookingId,
  }) async {
    return _invokeCanonicalCommand(
      callableName: 'cancelBookingRequestByParentV3',
      bookingId: bookingId,
    );
  }

  Future<CanonicalBookingCancellationPreview> previewBookingCancellationV3({
    required String bookingId,
    required String actorType,
  }) async {
    final callable = _functions.httpsCallable('previewBookingCancellationV3');
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId.trim(),
      'actorType': actorType.trim(),
    });
    return CanonicalBookingCancellationPreview.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<CanonicalBookingCancellationResult>
  cancelConfirmedBookingByCustomerV3({
    required String bookingId,
    String? reasonCode,
    String? reasonText,
  }) async {
    return _cancelConfirmedBookingV3(
      callableName: 'cancelConfirmedBookingByCustomerV3',
      bookingId: bookingId,
      reasonCode: reasonCode,
      reasonText: reasonText,
    );
  }

  Future<CanonicalBookingCancellationResult>
  cancelConfirmedBookingByProviderV3({
    required String bookingId,
    String? reasonCode,
    String? reasonText,
  }) async {
    return _cancelConfirmedBookingV3(
      callableName: 'cancelConfirmedBookingByProviderV3',
      bookingId: bookingId,
      reasonCode: reasonCode,
      reasonText: reasonText,
    );
  }

  Future<CanonicalPaymentOrderResult> createPaymentOrderV3({
    required String bookingId,
    String? paymentAttemptId,
    String? offerCampaignId,
  }) async {
    const callableName = 'createRazorpayPaymentOrderV3';
    final callable = _functions.httpsCallable(callableName);
    try {
      final result =
          await runCanonicalPaymentCallableWithAuthRecovery<
            HttpsCallableResult<Map<String, dynamic>>
          >(
            operationName: callableName,
            invoke: () => callable.call<Map<String, dynamic>>({
              'bookingId': bookingId.trim(),
              'paymentAttemptId': paymentAttemptId?.trim(),
              'offerCampaignId': offerCampaignId?.trim(),
            }),
          );
      return CanonicalPaymentOrderResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapCanonicalPaymentError(error);
    }
  }

  Future<CanonicalQrPaymentResult> createQrPaymentV3({
    required String bookingId,
    String? offerCampaignId,
  }) async {
    const callableName = 'createBookingQrPaymentV3';
    final callable = _functions.httpsCallable(callableName);
    try {
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] callable_start callable=$callableName bookingId=${bookingId.trim()} hasOffer=${offerCampaignId?.trim().isNotEmpty == true}',
        );
      }
      final result =
          await runCanonicalPaymentCallableWithAuthRecovery<
            HttpsCallableResult<Map<String, dynamic>>
          >(
            operationName: callableName,
            invoke: () => callable.call<Map<String, dynamic>>({
              'bookingId': bookingId.trim(),
              'offerCampaignId': offerCampaignId?.trim(),
            }),
            debugLogger: (message) {
              if (kDebugMode) {
                debugPrint(message);
              }
            },
          );
      if (kDebugMode) {
        final data = Map<String, dynamic>.from(result.data);
        debugPrint(
          '[BookingQrPayment] callable_success callable=$callableName bookingId=${bookingId.trim()} qrIdPresent=${(data['qrCodeId']?.toString().trim().isNotEmpty ?? false)} status=${data['state'] ?? ''}',
        );
      }
      return CanonicalQrPaymentResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] callable_failed callable=$callableName bookingId=${bookingId.trim()} functionsCode=${error.code} safeMessage=${error.message ?? ''} detailsType=${error.details.runtimeType}',
        );
      }
      throw _mapCanonicalPaymentError(error);
    }
  }

  Future<CanonicalPaymentPricingPreviewResult> previewPaymentPricingV3({
    required String bookingId,
    String? offerCampaignId,
  }) async {
    const callableName = 'previewBookingPaymentPricingV3';
    final safeBookingId = bookingId.trim();
    final safeOfferCampaignId = offerCampaignId?.trim();
    if (kDebugMode) {
      debugPrint(
        '[CanonicalPaymentPreview] request callable=$callableName bookingId=$safeBookingId hasCoupon=${safeOfferCampaignId?.isNotEmpty == true}',
      );
    }
    final callable = _functions.httpsCallable(callableName);
    try {
      final result =
          await runCanonicalPaymentCallableWithAuthRecovery<
            HttpsCallableResult<Map<String, dynamic>>
          >(
            operationName: callableName,
            invoke: () => callable.call<Map<String, dynamic>>({
              'bookingId': safeBookingId,
              'offerCampaignId': safeOfferCampaignId,
            }),
          );
      final preview = CanonicalPaymentPricingPreviewResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
      if (kDebugMode) {
        debugPrint(
          '[CanonicalPaymentPreview] success callable=$callableName bookingId=${preview.bookingId} payablePaise=${preview.pricingSummary.customerPaidPaise} discountPaise=${preview.pricingSummary.couponDiscountPaise}',
        );
      }
      return preview;
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[CanonicalPaymentPreview] firebase_error callable=$callableName bookingId=$safeBookingId code=${error.code} message=${error.message ?? ''} details=${error.details}',
        );
      }
      throw _mapCanonicalPaymentError(error);
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[CanonicalPaymentPreview] parse_error callable=$callableName bookingId=$safeBookingId error=${error.message}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[CanonicalPaymentPreview] unknown_error callable=$callableName bookingId=$safeBookingId error=$error',
        );
      }
      rethrow;
    }
  }

  Future<CanonicalPaymentVerificationResult> verifyPaymentV3({
    required String bookingId,
    required String paymentAttemptId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    const callableName = 'verifyBookingPaymentV3';
    final callable = _functions.httpsCallable(callableName);
    try {
      final result =
          await runCanonicalPaymentCallableWithAuthRecovery<
            HttpsCallableResult<Map<String, dynamic>>
          >(
            operationName: callableName,
            invoke: () => callable.call<Map<String, dynamic>>({
              'bookingId': bookingId.trim(),
              'paymentAttemptId': paymentAttemptId.trim(),
              'razorpay_order_id': razorpayOrderId.trim(),
              'razorpay_payment_id': razorpayPaymentId.trim(),
              'razorpay_signature': razorpaySignature.trim(),
            }),
          );
      return CanonicalPaymentVerificationResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapCanonicalPaymentError(error);
    }
  }

  Stream<CanonicalPaymentAttemptReadModel?> watchPaymentAttempt({
    required String bookingId,
    required String paymentAttemptId,
  }) {
    final safeBookingId = bookingId.trim();
    final safeAttemptId = paymentAttemptId.trim();
    if (safeBookingId.isEmpty || safeAttemptId.isEmpty) {
      return Stream.value(null);
    }

    return _firestore
        .collection('bookings')
        .doc(safeBookingId)
        .collection('paymentAttempts')
        .doc(safeAttemptId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return CanonicalPaymentAttemptReadModel.fromMap(
            Map<String, dynamic>.from(snapshot.data() ?? const {}),
          );
        });
  }

  Future<CanonicalPaymentAttemptReadModel?> fetchCanonicalPaymentAttempt({
    required String bookingId,
    required String paymentAttemptId,
  }) async {
    final safeBookingId = bookingId.trim();
    final safeAttemptId = paymentAttemptId.trim();
    if (safeBookingId.isEmpty || safeAttemptId.isEmpty) return null;

    final snapshot = await _firestore
        .collection('bookings')
        .doc(safeBookingId)
        .collection('paymentAttempts')
        .doc(safeAttemptId)
        .get();
    if (!snapshot.exists) return null;
    return CanonicalPaymentAttemptReadModel.fromMap(
      Map<String, dynamic>.from(snapshot.data() ?? const {}),
    );
  }

  Stream<CanonicalBookingPrivateData?> watchCanonicalBookingPrivate(
    String bookingId,
  ) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);

    final Stream<CanonicalBookingPrivateData?> stream = _firestore
        .collection('bookingPrivate')
        .doc(id)
        .snapshots()
        .map<CanonicalBookingPrivateData?>((snapshot) {
          if (!snapshot.exists) {
            throw CanonicalPrivateDataLoadException(
              kind: CanonicalPrivateDataLoadFailureKind.documentNotFound,
              collection: 'bookingPrivate',
              bookingId: id,
            );
          }
          try {
            final raw = Map<String, dynamic>.from(snapshot.data() ?? const {});
            final data = CanonicalBookingPrivateData.fromMap({
              ...raw,
              if ((raw['bookingId'] as String? ?? '').trim().isEmpty)
                'bookingId': id,
            });
            if (!data.hasOtp &&
                data.otpState.trim().isEmpty &&
                data.contactUnlockedAt == null) {
              throw const FormatException(
                'bookingPrivate missing paid-only data.',
              );
            }
            return data;
          } catch (error) {
            throw CanonicalPrivateDataLoadException(
              kind: CanonicalPrivateDataLoadFailureKind.malformedDocument,
              collection: 'bookingPrivate',
              bookingId: id,
              cause: error,
            );
          }
        });
    return _normalizeCanonicalPrivateStream(
      stream,
      collection: 'bookingPrivate',
      bookingId: id,
    );
  }

  Future<CanonicalBookingPrivateData?> fetchCanonicalBookingPrivate(
    String bookingId,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final snapshot = await _firestore
        .collection('bookingPrivate')
        .doc(id)
        .get();
    if (!snapshot.exists) return null;
    return CanonicalBookingPrivateData.fromMap(
      Map<String, dynamic>.from(snapshot.data() ?? const {}),
    );
  }

  Stream<CanonicalBookingPrivateParticipantsData?>
  watchCanonicalBookingPrivateParticipants(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);

    final Stream<CanonicalBookingPrivateParticipantsData?> stream = _firestore
        .collection('bookingPrivateParticipants')
        .doc(id)
        .snapshots()
        .map<CanonicalBookingPrivateParticipantsData?>((snapshot) {
          if (!snapshot.exists) {
            throw CanonicalPrivateDataLoadException(
              kind: CanonicalPrivateDataLoadFailureKind.documentNotFound,
              collection: 'bookingPrivateParticipants',
              bookingId: id,
            );
          }
          try {
            final raw = Map<String, dynamic>.from(snapshot.data() ?? const {});
            final data = CanonicalBookingPrivateParticipantsData.fromMap({
              ...raw,
              if ((raw['bookingId'] as String? ?? '').trim().isEmpty)
                'bookingId': id,
            });
            if (!data.hasPhoneNumber &&
                !data.hasAddress &&
                !data.hasProviderPhoneNumber) {
              throw const FormatException(
                'bookingPrivateParticipants missing participant-private data.',
              );
            }
            return data;
          } catch (error) {
            throw CanonicalPrivateDataLoadException(
              kind: CanonicalPrivateDataLoadFailureKind.malformedDocument,
              collection: 'bookingPrivateParticipants',
              bookingId: id,
              cause: error,
            );
          }
        });
    return _normalizeCanonicalPrivateStream(
      stream,
      collection: 'bookingPrivateParticipants',
      bookingId: id,
    );
  }

  Future<CanonicalBookingPrivateParticipantsData?>
  fetchCanonicalBookingPrivateParticipants(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final snapshot = await _firestore
        .collection('bookingPrivateParticipants')
        .doc(id)
        .get();
    if (!snapshot.exists) return null;
    return CanonicalBookingPrivateParticipantsData.fromMap(
      Map<String, dynamic>.from(snapshot.data() ?? const {}),
    );
  }

  Stream<BookingReadModel?> watchCanonicalBookingConfirmation(
    String bookingId,
  ) {
    return watchBookingReadModel(bookingId).map((booking) {
      if (booking is! CanonicalBookingReadModel) return null;
      return booking.booking.state == CanonicalBookingStateV3.confirmed &&
              booking.booking.lifecycle.paidAt != null
          ? booking
          : null;
    });
  }

  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) {
    return watchBookingReadModel(bookingId);
  }

  Future<BookingReadModel?> fetchCanonicalBooking(String bookingId) {
    return fetchBookingReadModel(bookingId);
  }

  Stream<CanonicalBookingCancellationRecord?> watchCanonicalBookingCancellation(
    String bookingId,
  ) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _firestore
        .collection('bookingCancellations')
        .doc(id)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          return CanonicalBookingCancellationRecord.fromMap(
            Map<String, dynamic>.from(snapshot.data() ?? const {}),
          );
        });
  }

  Future<CanonicalBookingCancellationRecord?> fetchCanonicalBookingCancellation(
    String bookingId,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    final snapshot = await _firestore
        .collection('bookingCancellations')
        .doc(id)
        .get();
    if (!snapshot.exists) return null;
    return CanonicalBookingCancellationRecord.fromMap(
      Map<String, dynamic>.from(snapshot.data() ?? const {}),
    );
  }

  Stream<CanonicalBookingRefundRecord?> watchCanonicalBookingRefund(
    String bookingId,
  ) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _firestore.collection('refunds').doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return CanonicalBookingRefundRecord.fromMap(
        Map<String, dynamic>.from(snapshot.data() ?? const {}),
      );
    });
  }

  Future<CanonicalBookingRefundRecord?> fetchCanonicalBookingRefund(
    String bookingId,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;
    final snapshot = await _firestore.collection('refunds').doc(id).get();
    if (!snapshot.exists) return null;
    return CanonicalBookingRefundRecord.fromMap(
      Map<String, dynamic>.from(snapshot.data() ?? const {}),
    );
  }

  Stream<CanonicalBookingDisputeRecord?> watchCanonicalBookingDispute(
    String bookingId,
  ) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _firestore.collection('disputes').doc(id).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      return CanonicalBookingDisputeRecord.fromMap(
        Map<String, dynamic>.from(snapshot.data() ?? const {}),
      );
    });
  }

  Stream<CanonicalBookingPayoutRecord?> watchCanonicalBookingProviderPayout(
    String bookingId,
  ) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _firestore.collection('providerPayouts').doc(id).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      return CanonicalBookingPayoutRecord.fromMap(
        Map<String, dynamic>.from(snapshot.data() ?? const {}),
      );
    });
  }

  CanonicalBookingRequestException _mapCanonicalRequestError(
    FirebaseFunctionsException error,
  ) => mapCanonicalBookingRequestFunctionsException(error);

  Future<CanonicalBookingCancellationResult> _cancelConfirmedBookingV3({
    required String callableName,
    required String bookingId,
    String? reasonCode,
    String? reasonText,
  }) async {
    final callable = _functions.httpsCallable(callableName);
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId.trim(),
      'reasonCode': reasonCode?.trim(),
      'reasonText': reasonText?.trim(),
    });
    return CanonicalBookingCancellationResult.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<CanonicalBookingCommandResult> _invokeCanonicalCommand({
    required String callableName,
    required String bookingId,
  }) async {
    final callable = _functions.httpsCallable(callableName);
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'bookingId': bookingId.trim(),
      });
      return CanonicalBookingCommandResult.fromMap(
        Map<String, dynamic>.from(result.data),
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapCanonicalCommandError(error);
    }
  }

  CanonicalBookingRequestException _mapCanonicalCommandError(
    FirebaseFunctionsException error,
  ) {
    final details = error.details;
    Map<String, dynamic> detailMap = const <String, dynamic>{};
    if (details is Map) {
      detailMap = Map<String, dynamic>.from(details.cast<dynamic, dynamic>());
    }
    final detailCode = (detailMap['code'] as String? ?? '')
        .trim()
        .toUpperCase();
    final code = switch (detailCode) {
      'BOOKING_NOT_FOUND' => CanonicalBookingRequestFailureCode.serviceNotFound,
      'ACTOR_NOT_AUTHORIZED' =>
        CanonicalBookingRequestFailureCode.permissionDenied,
      'INVALID_BOOKING_STATE' =>
        CanonicalBookingRequestFailureCode.invalidSchedule,
      'DEADLINE_PASSED' =>
        CanonicalBookingRequestFailureCode.runwayNotSatisfied,
      'CANONICAL_BOOKING_DISABLED' =>
        CanonicalBookingRequestFailureCode.canonicalBookingDisabled,
      _ =>
        error.code == 'unauthenticated'
            ? CanonicalBookingRequestFailureCode.unauthenticated
            : CanonicalBookingRequestFailureCode.unknown,
    };
    return CanonicalBookingRequestException(
      code: code,
      message: error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'We could not update this booking request right now.',
    );
  }

  CanonicalPaymentException _mapCanonicalPaymentError(
    FirebaseFunctionsException error,
  ) {
    final details = error.details;
    Map<String, dynamic> detailMap = const <String, dynamic>{};
    if (details is Map) {
      detailMap = Map<String, dynamic>.from(details.cast<dynamic, dynamic>());
    }
    final detailCode = (detailMap['code'] as String? ?? '')
        .trim()
        .toUpperCase();

    final code = switch (detailCode) {
      'BOOKING_NOT_FOUND' => CanonicalPaymentFailureCode.bookingNotFound,
      'INVALID_CANONICAL_BOOKING' =>
        CanonicalPaymentFailureCode.invalidCanonicalBooking,
      'ACTOR_NOT_AUTHORIZED' => CanonicalPaymentFailureCode.actorNotAuthorized,
      'PAYMENT_DISABLED' => CanonicalPaymentFailureCode.paymentDisabled,
      'BOOKING_NOT_PAYABLE' => CanonicalPaymentFailureCode.bookingNotPayable,
      'PAYMENT_WINDOW_EXPIRED' =>
        CanonicalPaymentFailureCode.paymentWindowExpired,
      'PAYMENT_ATTEMPT_CONFLICT' =>
        CanonicalPaymentFailureCode.paymentAttemptConflict,
      'SERVICE_UNAVAILABLE' => CanonicalPaymentFailureCode.serviceUnavailable,
      'CAPACITY_UNAVAILABLE' => CanonicalPaymentFailureCode.capacityUnavailable,
      'COUPON_INVALID' => CanonicalPaymentFailureCode.couponInvalid,
      'PRICING_CHANGED' => CanonicalPaymentFailureCode.pricingChanged,
      'PAYMENT_ALREADY_CONFIRMED' =>
        CanonicalPaymentFailureCode.paymentAlreadyConfirmed,
      'PAYMENT_RECONCILIATION_REQUIRED' =>
        CanonicalPaymentFailureCode.paymentReconciliationRequired,
      'PAYMENT_QR_SWITCH_LOCKED' =>
        CanonicalPaymentFailureCode.paymentQrSwitchLocked,
      _ => switch (error.code) {
        'unauthenticated' => CanonicalPaymentFailureCode.unauthenticated,
        _ => CanonicalPaymentFailureCode.unknown,
      },
    };

    return CanonicalPaymentException(
      code: code,
      message: _canonicalPaymentMessage(code, error.message),
      lockUntil: _readCanonicalPaymentDate(detailMap['lockUntil']),
      activeAttemptId:
          (detailMap['activeAttemptId'] as String? ??
                  detailMap['paymentAttemptId'] as String? ??
                  '')
              .trim(),
      paymentRail: (detailMap['paymentRail'] as String? ?? '').trim(),
    );
  }

  @visibleForTesting
  CanonicalPaymentException mapCanonicalPaymentFunctionsExceptionForTest(
    FirebaseFunctionsException error,
  ) => _mapCanonicalPaymentError(error);

  DateTime? _readCanonicalPaymentDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  String _canonicalPaymentMessage(
    CanonicalPaymentFailureCode code,
    String? fallback,
  ) {
    switch (code) {
      case CanonicalPaymentFailureCode.unauthenticated:
        return 'Please sign in again before continuing.';
      case CanonicalPaymentFailureCode.bookingNotFound:
        return 'This booking could not be found.';
      case CanonicalPaymentFailureCode.invalidCanonicalBooking:
        return 'This booking is not ready for canonical payment.';
      case CanonicalPaymentFailureCode.actorNotAuthorized:
        return 'You do not have permission to pay for this booking.';
      case CanonicalPaymentFailureCode.paymentDisabled:
        return 'Canonical payment is not active for this booking yet.';
      case CanonicalPaymentFailureCode.bookingNotPayable:
        return 'This booking is not payable right now.';
      case CanonicalPaymentFailureCode.paymentWindowExpired:
        return 'The payment window has expired.';
      case CanonicalPaymentFailureCode.paymentAttemptConflict:
        return 'This payment attempt no longer matches the current booking state.';
      case CanonicalPaymentFailureCode.serviceUnavailable:
        return 'This service is not available for payment right now.';
      case CanonicalPaymentFailureCode.capacityUnavailable:
        return 'One or more selected slots are no longer available. Please review your booking.';
      case CanonicalPaymentFailureCode.couponInvalid:
        return 'This coupon can no longer be applied.';
      case CanonicalPaymentFailureCode.pricingChanged:
        return 'The booking price changed before payment started.';
      case CanonicalPaymentFailureCode.paymentAlreadyConfirmed:
        return 'This booking payment is already confirmed.';
      case CanonicalPaymentFailureCode.paymentReconciliationRequired:
        return 'Payment was received and is being reconciled securely.';
      case CanonicalPaymentFailureCode.paymentQrSwitchLocked:
        return 'This QR payment is still active for your payment safety.';
      case CanonicalPaymentFailureCode.unknown:
        return fallback?.trim().isNotEmpty == true
            ? fallback!.trim()
            : 'We could not continue this payment right now.';
    }
  }

  Stream<List<ProviderEarningRecord>> watchProviderEarnings(
    String currentUserId, {
    int limit = 120,
  }) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('providerEarnings')
        .where('providerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ProviderEarningRecord.fromDocument)
              .toList(growable: false),
        );
  }

  Future<void> verifyBookingStartOtpV3({
    required String bookingId,
    required String otp,
    required String requestAttemptId,
  }) async {
    const callableName = 'verifyBookingStartOtpV3';
    final id = bookingId.trim();
    final otpValue = otp.trim();
    final attemptId = requestAttemptId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }
    if (otpValue.isEmpty) {
      throw ArgumentError.value(otp, 'otp', 'otp is required');
    }
    if (attemptId.isEmpty) {
      throw ArgumentError.value(
        requestAttemptId,
        'requestAttemptId',
        'requestAttemptId is required',
      );
    }

    debugPrint(
      '[CanonicalOtpVerification] request callable=$callableName bookingId=$id otpLength=${otpValue.length}',
    );
    final callable = _functions.httpsCallable(callableName);
    try {
      await callable.call<Map<String, dynamic>>({
        'bookingId': id,
        'otp': otpValue,
        'requestAttemptId': attemptId,
      });
      debugPrint(
        '[CanonicalOtpVerification] success callable=$callableName bookingId=$id',
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[CanonicalOtpVerification] firebase_error callable=$callableName bookingId=$id code=${error.code} message=${error.message ?? ''} details=${error.details}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[CanonicalOtpVerification] unknown_error callable=$callableName bookingId=$id error=$error',
      );
      rethrow;
    }
  }

  Future<void> completeBookingServiceV3({required String bookingId}) async {
    const callableName = 'completeBookingServiceV3';
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    debugPrint(
      '[CanonicalServiceCompletion] request callable=$callableName bookingId=$id',
    );
    final callable = _functions.httpsCallable(callableName);
    try {
      await callable.call<Map<String, dynamic>>({'bookingId': id});
      debugPrint(
        '[CanonicalServiceCompletion] success callable=$callableName bookingId=$id',
      );
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[CanonicalServiceCompletion] firebase_error callable=$callableName bookingId=$id code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[CanonicalServiceCompletion] unexpected_error callable=$callableName bookingId=$id error=$error',
      );
      rethrow;
    }
  }

  Future<String> submitBookingReviewV3({
    required String bookingId,
    required int rating,
    String comment = '',
    List<String> tags = const [],
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(
        rating,
        'rating',
        'rating must be between 1 and 5',
      );
    }

    final cleanedTags = tags
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final callable = _functions.httpsCallable('submitBookingReviewV3');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'bookingId': id,
        'rating': rating,
        'comment': comment.trim(),
        'tags': cleanedTags,
      });
      return (result.data['reviewId'] as String? ?? '').trim();
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[CanonicalReviewSubmission] firebase_error callable=submitBookingReviewV3 bookingId=$id code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
      );
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint(
        '[CanonicalReviewSubmission] firebase_exception callable=submitBookingReviewV3 bookingId=$id code=${error.code} message=${(error.message ?? '').trim()}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[CanonicalReviewSubmission] unexpected_error callable=submitBookingReviewV3 bookingId=$id error=$error',
      );
      rethrow;
    }
  }

  Future<String> createBookingDisputeV3({
    required String bookingId,
    required String reason,
    required String description,
    List<UploadedBookingDisputeEvidence> evidence = const [],
  }) async {
    final id = bookingId.trim();
    final trimmedReason = reason.trim();
    final trimmedDescription = description.trim();
    if (id.isEmpty || trimmedReason.isEmpty || trimmedDescription.isEmpty) {
      throw ArgumentError('bookingId, reason, and description are required');
    }

    final callable = _functions.httpsCallable('createBookingDisputeV3');
    final cleanedEvidence = evidence
        .where(
          (value) =>
              value.evidenceId.trim().isNotEmpty &&
              value.storagePath.trim().isNotEmpty,
        )
        .map((value) => value.toCallableMap())
        .toList(growable: false);
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'bookingId': id,
        'reason': trimmedReason,
        'description': trimmedDescription,
        'evidence': cleanedEvidence,
      });
      return (result.data['disputeId'] as String? ?? '').trim();
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[CanonicalDisputeSubmission] firebase_error callable=createBookingDisputeV3 bookingId=$id reasonPresent=${trimmedReason.isNotEmpty} descriptionLength=${trimmedDescription.length} code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
      );
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint(
        '[CanonicalDisputeSubmission] firebase_exception callable=createBookingDisputeV3 bookingId=$id reasonPresent=${trimmedReason.isNotEmpty} descriptionLength=${trimmedDescription.length} code=${error.code} message=${(error.message ?? '').trim()}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
        '[CanonicalDisputeSubmission] unexpected_error callable=createBookingDisputeV3 bookingId=$id reasonPresent=${trimmedReason.isNotEmpty} descriptionLength=${trimmedDescription.length} error=$error',
      );
      rethrow;
    }
  }

  Future<List<UploadedBookingDisputeEvidence>> uploadBookingDisputeEvidence({
    required String bookingId,
    required List<BookingDisputeDraftEvidence> evidence,
    void Function({
      required int currentIndex,
      required int totalCount,
      required double progress,
    })?
    onProgress,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthenticated',
        message: 'Please sign in again before uploading evidence.',
      );
    }
    if (evidence.length > 5) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'too-many-files',
        message: 'You can attach up to 5 screenshots or photos.',
      );
    }
    if (evidence.isEmpty) return const <UploadedBookingDisputeEvidence>[];

    final uploaded = <UploadedBookingDisputeEvidence>[];
    final random = Random();
    for (var index = 0; index < evidence.length; index++) {
      final item = evidence[index];
      final sizeBytes = item.bytes.length;
      if (sizeBytes == 0) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'missing-file',
          message: 'One selected image is empty.',
        );
      }
      if (sizeBytes > 5 * 1024 * 1024) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'file-too-large',
          message: 'Each evidence image must be 5 MB or smaller.',
        );
      }
      final evidenceId =
          'ev_${DateTime.now().microsecondsSinceEpoch}_${index + 1}_${random.nextInt(1 << 20)}';
      final extension = _storageExtensionForContentType(
        item.contentType,
        fallbackFileName: item.fileName,
      );
      final storagePath =
          'disputes/$bookingId/evidence/$uid/$evidenceId.$extension';
      final ref = _storage.ref().child(storagePath);
      final task = ref.putData(
        item.bytes,
        SettableMetadata(
          contentType: item.contentType,
          customMetadata: <String, String>{
            'bookingId': bookingId,
            'uploadedByUid': uid,
            'uploadedByRole': 'parent',
            'evidenceId': evidenceId,
            'originalFileName': item.fileName.trim(),
          },
        ),
      );
      await for (final snapshot in task.snapshotEvents) {
        final totalBytes = snapshot.totalBytes;
        final progress = totalBytes <= 0
            ? 0
            : snapshot.bytesTransferred / totalBytes;
        onProgress?.call(
          currentIndex: index,
          totalCount: evidence.length,
          progress: progress.clamp(0, 1).toDouble(),
        );
      }
      await task;
      uploaded.add(
        UploadedBookingDisputeEvidence(
          evidenceId: evidenceId,
          storagePath: storagePath,
        ),
      );
    }
    return uploaded;
  }

  Future<void> cleanupUploadedBookingDisputeEvidence(
    List<UploadedBookingDisputeEvidence> evidence,
  ) async {
    for (final item in evidence) {
      try {
        await _storage.ref().child(item.storagePath).delete();
      } on FirebaseException {
        // Best-effort cleanup only.
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  String _storageExtensionForContentType(
    String contentType, {
    required String fallbackFileName,
  }) {
    switch (contentType.trim().toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      default:
        final fileName = fallbackFileName.trim().toLowerCase();
        final dotIndex = fileName.lastIndexOf('.');
        if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
          return fileName.substring(dotIndex + 1);
        }
        return 'jpg';
    }
  }

  String _dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Stream<T?> _normalizeCanonicalPrivateStream<T>(
    Stream<T?> source, {
    required String collection,
    required String bookingId,
  }) {
    return source.transform(
      StreamTransformer<T?, T?>.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          sink.addError(
            _normalizeCanonicalPrivateLoadError(
              error,
              collection: collection,
              bookingId: bookingId,
            ),
            stackTrace,
          );
        },
      ),
    );
  }

  CanonicalPrivateDataLoadException _normalizeCanonicalPrivateLoadError(
    Object error, {
    required String collection,
    required String bookingId,
  }) {
    if (error is CanonicalPrivateDataLoadException) {
      return error;
    }
    if (error is FirebaseException) {
      final code = error.code.trim().toLowerCase();
      if (code == 'permission-denied') {
        return CanonicalPrivateDataLoadException(
          kind: CanonicalPrivateDataLoadFailureKind.permissionDenied,
          collection: collection,
          bookingId: bookingId,
          cause: error,
        );
      }
      if (code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-request-failed') {
        return CanonicalPrivateDataLoadException(
          kind: CanonicalPrivateDataLoadFailureKind.network,
          collection: collection,
          bookingId: bookingId,
          cause: error,
        );
      }
    }
    if (error is FormatException) {
      return CanonicalPrivateDataLoadException(
        kind: CanonicalPrivateDataLoadFailureKind.malformedDocument,
        collection: collection,
        bookingId: bookingId,
        cause: error,
      );
    }
    return CanonicalPrivateDataLoadException(
      kind: CanonicalPrivateDataLoadFailureKind.unknown,
      collection: collection,
      bookingId: bookingId,
      cause: error,
    );
  }
}
