import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  getAvailableOffersForUser,
} from "../application/getAvailableOffersApplication";

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalFiniteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export function assertAuthenticatedOfferUid(uid: string): void {
  if (uid) return;
  throw new HttpsError("unauthenticated", "Sign in to continue.");
}

export const getAvailableOffers = onCall(async (request) => {
  const uid = asTrimmedString(request.auth?.uid);
  assertAuthenticatedOfferUid(uid);

  const data =
    request.data && typeof request.data === "object" && !Array.isArray(request.data) ?
      request.data as Record<string, unknown> :
      {};
  const context =
    data.context && typeof data.context === "object" && !Array.isArray(data.context) ?
      data.context as Record<string, unknown> :
      {};

  return getAvailableOffersForUser({
    uid,
    bookingContext: {
      bookingAmount: asOptionalFiniteNumber(context.bookingAmount),
      serviceId: asTrimmedString(context.serviceId),
      providerId: asTrimmedString(context.providerId),
      serviceCategory: asTrimmedString(
        context.serviceCategory ?? context.category,
      ),
    },
  });
});
