import {Timestamp} from "firebase-admin/firestore";

type SerializedTimestampLike = {
  seconds: number | string;
  nanoseconds?: number | string;
};

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function asSerializedTimestampLike(
  value: unknown,
): SerializedTimestampLike | null {
  if (typeof value !== "object" || value == null) {
    return null;
  }
  const candidate = value as Partial<SerializedTimestampLike>;
  if (!("seconds" in candidate)) {
    return null;
  }
  return {
    seconds: candidate.seconds as number | string,
    nanoseconds: candidate.nanoseconds,
  };
}

export function normalizeTimestampLike(value: unknown): Date | null {
  if (value == null) {
    return null;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (
    typeof value === "object" &&
    value != null &&
    "toDate" in value &&
    typeof (value as {toDate?: unknown}).toDate === "function"
  ) {
    try {
      const date = (value as {toDate: () => unknown}).toDate();
      return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
    } catch (_) {
      return null;
    }
  }

  const serialized = asSerializedTimestampLike(value);
  if (serialized == null) {
    return null;
  }

  const seconds = asFiniteNumber(serialized.seconds);
  const nanoseconds = asFiniteNumber(serialized.nanoseconds ?? 0);
  if (seconds == null || !Number.isInteger(seconds)) {
    return null;
  }
  if (nanoseconds == null || !Number.isInteger(nanoseconds)) {
    return null;
  }
  if (nanoseconds < 0 || nanoseconds > 999999999) {
    return null;
  }

  const millis = seconds * 1000 + Math.trunc(nanoseconds / 1000000);
  const date = new Date(millis);
  return Number.isNaN(date.getTime()) ? null : date;
}
