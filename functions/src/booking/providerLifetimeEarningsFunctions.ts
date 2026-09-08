import {onCall} from "firebase-functions/v2/https";
import {db} from "../shared/firebase";
import {getProviderLifetimeEarningsDataV3} from "./application/providerLifetimeEarningsV3";

// Firebase client ID tokens authenticate inside onCall, not through Cloud Run IAM.
// The handler requires authentication and authorizes the requested provider.
export const getProviderLifetimeEarningsV3 = onCall({invoker: "public", timeoutSeconds: 60}, async request =>
  getProviderLifetimeEarningsDataV3({firestore: db, auth: request.auth, providerId: request.data?.providerId}));
