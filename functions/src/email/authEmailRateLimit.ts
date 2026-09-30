import {createHash} from "crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {db} from "../shared/firebase";

export const authEmailCooldownMs = 60 * 1000;

export function authEmailRateLimitKey(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export async function reserveAuthEmailCooldown(
  collectionName: string,
  key: string,
  nowMs = Date.now(),
): Promise<boolean> {
  const rateLimitRef = db.collection(collectionName).doc(key);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateLimitRef);
    const value = snapshot.data()?.lastRequestedAt;
    const lastRequestedAtMs = value instanceof Timestamp ? value.toMillis() : 0;
    if (
      lastRequestedAtMs > 0 &&
      nowMs - lastRequestedAtMs < authEmailCooldownMs
    ) {
      return false;
    }

    transaction.set(
      rateLimitRef,
      {
        lastRequestedAt: Timestamp.fromMillis(nowMs),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return true;
  });
}
