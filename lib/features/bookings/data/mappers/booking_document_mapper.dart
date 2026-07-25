import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';

BookingReadModel mapBookingDocumentSnapshot(
  DocumentSnapshot<Map<String, dynamic>> snapshot,
) {
  final data = snapshot.data() ?? const <String, dynamic>{};
  if (isCanonicalBookingDocumentCandidate(data)) {
    final parsed = parseCanonicalBookingDocumentV3(data);
    if (parsed.isValid && parsed.booking != null) {
      return CanonicalBookingReadModel(
        documentId: snapshot.id,
        booking: parsed.booking!,
      );
    }
    return InvalidBookingReadModel(
      id: snapshot.id,
      rawStatus: data['state'],
      errors: parsed.issues,
      rawData: data,
    );
  }
  return InvalidBookingReadModel(
    id: snapshot.id,
    rawStatus: data['state'] ?? data['status'],
    errors: const [
      CanonicalBookingValidationIssue(
        code: 'NON_CANONICAL_BOOKING_DOCUMENT',
        message: 'Only canonical Booking Model v3.2 documents are supported.',
        path: '',
      ),
    ],
    rawData: data,
  );
}
