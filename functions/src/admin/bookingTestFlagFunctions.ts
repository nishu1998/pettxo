import {onCall} from "firebase-functions/v2/https";
import {setBookingTestFlagForAdminData} from "./bookingTestFlag";

/**
 * Test-booking flag callable (Super Admin only). Region asia-south1 via the
 * global options. Declared private like the other admin callables: this NEW
 * service needs the Cloud Run invoker step after its first deploy
 * (--no-invoker-iam-check, then an unauthenticated POST must return 401).
 */
export const setBookingTestFlagForAdmin = onCall(
  {
    invoker: "private" as const,
    enforceAppCheck: false,
  },
  (request) => setBookingTestFlagForAdminData(request),
);
