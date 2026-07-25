import {createHmac, timingSafeEqual} from "node:crypto";

import {HttpsError} from "firebase-functions/https";

export type RazorpayPaymentRecord = {
  id: string;
  orderId: string;
  status: string;
  amountPaise: number;
  currency: string;
  createdAt: Date | null;
  capturedAt: Date | null;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.trunc(value) :
    fallback;
}

function asNullableDateFromEpochSeconds(value: unknown): Date | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return null;
  return new Date(value * 1000);
}

function encodeBasicAuth(keyId: string, keySecret: string): string {
  return `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`;
}

function requireCredentials(keyId: string, keySecret: string): void {
  if (!keyId.trim() || !keySecret.trim()) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay credentials are not configured in Functions.",
    );
  }
}

async function parseJsonResponse(response: Response): Promise<Record<string, unknown>> {
  const raw = await response.text();
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, unknown>;
  } catch (_) {
    return {};
  }
}

function paymentRecordFromApi(data: Record<string, unknown>): RazorpayPaymentRecord {
  return {
    id: asString(data.id),
    orderId: asString(data.order_id),
    status: asString(data.status),
    amountPaise: asInt(data.amount, 0),
    currency: asString(data.currency) || "INR",
    createdAt: asNullableDateFromEpochSeconds(data.created_at),
    capturedAt: asNullableDateFromEpochSeconds(data.captured_at),
  };
}

export async function createRazorpayOrderV3(params: {
  keyId: string;
  keySecret: string;
  bookingId: string;
  paymentAttemptId: string;
  amountPaise: number;
  currency: string;
  notes: Record<string, string>;
}): Promise<{
  orderId: string;
  amountPaise: number;
  currency: string;
  keyId: string;
}> {
  requireCredentials(params.keyId, params.keySecret);
  const response = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      Authorization: encodeBasicAuth(params.keyId, params.keySecret),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: Math.max(params.amountPaise, 0),
      currency: params.currency || "INR",
      receipt: params.bookingId,
      notes: params.notes,
    }),
  });
  const data = await parseJsonResponse(response);
  if (!response.ok) {
    throw new HttpsError(
      "internal",
      asString(data.error_description ?? data.error ?? data.description) ||
        "Unable to create Razorpay order right now.",
    );
  }
  const orderId = asString(data.id);
  if (!orderId) {
    throw new HttpsError("internal", "Razorpay order ID was missing.");
  }
  return {
    orderId,
    amountPaise: asInt(data.amount, params.amountPaise),
    currency: asString(data.currency) || params.currency || "INR",
    keyId: params.keyId.trim(),
  };
}

export function verifyRazorpayPaymentSignature(params: {
  keySecret: string;
  orderId: string;
  paymentId: string;
  signature: string;
}): boolean {
  requireCredentials("configured", params.keySecret);
  const expected = createHmac("sha256", params.keySecret)
    .update(`${params.orderId}|${params.paymentId}`)
    .digest("hex");
  const expectedBuffer = Buffer.from(expected, "utf8");
  const signatureBuffer = Buffer.from(params.signature, "utf8");
  return expectedBuffer.length === signatureBuffer.length &&
    timingSafeEqual(expectedBuffer, signatureBuffer);
}

export function verifyRazorpayWebhookSignatureV3(params: {
  webhookSecret: string;
  rawBody: Buffer;
  signature: string;
}): boolean {
  if (!params.webhookSecret.trim()) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay webhook secret is not configured in Functions.",
    );
  }
  const expected = createHmac("sha256", params.webhookSecret)
    .update(params.rawBody)
    .digest("hex");
  const expectedBuffer = Buffer.from(expected, "utf8");
  const signatureBuffer = Buffer.from(params.signature, "utf8");
  return expectedBuffer.length === signatureBuffer.length &&
    timingSafeEqual(expectedBuffer, signatureBuffer);
}

export async function fetchRazorpayPaymentV3(params: {
  keyId: string;
  keySecret: string;
  paymentId: string;
}): Promise<RazorpayPaymentRecord> {
  requireCredentials(params.keyId, params.keySecret);
  const response = await fetch(
    `https://api.razorpay.com/v1/payments/${encodeURIComponent(params.paymentId)}`,
    {
      method: "GET",
      headers: {
        Authorization: encodeBasicAuth(params.keyId, params.keySecret),
        "Content-Type": "application/json",
      },
    },
  );
  const data = await parseJsonResponse(response);
  if (!response.ok) {
    throw new HttpsError(
      "internal",
      asString(data.error_description ?? data.error ?? data.description) ||
        "Unable to verify Razorpay payment.",
    );
  }
  return paymentRecordFromApi(data);
}

export async function fetchRazorpayOrderPaymentsV3(params: {
  keyId: string;
  keySecret: string;
  orderId: string;
}): Promise<RazorpayPaymentRecord[]> {
  requireCredentials(params.keyId, params.keySecret);
  const response = await fetch(
    `https://api.razorpay.com/v1/orders/${encodeURIComponent(params.orderId)}/payments`,
    {
      method: "GET",
      headers: {
        Authorization: encodeBasicAuth(params.keyId, params.keySecret),
        "Content-Type": "application/json",
      },
    },
  );
  const data = await parseJsonResponse(response);
  if (!response.ok) {
    throw new HttpsError(
      "internal",
      asString(data.error_description ?? data.error ?? data.description) ||
        "Unable to verify Razorpay order payments.",
    );
  }
  const items = Array.isArray(data.items) ? data.items : [];
  return items.map((item) => paymentRecordFromApi(
    typeof item === "object" && item != null ? item as Record<string, unknown> : {},
  ));
}

export async function resolveCapturedRazorpayPaymentV3(params: {
  keyId: string;
  keySecret: string;
  paymentId: string;
  orderId: string;
  attempts?: number;
  delayMs?: number;
}): Promise<RazorpayPaymentRecord> {
  const maxAttempts = Math.max(params.attempts ?? 5, 1);
  const delayMs = Math.max(params.delayMs ?? 1500, 250);
  let lastPayment = await fetchRazorpayPaymentV3(params);
  if (lastPayment.orderId !== params.orderId) {
    throw new HttpsError("failed-precondition", "Razorpay payment order mismatch.");
  }
  if (lastPayment.status === "captured") {
    return lastPayment;
  }
  for (let attempt = 1; attempt < maxAttempts; attempt += 1) {
    const orderPayments = await fetchRazorpayOrderPaymentsV3(params);
    const capturedMatch = orderPayments.find((payment) =>
      payment.id === params.paymentId && payment.status === "captured",
    );
    if (capturedMatch) {
      return capturedMatch;
    }
    await new Promise((resolve) => setTimeout(resolve, delayMs));
    lastPayment = await fetchRazorpayPaymentV3(params);
    if (lastPayment.orderId !== params.orderId) {
      throw new HttpsError("failed-precondition", "Razorpay payment order mismatch.");
    }
    if (lastPayment.status === "captured") {
      return lastPayment;
    }
  }
  throw new HttpsError("failed-precondition", "Razorpay payment is not captured yet.");
}

export async function processRazorpayRefundV3(params: {
  keyId: string;
  keySecret: string;
  razorpayPaymentId: string;
  refundAmountPaise: number;
  reason: string;
}): Promise<{
  status: "pending" | "processed" | "failed";
  razorpayRefundId: string;
  error: string;
  processedAt: Date | null;
}> {
  if (params.refundAmountPaise <= 0) {
    return {
      status: "processed",
      razorpayRefundId: "",
      error: "",
      processedAt: new Date(),
    };
  }
  requireCredentials(params.keyId, params.keySecret);
  if (!params.razorpayPaymentId.trim()) {
    return {
      status: "pending",
      razorpayRefundId: "",
      error: "Razorpay payment ID is missing for this booking.",
      processedAt: null,
    };
  }
  try {
    const response = await fetch(
      `https://api.razorpay.com/v1/payments/${encodeURIComponent(params.razorpayPaymentId)}/refund`,
      {
        method: "POST",
        headers: {
          Authorization: encodeBasicAuth(params.keyId, params.keySecret),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: Math.max(params.refundAmountPaise, 0),
          speed: "normal",
          notes: {reason: params.reason},
        }),
      },
    );
    const data = await parseJsonResponse(response);
    if (!response.ok) {
      return {
        status: "failed",
        razorpayRefundId: "",
        error: asString(data.error_description ?? data.error ?? data.description) ||
          "Unable to process Razorpay refund.",
        processedAt: null,
      };
    }
    return {
      status: "processed",
      razorpayRefundId: asString(data.id),
      error: "",
      processedAt: new Date(),
    };
  } catch (error) {
    return {
      status: "failed",
      razorpayRefundId: "",
      error: error instanceof Error ? error.message : "Unable to process Razorpay refund.",
      processedAt: null,
    };
  }
}
