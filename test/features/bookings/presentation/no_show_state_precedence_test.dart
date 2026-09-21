import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/presentation/utils/canonical_booking_presentation_state.dart';

void main() {
  test('persisted no-show survives historical OTP and payment fields', () {
    expect(
      effectiveCanonicalBookingPresentationStateFromRaw(
        CanonicalBookingStateV3.noShow,
        DateTime(2020),
        otpEnteredAt: DateTime(2020),
        paidAt: DateTime(2020),
        paymentStatus: 'confirmed',
        disputeStatus: 'open',
      ),
      CanonicalBookingStateV3.noShow,
    );
  });
  for (final state in [
    CanonicalBookingStateV3.requested,
    CanonicalBookingStateV3.confirmed,
    CanonicalBookingStateV3.inProgress,
    CanonicalBookingStateV3.completedFinal,
    CanonicalBookingStateV3.cancelled,
    CanonicalBookingStateV3.cancelledByParent,
    CanonicalBookingStateV3.acceptedAwaitingPayment,
  ]) {
    test(
      'no-show presentation does not replace $state without eligibility',
      () {
        expect(
          effectiveCanonicalBookingPresentationStateFromRaw(
            state,
            null,
            otpEnteredAt: DateTime(2020),
          ),
          state,
        );
      },
    );
  }
}
