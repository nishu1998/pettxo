import {Timestamp} from "firebase-admin/firestore";

type Data = FirebaseFirestore.DocumentData;
const phases = new Set(["PROVISIONAL", "HELD", "FINALIZED", "ADJUSTED"]);
const money = (v: unknown) => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
const id = (v: unknown) => typeof v === "string" && Boolean(v.trim()) && !v.includes("/");
const date = (v: unknown) => v instanceof Timestamp || (v instanceof Date && Number.isFinite(v.getTime()));

/** Audit contract includes history ordering and writer timestamps in addition
 * to the Flutter parser's financial requirements. No values are returned. */
export function providerEarningsSchemaIssuesV3(data: Data): string[] {
  const fields = ["earningsSchemaVersion", "providerId", "bookingId", "earningsStatus",
    "providerFinalEntitlementPaise", "providerProvisionalEntitlementPaise", "createdAt", "updatedAt"];
  const issues = fields.filter(k => !Object.prototype.hasOwnProperty.call(data, k)).map(k => `MISSING:${k}`);
  const check = (k: string, valid: boolean) => {
    if (Object.prototype.hasOwnProperty.call(data, k) && !valid) issues.push(`INVALID:${k}`);
  };
  check("earningsSchemaVersion", data.earningsSchemaVersion === 1);
  check("providerId", id(data.providerId));
  check("bookingId", id(data.bookingId));
  check("earningsStatus", phases.has(data.earningsStatus));
  check("providerFinalEntitlementPaise", money(data.providerFinalEntitlementPaise) ||
    (data.providerFinalEntitlementPaise === null && ["PROVISIONAL", "HELD"].includes(data.earningsStatus)));
  check("providerProvisionalEntitlementPaise", money(data.providerProvisionalEntitlementPaise));
  check("createdAt", date(data.createdAt));
  check("updatedAt", date(data.updatedAt));
  return issues;
}
