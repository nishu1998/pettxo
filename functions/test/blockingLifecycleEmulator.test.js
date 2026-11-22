// Phase 3B-4e: booking lifecycles end in a blockable relationship.
//
// Drives real application code on the emulator: the canonical webhook route
// (finalisation and persistence), start OTP, service completion,
// finalisation, one pass of the expireAwaitingPaymentsV3 scheduler
// (runPaymentExpirySweepV3, which also runs the payment reconciler) and the
// request lifecycle commands. After each step it
// records getUserRelationshipStateDataV1 and blockUserDataV1 for the pair.
// Razorpay's HTTP API is stubbed. Accept + order is seeded as the documents
// the order callable writes (attempt, order/QR mapping, booking payment
// fields; bookingV3FlowFunctions.ts createRazorpayPaymentOrderV3).
//
// Runs in its own demo project: the gate documents and the expiry sweep are
// project-wide and must not touch other test files' data.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-blocking-lifecycle",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const enabled = firebaseEmulator.enabled;
let app;
let db;
let auth;
let web;
let start;
let comp;
let req;
let ub;
let fx;
let flows;
let race;
const knownPayments = new Map();
let originalFetch;

function epoch(date) {
  return Math.floor(date.getTime() / 1000);
}

function strip(value) {
  if (Array.isArray(value)) return value.map(strip);
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .map(([key, entry]) => [key, strip(entry)]));
  }
  return value;
}

function installFetch() {
  originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const target = String(url);
    const payment = target.match(/\/v1\/payments\/([^/?]+)$/);
    if (payment) {
      const record = knownPayments.get(decodeURIComponent(payment[1]));
      return new Response(JSON.stringify(record ?? {}), {status: record ? 200 : 404});
    }
    const orderPayments = target.match(/\/v1\/orders\/([^/]+)\/payments$/);
    if (orderPayments) {
      const items = [...knownPayments.values()].filter((item) => item.order_id === decodeURIComponent(orderPayments[1]));
      return new Response(JSON.stringify({items}), {status: 200});
    }
    if (/qr_codes\/[^/]+\/close$/.test(target)) return new Response(JSON.stringify({status: "closed"}), {status: 200});
    if (/\/refund$/.test(target)) return new Response(JSON.stringify({id: `rfnd_${randomUUID().slice(0, 6)}`, status: "processed"}), {status: 200});
    return new Response(JSON.stringify({error: {description: `unstubbed ${target}`}}), {status: 500});
  };
}

async function enableGate() {
  await Promise.all([
    db.doc("_migrations/userRelationshipGuardV1").set({migrationVersion: 1, runId: "lifecycle-run", status: "verified",
      sourceFingerprint: "lifecycle-fp", reconciliationPassed: true, anomalyCount: 0, mismatchCount: 0}),
    db.doc("userBlockingActivationAudit/lifecycle-activation").set({event: "ACTIVATE", enabled: true,
      migrationRunId: "lifecycle-run", sourceFingerprint: "lifecycle-fp", rolloutVersion: 1}),
    db.doc("_rollouts/userBlockingV1").set({enabled: true, status: "active", migrationRunId: "lifecycle-run",
      sourceFingerprint: "lifecycle-fp", activationAuditId: "lifecycle-activation", rolloutVersion: 1}),
  ]);
}

function pairify(booking, parent, provider, serviceId) {
  booking.parentId = parent;
  booking.customerId = parent;
  booking.providerId = provider;
  booking.serviceOwnerId = provider;
  booking.participantIds = [parent, provider];
  booking.participants.parent.parentId = parent;
  booking.participants.provider.providerId = provider;
  booking.serviceId = serviceId;
  booking.service.serviceId = serviceId;
  booking.service.providerId = provider;
  for (const slot of booking.schedule.slots ?? []) {
    slot.serviceId = serviceId;
    slot.providerId = provider;
  }
  return booking;
}

async function newPair(name) {
  const sfx = randomUUID().slice(0, 6);
  const ctx = {name, parent: `lc-par-${sfx}`, provider: `lc-pro-${sfx}`, serviceId: `lc-svc-${sfx}`, sfx};
  await Promise.all([
    db.doc(`users/${ctx.parent}`).set({uid: ctx.parent, displayName: "Parent", accountStatus: "active"}),
    db.doc(`users/${ctx.provider}`).set({uid: ctx.provider, displayName: "Provider", accountStatus: "active"}),
    db.doc(`services/${ctx.serviceId}`).set(strip({...race.liveService(), serviceId: ctx.serviceId, ownerUserId: ctx.provider})),
  ]);
  return ctx;
}

async function acceptedWithOrder(ctx, n, {qr = false} = {}) {
  const ids = {
    bookingId: `lc-bk-${ctx.sfx}-${n}`,
    paymentAttemptId: `lc-at-${ctx.sfx}-${n}-1`,
    razorpayOrderId: qr ? "" : `order_${ctx.sfx}_${n}_1`,
    razorpayPaymentId: `pay_${ctx.sfx}_${n}`,
    webhookEventId: "unused",
    refundInstructionId: "unused",
  };
  const base = race.buildCanonicalPaymentRaceFixture({ids});
  const booking = pairify(base.booking, ctx.parent, ctx.provider, ctx.serviceId);
  booking.bookingId = ids.bookingId;
  const attempt = {
    ...base.paymentAttempt,
    parentId: ctx.parent,
    providerId: ctx.provider,
    bookingId: ids.bookingId,
    ...(qr ? {paymentMethod: "qr", razorpayOrderId: "", razorpayQrCodeId: `qr_${ctx.sfx}_${n}`, qrState: "ACTIVE"} : {}),
  };
  booking.payment.paymentAttemptId = ids.paymentAttemptId;
  booking.payment.razorpayOrderId = attempt.razorpayOrderId;
  booking.payment.orderCreatedAt = attempt.orderCreatedAt;
  await Promise.all([
    db.doc(`bookings/${ids.bookingId}`).set(strip(booking)),
    db.doc(`bookings/${ids.bookingId}/paymentAttempts/${ids.paymentAttemptId}`).set(strip(attempt)),
    qr ?
      db.doc(`canonicalQrPaymentMappings/${attempt.razorpayQrCodeId}`).set({
        bookingId: ids.bookingId, paymentAttemptId: ids.paymentAttemptId, status: "ACTIVE", schemaVersion: 1,
      }) :
      db.doc(`canonicalPaymentOrderMappings/${ids.razorpayOrderId}`).set({
        bookingId: ids.bookingId, paymentAttemptId: ids.paymentAttemptId, schemaVersion: 1,
      }),
  ]);
  return {ids, attempt};
}

async function secondOrder(ctx, bk, n) {
  const attemptId = `lc-at-${ctx.sfx}-${n}-2`;
  const orderId = `order_${ctx.sfx}_${n}_2`;
  const attempt = {...bk.attempt, paymentAttemptId: attemptId, razorpayOrderId: orderId, requestAttemptId: `r-${attemptId}`};
  await Promise.all([
    db.doc(`bookings/${bk.ids.bookingId}/paymentAttempts/${attemptId}`).set(strip(attempt)),
    db.doc(`canonicalPaymentOrderMappings/${orderId}`).set({bookingId: bk.ids.bookingId, paymentAttemptId: attemptId, schemaVersion: 1}),
    db.doc(`bookings/${bk.ids.bookingId}`).update({"payment.paymentAttemptId": attemptId, "payment.razorpayOrderId": orderId}),
  ]);
  bk.ids.paymentAttemptId = attemptId;
  bk.ids.razorpayOrderId = orderId;
  bk.attempt = attempt;
}

async function payViaWebhook(bk, {qr = false, at}) {
  const payment = {
    id: bk.ids.razorpayPaymentId, order_id: bk.ids.razorpayOrderId, status: "captured", captured: true,
    amount: bk.attempt.amountPaise, currency: "INR", created_at: epoch(at), captured_at: epoch(at),
  };
  knownPayments.set(payment.id, payment);
  return web.routeCanonicalWebhookEventV3({
    firestore: db,
    eventId: `evt-${payment.id}`,
    eventName: qr ? "qr_code.credited" : "payment.captured",
    paymentEntity: {id: payment.id, order_id: payment.order_id, amount: payment.amount, currency: "INR", status: "captured"},
    refundEntity: {},
    qrCodeEntity: qr ? {id: bk.attempt.razorpayQrCodeId} : undefined,
    keyId: "rzp_test_k",
    keySecret: "test-secret",
    authoritativeNow: at,
  });
}

/** Records state + block for the pair; unblocks again after a successful block. */
async function check(ctx, now, {tryBlock = true} = {}) {
  const state = await ub.getUserRelationshipStateDataV1({
    firestore: db, actorUid: ctx.parent, targetUid: ctx.provider, authoritativeNow: now,
  });
  let block = "not attempted";
  if (tryBlock) {
    try {
      await ub.blockUserDataV1({firestore: db, actorUid: ctx.parent, targetUid: ctx.provider, authoritativeNow: now});
      block = "blocked";
      await ub.unblockUserDataV1({firestore: db, actorUid: ctx.parent, targetUid: ctx.provider});
    } catch (error) {
      block = error.details?.code ?? error.message;
    }
  }
  return {canBlock: state.canBlock, reasonCode: state.reasonCode, block};
}

function expectRefused(result, reasonCode, blockCode) {
  assert.equal(result.canBlock, false, JSON.stringify(result));
  assert.equal(result.reasonCode, reasonCode, JSON.stringify(result));
  if (blockCode) assert.equal(result.block, blockCode, JSON.stringify(result));
}

function expectBlockable(result) {
  assert.equal(result.canBlock, true, JSON.stringify(result));
  assert.equal(result.reasonCode, "", JSON.stringify(result));
  if (result.block !== "not attempted") assert.equal(result.block, "blocked", JSON.stringify(result));
}

async function runExpiryScheduler() {
  await flows.runPaymentExpirySweepV3({
    firestore: db, keyId: "rzp_test_k", keySecret: "test-secret", authoritativeNow: new Date(),
  });
}

async function bookingState(bookingId) {
  return (await db.doc(`bookings/${bookingId}`).get()).data().state;
}

async function paidToFinal(ctx, {qr = false, abandonFirst = false} = {}) {
  const bk = await acceptedWithOrder(ctx, 1, {qr});
  expectRefused(await check(ctx, new Date("2026-07-22T10:22:00Z")), "PAYMENT_RECONCILIATION_REQUIRED",
    "PAYMENT_RECONCILIATION_REQUIRED");
  if (abandonFirst) {
    await secondOrder(ctx, bk, 1);
    expectRefused(await check(ctx, new Date("2026-07-22T10:24:00Z"), {tryBlock: false}), "PAYMENT_RECONCILIATION_REQUIRED");
  }
  const paid = await payViaWebhook(bk, {qr, at: new Date("2026-07-22T10:25:05Z")});
  assert.equal(paid.outcome, "CONFIRMED", JSON.stringify(paid));
  expectRefused(await check(ctx, new Date("2026-07-22T10:30:00Z"), {tryBlock: false}), "PROTECTED_STATE_CONFIRMED");

  const privateDoc = (await db.doc(`bookingPrivate/${bk.ids.bookingId}`).get()).data();
  const started = await start.verifyBookingStartOtpV3({
    firestore: db, bookingId: bk.ids.bookingId, providerId: ctx.provider, otpCandidate: privateDoc.parentOtpCode,
    requestAttemptId: `otp-${ctx.sfx}`, authoritativeNow: new Date("2026-07-23T06:05:00Z"),
  });
  assert.equal(started.code, "VERIFIED_STARTED", JSON.stringify(started));
  expectRefused(await check(ctx, new Date("2026-07-23T06:10:00Z"), {tryBlock: false}), "PROTECTED_STATE_IN_PROGRESS");

  const completed = await comp.completeBookingServiceV3({
    firestore: db, bookingId: bk.ids.bookingId, providerUid: ctx.provider, authoritativeNow: new Date("2026-07-23T07:05:00Z"),
  });
  assert.equal(completed.code, "COMPLETED_PENDING_REVIEW", JSON.stringify(completed));
  expectRefused(await check(ctx, new Date("2026-07-23T07:10:00Z")),
    "PROTECTED_STATE_COMPLETED_PENDING_REVIEW", "PROTECTED_BOOKING_EXISTS");

  const reviewEnds = (await db.doc(`bookings/${bk.ids.bookingId}`).get()).data().lifecycle.reviewWindowEndsAt.toDate();
  const finalAt = new Date(reviewEnds.getTime() + 60_000);
  const finalised = await comp.finalizeCompletedBookingV3({firestore: db, bookingId: bk.ids.bookingId, authoritativeNow: finalAt});
  assert.equal(finalised.code, "FINALIZED", JSON.stringify(finalised));
  expectBlockable(await check(ctx, new Date(finalAt.getTime() + 60_000)));
  expectBlockable(await check(ctx, new Date()));
  assert.equal(await bookingState(bk.ids.bookingId), "COMPLETED_FINAL");
}

test.before(async () => {
  if (!enabled) return;
  process.env.RAZORPAY_KEY_ID = "rzp_test_k";
  process.env.RAZORPAY_KEY_SECRET = "test-secret";
  ({auth} = require("../lib/shared/firebase.js"));
  app = initializeApp({projectId: "demo-blocking-lifecycle"}, `lifecycle-${randomUUID()}`);
  // No ignoreUndefinedProperties: behave like the production default app.
  db = getFirestore(app);
  auth.getUser = async (uid) => ({uid, displayName: uid, email: "", phoneNumber: "+919000000000"});
  web = require("../lib/booking/application/canonicalPaymentWebhookV3.js");
  start = require("../lib/booking/application/serviceStartOrchestrationV3.js");
  comp = require("../lib/booking/application/serviceCompletionOrchestrationV3.js");
  req = require("../lib/booking/application/createBookingRequestV3.js");
  ub = require("../lib/blocking/userBlocking.js");
  fx = require("../lib/booking/schema/bookingFixtures.js");
  flows = require("../lib/booking/bookingV3FlowFunctions.js");
  race = require("./helpers/canonicalPaymentRaceFixture.js");
  installFetch();
  await enableGate();
});

test.after(async () => {
  if (!enabled) return;
  globalThis.fetch = originalFetch;
  await db.terminate();
  await deleteApp(app);
});

test("a: checkout paid -> confirmed -> OTP -> completed -> finalised", {skip: !enabled}, async () => {
  await paidToFinal(await newPair("a"));
});

test("b: abandoned first order, second order paid -> finalised", {skip: !enabled}, async () => {
  await paidToFinal(await newPair("b"), {abandonFirst: true});
});

test("g: QR paid -> finalised", {skip: !enabled}, async () => {
  await paidToFinal(await newPair("g"), {qr: true});
});

test("c/d/g-d/c2: unpaid orders expire; a never-captured payment ends FAILED and expires (R1)", {skip: !enabled}, async () => {
  const failed = await newPair("c");
  const failedBooking = await acceptedWithOrder(failed, 1);
  expectRefused(await check(failed, new Date("2026-07-22T10:40:00Z")), "PAYMENT_RECONCILIATION_REQUIRED",
    "PAYMENT_RECONCILIATION_REQUIRED");

  const abandoned = await newPair("d");
  const abandonedBooking = await acceptedWithOrder(abandoned, 1);
  await db.doc(`bookings/${abandonedBooking.ids.bookingId}/paymentAttempts/${abandonedBooking.ids.paymentAttemptId}`)
    .update({state: "CHECKOUT_OPENED"});

  const qrAbandoned = await newPair("g-d");
  const qrBooking = await acceptedWithOrder(qrAbandoned, 1, {qr: true});

  // c2: verify reported the payment before capture; it never captures.
  const neverCaptured = await newPair("c2");
  const c2 = await acceptedWithOrder(neverCaptured, 1);
  knownPayments.set(c2.ids.razorpayPaymentId, {
    id: c2.ids.razorpayPaymentId, order_id: c2.ids.razorpayOrderId, status: "failed", captured: false,
    amount: c2.attempt.amountPaise, currency: "INR", created_at: epoch(new Date("2026-07-22T10:25:00Z")),
  });
  await db.doc(`bookings/${c2.ids.bookingId}/paymentAttempts/${c2.ids.paymentAttemptId}`).set({
    razorpayOrderId: c2.ids.razorpayOrderId,
    razorpayPaymentId: c2.ids.razorpayPaymentId,
    state: "CAPTURED_REQUIRES_RECONCILIATION",
    captureReportedAt: new Date("2026-07-22T10:25:30Z"),
    verificationSource: "callable",
    retryCount: 1,
    updatedAt: new Date(),
  }, {merge: true});

  await runExpiryScheduler();
  for (const [ctx, bk] of [[failed, failedBooking], [abandoned, abandonedBooking], [qrAbandoned, qrBooking], [neverCaptured, c2]]) {
    assert.equal(await bookingState(bk.ids.bookingId), "PAYMENT_EXPIRED", ctx.name);
    expectBlockable(await check(ctx, new Date()));
  }
  const c2Attempt = (await db.doc(`bookings/${c2.ids.bookingId}/paymentAttempts/${c2.ids.paymentAttemptId}`).get()).data();
  assert.equal(c2Attempt.state, "FAILED");
  assert.ok(c2Attempt.terminalFailureAt);
  assert.equal(c2Attempt.lastReconciliationCode, "PAYMENT_FAILED");
  const expiredAttempt = (await db.doc(`bookings/${failedBooking.ids.bookingId}/paymentAttempts/${failedBooking.ids.paymentAttemptId}`).get()).data();
  assert.equal(expiredAttempt.state, "EXPIRED");
});

test("e: declined, provider-expired and parent-cancelled requests", {skip: !enabled}, async () => {
  const now = new Date("2026-07-22T10:20:00Z");
  for (const [name, command, expectedState] of [
    ["e-declined", (booking, id) => req.declineBookingRequestV3({bookingId: id, booking, providerUid: booking.providerId, authoritativeNow: now}), "DECLINED"],
    ["e-provider-expired", (booking, id) => req.expirePendingProviderBookingV3({bookingId: id,
      booking: {...booking, state: "PENDING_PROVIDER", stateQueryValue: "PENDING_PROVIDER"},
      authoritativeNow: new Date("2026-07-22T12:00:00Z")}), "EXPIRED"],
    ["e-parent-cancelled", (booking, id) => req.cancelBookingRequestByParentV3({bookingId: id, booking, parentUid: booking.parentId, authoritativeNow: now}), "CANCELLED_BY_PARENT"],
  ]) {
    const ctx = await newPair(name);
    const id = `lc-bk-${ctx.sfx}-e`;
    const result = command(pairify(fx.buildRequestedSingleSlotBookingFixture(), ctx.parent, ctx.provider, ctx.serviceId), id);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.booking.state, expectedState);
    await db.doc(`bookings/${id}`).set(strip(result.booking));
    expectBlockable(await check(ctx, new Date()));
  }
});

test("f: paid booking cancelled (CANCELLED): refund pending protects, processed releases", {skip: !enabled}, async () => {
  const ctx = await newPair("f");
  const id = `lc-bk-${ctx.sfx}-f`;
  const cancelled = pairify(fx.buildCancelledBookingFixture(), ctx.parent, ctx.provider, ctx.serviceId);
  // Confirmed-booking cancellation ends in CANCELLED (cancellationOrchestrationV3.ts).
  cancelled.state = "CANCELLED";
  cancelled.stateQueryValue = "CANCELLED";
  cancelled.payment.status = "refund_pending";
  await db.doc(`bookings/${id}`).set(strip(cancelled));
  expectRefused(await check(ctx, new Date()), "FINANCIAL_OBLIGATION_UNRESOLVED", "PROTECTED_BOOKING_EXISTS");
  await db.doc(`bookings/${id}`).update({"payment.status": "refunded"});
  expectBlockable(await check(ctx, new Date()));
});

test("x: late capture after PAYMENT_EXPIRED: protected while the refund is pending, released once refunded (R2)", {skip: !enabled}, async () => {
  const ctx = await newPair("x");
  const bk = await acceptedWithOrder(ctx, 1);
  await runExpiryScheduler();
  assert.equal(await bookingState(bk.ids.bookingId), "PAYMENT_EXPIRED");
  expectBlockable(await check(ctx, new Date(), {tryBlock: false}));
  const late = await payViaWebhook(bk, {at: new Date()});
  assert.equal(late.outcome, "REFUND_REQUIRED");
  assert.equal(late.failureCode, "PAYMENT_EXPIRED");
  await db.doc(`bookings/${bk.ids.bookingId}`).update({"payment.status": "refund_pending"});
  expectRefused(await check(ctx, new Date()), "FINANCIAL_OBLIGATION_UNRESOLVED", "PROTECTED_BOOKING_EXISTS");
  await db.doc(`bookings/${bk.ids.bookingId}`).update({"payment.status": "refunded"});
  expectBlockable(await check(ctx, new Date()));
});
