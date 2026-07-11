import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/booking_cancellation_preview.dart';
import '../../domain/models/booking_model.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/pending_payment_booking.dart';
import '../../domain/models/provider_earning_record.dart';
import '../../domain/models/service_slot_model.dart';

enum PendingPaymentRemovalOutcome { deleted, hiddenExpired, alreadyHidden }

class BookingRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  BookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Stream<List<BookingModel>> watchReceivingBookings(
    String currentUserId, {
    int limit = 80,
  }) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('bookings')
        .where('customerId', isEqualTo: userId)
        .orderBy('scheduledStartAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => _mapBookings(
            snapshot,
          ).where((booking) => !booking.isHiddenFromCustomer).toList(),
        );
  }

  Stream<List<BookingModel>> watchDeliveringBookings(
    String currentUserId, {
    int limit = 80,
  }) {
    final userId = currentUserId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    // Current booking functions write serviceOwnerId. BookingModel still accepts
    // providerId as a fallback so a future schema rename is low-friction.
    return _firestore
        .collection('bookings')
        .where('serviceOwnerId', isEqualTo: userId)
        .orderBy('scheduledStartAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_mapBookings);
  }

  Stream<BookingModel?> watchBookingById(String bookingId) {
    final id = bookingId.trim();
    if (id.isEmpty) return Stream.value(null);

    return _firestore
        .collection('bookings')
        .doc(id)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? BookingModel.fromDocument(snapshot) : null,
        );
  }

  Future<BookingModel?> fetchBookingById(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final snapshot = await _firestore.collection('bookings').doc(id).get();
    if (!snapshot.exists) return null;
    return BookingModel.fromDocument(snapshot);
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

  List<BookingModel> receivingUpcoming(List<BookingModel> bookings) {
    return bookings
        .where((booking) => booking.belongsInReceivingUpcoming)
        .toList()
      ..sort(_sortUpcoming);
  }

  List<BookingModel> receivingPast(List<BookingModel> bookings) {
    return bookings.where((booking) => booking.belongsInReceivingPast).toList()
      ..sort(_sortLatestFirst);
  }

  List<BookingModel> deliveringRequests(List<BookingModel> bookings) {
    return bookings.where((booking) => booking.isRequested).toList()
      ..sort(_sortUpcoming);
  }

  List<BookingModel> deliveringConfirmed(List<BookingModel> bookings) {
    return bookings.where((booking) => booking.isConfirmedLike).toList()
      ..sort(_sortUpcoming);
  }

  List<BookingModel> deliveringPast(List<BookingModel> bookings) {
    return bookings.where((booking) => booking.belongsInDeliveringPast).toList()
      ..sort(_sortLatestFirst);
  }

  Future<BookingPaymentOrder> createRazorpayBookingOrder({
    required String serviceId,
    required String slotId,
    required String userId,
    String? claimedOfferId,
  }) async {
    final callable = _functions.httpsCallable('createRazorpayBookingOrder');
    final result = await callable.call<Map<String, dynamic>>({
      'serviceId': serviceId,
      'slotId': slotId,
      'userId': userId,
      'claimedOfferId': claimedOfferId,
    });
    final order = BookingPaymentOrder.fromMap(
      Map<String, dynamic>.from(result.data),
    );
    _debugLog(
      'createRazorpayBookingOrder -> bookingId=${order.bookingId}, '
      'orderId=${_maskValue(order.razorpayOrderId)}, '
      'amountPaise=${order.amountPaise}',
    );
    return order;
  }

  Future<PendingPaymentBooking?> getPendingPaymentBooking({
    String? bookingId,
    String? serviceId,
    String? slotId,
  }) async {
    final callable = _functions.httpsCallable('getPendingPaymentBooking');
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId,
      'serviceId': serviceId,
      'slotId': slotId,
    });

    final data = Map<String, dynamic>.from(result.data);
    final pending = data['pendingBooking'];
    if (pending is! Map) return null;
    return PendingPaymentBooking.fromMap(Map<String, dynamic>.from(pending));
  }

  Future<String> verifyRazorpayPayment({
    required String bookingId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final callable = _functions.httpsCallable('verifyRazorpayPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId,
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
    });

    final data = result.data;
    _debugLog(
      'verifyRazorpayPayment -> bookingId=$bookingId, '
      'orderId=${_maskValue(razorpayOrderId)}, '
      'paymentId=${_maskValue(razorpayPaymentId)}',
    );
    return (data['bookingId'] as String? ?? bookingId).trim();
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('BookingRepository debug -> $message');
  }

  String _maskValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 8) return trimmed;
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }

  Future<void> markRazorpayPaymentFailed({
    required String bookingId,
    String? code,
    String? message,
  }) async {
    final callable = _functions.httpsCallable('markRazorpayPaymentFailed');
    await callable.call<Map<String, dynamic>>({
      'bookingId': bookingId,
      'code': code,
      'message': message,
    });
  }

  Future<void> acceptBookingRequest({required String bookingId}) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('acceptBookingRequest');
    await callable.call<Map<String, dynamic>>({'bookingId': id});
  }

  Future<void> rejectBookingRequest({
    required String bookingId,
    String reason = 'Rejected by provider',
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('rejectBookingRequest');
    await callable.call<Map<String, dynamic>>({
      'bookingId': id,
      'reason': reason,
    });
  }

  Future<void> cancelBooking({
    required String bookingId,
    String reason = 'Cancelled by user',
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('cancelBooking');
    await callable.call<Map<String, dynamic>>({
      'bookingId': id,
      'reason': reason,
    });
  }

  Future<BookingCancellationPreview> previewCancellation({
    required String bookingId,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('previewCancellation');
    final result = await callable.call<Map<String, dynamic>>({'bookingId': id});
    return BookingCancellationPreview.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<BookingCancellationPreview> cancelBookingWithBreakdown({
    required String bookingId,
    String reason = 'Cancelled by user',
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('cancelBooking');
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': id,
      'reason': reason,
    });
    return BookingCancellationPreview.fromMap(
      Map<String, dynamic>.from(result.data),
    );
  }

  Future<void> raiseDispute({
    required String bookingId,
    required String reason,
    required String description,
  }) async {
    final id = bookingId.trim();
    final trimmedReason = reason.trim();
    final trimmedDescription = description.trim();
    if (id.isEmpty || trimmedReason.isEmpty || trimmedDescription.isEmpty) {
      throw ArgumentError('bookingId, reason, and description are required');
    }

    final callable = _functions.httpsCallable('raiseDispute');
    await callable.call<Map<String, dynamic>>({
      'bookingId': id,
      'reason': trimmedReason,
      'description': trimmedDescription,
    });
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

  Future<String> generateBookingOtp({required String bookingId}) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('generateBookingOtp');
    final result = await callable.call<Map<String, dynamic>>({'bookingId': id});
    return (result.data['otp'] as String? ?? '').trim();
  }

  Future<void> verifyBookingOtpAndStart({
    required String bookingId,
    required String otp,
  }) async {
    final id = bookingId.trim();
    final otpValue = otp.trim();
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

    final callable = _functions.httpsCallable('verifyBookingOtpAndStart');
    await callable.call<Map<String, dynamic>>({
      'bookingId': id,
      'otp': otpValue,
    });
  }

  Future<void> completeBooking({required String bookingId}) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }

    final callable = _functions.httpsCallable('completeBooking');
    await callable.call<Map<String, dynamic>>({'bookingId': id});
  }

  Future<PendingPaymentRemovalOutcome> deletePendingPaymentBookingForCustomer({
    required String bookingId,
  }) async {
    final trimmedBookingId = bookingId.trim();
    if (trimmedBookingId.isEmpty) {
      throw ArgumentError.value(
        bookingId,
        'bookingId',
        'bookingId is required',
      );
    }
    final callable = _functions.httpsCallable(
      'deletePendingPaymentBookingForCustomer',
    );
    final result = await callable.call<Map<String, dynamic>>({
      'bookingId': trimmedBookingId,
    });
    final outcome = (result.data['outcome'] as String? ?? '').trim();
    return switch (outcome) {
      'hidden_expired' => PendingPaymentRemovalOutcome.hiddenExpired,
      'already_hidden' => PendingPaymentRemovalOutcome.alreadyHidden,
      _ => PendingPaymentRemovalOutcome.deleted,
    };
  }

  Future<BookingContactSnapshot> fetchPostConfirmationDetails(
    BookingModel booking, {
    bool includeProviderPhone = false,
  }) async {
    final providerId = booking.providerId.trim();
    final serviceId = booking.serviceId.trim();

    final futures = await Future.wait([
      providerId.isEmpty || !includeProviderPhone
          ? Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
          : _firestore.collection('users').doc(providerId).get(),
      serviceId.isEmpty
          ? Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
          : _firestore.collection('services').doc(serviceId).get(),
    ]);

    final providerData = futures[0]?.data() ?? const <String, dynamic>{};
    final serviceData = futures[1]?.data() ?? const <String, dynamic>{};
    final serviceLocation = _map(serviceData['location']);

    final phone = _firstString([
      booking.providerPhone,
      providerData['phone'],
      providerData['mobileNumber'],
      providerData['phoneNumber'],
    ]);

    return BookingContactSnapshot(
      providerPhone: phone,
      displayAddress: _firstString([
        booking.displayAddress,
        serviceLocation['displayAddress'],
      ]),
      latitude: booking.hasUsableCoordinates
          ? booking.latitude
          : _double(serviceLocation['latitude']),
      longitude: booking.hasUsableCoordinates
          ? booking.longitude
          : _double(serviceLocation['longitude']),
    );
  }

  List<BookingModel> _mapBookings(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(BookingModel.fromDocument).toList();
  }

  int _sortUpcoming(BookingModel a, BookingModel b) {
    final aStart = a.scheduledStartAt ?? a.createdAt ?? DateTime(9999);
    final bStart = b.scheduledStartAt ?? b.createdAt ?? DateTime(9999);
    return aStart.compareTo(bStart);
  }

  int _sortLatestFirst(BookingModel a, BookingModel b) {
    final aStart = a.scheduledStartAt ?? a.createdAt ?? DateTime(0);
    final bStart = b.scheduledStartAt ?? b.createdAt ?? DateTime(0);
    return bStart.compareTo(aStart);
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String _firstString(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  double _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _dateKey(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class BookingContactSnapshot {
  final String providerPhone;
  final String displayAddress;
  final double latitude;
  final double longitude;

  const BookingContactSnapshot({
    required this.providerPhone,
    required this.displayAddress,
    required this.latitude,
    required this.longitude,
  });

  bool get hasLocation =>
      displayAddress.trim().isNotEmpty || latitude != 0 || longitude != 0;
}
