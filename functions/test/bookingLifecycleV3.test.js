const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCEPT_WINDOW_MINUTES,
  PAY_WINDOW_MINUTES,
  BUFFER_MINUTES,
  RUNWAY_MINUTES,
} = require("../lib/booking/domain/bookingConstants.js");
const {
  createBookingRequestV3,
  acceptBookingRequestV3,
  declineBookingRequestV3,
  cancelBookingRequestByParentV3,
  expirePendingProviderBookingV3,
  expireAwaitingPaymentBookingV3,
  activateQueuedBookingRequestV3,
  markBookingViewedByProviderV3,
} = require("../lib/booking/application/createBookingRequestV3.js");
const {
  computeTimerStartsAt,
  normalizeServiceWorkingHours,
} = require("../lib/booking/application/workingHours.js");
const {
  evaluateBookingTransition,
  transitionTable,
} = require("../lib/booking/application/bookingStateMachine.js");
const {
  validateCanonicalBookingRunway,
} = require("../lib/booking/application/bookingRunway.js");
const {
  emptyParentStatsV3,
  emptyProviderStatsV3,
  applyProviderStatsMutation,
  applyParentStatsMutation,
} = require("../lib/booking/application/bookingStats.js");
const notifications = require("../lib/booking/application/bookingNotificationsV3.js");
const {
  validatePreCheckoutAvailabilityV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");

test("constants remain locked to the 60/60/30/150 model", () => {
  assert.equal(ACCEPT_WINDOW_MINUTES, 60);
  assert.equal(PAY_WINDOW_MINUTES, 60);
  assert.equal(BUFFER_MINUTES, 30);
  assert.equal(RUNWAY_MINUTES, 150);
});

function baseService(overrides = {}) {
  return {
    id: "service-1",
    ownerUserId: "provider-1",
    ownerName: "Pettxo Care",
    ownerUsername: "pettxocare",
    ownerPhotoUrl: "",
    title: "Dog Walking",
    animalType: "Dog",
    category: "Walking",
    serviceType: "provider_location",
    currency: "INR",
    sessionDurationMinutes: 60,
    capacity: 1,
    availableDays: ["monday", "tuesday", "wednesday", "thursday", "friday"],
    startMinutes: 9 * 60,
    endMinutes: 17 * 60,
    timezone: "Asia/Kolkata",
    status: "active",
    isActive: true,
    isDeleted: false,
    isPaused: false,
    isVisibleToMarketplace: true,
    providerVerificationStatus: "approved",
    isPausedByVerification: false,
    stats: {
      ratingAverage: 4.9,
      completedBookingsCount: 12,
    },
    ...overrides,
  };
}

function parent(overrides = {}) {
  return {
    uid: "parent-1",
    fullName: "Nisha Gautam",
    displayName: "Nisha Gautam",
    photoUrl: "",
    rating: 4.7,
    completedBookingCount: 5,
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
    ...overrides,
  };
}

function slotSchedule({serviceId = "service-1", providerId = "provider-1", startAt} = {}) {
  const start = startAt ?? new Date("2026-07-24T06:30:00.000Z");
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  return {
    bookingType: "SLOT",
    slots: [{
      slotId: "slot-1",
      serviceId,
      providerId,
      timezone: "Asia/Kolkata",
      dateKey: "2026-07-24",
      startAt: start,
      endAt: end,
      durationMinutes: 60,
      unitPricePaise: 25000,
    }],
    slotCount: 1,
    scheduledStartAt: start,
    scheduledEndAt: end,
    totalDurationMinutes: 60,
  };
}

function multiSlotSchedule() {
  const start = new Date("2026-07-24T06:30:00.000Z");
  const middle = new Date("2026-07-24T07:30:00.000Z");
  const later = new Date("2026-07-24T08:30:00.000Z");
  const end = new Date("2026-07-24T09:30:00.000Z");
  return {
    bookingType: "SLOT",
    slots: [
      {
        slotId: "slot-1",
        serviceId: "service-1",
        providerId: "provider-1",
        timezone: "Asia/Kolkata",
        dateKey: "2026-07-24",
        startAt: start,
        endAt: middle,
        durationMinutes: 60,
        unitPricePaise: 25000,
      },
      {
        slotId: "slot-2",
        serviceId: "service-1",
        providerId: "provider-1",
        timezone: "Asia/Kolkata",
        dateKey: "2026-07-24",
        startAt: middle,
        endAt: later,
        durationMinutes: 60,
        unitPricePaise: 25000,
      },
      {
        slotId: "slot-3",
        serviceId: "service-1",
        providerId: "provider-1",
        timezone: "Asia/Kolkata",
        dateKey: "2026-07-24",
        startAt: later,
        endAt: end,
        durationMinutes: 60,
        unitPricePaise: 25000,
      },
    ],
    slotCount: 3,
    scheduledStartAt: start,
    scheduledEndAt: end,
    totalDurationMinutes: 180,
  };
}

function rangeSchedule({checkIn} = {}) {
  const checkInDateTime = checkIn ?? new Date("2026-07-25T06:30:00.000Z");
  const checkOutDateTime = new Date(checkInDateTime.getTime() + 2 * 24 * 60 * 60 * 1000);
  return {
    bookingType: "RANGE",
    checkInDateTime,
    checkOutDateTime,
    nights: 2,
    pricePerNightPaise: 180000,
    timezone: "Asia/Kolkata",
    petQuantity: 1,
    maxConcurrentPetsSnapshot: 2,
    minNights: 1,
    maxNights: 14,
  };
}

test("working-hours adapter preserves the real service schema", () => {
  const normalized = normalizeServiceWorkingHours(baseService());
  assert.equal(normalized.ok, true);
  assert.equal(normalized.workingHours.timezone, "Asia/Kolkata");
  assert.deepEqual(normalized.workingHours.days.monday, [{startMinutes: 540, endMinutes: 1020}]);
  assert.equal(normalized.workingHours.sourceSupportsSingleIntervalPerDay, true);
});

test("working-hours timer starts immediately during working hours", () => {
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const requestedAt = new Date("2026-07-22T04:00:00.000Z"); // 09:30 IST
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(result.timerStartsAt.getTime(), requestedAt.getTime());
  assert.equal(result.wasQueuedOutsideWorkingHours, false);
});

test("working-hours timer queues before opening", () => {
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const requestedAt = new Date("2026-07-22T02:30:00.000Z"); // 08:00 IST
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(result.wasQueuedOutsideWorkingHours, true);
  assert.equal(result.timerStartsAt.toISOString(), "2026-07-22T03:30:00.000Z");
});

test("working-hours timer queues after closing to next day", () => {
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const requestedAt = new Date("2026-07-22T12:30:00.000Z"); // 18:00 IST
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(result.timerStartsAt.toISOString(), "2026-07-23T03:30:00.000Z");
  assert.equal(result.nextOpeningDay, "thursday");
});

test("working-hours timer skips closed days and rolls across weekend", () => {
  const normalized = normalizeServiceWorkingHours(baseService({
    availableDays: ["monday"],
  })).workingHours;
  const requestedAt = new Date("2026-07-21T12:30:00.000Z"); // Tuesday after close
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(result.nextOpeningDay, "monday");
});

test("working-hours handles exact opening and closing boundaries", () => {
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const exactOpen = computeTimerStartsAt({
    requestedAt: new Date("2026-07-22T03:30:00.000Z"),
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(exactOpen.wasQueuedOutsideWorkingHours, false);

  const exactClose = computeTimerStartsAt({
    requestedAt: new Date("2026-07-22T11:30:00.000Z"),
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(exactClose.wasQueuedOutsideWorkingHours, true);
});

test("24/7 providers start immediately", () => {
  const normalized = normalizeServiceWorkingHours(baseService({
    availableDays: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
    startMinutes: 0,
    endMinutes: 1440,
  })).workingHours;
  const requestedAt = new Date("2026-07-22T20:00:00.000Z");
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  assert.equal(result.timerStartsAt.getTime(), requestedAt.getTime());
});

test("DST-observing timezone computes next opening correctly", () => {
  const normalized = normalizeServiceWorkingHours(baseService({
    timezone: "America/New_York",
    availableDays: ["monday", "tuesday", "wednesday", "thursday", "friday"],
    startMinutes: 9 * 60,
    endMinutes: 17 * 60,
  })).workingHours;
  const requestedAt = new Date("2026-11-02T12:30:00.000Z"); // 07:30 local after DST fallback weekend
  const result = computeTimerStartsAt({
    requestedAt,
    timezone: "America/New_York",
    workingHours: normalized,
  });
  assert.equal(result.wasQueuedOutsideWorkingHours, true);
  assert.equal(result.timerStartsAt.toISOString(), "2026-11-02T14:00:00.000Z");
});

test("runway validation accepts exact SLOT runway boundary", () => {
  const authoritativeNow = new Date("2026-07-22T03:30:00.000Z");
  const anchor = new Date(authoritativeNow.getTime() + 150 * 60 * 1000);
  const schedule = slotSchedule({startAt: anchor});
  const result = validateCanonicalBookingRunway({
    bookingType: "SLOT",
    schedule,
    authoritativeNow,
    service: baseService(),
    workingHours: normalizeServiceWorkingHours(baseService()).workingHours,
  });
  assert.equal(result.ok, true);
});

test("runway validation rejects SLOT one millisecond too early", () => {
  const authoritativeNow = new Date("2026-07-22T03:30:00.000Z");
  const anchor = new Date(authoritativeNow.getTime() + 150 * 60 * 1000 - 1);
  const schedule = slotSchedule({startAt: anchor});
  const result = validateCanonicalBookingRunway({
    bookingType: "SLOT",
    schedule,
    authoritativeNow,
    service: baseService(),
    workingHours: normalizeServiceWorkingHours(baseService()).workingHours,
  });
  assert.equal(result.ok, false);
  assert.equal(result.issues.some((entry) => entry.code === "RUNWAY_NOT_SATISFIED"), true);
});

test("runway validation accepts exact RANGE boundary from authoritative now", () => {
  const requestedAt = new Date("2026-07-22T12:30:00.000Z");
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const timerStart = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  const anchor = new Date(requestedAt.getTime() + 150 * 60 * 1000);
  const schedule = rangeSchedule({checkIn: anchor});
  const result = validateCanonicalBookingRunway({
    bookingType: "RANGE",
    schedule,
    authoritativeNow: requestedAt,
    service: baseService(),
    workingHours: normalized,
  });
  assert.equal(timerStart.timerStartsAt.toISOString(), "2026-07-23T03:30:00.000Z");
  assert.equal(result.ok, true);
});

test("queued requests still use authoritative now for runway validation", () => {
  const requestedAt = new Date("2026-07-22T12:30:00.000Z");
  const normalized = normalizeServiceWorkingHours(baseService()).workingHours;
  const timerStart = computeTimerStartsAt({
    requestedAt,
    timezone: "Asia/Kolkata",
    workingHours: normalized,
  });
  const anchor = new Date(requestedAt.getTime() + 150 * 60 * 1000);
  const schedule = slotSchedule({startAt: anchor});
  const result = validateCanonicalBookingRunway({
    bookingType: "SLOT",
    schedule,
    authoritativeNow: requestedAt,
    service: baseService(),
    workingHours: normalized,
  });
  assert.equal(timerStart.wasQueuedOutsideWorkingHours, true);
  assert.equal(result.ok, true);
});

test("transition table matches the Block 3 state machine", () => {
  assert.deepEqual(transitionTable().REQUESTED, [
    "PENDING_PROVIDER",
    "ACCEPTED_AWAITING_PAYMENT",
    "DECLINED",
    "CANCELLED_BY_PARENT",
  ]);
  assert.deepEqual(transitionTable().PENDING_PROVIDER, [
    "ACCEPTED_AWAITING_PAYMENT",
    "DECLINED",
    "EXPIRED",
    "CANCELLED_BY_PARENT",
  ]);
  assert.deepEqual(transitionTable().ACCEPTED_AWAITING_PAYMENT, ["PAYMENT_EXPIRED"]);
});

test("state machine allows and rejects expected transitions", () => {
  const now = new Date("2026-07-22T04:00:00.000Z");
  assert.equal(evaluateBookingTransition({
    fromState: "REQUESTED",
    toState: "PENDING_PROVIDER",
    actor: "system",
    now,
  }).ok, true);
  assert.equal(evaluateBookingTransition({
    fromState: "PENDING_PROVIDER",
    toState: "ACCEPTED_AWAITING_PAYMENT",
    actor: "provider",
    now,
    acceptDeadlineAt: new Date("2026-07-22T04:30:00.000Z"),
  }).ok, true);
  assert.equal(evaluateBookingTransition({
    fromState: "PENDING_PROVIDER",
    toState: "DECLINED",
    actor: "parent",
    now,
    acceptDeadlineAt: new Date("2026-07-22T04:30:00.000Z"),
  }).code, "ACTOR_NOT_AUTHORIZED");
  assert.equal(evaluateBookingTransition({
    fromState: "DECLINED",
    toState: "PENDING_PROVIDER",
    actor: "system",
    now,
  }).code, "TERMINAL_STATE");
});

test("createBookingRequestV3 creates canonical SLOT request inside working hours", () => {
  const result = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-1",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-1",
  });
  assert.equal(result.ok, true);
  assert.equal(result.booking.state, "PENDING_PROVIDER");
  assert.equal(result.booking.financials, null);
  assert.equal(result.booking.participants.parent.phoneNumber, undefined);
  assert.equal(result.notifications[0].type, "provider_action_required");
});

test("createBookingRequestV3 creates canonical multi-slot request", () => {
  const result = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-2",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: multiSlotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-2",
  });
  assert.equal(result.ok, true);
  assert.equal(result.booking.schedule.slotCount, 3);
});

test("createBookingRequestV3 creates canonical RANGE request", () => {
  const service = baseService({
    title: "Pet Boarding",
    category: "Boarding",
  });
  const result = createBookingRequestV3({
    parent: parent(),
    service,
    input: {
      requestAttemptId: "attempt-3",
      serviceId: "service-1",
      bookingType: "RANGE",
      schedule: rangeSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-3",
  });
  assert.equal(result.ok, true);
  assert.equal(result.booking.bookingType, "RANGE");
});

test("createBookingRequestV3 rejects inactive or paused services", () => {
  const inactive = createBookingRequestV3({
    parent: parent(),
    service: baseService({status: "paused"}),
    input: {
      requestAttemptId: "attempt-inactive",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-x",
  });
  assert.equal(inactive.ok, false);

  const paused = createBookingRequestV3({
    parent: parent(),
    service: baseService({isPausedByVerification: true}),
    input: {
      requestAttemptId: "attempt-paused",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-y",
  });
  assert.equal(paused.ok, false);
});

test("createBookingRequestV3 rejects mixed provider IDs and ignores parent private fields", () => {
  const result = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-mismatch",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule({providerId: "provider-2"}),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-z",
  });
  assert.equal(result.ok, false);
});

test("createBookingRequestV3 enforces idempotency and rejects same key with different payload", () => {
  const first = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-repeat",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-repeat",
  });
  assert.equal(first.ok, true);

  const replay = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-repeat",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:01:00.000Z"),
    generatedBookingId: "booking-repeat-2",
    existingAttempt: first.attemptRecord,
  });
  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
  assert.equal(replay.bookingId, "booking-repeat");

  const mismatch = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-repeat",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: multiSlotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:02:00.000Z"),
    generatedBookingId: "booking-repeat-3",
    existingAttempt: first.attemptRecord,
  });
  assert.equal(mismatch.ok, false);
});

test("queued requests can be activated once and only once", () => {
  const created = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-queued",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule({startAt: new Date("2026-07-23T06:30:00.000Z")}),
    },
    authoritativeNow: new Date("2026-07-22T12:30:00.000Z"), // after close
    generatedBookingId: "booking-queued",
  });
  assert.equal(created.ok, true);
  assert.equal(created.booking.state, "REQUESTED");

  const activated = activateQueuedBookingRequestV3({
    booking: created.booking,
    authoritativeNow: new Date("2026-07-23T03:31:00.000Z"),
    existingProviderStats: emptyProviderStatsV3(),
  });
  assert.equal(activated.ok, true);
  assert.equal(activated.booking.state, "PENDING_PROVIDER");

  const replay = activateQueuedBookingRequestV3({
    booking: activated.booking,
    authoritativeNow: new Date("2026-07-23T03:35:00.000Z"),
    existingProviderStats: activated.providerStats,
  });
  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
});

test("provider view writes viewedByProviderAt only once", () => {
  const created = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-view",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-view",
  }).booking;

  const viewed = markBookingViewedByProviderV3({
    booking: created,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:05:00.000Z"),
  });
  assert.equal(viewed.ok, true);
  assert.ok(viewed.booking.lifecycle.viewedByProviderAt instanceof Date);

  const replay = markBookingViewedByProviderV3({
    booking: viewed.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:06:00.000Z"),
  });
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
});

test("provider accept and decline commands are deadline-checked and consume no capacity", () => {
  const created = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-accept",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-accept",
  });
  const accepted = acceptBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:10:00.000Z"),
    existingProviderStats: created.providerStats,
  });
  assert.equal(accepted.ok, true);
  assert.equal(accepted.booking.state, "ACCEPTED_AWAITING_PAYMENT");
  assert.equal(accepted.booking.lifecycle.payDeadlineAt.toISOString(), "2026-07-22T05:10:00.000Z");
  assert.equal(accepted.booking.service.capacitySnapshot, 1);
  assert.equal(accepted.notifications[0].body.includes("slot reserved"), false);
  assert.equal(accepted.notifications[0].body.includes("booking confirmed"), false);

  const duplicateAccept = acceptBookingRequestV3({
    booking: accepted.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:11:00.000Z"),
    existingProviderStats: accepted.providerStats,
  });
  assert.equal(duplicateAccept.ok, true);
  assert.equal(duplicateAccept.code, "IDEMPOTENT_REPLAY");

  const tooLate = acceptBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T05:30:01.000Z"),
    existingProviderStats: created.providerStats,
  });
  assert.equal(tooLate.ok, false);

  const declined = declineBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:12:00.000Z"),
    existingProviderStats: created.providerStats,
  });
  assert.equal(declined.ok, true);
  assert.equal(declined.booking.state, "DECLINED");
});

test("queued outside-working-hours requests remain actionable before the official timer starts", () => {
  const created = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-queued-early-action",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule({startAt: new Date("2026-07-27T06:30:00.000Z")}),
    },
    authoritativeNow: new Date("2026-07-26T12:30:00.000Z"),
    generatedBookingId: "booking-queued-early-action",
  });

  assert.equal(created.ok, true);
  assert.equal(created.booking.state, "REQUESTED");
  assert.equal(created.booking.lifecycle.wasQueuedOutsideWorkingHours, true);
  assert.equal(
    created.booking.lifecycle.timerStartsAt.toISOString(),
    "2026-07-27T03:30:00.000Z",
  );
  assert.equal(
    created.booking.lifecycle.acceptDeadlineAt.toISOString(),
    "2026-07-27T04:30:00.000Z",
  );

  const accepted = acceptBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-26T13:00:00.000Z"),
    existingProviderStats: created.providerStats,
  });

  assert.equal(accepted.ok, true);
  assert.equal(accepted.booking.state, "ACCEPTED_AWAITING_PAYMENT");
  assert.equal(
    accepted.booking.lifecycle.respondedAt.toISOString(),
    "2026-07-26T13:00:00.000Z",
  );
  assert.equal(
    accepted.booking.lifecycle.payDeadlineAt.toISOString(),
    "2026-07-27T04:30:00.000Z",
  );
  assert.equal(accepted.notifications.length, 1);
  assert.equal(accepted.notifications[0].type, "payment_required");

  const payableEarly = validatePreCheckoutAvailabilityV3({
    booking: accepted.booking,
    service: {
      serviceId: "service-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      timezone: "Asia/Kolkata",
      slotCapacity: 1,
      rangeCapacity: null,
      isActive: true,
      isDeleted: false,
      isPaused: false,
    },
    authoritativeNow: new Date("2026-07-26T13:05:00.000Z"),
  });
  assert.equal(payableEarly.ok, true);

  const declined = declineBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-26T13:10:00.000Z"),
    existingProviderStats: created.providerStats,
  });

  assert.equal(declined.ok, true);
  assert.equal(declined.booking.state, "DECLINED");
  assert.equal(declined.notifications.length, 1);
  assert.equal(declined.notifications[0].type, "request_declined");
});

test("pre-payment parent cancellation is only allowed from REQUESTED and PENDING_PROVIDER", () => {
  const pending = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-cancel",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-cancel",
  }).booking;
  const cancelled = cancelBookingRequestByParentV3({
    booking: pending,
    parentUid: "parent-1",
    authoritativeNow: new Date("2026-07-22T04:08:00.000Z"),
  });
  assert.equal(cancelled.ok, true);
  assert.equal(cancelled.booking.state, "CANCELLED_BY_PARENT");

  const accepted = acceptBookingRequestV3({
    booking: pending,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:10:00.000Z"),
    existingProviderStats: emptyProviderStatsV3(),
  }).booking;
  const rejected = cancelBookingRequestByParentV3({
    booking: accepted,
    parentUid: "parent-1",
    authoritativeNow: new Date("2026-07-22T04:12:00.000Z"),
  });
  assert.equal(rejected.ok, false);
});

test("expiry processors use business deadlines and stay idempotent", () => {
  const created = createBookingRequestV3({
    parent: parent(),
    service: baseService(),
    input: {
      requestAttemptId: "attempt-expire",
      serviceId: "service-1",
      bookingType: "SLOT",
      schedule: slotSchedule(),
    },
    authoritativeNow: new Date("2026-07-22T04:00:00.000Z"),
    generatedBookingId: "booking-expire",
  });

  const expired = expirePendingProviderBookingV3({
    booking: created.booking,
    authoritativeNow: new Date("2026-07-22T05:45:00.000Z"),
    existingProviderStats: created.providerStats,
  });
  assert.equal(expired.ok, true);
  assert.equal(expired.booking.state, "EXPIRED");
  assert.equal(expired.booking.lifecycle.responseSeconds, 3600);

  const replay = expirePendingProviderBookingV3({
    booking: expired.booking,
    authoritativeNow: new Date("2026-07-22T06:00:00.000Z"),
    existingProviderStats: expired.providerStats,
  });
  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");

  const accepted = acceptBookingRequestV3({
    booking: created.booking,
    providerUid: "provider-1",
    authoritativeNow: new Date("2026-07-22T04:10:00.000Z"),
    existingProviderStats: created.providerStats,
  });
  const paymentExpired = expireAwaitingPaymentBookingV3({
    booking: accepted.booking,
    authoritativeNow: new Date("2026-07-22T06:30:00.000Z"),
    existingProviderStats: accepted.providerStats,
    existingParentStats: emptyParentStatsV3(),
  });
  assert.equal(paymentExpired.ok, true);
  assert.equal(paymentExpired.booking.state, "PAYMENT_EXPIRED");
  assert.equal(paymentExpired.providerStats.parentPaymentAbandoned, 1);
  assert.equal(paymentExpired.parentStats.paymentsAbandoned, 1);
});

test("stats helpers remain idempotent and do not punish provider for payment abandonment", () => {
  const mutationKey = "accepted:booking-1";
  const accepted = applyProviderStatsMutation(emptyProviderStatsV3(), {
    type: "accepted",
    mutationKey,
    occurredAt: new Date("2026-07-22T04:10:00.000Z"),
    responseSeconds: 600,
  });
  const replay = applyProviderStatsMutation(accepted, {
    type: "accepted",
    mutationKey,
    occurredAt: new Date("2026-07-22T04:12:00.000Z"),
    responseSeconds: 610,
  });
  assert.equal(replay.requestsAccepted, 1);

  const parentStats = applyParentStatsMutation(emptyParentStatsV3(), {
    type: "payment_abandoned",
    mutationKey: "payment_abandoned:booking-1",
    occurredAt: new Date("2026-07-22T05:10:00.000Z"),
  });
  assert.equal(parentStats.paymentsAbandoned, 1);
});

test("notification payloads remain request-safe", () => {
  const plans = [
    notifications.buildProviderActionRequiredNotification({
      bookingId: "booking-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "PENDING_PROVIDER",
    }),
    notifications.buildPaymentRequiredNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      bookingType: "SLOT",
      state: "ACCEPTED_AWAITING_PAYMENT",
    }),
    ...notifications.buildPaymentOrderReadyNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      bookingType: "SLOT",
      state: "ACCEPTED_AWAITING_PAYMENT",
    }),
    ...notifications.buildPaymentCapturedProcessingNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      bookingType: "SLOT",
      state: "CAPTURE_REPORTED",
    }),
    ...notifications.buildBookingConfirmedNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "CONFIRMED",
    }),
    ...notifications.buildPaymentRefundRequiredNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "PAYMENT_EXPIRED",
    }),
    ...notifications.buildPaymentFailedNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "PAYMENT_EXPIRED",
    }),
    ...notifications.buildZeroPayableConfirmationNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "CONFIRMED",
    }),
    notifications.buildDeclinedNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      bookingType: "SLOT",
      state: "DECLINED",
    }),
    notifications.buildRequestExpiredNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      bookingType: "SLOT",
      state: "EXPIRED",
    }),
    notifications.buildCancelledByParentNotification({
      bookingId: "booking-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "CANCELLED_BY_PARENT",
    }),
    ...notifications.buildPaymentExpiredNotification({
      bookingId: "booking-1",
      parentId: "parent-1",
      providerId: "provider-1",
      bookingType: "SLOT",
      state: "PAYMENT_EXPIRED",
    }),
  ];

  for (const plan of plans) {
    const serialized = JSON.stringify(plan);
    assert.equal(serialized.includes("+91"), false);
    assert.equal(serialized.includes("address"), false);
    assert.equal(serialized.includes("latitude"), false);
    assert.equal(serialized.includes("longitude"), false);
    assert.equal(serialized.includes("otp"), false);
    assert.equal(serialized.includes("phone"), false);
    assert.equal(serialized.includes("serviceAddress"), false);
    assert.equal(serialized.includes("razorpay_signature"), false);
    assert.equal(serialized.includes("key_secret"), false);
  }
});

test("payment-ready notifications include canonical payment identifiers for navigation", () => {
  const [plan] = notifications.buildPaymentOrderReadyNotification({
    bookingId: "booking-1",
    parentId: "parent-1",
    bookingType: "SLOT",
    state: "ACCEPTED_AWAITING_PAYMENT",
    paymentAttemptId: "attempt-123",
  });

  assert.equal(plan.recipientUserId, "parent-1");
  assert.equal(plan.data.bookingId, "booking-1");
  assert.equal(plan.data.navigationIntent, "payment");
  assert.equal(plan.data.recipientRole, "customer");
  assert.equal(plan.data.paymentAttemptId, "attempt-123");
  assert.equal(plan.data.bookingFlowVersion, "3.2");
});
