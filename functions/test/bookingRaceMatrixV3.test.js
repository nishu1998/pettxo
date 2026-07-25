const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createRaceFixture,
  assertConfirmedExactlyOnce,
  assertRefundRequiredExactlyOnce,
  assertNoCrossBookingEffects,
} = require("./helpers/canonicalPaymentRaceHarness.js");

test("callable confirms first, webhook arrives later", async () => {
  const fixture = createRaceFixture();
  await fixture.runCallable();
  await fixture.runWebhook({eventId: "webhook-race-a"});
  assertConfirmedExactlyOnce(fixture);
});

test("webhook confirms first, callable retries later", async () => {
  const fixture = createRaceFixture();
  await fixture.runWebhook({eventId: "webhook-race-a"});
  await fixture.runCallable();
  assertConfirmedExactlyOnce(fixture);
});

test("callable and webhook run concurrently", async () => {
  const fixture = createRaceFixture();
  await Promise.all([
    fixture.runCallable(),
    fixture.runWebhook({eventId: "webhook-race-a"}),
  ]);
  assertConfirmedExactlyOnce(fixture);
});

test("duplicate callable submissions remain exactly-once", async () => {
  const fixture = createRaceFixture();
  await fixture.runCallable();
  await fixture.runCallable();
  assertConfirmedExactlyOnce(fixture);
});

test("duplicate webhook envelope with same event key remains exactly-once", async () => {
  const fixture = createRaceFixture();
  await fixture.runWebhook({mode: "envelope"});
  await fixture.runWebhook({mode: "envelope"});
  assertConfirmedExactlyOnce(fixture);
});

test("two webhook event ids for same captured payment remain exactly-once", async () => {
  const fixture = createRaceFixture();
  await fixture.runWebhook({eventId: "webhook-race-a"});
  await fixture.runWebhook({eventId: "webhook-race-b"});
  assertConfirmedExactlyOnce(fixture);
});

test("callable timeout after commit then retry remains exactly-once", async () => {
  const fixture = createRaceFixture();
  await assert.rejects(
    fixture.runCallable({simulateTimeoutAfterCommit: true}),
  );
  await fixture.runCallable();
  assertConfirmedExactlyOnce(fixture);
});

test("webhook retryable failure can be reclaimed and later succeed", async () => {
  const fixture = createRaceFixture();
  await assert.rejects(
    fixture.runWebhook({mode: "envelope", failBeforeFinalize: true}),
  );
  await fixture.runWebhook({mode: "envelope"});
  assertConfirmedExactlyOnce(fixture);
});

test("valid capture racing payment expiry keeps confirmed state authoritative", async () => {
  const fixture = createRaceFixture();
  await Promise.allSettled([
    fixture.runCallable(),
    fixture.runPaymentExpiry(),
  ]);
  assertConfirmedExactlyOnce(fixture);
});

test("same Razorpay payment id reused against another booking attempt creates no cross-booking effects", async () => {
  const fixture = createRaceFixture();
  fixture.firestore._set("bookings/booking-other", {
    ...fixture.base.booking,
    bookingId: "booking-other",
    parentId: "parent-2",
  });
  fixture.firestore._set("bookings/booking-other/paymentAttempts/attempt-other", {
    ...fixture.base.paymentAttempt,
    bookingId: "booking-other",
    paymentAttemptId: "attempt-other",
    razorpayOrderId: "order-other",
    razorpayPaymentId: fixture.ids.razorpayPaymentId,
  });
  await fixture.runWebhook({eventId: "webhook-race-a"});
  assertConfirmedExactlyOnce(fixture);
  assertNoCrossBookingEffects(fixture, "booking-other");
});

test("callable confirms while active reconciliation lease exists", async () => {
  const fixture = createRaceFixture();
  await fixture.runReconciliation({leaseState: "active"});
  await fixture.runCallable();
  assertConfirmedExactlyOnce(fixture);
});

test("reconciliation confirms before callable retry", async () => {
  const fixture = createRaceFixture();
  await fixture.runReconciliation();
  await fixture.runCallable();
  assertConfirmedExactlyOnce(fixture);
});

test("callable and reconciliation run concurrently", async () => {
  const fixture = createRaceFixture();
  await Promise.all([
    fixture.runCallable(),
    fixture.runReconciliation(),
  ]);
  assertConfirmedExactlyOnce(fixture);
});

test("reconciliation retry after callable confirmation does not reopen state", async () => {
  const fixture = createRaceFixture();
  await fixture.runCallable();
  await fixture.runReconciliation();
  assertConfirmedExactlyOnce(fixture);
});

test("stale reconciliation lease is reclaimed after callable confirmation", async () => {
  const fixture = createRaceFixture();
  await fixture.runCallable();
  await fixture.runReconciliation({leaseState: "stale"});
  assertConfirmedExactlyOnce(fixture);
});

test("webhook and reconciliation run concurrently", async () => {
  const fixture = createRaceFixture();
  await Promise.all([
    fixture.runWebhook({eventId: "webhook-race-a"}),
    fixture.runReconciliation(),
  ]);
  assertConfirmedExactlyOnce(fixture);
});

test("webhook confirms while reconciliation lease is active", async () => {
  const fixture = createRaceFixture();
  await fixture.runReconciliation({leaseState: "active"});
  await fixture.runWebhook({eventId: "webhook-race-a"});
  assertConfirmedExactlyOnce(fixture);
});

test("webhook confirms while reconciliation lease is expired", async () => {
  const fixture = createRaceFixture();
  await fixture.runReconciliation({leaseState: "stale"});
  await fixture.runWebhook({eventId: "webhook-race-a"});
  assertConfirmedExactlyOnce(fixture);
});

test("reconciliation confirms before webhook replay", async () => {
  const fixture = createRaceFixture();
  await fixture.runReconciliation();
  await fixture.runWebhook({eventId: "webhook-race-a"});
  assertConfirmedExactlyOnce(fixture);
});

test("callable, webhook and reconciliation all run concurrently for valid capture", async () => {
  const fixture = createRaceFixture();
  await Promise.all([
    fixture.runCallable(),
    fixture.runWebhook({eventId: "webhook-race-a"}),
    fixture.runReconciliation(),
  ]);
  assertConfirmedExactlyOnce(fixture);
});

test("callable, webhook and reconciliation all race into one capacity-loss refund path", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await Promise.allSettled([
    fixture.runCallable(),
    fixture.runWebhook({eventId: "webhook-race-a"}),
    fixture.runReconciliation(),
  ]);
  assertRefundRequiredExactlyOnce(fixture);
});

test("duplicate callable compensation keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await fixture.runCallable();
  await fixture.runCallable();
  assertRefundRequiredExactlyOnce(fixture);
});

test("duplicate webhook compensation keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await fixture.runWebhook({eventId: "webhook-race-a"});
  await fixture.runWebhook({eventId: "webhook-race-b"});
  assertRefundRequiredExactlyOnce(fixture);
});

test("duplicate reconciliation compensation keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await fixture.runCallable();
  await fixture.runReconciliation();
  assertRefundRequiredExactlyOnce(fixture);
});

test("callable and webhook compensation race keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await Promise.allSettled([
    fixture.runCallable(),
    fixture.runWebhook({eventId: "webhook-race-a"}),
  ]);
  assertRefundRequiredExactlyOnce(fixture);
});

test("callable and reconciliation compensation race keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await Promise.allSettled([
    fixture.runCallable(),
    fixture.runReconciliation(),
  ]);
  assertRefundRequiredExactlyOnce(fixture);
});

test("webhook and reconciliation compensation race keeps one refund instruction", async () => {
  const fixture = createRaceFixture({capacityAvailable: false});
  await Promise.allSettled([
    fixture.runWebhook({eventId: "webhook-race-a"}),
    fixture.runReconciliation(),
  ]);
  assertRefundRequiredExactlyOnce(fixture);
});

test("refund submission retry reuses deterministic refund document", async () => {
  const fixture = createRaceFixture({capacityAvailable: false, refundGatewayOutcome: "timeout"});
  await fixture.runCallable();
  const first = await fixture.runRefundSubmission();
  assert.equal(first.outcome, "RETRY_LATER");
  assert.equal(first.callCount, 1);
  assert.equal(fixture.firestore.store.has(`refunds/${fixture.ids.bookingId}`), true);
  assert.equal(
    fixture.firestore.store.get(`refunds/${fixture.ids.bookingId}`).razorpayRefundId ?? "",
    "",
  );
  assert.equal(
    [...fixture.firestore.store.keys()].filter(
      (path) => path === `refunds/${fixture.ids.bookingId}`,
    ).length,
    1,
  );

  fixture.setRefundGatewayOutcome("processed");
  const second = await fixture.runRefundSubmission();
  assert.equal(second.outcome, "REFUNDED");
  assert.equal(second.callCount, 1);
  assert.equal(
    fixture.firestore.store.get(`refunds/${fixture.ids.bookingId}`).razorpayRefundId,
    "rfnd-race-v3",
  );
  assert.equal(
    [...fixture.firestore.store.keys()].filter(
      (path) => path === `refunds/${fixture.ids.bookingId}`,
    ).length,
    1,
  );
});
