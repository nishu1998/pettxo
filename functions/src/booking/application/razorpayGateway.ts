import {createHmac, timingSafeEqual} from "node:crypto";

import {HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

export type RazorpayPaymentRecord = {
  id: string;
  orderId: string;
  status: string;
  amountPaise: number;
  currency: string;
  createdAt: Date | null;
  capturedAt: Date | null;
  receipt: string;
  notes: Record<string, string>;
};

export type RazorpayQrCodeRecord = {
  id: string;
  status: string;
  imageUrl: string;
  amountPaise: number;
  currency: string;
  closeBy: Date | null;
  closedAt: Date | null;
  closeReason: string;
};

type RazorpayApiErrorDetails = {
  httpStatus: number;
  code: string;
  description: string;
  reason: string;
  source: string;
  step: string;
  field: string;
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

function asStringRecord(value: unknown): Record<string, string> {
  if (typeof value !== "object" || value == null) return {};
  const record: Record<string, string> = {};
  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    const normalized = asString(entry);
    if (normalized) record[key] = normalized;
  }
  return record;
}

function asObject(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
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

function razorpayApiErrorDetails(
  httpStatus: number,
  data: Record<string, unknown>,
): RazorpayApiErrorDetails {
  const nestedError = asObject(data.error);
  return {
    httpStatus,
    code: asString(nestedError.code || data.error_code),
    description: asString(
      nestedError.description ||
      data.error_description ||
      data.description ||
      data.error,
    ),
    reason: asString(nestedError.reason || data.reason),
    source: asString(nestedError.source || data.source),
    step: asString(nestedError.step || data.step),
    field: asString(nestedError.field || data.field),
  };
}

function classifyRazorpayApiError(
  operation: string,
  details: RazorpayApiErrorDetails,
  defaultError: string,
): {
  error: HttpsError;
  applicationCode: string;
} {
  const haystack = [
    details.code,
    details.description,
    details.reason,
    details.source,
    details.step,
    details.field,
  ].join(" ").toLowerCase();

  if (
    haystack.includes("feature") ||
    haystack.includes("not enabled") ||
    haystack.includes("not available") ||
    haystack.includes("unsupported")
  ) {
    return {
      applicationCode: "QR_FEATURE_UNAVAILABLE",
      error: new HttpsError(
        "failed-precondition",
        "QR payments are not available on this payment account right now.",
        {
          code: "QR_FEATURE_UNAVAILABLE",
          razorpay: details,
          operation,
        },
      ),
    };
  }

  if (
    haystack.includes("payment amount must be at least") ||
    haystack.includes("minimum amount")
  ) {
    return {
      applicationCode: "QR_AMOUNT_NOT_SUPPORTED",
      error: new HttpsError(
        "failed-precondition",
        "This payment amount is not supported for QR payments.",
        {
          code: "QR_AMOUNT_NOT_SUPPORTED",
          razorpay: details,
          operation,
        },
      ),
    };
  }

  if (haystack.includes("close_by")) {
    return {
      applicationCode: "QR_CONFIGURATION_INVALID",
      error: new HttpsError(
        "failed-precondition",
        "This booking's payment window is not compatible with QR creation right now.",
        {
          code: "QR_CONFIGURATION_INVALID",
          razorpay: details,
          operation,
        },
      ),
    };
  }

  if (
    details.httpStatus >= 400 &&
    details.httpStatus < 500
  ) {
    return {
      applicationCode: "QR_CREATION_REJECTED",
      error: new HttpsError(
        "failed-precondition",
        details.description || defaultError,
        {
          code: "QR_CREATION_REJECTED",
          razorpay: details,
          operation,
        },
      ),
    };
  }

  return {
    applicationCode: "QR_CREATION_REJECTED",
    error: new HttpsError("internal", details.description || defaultError, {
      code: "QR_CREATION_REJECTED",
      razorpay: details,
      operation,
    }),
  };
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
    receipt: asString(data.receipt),
    notes: asStringRecord(data.notes),
  };
}

function qrCodeRecordFromApi(data: Record<string, unknown>): RazorpayQrCodeRecord {
  return {
    id: asString(data.id),
    status: asString(data.status),
    imageUrl: asString(data.image_url),
    amountPaise: asInt(data.payment_amount, 0),
    currency: asString(data.currency) || "INR",
    closeBy: asNullableDateFromEpochSeconds(data.close_by),
    closedAt: asNullableDateFromEpochSeconds(data.closed_at),
    closeReason: asString(data.close_reason),
  };
}

async function razorpayJsonRequest(params: {
  keyId: string;
  keySecret: string;
  url: string;
  method: "GET" | "POST";
  body?: Record<string, unknown>;
  defaultError: string;
  operation: string;
}): Promise<Record<string, unknown>> {
  requireCredentials(params.keyId, params.keySecret);
  const response = await fetch(params.url, {
    method: params.method,
    headers: {
      Authorization: encodeBasicAuth(params.keyId, params.keySecret),
      "Content-Type": "application/json",
    },
    body: params.body == null ? undefined : JSON.stringify(params.body),
  });
  const data = await parseJsonResponse(response);
  if (!response.ok) {
    const details = razorpayApiErrorDetails(response.status, data);
    logger.warn("razorpay-api-request-failed", {
      operation: params.operation,
      httpStatus: details.httpStatus,
      errorCode: details.code,
      errorDescription: details.description,
      errorReason: details.reason,
      errorSource: details.source,
      errorStep: details.step,
      errorField: details.field,
    });
    throw classifyRazorpayApiError(
      params.operation,
      details,
      params.defaultError,
    ).error;
  }
  return data;
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

export async function createRazorpayQrCodeV3(params: {
  keyId: string;
  keySecret: string;
  bookingId: string;
  paymentAttemptId: string;
  amountPaise: number;
  currency: string;
  closeBy: Date;
  notes: Record<string, string>;
  name?: string;
  description?: string;
}): Promise<RazorpayQrCodeRecord> {
  const data = await razorpayJsonRequest({
    keyId: params.keyId,
    keySecret: params.keySecret,
    url: "https://api.razorpay.com/v1/payments/qr_codes",
    method: "POST",
    body: {
  type: "upi_qr",
  usage: "single_use",
  fixed_amount: true,
  payment_amount: Math.max(params.amountPaise, 0),
  close_by: Math.floor(params.closeBy.getTime() / 1000),
  name: params.name || "Pettxo Booking Payment",
  description: params.description || `Booking ${params.bookingId}`,
  notes: {
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttemptId,
    purpose: "booking",
    ...params.notes,
  },
},
    defaultError: "Unable to create Razorpay QR right now.",
    operation: "create_qr_code",
  });
  const qr = qrCodeRecordFromApi(data);
  if (!qr.id || !qr.imageUrl) {
    throw new HttpsError("internal", "Razorpay QR code details were incomplete.");
  }
  return qr;
}

export async function closeRazorpayQrCodeV3(params: {
  keyId: string;
  keySecret: string;
  qrCodeId: string;
}): Promise<RazorpayQrCodeRecord> {
  const data = await razorpayJsonRequest({
    keyId: params.keyId,
    keySecret: params.keySecret,
    url: `https://api.razorpay.com/v1/payments/qr_codes/${encodeURIComponent(params.qrCodeId)}/close`,
    method: "POST",
    defaultError: "Unable to close Razorpay QR right now.",
    operation: "close_qr_code",
  });
  return qrCodeRecordFromApi(data);
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
