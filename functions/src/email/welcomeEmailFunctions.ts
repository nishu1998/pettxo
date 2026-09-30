import {createHash, randomUUID} from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {RESEND_API_KEY} from "../config/secrets";
import {auth, db} from "../shared/firebase";
import {
  handleCanonicalUserCreated,
  type WelcomeEmailDependencies,
  type WelcomeProfile,
  type WelcomeReservation,
} from "./welcomeEmailApplication";
import {sendAuthEmail} from "./authEmailTransport";

const welcomeDeliveryCollection = "welcomeEmailDeliveries";
const welcomeLeaseMs = 5 * 60 * 1000;

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function profileData(value: unknown): WelcomeProfile {
  if (typeof value !== "object" || value === null) return {};
  const data = value as Record<string, unknown>;
  return {
    displayName:
      typeof data.displayName === "string" ? data.displayName : undefined,
    name: typeof data.name === "string" ? data.name : undefined,
  };
}

function deliveryRef(uid: string) {
  return db.collection(welcomeDeliveryCollection).doc(uid);
}

async function reserveDelivery(
  uid: string,
  recipientEmail: string,
): Promise<WelcomeReservation> {
  const ref = deliveryRef(uid);
  const nowMs = Date.now();
  const leaseId = randomUUID();
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    const status = typeof data.status === "string" ? data.status : "";
    if (status === "sent") return {decision: "sent"};
    if (status === "skippedNoEmail") return {decision: "skippedNoEmail"};

    const leaseUntil = data.leaseUntil;
    if (
      status === "sending" &&
      leaseUntil instanceof Timestamp &&
      leaseUntil.toMillis() > nowMs
    ) {
      return {decision: "busy"};
    }

    transaction.set(
      ref,
      {
        uid,
        status: "sending",
        leaseId,
        leaseUntil: Timestamp.fromMillis(nowMs + welcomeLeaseMs),
        recipientHash: hash(recipientEmail.toLowerCase()),
        attemptCount: Number(data.attemptCount ?? 0) + 1,
        lastAttemptAt: Timestamp.fromMillis(nowMs),
        updatedAt: FieldValue.serverTimestamp(),
        ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    );
    return {
      decision: "send",
      leaseId,
      idempotencyKey: `welcome-${hash(uid)}`,
    };
  });
}

async function recordTerminalSkip(
  uid: string,
  status: "skippedNoEmail" | "skippedMissingAuthUser",
): Promise<void> {
  const ref = deliveryRef(uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.status === "sent") return;
    transaction.set(
      ref,
      {
        uid,
        status,
        updatedAt: FieldValue.serverTimestamp(),
        ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      },
      {merge: true},
    );
  });
}

async function updateOwnedLease(
  uid: string,
  leaseId: string,
  values: Record<string, unknown>,
): Promise<void> {
  const ref = deliveryRef(uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    if (data.status !== "sending" || data.leaseId !== leaseId) return;
    transaction.set(
      ref,
      {
        ...values,
        leaseId: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}

function buildWelcomeDependencies(): WelcomeEmailDependencies {
  return {
    async getAuthUser(uid) {
      try {
        const user = await auth.getUser(uid);
        return {
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        };
      } catch (error) {
        if ((error as {code?: string}).code === "auth/user-not-found") {
          return null;
        }
        throw error;
      }
    },
    reserveDelivery,
    recordNoEmail(uid) {
      return recordTerminalSkip(uid, "skippedNoEmail");
    },
    recordMissingAuthUser(uid) {
      return recordTerminalSkip(uid, "skippedMissingAuthUser");
    },
    markSent(uid, leaseId) {
      return updateOwnedLease(uid, leaseId, {
        status: "sent",
        sentAt: FieldValue.serverTimestamp(),
      });
    },
    markRetryableFailure(uid, leaseId, error) {
      return updateOwnedLease(uid, leaseId, {
        status: "retryableFailure",
        lastFailureAt: FieldValue.serverTimestamp(),
        lastFailureCode: (error as {code?: string}).code ?? "unknown",
      });
    },
    sendEmail(message, idempotencyKey) {
      return sendAuthEmail(RESEND_API_KEY.value(), message, {idempotencyKey});
    },
  };
}

export const sendWelcomeEmailOnUserCreated = onDocumentCreated(
  {
    document: "users/{uid}",
    region: "asia-south1",
    retry: true,
    secrets: [RESEND_API_KEY],
  },
  async (event) => {
    const profile = event.data?.data();
    if (!profile) return;
    await handleCanonicalUserCreated(
      event.params.uid,
      profileData(profile),
      buildWelcomeDependencies(),
    );
  },
);
