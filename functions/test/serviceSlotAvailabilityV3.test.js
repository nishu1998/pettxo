const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  buildCustomerBookableSlotsV3,
} = require("../lib/booking/application/serviceSlotAvailabilityV3.js");

const now = new Date("2026-09-14T00:00:00.000Z");
const service = {
  ownerUserId: "provider-1",
  status: "active",
  isActive: true,
  isDeleted: false,
  isPaused: false,
  isVisibleToMarketplace: true,
  providerVerificationStatus: "approved",
  availableDays: ["Mon"],
  startMinutes: 540,
  endMinutes: 600,
  sessionDurationMinutes: 60,
  capacity: 1,
};
const slot = {
  id: "2026-09-14_0540",
  serviceId: "service-1",
  serviceOwnerId: "provider-1",
  startAt: new Date("2026-09-14T03:30:00.000Z"),
  endAt: new Date("2026-09-14T04:30:00.000Z"),
  dateKey: "2026-09-14",
  capacity: 1,
  acceptedCount: 0,
  isBookable: true,
  status: "open",
};

function visible({servicePatch = {}, slotPatch = {}, occupancy, authoritativeNow = now} = {}) {
  const currentSlot = {...slot, ...slotPatch};
  const occupancyBySlotId = new Map();
  if (occupancy !== undefined) occupancyBySlotId.set(currentSlot.id, occupancy);
  return buildCustomerBookableSlotsV3({
    serviceId: "service-1",
    service: {...service, ...servicePatch},
    dateKey: "2026-09-14",
    slots: [currentSlot],
    occupancyBySlotId,
    authoritativeNow,
  });
}

test("capacity 1 with zero confirmed bookings is visible", () => {
  assert.equal(visible().length, 1);
  assert.equal(visible()[0].confirmedUnits, 0);
});

test("capacity 1 with one confirmed booking is hidden", () => {
  assert.deepEqual(visible({occupancy: {confirmedUnits: 1}}), []);
});

test("partial occupancy remains visible with accurate remaining capacity inputs", () => {
  const result = visible({
    servicePatch: {capacity: 3},
    slotPatch: {capacity: 3},
    occupancy: {confirmedUnits: 2},
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].capacity - result[0].confirmedUnits, 1);
});

test("multi-unit slot is hidden when canonical occupancy reaches capacity", () => {
  assert.deepEqual(visible({
    servicePatch: {capacity: 3},
    slotPatch: {capacity: 3},
    occupancy: {confirmedUnits: 3},
  }), []);
});

test("cancellation release makes the slot visible on the next availability build", () => {
  assert.equal(visible({occupancy: {confirmedUnits: 1}}).length, 0);
  assert.equal(visible({occupancy: {confirmedUnits: 0}}).length, 1);
});

test("past or runway-ineligible slots are hidden", () => {
  assert.deepEqual(visible({authoritativeNow: new Date("2026-09-14T01:01:00.000Z")}), []);
  assert.deepEqual(visible({authoritativeNow: new Date("2026-09-14T05:00:00.000Z")}), []);
});

for (const servicePatch of [
  {status: "removed"},
  {isActive: false},
  {isPaused: true},
  {isVisibleToMarketplace: false},
  {isPausedByVerification: true},
]) {
  test(`unavailable service/provider is hidden: ${JSON.stringify(servicePatch)}`, () => {
    assert.deepEqual(visible({servicePatch}), []);
  });
}

test("closed or non-bookable slots are hidden", () => {
  assert.deepEqual(visible({slotPatch: {status: "closed"}}), []);
  assert.deepEqual(visible({slotPatch: {isBookable: false}}), []);
});

test("a retained slot that no longer matches the current provider schedule is hidden", () => {
  assert.deepEqual(visible({servicePatch: {availableDays: ["Tue"]}}), []);
});

test("a valid legacy day-care slot ID remains visible when its window matches", () => {
  assert.equal(visible({
    servicePatch: {schedulingMode: "dayCare", sessionDurationMinutes: 0},
  }).length, 1);
});

test("stale-low acceptedCount cannot expose canonically full capacity", () => {
  assert.deepEqual(visible({
    slotPatch: {acceptedCount: 0},
    occupancy: {confirmedUnits: 1},
  }), []);
});

test("stale-high acceptedCount cannot hide canonically free capacity", () => {
  const result = visible({
    slotPatch: {acceptedCount: 1},
    occupancy: {confirmedUnits: 0},
  });
  assert.equal(result.length, 1);
});

test("customer response contains no booking claims or acceptedCount projection", () => {
  const [result] = visible({
    slotPatch: {acceptedCount: 99},
    occupancy: {confirmedUnits: 0, bookingClaims: {privateBookingId: 1}},
  });
  assert.equal(Object.hasOwn(result, "acceptedCount"), false);
  assert.equal(Object.hasOwn(result, "bookingClaims"), false);
  assert.equal(JSON.stringify(result).includes("privateBookingId"), false);
});

test("callable batches occupancy reads and does not expose slotOccupancy directly", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "../src/booking/bookingV3FlowFunctions.ts"),
    "utf8",
  );
  const start = source.indexOf("export const listBookableServiceSlotsV3");
  const end = source.indexOf("export const createBookingRequestV3", start);
  const body = source.slice(start, end);
  assert.ok(body.includes("await db.getAll("));
  assert.equal(body.includes("bookingClaims"), false);
});
