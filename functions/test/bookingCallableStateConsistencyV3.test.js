const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sourcePath = path.join(
  __dirname,
  "..",
  "src",
  "booking",
  "bookingV3FlowFunctions.ts",
);
const source = fs.readFileSync(sourcePath, "utf8");

test("provider accept and decline callables authorize queued and active request states through the shared actionable-state constant", () => {
  assert.match(
    source,
    /acceptBookingRequestV3[\s\S]*?allowedStates:\s*\[\.\.\.ACTIONABLE_PROVIDER_REQUEST_STATES\]/,
  );
  assert.match(
    source,
    /declineBookingRequestV3[\s\S]*?allowedStates:\s*\[\.\.\.ACTIONABLE_PROVIDER_REQUEST_STATES\]/,
  );
});

test("provider-request expiry scheduler scans the same actionable raw states used by provider actions", () => {
  assert.match(
    source,
    /for\s*\(const state of ACTIONABLE_PROVIDER_REQUEST_STATES\)\s*\{[\s\S]*?where\("stateQueryValue", "==", state\)[\s\S]*?where\("acceptDeadlineAt", "<=", Timestamp\.fromDate\(authoritativeNow\)\)/,
  );
});

test("create-order authorization blocks new payment orders once a capture or refund-resolution state exists", () => {
  assert.match(
    source,
    /const requiresContinuationOnly =[\s\S]*?"CAPTURE_REPORTED"[\s\S]*?"CAPTURED_REQUIRES_RECONCILIATION"[\s\S]*?"REFUND_REQUIRED"[\s\S]*?"REFUND_PENDING"[\s\S]*?if \(params\.command === "create_order"\) \{[\s\S]*?if \(requiresContinuationOnly\) \{[\s\S]*?code: "PAYMENT_RECONCILIATION_REQUIRED"/,
  );
});
