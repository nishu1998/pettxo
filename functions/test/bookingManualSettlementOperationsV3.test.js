const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");

const {
  listManualSettlementObligationsDataV3,
  getManualSettlementObligationDetailDataV3,
  revealManualSettlementProviderDestinationDataV3,
  recordManualProviderPayoutDataV3,
  recordManualCustomerRefundDataV3,
  materializeManualSettlementObligationsForBookingDataV3,
} = require("../lib/booking/bookingManualSettlementOperationsV3.js");
const {
  submitRefundInstructionV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");
const razorpayGateway = require("../lib/booking/application/razorpayGateway.js");
const {
  buildCompletedFinalBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");

function getByPath(source, fieldPath) {
  return fieldPath.split(".").reduce((value, segment) => {
    if (value == null || typeof value !== "object") return undefined;
    return value[segment];
  }, source);
}

function comparableValue(value) {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return value;
}

class FakeDocSnapshot {
  constructor(firestore, path, data) {
    this.firestore = firestore;
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

  get(fieldPath) {
    return getByPath(this._data, fieldPath);
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.empty = docs.length === 0;
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

  async get() {
    return new FakeDocSnapshot(this.firestore, this.path, this.firestore.store.get(this.path));
  }

  set(data, options) {
    this.firestore._set(this.path, data, options);
    return Promise.resolve();
  }

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }
}

class FakeQuery {
  constructor(firestore, path, options = {}) {
    this.firestore = firestore;
    this.path = path;
    this.filters = options.filters ?? [];
    this.orderings = options.orderings ?? [];
    this.limitValue = options.limitValue ?? null;
  }

  where(field, op, value) {
    return new FakeQuery(this.firestore, this.path, {
      filters: [...this.filters, {field, op, value}],
      orderings: this.orderings,
      limitValue: this.limitValue,
    });
  }

  orderBy(field, direction = "asc") {
    return new FakeQuery(this.firestore, this.path, {
      filters: this.filters,
      orderings: [...this.orderings, {field, direction}],
      limitValue: this.limitValue,
    });
  }

  limit(value) {
    return new FakeQuery(this.firestore, this.path, {
      filters: this.filters,
      orderings: this.orderings,
      limitValue: value,
    });
  }

  async get() {
    const prefix = `${this.path}/`;
    let docs = [...this.firestore.store.entries()]
      .filter(([path]) => path.startsWith(prefix))
      .filter(([path]) => path.split("/").length === this.path.split("/").length + 1)
      .map(([path, data]) => new FakeDocSnapshot(this.firestore, path, data));

    docs = docs.filter((doc) => this.filters.every((filter) => {
      const actual = comparableValue(doc.get(filter.field));
      const expected = comparableValue(filter.value);
      switch (filter.op) {
      case "==":
        return actual === expected;
      case "<=":
        return actual <= expected;
      case "<":
        return actual < expected;
      case ">=":
        return actual >= expected;
      default:
        throw new Error(`Unsupported op: ${filter.op}`);
      }
    }));

    if (this.orderings.length > 0) {
      docs.sort((left, right) => {
        for (const ordering of this.orderings) {
          const a = comparableValue(left.get(ordering.field));
          const b = comparableValue(right.get(ordering.field));
          if (a === b) continue;
          return ordering.direction === "desc" ? (a < b ? 1 : -1) : (a < b ? -1 : 1);
        }
        return left.id.localeCompare(right.id);
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
    this.firestore = firestore;
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

function validSummary() {
  return {
    status: "submitted",
    schemaVersion: 3,
    hasBankAccount: true,
    hasUpi: true,
    preferredPayoutMethod: "BANK_ACCOUNT",
    accountHolderName: "Pettxo Provider",
    bankName: "Axis Bank",
    accountType: "SAVINGS",
    accountNumberMasked: "••••4321",
    upiId: "pe****@oksbi",
  };
}

function validSensitive() {
  return {
    userId: "provider-1",
    schemaVersion: 1,
    hasBankAccount: true,
    hasUpi: true,
    preferredPayoutMethod: "BANK_ACCOUNT",
    bankAccount: {
      accountHolderName: "Pettxo Provider",
      bankName: "Axis Bank",
      accountType: "SAVINGS",
      accountNumber: "1234567894321",
      ifscCode: "UTIB0000123",
    },
    upi: {
      upiId: "provider@oksbi",
    },
  };
}

function buildBaseBooking() {
  const booking = buildCompletedFinalBookingFixture();
  booking.bookingIdSearchKey = "booking-1";
  booking.parentId = "customer-1";
  booking.customerId = "customer-1";
  booking.providerId = "provider-1";
  booking.serviceOwnerId = "provider-1";
  booking.participants.parent.parentId = "customer-1";
  booking.participants.provider.providerId = "provider-1";
  booking.participants.provider.displayName = "Provider One";
  booking.participants.parent.displayFirstName = "Nisha";
  booking.participants.parent.lastInitial = "G";
  booking.service.serviceTitle = "Pet Grooming";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-08-20T09:00:00.000Z");
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.dispute.status = "none";
  return booking;
}

function buildObligation(overrides = {}) {
  return {
    obligationId: "provider_payout_booking-1",
    bookingId: "booking-1",
    disputeId: "",
    disputeResolutionId: "",
    recipientType: "PROVIDER",
    obligationType: "PROVIDER_PAYOUT",
    recipientUserId: "provider-1",
    amountPaise: 8500,
    currency: "INR",
    source: "NORMAL_COMPLETION",
    status: "READY",
    financialSettlementStatus: "PENDING",
    reasonCode: "NORMAL_PROVIDER_PAYOUT",
    holdReason: "",
    relatedPayoutId: "booking-1",
    relatedRefundId: "",
    paymentAttemptId: "attempt-1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_1",
    createdAt: Timestamp.fromDate(new Date("2026-08-20T10:00:00.000Z")),
    updatedAt: Timestamp.fromDate(new Date("2026-08-20T10:00:00.000Z")),
    readyAt: Timestamp.fromDate(new Date("2026-08-20T10:00:00.000Z")),
    completedAt: null,
    completedByAdminUid: "",
    metadata: {},
    ...overrides,
  };
}

function buildSeed() {
  const booking = buildBaseBooking();
  booking.financials.customerPaidPaise = 10000;
  booking.financials.serviceSubtotalPaise = 11000;
  booking.financials.pettxoCouponFundingPaise = 1000;
  booking.financials.providerPayoutPaise = 8500;
  booking.financials.platformCommissionPaise = 1500;

  const disputeBooking = structuredClone(booking);
  disputeBooking.bookingIdSearchKey = "booking-2";
  disputeBooking.service.serviceTitle = "Pet Walking";
  disputeBooking.state = "COMPLETED_FINAL";
  disputeBooking.dispute = {
    ...disputeBooking.dispute,
    disputeId: "booking-2",
    status: "RESOLVED",
    resolution: "PARTIAL_REFUND",
  };

  const paidBooking = structuredClone(booking);
  paidBooking.bookingIdSearchKey = "booking-3";

  return new FakeFirestore({
    "users/super-1": {adminRole: "superAdmin"},
    "users/finance-1": {adminRole: "financeAdmin"},
    "users/support-1": {adminRole: "customerSupportAdmin"},
    "users/customer-1": {},
    "users/provider-1/providerBankDetails/main": validSummary(),
    "users/provider-1/providerPayoutSensitive/main": validSensitive(),
    "bookings/booking-1": booking,
    "bookings/booking-2": disputeBooking,
    "bookings/booking-3": paidBooking,
    "manualSettlementObligations/provider_payout_booking-1": buildObligation(),
    "manualSettlementObligations/customer_refund_resolution_booking-2": buildObligation({
      obligationId: "customer_refund_resolution_booking-2",
      bookingId: "booking-2",
      disputeId: "booking-2",
      disputeResolutionId: "resolution_booking-2",
      recipientType: "CUSTOMER",
      obligationType: "CUSTOMER_REFUND",
      recipientUserId: "customer-1",
      amountPaise: 3000,
      source: "DISPUTE_RESOLUTION",
      reasonCode: "DISPUTE_CUSTOMER_REFUND",
      relatedRefundId: "booking-2",
      status: "READY",
      razorpayOrderId: "order_2",
      razorpayPaymentId: "pay_2",
      paymentAttemptId: "attempt-2",
      createdAt: Timestamp.fromDate(new Date("2026-08-21T10:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-21T10:00:00.000Z")),
      readyAt: Timestamp.fromDate(new Date("2026-08-21T10:00:00.000Z")),
    }),
    "manualSettlementObligations/provider_payout_booking-2": buildObligation({
      obligationId: "provider_payout_booking-2",
      bookingId: "booking-2",
      disputeId: "booking-2",
      disputeResolutionId: "resolution_booking-2",
      amountPaise: 5500,
      source: "DISPUTE_RESOLUTION",
      reasonCode: "DISPUTE_PROVIDER_PAYOUT",
      relatedRefundId: "booking-2",
      createdAt: Timestamp.fromDate(new Date("2026-08-21T09:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-21T09:00:00.000Z")),
      readyAt: Timestamp.fromDate(new Date("2026-08-21T09:00:00.000Z")),
    }),
    "manualSettlementObligations/provider_payout_booking-3": buildObligation({
      obligationId: "provider_payout_booking-3",
      bookingId: "booking-3",
      amountPaise: 7000,
      status: "COMPLETED",
      financialSettlementStatus: "COMPLETED",
      createdAt: Timestamp.fromDate(new Date("2026-08-22T09:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-22T12:00:00.000Z")),
      completedAt: Timestamp.fromDate(new Date("2026-08-22T12:00:00.000Z")),
      metadata: {manualTransactionReference: "utr-existing"},
    }),
    "providerPayouts/booking-1": {
      payoutId: "booking-1",
      bookingId: "booking-1",
      providerId: "provider-1",
      status: "READY",
      providerEntitlementPaise: 8500,
      priorPaidPaise: 0,
      remainingPayablePaise: 8500,
      currency: "INR",
      createdAt: Timestamp.fromDate(new Date("2026-08-20T10:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-20T10:00:00.000Z")),
    },
    "providerPayouts/booking-2": {
      payoutId: "booking-2",
      bookingId: "booking-2",
      providerId: "provider-1",
      status: "READY",
      providerEntitlementPaise: 5500,
      priorPaidPaise: 0,
      remainingPayablePaise: 5500,
      currency: "INR",
      createdAt: Timestamp.fromDate(new Date("2026-08-21T09:00:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-21T09:00:00.000Z")),
    },
    "providerPayouts/booking-3": {
      payoutId: "booking-3",
      bookingId: "booking-3",
      providerId: "provider-1",
      status: "PAID",
      providerEntitlementPaise: 7000,
      priorPaidPaise: 7000,
      remainingPayablePaise: 0,
      currency: "INR",
    },
    "payoutReadiness/booking-1": {
      status: "READY",
      payoutStatus: "READY",
      manualSettlementStatus: "READY",
    },
    "payoutReadiness/booking-2": {
      status: "READY",
      payoutStatus: "READY",
      manualSettlementStatus: "READY",
    },
    "providerEarnings/booking-1": {
      status: "READY",
      amountPaise: 8500,
    },
    "providerEarnings/booking-2": {
      status: "READY",
      amountPaise: 5500,
    },
    "refunds/booking-2": {
      bookingId: "booking-2",
      paymentAttemptId: "attempt-2",
      refundAmountPaise: 3000,
      state: "pending",
      executionMode: "MANUAL",
      origin: "DISPUTE_RESOLUTION",
      createdAt: Timestamp.fromDate(new Date("2026-08-21T08:50:00.000Z")),
      updatedAt: Timestamp.fromDate(new Date("2026-08-21T08:50:00.000Z")),
    },
    "bookingDisputeResolutions/resolution_booking-2": {
      resolutionId: "resolution_booking-2",
      bookingId: "booking-2",
      disputeId: "booking-2",
      resolutionType: "PARTIAL_REFUND",
      customerRefundPaise: 3000,
      providerFinalEntitlementPaise: 5500,
      pettxoFinalRetainedPaise: 1500,
      financialSettlementStatus: "PENDING",
      manualSettlementObligationIds: [
        "provider_payout_booking-2",
        "customer_refund_resolution_booking-2",
      ],
    },
    "disputes/booking-2": {
      disputeId: "booking-2",
      bookingId: "booking-2",
      status: "RESOLVED",
      financialSettlementStatus: "PENDING",
      resolution: {
        type: "PARTIAL_REFUND",
        financialSettlementStatus: "PENDING",
        manualSettlementObligationIds: [
          "provider_payout_booking-2",
          "customer_refund_resolution_booking-2",
        ],
      },
    },
    "bookings/booking-2/paymentAttempts/attempt-2": {
      bookingId: "booking-2",
      paymentAttemptId: "attempt-2",
      state: "REFUND_PENDING",
      amountPaise: 3000,
      razorpayPaymentId: "pay_2",
      reconciliationAttemptCount: 0,
    },
  });
}

test("manual settlement operations reject non-super-admin callers", async () => {
  const firestore = buildSeed();
  await assert.rejects(
    () =>
      listManualSettlementObligationsDataV3({
        firestore,
        auth: null,
        input: {},
      }),
    /Sign in required/i,
  );
  await assert.rejects(
    () =>
      listManualSettlementObligationsDataV3({
        firestore,
        auth: {uid: "finance-1"},
        input: {},
      }),
    /Super Admin access required/i,
  );
  await assert.rejects(
    () =>
      listManualSettlementObligationsDataV3({
        firestore,
        auth: {uid: "support-1"},
        input: {},
      }),
    /(Finance admin access required|Super Admin access required)/i,
  );
  await assert.rejects(
    () =>
      listManualSettlementObligationsDataV3({
        firestore,
        auth: {uid: "customer-1"},
        input: {},
      }),
    /Finance admin access required/i,
  );
});

test("manual settlement list supports filtering pagination and keeps sensitive credentials out", async () => {
  const firestore = buildSeed();
  const firstPage = await listManualSettlementObligationsDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {status: "READY", limit: 1},
  });
  assert.equal(firstPage.items.length, 1);
  assert.equal(firstPage.items[0].status, "READY");
  assert.ok(firstPage.nextCursor);
  assert.equal(firstPage.items[0].payoutMethodSummary?.accountNumber, undefined);

  const secondPage = await listManualSettlementObligationsDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {status: "READY", limit: 1, cursor: firstPage.nextCursor},
  });
  assert.equal(secondPage.items.length, 1);
  assert.notEqual(secondPage.items[0].obligationId, firstPage.items[0].obligationId);

  const refundOnly = await listManualSettlementObligationsDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {obligationType: "CUSTOMER_REFUND", search: "booking-2"},
  });
  assert.equal(refundOnly.items.length, 1);
  assert.equal(refundOnly.items[0].obligationType, "CUSTOMER_REFUND");
});

test("manual settlement detail exposes safe financial breakdown and safe Razorpay references", async () => {
  const firestore = buildSeed();
  const payoutDetail = await getManualSettlementObligationDetailDataV3({
    firestore,
    auth: {uid: "super-1"},
    obligationId: "provider_payout_booking-1",
  });
  assert.equal(payoutDetail.financials.customerPaidPaise, 10000);
  assert.equal(payoutDetail.financials.pettxoCouponFundingPaise, 1000);
  assert.equal(payoutDetail.financials.canonicalProviderEntitlementPaise, 8500);
  assert.equal(payoutDetail.payout.payoutMethodSummary.accountNumberMasked, "••••4321");

  const refundDetail = await getManualSettlementObligationDetailDataV3({
    firestore,
    auth: {uid: "super-1"},
    obligationId: "customer_refund_resolution_booking-2",
  });
  assert.equal(refundDetail.dispute.resolutionType, "PARTIAL_REFUND");
  assert.equal(refundDetail.dispute.providerFinalEntitlementPaise, 5500);
  assert.equal(refundDetail.refund.razorpayOrderId, "order_2");
  assert.equal(refundDetail.refund.razorpayPaymentId, "pay_2");
});

test("provider destination reveal derives the provider from the obligation and returns only the selected method", async () => {
  const firestore = buildSeed();
  const revealed = await revealManualSettlementProviderDestinationDataV3({
    firestore,
    auth: {uid: "super-1"},
    obligationId: "provider_payout_booking-1",
  });
  assert.equal(revealed.providerId, "provider-1");
  assert.equal(revealed.payoutMethod, "BANK_ACCOUNT");
  assert.equal(revealed.bankAccount.accountNumber, "1234567894321");
  assert.equal(revealed.upi, null);
});

test("manual provider payout recording is idempotent and writes canonical paid state", async () => {
  const firestore = buildSeed();
  const first = await recordManualProviderPayoutDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {
      obligationId: "provider_payout_booking-1",
      transactionReference: "utr-123",
      paymentMethod: "BANK_ACCOUNT",
      adminNote: "Paid from ops account",
    },
  });
  assert.equal(first.code, "RECORDED");
  assert.equal(
    firestore.store.get("manualSettlementObligations/provider_payout_booking-1").status,
    "COMPLETED",
  );
  assert.equal(firestore.store.get("providerPayouts/booking-1").status, "PAID");
  assert.equal(firestore.store.get("payoutReadiness/booking-1").status, "PAID");
  assert.equal(firestore.store.get("providerEarnings/booking-1").status, "PAID");
  assert.equal(
    firestore.store.get("bookingFinancialLedger/booking-1_PROVIDER_PAYOUT_booking-1").metadata.transactionReference,
    "utr-123",
  );

  const replay = await recordManualProviderPayoutDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {
      obligationId: "provider_payout_booking-1",
      transactionReference: "utr-123",
    },
  });
  assert.equal(replay.code, "ALREADY_COMPLETED");
  assert.equal(replay.idempotentReplay, true);

  await assert.rejects(
    () =>
      recordManualProviderPayoutDataV3({
        firestore,
        auth: {uid: "super-1"},
        input: {
          obligationId: "provider_payout_booking-1",
          transactionReference: "utr-456",
        },
      }),
    /different evidence/i,
  );
});

test("manual provider payout rejects held obligations and active dispute regressions", async () => {
  const firestore = buildSeed();
  firestore.store.set(
    "manualSettlementObligations/provider_payout_booking-1",
    buildObligation({status: "HELD", holdReason: "Awaiting documents"}),
  );
  await assert.rejects(
    () =>
      recordManualProviderPayoutDataV3({
        firestore,
        auth: {uid: "super-1"},
        input: {
          obligationId: "provider_payout_booking-1",
          transactionReference: "utr-held",
        },
      }),
    /Only READY provider payout obligations/i,
  );
});

test("manual customer refund recording never calls Razorpay and updates dispute aggregation safely", async () => {
  const firestore = buildSeed();
  const originalRefundProcessor = razorpayGateway.processRazorpayRefundV3;
  let callCount = 0;
  razorpayGateway.processRazorpayRefundV3 = async () => {
    callCount += 1;
    return {razorpayRefundId: "rfnd_should_not_happen", status: "submitted"};
  };

  try {
    const recorded = await recordManualCustomerRefundDataV3({
      firestore,
      auth: {uid: "super-1"},
      input: {
        obligationId: "customer_refund_resolution_booking-2",
        razorpayRefundId: "rfnd_manual_1",
        reference: "ops-note-1",
      },
    });
    assert.equal(recorded.code, "RECORDED");
    assert.equal(callCount, 0);
    assert.equal(
      firestore.store.get("manualSettlementObligations/customer_refund_resolution_booking-2").status,
      "PROCESSING",
    );
    assert.equal(firestore.store.get("refunds/booking-2").state, "manual_recorded");
    assert.equal(firestore.store.get("refunds/booking-2").manualRefundStatus, "INITIATED");
    assert.equal(
      firestore.store.get("bookingDisputeResolutions/resolution_booking-2").financialSettlementStatus,
      "PENDING",
    );

    const skipped = await submitRefundInstructionV3({
      firestore,
      bookingId: "booking-2",
      paymentAttemptId: "attempt-2",
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: new Date("2026-08-21T11:00:00.000Z"),
    });
    assert.equal(skipped, "SKIPPED");
    assert.equal(callCount, 0);
  } finally {
    razorpayGateway.processRazorpayRefundV3 = originalRefundProcessor;
  }
});

test("manual customer refund recording keeps single-obligation disputes pending until processor confirmation", async () => {
  const firestore = buildSeed();
  firestore.store.delete("manualSettlementObligations/provider_payout_booking-2");
  const first = await recordManualCustomerRefundDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {
      obligationId: "customer_refund_resolution_booking-2",
      razorpayRefundId: "rfnd_manual_single",
    },
  });
  assert.equal(first.code, "RECORDED");
  assert.equal(
    firestore.store.get("manualSettlementObligations/customer_refund_resolution_booking-2").status,
    "PROCESSING",
  );
  assert.equal(
    firestore.store.get("bookingDisputeResolutions/resolution_booking-2").financialSettlementStatus,
    "PENDING",
  );

  const replay = await recordManualCustomerRefundDataV3({
    firestore,
    auth: {uid: "super-1"},
    input: {
      obligationId: "customer_refund_resolution_booking-2",
      razorpayRefundId: "rfnd_manual_single",
    },
  });
  assert.equal(replay.code, "RECORDED");
  assert.equal(
    firestore.store.get("refunds/booking-2").manualRefundStatus,
    "INITIATED",
  );
});

test("historical materialization is idempotent and skips already-paid or dispute-blocked bookings", async () => {
  const firestore = buildSeed();
  firestore.store.delete("manualSettlementObligations/provider_payout_booking-1");
  const materialized = await materializeManualSettlementObligationsForBookingDataV3({
    firestore,
    auth: {uid: "super-1"},
    bookingId: "booking-1",
  });
  assert.equal(materialized.code, "MATERIALIZED");
  assert.equal(
    firestore.store.get("manualSettlementObligations/provider_payout_booking-1").obligationType,
    "PROVIDER_PAYOUT",
  );

  const noActionPaid = await materializeManualSettlementObligationsForBookingDataV3({
    firestore,
    auth: {uid: "super-1"},
    bookingId: "booking-3",
  });
  assert.equal(noActionPaid.code, "ALREADY_EXISTS");

  const blockedFirestore = buildSeed();
  const blockedBooking = blockedFirestore.store.get("bookings/booking-1");
  blockedBooking.dispute.status = "OPEN";
  blockedFirestore.store.set("bookings/booking-1", blockedBooking);
  blockedFirestore.store.delete("manualSettlementObligations/provider_payout_booking-1");
  const blocked = await materializeManualSettlementObligationsForBookingDataV3({
    firestore: blockedFirestore,
    auth: {uid: "super-1"},
    bookingId: "booking-1",
  });
  assert.equal(blocked.code, "BLOCKED_BY_DISPUTE");
});
