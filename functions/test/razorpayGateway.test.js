const test = require("node:test");
const assert = require("node:assert/strict");

const {HttpsError} = require("firebase-functions/https");
const {
  createRazorpayQrCodeV3,
} = require("../lib/booking/application/razorpayGateway.js");

test("createRazorpayQrCodeV3 maps nested Razorpay feature errors safely", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: false,
    status: 400,
    async text() {
      return JSON.stringify({
        error: {
          code: "BAD_REQUEST_ERROR",
          description: "QR payments feature is not enabled on this account.",
          reason: "feature_disabled",
          source: "business",
          step: "payment_initiation",
        },
      });
    },
  });

  try {
    await assert.rejects(
      createRazorpayQrCodeV3({
        keyId: "key_id",
        keySecret: "key_secret",
        bookingId: "booking-1",
        paymentAttemptId: "attempt-1",
        customerUid: "customer-1",
        amountPaise: 5000,
        currency: "INR",
        closeBy: new Date("2026-08-16T10:30:00.000Z"),
        notes: {},
      }),
      (error) => {
        assert.equal(error instanceof HttpsError, true);
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.message,
          "QR payments are not available on this payment account right now.",
        );
        assert.equal(error.details.code, "QR_FEATURE_UNAVAILABLE");
        assert.equal(
          error.details.razorpay.description,
          "QR payments feature is not enabled on this account.",
        );
        return true;
      },
    );
  } finally {
    global.fetch = originalFetch;
  }
});

test("createRazorpayQrCodeV3 maps nested amount validation errors safely", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: false,
    status: 400,
    async text() {
      return JSON.stringify({
        error: {
          code: "BAD_REQUEST_ERROR",
          description: "The payment amount must be at least 1.",
          field: "payment_amount",
        },
      });
    },
  });

  try {
    await assert.rejects(
      createRazorpayQrCodeV3({
        keyId: "key_id",
        keySecret: "key_secret",
        bookingId: "booking-1",
        paymentAttemptId: "attempt-1",
        customerUid: "customer-1",
        amountPaise: 0,
        currency: "INR",
        closeBy: new Date("2026-08-16T10:30:00.000Z"),
        notes: {},
      }),
      (error) => {
        assert.equal(error instanceof HttpsError, true);
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.message,
          "This payment amount is not supported for QR payments.",
        );
        assert.equal(error.details.code, "QR_AMOUNT_NOT_SUPPORTED");
        return true;
      },
    );
  } finally {
    global.fetch = originalFetch;
  }
});

test("createRazorpayQrCodeV3 rejects malformed successful payloads", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: true,
    status: 200,
    async text() {
      return JSON.stringify({
        id: "qr_123",
        status: "active",
        payment_amount: 5000,
        currency: "INR",
      });
    },
  });

  try {
    await assert.rejects(
      createRazorpayQrCodeV3({
        keyId: "key_id",
        keySecret: "key_secret",
        bookingId: "booking-1",
        paymentAttemptId: "attempt-1",
        customerUid: "customer-1",
        amountPaise: 5000,
        currency: "INR",
        closeBy: new Date("2026-08-16T10:30:00.000Z"),
        notes: {},
      }),
      (error) => {
        assert.equal(error instanceof HttpsError, true);
        assert.equal(error.code, "internal");
        assert.equal(
          error.message,
          "Razorpay QR code details were incomplete.",
        );
        return true;
      },
    );
  } finally {
    global.fetch = originalFetch;
  }
});
