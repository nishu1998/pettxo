const test = require("node:test");
const assert = require("node:assert/strict");

const {
  generateSlotWindows,
  normalizeServiceSchedulingMode,
  resolveSessionDurationMinutes,
  SERVICE_SCHEDULING_MODE_DAY_CARE,
  SERVICE_SCHEDULING_MODE_FIXED_DURATION,
  SERVICE_SCHEDULING_MODE_OVERNIGHT,
  SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
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

test("09:00-17:00 hourly availability includes the closing boundary exactly", () => {
  const slots = generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_FIXED_DURATION,
    sessionDurationMinutes: 60,
    startMinutes: 9 * 60,
    endMinutes: 17 * 60,
  });

  assert.equal(slots.length, 8);
  assert.deepEqual(slots[0], {
    startMinutes: 9 * 60,
    endMinutes: 10 * 60,
    durationMinutes: 60,
  });
  assert.deepEqual(slots.at(-1), {
    startMinutes: 16 * 60,
    endMinutes: 17 * 60,
    durationMinutes: 60,
  });
  assert.ok(slots.every((slot) =>
    slot.startMinutes >= 9 * 60 && slot.endMinutes <= 17 * 60));
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

test("overnight scheduling generates exactly one next-day slot", () => {
  const slots = generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_OVERNIGHT,
    startMinutes: 19 * 60,
    endMinutes: 10 * 60,
  });

  assert.deepEqual(slots, [
    {startMinutes: 1140, endMinutes: 600, durationMinutes: 900},
  ]);
  assert.equal(
    resolveSessionDurationMinutes({
      schedulingMode: SERVICE_SCHEDULING_MODE_OVERNIGHT,
      startMinutes: 19 * 60,
      endMinutes: 10 * 60,
    }),
    900,
  );
});

test("overnight rejects same-day or 24-hour windows", () => {
  assert.deepEqual(generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_OVERNIGHT,
    startMinutes: 19 * 60,
    endMinutes: 20 * 60,
  }), []);
  assert.equal(
    resolveSessionDurationMinutes({
      schedulingMode: SERVICE_SCHEDULING_MODE_OVERNIGHT,
      startMinutes: 19 * 60,
      endMinutes: 19 * 60,
    }),
    0,
  );
});

test("24-hour scheduling generates exactly one full-day slot", () => {
  const slots = generateSlotWindows({
    schedulingMode: SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
    startMinutes: 8 * 60,
    endMinutes: 8 * 60,
  });

  assert.deepEqual(slots, [
    {startMinutes: 480, endMinutes: 480, durationMinutes: 1440},
  ]);
  assert.equal(
    normalizeServiceSchedulingMode({
      schedulingMode: SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
      sessionDurationMinutes: 24 * 60,
    }),
    SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
  );
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
