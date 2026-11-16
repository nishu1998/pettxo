import {onCall} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";
import {moderateReportData, type ReportModerationAction} from "./reportModeration";

const callableOptions = {
  region: "asia-south1",
  invoker: "public" as const,
  enforceAppCheck: false,
};

function reportModerationCallable(action: ReportModerationAction) {
  return onCall(callableOptions, async (request) => moderateReportData({
    firestore: db,
    authUid: request.auth?.uid ?? "",
    input: request.data,
    action,
  }));
}

export const resolveReport = reportModerationCallable("resolve_report");
export const rejectReport = reportModerationCallable("reject_report");
export const hideReportedService = reportModerationCallable("hide_reported_service");
export const hideReportedReview = reportModerationCallable("hide_reported_review");
