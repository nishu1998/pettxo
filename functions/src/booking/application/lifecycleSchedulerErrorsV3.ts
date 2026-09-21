import {HttpsError} from "firebase-functions/https";

const transportCodes: Record<string, string> = {
  "4": "deadline-exceeded", "8": "resource-exhausted", "10": "aborted",
  "13": "internal", "14": "unavailable",
  "deadline-exceeded": "deadline-exceeded", "resource-exhausted": "resource-exhausted",
  aborted: "aborted", internal: "internal", unavailable: "unavailable",
};
/** Unknown failures propagate. Never log arbitrary exception messages or payloads. */
export function classifyLifecycleSchedulerErrorV3(error: unknown): {code: string; deterministic: boolean} {
  const raw = error != null && typeof error === "object" ? (error as {code?: unknown}).code : null;
  const normalized = typeof raw === "string" || typeof raw === "number" ?
    String(raw).toLowerCase().replace(/_/g, "-").split("/").pop()! : "";
  if (transportCodes[normalized]) return {code: transportCodes[normalized], deterministic: false};
  // HttpsError is our application validation type, not Firestore's gRPC error.
  // In particular, native gRPC FAILED_PRECONDITION (e.g. missing index) must fail.
  if (error instanceof HttpsError &&
      (error.code === "failed-precondition" || error.code === "invalid-argument")) {
    return {code: error.message === "SERVICE_START_EVIDENCE_CONFLICT" ?
      "service-start-evidence-conflict" : error.code, deterministic: true};
  }
  return {code: "unknown", deterministic: false};
}
