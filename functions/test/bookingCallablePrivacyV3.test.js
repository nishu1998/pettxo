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

function extractFunctionBody(functionName) {
  const signature = `function ${functionName}`;
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `${functionName} was not found`);

  const declarationEnd = source.indexOf("}):", start);
  assert.notEqual(declarationEnd, -1, `${functionName} declaration end was not found`);
  const braceStart = source.indexOf("{", declarationEnd);
  let depth = 0;
  for (let index = braceStart; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(braceStart + 1, index);
      }
    }
  }
  throw new Error(`Could not extract ${functionName}`);
}

function assertNoPrivateTerms(body, reason) {
  for (const forbidden of [
    "otpCode",
    "phone",
    "phoneNumber",
    "address",
    "serviceAddress",
    "latitude",
    "longitude",
    "bookingPrivate",
    "storage",
    "secret",
    "razorpaySignature",
  ]) {
    assert.equal(
      body.includes(forbidden),
      false,
      `${reason} should not contain ${forbidden}`,
    );
  }
}

test("buildPaymentOrderResponse exposes only safe order fields", () => {
  const body = extractFunctionBody("buildPaymentOrderResponse");

  assert.equal(body.includes("bookingId:"), true);
  assert.equal(body.includes("paymentAttemptId:"), true);
  assert.equal(body.includes('mode: "zero_payable"'), true);
  assert.equal(body.includes('mode: "razorpay"'), true);
  assert.equal(body.includes("keyId:"), true);
  assert.equal(body.includes("razorpayOrderId:"), true);
  assert.equal(body.includes("amountPaise:"), true);
  assert.equal(body.includes("currency:"), true);
  assert.equal(body.includes("pricingSummary"), true);
  assert.equal(body.includes("expiresAt:"), true);
  assert.equal(body.includes("state:"), true);
  assert.equal(body.includes("confirmedAt:"), true);
  assert.equal(body.includes("idempotentReplay:"), true);

  assertNoPrivateTerms(body, "buildPaymentOrderResponse");
});

test("buildPaymentVerificationResponse exposes only safe verification fields", () => {
  const body = extractFunctionBody("buildPaymentVerificationResponse");

  assert.equal(body.includes("bookingId:"), true);
  assert.equal(body.includes("paymentAttemptId:"), true);
  assert.equal(body.includes("status:"), true);
  assert.equal(body.includes("state:"), true);
  assert.equal(body.includes("confirmedAt:"), true);
  assert.equal(body.includes("payDeadlineAt:"), true);
  assert.equal(body.includes("idempotentReplay:"), true);

  assertNoPrivateTerms(body, "buildPaymentVerificationResponse");
});

test("payment request logging payloads remain free of private booking details", () => {
  const paymentLogBlocks = [...source.matchAll(/logRequestEvent\("payment_[^"]+",\s*\{([\s\S]*?)\}\);/g)];
  assert.ok(paymentLogBlocks.length >= 2);

  for (const [, body] of paymentLogBlocks) {
    assertNoPrivateTerms(body, "payment log payload");
  }
});
