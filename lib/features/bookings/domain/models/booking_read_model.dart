import 'booking_document_v3.dart';

abstract class BookingReadModel {
  const BookingReadModel();

  String get bookingId;
}

class CanonicalBookingReadModel extends BookingReadModel {
  final String documentId;
  final CanonicalBookingDocumentV3 booking;

  const CanonicalBookingReadModel({
    required this.documentId,
    required this.booking,
  });

  @override
  String get bookingId => documentId;
}

class InvalidBookingReadModel extends BookingReadModel {
  final String id;
  final Object? rawStatus;
  final List<CanonicalBookingValidationIssue> errors;
  final Map<String, dynamic> rawData;

  const InvalidBookingReadModel({
    required this.id,
    required this.rawStatus,
    required this.errors,
    required this.rawData,
  });

  @override
  String get bookingId => id;
}
