// Phase 3B-4c (D1): a captured payment that would confirm a booking for a
// blocked pair is recorded and held for Super Admin review: never confirmed,
// never refunded automatically, and the Razorpay webhook is acknowledged.
//
// Most tests use an isolated demo project (the reconciler scans the whole
// paymentAttempts collection group). The callable test uses the default
// emulator project, because verifyBookingPaymentV3 uses lib/shared/firebase.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-payment-hold",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHmac, randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const enabled = firebaseEmulator.enabled;

const HOLD_BODY = "We received your payment. It's being reviewed and our team will contact you.";
const KEY_ID = "rzp_test_hold";
const KEY_SECRET = "test-key-secret";
const WEBHOOK_SECRET = "test-webhook-secret";

let app;
let firestore;
let sharedDb;
let sharedAuth;
let payments;
let webhook;
let envelope;
let fixtures;
let chatIdentity;
let verifyBookingPaymentV3;
const fetchCalls = [];
let originalFetch;

function withoutUndefined(value) {
  if (Array.isArray(value)) return value.map(withoutUndefined);
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .map(([key, entry]) => [key, withoutUndefined(entry)]));
  }
  return value;
}

function epochSeconds(date) {
  return Math.floor(date.getTime() / 1000);
}

// Razorpay API stand-in: payments are "captured"; refunds are recorded.
function installFetchStub() {
  originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init = {}) => {
    const target = String(url);
    fetchCalls.push({url: target, method: init.method ?? "GET"});
    const paymentMatch = target.match(/\/v1\/payments\/([^/?]+)$/);
    if (paymentMatch && (init.method ?? "GET") === "GET") {
      const known = knownPayments.get(decodeURIComponent(paymentMatch[1]));
      return new Response(JSON.stringify(known ?? {error: {description: "unknown"}}), {
        status: known ? 200 : 404,
        headers: {"content-type": "application/json"},
      });
    }
    if (/\/v1\/payments\/[^/]+\/refund$/.test(target)) {
      return new Response(JSON.stringify({id: `rfnd_${randomUUID().slice(0, 8)}`, status: "processed"}), {
        status: 200,
        headers: {"content-type": "application/json"},
      });
    }
    return new Response(JSON.stringify({error: {description: "not stubbed"}}), {
      status: 500,
      headers: {"content-type": "application/json"},
    });
  };
}

const knownPayments = new Map();

function registerPayment(ctx) {
  knownPayments.set(ctx.ids.razorpayPaymentId, {
    id: ctx.ids.razorpayPaymentId,
    order_id: ctx.ids.razorpayOrderId,
    status: "captured",
    amount: ctx.amountPaise,
    currency: "INR",
    created_at: epochSeconds(ctx.capturedAt),
    captured_at: epochSeconds(ctx.capturedAt),
  });
}

/**
 * Seeds a payable ACCEPTED_AWAITING_PAYMENT booking for a fresh pair.
 * options.qr: QR attempt. options.state: booking state override.
 * options.payDeadlineAt / options.now: time window.
 */
async function seedPayable(db, options = {}) {
  const sfx = randomUUID().slice(0, 8);
  const parentId = `hold-parent-${sfx}`;
  const providerId = `hold-provider-${sfx}`;
  const serviceId = `hold-service-${sfx}`;
  const ids = {
    bookingId: `hold-booking-${sfx}`,
    paymentAttemptId: `hold-attempt-${sfx}`,
    razorpayOrderId: options.qr ? "" : `order_hold_${sfx}`,
    razorpayPaymentId: `pay_hold_${sfx}`,
    webhookEventId: `payment.captured:pay_hold_${sfx}`,
    refundInstructionId: `hold-booking-${sfx}`,
  };
  const qrCodeId = `qr_hold_${sfx}`;
  const base = fixtures.buildCanonicalPaymentRaceFixture({ids});
  const booking = base.booking;
  booking.parentId = parentId;
  booking.customerId = parentId;
  booking.providerId = providerId;
  booking.serviceOwnerId = providerId;
  booking.participantIds = [parentId, providerId];
  booking.participants.parent.parentId = parentId;
  booking.participants.provider.providerId = providerId;
  booking.serviceId = serviceId;
  booking.service.serviceId = serviceId;
  booking.service.providerId = providerId;
  for (const slot of booking.schedule.slots) {
    slot.serviceId = serviceId;
    slot.providerId = providerId;
  }
  const now = options.now ?? base.authoritativeNow;
  if (options.payDeadlineAt) {
    booking.lifecycle.payDeadlineAt = options.payDeadlineAt;
    booking.payDeadlineAt = options.payDeadlineAt;
  }
  if (options.state) {
    booking.state = options.state;
    booking.stateQueryValue = options.state;
  }
  const attempt = {
    ...base.paymentAttempt,
    parentId,
    providerId,
    orderExpiresAt: booking.lifecycle.payDeadlineAt,
    ...(options.qr ? {
      paymentMethod: "qr",
      razorpayOrderId: "",
      razorpayQrCodeId: qrCodeId,
      qrState: "ACTIVE",
    } : {}),
  };
  await Promise.all([
    db.collection("users").doc(parentId).set({uid: parentId, displayName: "Hold Parent", accountStatus: "active"}),
    db.collection("users").doc(providerId).set({uid: providerId, displayName: "Hold Provider", accountStatus: "active"}),
    db.collection("bookings").doc(ids.bookingId).set(withoutUndefined({...booking, bookingId: ids.bookingId})),
    db.collection("bookings").doc(ids.bookingId).collection("paymentAttempts")
      .doc(ids.paymentAttemptId).set(withoutUndefined({...attempt, bookingId: ids.bookingId})),
    db.collection("services").doc(serviceId).set(withoutUndefined({
      ...fixtures.liveService(),
      serviceId,
      ownerUserId: providerId,
    })),
    options.qr ?
      db.collection("canonicalQrPaymentMappings").doc(qrCodeId).set({
        bookingId: ids.bookingId,
        paymentAttemptId: ids.paymentAttemptId,
        status: "ACTIVE",
        schemaVersion: 1,
      }) :
      db.collection("canonicalPaymentOrderMappings").doc(ids.razorpayOrderId).set({
        bookingId: ids.bookingId,
        paymentAttemptId: ids.paymentAttemptId,
        schemaVersion: 1,
      }),
  ]);
  const ctx = {
    ids,
    qrCodeId,
    parentId,
    providerId,
    serviceId,
    now,
    capturedAt: new Date(now.getTime() - 5000),
    amountPaise: attempt.amountPaise,
    booking: {...booking, bookingId: ids.bookingId},
    attempt: {...attempt, bookingId: ids.bookingId},
  };
  registerPayment(ctx);
  return ctx;
}

async function blockPair(db, ctx, direction = "provider->parent") {
  const [owner, blocked] = direction === "provider->parent" ?
    [ctx.providerId, ctx.parentId] : [ctx.parentId, ctx.providerId];
  await db.collection("userBlocks").doc(`${owner}_${blocked}`).set({
    ownerUserId: owner, blockedUserId: blocked, createdAt: new Date(),
  });
}

async function setGate(db, state) {
  await Promise.all([
    db.doc("_rollouts/userBlockingV1").delete(),
    db.doc("_migrations/userRelationshipGuardV1").delete(),
    db.doc("userBlockingActivationAudit/hold-activation").delete(),
  ]);
  if (state !== "enabled") return;
  await Promise.all([
    db.doc("_migrations/userRelationshipGuardV1").set({
      migrationVersion: 1, runId: "hold-run", status: "verified",
      sourceFingerprint: "hold-fp", reconciliationPassed: true, anomalyCount: 0, mismatchCount: 0,
    }),
    db.doc("userBlockingActivationAudit/hold-activation").set({
      event: "ACTIVATE", enabled: true, migrationRunId: "hold-run",
      sourceFingerprint: "hold-fp", rolloutVersion: 1,
    }),
    db.doc("_rollouts/userBlockingV1").set({
      enabled: true, status: "active", migrationRunId: "hold-run",
      sourceFingerprint: "hold-fp", activationAuditId: "hold-activation", rolloutVersion: 1,
    }),
  ]);
}

function facts(ctx, overrides = {}) {
  return {
    bookingId: ctx.ids.bookingId,
    paymentAttemptId: ctx.ids.paymentAttemptId,
    razorpayOrderId: ctx.ids.razorpayOrderId,
    razorpayPaymentId: ctx.ids.razorpayPaymentId,
    capturedAmountPaise: ctx.amountPaise,
    currency: "INR",
    capturedAt: ctx.capturedAt,
    verificationSource: "webhook",
    sourceEventId: `evt-${ctx.ids.razorpayPaymentId}`,
    ...overrides,
  };
}

async function assertHeld(db, ctx, {sourceEventIds, bookingState = "ACCEPTED_AWAITING_PAYMENT"} = {}) {
  const bookingRef = db.collection("bookings").doc(ctx.ids.bookingId);
  const booking = (await bookingRef.get()).data();
  assert.equal(booking.state, bookingState, "booking keeps its state");
  assert.notEqual(booking.state, "CONFIRMED");
  assert.equal(booking.lifecycle.paidAt ?? null, null, "booking is not marked paid");
  assert.equal(booking.chatId, undefined, "no chat linked");

  const attempt = (await bookingRef.collection("paymentAttempts").doc(ctx.ids.paymentAttemptId).get()).data();
  assert.equal(attempt.state, "CAPTURED_REQUIRES_RECONCILIATION");
  assert.ok(attempt.terminalFailureAt, "attempt is out of automatic reconciliation");
  assert.equal(attempt.lastReconciliationCode, "BLOCKED_RELATIONSHIP_HOLD");
  assert.equal(attempt.adminHoldId, ctx.ids.razorpayPaymentId);
  assert.equal(attempt.razorpayPaymentId, ctx.ids.razorpayPaymentId);
  assert.equal(attempt.capturedAmountPaise, ctx.amountPaise);

  const hold = (await db.collection("blockedRelationshipPaymentHolds").doc(ctx.ids.razorpayPaymentId).get()).data();
  assert.ok(hold, "hold document exists");
  assert.equal(hold.status, "OPEN");
  assert.equal(hold.requiredRole, "superAdmin");
  assert.equal(hold.bookingId, ctx.ids.bookingId);
  assert.equal(hold.paymentAttemptId, ctx.ids.paymentAttemptId);
  assert.equal(hold.amountPaise, ctx.amountPaise);
  assert.equal(hold.parentId, ctx.parentId);
  assert.equal(hold.providerId, ctx.providerId);
  assert.equal(hold.reasonCode, "USER_RELATIONSHIP_BLOCKED");
  assert.equal(hold.resolution, null);
  if (sourceEventIds) assert.deepEqual([...hold.sourceEventIds].sort(), [...sourceEventIds].sort());

  const event = (await bookingRef.collection("events")
    .doc(`payment_held_blocked_relationship_${ctx.ids.razorpayPaymentId}`).get()).data();
  assert.equal(event.event, "payment_held_blocked_relationship");
  assert.equal(event.meta.razorpayPaymentId, ctx.ids.razorpayPaymentId);

  const notices = await db.collection("notifications").where("userId", "==", ctx.parentId).get();
  const types = notices.docs.map((doc) => doc.data().type);
  assert.deepEqual(types, ["payment_held_for_review"], "one neutral notice, no refund notice");
  const notice = notices.docs[0].data();
  assert.equal(notice.body, HOLD_BODY);
  assert.deepEqual([...notice.channels].sort(), ["in_app", "push"]);
  const providerNotices = await db.collection("notifications").where("userId", "==", ctx.providerId).get();
  assert.equal(providerNotices.size, 0);

  // Nothing from the confirmation path and no refund.
  for (const collection of ["payments", "bookingFinancials", "invoices", "providerEarnings", "payoutReadiness", "bookingChats", "bookingPrivate"]) {
    assert.equal((await db.collection(collection).doc(ctx.ids.bookingId).get()).exists, false, collection);
  }
  const refunds = await db.collection("refunds").where("bookingId", "==", ctx.ids.bookingId).get();
  assert.equal(refunds.size, 0, "no refund instruction");
  const chatId = chatIdentity.canonicalChatIdForUidPair(
    ...chatIdentity.canonicalParticipantIds(ctx.parentId, ctx.providerId),
  );
  assert.equal((await db.collection("chats").doc(chatId).get()).exists, false, "no chat");
  assert.equal(fetchCalls.some((call) => call.url.includes(`/payments/${ctx.ids.razorpayPaymentId}/refund`)), false,
    "no refund call to Razorpay");
}

function signedEnvelope(payloadObject) {
  const rawBody = Buffer.from(JSON.stringify(payloadObject));
  return {
    rawBody,
    payload: payloadObject,
    signature: createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex"),
  };
}

function capturedPayload(ctx) {
  return {
    event: "payment.captured",
    payload: {
      payment: {
        entity: {
          id: ctx.ids.razorpayPaymentId,
          order_id: ctx.ids.razorpayOrderId,
          amount: ctx.amountPaise,
          currency: "INR",
          status: "captured",
        },
      },
    },
  };
}

function routeWithStubs(ctx) {
  return (params) => webhook.routeCanonicalWebhookEventV3({
    ...params,
    authoritativeNow: ctx.now,
  });
}

test.before(async () => {
  if (!enabled) return;
  installFetchStub();
  app = initializeApp({projectId: "demo-payment-hold"}, `payment-hold-${randomUUID()}`);
  firestore = getFirestore(app);
  firestore.settings({ignoreUndefinedProperties: true});
  ({db: sharedDb, auth: sharedAuth} = require("../lib/shared/firebase.js"));
  sharedAuth.getUser = async (uid) => ({uid, displayName: uid, email: "", phoneNumber: ""});
  payments = require("../lib/booking/application/paymentOrchestrationV3.js");
  webhook = require("../lib/booking/application/canonicalPaymentWebhookV3.js");
  envelope = require("../lib/booking/application/paymentWebhookEventsV3.js");
  fixtures = require("./helpers/canonicalPaymentRaceFixture.js");
  chatIdentity = require("../lib/chat/chatIdentity.js");
  process.env.RAZORPAY_KEY_ID = KEY_ID;
  process.env.RAZORPAY_KEY_SECRET = KEY_SECRET;
  ({verifyBookingPaymentV3} = require("../lib/booking/bookingV3FlowFunctions.js"));
});

test.after(async () => {
  if (!enabled) return;
  globalThis.fetch = originalFetch;
  await firestore.terminate();
  await deleteApp(app);
});

for (const gate of ["absent", "enabled"]) {
  for (const direction of ["provider->parent", "parent->provider"]) {
    test(`gate ${gate}, block ${direction}: a would-confirm capture is held, not confirmed or refunded`, {
      skip: !enabled,
    }, async () => {
      await setGate(firestore, gate);
      const ctx = await seedPayable(firestore);
      await blockPair(firestore, ctx, direction);
      const result = await payments.finalizeCapturedCanonicalPaymentV3({
        firestore,
        facts: facts(ctx),
        keyId: KEY_ID,
        keySecret: KEY_SECRET,
        authoritativeNow: ctx.now,
      });
      assert.equal(result.ok, false);
      assert.equal(result.code, "HELD_BLOCKED_RELATIONSHIP");
      assert.deepEqual(result.notifications, []);
      assert.equal(result.refundInstruction, null);
      await assertHeld(firestore, ctx, {sourceEventIds: [`evt-${ctx.ids.razorpayPaymentId}`]});
    });
  }
}

test("webhook end to end: 200, PROCESSED, replay and a second event for the same payment", {
  skip: !enabled,
}, async () => {
  await setGate(firestore, "absent");
  const ctx = await seedPayable(firestore);
  await blockPair(firestore, ctx);
  const body = signedEnvelope(capturedPayload(ctx));
  const call = () => envelope.processRazorpayWebhookEnvelopeV3({
    firestore,
    signature: body.signature,
    rawBody: body.rawBody,
    payload: body.payload,
    webhookSecret: WEBHOOK_SECRET,
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: ctx.now,
    routeCanonicalWebhook: routeWithStubs(ctx),
  });

  const first = await call();
  assert.equal(first.statusCode, 200);
  assert.equal(first.routeType, "canonical");
  const eventDoc = (await firestore.collection("paymentWebhookEvents").doc(first.eventKey).get()).data();
  assert.equal(eventDoc.processingState, "PROCESSED");
  assert.equal(eventDoc.outcome, "HELD_BLOCKED_RELATIONSHIP");
  assert.equal(eventDoc.retryable, false);
  assert.equal(eventDoc.failureCode, "USER_RELATIONSHIP_BLOCKED");
  await assertHeld(firestore, ctx, {sourceEventIds: [first.eventKey]});

  // Same signed delivery again: acknowledged without any new work.
  const replay = await call();
  assert.equal(replay.statusCode, 200);
  assert.equal(replay.routeType, "ignored");
  await assertHeld(firestore, ctx, {sourceEventIds: [first.eventKey]});

  // A different event for the same payment lands on the same hold.
  const second = await webhook.routeCanonicalWebhookEventV3({
    firestore,
    eventId: "manual-second-event",
    eventName: "payment.captured",
    paymentEntity: capturedPayload(ctx).payload.payment.entity,
    refundEntity: {},
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: ctx.now,
  });
  assert.equal(second.outcome, "HELD_BLOCKED_RELATIONSHIP");
  assert.equal(second.retryable, false);
  await assertHeld(firestore, ctx, {sourceEventIds: [first.eventKey, "manual-second-event"]});
  const holds = await firestore.collection("blockedRelationshipPaymentHolds")
    .where("bookingId", "==", ctx.ids.bookingId).get();
  assert.equal(holds.size, 1);
});

test("webhook returns an error (500 path) when the hold cannot be recorded", {skip: !enabled}, async () => {
  const ctx = await seedPayable(firestore);
  await blockPair(firestore, ctx);
  const body = signedEnvelope(capturedPayload(ctx));
  await assert.rejects(envelope.processRazorpayWebhookEnvelopeV3({
    firestore,
    signature: body.signature,
    rawBody: body.rawBody,
    payload: body.payload,
    webhookSecret: WEBHOOK_SECRET,
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: ctx.now,
    routeCanonicalWebhook: (params) => webhook.routeCanonicalWebhookEventV3({
      ...params,
      authoritativeNow: ctx.now,
      deps: {
        finalizeCapturedPayment: async () => {
          throw new Error("simulated hold write failure");
        },
      },
    }),
  }), /simulated hold write failure/);
  const events = await firestore.collection("paymentWebhookEvents")
    .where("processingState", "==", "RETRYABLE_FAILURE").get();
  assert.ok(events.docs.some((doc) => doc.data().failureCode.includes("simulated hold write failure")));
  assert.equal((await firestore.collection("blockedRelationshipPaymentHolds")
    .doc(ctx.ids.razorpayPaymentId).get()).exists, false);
});

test("QR credited on a blocked pair: mapping HELD and the same hold", {skip: !enabled}, async () => {
  const ctx = await seedPayable(firestore, {qr: true});
  await blockPair(firestore, ctx);
  const result = await webhook.routeCanonicalWebhookEventV3({
    firestore,
    eventId: `qr_code.credited:${ctx.qrCodeId}`,
    eventName: "qr_code.credited",
    paymentEntity: {
      id: ctx.ids.razorpayPaymentId,
      amount: ctx.amountPaise,
      currency: "INR",
      status: "captured",
    },
    refundEntity: {},
    qrCodeEntity: {id: ctx.qrCodeId},
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: ctx.now,
  });
  assert.equal(result.outcome, "HELD_BLOCKED_RELATIONSHIP");
  assert.equal(result.retryable, false);
  assert.equal((await firestore.collection("canonicalQrPaymentMappings").doc(ctx.qrCodeId).get())
    .data().status, "HELD");
  await assertHeld(firestore, ctx, {sourceEventIds: [`qr_code.credited:${ctx.qrCodeId}`]});
});

test("the reconciler skips a held attempt", {skip: !enabled}, async () => {
  const ctx = await seedPayable(firestore);
  await blockPair(firestore, ctx);
  await payments.finalizeCapturedCanonicalPaymentV3({
    firestore, facts: facts(ctx), keyId: KEY_ID, keySecret: KEY_SECRET, authoritativeNow: ctx.now,
  });
  const touched = [];
  const record = (name) => async (params) => {
    touched.push({name, paymentAttemptId: params.paymentAttemptId ?? params.facts?.paymentAttemptId});
    throw new Error(`${name} must not run for a held attempt`);
  };
  await payments.reconcilePaymentAttemptsV3({
    firestore,
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: new Date(ctx.now.getTime() + 24 * 60 * 60 * 1000),
    limit: 500,
    deps: {
      verifyCapturedPayment: record("verifyCapturedPayment"),
      fetchPayment: record("fetchPayment"),
      finalizeCapturedPayment: record("finalizeCapturedPayment"),
      submitRefundInstruction: async (params) => {
        touched.push({name: "submitRefundInstruction", paymentAttemptId: params.paymentAttemptId});
        return "SKIPPED";
      },
      persistNotifications: async () => undefined,
    },
  }).catch(() => undefined);
  assert.equal(touched.some((entry) => entry.paymentAttemptId === ctx.ids.paymentAttemptId), false);
  await assertHeld(firestore, ctx);
});

test("race: a block that commits after the result is computed still produces a hold", {
  skip: !enabled,
}, async () => {
  const ctx = await seedPayable(firestore);
  const base = fixtures.buildCanonicalPaymentRaceFixture();
  const result = payments.finalizeCapturedBookingPaymentV3({
    bookingId: ctx.ids.bookingId,
    booking: ctx.booking,
    paymentAttempt: ctx.attempt,
    parent: {...base.parent, uid: ctx.parentId},
    providerPrivate: {uid: ctx.providerId},
    service: {...base.service, id: ctx.serviceId, ownerUserId: ctx.providerId},
    existingBookingPrivate: null,
    existingBookingPrivateParticipants: null,
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: ctx.ids.razorpayPaymentId,
      orderId: ctx.ids.razorpayOrderId,
      status: "captured",
      amountPaise: ctx.amountPaise,
      currency: "INR",
      createdAt: ctx.capturedAt,
      capturedAt: ctx.capturedAt,
      receipt: "",
      notes: {},
    },
    authoritativeNow: ctx.now,
    verificationSource: "webhook",
  });
  assert.equal(result.ok, true, `pure result should confirm: ${result.code}`);
  await blockPair(firestore, ctx);
  const outcome = await payments.persistFinalizePaymentResultV3({
    firestore,
    result,
    bookingId: ctx.ids.bookingId,
    holdContext: {verificationSource: "webhook", sourceEventId: "race-event"},
  });
  assert.equal(outcome.held, true);
  assert.equal(outcome.created, true);
  await assertHeld(firestore, ctx, {sourceEventIds: ["race-event"]});
});

test("regression: an unblocked pair confirms normally and creates no hold", {skip: !enabled}, async () => {
  const ctx = await seedPayable(firestore);
  const result = await payments.finalizeCapturedCanonicalPaymentV3({
    firestore, facts: facts(ctx), keyId: KEY_ID, keySecret: KEY_SECRET, authoritativeNow: ctx.now,
  });
  assert.equal(result.ok, true, result.code);
  assert.equal(result.code, "CONFIRMED");
  const booking = (await firestore.collection("bookings").doc(ctx.ids.bookingId).get()).data();
  assert.equal(booking.state, "CONFIRMED");
  assert.equal((await firestore.collection("blockedRelationshipPaymentHolds")
    .doc(ctx.ids.razorpayPaymentId).get()).exists, false);
  assert.equal((await firestore.collection("bookings").doc(ctx.ids.bookingId).collection("events")
    .doc(`payment_held_blocked_relationship_${ctx.ids.razorpayPaymentId}`).get()).exists, false);
});

test("Q1: PAYMENT_EXPIRED + blocked pair keeps the automatic refund and creates no hold", {
  skip: !enabled,
}, async () => {
  const ctx = await seedPayable(firestore, {state: "PAYMENT_EXPIRED"});
  await blockPair(firestore, ctx);
  // Through the real webhook route, which records the payment on the attempt
  // before finalization (canonicalPaymentWebhookV3.ts payment.captured path).
  const result = await webhook.routeCanonicalWebhookEventV3({
    firestore,
    eventId: `payment.captured:${ctx.ids.razorpayPaymentId}`,
    eventName: "payment.captured",
    paymentEntity: capturedPayload(ctx).payload.payment.entity,
    refundEntity: {},
    keyId: KEY_ID,
    keySecret: KEY_SECRET,
    authoritativeNow: ctx.now,
  });
  assert.equal(result.outcome, "REFUND_REQUIRED");
  assert.equal(result.failureCode, "PAYMENT_EXPIRED");
  const refunds = await firestore.collection("refunds")
    .where("razorpayPaymentId", "==", ctx.ids.razorpayPaymentId).get();
  assert.equal(refunds.size, 1, "refund instruction persisted");
  const notices = await firestore.collection("notifications").where("userId", "==", ctx.parentId).get();
  assert.ok(notices.docs.every((doc) => doc.data().type !== "payment_held_for_review"));
  assert.ok(fetchCalls.some((call) => call.url.includes(`/payments/${ctx.ids.razorpayPaymentId}/refund`)),
    "automatic refund submitted to Razorpay");
  assert.equal((await firestore.collection("blockedRelationshipPaymentHolds")
    .doc(ctx.ids.razorpayPaymentId).get()).exists, false);
  const booking = (await firestore.collection("bookings").doc(ctx.ids.bookingId).get()).data();
  assert.notEqual(booking.state, "CONFIRMED");
});

test("zero-payable confirmation for a blocked pair is still refused (nothing captured to hold)", {
  skip: !enabled,
}, async () => {
  const ctx = await seedPayable(firestore);
  await blockPair(firestore, ctx);
  await assert.rejects(payments.persistFinalizePaymentResultV3({
    firestore,
    bookingId: ctx.ids.bookingId,
    result: {
      ok: true,
      code: "CONFIRMED",
      booking: (await firestore.collection("bookings").doc(ctx.ids.bookingId).get()).data(),
      paymentAttempt: {paymentAttemptId: ctx.ids.paymentAttemptId, razorpayPaymentId: ""},
      couponWrite: null,
      notifications: [],
      events: [],
      occupancyWrites: {},
    },
  }).catch((error) => {
    throw error;
  }), (error) => {
    assert.ok(["USER_RELATIONSHIP_BLOCKED"].includes(error.details?.code) ||
      /paid timestamp|canonical conversation/.test(error.message), error.message);
    return true;
  });
  assert.equal((await firestore.collection("blockedRelationshipPaymentHolds")
    .where("bookingId", "==", ctx.ids.bookingId).get()).size, 0);
});

test("callable verify on a blocked pair: PAYMENT_HELD_FOR_REVIEW, same hold, idempotent", {
  skip: !enabled,
}, async () => {
  const now = new Date();
  const ctx = await seedPayable(sharedDb, {
    now,
    payDeadlineAt: new Date(now.getTime() + 60 * 60 * 1000),
  });
  await blockPair(sharedDb, ctx);
  const signature = createHmac("sha256", KEY_SECRET)
    .update(`${ctx.ids.razorpayOrderId}|${ctx.ids.razorpayPaymentId}`).digest("hex");
  const request = {
    auth: {uid: ctx.parentId},
    data: {
      bookingId: ctx.ids.bookingId,
      paymentAttemptId: ctx.ids.paymentAttemptId,
      razorpay_order_id: ctx.ids.razorpayOrderId,
      razorpay_payment_id: ctx.ids.razorpayPaymentId,
      razorpay_signature: signature,
    },
  };
  for (let call = 0; call < 2; call += 1) {
    await assert.rejects(verifyBookingPaymentV3.run(request), (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.equal(error.details?.code, "PAYMENT_HELD_FOR_REVIEW");
      return true;
    });
  }
  await assertHeld(sharedDb, ctx);
  const hold = (await sharedDb.collection("blockedRelationshipPaymentHolds")
    .doc(ctx.ids.razorpayPaymentId).get()).data();
  assert.deepEqual(hold.sources, ["callable"]);
  assert.deepEqual(hold.sourceEventIds, []);
  // Clean up the default project.
  await sharedDb.collection("userBlocks").doc(`${ctx.providerId}_${ctx.parentId}`).delete();
});
