import {Timestamp} from "firebase-admin/firestore";

export type OfferWallUserState = {
  campaignId: string;
  uid: string;
  eligibleOpenCount: number;
  impressionsShown: number;
  lastShownAt: Date | null;
  completedAt: Date | null;
  lastCountedSessionId: string;
  pendingDisplayToken: string;
  pendingSessionId: string;
  pendingIssuedAt: Date | null;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNonNegativeInt(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ?
    value :
    0;
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

export function normalizeOfferWallUserState(params: {
  uid: string;
  campaignId: string;
  data: Record<string, unknown> | undefined;
}): OfferWallUserState {
  const data = params.data ?? {};
  return {
    campaignId: asTrimmedString(data.campaignId) || params.campaignId,
    uid: asTrimmedString(data.uid) || params.uid,
    eligibleOpenCount: asNonNegativeInt(data.eligibleOpenCount),
    impressionsShown: asNonNegativeInt(data.impressionsShown),
    lastShownAt: asDate(data.lastShownAt),
    completedAt: asDate(data.completedAt),
    lastCountedSessionId: asTrimmedString(data.lastCountedSessionId),
    pendingDisplayToken: asTrimmedString(data.pendingDisplayToken),
    pendingSessionId: asTrimmedString(data.pendingSessionId),
    pendingIssuedAt: asDate(data.pendingIssuedAt),
  };
}
