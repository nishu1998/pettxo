import {createHash} from "node:crypto";

import {computeAcceptDeadlineAt, computePayDeadlineAt} from "../domain/bookingDeadlines";
import type {BookingType, CanonicalBookingState, ProviderResponseType} from "../domain/bookingContracts";
import type {RangeBookingSelection} from "../domain/rangeBooking";
import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";
import {
  BOOKING_PRIVACY_VERSION,
  CANONICAL_BOOKING_DOCUMENT_FORMAT,
  CANONICAL_BOOKING_MODEL_VERSION,
  CANONICAL_BOOKING_SCHEMA_VERSION,
} from "../schema/bookingDocumentV3";
import type {SlotBookingSelection} from "../domain/slotBooking";
import {buildBookingEventPlan, type BookingEventWritePlan} from "./bookingEventsWriter";
import {
  buildCancelledByParentNotification,
  buildDeclinedNotification,
  buildPaymentExpiredNotification,
  buildPaymentRequiredNotification,
  buildProviderActionRequiredNotification,
  buildQueuedRequestCreatedNotification,
  buildRequestExpiredNotification,
  type BookingNotificationPlan,
} from "./bookingNotificationsV3";
import {
  applyParentStatsMutation,
  applyProviderStatsMutation,
  emptyParentStatsV3,
  emptyProviderStatsV3,
  type ParentStatsV3,
  type ProviderStatsV3,
} from "./bookingStats";
import {evaluateBookingTransition} from "./bookingStateMachine";
import {
  computeTimerStartsAt,
  normalizeServiceWorkingHours,
  type CanonicalServiceWorkingHoursSource,
} from "./workingHours";
import {validateCanonicalBookingRunway} from "./bookingRunway";

export type CanonicalServiceSource = CanonicalServiceWorkingHoursSource & {
  id: string;
  ownerUserId: string;
  ownerName?: string;
  ownerUsername?: string;
  ownerPhotoUrl?: string;
  title?: string;
  animalType?: string;
  category?: string;
  serviceType?: string;
  currency?: string;
  sessionDurationMinutes?: number;
  capacity?: number;
  stats?: Record<string, unknown>;
  location?: Record<string, unknown>;
};

export type AuthenticatedParentIdentity = {
  uid: string;
  displayName?: string;
  photoUrl?: string;
  fullName?: string;
  email?: string;
  phoneNumber?: string;
  rating?: number;
  completedBookingCount?: number;
};

export type BookingRequestAttemptRecord = {
  parentId: string;
  requestAttemptId: string;
  bookingId: string;
  requestHash: string;
  bookingSnapshot: CanonicalBookingDocumentV3;
};

export type CreateBookingRequestV3Input = {
  requestAttemptId: string;
  serviceId: string;
  bookingType: BookingType;
  schedule: SlotBookingSelection | RangeBookingSelection;
};

export type CreateBookingRequestV3Result =
  | {
      ok: true;
      code: "CREATED" | "IDEMPOTENT_REPLAY";
      bookingId: string;
      booking: CanonicalBookingDocumentV3;
      attemptRecord: BookingRequestAttemptRecord;
      events: BookingEventWritePlan[];
      notifications: BookingNotificationPlan[];
      providerStats: ProviderStatsV3;
      parentStats: ParentStatsV3;
    }
  | {
      ok: false;
      code: string;
      message: string;
      issues?: string[];
    };

export type RequestLifecycleCommandResult =
  | {
      ok: true;
      code: "UPDATED" | "IDEMPOTENT_REPLAY";
      booking: CanonicalBookingDocumentV3;
      events: BookingEventWritePlan[];
      notifications: BookingNotificationPlan[];
      providerStats: ProviderStatsV3 | null;
      parentStats: ParentStatsV3 | null;
    }
  | {
      ok: false;
      code: string;
      message: string;
    };

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function cloneBooking(booking: CanonicalBookingDocumentV3): CanonicalBookingDocumentV3 {
  return structuredClone(booking);
}

function firstName(fullName: string): string {
  const trimmed = fullName.trim();
  if (!trimmed) return "Pet";
  return trimmed.split(/\s+/)[0] || "Pet";
}

function lastInitial(fullName: string): string {
  const trimmed = fullName.trim();
  if (!trimmed) return "P";
  const parts = trimmed.split(/\s+/);
  const last = parts[parts.length - 1] ?? "";
  return last ? last[0].toUpperCase() : "P";
}

function requestHash(input: CreateBookingRequestV3Input): string {
  const payload = {
    serviceId: input.serviceId,
    bookingType: input.bookingType,
    requestAttemptId: input.requestAttemptId,
    schedule: JSON.parse(JSON.stringify(input.schedule)),
  };
  return createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

function buildServiceSnapshot(
  service: CanonicalServiceSource,
  input: CreateBookingRequestV3Input,
): CanonicalBookingDocumentV3["service"] {
  const base = {
    serviceId: service.id,
    providerId: service.ownerUserId,
    serviceTitle: asString(service.title) || "Service booking",
    animalType: asString(service.animalType),
    category: asString(service.category),
    bookingType: input.bookingType,
    timezone: asString(service.timezone) || "Asia/Kolkata",
    capacitySnapshot: Math.max(asInt(service.capacity) ?? 1, 1),
    serviceLocationType: asString(service.serviceType) || "provider_location",
    currency: asString(service.currency) || "INR",
    snapshotVersion: 1 as const,
  };
  if (input.bookingType === "SLOT") {
    const schedule = input.schedule as SlotBookingSelection;
    return {
      ...base,
      serviceUnitPricePaise: Math.max(
        asInt((service as {pricePerSession?: unknown}).pricePerSession) ?? 0,
        0,
      ) * 100,
      durationMinutes: asInt(service.sessionDurationMinutes) ?? schedule.totalDurationMinutes,
      selectedSlotCount: schedule.slotCount,
      totalDurationMinutes: schedule.totalDurationMinutes,
    };
  }
  const range = input.schedule as RangeBookingSelection;
  return {
    ...base,
    pricePerNightPaise: range.pricePerNightPaise,
    checkInDateTime: range.checkInDateTime,
    checkOutDateTime: range.checkOutDateTime,
  };
}

function buildSchedule(
  input: CreateBookingRequestV3Input,
  serviceTimezone: string,
): CanonicalBookingDocumentV3["schedule"] {
  if (input.bookingType === "SLOT") {
    const schedule = input.schedule as SlotBookingSelection;
    return {
      bookingType: "SLOT",
      slots: schedule.slots.map((slot) => ({
        slotId: slot.slotId,
        dateKey: slot.dateKey,
        startAt: new Date(slot.startAt.getTime()),
        endAt: new Date(slot.endAt.getTime()),
        durationMinutes: slot.durationMinutes,
        unitPricePaise: slot.unitPricePaise,
        serviceId: slot.serviceId,
        providerId: slot.providerId,
        timezone: slot.timezone,
      })),
      slotCount: schedule.slotCount,
      scheduledStartAt: new Date(schedule.scheduledStartAt.getTime()),
      scheduledEndAt: new Date(schedule.scheduledEndAt.getTime()),
      totalDurationMinutes: schedule.totalDurationMinutes,
      timezone: serviceTimezone,
      serviceAnchorAt: new Date(schedule.scheduledStartAt.getTime()),
    };
  }
  const range = input.schedule as RangeBookingSelection;
  return {
    bookingType: "RANGE",
    checkInDateTime: new Date(range.checkInDateTime.getTime()),
    checkOutDateTime: new Date(range.checkOutDateTime.getTime()),
    nights: range.nights,
    timezone: serviceTimezone,
    minNightsSnapshot: range.minNights ?? null,
    maxNightsSnapshot: range.maxNights ?? null,
    maxConcurrentPetsSnapshot: range.maxConcurrentPetsSnapshot ?? null,
    petQuantity: range.petQuantity ?? null,
    serviceAnchorAt: new Date(range.checkInDateTime.getTime()),
  };
}

function buildRequestSafeBooking(params: {
  bookingId: string;
  parent: AuthenticatedParentIdentity;
  service: CanonicalServiceSource;
  input: CreateBookingRequestV3Input;
  requestedAt: Date;
  timerStartsAt: Date;
  wasQueuedOutsideWorkingHours: boolean;
  serviceAnchorAt: Date;
}): CanonicalBookingDocumentV3 {
  const immediateTimer = params.timerStartsAt.getTime() <= params.requestedAt.getTime();
  const state: CanonicalBookingState = immediateTimer ? "PENDING_PROVIDER" : "REQUESTED";
  const acceptDeadlineAt = computeAcceptDeadlineAt(params.timerStartsAt);
  const serviceTimezone = asString(params.service.timezone) || "Asia/Kolkata";
  return {
    schemaVersion: CANONICAL_BOOKING_SCHEMA_VERSION,
    bookingModelVersion: CANONICAL_BOOKING_MODEL_VERSION,
    documentFormat: CANONICAL_BOOKING_DOCUMENT_FORMAT,
    bookingType: params.input.bookingType,
    state,
    participants: {
      parent: {
        parentId: params.parent.uid,
        displayFirstName: firstName(asString(params.parent.fullName) || asString(params.parent.displayName)),
        lastInitial: lastInitial(asString(params.parent.fullName) || asString(params.parent.displayName)),
        photoUrl: asString(params.parent.photoUrl),
        completedBookingCount: Math.max(params.parent.completedBookingCount ?? 0, 0),
        rating: params.parent.rating ?? 0,
      },
      provider: {
        providerId: params.service.ownerUserId,
        displayName: asString(params.service.ownerName) || "Provider",
        username: asString(params.service.ownerUsername).replace(/^@/, ""),
        photoUrl: asString(params.service.ownerPhotoUrl),
        completedBookingCount: Math.max(
          asInt((params.service.stats ?? {}).completedBookingsCount) ??
          asInt((params.service.stats ?? {}).completedBookingCount) ??
          0,
          0,
        ),
        rating: asNumber((params.service.stats ?? {}).ratingAverage) ?? 0,
      },
    },
    service: buildServiceSnapshot(params.service, params.input),
    schedule: buildSchedule(params.input, serviceTimezone),
    lifecycle: {
      requestedAt: new Date(params.requestedAt.getTime()),
      timerStartsAt: new Date(params.timerStartsAt.getTime()),
      wasQueuedOutsideWorkingHours: params.wasQueuedOutsideWorkingHours,
      notifiedAt: null,
      acceptDeadlineAt,
      viewedByProviderAt: null,
      respondedAt: null,
      providerResponseType: null,
      responseSeconds: null,
      payDeadlineAt: null,
      paymentStartedAt: null,
      paidAt: null,
      paymentSeconds: null,
      otpGeneratedAt: null,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: null,
      cancelledAt: null,
    },
    payment: {
      status: "not_started",
      razorpayOrderId: "",
      razorpayPaymentId: "",
      razorpayRefundId: "",
      paymentAttemptId: "",
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: "",
      webhookEventIds: [],
      failureCode: "",
      failureMessage: "",
    },
    financials: null,
    privacy: {
      isPaidContactUnlocked: false,
      contactUnlockedAt: null,
      chatUnlockedAt: null,
      otpVisibleToParent: false,
      exactAddressUnlocked: false,
      privacyVersion: BOOKING_PRIVACY_VERSION,
      privateParticipantsRefPath: `bookingPrivateParticipants/${params.bookingId}`,
    },
    cancellation: {
      cancelledAt: null,
      cancelledBy: null,
      cancelReasonCode: "",
      cancelReasonText: "",
      hoursBeforeServiceAtCancel: null,
      refundBand: "",
      refundBasisPoints: null,
      refundAmountPaise: 0,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 0,
      cancellationType: null,
    },
    dispute: {
      disputeId: "",
      status: "none",
      raisedAt: null,
      raisedBy: null,
      reasonCode: "",
      description: "",
      evidenceRefs: [],
      resolvedAt: null,
      resolvedBy: null,
      resolution: "",
      resolutionVersion: 0,
      financialAdjustmentId: "",
      refundInstructionId: "",
      customerRefundPaise: 0,
      providerReleasePaise: 0,
    },
    payout: {
      status: "not_eligible",
      holdReason: "",
      eligibleAt: null,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: 0,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: "",
      externalTransactionId: "",
      failureCode: "",
      retryCount: 0,
    },
    statistics: {
      selectedSlotCount: params.input.bookingType === "SLOT" ?
        (params.input.schedule as SlotBookingSelection).slotCount :
        null,
      totalDurationMinutes: params.input.bookingType === "SLOT" ?
        (params.input.schedule as SlotBookingSelection).totalDurationMinutes :
        null,
      nights: params.input.bookingType === "RANGE" ?
        (params.input.schedule as RangeBookingSelection).nights :
        null,
    },
    audit: {
      createdBy: "parent",
      lastUpdatedBy: "system",
      source: "booking_v3_internal",
    },
    parentId: params.parent.uid,
    providerId: params.service.ownerUserId,
    serviceId: params.service.id,
    stateQueryValue: state,
    bookingTypeQueryValue: params.input.bookingType,
    serviceAnchorAt: new Date(params.serviceAnchorAt.getTime()),
    scheduledStartAt: params.input.bookingType === "SLOT" ?
      new Date((params.input.schedule as SlotBookingSelection).scheduledStartAt.getTime()) :
      null,
    checkInDateTime: params.input.bookingType === "RANGE" ?
      new Date((params.input.schedule as RangeBookingSelection).checkInDateTime.getTime()) :
      null,
    acceptDeadlineAt,
    payDeadlineAt: null,
    completedAt: null,
    customerId: params.parent.uid,
    serviceOwnerId: params.service.ownerUserId,
    createdAt: new Date(params.requestedAt.getTime()),
    updatedAt: new Date(params.requestedAt.getTime()),
  };
}

export function createBookingRequestV3(params: {
  parent: AuthenticatedParentIdentity;
  service: CanonicalServiceSource | null;
  input: CreateBookingRequestV3Input;
  authoritativeNow: Date;
  generatedBookingId: string;
  existingAttempt?: BookingRequestAttemptRecord | null;
  existingProviderStats?: ProviderStatsV3 | null;
  existingParentStats?: ParentStatsV3 | null;
}): CreateBookingRequestV3Result {
  if (!params.service) {
    return {ok: false, code: "SERVICE_NOT_FOUND", message: "Service does not exist."};
  }
  if (!params.parent.uid.trim()) {
    return {ok: false, code: "UNAUTHENTICATED", message: "Authenticated parent is required."};
  }
  if (params.service.ownerUserId === params.parent.uid) {
    return {ok: false, code: "SELF_BOOKING_NOT_ALLOWED", message: "Providers cannot book their own service."};
  }

  const attemptHash = requestHash(params.input);
  if (params.existingAttempt) {
    if (params.existingAttempt.requestHash !== attemptHash) {
      return {
        ok: false,
        code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
        message: "requestAttemptId is already bound to a different booking payload.",
      };
    }
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      bookingId: params.existingAttempt.bookingId,
      booking: cloneBooking(params.existingAttempt.bookingSnapshot),
      attemptRecord: params.existingAttempt,
      events: [],
      notifications: [],
      providerStats: params.existingProviderStats ?? emptyProviderStatsV3(),
      parentStats: params.existingParentStats ?? emptyParentStatsV3(),
    };
  }

  const normalizedHours = normalizeServiceWorkingHours(params.service);
  if (!normalizedHours.ok) {
    return {
      ok: false,
      code: "INVALID_WORKING_HOURS",
      message: "Service working-hours configuration is invalid.",
      issues: normalizedHours.issues,
    };
  }

  const timerStart = computeTimerStartsAt({
    requestedAt: params.authoritativeNow,
    timezone: normalizedHours.workingHours.timezone,
    workingHours: normalizedHours.workingHours,
  });
  const runway = validateCanonicalBookingRunway({
    bookingType: params.input.bookingType,
    schedule: params.input.schedule,
    authoritativeNow: params.authoritativeNow,
    service: params.service,
    workingHours: normalizedHours.workingHours,
  });
  if (!runway.ok || runway.serviceAnchorAt == null) {
    return {
      ok: false,
      code: runway.issues[0]?.code ?? "INVALID_SCHEDULE",
      message: "Booking request failed validation.",
      issues: runway.issues.map((entry) => `${entry.code}:${entry.message}`),
    };
  }

  if (params.input.bookingType === "SLOT") {
    const slotSchedule = params.input.schedule as SlotBookingSelection;
    const wrongService = slotSchedule.slots.some((slot) => slot.serviceId !== params.service!.id);
    const wrongProvider = slotSchedule.slots.some((slot) => slot.providerId !== params.service!.ownerUserId);
    if (wrongService || wrongProvider) {
      return {
        ok: false,
        code: "AUTHORITATIVE_SCHEDULE_MISMATCH",
        message: "Selected slot ownership does not match the authoritative service.",
      };
    }
  }

  const booking = buildRequestSafeBooking({
    bookingId: params.generatedBookingId,
    parent: params.parent,
    service: params.service,
    input: params.input,
    requestedAt: params.authoritativeNow,
    timerStartsAt: timerStart.timerStartsAt,
    wasQueuedOutsideWorkingHours: timerStart.wasQueuedOutsideWorkingHours,
    serviceAnchorAt: runway.serviceAnchorAt,
  });

  const events = [
    buildBookingEventPlan({
      bookingId: params.generatedBookingId,
      event: "requested",
      actor: "parent",
      at: params.authoritativeNow,
      meta: {state: booking.state, queued: timerStart.wasQueuedOutsideWorkingHours},
    }),
  ];

  const notifications: BookingNotificationPlan[] = [];
  let providerStats = params.existingProviderStats ?? emptyProviderStatsV3();
  let parentStats = applyParentStatsMutation(
    params.existingParentStats ?? emptyParentStatsV3(),
    {
      type: "request_created",
      mutationKey: `request_created:${params.generatedBookingId}`,
      occurredAt: params.authoritativeNow,
    },
  );

  if (booking.state === "PENDING_PROVIDER") {
    events.push(
      buildBookingEventPlan({
        bookingId: params.generatedBookingId,
        event: "timer_started",
        actor: "system",
        at: booking.lifecycle.timerStartsAt ?? params.authoritativeNow,
        meta: {acceptDeadlineAt: booking.acceptDeadlineAt?.toISOString() ?? ""},
      }),
    );
    notifications.push(
      buildProviderActionRequiredNotification({
        bookingId: params.generatedBookingId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: booking.state,
      }),
    );
    providerStats = applyProviderStatsMutation(providerStats, {
      type: "request_started",
      mutationKey: `request_started:${params.generatedBookingId}`,
      occurredAt: booking.lifecycle.timerStartsAt ?? params.authoritativeNow,
    });
  } else {
    notifications.push(
      buildQueuedRequestCreatedNotification({
        bookingId: params.generatedBookingId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: booking.state,
      }),
    );
  }

  const attemptRecord: BookingRequestAttemptRecord = {
    parentId: params.parent.uid,
    requestAttemptId: params.input.requestAttemptId,
    bookingId: params.generatedBookingId,
    requestHash: attemptHash,
    bookingSnapshot: cloneBooking(booking),
  };

  return {
    ok: true,
    code: "CREATED",
    bookingId: params.generatedBookingId,
    booking,
    attemptRecord,
    events,
    notifications,
    providerStats,
    parentStats,
  };
}

function updateBookingState(
  booking: CanonicalBookingDocumentV3,
  state: CanonicalBookingState,
): CanonicalBookingDocumentV3 {
  const next = cloneBooking(booking);
  next.state = state;
  next.stateQueryValue = state;
  next.updatedAt = new Date(next.updatedAt.getTime());
  return next;
}

function responseSecondsFromTimer(booking: CanonicalBookingDocumentV3, at: Date): number | null {
  const timerStartsAt = booking.lifecycle.timerStartsAt;
  if (!timerStartsAt) return null;
  return Math.max(Math.round((at.getTime() - timerStartsAt.getTime()) / 1000), 0);
}

export function activateQueuedBookingRequestV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
  existingProviderStats?: ProviderStatsV3 | null;
}): RequestLifecycleCommandResult {
  if (params.booking.state === "PENDING_PROVIDER") {
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      booking: cloneBooking(params.booking),
      events: [],
      notifications: [],
      providerStats: params.existingProviderStats ?? emptyProviderStatsV3(),
      parentStats: null,
    };
  }
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: "PENDING_PROVIDER",
    actor: "system",
    now: params.authoritativeNow,
  });
  if (!transition.ok) {
    return {ok: false, code: transition.code, message: transition.message};
  }
  if (
    !params.booking.lifecycle.timerStartsAt ||
    params.authoritativeNow.getTime() < params.booking.lifecycle.timerStartsAt.getTime()
  ) {
    return {ok: false, code: "DEADLINE_PASSED", message: "Timer cannot start before timerStartsAt."};
  }
  const next = updateBookingState(params.booking, "PENDING_PROVIDER");
  next.audit.lastUpdatedBy = "system";
  const events = [
    buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "timer_started",
      actor: "system",
      at: params.booking.lifecycle.timerStartsAt,
      meta: {acceptDeadlineAt: params.booking.acceptDeadlineAt?.toISOString() ?? ""},
    }),
  ];
  const notifications = [
    buildProviderActionRequiredNotification({
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      bookingType: params.booking.bookingType,
      state: next.state,
    }),
  ];
  const providerStats = applyProviderStatsMutation(
    params.existingProviderStats ?? emptyProviderStatsV3(),
    {
      type: "request_started",
      mutationKey: `request_started:${params.bookingId}`,
      occurredAt: params.booking.lifecycle.timerStartsAt,
    },
  );
  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events,
    notifications,
    providerStats,
    parentStats: null,
  };
}

export function markBookingViewedByProviderV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  providerUid: string;
  authoritativeNow: Date;
}): RequestLifecycleCommandResult {
  if (params.providerUid !== params.booking.providerId) {
    return {ok: false, code: "ACTOR_NOT_AUTHORIZED", message: "Provider does not own this booking."};
  }
  if (!["REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT"].includes(params.booking.state)) {
    return {ok: false, code: "INVALID_CURRENT_STATE", message: "Viewing is not meaningful in this state."};
  }
  if (params.booking.lifecycle.viewedByProviderAt) {
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      booking: cloneBooking(params.booking),
      events: [],
      notifications: [],
      providerStats: null,
      parentStats: null,
    };
  }
  const next = cloneBooking(params.booking);
  next.lifecycle.viewedByProviderAt = new Date(params.authoritativeNow.getTime());
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "provider";
  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "viewed_by_provider",
        actor: "provider",
        at: params.authoritativeNow,
      }),
    ],
    notifications: [],
    providerStats: null,
    parentStats: null,
  };
}

function applyProviderResponse(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  providerUid: string;
  authoritativeNow: Date;
  targetState: "ACCEPTED_AWAITING_PAYMENT" | "DECLINED";
  responseType: ProviderResponseType;
  existingProviderStats?: ProviderStatsV3 | null;
}): RequestLifecycleCommandResult {
  if (params.providerUid !== params.booking.providerId) {
    return {ok: false, code: "ACTOR_NOT_AUTHORIZED", message: "Provider does not own this booking."};
  }
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: params.targetState,
    actor: "provider",
    now: params.authoritativeNow,
    acceptDeadlineAt: params.booking.acceptDeadlineAt,
  });
  if (!transition.ok) {
    if (transition.code === "IDEMPOTENT_REPLAY" && params.booking.state === params.targetState) {
      return {
        ok: true,
        code: "IDEMPOTENT_REPLAY",
        booking: cloneBooking(params.booking),
        events: [],
        notifications: [],
        providerStats: params.existingProviderStats ?? emptyProviderStatsV3(),
        parentStats: null,
      };
    }
    return {ok: false, code: transition.code, message: transition.message};
  }

  const next = updateBookingState(params.booking, params.targetState);
  next.lifecycle.respondedAt = new Date(params.authoritativeNow.getTime());
  next.lifecycle.providerResponseType = params.responseType;
  next.lifecycle.responseSeconds = responseSecondsFromTimer(params.booking, params.authoritativeNow);
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "provider";
  next.audit.source = "booking_v3_internal";

  const providerStats = applyProviderStatsMutation(
    params.existingProviderStats ?? emptyProviderStatsV3(),
    params.targetState === "ACCEPTED_AWAITING_PAYMENT" ? {
      type: "accepted",
      mutationKey: `accepted:${params.bookingId}`,
      occurredAt: params.authoritativeNow,
      responseSeconds: next.lifecycle.responseSeconds,
    } : {
      type: "declined",
      mutationKey: `declined:${params.bookingId}`,
      occurredAt: params.authoritativeNow,
      responseSeconds: next.lifecycle.responseSeconds,
    },
  );

  if (params.targetState === "ACCEPTED_AWAITING_PAYMENT") {
    next.lifecycle.payDeadlineAt = computePayDeadlineAt(params.authoritativeNow);
    next.payDeadlineAt = next.lifecycle.payDeadlineAt;
    const notifications = [
      buildPaymentRequiredNotification({
        bookingId: params.bookingId,
        parentId: params.booking.parentId,
        bookingType: next.bookingType,
        state: next.state,
      }),
    ];
    return {
      ok: true,
      code: "UPDATED",
      booking: next,
      events: [
        buildBookingEventPlan({
          bookingId: params.bookingId,
          event: "accepted",
          actor: "provider",
          at: params.authoritativeNow,
          meta: {payDeadlineAt: next.payDeadlineAt?.toISOString() ?? ""},
        }),
      ],
      notifications,
      providerStats,
      parentStats: null,
    };
  }

  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "declined",
        actor: "provider",
        at: params.authoritativeNow,
      }),
    ],
    notifications: [
      buildDeclinedNotification({
        bookingId: params.bookingId,
        parentId: params.booking.parentId,
        bookingType: next.bookingType,
        state: next.state,
      }),
    ],
    providerStats,
    parentStats: null,
  };
}

export function acceptBookingRequestV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  providerUid: string;
  authoritativeNow: Date;
  existingProviderStats?: ProviderStatsV3 | null;
}): RequestLifecycleCommandResult {
  return applyProviderResponse({
    ...params,
    targetState: "ACCEPTED_AWAITING_PAYMENT",
    responseType: "accept",
  });
}

export function declineBookingRequestV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  providerUid: string;
  authoritativeNow: Date;
  existingProviderStats?: ProviderStatsV3 | null;
}): RequestLifecycleCommandResult {
  return applyProviderResponse({
    ...params,
    targetState: "DECLINED",
    responseType: "decline",
  });
}

export function cancelBookingRequestByParentV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  parentUid: string;
  authoritativeNow: Date;
}): RequestLifecycleCommandResult {
  if (params.parentUid !== params.booking.parentId) {
    return {ok: false, code: "ACTOR_NOT_AUTHORIZED", message: "Parent does not own this booking."};
  }
  if (!["REQUESTED", "PENDING_PROVIDER"].includes(params.booking.state)) {
    return {
      ok: false,
      code: "INVALID_CURRENT_STATE",
      message: "Parent cancellation is only allowed before payment while the request is queued or pending provider response.",
    };
  }
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: "CANCELLED_BY_PARENT",
    actor: "parent",
    now: params.authoritativeNow,
    acceptDeadlineAt: params.booking.acceptDeadlineAt,
  });
  if (!transition.ok) {
    return {ok: false, code: transition.code, message: transition.message};
  }
  const next = updateBookingState(params.booking, "CANCELLED_BY_PARENT");
  next.lifecycle.cancelledAt = new Date(params.authoritativeNow.getTime());
  next.cancellation.cancelledAt = new Date(params.authoritativeNow.getTime());
  next.cancellation.cancelledBy = "parent";
  next.cancellation.cancellationType = "parent_requested";
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "parent";
  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "cancelled",
        actor: "parent",
        at: params.authoritativeNow,
      }),
    ],
    notifications: [
      buildCancelledByParentNotification({
        bookingId: params.bookingId,
        providerId: params.booking.providerId,
        bookingType: next.bookingType,
        state: next.state,
      }),
    ],
    providerStats: null,
    parentStats: null,
  };
}

export function expirePendingProviderBookingV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
  existingProviderStats?: ProviderStatsV3 | null;
}): RequestLifecycleCommandResult {
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: "EXPIRED",
    actor: "system",
    now: params.authoritativeNow,
    acceptDeadlineAt: params.booking.acceptDeadlineAt,
  });
  if (!transition.ok) {
    if (transition.code === "IDEMPOTENT_REPLAY" && params.booking.state === "EXPIRED") {
      return {
        ok: true,
        code: "IDEMPOTENT_REPLAY",
        booking: cloneBooking(params.booking),
        events: [],
        notifications: [],
        providerStats: params.existingProviderStats ?? emptyProviderStatsV3(),
        parentStats: null,
      };
    }
    return {ok: false, code: transition.code, message: transition.message};
  }
  const deadline = params.booking.acceptDeadlineAt ?? params.authoritativeNow;
  const next = updateBookingState(params.booking, "EXPIRED");
  next.lifecycle.respondedAt = new Date(deadline.getTime());
  next.lifecycle.providerResponseType = "expired";
  next.lifecycle.responseSeconds = responseSecondsFromTimer(params.booking, deadline);
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "system";
  const providerStats = applyProviderStatsMutation(
    params.existingProviderStats ?? emptyProviderStatsV3(),
    {
      type: "expired",
      mutationKey: `expired:${params.bookingId}`,
      occurredAt: deadline,
      responseSeconds: next.lifecycle.responseSeconds,
    },
  );
  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "expired",
        actor: "system",
        at: deadline,
      }),
    ],
    notifications: [
      buildRequestExpiredNotification({
        bookingId: params.bookingId,
        parentId: params.booking.parentId,
        bookingType: next.bookingType,
        state: next.state,
      }),
    ],
    providerStats,
    parentStats: null,
  };
}

export function expireAwaitingPaymentBookingV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
  existingProviderStats?: ProviderStatsV3 | null;
  existingParentStats?: ParentStatsV3 | null;
}): RequestLifecycleCommandResult {
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: "PAYMENT_EXPIRED",
    actor: "system",
    now: params.authoritativeNow,
    payDeadlineAt: params.booking.payDeadlineAt,
  });
  if (!transition.ok) {
    if (transition.code === "IDEMPOTENT_REPLAY" && params.booking.state === "PAYMENT_EXPIRED") {
      return {
        ok: true,
        code: "IDEMPOTENT_REPLAY",
        booking: cloneBooking(params.booking),
        events: [],
        notifications: [],
        providerStats: params.existingProviderStats ?? emptyProviderStatsV3(),
        parentStats: params.existingParentStats ?? emptyParentStatsV3(),
      };
    }
    return {ok: false, code: transition.code, message: transition.message};
  }
  if (params.booking.lifecycle.paidAt) {
    return {ok: false, code: "INVALID_CURRENT_STATE", message: "Paid bookings cannot expire as payment abandoned."};
  }
  const next = updateBookingState(params.booking, "PAYMENT_EXPIRED");
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "system";
  const providerStats = applyProviderStatsMutation(
    params.existingProviderStats ?? emptyProviderStatsV3(),
    {
      type: "parent_payment_abandoned",
      mutationKey: `parent_payment_abandoned:${params.bookingId}`,
      occurredAt: params.booking.payDeadlineAt ?? params.authoritativeNow,
    },
  );
  const parentStats = applyParentStatsMutation(
    params.existingParentStats ?? emptyParentStatsV3(),
    {
      type: "payment_abandoned",
      mutationKey: `payment_abandoned:${params.bookingId}`,
      occurredAt: params.booking.payDeadlineAt ?? params.authoritativeNow,
    },
  );
  return {
    ok: true,
    code: "UPDATED",
    booking: next,
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "payment_abandoned",
        actor: "system",
        at: params.booking.payDeadlineAt ?? params.authoritativeNow,
      }),
    ],
    notifications: buildPaymentExpiredNotification({
      bookingId: params.bookingId,
      parentId: params.booking.parentId,
      providerId: params.booking.providerId,
      bookingType: next.bookingType,
      state: next.state,
    }),
    providerStats,
    parentStats,
  };
}
