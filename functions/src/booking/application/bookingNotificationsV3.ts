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
    title: "New booking request",
    body: "Waiting for your next working window.",
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
    body: `${serviceName}. Respond before the request expires.`,
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
      `${serviceName}: ${safeMinutesRemaining} minutes left to respond.` :
      `${serviceName}: ${safeMinutesRemaining} minutes left to accept or decline.`;
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
    title: "Request accepted",
    body: "Complete payment within 60 minutes to confirm availability.",
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
      `${safeMinutesRemaining} minutes left to complete payment.` :
      `${safeMinutesRemaining} minutes left before payment expires.`;
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
      body: "Complete payment before the payment window ends.",
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
      body: "Confirming your booking.",
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
      body: "OTP, contact, and chat are available in booking details.",
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
      body: `Payment successful for ${serviceName}.`,
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
      title: "Refund initiated",
      body: "We could not confirm the booking. A full refund is underway.",
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
      title: "Booking unavailable",
      body: "Another booking filled the remaining availability first.",
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
      title: "Payment not completed",
      body: "The payment window ended before confirmation.",
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
      body: "The customer did not complete payment in time.",
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
      body: "Your Pettxo promotion covered the full amount.",
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
      body: `Confirmed for ${serviceName}.`,
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
    body: "The provider could not accept this booking.",
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
    body: "The customer cancelled before payment.",
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
      body: "Payment was not completed in time.",
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
      body: "The customer missed the 60-minute deadline.",
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
    body: "Your provider has begun the booking.",
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
      body: "The service OTP was not entered before the service window ended.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
    buildPlan({
      bookingId: params.bookingId,
      recipientUserId: params.providerId,
      type: "booking_no_show",
      channels: ["push", "in_app"],
      title: "Booking marked no-show",
      body: "The service OTP was not entered before the service window ended.",
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
      body: "Review your experience or raise a dispute within 24 hours.",
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
    body: "Settlement is on hold while Pettxo reviews the case.",
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
      body: "A customer reviewed this completed booking.",
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
      body: "The customer review window has closed.",
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
      body: "Earnings from this booking are ready for payout.",
      data: {bookingType: params.bookingType, state: params.state},
    }),
  ];
}
