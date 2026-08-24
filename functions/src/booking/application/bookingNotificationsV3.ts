import {
  normalizeNotificationChannels,
  type NotificationChannel,
} from "../../notifications/notificationChannels";

export type BookingNotificationChannel = NotificationChannel;

export type BookingNotificationType =
  | "queued_request_created"
  | "provider_action_required"
  | "provider_request_halfway"
  | "provider_request_ten_minute"
  | "payment_required"
  | "customer_payment_halfway"
  | "customer_payment_ten_minute"
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
  | "booking_dispute_opened"
  | "booking_dispute_resolved"
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

function buildPlan(
  params: Omit<BookingNotificationPlan, "idempotencyKey"> & {
    bookingId: string;
    idempotencyKey?: string;
  },
): BookingNotificationPlan {
  return {
    idempotencyKey:
      params.idempotencyKey ?? `${params.type}:${params.bookingId}:${params.recipientUserId}`,
    recipientUserId: params.recipientUserId,
    type: params.type,
    channels: normalizeNotificationChannels(params.channels),
    title: params.title,
    body: params.body,
    data: {
      ...params.data,
      bookingId: params.bookingId,
      bookingType: params.data.bookingType ?? "",
      state: params.data.state ?? "",
    },
  };
}

function serviceNameOrFallback(serviceName: string | undefined): string {
  const trimmed = serviceName?.trim() ?? "";
  return trimmed || "your service";
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
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "provider",
      navigationIntent: "provider_request",
      bookingFlowVersion: "3.2",
    },
  });
}

export function buildProviderActionRequiredNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
  serviceName?: string;
}): BookingNotificationPlan {
  const serviceName = serviceNameOrFallback(params.serviceName);
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type: "provider_action_required",
    channels: ["push", "in_app"],
    title: "New booking request",
    body: `You received a booking request for ${serviceName}. Review it before the request expires.`,
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "provider",
      navigationIntent: "provider_request",
      bookingFlowVersion: "3.2",
    },
  });
}

export function buildProviderRequestReminderNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
  serviceName?: string;
  minutesRemaining: number;
  stage: "halfway" | "ten_minute";
}): BookingNotificationPlan {
  const serviceName = serviceNameOrFallback(params.serviceName);
  const safeMinutesRemaining = Math.max(Math.trunc(params.minutesRemaining), 1);
  const type =
    params.stage === "halfway" ?
      "provider_request_halfway" :
      "provider_request_ten_minute";
  const title =
    params.stage === "halfway" ?
      "Booking request waiting" :
      "Booking request expires soon";
  const body =
    params.stage === "halfway" ?
      `A booking request for ${serviceName} is still waiting for your response. ${safeMinutesRemaining} minutes remain.` :
      `Only ${safeMinutesRemaining} minutes remain to accept or decline the booking request for ${serviceName}.`;
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type,
    channels: ["push", "in_app"],
    title,
    body,
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "provider",
      navigationIntent: "provider_request",
      bookingFlowVersion: "3.2",
    },
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
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "customer",
      navigationIntent: "payment",
      bookingFlowVersion: "3.2",
    },
  });
}

export function buildCustomerPaymentReminderNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
  minutesRemaining: number;
  stage: "halfway" | "ten_minute";
}): BookingNotificationPlan {
  const safeMinutesRemaining = Math.max(Math.trunc(params.minutesRemaining), 1);
  const type =
    params.stage === "halfway" ?
      "customer_payment_halfway" :
      "customer_payment_ten_minute";
  const title =
    params.stage === "halfway" ?
      "Payment reminder" :
      "Payment expires soon";
  const body =
    params.stage === "halfway" ?
      `Complete payment to confirm your booking. ${safeMinutesRemaining} minutes remain before this booking request expires.` :
      `Only ${safeMinutesRemaining} minutes remain to complete payment before your booking request expires.`;
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.parentId,
    type,
    channels: ["push", "in_app"],
    title,
    body,
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "customer",
      navigationIntent: "payment",
      bookingFlowVersion: "3.2",
    },
  });
}

export function buildPaymentOrderReadyNotification(params: {
  bookingId: string;
  parentId: string;
  bookingType: string;
  state: string;
  paymentAttemptId?: string;
}): BookingNotificationPlan[] {
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "payment_order_ready",
      channels: ["push", "in_app"],
      title: "Payment ready",
      body: "Checkout is ready. Complete payment before the 60-minute window ends.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "payment",
        bookingFlowVersion: "3.2",
        paymentAttemptId: params.paymentAttemptId ?? "",
      },
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
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "booking_detail",
        bookingFlowVersion: "3.2",
      },
    }),
  ];
}

export function buildBookingConfirmedNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
  serviceName?: string;
}): BookingNotificationPlan[] {
  const serviceName = serviceNameOrFallback(params.serviceName);
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "booking_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: "Your booking is confirmed. OTP, contact, and chat are now available in booking details.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "booking_detail",
        bookingFlowVersion: "3.2",
      },
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "booking_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: `Payment was successful. Your booking for ${serviceName} is now confirmed.`,
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "provider",
        navigationIntent: "booking_detail",
        bookingFlowVersion: "3.2",
      },
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
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "request_status",
        bookingFlowVersion: "3.2",
      },
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_refund_required",
      channels: ["in_app"],
      title: "Capacity race resolved",
      body: "A captured payment could not be confirmed because availability was exhausted first.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "provider",
        navigationIntent: "provider_request",
        bookingFlowVersion: "3.2",
      },
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
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "request_status",
        bookingFlowVersion: "3.2",
      },
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_failed",
      channels: ["in_app"],
      title: "Payment not completed",
      body: "The booking did not advance to paid confirmation.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "provider",
        navigationIntent: "provider_request",
        bookingFlowVersion: "3.2",
      },
    }),
  ];
}

export function buildZeroPayableConfirmationNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
  serviceName?: string;
}): BookingNotificationPlan[] {
  const serviceName = serviceNameOrFallback(params.serviceName);
  return [
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.parentId,
      type: "zero_payable_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: "Your Pettxo promotion covered the full amount and the booking is confirmed.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "booking_detail",
        bookingFlowVersion: "3.2",
      },
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "zero_payable_confirmed",
      channels: ["push", "in_app"],
      title: "Booking confirmed",
      body: `Your booking for ${serviceName} is now confirmed.`,
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "provider",
        navigationIntent: "booking_detail",
        bookingFlowVersion: "3.2",
      },
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
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "customer",
      navigationIntent: "request_status",
      bookingFlowVersion: "3.2",
    },
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
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "customer",
      navigationIntent: "request_status",
      bookingFlowVersion: "3.2",
    },
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
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "provider",
      navigationIntent: "provider_request",
      bookingFlowVersion: "3.2",
    },
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
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "customer",
        navigationIntent: "request_status",
        bookingFlowVersion: "3.2",
      },
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "payment_expired",
      channels: ["push", "in_app"],
      title: "Payment not completed",
      body: "The pet parent did not complete payment before the 60-minute deadline.",
      data: {
        bookingType: params.bookingType,
        state: params.state,
        recipientRole: "provider",
        navigationIntent: "provider_request",
        bookingFlowVersion: "3.2",
      },
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

export function buildBookingDisputeOpenedNotification(params: {
  bookingId: string;
  providerId: string;
  bookingType: string;
  state: string;
}): BookingNotificationPlan {
  return buildPlan({
    bookingId: params.bookingId,
    recipientUserId: params.providerId,
    type: "booking_dispute_opened",
    channels: ["push", "in_app"],
    title: "Booking dispute opened",
    body:
      "A dispute has been raised for this booking. Your settlement is currently on hold while Pettxo reviews the case.",
    data: {
      bookingType: params.bookingType,
      state: params.state,
      recipientRole: "provider",
      navigationIntent: "provider_booking",
      bookingFlowVersion: "3.2",
    },
  });
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
