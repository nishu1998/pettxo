const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");

const {
  buildCompletedFinalBookingFixture,
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  previewBookingDisputeResolutionV3,
  resolveBookingDisputeV3,
  processProviderPayoutV3,
  processRetryableProviderPayoutBatchV3,
  reconcileBookingFinancialsV3,
} = require("../lib/booking/application/financialSettlementV3.js");

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
  }
}

class FakeDocSnapshot {
  constructor(firestore, path, data) {
    this.ref = new FakeDocRef(firestore, path);
    this.path = path;
    this.id = path.split("/").pop();
    this._data = data;
  }

  get exists() {
    return this._data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeTransaction {
  constructor(firestore) {
    this.firestore = firestore;
    this.pendingWrites = [];
  }

  async get(ref) {
    return ref.get();
  }

  set(ref, data, options) {
    this.pendingWrites.push({path: ref.path, data, options});
  }

  commit() {
    for (const write of this.pendingWrites) {
      this.firestore._set(write.path, write.data, write.options);
    }
  }
}

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }

  async get() {
    return new FakeDocSnapshot(
      this.firestore,
      this.path,
      this.firestore.store.get(this.path),
    );
  }

  set(data, options) {
    this.firestore._set(this.path, data, options);
    return Promise.resolve();
  }
}

class FakeQuery {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.filters = [];
    this.limitValue = null;
  }

  where(field, op, value) {
    this.filters.push({field, op, value});
    return this;
  }

  limit(value) {
    this.limitValue = value;
    return this;
  }

  async get() {
    const prefix = `${this.path}/`;
    let docs = Array.from(this.firestore.store.entries())
      .filter(([path]) => path.startsWith(prefix))
      .filter(([path]) => path.split("/").length === this.path.split("/").length + 1)
      .map(([path, data]) => new FakeDocSnapshot(this.firestore, path, data));
    for (const filter of this.filters) {
      docs = docs.filter((doc) => {
        const data = doc.data() ?? {};
        if (filter.op === "==") {
          return data[filter.field] === filter.value;
        }
        return true;
      });
    }
    if (this.limitValue != null) {
      docs = docs.slice(0, this.limitValue);
    }
    return new FakeQuerySnapshot(docs);
  }
}

class FakeCollectionRef extends FakeQuery {
  constructor(firestore, path) {
    super(firestore, path);
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  async runTransaction(handler) {
    const transaction = new FakeTransaction(this);
    const result = await handler(transaction);
    transaction.commit();
    return result;
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function buildOpenDisputeBooking() {
  const booking = buildConfirmedSlotBookingFixture();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.dispute = {
    ...booking.dispute,
    disputeId: "booking-dispute-1",
    status: "OPEN",
    raisedAt: new Date("2026-07-23T07:00:00.000Z"),
    raisedBy: "parent",
    reasonCode: "provider_unavailable",
    description: "Provider did not show up.",
  };
  booking.payout.status = "HELD";
  booking.payout.eligibleAt = booking.lifecycle.reviewWindowEndsAt;
  return booking;
}

test("dispute resolution is idempotent for matching repeated admin requests", async () => {
  const bookingId = "booking-dispute-1";
  const booking = buildOpenDisputeBooking();
  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
      reasonCode: "provider_unavailable",
      description: "Provider did not show up.",
      createdAt: new Date("2026-07-23T07:00:00.000Z"),
      updatedAt: new Date("2026-07-23T07:00:00.000Z"),
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const first = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOMER_WINS",
      policyReason: "Service failed",
      resolutionAttemptId: "attempt-1",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });
  const second = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOMER_WINS",
      policyReason: "Service failed",
      resolutionAttemptId: "attempt-1",
    },
    authoritativeNow: new Date("2026-07-23T08:01:00.000Z"),
  });

  assert.equal(first.ok, true);
  assert.equal(first.idempotentReplay, false);
  assert.equal(second.idempotentReplay, true);
  assert.equal(
    firestore.store.get(`disputes/${bookingId}`).status,
    "RESOLVED",
  );
  assert.equal(
    firestore.store.get(`refunds/${bookingId}`).state,
    "required",
  );
});

test("conflicting second dispute resolution is rejected", async () => {
  const bookingId = "booking-dispute-2";
  const booking = buildOpenDisputeBooking();
  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "PROVIDER_WINS",
      policyReason: "Evidence validated",
      resolutionAttemptId: "attempt-a",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  await assert.rejects(
    () =>
      resolveBookingDisputeV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOMER_WINS",
          policyReason: "Conflicting retry",
          resolutionAttemptId: "attempt-b",
        },
        authoritativeNow: new Date("2026-07-23T08:05:00.000Z"),
      }),
    /already been resolved with a different outcome/i,
  );
});

test("provider payout processing remains source-complete but live-disabled by default", async () => {
  const bookingId = "booking-payout-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.payout.status = "READY";
  booking.payout.eligibleAt = new Date("2026-07-23T04:10:00.000Z");
  booking.payout.releasedAt = null;
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise =
    booking.financials.providerPayoutPaise;

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`providerPayouts/${bookingId}`]: {
      payoutId: bookingId,
      bookingId,
      providerId: booking.providerId,
      status: "READY",
      eligibleAt: {seconds: "bad-value"},
      providerEntitlementPaise: booking.financials.providerPayoutPaise,
      remainingPayablePaise: booking.financials.providerPayoutPaise,
    },
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  const result = await processProviderPayoutV3({
    firestore,
    bookingId,
    processorLeaseOwner: "worker-1",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "LIVE_PAYOUT_DISABLED");
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).status,
    "FAILED",
  );
});

test("provider payout processing normalizes Firestore Timestamp eligibleAt values", async () => {
  const bookingId = "booking-payout-timestamp-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = Timestamp.fromDate(new Date("2026-07-23T05:10:00.000Z"));
  booking.payout.status = "READY";
  booking.payout.eligibleAt = Timestamp.fromDate(new Date("2026-07-23T04:10:00.000Z"));
  booking.payout.releasedAt = null;
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise =
    booking.financials.providerPayoutPaise;
  booking.createdAt = Timestamp.fromDate(booking.createdAt);
  booking.updatedAt = Timestamp.fromDate(booking.updatedAt);
  booking.serviceAnchorAt = Timestamp.fromDate(booking.serviceAnchorAt);
  booking.completedAt = Timestamp.fromDate(booking.completedAt);
  booking.lifecycle.completedAt = Timestamp.fromDate(booking.lifecycle.completedAt);
  booking.lifecycle.serviceEndedAt = Timestamp.fromDate(booking.lifecycle.serviceEndedAt);
  booking.lifecycle.disputeDeadlineAt = Timestamp.fromDate(booking.lifecycle.disputeDeadlineAt);
  booking.schedule.checkInDateTime = Timestamp.fromDate(booking.schedule.checkInDateTime);
  booking.schedule.checkOutDateTime = Timestamp.fromDate(booking.schedule.checkOutDateTime);
  booking.schedule.serviceAnchorAt = Timestamp.fromDate(booking.schedule.serviceAnchorAt);

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  const result = await processProviderPayoutV3({
    firestore,
    bookingId,
    processorLeaseOwner: "worker-ts",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "LIVE_PAYOUT_DISABLED");
});

test("provider payout processing accepts serialized timestamp shapes from canonical records", async () => {
  const bookingId = "booking-payout-serialized-1";
  const booking = buildCompletedFinalBookingFixture();
  const eligibleAt = new Date("2026-07-23T04:10:00.000Z");
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = {seconds: 1784783400, nanoseconds: 0};
  booking.payout.status = "READY";
  booking.payout.eligibleAt = {
    seconds: Math.floor(eligibleAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.payout.releasedAt = null;
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise =
    booking.financials.providerPayoutPaise;
  booking.createdAt = {
    seconds: Math.floor(booking.createdAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.updatedAt = {
    seconds: Math.floor(booking.updatedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.serviceAnchorAt = {
    seconds: Math.floor(booking.serviceAnchorAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.completedAt = {
    seconds: Math.floor(booking.completedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.lifecycle.completedAt = {
    seconds: Math.floor(booking.lifecycle.completedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.lifecycle.serviceEndedAt = {
    seconds: Math.floor(booking.lifecycle.serviceEndedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.lifecycle.disputeDeadlineAt = {
    seconds: Math.floor(booking.lifecycle.disputeDeadlineAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.schedule.checkInDateTime = {
    seconds: Math.floor(booking.schedule.checkInDateTime.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.schedule.checkOutDateTime = {
    seconds: Math.floor(booking.schedule.checkOutDateTime.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.schedule.serviceAnchorAt = {
    seconds: Math.floor(booking.schedule.serviceAnchorAt.getTime() / 1000),
    nanoseconds: 0,
  };

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  const result = await processProviderPayoutV3({
    firestore,
    bookingId,
    processorLeaseOwner: "worker-serialized",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "LIVE_PAYOUT_DISABLED");
});

test("provider payout processing does not crash when payout eligibleAt is malformed but payout execution remains disabled", async () => {
  const bookingId = "booking-payout-invalid-ts-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.lifecycle.finalizedAt = null;
  booking.payout.status = "READY";
  booking.payout.eligibleAt = {seconds: "bad-value"};
  booking.payout.releasedAt = null;
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise =
    booking.financials.providerPayoutPaise;

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  const result = await processProviderPayoutV3({
    firestore,
    bookingId,
    processorLeaseOwner: "worker-invalid",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "LIVE_PAYOUT_DISABLED");
});

test("reconciliation detects missing base payment ledger entries and proposes safe repairs", async () => {
  const bookingId = "booking-reconcile-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.payout.status = "READY";

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await reconcileBookingFinancialsV3({
    firestore,
    bookingId,
    authoritativeNow: new Date("2026-07-23T09:30:00.000Z"),
  });

  assert.equal(result.status, "MISSING_ENTRY");
  assert.equal(result.action, "SAFE_AUTOMATIC_REPAIR");
  assert.ok(result.repairWrites.length >= 1);
});

test("customer-win dispute on 100 percent Pettxo coupon never issues cash refund above customer paid", async () => {
  const bookingId = "booking-dispute-coupon-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 0;
  booking.financials.pettxoCouponFundingPaise = booking.financials.serviceSubtotalPaise;
  booking.financials.providerPayoutPaise = 20000;
  booking.financials.platformCommissionPaise = 0;
  booking.financials.pettxoNetBeforeGatewayPaise = 0;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1200",
    },
  });

  const result = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOMER_WINS",
      policyReason: "Platform-funded booking failed",
      resolutionAttemptId: "attempt-coupon",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(result.customerRefundPaise, 0);
  assert.equal(result.providerFinalEntitlementPaise, 0);
  assert.equal(firestore.store.has(`refunds/${bookingId}`), false);
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).remainingPayablePaise,
    0,
  );
});

test("legacy partial refund dispute input remains normalized safely", async () => {
  const bookingId = "booking-dispute-partial-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 50000;
  booking.financials.providerPayoutPaise = 30000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`refunds/${bookingId}`]: {
      refundAmountPaise: 10000,
      state: "submitted",
      createdAt: new Date("2026-07-23T07:00:00.000Z"),
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const result = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "PARTIAL_REFUND",
      customerRefundPaise: 20000,
      policyReason: "Partial goodwill refund",
      resolutionAttemptId: "attempt-partial",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(result.customerRefundPaise, 20000);
  assert.equal(result.customerAllocationBasisPoints, 4000);
  assert.equal(
    firestore.store.get(`refunds/${bookingId}`).refundAmountPaise,
    20000,
  );
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).providerEntitlementPaise,
    30000,
  );
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).pettxoRetainedPaise,
    0,
  );
});

test("successful payout processing is exactly once across replay and writes one payout ledger entry", async () => {
  const bookingId = "booking-payout-success-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.payout.status = "READY";
  booking.payout.eligibleAt = new Date("2026-07-23T04:10:00.000Z");
  booking.payout.releasedAt = null;
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise = booking.financials.providerPayoutPaise;

  let gatewayCalls = 0;
  const gateway = {
    async executePayout() {
      gatewayCalls += 1;
      return {
        ok: true,
        status: "PAID",
        externalPayoutId: "payout_ext_1",
        externalTransactionId: "txn_ext_1",
      };
    },
  };

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  const first = await processProviderPayoutV3({
    firestore,
    bookingId,
    gateway,
    processorLeaseOwner: "worker-1",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });
  const replay = await processProviderPayoutV3({
    firestore,
    bookingId,
    gateway,
    processorLeaseOwner: "worker-2",
    authoritativeNow: new Date("2026-07-23T09:01:00.000Z"),
  });

  assert.equal(first.ok, true);
  assert.equal(first.code, "PAID");
  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
  assert.equal(gatewayCalls, 1);
  assert.equal(firestore.store.get(`providerPayouts/${bookingId}`).status, "PAID");
  assert.equal(
    firestore.store.get(`bookingFinancialLedger/${bookingId}_PROVIDER_PAYOUT_${bookingId}`).amountPaise,
    booking.financials.providerPayoutPaise,
  );
  assert.equal(
    firestore.store.get(
      `notifications/booking_payout_completed:${bookingId}:${booking.providerId}`,
    ).type,
    "booking_payout_completed",
  );
});

test("payout processing stays held and does not invoke gateway when refund is pending", async () => {
  const bookingId = "booking-payout-held-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.payout.status = "HELD";
  booking.payout.eligibleAt = new Date("2026-07-23T04:10:00.000Z");
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise = booking.financials.providerPayoutPaise;

  let gatewayCalls = 0;
  const gateway = {
    async executePayout() {
      gatewayCalls += 1;
      throw new Error("gateway should not be called");
    },
  };

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`refunds/${bookingId}`]: {
      state: "required",
      refundAmountPaise: 10000,
    },
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX4321",
    },
  });

  await assert.rejects(
    () =>
      processProviderPayoutV3({
        firestore,
        bookingId,
        gateway,
        processorLeaseOwner: "worker-hold",
        authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
      }),
    /refund is pending/i,
  );
  assert.equal(gatewayCalls, 0);
});

test("reconciliation flags stale ready payouts without issuing external money", async () => {
  const bookingId = "booking-reconcile-stale-ready-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-07-23T05:10:00.000Z");
  booking.payout.status = "READY";
  booking.payout.eligibleAt = new Date("2026-07-20T05:10:00.000Z");
  booking.payout.readyAt = new Date("2026-07-20T05:20:00.000Z");
  booking.payout.priorPaidPaise = 0;
  booking.payout.remainingPayablePaise = booking.financials.providerPayoutPaise;

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancialLedger/${bookingId}_PAYMENT_CAPTURED_${bookingId}`]: {
      entryId: `${bookingId}_PAYMENT_CAPTURED_${bookingId}`,
      bookingId,
      type: "PAYMENT_CAPTURED",
      amountPaise: booking.financials.customerPaidPaise,
      occurredAt: new Date("2026-07-23T05:10:00.000Z"),
      createdAt: new Date("2026-07-23T05:10:00.000Z"),
    },
    [`providerPayouts/${bookingId}`]: {
      payoutId: bookingId,
      bookingId,
      providerId: booking.providerId,
      status: "READY",
      providerEntitlementPaise: booking.financials.providerPayoutPaise,
      priorPaidPaise: 0,
      remainingPayablePaise: booking.financials.providerPayoutPaise,
      readyAt: new Date("2026-07-20T05:20:00.000Z"),
      createdAt: new Date("2026-07-20T05:20:00.000Z"),
      updatedAt: new Date("2026-07-20T05:20:00.000Z"),
    },
  });

  const result = await reconcileBookingFinancialsV3({
    firestore,
    bookingId,
    authoritativeNow: new Date("2026-07-23T09:30:00.000Z"),
  });

  assert.equal(result.status, "STALE_PAYOUT");
  assert.equal(result.action, "MANUAL_REVIEW_REQUIRED");
  assert.equal(result.repairWrites.length, 0);
});

test("retry payout batch does not crash on Firestore Timestamp retry fields", async () => {
  const bookingId = "booking-payout-batch-ts-1";
  const booking = buildCompletedFinalBookingFixture();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = Timestamp.fromDate(new Date("2026-07-23T05:10:00.000Z"));
  booking.payout.status = "FAILED";
  booking.payout.eligibleAt = Timestamp.fromDate(new Date("2026-07-23T04:10:00.000Z"));
  booking.payout.failedAt = Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z"));
  booking.payout.remainingPayablePaise = booking.financials.providerPayoutPaise;
  booking.createdAt = Timestamp.fromDate(booking.createdAt);
  booking.updatedAt = Timestamp.fromDate(booking.updatedAt);
  booking.serviceAnchorAt = Timestamp.fromDate(booking.serviceAnchorAt);
  booking.completedAt = Timestamp.fromDate(booking.completedAt);
  booking.lifecycle.completedAt = Timestamp.fromDate(booking.lifecycle.completedAt);
  booking.lifecycle.serviceEndedAt = Timestamp.fromDate(booking.lifecycle.serviceEndedAt);
  booking.lifecycle.disputeDeadlineAt = Timestamp.fromDate(booking.lifecycle.disputeDeadlineAt);
  booking.schedule.checkInDateTime = Timestamp.fromDate(booking.schedule.checkInDateTime);
  booking.schedule.checkOutDateTime = Timestamp.fromDate(booking.schedule.checkOutDateTime);
  booking.schedule.serviceAnchorAt = Timestamp.fromDate(booking.schedule.serviceAnchorAt);

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`providerPayouts/${bookingId}`]: {
      payoutId: bookingId,
      bookingId,
      providerId: booking.providerId,
      status: "FAILED",
      providerEntitlementPaise: booking.financials.providerPayoutPaise,
      priorPaidPaise: 0,
      remainingPayablePaise: booking.financials.providerPayoutPaise,
      eligibleAt: Timestamp.fromDate(new Date("2026-07-23T04:10:00.000Z")),
      nextRetryAt: Timestamp.fromDate(new Date("2026-07-23T08:30:00.000Z")),
      createdAt: Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-07-23T08:00:00.000Z")),
    },
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX9999",
    },
  });

  const results = await processRetryableProviderPayoutBatchV3({
    firestore,
    processorLeaseOwner: "batch-worker",
    authoritativeNow: new Date("2026-07-23T09:00:00.000Z"),
  });

  assert.equal(results.length, 1);
  assert.equal(results[0].ok, false);
  assert.equal(results[0].code, "LIVE_PAYOUT_DISABLED");
});

test("super admin can resolve disputes while customer support is denied", async () => {
  const bookingId = "booking-dispute-auth-super";
  const booking = buildOpenDisputeBooking();
  const baseSeed = {
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  };

  const superAdminFirestore = new FakeFirestore({
    ...baseSeed,
    ["users/admin-super"]: {adminRole: "superAdmin"},
  });
  const superAdminResult = await resolveBookingDisputeV3({
    firestore: superAdminFirestore,
    auth: {uid: "admin-super"},
    input: {
      disputeId: bookingId,
      resolutionType: "PROVIDER_WINS",
      policyReason: "Evidence favored provider",
      resolutionAttemptId: "super-auth-1",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });
  assert.equal(superAdminResult.ok, true);

  const supportFirestore = new FakeFirestore({
    ...baseSeed,
    ["users/admin-support"]: {adminRole: "customerSupportAdmin"},
  });
  await assert.rejects(
    () =>
      resolveBookingDisputeV3({
        firestore: supportFirestore,
        auth: {uid: "admin-support"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOMER_WINS",
          policyReason: "Support should not resolve",
          resolutionAttemptId: "support-auth-1",
        },
        authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
      }),
    /finance admin access required/i,
  );
});

test("ordinary user cannot resolve disputes and preview supports three-party basis points", async () => {
  const bookingId = "booking-dispute-auth-user";
  const booking = buildOpenDisputeBooking();
  const firestore = new FakeFirestore({
    [`users/admin-finance`]: {adminRole: "financeAdmin"},
    [`users/user-1`]: {adminRole: ""},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  await assert.rejects(
    () =>
      resolveBookingDisputeV3({
        firestore,
        auth: {uid: "user-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOMER_WINS",
          policyReason: "User should not resolve",
          resolutionAttemptId: "user-auth-1",
        },
        authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
      }),
    /finance admin access required/i,
  );

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-finance"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Three-party preview",
      resolutionAttemptId: "preview-only",
      customerAllocationBasisPoints: 4000,
      providerAllocationBasisPoints: 5000,
      pettxoAllocationBasisPoints: 1000,
    },
  });

  assert.equal(preview.customerAllocationBasisPoints, 4000);
  assert.equal(preview.providerAllocationBasisPoints, 5000);
  assert.equal(preview.pettxoAllocationBasisPoints, 1000);
  assert.equal(
    preview.customerFinalPaise,
    Math.floor((booking.financials.customerPaidPaise * 4000) / 10000),
  );
  assert.equal(
    preview.providerAllocationPaise,
    Math.floor((booking.financials.customerPaidPaise * 5000) / 10000),
  );
  assert.equal(preview.providerFinalEntitlementPaise, preview.providerAllocationPaise);
  assert.equal(
    preview.pettxoFinalRetainedPaise,
    booking.financials.customerPaidPaise -
      preview.customerFinalPaise -
      preview.providerAllocationPaise,
  );
  assert.equal(preview.refundToIssuePaise, preview.customerFinalPaise);
});

test("three-party custom allocation preview and final resolution stay consistent", async () => {
  const bookingId = "booking-dispute-custom-allocation-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 100000;
  booking.financials.providerPayoutPaise = 85000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const input = {
    disputeId: bookingId,
    resolutionType: "CUSTOM_ALLOCATION",
    policyReason: "Shared accountability",
    notes: "Customer 40, provider 50, Pettxo 10",
    resolutionAttemptId: "custom-allocation-1",
    customerAllocationBasisPoints: 4000,
    providerAllocationBasisPoints: 5000,
    pettxoAllocationBasisPoints: 1000,
  };

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input,
  });
  const result = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input,
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(preview.customerFinalPaise, 40000);
  assert.equal(preview.providerAllocationPaise, 50000);
  assert.equal(preview.providerFinalEntitlementPaise, 50000);
  assert.equal(preview.pettxoFinalRetainedPaise, 10000);
  assert.equal(preview.refundToIssuePaise, 40000);
  assert.equal(result.customerFinalPaise, preview.customerFinalPaise);
  assert.equal(result.providerAllocationPaise, preview.providerAllocationPaise);
  assert.equal(
    result.providerFinalEntitlementPaise,
    preview.providerFinalEntitlementPaise,
  );
  assert.equal(
    result.pettxoFinalRetainedPaise,
    preview.pettxoFinalRetainedPaise,
  );
  assert.equal(result.refundToIssuePaise, preview.refundToIssuePaise);
});

test("three-party allocation rejects sums above or below 100 percent", async () => {
  const bookingId = "booking-dispute-invalid-sum-1";
  const booking = buildOpenDisputeBooking();
  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
  });

  await assert.rejects(
    () =>
      previewBookingDisputeResolutionV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Invalid 110 percent",
          resolutionAttemptId: "invalid-over",
          customerAllocationBasisPoints: 4000,
          providerAllocationBasisPoints: 5000,
          pettxoAllocationBasisPoints: 2000,
        },
      }),
    /must equal 10000/i,
  );

  await assert.rejects(
    () =>
      previewBookingDisputeResolutionV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Invalid 85 percent",
          resolutionAttemptId: "invalid-under",
          customerAllocationBasisPoints: 4000,
          providerAllocationBasisPoints: 4000,
          pettxoAllocationBasisPoints: 500,
        },
      }),
    /must equal 10000/i,
  );
});

test("existing refunds are treated as cumulative final customer allocation", async () => {
  const bookingId = "booking-dispute-existing-refund-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 100000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`refunds/${bookingId}`]: {
      refundAmountPaise: 20000,
      state: "processed",
      createdAt: new Date("2026-07-23T07:00:00.000Z"),
      updatedAt: new Date("2026-07-23T07:10:00.000Z"),
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Customer keeps half",
      resolutionAttemptId: "existing-refund-preview",
      customerAllocationBasisPoints: 5000,
      providerAllocationBasisPoints: 4000,
      pettxoAllocationBasisPoints: 1000,
    },
  });
  assert.equal(preview.customerFinalPaise, 50000);
  assert.equal(preview.refundToIssuePaise, 30000);

  await assert.rejects(
    () =>
      previewBookingDisputeResolutionV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Customer below already refunded amount",
          resolutionAttemptId: "existing-refund-invalid",
          customerAllocationBasisPoints: 1000,
          providerAllocationBasisPoints: 8000,
          pettxoAllocationBasisPoints: 1000,
        },
      }),
    /cannot be less than the amount already refunded/i,
  );
});

test("existing provider payout blocks lower final entitlement without clawback flow", async () => {
  const bookingId = "booking-dispute-provider-paid-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 100000;
  booking.financials.providerPayoutPaise = 85000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`providerPayouts/${bookingId}`]: {
      payoutId: bookingId,
      bookingId,
      providerId: booking.providerId,
      providerEntitlementPaise: 85000,
      priorPaidPaise: 45000,
      remainingPayablePaise: 40000,
      status: "HELD",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Provider keeps half",
      resolutionAttemptId: "provider-paid-preview",
      customerAllocationBasisPoints: 4000,
      providerAllocationBasisPoints: 5000,
      pettxoAllocationBasisPoints: 1000,
    },
  });
  assert.equal(preview.providerFinalEntitlementPaise, 50000);
  assert.equal(preview.providerRemainingPayablePaise, 5000);

  await assert.rejects(
    () =>
      previewBookingDisputeResolutionV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Provider below already paid",
          resolutionAttemptId: "provider-paid-invalid",
          customerAllocationBasisPoints: 7000,
          providerAllocationBasisPoints: 2500,
          pettxoAllocationBasisPoints: 500,
        },
      }),
    /cannot be less than the amount already paid/i,
  );
});

test("three-party allocation rounding stays exact with uneven paise", async () => {
  const bookingId = "booking-dispute-rounding-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 99999;
  booking.financials.providerPayoutPaise = 60000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
  });

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Rounding audit",
      resolutionAttemptId: "rounding-preview",
      customerAllocationBasisPoints: 3333,
      providerAllocationBasisPoints: 3333,
      pettxoAllocationBasisPoints: 3334,
    },
  });

  assert.equal(
    preview.customerFinalPaise +
      preview.providerAllocationPaise +
      preview.pettxoFinalRetainedPaise,
    99999,
  );
});

test("coupon-aware provider wins preserves canonical provider entitlement while custom allocation only splits the customer-paid pool", async () => {
  const bookingId = "booking-dispute-coupon-preset-1";
  const booking = buildOpenDisputeBooking();
  booking.financials.customerPaidPaise = 80000;
  booking.financials.providerPayoutPaise = 85000;
  booking.financials.platformCommissionPaise = 15000;
  booking.financials.pettxoCouponFundingPaise = 20000;
  booking.financials.pettxoNetBeforeGatewayPaise = -5000;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1200",
    },
  });

  const providerWins = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "PROVIDER_WINS",
      policyReason: "Provider completed service",
      resolutionAttemptId: "provider-wins-coupon",
    },
  });
  assert.equal(providerWins.providerAllocationPaise, 80000);
  assert.equal(providerWins.providerFinalEntitlementPaise, 85000);
  assert.equal(providerWins.providerCouponSubsidyPaise, 5000);
  assert.equal(providerWins.pettxoFinalRetainedPaise, 0);

  const customAllocation = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Shared coupon dispute allocation",
      resolutionAttemptId: "coupon-custom-1",
      customerAllocationBasisPoints: 4000,
      providerAllocationBasisPoints: 5000,
      pettxoAllocationBasisPoints: 1000,
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(customAllocation.customerFinalPaise, 32000);
  assert.equal(customAllocation.providerAllocationPaise, 40000);
  assert.equal(customAllocation.providerFinalEntitlementPaise, 40000);
  assert.equal(customAllocation.pettxoFinalRetainedPaise, 8000);
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).couponCostPaise,
    20000,
  );
});

test("legacy dispute missing provider entitlement context returns failed-precondition instead of internal", async () => {
  const bookingId = "booking-dispute-legacy-shape-1";
  const booking = buildOpenDisputeBooking();
  delete booking.financials.providerPayoutPaise;

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
  });

  await assert.rejects(
    () =>
      previewBookingDisputeResolutionV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Legacy context check",
          resolutionAttemptId: "legacy-shape-preview",
          customerAllocationBasisPoints: 4000,
          providerAllocationBasisPoints: 5000,
          pettxoAllocationBasisPoints: 1000,
        },
      }),
    /Financial settlement context is incomplete for this booking/i,
  );
});

test("resolve dispute accepts Firestore Timestamp payout eligibility dates for all final resolution types", async () => {
  const resolutionCases = [
    {
      bookingId: "booking-dispute-ts-customer",
      resolutionType: "CUSTOMER_WINS",
      policyReason: "Customer wins timestamp path",
      extraInput: {},
    },
    {
      bookingId: "booking-dispute-ts-provider",
      resolutionType: "PROVIDER_WINS",
      policyReason: "Provider wins timestamp path",
      extraInput: {},
    },
    {
      bookingId: "booking-dispute-ts-custom",
      resolutionType: "CUSTOM_ALLOCATION",
      policyReason: "Custom allocation timestamp path",
      extraInput: {
        customerAllocationBasisPoints: 4000,
        providerAllocationBasisPoints: 5000,
        pettxoAllocationBasisPoints: 1000,
      },
    },
  ];

  for (const testCase of resolutionCases) {
    const booking = buildOpenDisputeBooking();
    booking.lifecycle.paidAt = Timestamp.fromDate(
      new Date("2026-07-23T05:10:00.000Z"),
    );
    booking.payout.eligibleAt = Timestamp.fromDate(
      new Date("2026-07-24T06:10:00.000Z"),
    );
    const firestore = new FakeFirestore({
      [`users/admin-1`]: {adminRole: "financeAdmin"},
      [`bookings/${testCase.bookingId}`]: booking,
      [`disputes/${testCase.bookingId}`]: {
        disputeId: testCase.bookingId,
        bookingId: testCase.bookingId,
        providerId: booking.providerId,
        parentId: booking.parentId,
        customerId: booking.parentId,
        status: "OPEN",
        source: "canonical_v3",
      },
      [`bookingFinancials/${testCase.bookingId}`]: {},
      [`providerEarnings/${testCase.bookingId}`]: {},
      [`payoutReadiness/${testCase.bookingId}`]: {},
      [`users/${booking.providerId}/providerBankDetails/main`]: {
        status: "submitted",
        accountNumberMasked: "XXXX1234",
      },
    });

    const result = await resolveBookingDisputeV3({
      firestore,
      auth: {uid: "admin-1"},
      input: {
        disputeId: testCase.bookingId,
        resolutionType: testCase.resolutionType,
        policyReason: testCase.policyReason,
        resolutionAttemptId: `${testCase.bookingId}-attempt-1`,
        ...testCase.extraInput,
      },
      authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
    });

    assert.equal(result.ok, true);
    assert.equal(result.disputeStatus, "RESOLVED");
    assert.equal(
      firestore.store.get(`providerPayouts/${testCase.bookingId}`).eligibleAt
        instanceof Timestamp,
      true,
    );
  }
});

test("resolve dispute accepts timestamp-like ledger source timestamps", async () => {
  const bookingId = "booking-dispute-ledger-timestamp-like";
  const booking = buildOpenDisputeBooking();
  booking.lifecycle.paidAt = {
    toDate: () => new Date("2026-07-23T05:10:00.000Z"),
  };

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const result = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "CUSTOMER_WINS",
      policyReason: "Timestamp-like ledger source",
      resolutionAttemptId: "ledger-timestamp-like",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(result.ok, true);
  assert.equal(
    firestore.store.get(
      `bookingFinancialLedger/${bookingId}_PAYMENT_CAPTURED_${booking.payment.paymentAttemptId}`,
    ).occurredAt instanceof Timestamp,
    true,
  );
});

test("resolve dispute accepts Firestore Timestamp finalizedAt fallback when payout eligibleAt is missing", async () => {
  const bookingId = "booking-dispute-ts-finalized-fallback";
  const booking = buildOpenDisputeBooking();
  booking.payout.eligibleAt = null;
  booking.lifecycle.finalizedAt = Timestamp.fromDate(
    new Date("2026-07-23T05:55:00.000Z"),
  );

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  const preview = await previewBookingDisputeResolutionV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "PROVIDER_WINS",
      policyReason: "Finalized timestamp fallback",
      resolutionAttemptId: "preview-finalized-fallback",
    },
  });

  const result = await resolveBookingDisputeV3({
    firestore,
    auth: {uid: "admin-1"},
    input: {
      disputeId: bookingId,
      resolutionType: "PROVIDER_WINS",
      policyReason: "Finalized timestamp fallback",
      resolutionAttemptId: "resolve-finalized-fallback",
    },
    authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
  });

  assert.equal(result.customerRefundPaise, preview.customerRefundPaise);
  assert.equal(
    result.providerFinalEntitlementPaise,
    preview.providerFinalEntitlementPaise,
  );
  assert.equal(
    firestore.store.get(`providerPayouts/${bookingId}`).eligibleAt
      instanceof Timestamp,
    true,
  );
});

test("resolve dispute rejects malformed payout timestamps before any financial writes are committed", async () => {
  const bookingId = "booking-dispute-bad-timestamp";
  const booking = buildOpenDisputeBooking();
  booking.payout.eligibleAt = {seconds: "bad-seconds"};

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  await assert.rejects(
    () =>
      resolveBookingDisputeV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOMER_WINS",
          policyReason: "Malformed timestamp guard",
          resolutionAttemptId: "bad-timestamp-attempt",
        },
        authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
      }),
    /bookings\.payout\.eligibleAt is missing or malformed/i,
  );

  assert.equal(
    firestore.store.has(`bookingDisputeResolutions/resolution_${bookingId}`),
    false,
  );
  assert.equal(
    firestore.store.has(`providerPayouts/${bookingId}`),
    false,
  );
  assert.equal(
    firestore.store.has(`refunds/${bookingId}`),
    false,
  );
  assert.equal(firestore.store.get(`disputes/${bookingId}`).status, "OPEN");
});

test("resolve dispute rejects malformed ledger source timestamps before any financial writes are committed", async () => {
  const bookingId = "booking-dispute-bad-ledger-timestamp";
  const booking = buildOpenDisputeBooking();
  booking.lifecycle.paidAt = {seconds: "bad-seconds"};

  const firestore = new FakeFirestore({
    [`users/admin-1`]: {adminRole: "financeAdmin"},
    [`bookings/${bookingId}`]: booking,
    [`disputes/${bookingId}`]: {
      disputeId: bookingId,
      bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      customerId: booking.parentId,
      status: "OPEN",
      source: "canonical_v3",
    },
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`users/${booking.providerId}/providerBankDetails/main`]: {
      status: "submitted",
      accountNumberMasked: "XXXX1234",
    },
  });

  await assert.rejects(
    () =>
      resolveBookingDisputeV3({
        firestore,
        auth: {uid: "admin-1"},
        input: {
          disputeId: bookingId,
          resolutionType: "CUSTOM_ALLOCATION",
          policyReason: "Malformed ledger timestamp guard",
          resolutionAttemptId: "bad-ledger-timestamp-attempt",
          customerAllocationBasisPoints: 4000,
          providerAllocationBasisPoints: 5000,
          pettxoAllocationBasisPoints: 1000,
        },
        authoritativeNow: new Date("2026-07-23T08:00:00.000Z"),
      }),
    /bookingFinancialLedger\.occurredAt is missing or malformed/i,
  );

  assert.equal(
    firestore.store.has(`bookingDisputeResolutions/resolution_${bookingId}`),
    false,
  );
  assert.equal(
    firestore.store.has(`providerPayouts/${bookingId}`),
    false,
  );
  assert.equal(
    firestore.store.has(`bookingFinancialLedger/${bookingId}_PAYMENT_CAPTURED_${booking.payment.paymentAttemptId}`),
    false,
  );
  assert.equal(firestore.store.get(`disputes/${bookingId}`).status, "OPEN");
});
