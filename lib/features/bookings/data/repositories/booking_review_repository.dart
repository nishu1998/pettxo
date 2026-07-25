import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/booking_review_model.dart';

class BookingReviewRepository {
  final FirebaseFirestore _firestore;

  BookingReviewRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<BookingReviewModel>> watchServiceReviews(
    String serviceId, {
    int limit = 40,
  }) {
    final id = serviceId.trim();
    if (id.isEmpty) return Stream.value(const []);

    return _firestore
        .collection('services')
        .doc(id)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BookingReviewModel.fromDocument).toList(),
        );
  }

  Stream<List<BookingReviewModel>> watchProviderReviews(
    String providerUserId, {
    int limit = 40,
  }) {
    final id = providerUserId.trim();
    if (id.isEmpty) return Stream.value(const []);

    return _firestore
        .collectionGroup('reviews')
        .where('providerUserId', isEqualTo: id)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(BookingReviewModel.fromDocument).toList(),
        );
  }

  Stream<BookingReviewModel?> watchServiceReviewById({
    required String serviceId,
    required String reviewId,
  }) {
    final service = serviceId.trim();
    final review = reviewId.trim();
    if (service.isEmpty || review.isEmpty) return Stream.value(null);

    return _firestore
        .collection('services')
        .doc(service)
        .collection('reviews')
        .doc(review)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? BookingReviewModel.fromDocument(snapshot)
              : null,
        );
  }

  Future<BookingReviewModel?> fetchServiceReviewById({
    required String serviceId,
    required String reviewId,
  }) async {
    final service = serviceId.trim();
    final review = reviewId.trim();
    if (service.isEmpty || review.isEmpty) return null;

    final snapshot = await _firestore
        .collection('services')
        .doc(service)
        .collection('reviews')
        .doc(review)
        .get();

    if (!snapshot.exists) return null;
    return BookingReviewModel.fromDocument(snapshot);
  }

  Future<BookingReviewModel?> getReviewForBooking(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final bookingSnapshot = await _firestore
        .collection('bookings')
        .doc(id)
        .get();
    if (!bookingSnapshot.exists) return null;

    final bookingData = bookingSnapshot.data() ?? const <String, dynamic>{};
    final serviceId = _readFirstString([
      bookingData['serviceId'],
      bookingData['service_id'],
    ]);
    final review = bookingData['review'] as Map<String, dynamic>? ?? const {};
    final reviewId = _readFirstString([
      bookingData['reviewId'],
      review['reviewId'],
    ], fallback: id);
    final reviewStatus = _readFirstString([
      bookingData['reviewStatus'],
      review['status'],
    ]);

    if (serviceId.isEmpty || reviewStatus.toLowerCase() != 'submitted') {
      return null;
    }

    final reviewSnapshot = await _firestore
        .collection('services')
        .doc(serviceId)
        .collection('reviews')
        .doc(reviewId)
        .get();

    if (!reviewSnapshot.exists) return null;
    return BookingReviewModel.fromDocument(reviewSnapshot);
  }

  String _readFirstString(List<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}
