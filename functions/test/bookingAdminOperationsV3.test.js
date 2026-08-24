const test = require("node:test");
const assert = require("node:assert/strict");
const {FieldPath, Timestamp} = require("firebase-admin/firestore");

const {
  loadAdminActor,
  listCanonicalDisputesForAdminDataV3,
  getCanonicalDisputeAdminDetailDataV3,
  listCanonicalBookingsForAdminDataV3,
  getCanonicalBookingAdminDetailDataV3,
  listCanonicalProviderPayoutsForAdminDataV3,
  getCanonicalFinancialSummaryDataV3,
  listCanonicalNoShowCasesDataV3,
  listCanonicalRefundsForAdminDataV3,
  getCanonicalRefundAdminDetailDataV3,
} = require("../lib/booking/bookingAdminOperationsV3.js");
const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildConfirmedSlotBookingFixture,
  buildConfirmedRangeBookingFixture,
  buildCompletedFinalBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");

function getByPath(source, fieldPath) {
  if (fieldPath === "__name__") return source.__name__;
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
    this.ref = new FakeDocRef(firestore, path);
    this.id = path.split("/").pop();
    this.path = path;
    this._data = data;
  }

  get exists() {
    return this._data !== undefined;
  }

  data() {
    return this._data;
  }

  get(fieldPath) {
    if (!this.exists) return undefined;
    return getByPath(this._data, fieldPath);
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.empty = docs.length === 0;
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
    this.startAfterValues = options.startAfterValues ?? null;
  }

  where(field, op, value) {
    return new FakeQuery(this.firestore, this.path, {
      filters: [...this.filters, {field, op, value}],
      orderings: this.orderings,
      limitValue: this.limitValue,
      startAfterValues: this.startAfterValues,
    });
  }

  orderBy(field, direction = "asc") {
    const fieldPath = typeof field === "string" ? field : field.segments.join(".");
    return new FakeQuery(this.firestore, this.path, {
      filters: this.filters,
      orderings: [...this.orderings, {fieldPath, direction}],
      limitValue: this.limitValue,
      startAfterValues: this.startAfterValues,
    });
  }

  limit(value) {
    return new FakeQuery(this.firestore, this.path, {
      filters: this.filters,
      orderings: this.orderings,
      limitValue: value,
      startAfterValues: this.startAfterValues,
    });
  }

  startAfter(...values) {
    return new FakeQuery(this.firestore, this.path, {
      filters: this.filters,
      orderings: this.orderings,
      limitValue: this.limitValue,
      startAfterValues: values,
    });
  }

  async get() {
    const baseSegments = this.path.split("/");
    const candidates = [];
    for (const [path, data] of this.firestore.store.entries()) {
      const segments = path.split("/");
      if (segments.length !== baseSegments.length + 1) continue;
      if (!segments.slice(0, baseSegments.length).every((segment, index) => segment === baseSegments[index])) {
        continue;
      }
      candidates.push(new FakeDocSnapshot(this.firestore, path, data));
    }

    let docs = candidates.filter((doc) => this.filters.every((filter) => {
      const actual = doc.get(filter.field);
      const actualComparable = comparableValue(actual);
      const filterComparable = comparableValue(filter.value);
      switch (filter.op) {
      case "==":
        return actualComparable === filterComparable;
      case ">=":
        return actualComparable >= filterComparable;
      case "<":
        return actualComparable < filterComparable;
      case "<=":
        return actualComparable <= filterComparable;
      default:
        throw new Error(`Unsupported filter op: ${filter.op}`);
      }
    }));

    if (this.orderings.length > 0) {
      docs = docs.sort((left, right) => {
        for (const ordering of this.orderings) {
          const leftValue = ordering.fieldPath === "__name__" ?
            left.id :
            left.get(ordering.fieldPath);
          const rightValue = ordering.fieldPath === "__name__" ?
            right.id :
            right.get(ordering.fieldPath);
          const leftComparable = comparableValue(leftValue);
          const rightComparable = comparableValue(rightValue);
          if (leftComparable === rightComparable) continue;
          const direction = ordering.direction.toLowerCase() === "desc" ? -1 : 1;
          return leftComparable < rightComparable ? -1 * direction : 1 * direction;
        }
        return 0;
      });
    }

    if (this.startAfterValues != null && this.orderings.length > 0) {
      docs = docs.filter((doc) => {
        for (let index = 0; index < this.orderings.length; index += 1) {
          const ordering = this.orderings[index];
          const cursor = this.startAfterValues[index];
          const actual = ordering.fieldPath === "__name__" ?
            doc.id :
            doc.get(ordering.fieldPath);
          const actualComparable = comparableValue(actual);
          const cursorComparable = comparableValue(cursor);
          if (actualComparable === cursorComparable) continue;
          if (ordering.direction.toLowerCase() === "desc") {
            return actualComparable < cursorComparable;
          }
          return actualComparable > cursorComparable;
        }
        return false;
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
}

function buildAdminSeed() {
  const booking = buildCompletedFinalBookingFixture();
  booking.parentId = "customer-1";
  booking.customerId = "customer-1";
  booking.providerId = "provider-1";
  booking.serviceOwnerId = "provider-1";
  booking.participants.parent.parentId = "customer-1";
  booking.participants.provider.providerId = "provider-1";
  booking.service.providerId = "provider-1";
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.dispute.status = "OPEN";
  booking.dispute.raisedBy = "parent";
  booking.dispute.reasonCode = "SERVICE_QUALITY";
  booking.dispute.description = "Provider arrived late.";
  booking.dispute.evidenceRefs = ["disputes/booking-1/photo1.png"];

  const bookingTwo = structuredClone(booking);
  bookingTwo.updatedAt = new Date("2026-07-23T16:00:00.000Z");
  bookingTwo.createdAt = new Date("2026-07-23T10:00:00.000Z");
  bookingTwo.bookingIdSearchKey = "booking-2";
  bookingTwo.dispute.description = "Older dispute.";
  bookingTwo.service.serviceTitle = "Pet Walking";
  bookingTwo.service.category = "Walking";

  return {
    booking,
    bookingTwo,
    firestore: new FakeFirestore({
      "users/finance-1": {adminRole: "financeAdmin", email: "finance@example.com"},
      "users/super-1": {adminRole: "superAdmin", email: "super@example.com"},
      "users/support-1": {adminRole: "customerSupportAdmin", email: "support@example.com"},
      "users/customer-1": {
        email: "customer@example.com",
        phoneNumber: "+919876543210",
      },
      "users/provider-1": {
        email: "provider@example.com",
        phoneNumber: "+919000111222",
      },
      "users/provider-1/providerBankDetails/main": {
        status: "submitted",
        accountNumberMasked: "XXXX4321",
      },
      "bookings/booking-1": booking,
      "bookings/booking-2": bookingTwo,
      "bookings/booking-1/events/dispute_created": {
        event: "dispute_created",
        actor: "parent",
        at: Timestamp.fromDate(new Date("2026-07-23T12:00:00.000Z")),
        meta: {reason: "SERVICE_QUALITY"},
      },
      "bookings/booking-1/events/dispute_resolved": {
        event: "dispute_resolved",
        actor: "admin",
        at: Timestamp.fromDate(new Date("2026-07-23T13:00:00.000Z")),
        meta: {resolutionType: "PARTIAL_REFUND"},
      },
      "disputes/booking-1": {
        bookingId: "booking-1",
        providerId: "provider-1",
        parentId: "customer-1",
        customerId: "customer-1",
        reasonCode: "SERVICE_QUALITY",
        description: "Provider arrived late.",
        attachments: ["disputes/booking-1/photo1.png"],
        createdAt: Timestamp.fromDate(new Date("2026-07-23T12:00:00.000Z")),
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T13:00:00.000Z")),
        status: "OPEN",
        source: "canonical_v3",
      },
      "disputes/booking-2": {
        bookingId: "booking-2",
        providerId: "provider-1",
        parentId: "customer-1",
        customerId: "customer-1",
        reasonCode: "TIMING",
        description: "Older dispute.",
        attachments: [],
        createdAt: Timestamp.fromDate(new Date("2026-07-23T10:00:00.000Z")),
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T11:00:00.000Z")),
        status: "RESOLVED",
        source: "canonical_v3",
      },
      "refunds/booking-1": {
        schemaVersion: 3,
        bookingModelVersion: "3.2",
        state: "processed",
        refundAmountPaise: 12000,
        razorpayRefundId: "rfnd_1",
        lastErrorCode: "",
        createdAt: Timestamp.fromDate(new Date("2026-07-23T12:10:00.000Z")),
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T12:12:00.000Z")),
      },
      "providerPayouts/booking-1": {
        bookingId: "booking-1",
        providerId: "provider-1",
        status: "FAILED",
        failureCode: "LIVE_PAYOUT_DISABLED",
        retryCount: 2,
        nextRetryAt: Timestamp.fromDate(new Date("2026-07-23T15:00:00.000Z")),
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T14:00:00.000Z")),
        eligibleAt: Timestamp.fromDate(new Date("2026-07-23T13:30:00.000Z")),
        remainingPayablePaise: 306000,
      },
      "bookingFinancialReconciliation/booking-1": {
        status: "BALANCED",
        action: "NO_ACTION",
        issues: [],
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T14:05:00.000Z")),
      },
      "bookingFinancialLedger/payment": {
        bookingId: "booking-1",
        type: "PAYMENT_CAPTURED",
        amountPaise: 360000,
        occurredAt: Timestamp.fromDate(new Date("2026-07-23T11:59:00.000Z")),
        createdAt: Timestamp.fromDate(new Date("2026-07-23T11:59:00.000Z")),
      },
      "bookingFinancialLedger/refund": {
        bookingId: "booking-1",
        type: "CUSTOMER_REFUND",
        amountPaise: 12000,
        occurredAt: Timestamp.fromDate(new Date("2026-07-23T12:12:00.000Z")),
        createdAt: Timestamp.fromDate(new Date("2026-07-23T12:12:00.000Z")),
      },
      "bookingFinancials/booking-1": {
        status: "HELD",
        refundAmountPaise: 12000,
        providerAmountPaise: 306000,
        pettxoAmountPaise: 42000,
      },
      "providerEarnings/booking-1": {
        status: "HELD",
        amountPaise: 306000,
      },
      "payoutReadiness/booking-1": {
        status: "HELD",
        payoutStatus: "HELD",
      },
      "bookingNoShows/booking-1": {
        bookingId: "booking-1",
        providerId: "provider-1",
        parentId: "customer-1",
        noShowAt: Timestamp.fromDate(new Date("2026-07-23T18:00:00.000Z")),
        noShowReasonCode: "OTP_NOT_ENTERED_BY_SERVICE_END",
        customerRefundPaise: 0,
        providerCompensationPaise: 306000,
        pettxoRetainedPaise: 54000,
        updatedAt: Timestamp.fromDate(new Date("2026-07-23T18:00:00.000Z")),
      },
      "bookingPrivate/booking-1": {
        otpState: "REVOKED",
      },
      "bookingCancellations/booking-1": {
        actorType: "CUSTOMER",
        reasonCode: "changed_plans",
        effectiveAt: Timestamp.fromDate(new Date("2026-07-23T12:05:00.000Z")),
        providerCompensationPaise: 306000,
        pettxoRetainedPaise: 42000,
        gatewayFeeSunkPaise: 0,
      },
    }),
  };
}

test("loadAdminActor rejects unauthenticated and unauthorized requests", async () => {
  const {firestore} = buildAdminSeed();
  await assert.rejects(
    () => loadAdminActor(firestore, null, "financial"),
    /Sign in required/i,
  );
  await assert.rejects(
    () => loadAdminActor(firestore, {uid: "customer-1"}, "financial"),
    /Finance admin access required/i,
  );
});

test("loadAdminActor allows customer support only for nonfinancial dispute scope", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "support-1"}, "dispute_nonfinancial");
  assert.equal(actor.role, "customerSupportAdmin");
  assert.equal(actor.canViewFinancials, false);
  await assert.rejects(
    () => loadAdminActor(firestore, {uid: "support-1"}, "financial"),
    /Finance admin access required/i,
  );
});

test("listCanonicalDisputesForAdminDataV3 masks financial fields for customer support", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "support-1"}, "dispute_nonfinancial");
  const result = await listCanonicalDisputesForAdminDataV3({
    firestore,
    actor,
    input: {limit: 10, status: "OPEN"},
  });
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].status, "OPEN");
  assert.equal(result.items[0].customer.maskedEmail, "cu***@example.com");
  assert.equal(result.items[0].disputedAmountPaise, null);
  assert.equal(result.items[0].paymentStatus, null);
  assert.equal(result.items[0].payoutStatus, null);
});

test("listCanonicalDisputesForAdminDataV3 provides stable cursor pagination", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "dispute_nonfinancial");
  const firstPage = await listCanonicalDisputesForAdminDataV3({
    firestore,
    actor,
    input: {limit: 1},
  });
  assert.equal(firstPage.items.length, 1);
  assert.ok(firstPage.nextCursor);
  const secondPage = await listCanonicalDisputesForAdminDataV3({
    firestore,
    actor,
    input: {limit: 1, cursor: firstPage.nextCursor},
  });
  assert.equal(secondPage.items.length, 1);
  assert.notEqual(firstPage.items[0].disputeId, secondPage.items[0].disputeId);
});

test("getCanonicalDisputeAdminDetailDataV3 includes evidence and ledger details", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "dispute_nonfinancial");
  const detail = await getCanonicalDisputeAdminDetailDataV3({
    firestore,
    actor,
    disputeId: "booking-1",
  });
  assert.equal(detail.disputeId, "booking-1");
  assert.equal(detail.evidence.length, 1);
  assert.equal(detail.evidence[0].storagePath, "disputes/booking-1/photo1.png");
  assert.equal(detail.ledgerSummary.totals.paymentCapturedPaise, 360000);
});

test("listCanonicalBookingsForAdminDataV3 rejects malformed cursor", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  await assert.rejects(
    () => listCanonicalBookingsForAdminDataV3({
      firestore,
      actor,
      input: {cursor: "bad-cursor"},
    }),
    /cursor is invalid/i,
  );
});

test("listCanonicalBookingsForAdminDataV3 resolves booking IDs case-insensitively", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const booking = buildCompletedFinalBookingFixture();
  booking.updatedAt = new Date("2026-08-15T18:30:00.000Z");
  booking.createdAt = new Date("2026-08-15T17:30:00.000Z");
  booking.bookingIdSearchKey = "guxodz2dcbuw1atcmkok";
  firestore.store.set("bookings/guXODz2DCBuw1ATCMKOK", booking);

  const result = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "  GUXODZ2DCBUW1ATCMKOK  "},
  });

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingId, "guXODz2DCBuw1ATCMKOK");
});

test("listCanonicalBookingsForAdminDataV3 returns all indexed prefix matches", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const first = buildCompletedFinalBookingFixture();
  first.updatedAt = new Date("2026-08-15T18:30:00.000Z");
  first.createdAt = new Date("2026-08-15T17:30:00.000Z");
  first.bookingIdSearchKey = "guxodz2dcbuw1atcmkok";
  firestore.store.set("bookings/guXODz2DCBuw1ATCMKOK", first);

  const second = buildCompletedFinalBookingFixture();
  second.updatedAt = new Date("2026-08-15T18:31:00.000Z");
  second.createdAt = new Date("2026-08-15T17:31:00.000Z");
  second.bookingIdSearchKey = "guxodz2dcbuw1atcmzzz";
  firestore.store.set("bookings/guXODz2DCBuw1ATCMZZZ", second);

  const result = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "guxodz2dcbuw1atcm"},
  });

  assert.equal(result.items.length, 2);
  assert.deepEqual(
    result.items.map((item) => item.bookingId).sort(),
    ["guXODz2DCBuw1ATCMKOK", "guXODz2DCBuw1ATCMZZZ"],
  );
});

test("listCanonicalBookingsForAdminDataV3 combines prefix search with filters", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const first = buildAcceptedAwaitingPaymentSlotBookingFixture();
  first.updatedAt = new Date("2026-08-15T18:30:00.000Z");
  first.createdAt = new Date("2026-08-15T17:30:00.000Z");
  first.bookingIdSearchKey = "guxprefix001";
  first.payment.status = "ORDER_CREATED";
  first.bookingType = "SLOT";
  first.bookingTypeQueryValue = "SLOT";
  firestore.store.set("bookings/guXPrefix001", first);

  const second = buildCompletedFinalBookingFixture();
  second.updatedAt = new Date("2026-08-15T18:31:00.000Z");
  second.createdAt = new Date("2026-08-15T17:31:00.000Z");
  second.bookingIdSearchKey = "guxprefix002";
  second.payment.status = "CONFIRMED";
  second.bookingType = "RANGE";
  second.bookingTypeQueryValue = "RANGE";
  firestore.store.set("bookings/guXPrefix002", second);

  const result = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {
      search: "guxprefix",
      paymentStatus: "order_created",
      bookingType: "slot",
    },
  });

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingId, "guXPrefix001");
});

test("listCanonicalBookingsForAdminDataV3 falls back for legacy mixed-case IDs without normalized field", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const booking = buildCompletedFinalBookingFixture();
  booking.updatedAt = new Date("2026-08-15T18:30:00.000Z");
  booking.createdAt = new Date("2026-08-15T17:30:00.000Z");
  delete booking.bookingIdSearchKey;
  firestore.store.set("bookings/guXODz2DCBuw1ATCMKOK", booking);

  const result = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "guxodz2dcbuw1atcmkok"},
  });

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingId, "guXODz2DCBuw1ATCMKOK");
});

test("listCanonicalBookingsForAdminDataV3 returns empty when searched booking is missing", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const result = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "missing-booking-id"},
  });
  assert.equal(result.items.length, 0);
});

test("booking admin list and detail expose effective payment-expired state", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  booking.updatedAt = new Date("2026-08-15T18:30:00.000Z");
  booking.createdAt = new Date("2026-08-15T17:30:00.000Z");
  booking.lifecycle.payDeadlineAt = new Date("2026-08-15T18:00:00.000Z");
  booking.payDeadlineAt = booking.lifecycle.payDeadlineAt;
  booking.payment.status = "ORDER_CREATED";
  booking.bookingIdSearchKey = "guxodz2dcbuw1atcmkok";
  firestore.store.set("bookings/guXODz2DCBuw1ATCMKOK", booking);

  const list = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "GUXODZ2DCBUW1ATCMKOK", status: "PAYMENT_EXPIRED"},
  });
  assert.equal(list.items.length, 1);
  assert.equal(list.items[0].state, "PAYMENT_EXPIRED");
  assert.equal(list.items[0].storedState, "ACCEPTED_AWAITING_PAYMENT");

  const detail = await getCanonicalBookingAdminDetailDataV3({
    firestore,
    actor,
    bookingId: "GUXODZ2DCBUW1ATCMKOK",
  });
  assert.equal(detail.bookingId, "guXODz2DCBuw1ATCMKOK");
  assert.equal(detail.effectiveState, "PAYMENT_EXPIRED");
  assert.equal(detail.storedState, "ACCEPTED_AWAITING_PAYMENT");
  assert.equal(detail.paymentState, "ORDER_CREATED");
});

test("booking admin readers prefer canonical resolved dispute state over stale booking mirrors", async () => {
  const {firestore, booking} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  booking.dispute.status = "OPEN";
  firestore.store.set("bookings/booking-1", booking);
  firestore.store.set("disputes/booking-1", {
    ...firestore.store.get("disputes/booking-1"),
    status: "RESOLVED",
    resolvedAt: Timestamp.fromDate(new Date("2026-07-23T13:00:00.000Z")),
    resolution: {
      type: "CUSTOM_ALLOCATION",
      customerRefundPaise: 12000,
      providerFinalEntitlementPaise: 306000,
    },
  });

  const list = await listCanonicalBookingsForAdminDataV3({
    firestore,
    actor,
    input: {search: "booking-1"},
  });
  assert.equal(list.items.length, 1);
  assert.equal(list.items[0].state, "DISPUTE_RESOLVED");
  assert.equal(list.items[0].disputeStatus, "RESOLVED");
  assert.equal(list.items[0].disputeResolutionType, "CUSTOM_ALLOCATION");

  const detail = await getCanonicalBookingAdminDetailDataV3({
    firestore,
    actor,
    bookingId: "booking-1",
  });
  assert.equal(detail.effectiveState, "DISPUTE_RESOLVED");
  assert.equal(detail.dispute.status, "RESOLVED");
  assert.equal(detail.dispute.resolution, "CUSTOM_ALLOCATION");

  const disputeDetail = await getCanonicalDisputeAdminDetailDataV3({
    firestore,
    actor,
    disputeId: "booking-1",
  });
  assert.equal(disputeDetail.bookingSummary.disputeStatus, "RESOLVED");
});

test("booking admin readers derive completed-pending-review from stale started in-progress booking after final service end", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const booking = buildConfirmedRangeBookingFixture();
  booking.state = "IN_PROGRESS";
  booking.stateQueryValue = "IN_PROGRESS";
  booking.payment.status = "paid";
  booking.lifecycle.paidAt = new Date("2026-08-18T00:30:00.000Z");
  booking.lifecycle.otpEnteredAt = new Date("2026-08-18T00:35:00.000Z");
  booking.schedule.checkInDateTime = new Date("2026-08-18T00:30:00.000Z");
  booking.schedule.checkOutDateTime = new Date("2026-08-19T00:30:00.000Z");
  booking.schedule.scheduledStartAt = new Date("2026-08-18T00:30:00.000Z");
  booking.schedule.scheduledEndAt = new Date("2026-08-19T00:30:00.000Z");
  booking.schedule.firstSegmentEndAt = new Date("2026-08-19T00:30:00.000Z");
  booking.schedule.finalEndAt = new Date("2026-08-19T00:30:00.000Z");
  booking.schedule.nights = 1;
  booking.schedule.serviceAnchorAt = new Date("2026-08-18T00:30:00.000Z");
  booking.service.checkInDateTime = new Date("2026-08-18T00:30:00.000Z");
  booking.service.checkOutDateTime = new Date("2026-08-19T00:30:00.000Z");
  booking.serviceAnchorAt = new Date("2026-08-18T00:30:00.000Z");
  booking.checkInDateTime = new Date("2026-08-18T00:30:00.000Z");
  booking.updatedAt = new Date("2026-08-19T00:31:00.000Z");
  booking.createdAt = new Date("2026-08-18T00:00:00.000Z");
  booking.bookingIdSearchKey = "fcxsk8oljx4qvdqzurnq";
  firestore.store.set("bookings/FCxsk8oljX4qvdqZuRNq", booking);

  const detail = await getCanonicalBookingAdminDetailDataV3({
    firestore,
    actor,
    bookingId: "FCxsk8oljX4qvdqZuRNq",
  });
  assert.equal(detail.effectiveState, "COMPLETED_PENDING_REVIEW");
  assert.equal(detail.storedState, "IN_PROGRESS");
});

test("listCanonicalProviderPayoutsForAdminDataV3 returns payout blockers and disabled-live flag", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const result = await listCanonicalProviderPayoutsForAdminDataV3({
    firestore,
    actor,
    input: {search: "booking-1"},
  });
  assert.equal(result.livePayoutEnabled, false);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].failureCode, "LIVE_PAYOUT_DISABLED");
  assert.equal(result.items[0].refundBlocker, false);
});

test("listCanonicalRefundsForAdminDataV3 and refund detail expose canonical refund breakdown", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const listResult = await listCanonicalRefundsForAdminDataV3({
    firestore,
    actor,
    input: {limit: 10},
  });
  assert.equal(listResult.items.length, 1);
  assert.equal(listResult.items[0].status, "processed");

  const detail = await getCanonicalRefundAdminDetailDataV3({
    firestore,
    actor,
    bookingId: "booking-1",
  });
  assert.equal(detail.summary.customerRefundPaise, 12000);
  assert.equal(detail.summary.razorpayRefundReference, "rfnd_1");
});

test("listCanonicalRefundsForAdminDataV3 supports case-insensitive indexed booking prefix search", async () => {
  const {firestore} = buildAdminSeed();
  firestore.store.set("refunds/booking-2", {
    schemaVersion: 3,
    bookingModelVersion: "3.2",
    state: "pending",
    refundAmountPaise: 8000,
    razorpayRefundId: "",
    lastErrorCode: "",
    createdAt: Timestamp.fromDate(new Date("2026-07-23T16:10:00.000Z")),
    updatedAt: Timestamp.fromDate(new Date("2026-07-23T16:12:00.000Z")),
  });

  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");

  const exactResult = await listCanonicalRefundsForAdminDataV3({
    firestore,
    actor,
    input: {search: "BOOKING-1", limit: 10},
  });
  assert.equal(exactResult.items.length, 1);
  assert.equal(exactResult.items[0].bookingId, "booking-1");

  const prefixResult = await listCanonicalRefundsForAdminDataV3({
    firestore,
    actor,
    input: {search: "BOOKING-", limit: 10},
  });
  assert.equal(prefixResult.items.length, 2);
  assert.deepEqual(
    prefixResult.items.map((item) => item.bookingId).sort(),
    ["booking-1", "booking-2"],
  );

  const filteredResult = await listCanonicalRefundsForAdminDataV3({
    firestore,
    actor,
    input: {search: "BOOKING-", status: "processed", limit: 10},
  });
  assert.equal(filteredResult.items.length, 1);
  assert.equal(filteredResult.items[0].bookingId, "booking-1");
});

test("listCanonicalNoShowCasesDataV3 returns no-show financial breakdown", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const result = await listCanonicalNoShowCasesDataV3({
    firestore,
    actor,
    input: {limit: 10},
  });
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].classification, "OTP_NOT_ENTERED_BY_SERVICE_END");
  assert.equal(result.items[0].defaultSettlement.providerCompensationPaise, 306000);
});

test("getCanonicalFinancialSummaryDataV3 returns overview counts and booking scope", async () => {
  const {firestore} = buildAdminSeed();
  const actor = await loadAdminActor(firestore, {uid: "finance-1"}, "financial");
  const overview = await getCanonicalFinancialSummaryDataV3({
    firestore,
    actor,
  });
  assert.equal(overview.scope, "overview");
  assert.equal(overview.counts.canonicalDisputesOpen, 1);
  const booking = await getCanonicalFinancialSummaryDataV3({
    firestore,
    actor,
    bookingId: "booking-1",
  });
  assert.equal(booking.scope, "booking");
  assert.equal(booking.ledgerTotals.refundPaise, 12000);
});
