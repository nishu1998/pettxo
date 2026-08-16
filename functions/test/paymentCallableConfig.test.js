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

test("canonical payment callables share the explicit private callable policy", () => {
  const source = fs.readFileSync(sourcePath, "utf8");

  assert.match(
    source,
    /const canonicalPrivateCallableOptions = \{[\s\S]*region: "asia-south1" as const,[\s\S]*invoker: "private" as const,[\s\S]*enforceAppCheck: false,[\s\S]*\}/,
  );
  assert.match(
    source,
    /const canonicalPrivateRazorpayCallableOptions = \{[\s\S]*\.\.\.canonicalPrivateCallableOptions,[\s\S]*secrets: \[RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET\],[\s\S]*\}/,
  );
  assert.match(
    source,
    /export const createRazorpayPaymentOrderV3 = onCall\(\s*canonicalPrivateRazorpayCallableOptions,/,
  );
  assert.match(
    source,
    /export const createBookingQrPaymentV3 = onCall\(\s*canonicalPrivateRazorpayCallableOptions,/,
  );
  assert.match(
    source,
    /export const previewBookingPaymentPricingV3 = onCall\(\s*canonicalPrivateCallableOptions,/,
  );
  assert.match(
    source,
    /export const verifyBookingPaymentV3 = onCall\(\s*canonicalPrivateRazorpayCallableOptions,/,
  );
});
