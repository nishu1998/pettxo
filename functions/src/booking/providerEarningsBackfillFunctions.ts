import {onCall} from "firebase-functions/v2/https";
import {db} from "../shared/firebase";
import {reconcileProviderEarningsBatchDataV3} from "./application/providerEarningsBackfillV3";

export const reconcileProviderEarningsBatchV3 = onCall({invoker: "private", timeoutSeconds: 300}, async request =>
  reconcileProviderEarningsBatchDataV3({firestore: db, auth: request.auth, input: request.data ?? {}}));
