import {onCall} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";
import {submitReportData} from "./reportSubmission";

export const submitReport = onCall(
  {
    region: "asia-south1",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => submitReportData({
    firestore: db,
    authUid: request.auth?.uid ?? "",
    input: request.data,
  }),
);
