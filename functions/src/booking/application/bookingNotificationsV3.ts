export type BookingNotificationChannel = "push" | "in_app";

export type BookingNotificationType =
  | "queued_request_created"
  | "provider_action_required"
  | "payment_required"
  | "payment_order_ready"
  | "payment_captured_processing"
  | "booking_confirmed"
  | "payment_refund_required"
  | "payment_failed"
  | "zero_payable_confirmed"
  | "request_declined"
  | "request_expired"
  | "request_cancelled_by_parent"
  | "payment_expired"
  | "booking_cancelled_by_customer"
  | "booking_cancelled_by_provider"
  | "booking_cancellation_acknowledged"
  | "booking_refund_processed"
  | "booking_refund_failed"
  | "service_started"
  | "booking_no_show"
  | "service_completed"
  | "review_received"
  | "booking_finalized"
  | "payout_ready";

export type BookingNotificationPlan = {
  idempotencyKey: string;
  recipientUserId: string;
  type: BookingNotificationType;
  channels: BookingNotificationChannel[];
  title: string;
  body: string;
  data: Record<string, string>;
};

function buildPlan(params: Omit<BookingNotificationPlan, "idempotencyKey"> & {bookingId: string}): BookingNotificationPlan {
  return {
    idempotencyKey: `${params.type}:${params.bookingId}:${params.recipientUserId}`,
    recipientUserId: params.recipientUserId,
    type: params.type,
    channels: params.channels,
    title: params.title,
    body: params.body,
    data: {
      bookingId: params.bookingId,
      bookingType: params.data.bookingType ?? "",
      state: params.data.state ?? "",
    },
  };
}

export function buildQueuedRequestCreatedNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type: "queued_request_created",
    channels: ["in_app"],
    title: "New request queued",
    body: "A new booking request is waiting for your next working window.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildProviderActionRequiredNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type: "provider_action_required",
    channels: ["push", "in_app"],
    title: "New booking request",
    body: "A pet parent sent a request. Review and respond within 60 minutes.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildPaymentRequiredNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.parentId,
    type: "payment_required",
    channels: ["push", "in_app"],
    title: "Provider accepted your request",
    body: "Complete payment within 60 minutes. Availability will be confirmed when payment succeeds.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildPaymentOrderReadyNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_order_ready",
      channels: ["push", "in_app"],
      title: "Payment ready",
      body: "Checkout is ready. Complete payment before the 60-minute window ends.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildPaymentCapturedProcessingNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_captured_processing",
      channels: ["in_app"],
      title: "Payment received",
      body: "We are finalizing your booking confirmation now.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildBookingConfirmedNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "booking_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: "Your booking is confirmed. OTP, contact, and chat are now available in booking details.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "booking_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: "Payment is complete. You can now view paid-only booking details inside Pettxo.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildPaymentRefundRequiredNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_refund_required",
      channels: ["push", "in_app"],
      title: "Payment captured, refund initiated",
      body: "This booking could not be confirmed. A full refund has been initiated.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_refund_required",
      channels: ["in_app"],
      title: "Capacity race resolved",
      body: "A captured payment could not be confirmed because availability was exhausted first.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildPaymentFailedNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_failed",
      channels: ["push", "in_app"],
      title: "Payment could not be confirmed",
      body: "This payment attempt could not be completed within the allowed booking window.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_failed",
      channels: ["in_app"],
      title: "Payment not completed",
      body: "The booking did not advance to paid confirmation.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildZeroPayableConfirmationNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "zero_payable_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: "Your Pettxo promotion covered the full amount and the booking is confirmed.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "zero_payable_confirmed",
      channels: ["in_app"],
      title: "Booking confirmed",
      body: "A Pettxo-funded promotion confirmed this booking without customer checkout.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildDeclinedNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.parentId,
    type: "request_declined",
    channels: ["push", "in_app"],
    title: "Request declined",
    body: "The provider declined your booking request.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildRequestExpiredNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.parentId,
    type: "request_expired",
    channels: ["push", "in_app"],
    title: "Request expired",
    body: "The provider did not respond within the 60-minute window.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildCancelledByParentNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type: "request_cancelled_by_parent",
    channels: ["push", "in_app"],
    title: "Request cancelled",
    body: "The pet parent cancelled this request before payment.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildPaymentExpiredNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_expired",
      channels: ["push", "in_app"],
      title: "Payment window expired",
      body: "This request expired because payment was not completed in time.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_expired",
      channels: ["push", "in_app"],
      title: "Payment not completed",
      body: "The pet parent did not complete payment before the 60-minute deadline.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildServiceStartedNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.parentId,
    type: "service_started",
    channels: ["push", "in_app"],
    title: "Service started",
    body: "Your provider has started this Pettxo booking.",
    data: {bookingType: params.bookingType, state: params.state},
  });
}

export function buildBookingNoShowNotifications(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "booking_no_show",
      channels: ["push", "in_app"],
      title: "Booking marked no-show",
      body: "This booking was marked as no-show because the service OTP was not entered before the service window ended.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "booking_no_show",
      channels: ["push", "in_app"],
      title: "Booking marked no-show",
      body: "This booking was marked as no-show because the service OTP was not entered before the service window ended.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildServiceCompletedNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "service_completed",
      channels: ["push", "in_app"],
      title: "Service completed",
      body: "Your provider marked this service complete. Review your experience or raise a dispute within 24 hours if needed.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildBookingReviewReceivedNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "review_received",
      channels: ["push", "in_app"],
      title: "New review received",
      body: "The pet parent submitted a review for this completed booking.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildBookingFinalizedNotifications(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "booking_finalized",
      channels: ["push", "in_app"],
      title: "Booking finalized",
      body: "The customer review window closed and this booking is now finalized.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}

export function buildBookingPayoutReadyNotifications(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payout_ready",
      channels: ["push", "in_app"],
      title: "Payout ready",
      body: "This completed booking is now payout-ready in Pettxo.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}
