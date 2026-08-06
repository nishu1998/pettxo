const test = require("node:test");
const assert = require("node:assert/strict");

const {
  generateSlotWindows,
  normalizeServiceSchedulingMode,
  resolveSessionDurationMinutes,
  SERVICE_SCHEDULING_MODE_DAY_CARE,
  SERVICE_SCHEDULING_MODE_FIXED_DURATION,
} = require("../lib/serviceScheduling");

test("fixed-duration scheduling generates repeating 180-minute slots", () => {
  const slots = generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_FIXED_DURATION,
    sessionDurationMinutes: 180,
    startMinutes: 9 * 60,
    endMinutes: 18 * 60,
  });

  assert.deepEqual(slots, [
    {startMinutes: 540, endMinutes: 720, durationMinutes: 180},
    {startMinutes: 720, endMinutes: 900, durationMinutes: 180},
    {startMinutes: 900, endMinutes: 1080, durationMinutes: 180},
  ]);
});

test("day care scheduling generates exactly one slot for the full range", () => {
  const slots = generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_DAY_CARE,
    startMinutes: 9 * 60,
    endMinutes: 18 * 60,
  });

  assert.deepEqual(slots, [
    {startMinutes: 540, endMinutes: 1080, durationMinutes: 540},
  ]);
});

test("day care rejects invalid same-day ranges", () => {
  assert.deepEqual(generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_DAY_CARE,
    startMinutes: 18 * 60,
    endMinutes: 9 * 60,
  }), []);
});

test("legacy whole-day metadata normalizes to day care", () => {
  assert.equal(
    normalizeServiceSchedulingMode({sessionDurationMinutes: 24 * 60}),
    SERVICE_SCHEDULING_MODE_DAY_CARE,
  );
  assert.equal(
    normalizeServiceSchedulingMode({schedulingMode: "wholeDay", sessionDurationMinutes: 0}),
    SERVICE_SCHEDULING_MODE_DAY_CARE,
  );
});

test("legacy 15-minute services remain fixed-duration and readable", () => {
  assert.equal(
    normalizeServiceSchedulingMode({sessionDurationMinutes: 15}),
    SERVICE_SCHEDULING_MODE_FIXED_DURATION,
  );
  assert.equal(
    resolveSessionDurationMinutes({
      schedulingMode: SERVICE_SCHEDULING_MODE_FIXED_DURATION,
      sessionDurationMinutes: 15,
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
    }),
    15,
  );
});
