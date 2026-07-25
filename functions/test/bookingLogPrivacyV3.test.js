const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const FORBIDDEN_TOKENS = [
  "otpCode",
  "parentOtpCode",
  "providerOtpHash",
  "phoneNumber",
  "serviceAddress",
  "latitude",
  "longitude",
  "bookingPrivate",
  "razorpay_signature",
  "keySecret",
  "RAZORPAY_KEY_SECRET",
  "rawBody",
  "raw webhook body",
];

function read(relativePath) {
  return fs.readFileSync(path.join(__dirname, "..", relativePath), "utf8");
}

function assertSafeLogBodies(source, label) {
  const logBodies = [
    ...source.matchAll(/console\.(?:info|log|warn|error)\([^,]+,\s*(\{[\s\S]*?\})\);/g),
  ].map((match) => match[1]);

  for (const body of logBodies) {
    for (const token of FORBIDDEN_TOKENS) {
      assert.equal(
        body.includes(token),
        false,
        `${label} log payload leaked ${token}`,
      );
    }
  }
}

test("booking callable logging payloads stay free of private payment details", () => {
  const source = read("src/booking/bookingV3FlowFunctions.ts");
  assertSafeLogBodies(source, "bookingV3FlowFunctions.ts");
});

test("canonical webhook routing emits no direct console logs with raw gateway payloads", () => {
  const source = read("src/booking/application/canonicalPaymentWebhookV3.ts");
  assert.equal(/console\.(?:info|log|warn|error)\(/.test(source), false);
});

test("webhook envelope processing emits no direct console logs with raw webhook bodies", () => {
  const source = read("src/booking/application/paymentWebhookEventsV3.ts");
  assert.equal(/console\.(?:info|log|warn|error)\(/.test(source), false);
});

test("payment orchestration emits no direct console logs with booking-private data", () => {
  const source = read("src/booking/application/paymentOrchestrationV3.ts");
  assert.equal(/console\.(?:info|log|warn|error)\(/.test(source), false);
});
