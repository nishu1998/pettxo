const mergeFirestoreSet = require("./helpers/mergeFirestoreSet");
const assertCanonicalEarning = require('./helpers/assertCanonicalEarning');
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");

const {
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  buildNoShowRecord,
  calculateCanonicalNoShowAllocationV3,
  finalizeCanonicalNoShowV3,
  verifyBookingStartOtpV3,
} = require("../lib/booking/application/serviceStartOrchestrationV3.js");

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
  }

  async get(ref) {
    return ref.get();
  }

  set(ref, data, options) {
    this.firestore._set(ref.path, data, options);
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
}

class FakeCollectionRef {
  constructor(firestore, path) {
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
    return handler(new FakeTransaction(this));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? mergeFirestoreSet(existing, data) : {...data});
  }
}

function providerOtpHash(bookingId, otp) {
  return createHash("sha256").update(`${bookingId}:${otp}`).digest("hex");
}

function buildPrivateDoc({bookingId, booking, otp = "482913"}) {
  return {
    schemaVersion: 1,
    bookingId,
    parentId: booking.parentId,
    providerId: booking.providerId,
    parentOtpCode: otp,
    providerOtpHash: providerOtpHash(bookingId, otp),
    otpState: "ACTIVE",
    failedAttemptCount: 0,
    lastFailedAttemptAt: null,
    lockedUntil: null,
    verifiedAt: null,
    successfulAttemptNumber: null,
    lastVerificationAttemptId: "",
    lastVerificationOutcome: "",
    contactUnlockedAt: booking.lifecycle.paidAt,
    createdAt: booking.lifecycle.paidAt,
    updatedAt: booking.lifecycle.paidAt,
  };
}

function buildConfirmedBookingSeed() {
  const bookingId = "booking-start-1";
  const booking = buildConfirmedSlotBookingFixture();
  return {
    bookingId,
    booking,
    privateDoc: buildPrivateDoc({bookingId, booking}),
  };
}

function buildMultiSegmentConfirmedBookingSeed() {
  const bookingId = "booking-start-multiday-1";
  const booking = buildConfirmedSlotBookingFixture();
  const firstStart = new Date("2026-07-23T06:00:00.000Z");
  const firstEnd = new Date("2026-07-23T07:00:00.000Z");
  const secondStart = new Date("2026-07-23T07:00:00.000Z");
  const secondEnd = new Date("2026-07-23T08:00:00.000Z");
  booking.schedule.slots = [
    {
      ...booking.schedule.slots[0],
      slotId: "slot-1",
      dateKey: "2026-07-23",
      serviceDateKey: "2026-07-23",
      startAt: firstStart,
      endAt: firstEnd,
      schedulingMode: "fixedDuration",
    },
    {
      ...booking.schedule.slots[0],
      slotId: "slot-2",
      dateKey: "2026-07-23",
      serviceDateKey: "2026-07-23",
      startAt: secondStart,
      endAt: secondEnd,
      schedulingMode: "fixedDuration",
    },
  ];
  booking.schedule.slotCount = 2;
  booking.schedule.scheduledStartAt = firstStart;
  booking.schedule.scheduledEndAt = secondEnd;
  booking.schedule.totalDurationMinutes = 120;
  booking.schedule.segments = [
    {
      serviceDateKey: "2026-07-23",
      startAt: firstStart,
      endAt: firstEnd,
      slotIds: ["slot-1"],
      durationMinutes: 60,
      schedulingMode: "fixedDuration",
    },
    {
      serviceDateKey: "2026-07-23",
      startAt: secondStart,
      endAt: secondEnd,
      slotIds: ["slot-2"],
      durationMinutes: 60,
      schedulingMode: "fixedDuration",
    },
  ];
  booking.schedule.firstSegmentEndAt = firstEnd;
  booking.schedule.finalEndAt = secondEnd;
  booking.schedule.serviceDayCount = 1;
  booking.schedule.segmentCount = 2;
  booking.service.selectedSlotCount = 2;
  booking.service.totalDurationMinutes = 120;
  booking.statistics.selectedSlotCount = 2;
  booking.statistics.totalDurationMinutes = 120;
  return {
    bookingId,
    booking,
    privateDoc: buildPrivateDoc({bookingId, booking}),
  };
}

function deepConvertDatesToTimestamps(value) {
  if (value instanceof Date) {
    return Timestamp.fromDate(value);
  }
  if (Array.isArray(value)) {
    return value.map((entry) => deepConvertDatesToTimestamps(entry));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        deepConvertDatesToTimestamps(entry),
      ]),
    );
  }
  return value;
}

test("correct OTP succeeds before the scheduled start once payment is confirmed", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: deepConvertDatesToTimestamps(booking),
    [`bookingPrivate/${bookingId}`]: deepConvertDatesToTimestamps(privateDoc),
  });
  const beforeScheduledStart = new Date(
    booking.schedule.scheduledStartAt.getTime() - 60 * 1000,
  );

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-1",
    authoritativeNow: beforeScheduledStart,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("correct OTP is still allowed at the exact authoritative service end", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-2",
    authoritativeNow: booking.schedule.scheduledEndAt,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
});

test("correct OTP is still allowed at the first segment end for a continuous multi-slot slot booking", async () => {
  const {bookingId, booking, privateDoc} = buildMultiSegmentConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-2b",
    authoritativeNow: booking.schedule.firstSegmentEndAt,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
});

test("confirmed booking still starts when refund mirroring overwrote display payment status", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  booking.payment.status = "refunded";
  booking.payment.razorpayRefundId = "rfnd_123";
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });
  const beforeScheduledStart = new Date(
    booking.schedule.scheduledStartAt.getTime() - 60 * 1000,
  );

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-refund-shadow",
    authoritativeNow: beforeScheduledStart,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("OTP is rejected after authoritative service end by one millisecond", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-3",
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 1),
  });

  assert.equal(result.code, "AFTER_SERVICE_END");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "CONFIRMED");
});

test("overdue confirmed booking finalizes to NO_SHOW exactly once", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });
  const authoritativeNow = new Date(
    booking.schedule.scheduledEndAt.getTime() + 2 * 60 * 60 * 1000,
  );

  const result = await finalizeCanonicalNoShowV3({
    firestore,
    bookingId,
    authoritativeNow,
  });

  assert.equal(result.code, "FINALIZED_NO_SHOW");
  const earning = firestore.store.get(`providerEarnings/${bookingId}`);
  assert.equal(earning.amountPaise, booking.financials.providerPayoutPaise);
  assert.equal(earning.providerFinalEntitlementPaise, booking.financials.providerPayoutPaise);
  assertCanonicalEarning(earning, bookingId);
  assert.equal(earning.earningsStatus, "FINALIZED");
  await finalizeCanonicalNoShowV3({firestore, bookingId, authoritativeNow});
  assert.deepEqual(firestore.store.get(`providerEarnings/${bookingId}`), earning);
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "NO_SHOW");
  assert.equal(firestore.store.has(`bookingNoShows/${bookingId}`), true);
  assert.equal(
    firestore.store.get(`bookingFinancials/${bookingId}`).customerRefundPaise,
    0,
  );
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).lifecycle.noShowAt.toDate().getTime(),
    booking.schedule.scheduledEndAt.getTime(),
  );
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).lifecycle.disputeDeadlineAt.toDate().getTime(),
    booking.schedule.scheduledEndAt.getTime() + 24 * 60 * 60 * 1000,
  );
  assert.equal(
    firestore.store.get(`payoutReadiness/${bookingId}`).status,
    "held",
  );
  assert.equal(
    firestore.store.get(`payoutReadiness/${bookingId}`).eligibleAt.toDate().getTime(),
    booking.schedule.scheduledEndAt.getTime() + 24 * 60 * 60 * 1000,
  );
});

test("continuous multi-slot confirmed booking finalizes to NO_SHOW from the final segment end", async () => {
  const {bookingId, booking, privateDoc} = buildMultiSegmentConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });
  const notDue = await finalizeCanonicalNoShowV3({firestore, bookingId,
    authoritativeNow: new Date(booking.schedule.firstSegmentEndAt.getTime() + 1)});
  assert.equal(notDue.code, "NOT_DUE");
  assert.equal(firestore.store.has(`bookingNoShows/${bookingId}`), false);
  const authoritativeNow = new Date(
    booking.schedule.firstSegmentEndAt.getTime() + 2 * 60 * 60 * 1000,
  );

  const result = await finalizeCanonicalNoShowV3({
    firestore,
    bookingId,
    authoritativeNow,
  });

  assert.equal(firestore.store.get(`manualSettlementObligations/provider_payout_${bookingId}`).source, "NO_SHOW");
  assert.equal([...firestore.store.keys()].filter(path => path.startsWith("manualSettlementObligations/")).length, 1);
  assert.equal(result.code, "FINALIZED_NO_SHOW");
  const earning = firestore.store.get(`providerEarnings/${bookingId}`);
  assert.equal(earning.amountPaise, booking.financials.providerPayoutPaise);
  assert.equal(earning.providerFinalEntitlementPaise, booking.financials.providerPayoutPaise);
  assertCanonicalEarning(earning, bookingId);
  assert.equal(earning.earningsStatus, "FINALIZED");
  await finalizeCanonicalNoShowV3({firestore, bookingId, authoritativeNow});
  assert.deepEqual(firestore.store.get(`providerEarnings/${bookingId}`), earning);
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "NO_SHOW");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).lifecycle.noShowAt.toDate().getTime(),
    booking.schedule.finalEndAt.getTime(),
  );
  assert.equal(
    firestore.store
      .get(`bookings/${bookingId}`)
      .lifecycle.disputeDeadlineAt.toDate()
      .getTime(),
    booking.schedule.finalEndAt.getTime() + 24 * 60 * 60 * 1000,
  );
});

test("buildNoShowRecord normalizes a live Firestore Timestamp anchor to a Date", () => {
  const {bookingId, booking} = buildConfirmedBookingSeed();

  const record = buildNoShowRecord({
    booking: deepConvertDatesToTimestamps(booking),
    bookingId,
    authoritativeNow: new Date("2026-07-30T05:50:00.000Z"),
    expectedServiceEndAt: booking.schedule.scheduledEndAt,
  });

  assert.ok(record.serviceAnchorAt instanceof Date);
  assert.equal(
    record.serviceAnchorAt.getTime(),
    booking.schedule.scheduledStartAt.getTime(),
  );
  assert.equal(
    record.noShowAt.getTime(),
    booking.schedule.scheduledEndAt.getTime(),
  );
  assert.equal(
    record.disputeDeadlineAt.getTime(),
    booking.schedule.scheduledEndAt.getTime() + 24 * 60 * 60 * 1000,
  );
});

test("buildNoShowRecord preserves a Date anchor and exact no-show timeline", () => {
  const {bookingId, booking} = buildConfirmedBookingSeed();

  const record = buildNoShowRecord({
    booking,
    bookingId,
    authoritativeNow: new Date("2026-07-30T05:50:00.000Z"),
    expectedServiceEndAt: booking.schedule.scheduledEndAt,
  });

  assert.equal(
    record.serviceAnchorAt.getTime(),
    booking.schedule.scheduledStartAt.getTime(),
  );
  assert.equal(
    record.noShowAt.getTime(),
    booking.schedule.scheduledEndAt.getTime(),
  );
  assert.equal(
    record.disputeDeadlineAt.getTime(),
    booking.schedule.scheduledEndAt.getTime() + 24 * 60 * 60 * 1000,
  );
});

test("buildNoShowRecord rejects an invalid authoritative service anchor", () => {
  const {bookingId, booking} = buildConfirmedBookingSeed();
  const invalidBooking = {
    ...booking,
    schedule: {
      ...booking.schedule,
      scheduledStartAt: "invalid-anchor",
    },
  };

  assert.throws(
    () =>
      buildNoShowRecord({
        booking: invalidBooking,
        bookingId,
        authoritativeNow: new Date("2026-07-30T05:50:00.000Z"),
        expectedServiceEndAt: booking.schedule.scheduledEndAt,
      }),
    /missing a valid authoritative service anchor time/i,
  );
});

test("no-show allocation keeps provider entitlement intact across coupon scenarios", () => {
  const booking = buildConfirmedSlotBookingFixture();

  booking.financials.serviceSubtotalPaise = 100000;
  booking.financials.couponDiscountPaise = 50000;
  booking.financials.customerPaidPaise = 50000;
  booking.financials.pettxoCouponFundingPaise = 50000;
  booking.financials.providerPayoutPaise = 85000;
  booking.financials.platformCommissionPaise = 15000;

  const partialCoupon = calculateCanonicalNoShowAllocationV3({booking});
  assert.equal(partialCoupon.customerRefundPaise, 0);
  assert.equal(partialCoupon.providerCompensationPaise, 85000);
  assert.equal(partialCoupon.pettxoRetainedPaise, 15000);
  assert.equal(partialCoupon.pettxoCouponCostPaise, 50000);

  booking.financials.couponDiscountPaise = 100000;
  booking.financials.customerPaidPaise = 0;
  booking.financials.pettxoCouponFundingPaise = 100000;

  const fullCoupon = calculateCanonicalNoShowAllocationV3({booking});
  assert.equal(fullCoupon.customerRefundPaise, 0);
  assert.equal(fullCoupon.providerCompensationPaise, 85000);
  assert.equal(fullCoupon.pettxoRetainedPaise, 15000);
  assert.equal(fullCoupon.pettxoCouponCostPaise, 100000);
});

const {reconcileCanonicalServiceStartArtifactsV3, resolveAuthoritativeServiceEndV3,
  resolveCanonicalCompletionAvailableAtV3, SERVICE_START_POLICY_VERSION} = require('../lib/booking/application/serviceStartOrchestrationV3');
const {reconcileCanonicalCompletionStateV3} = require('../lib/booking/application/serviceCompletionOrchestrationV3');
function recoverySeed() {
  const {bookingId, booking} = buildConfirmedBookingSeed();
  const at = new Date('2026-07-23T05:55:00Z');
  booking.state = booking.stateQueryValue = 'IN_PROGRESS';
  booking['lifecycle.otpEnteredAt'] = Timestamp.fromDate(at);
  const artifact = {bookingId, providerId:booking.providerId, parentId:booking.parentId,
    verifiedAt:Timestamp.fromDate(at), otpVerifiedAt:Timestamp.fromDate(at),
    stateBefore:'CONFIRMED', stateAfter:'IN_PROGRESS', policyVersion:SERVICE_START_POLICY_VERSION,
    serviceAnchorAt:Timestamp.fromDate(booking.schedule.scheduledStartAt)};
  return {bookingId,booking,artifact};
}
test('OTP writes a nested start, preserves lifecycle and permits completion reconciliation', async()=>{
  const {bookingId,booking,privateDoc}=buildConfirmedBookingSeed();
  const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingPrivate/${bookingId}`]:privateDoc,
    [`providerEarnings/${bookingId}`]:{earningsSchemaVersion:1,earningsStatus:'PROVISIONAL',providerFinalEntitlementPaise:null}});
  const at=new Date('2026-07-23T05:55:00Z');
  assert.equal((await verifyBookingStartOtpV3({firestore,bookingId,providerId:booking.providerId,otpCandidate:'482913',requestAttemptId:'phase1',authoritativeNow:at})).code,'VERIFIED_STARTED');
  const stored=firestore.store.get(`bookings/${bookingId}`);
  assert.equal(stored.lifecycle.otpEnteredAt.toDate().getTime(),at.getTime());
  assert.deepEqual(stored.lifecycle.paidAt,booking.lifecycle.paidAt);
  assert.deepEqual(stored.lifecycle.requestedAt,booking.lifecycle.requestedAt);
  assert.equal(Object.hasOwn(stored,'lifecycle.otpEnteredAt'),false);
  assert.equal(firestore.store.get(`providerEarnings/${bookingId}`).earningsStatus,'PROVISIONAL');
  assert.equal(await reconcileCanonicalCompletionStateV3({firestore,bookingId,authoritativeNow:new Date(booking.schedule.scheduledEndAt.getTime()+1)}),'AUTO_COMPLETED_PENDING_REVIEW');
});
test('corroborated start recovery is idempotent and never changes earnings',async()=>{
  const {bookingId,booking,artifact}=recoverySeed();
  const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingServiceStarts/${bookingId}`]:artifact});
  const args={firestore,bookingId,allowHistoricalRecovery:true,authoritativeNow:new Date('2026-07-24T12:00:00Z')};
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'REPAIRED');
  assert.deepEqual(firestore.store.get(`bookings/${bookingId}`).lifecycle.paidAt,booking.lifecycle.paidAt);
  assert.equal(firestore.store.get(`bookings/${bookingId}`).lifecycle.otpEnteredAt.toMillis(),artifact.verifiedAt.toMillis());
  const after=[...firestore.store];
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
  assert.deepEqual([...firestore.store],after);
  assert.equal(firestore.store.has(`providerEarnings/${bookingId}`),false);
  assert.equal((await finalizeCanonicalNoShowV3(args)).code,'STARTED');
});
for(const mode of ['missing','provider','customer','booking','timestamps','literal','terminal','artifact-terminal','policy','anchor','future']) {
 test(`start recovery refuses ${mode} evidence without writes`,async()=>{
  const {bookingId,booking,artifact}=recoverySeed();
  if(mode==='provider')artifact.providerId='wrong';
  if(mode==='customer')artifact.parentId='wrong';
  if(mode==='booking')artifact.bookingId='wrong';
  if(mode==='timestamps')artifact.otpVerifiedAt=Timestamp.fromMillis(1);
  if(mode==='literal')booking['lifecycle.otpEnteredAt']=Timestamp.fromMillis(1);
  if(mode==='terminal')booking.lifecycle.cancelledAt=new Date();
  if(mode==='policy')artifact.policyVersion='unknown';
  if(mode==='anchor')artifact.serviceAnchorAt=Timestamp.fromMillis(1);
  if(mode==='future')artifact.verifiedAt=artifact.otpVerifiedAt=booking['lifecycle.otpEnteredAt']=Timestamp.fromDate(new Date('2030-01-01'));
  const seed={[`bookings/${bookingId}`]:booking};
  if(mode!=='missing')seed[`bookingServiceStarts/${bookingId}`]=artifact;
  if(mode==='artifact-terminal')seed[`bookingNoShows/${bookingId}`]={bookingId};
  const firestore=new FakeFirestore(seed);const before=[...firestore.store];
  await assert.rejects(reconcileCanonicalServiceStartArtifactsV3({firestore,bookingId,allowHistoricalRecovery:true,authoritativeNow:new Date('2026-07-24T12:00:00Z')}),/SERVICE_START_EVIDENCE_CONFLICT/);
  assert.deepEqual([...firestore.store],before);
 });
}
test('combined consecutive slots resolve the full deadline; gaps and malformed boundaries fail closed',()=>{
 const {booking}=buildMultiSegmentConfirmedBookingSeed();
 booking.schedule.segments=[{...booking.schedule.segments[0],endAt:booking.schedule.finalEndAt,
   durationMinutes:120,slotIds:['slot-1','slot-2']}];
 booking.schedule.firstSegmentEndAt=booking.schedule.finalEndAt;booking.schedule.segmentCount=1;
 for(const resolve of [resolveAuthoritativeServiceEndV3,resolveCanonicalCompletionAvailableAtV3]){
  assert.equal(resolve({booking}).expectedServiceEndAt.getTime(),booking.schedule.finalEndAt.getTime());
  for(const mode of ['gap','overlap','invalid-date','segment','duration']){
   const bad=structuredClone(booking);
   if(mode==='gap')bad.schedule.slots[1].startAt=new Date(bad.schedule.slots[1].startAt.getTime()+60000);
   if(mode==='overlap')bad.schedule.slots[1].startAt=new Date(bad.schedule.slots[1].startAt.getTime()-60000);
   if(mode==='invalid-date')bad.schedule.slots[1].endAt=null;
   if(mode==='segment')bad.schedule.segments[0].endAt=new Date('2026-07-23T07:30:00Z');
   if(mode==='duration')bad.schedule.totalDurationMinutes=119;
   assert.equal(resolve({booking:bad}).code,'INVALID_BOOKING_DATA',mode);
  }
 }
});

test('default rollout never recovers a historical missing nested start, while Phase 2 opt-in retains evidence checks',async()=>{
 const {bookingId,booking,artifact}=recoverySeed();
 const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingServiceStarts/${bookingId}`]:artifact});
 const before=[...firestore.store];
 const args={firestore,bookingId,authoritativeNow:new Date('2026-09-17')};
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
 assert.deepEqual([...firestore.store],before);
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3({...args,allowHistoricalRecovery:true}),'REPAIRED');
});

test('unversioned combined-segment multi-slot no-show is deferred, while a release-marked booking processes normally',async()=>{
 const {bookingId,booking,privateDoc}=buildMultiSegmentConfirmedBookingSeed();
 booking.schedule.segments=[{...booking.schedule.segments[0],endAt:booking.schedule.finalEndAt,durationMinutes:120,slotIds:['slot-1','slot-2']}];
 booking.schedule.segmentCount=1;booking.schedule.firstSegmentEndAt=booking.schedule.finalEndAt;
 const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingPrivate/${bookingId}`]:privateDoc});
 const args={firestore,bookingId,authoritativeNow:new Date('2026-09-17')};
 const before=[...firestore.store];
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
 assert.deepEqual([...firestore.store],before);
 firestore.store.set(`bookingLifecycleReleaseBoundaries/${bookingId}`,{bookingId,providerId:booking.providerId,parentId:booking.parentId,policyVersion:'continuous_v1'});
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NO_SHOW_FINALIZED');
});

test('unversioned canonical multi-slot schedule accepted by the old deadline still processes',async()=>{
 const {bookingId,booking,privateDoc}=buildMultiSegmentConfirmedBookingSeed();
 const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingPrivate/${bookingId}`]:privateDoc});
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3({firestore,bookingId,authoritativeNow:new Date('2026-09-17')}),'NO_SHOW_FINALIZED');
});

test('historical combined-segment no-show requires valid boundary identity or explicit Phase 2',async()=>{
 const {bookingId,booking,privateDoc}=buildMultiSegmentConfirmedBookingSeed();
 booking.schedule.segments=[{...booking.schedule.segments[0],endAt:booking.schedule.finalEndAt,durationMinutes:120,slotIds:['slot-1','slot-2']}];
 booking.schedule.segmentCount=1;booking.schedule.firstSegmentEndAt=booking.schedule.finalEndAt;
 const firestore=new FakeFirestore({[`bookings/${bookingId}`]:booking,[`bookingPrivate/${bookingId}`]:privateDoc,
  [`bookingLifecycleReleaseBoundaries/${bookingId}`]:{bookingId,providerId:'wrong',parentId:booking.parentId,policyVersion:'continuous_v1'}});
 const args={firestore,bookingId,authoritativeNow:new Date('2026-09-17')};
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
 assert.equal(await reconcileCanonicalServiceStartArtifactsV3({...args,allowHistoricalRecovery:true}),'NO_SHOW_FINALIZED');
});
