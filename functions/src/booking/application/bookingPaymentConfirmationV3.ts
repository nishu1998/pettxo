import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";

function hasConfirmedDisplayPaymentStatus(status: string): boolean {
  const normalized = status.trim().toLowerCase();
  return normalized === "paid" || normalized === "confirmed";
}

export function hasAuthoritativeConfirmedBookingPaymentV3(
  booking: Pick<CanonicalBookingDocumentV3, "lifecycle" | "payment" | "privacy">,
): boolean {
  return booking.lifecycle.paidAt != null &&
    booking.privacy.contactUnlockedAt != null &&
    (
      hasConfirmedDisplayPaymentStatus(booking.payment.status) ||
      booking.payment.capturedAt != null ||
      booking.payment.verifiedAt != null
    );
}
