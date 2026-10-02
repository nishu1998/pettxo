import {createHash, randomBytes} from "crypto";
import {getAuth, type UserRecord} from "firebase-admin/auth";
import {
  FieldPath,
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentSnapshot,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {RESEND_MARKETING_API_KEY} from "../config/secrets";
import {db} from "../shared/firebase";
import {
  classifyMarketingEligibility,
  assertMarketingAdminRole,
  normalizeMarketingAudience,
  normalizeMarketingCampaignInput,
  normalizeMarketingContent,
  durableMarketingUnsubscribeUid,
  isMarketingUnsubscribeToken,
  marketingEmailPreferencePatch,
  stableMarketingId,
  type MarketingAudience,
  type MarketingCampaignInput,
  type MarketingCampaignStatus,
} from "./marketingEmailDomain";
import {renderMarketingEmail} from "./marketingEmailTemplate";
import {sendMarketingEmail} from "./marketingEmailTransport";

const campaigns = db.collection("marketingCampaigns");
const executions = db.collection("marketingCampaignExecutions");
const unsubscribeTokens = db.collection("marketingUnsubscribeTokens");
const batchSize = 25;
const scanPageSize = 25;
const testCooldownMs = 60_000;
const unsubscribeBaseUrl =
  "https://asia-south1-pettexo-d9409.cloudfunctions.net/unsubscribeMarketingEmailV3";

type AdminActor = {uid: string; role: "superAdmin"};
type Counts = {
  matchedUsers: number;
  noCanonicalEmail: number;
  marketingOptedOut: number;
  otherExclusions: number;
  eligibleRecipients: number;
  providerAccepted: number;
  failed: number;
  skipped: number;
};

const emptyCounts = (): Counts => ({
  matchedUsers: 0,
  noCanonicalEmail: 0,
  marketingOptedOut: 0,
  otherExclusions: 0,
  eligibleRecipients: 0,
  providerAccepted: 0,
  failed: 0,
  skipped: 0,
});

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requireUid(uid: string | undefined): string {
  if (uid) return uid;
  throw new HttpsError("unauthenticated", "Sign in to continue.", {appCode: "UNAUTHORIZED"});
}

async function requireSuperAdmin(uid: string | undefined): Promise<AdminActor> {
  const id = requireUid(uid);
  const snapshot = await db.collection("users").doc(id).get();
  if (!snapshot.exists || text(snapshot.data()?.adminRole) !== "superAdmin") {
    assertMarketingAdminRole(id, text(snapshot.data()?.adminRole));
  }
  return {uid: id, role: "superAdmin"};
}

function campaignId(data: unknown): string {
  const id = text((data as {campaignId?: unknown} | null)?.campaignId);
  if (!id) throw new HttpsError("invalid-argument", "campaignId is required.", {appCode: "CAMPAIGN_NOT_FOUND"});
  return id;
}

function requestId(data: unknown): string {
  const id = text((data as {requestId?: unknown} | null)?.requestId);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", "A stable requestId is required.", {appCode: "INVALID_REQUEST_ID"});
  }
  return id;
}

function asCampaign(snapshot: DocumentSnapshot): MarketingCampaignInput & {
  campaignId: string;
  status: MarketingCampaignStatus;
  data: DocumentData;
} {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Marketing campaign not found.", {appCode: "CAMPAIGN_NOT_FOUND"});
  }
  const data = snapshot.data() ?? {};
  return {
    campaignId: snapshot.id,
    status: text(data.status) as MarketingCampaignStatus,
    ...normalizeMarketingCampaignInput(data),
    data,
  };
}

function serialize(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .filter(([key]) => !["lastFailureDetail"].includes(key))
      .map(([key, item]) => [key, serialize(item)]));
  }
  return value;
}

function publicCampaign(snapshot: DocumentSnapshot): Record<string, unknown> {
  const data = snapshot.data() ?? {};
  return serialize({
    campaignId: snapshot.id,
    internalName: data.internalName,
    content: data.content,
    audience: data.audience,
    status: data.status,
    createdBy: data.createdBy,
    createdAt: data.createdAt,
    updatedBy: data.updatedBy,
    updatedAt: data.updatedAt,
    scheduledAt: data.scheduledAt ?? null,
    scheduleTimezone: data.scheduleTimezone ?? "",
    scheduleTimezoneOffset: data.scheduleTimezoneOffset ?? "",
    startedAt: data.startedAt ?? null,
    completedAt: data.completedAt ?? null,
    cancelledAt: data.cancelledAt ?? null,
    executionId: data.executionId ?? null,
    metrics: data.metrics ?? emptyCounts(),
    failureCode: data.failureCode ?? null,
    lastTestSentAt: data.lastTestSentAt ?? null,
  }) as Record<string, unknown>;
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

async function loadAuthUser(uid: string): Promise<UserRecord | null> {
  try {
    return await getAuth().getUser(uid);
  } catch (error) {
    if ((error as {code?: string}).code === "auth/user-not-found") return null;
    throw error;
  }
}

async function loadEligibility(
  uid: string,
  profileExists: boolean,
  profile: Record<string, unknown>,
  audience: MarketingAudience,
) {
  if (!profileExists) {
    return classifyMarketingEligibility({uid, profileExists, profile, privateProfile: {}, authUser: null, audience});
  }
  const privateSnapshot = await db.collection("userPrivate").doc(uid).get();
  const authUser = await loadAuthUser(uid);
  return classifyMarketingEligibility({
    uid,
    profileExists,
    profile,
    privateProfile: privateSnapshot.data() ?? {},
    authUser: authUser ? {email: authUser.email, disabled: authUser.disabled} : null,
    audience,
  });
}

async function audienceDocuments(audience: MarketingAudience): Promise<Array<{uid: string; exists: boolean; data: Record<string, unknown>}>> {
  if (audience.mode === "selected") {
    const snapshots = await db.getAll(...audience.selectedUids.map((uid) => db.collection("users").doc(uid)));
    return snapshots.map((snapshot) => ({uid: snapshot.id, exists: snapshot.exists, data: snapshot.data() ?? {}}));
  }
  // Estimates are deliberately bounded. Execution itself remains paginated
  // and can deliver to audiences larger than this preview ceiling.
  const snapshot = await db.collection("users").limit(5001).get();
  if (snapshot.size > 5000) {
    throw new HttpsError(
      "resource-exhausted",
      "This audience is too large for a synchronous estimate. Execution remains paginated.",
      {appCode: "AUDIENCE_ESTIMATE_TOO_LARGE"},
    );
  }
  return snapshot.docs.map((doc) => ({uid: doc.id, exists: true, data: doc.data()}));
}

async function estimateAudience(audience: MarketingAudience): Promise<Counts> {
  const counts = emptyCounts();
  const docs = await audienceDocuments(audience);
  for (const item of docs) {
    const eligibility = await loadEligibility(item.uid, item.exists, item.data, audience);
    if (eligibility.category === "notMatched") continue;
    counts.matchedUsers++;
    if (eligibility.category === "eligible") counts.eligibleRecipients++;
    else if (eligibility.category === "noCanonicalEmail") counts.noCanonicalEmail++;
    else if (eligibility.category === "marketingOptedOut") counts.marketingOptedOut++;
    else counts.otherExclusions++;
  }
  counts.skipped = counts.noCanonicalEmail + counts.marketingOptedOut + counts.otherExclusions;
  return counts;
}

export const getMarketingEmailPreferenceV3 = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const snapshot = await db.collection("userPrivate").doc(uid).get();
  return {ok: true, marketingEmailEnabled: snapshot.data()?.marketingEmailEnabled === true};
});

export const updateMarketingEmailPreferenceV3 = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth?.uid);
  if (typeof request.data?.enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "enabled must be a boolean.");
  }
  await db.collection("userPrivate").doc(uid).set({
    uid,
    ...marketingEmailPreferencePatch(request.data.enabled, "settings", FieldValue.serverTimestamp()),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return {ok: true, marketingEmailEnabled: request.data.enabled};
});

export const createMarketingEmailCampaignDraftV3 = onCall({invoker: "public"}, async (request) => {
  const actor = await requireSuperAdmin(request.auth?.uid);
  const input = normalizeMarketingCampaignInput(request.data);
  const suppliedRequestId = requestId(request.data);
  const ref = campaigns.doc(stableMarketingId("draft", actor.uid, suppliedRequestId));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) return;
    transaction.create(ref, {
      campaignId: ref.id,
      ...input,
      status: "DRAFT",
      schemaVersion: 1,
      createdBy: actor.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
      metrics: emptyCounts(),
      createRequestIdHash: sha256(suppliedRequestId),
    });
  });
  return {ok: true, campaignId: ref.id};
});

export const updateMarketingEmailCampaignDraftV3 = onCall({invoker: "public"}, async (request) => {
  const actor = await requireSuperAdmin(request.auth?.uid);
  const id = campaignId(request.data);
  const input = normalizeMarketingCampaignInput(request.data);
  await db.runTransaction(async (transaction) => {
    const ref = campaigns.doc(id);
    const campaign = asCampaign(await transaction.get(ref));
    if (campaign.status !== "DRAFT") {
      throw new HttpsError("failed-precondition", "Campaign is not editable.", {appCode: "CAMPAIGN_NOT_EDITABLE"});
    }
    transaction.update(ref, {...input, updatedBy: actor.uid, updatedAt: FieldValue.serverTimestamp()});
  });
  return {ok: true, campaignId: id};
});

export const listMarketingEmailCampaignsV3 = onCall({invoker: "public"}, async (request) => {
  await requireSuperAdmin(request.auth?.uid);
  const requestedLimit = Number(request.data?.limit ?? 25);
  const limit = Number.isInteger(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 50) : 25;
  let query = campaigns.orderBy("updatedAt", "desc").orderBy(FieldPath.documentId()).limit(limit);
  const cursor = text(request.data?.cursor);
  if (cursor) {
    const cursorSnapshot = await campaigns.doc(cursor).get();
    if (cursorSnapshot.exists) query = query.startAfter(cursorSnapshot);
  }
  const snapshot = await query.get();
  return {
    ok: true,
    campaigns: snapshot.docs.map(publicCampaign),
    nextCursor: snapshot.size === limit ? snapshot.docs.at(-1)?.id ?? null : null,
  };
});

export const getMarketingEmailCampaignV3 = onCall({invoker: "public"}, async (request) => {
  await requireSuperAdmin(request.auth?.uid);
  const snapshot = await campaigns.doc(campaignId(request.data)).get();
  asCampaign(snapshot);
  return {ok: true, campaign: publicCampaign(snapshot)};
});

export const estimateMarketingEmailAudienceV3 = onCall({invoker: "public", timeoutSeconds: 120}, async (request) => {
  await requireSuperAdmin(request.auth?.uid);
  let audience: MarketingAudience;
  const id = text(request.data?.campaignId);
  if (id) audience = asCampaign(await campaigns.doc(id).get()).audience;
  else audience = normalizeMarketingAudience(request.data?.audience);
  return {ok: true, estimate: await estimateAudience(audience)};
});

export const previewMarketingEmailCampaignV3 = onCall({invoker: "public"}, async (request) => {
  await requireSuperAdmin(request.auth?.uid);
  const id = text(request.data?.campaignId);
  const content = id ? asCampaign(await campaigns.doc(id).get()).content : normalizeMarketingContent(request.data?.content);
  return {
    ok: true,
    subject: content.subject,
    html: renderMarketingEmail({content, unsubscribeUrl: "https://pettxo.com/email-preferences"}),
  };
});

export const searchMarketingEmailUsersV3 = onCall({invoker: "public"}, async (request) => {
  await requireSuperAdmin(request.auth?.uid);
  const term = text(request.data?.query).toLocaleLowerCase();
  if (term.length < 2) throw new HttpsError("invalid-argument", "Enter at least 2 characters.");
  const requestedLimit = Number(request.data?.limit ?? 20);
  const limit = Number.isInteger(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 20) : 20;
  const end = `${term}\uf8ff`;
  const rawQuery = text(request.data?.query);
  const [uidDoc, usernameDocs, displayNameDocs, nameDocs] = await Promise.all([
    /^[A-Za-z0-9:_-]{1,128}$/.test(rawQuery) ?
      db.collection("users").doc(rawQuery).get() : Promise.resolve(null),
    db.collection("users").orderBy("usernameLowercase").startAt(term).endAt(end).limit(limit).get(),
    db.collection("users").orderBy("displayName").startAt(text(request.data?.query)).endAt(`${text(request.data?.query)}\uf8ff`).limit(limit).get(),
    db.collection("users").orderBy("name").startAt(text(request.data?.query)).endAt(`${text(request.data?.query)}\uf8ff`).limit(limit).get(),
  ]);
  const matches = new Map<string, DocumentSnapshot>();
  if (uidDoc?.exists) matches.set(uidDoc.id, uidDoc);
  for (const doc of [...usernameDocs.docs, ...displayNameDocs.docs, ...nameDocs.docs]) matches.set(doc.id, doc);
  const users = [...matches.values()].filter((doc) => {
    const status = text(doc.data()?.accountStatus);
    return !["pendingDeletion", "deletionInProgress", "deleted", "hardBanned"].includes(status);
  }).slice(0, limit).map((doc) => {
    const data = doc.data() ?? {};
    const username = text(data.usernameLowercase || data.username);
    return {
      uid: doc.id,
      displayName: text(data.displayName || data.name),
      role: text(data.role),
      roleLabel: text(data.role) === "serviceProvider" ? "Provider" : "Pet Parent",
      maskedIdentity: username ? `@${username}` : `User …${doc.id.slice(-4)}`,
      state: text(data.state),
      city: text(data.city),
    };
  });
  return {ok: true, users};
});

async function createUnsubscribeToken(campaign: string, uid: string, deliveryRef: FirebaseFirestore.DocumentReference): Promise<string> {
  const existing = await deliveryRef.get();
  const existingToken = text(existing.data()?.pendingUnsubscribeToken);
  if (existingToken) return existingToken;
  const token = randomBytes(32).toString("base64url");
  const hash = sha256(token);
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(deliveryRef);
    const pending = text(current.data()?.pendingUnsubscribeToken);
    if (pending) return;
    transaction.set(unsubscribeTokens.doc(hash), {
      tokenHash: hash,
      uid,
      campaignId: campaign,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.set(deliveryRef, {pendingUnsubscribeToken: token}, {merge: true});
  });
  const finalSnapshot = await deliveryRef.get();
  return text(finalSnapshot.data()?.pendingUnsubscribeToken) || token;
}

export const sendMarketingEmailCampaignTestV3 = onCall(
  {invoker: "public", secrets: [RESEND_MARKETING_API_KEY]},
  async (request) => {
    const actor = await requireSuperAdmin(request.auth?.uid);
    const campaign = asCampaign(await campaigns.doc(campaignId(request.data)).get());
    if (campaign.status !== "DRAFT") {
      throw new HttpsError("failed-precondition", "Only a saved draft can be test sent.", {appCode: "CAMPAIGN_NOT_EDITABLE"});
    }
    const authUser = await loadAuthUser(actor.uid);
    const email = text(authUser?.email).toLowerCase();
    if (!email) throw new HttpsError("failed-precondition", "Your canonical account email is unavailable.");
    const rateRef = db.collection("marketingEmailTestRateLimits").doc(actor.uid);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(rateRef);
      const last = snapshot.data()?.lastSentAt;
      if (last instanceof Timestamp && Date.now() - last.toMillis() < testCooldownMs) {
        throw new HttpsError("resource-exhausted", "Please wait before sending another test.", {appCode: "RATE_LIMITED"});
      }
      transaction.set(rateRef, {lastSentAt: Timestamp.now(), updatedAt: FieldValue.serverTimestamp()});
    });
    await sendMarketingEmail(RESEND_MARKETING_API_KEY.value(), {
      to: email,
      subject: `[TEST] ${campaign.content.subject}`,
      html: renderMarketingEmail({content: campaign.content, unsubscribeUrl: "https://pettxo.com/email-preferences", testMode: true}),
      unsubscribeUrl: "https://pettxo.com/email-preferences",
    }, stableMarketingId("marketing-test", actor.uid, campaign.campaignId, String(Math.floor(Date.now() / testCooldownMs))));
    await campaigns.doc(campaign.campaignId).set({lastTestSentAt: FieldValue.serverTimestamp(), lastTestSentBy: actor.uid}, {merge: true});
    return {ok: true};
  },
);

async function queueCampaign(params: {id: string; actor: AdminActor; initiationId: string; expectedStatus: "DRAFT" | "SCHEDULED"}) {
  const executionId = stableMarketingId("execution", params.id);
  const initiationHash = sha256(params.initiationId);
  await db.runTransaction(async (transaction) => {
    const campaignRef = campaigns.doc(params.id);
    const executionRef = executions.doc(executionId);
    const campaign = asCampaign(await transaction.get(campaignRef));
    if (campaign.status === "QUEUED" || campaign.status === "SENDING" || campaign.status === "COMPLETED" || campaign.status === "FAILED") {
      if (campaign.data.initiationRequestHash === initiationHash) return;
      const code = `CAMPAIGN_ALREADY_${campaign.status}`;
      throw new HttpsError("already-exists", "Campaign execution has already been initiated.", {appCode: code});
    }
    if (campaign.status !== params.expectedStatus) {
      throw new HttpsError("failed-precondition", "Campaign cannot be queued from its current state.", {appCode: "CAMPAIGN_NOT_EDITABLE"});
    }
    transaction.set(executionRef, {
      executionId,
      campaignId: params.id,
      status: "QUEUED",
      cursor: null,
      selectedCursor: 0,
      attemptCount: 0,
      metrics: emptyCounts(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(campaignRef, {
      status: "QUEUED",
      executionId,
      initiationRequestHash: initiationHash,
      queuedAt: FieldValue.serverTimestamp(),
      updatedBy: params.actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return executionId;
}

export const sendMarketingEmailCampaignNowV3 = onCall({invoker: "public"}, async (request) => {
  const actor = await requireSuperAdmin(request.auth?.uid);
  const id = campaignId(request.data);
  const executionId = await queueCampaign({id, actor, initiationId: requestId(request.data), expectedStatus: "DRAFT"});
  return {ok: true, campaignId: id, executionId, status: "QUEUED"};
});

export const scheduleMarketingEmailCampaignV3 = onCall({invoker: "public"}, async (request) => {
  const actor = await requireSuperAdmin(request.auth?.uid);
  const id = campaignId(request.data);
  const scheduleRequestHash = sha256(requestId(request.data));
  const raw = text(request.data?.scheduledAt);
  const scheduledAt = new Date(raw);
  if (!raw || !raw.endsWith("Z") || Number.isNaN(scheduledAt.getTime()) || scheduledAt.getTime() < Date.now() + 60_000) {
    throw new HttpsError("invalid-argument", "Schedule must be a valid future UTC time.", {appCode: "INVALID_SCHEDULE"});
  }
  const timezone = text(request.data?.timezone);
  const offset = text(request.data?.timezoneOffset);
  await db.runTransaction(async (transaction) => {
    const ref = campaigns.doc(id);
    const campaign = asCampaign(await transaction.get(ref));
    if (campaign.status === "SCHEDULED" && campaign.data.scheduleRequestHash === scheduleRequestHash) return;
    if (campaign.status !== "DRAFT") throw new HttpsError("failed-precondition", "Only a draft can be scheduled.", {appCode: "CAMPAIGN_NOT_EDITABLE"});
    transaction.update(ref, {
      status: "SCHEDULED",
      scheduledAt: Timestamp.fromDate(scheduledAt),
      scheduleTimezone: timezone,
      scheduleTimezoneOffset: offset,
      scheduleRequestHash,
      scheduledBy: actor.uid,
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {ok: true, campaignId: id, status: "SCHEDULED", scheduledAt: scheduledAt.toISOString()};
});

export const cancelScheduledMarketingEmailCampaignV3 = onCall({invoker: "public"}, async (request) => {
  const actor = await requireSuperAdmin(request.auth?.uid);
  const id = campaignId(request.data);
  await db.runTransaction(async (transaction) => {
    const ref = campaigns.doc(id);
    const campaign = asCampaign(await transaction.get(ref));
    if (campaign.status === "CANCELLED") return;
    if (campaign.status !== "SCHEDULED") {
      throw new HttpsError("failed-precondition", "Campaign is not cancellable.", {appCode: "CAMPAIGN_NOT_CANCELLABLE"});
    }
    transaction.update(ref, {status: "CANCELLED", cancelledAt: FieldValue.serverTimestamp(), cancelledBy: actor.uid, updatedAt: FieldValue.serverTimestamp()});
  });
  return {ok: true, campaignId: id, status: "CANCELLED"};
});

async function reserveDelivery(campaign: string, uid: string, email: string) {
  const ref = campaigns.doc(campaign).collection("deliveries").doc(uid);
  const result = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    if (data.status === "providerAccepted") return {decision: "accepted" as const, ref};
    const attempts = Number(data.attemptCount ?? 0);
    if (data.status === "failed" && attempts >= 3) return {decision: "failed" as const, ref};
    transaction.set(ref, {
      uid,
      campaignId: campaign,
      status: "sending",
      recipientHash: sha256(email),
      attemptCount: attempts + 1,
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    }, {merge: true});
    return {decision: "send" as const, ref, attempts: attempts + 1};
  });
  return result;
}

async function nextExecutionProfiles(execution: DocumentData, audience: MarketingAudience) {
  if (audience.mode === "selected") {
    const start = Number(execution.selectedCursor ?? 0);
    const ids = audience.selectedUids.slice(start, start + scanPageSize);
    const docs = ids.length ? await db.getAll(...ids.map((uid) => db.collection("users").doc(uid))) : [];
    return {docs, nextCursor: null, nextSelectedCursor: start + ids.length, done: start + ids.length >= audience.selectedUids.length};
  }
  let query = db.collection("users").orderBy(FieldPath.documentId()).limit(scanPageSize);
  const cursor = text(execution.cursor);
  if (cursor) query = query.startAfter(cursor);
  const snapshot = await query.get();
  return {
    docs: snapshot.docs,
    nextCursor: snapshot.docs.at(-1)?.id ?? null,
    nextSelectedCursor: 0,
    done: snapshot.size < scanPageSize,
  };
}

async function processExecution(snapshot: QueryDocumentSnapshot): Promise<void> {
  const executionRef = snapshot.ref;
  const execution = snapshot.data();
  const campaignRef = campaigns.doc(text(execution.campaignId));
  const campaignSnapshot = await campaignRef.get();
  const campaign = asCampaign(campaignSnapshot);
  if (campaign.status !== "QUEUED" && campaign.status !== "SENDING") {
    await executionRef.set({status: "CANCELLED", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return;
  }
  const claimed = await db.runTransaction(async (transaction) => {
    const currentExecution = await transaction.get(executionRef);
    if (currentExecution.data()?.status !== "QUEUED") return false;
    transaction.update(executionRef, {status: "SENDING", attemptCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()});
    transaction.update(campaignRef, {status: "SENDING", startedAt: campaign.data.startedAt ?? FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
    return true;
  });
  if (!claimed) return;

  try {
    const page = await nextExecutionProfiles(execution, campaign.audience);
    const pageCounts = emptyCounts();
    let retryRequired = false;
    let processedEligible = 0;
    for (const profileSnapshot of page.docs) {
      if (processedEligible >= batchSize) break;
      const eligibility = await loadEligibility(profileSnapshot.id, profileSnapshot.exists, profileSnapshot.data() ?? {}, campaign.audience);
      if (eligibility.category === "notMatched") continue;
      pageCounts.matchedUsers++;
      if (eligibility.category !== "eligible") {
        if (eligibility.category === "noCanonicalEmail") pageCounts.noCanonicalEmail++;
        else if (eligibility.category === "marketingOptedOut") pageCounts.marketingOptedOut++;
        else pageCounts.otherExclusions++;
        pageCounts.skipped++;
        continue;
      }
      processedEligible++;
      pageCounts.eligibleRecipients++;
      const reservation = await reserveDelivery(campaign.campaignId, profileSnapshot.id, eligibility.email);
      if (reservation.decision === "accepted") {
        pageCounts.providerAccepted++;
        continue;
      }
      if (reservation.decision === "failed") {
        pageCounts.failed++;
        continue;
      }
      const token = await createUnsubscribeToken(campaign.campaignId, profileSnapshot.id, reservation.ref);
      const unsubscribeUrl = `${unsubscribeBaseUrl}?token=${encodeURIComponent(token)}`;
      try {
        const providerMessageId = await sendMarketingEmail(RESEND_MARKETING_API_KEY.value(), {
          to: eligibility.email,
          subject: campaign.content.subject,
          html: renderMarketingEmail({content: campaign.content, unsubscribeUrl}),
          unsubscribeUrl,
        }, stableMarketingId("marketing-delivery", campaign.campaignId, profileSnapshot.id));
        await reservation.ref.set({
          status: "providerAccepted",
          providerMessageId,
          providerAcceptedAt: FieldValue.serverTimestamp(),
          pendingUnsubscribeToken: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        pageCounts.providerAccepted++;
      } catch (_) {
        const terminal = reservation.attempts >= 3;
        await reservation.ref.set({
          status: terminal ? "failed" : "retryableFailure",
          failureCode: "provider_rejected_or_unavailable",
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        if (terminal) pageCounts.failed++;
        else retryRequired = true;
      }
    }
    if (retryRequired) {
      await executionRef.set({status: "QUEUED", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      return;
    }
    const increments = Object.fromEntries(Object.entries(pageCounts).map(([key, value]) => [`metrics.${key}`, FieldValue.increment(value)]));
    if (page.done) {
      const existingMetrics = execution.metrics ?? {};
      const totalFailed = Number(existingMetrics.failed ?? 0) + pageCounts.failed;
      const finalStatus = totalFailed > 0 ? "FAILED" : "COMPLETED";
      await db.runTransaction(async (transaction) => {
        transaction.update(executionRef, {...increments, status: finalStatus, completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
        transaction.update(campaignRef, {...increments, status: finalStatus, completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
      });
    } else {
      await db.runTransaction(async (transaction) => {
        transaction.update(executionRef, {...increments, status: "QUEUED", cursor: page.nextCursor, selectedCursor: page.nextSelectedCursor, updatedAt: FieldValue.serverTimestamp()});
        transaction.update(campaignRef, {...increments, updatedAt: FieldValue.serverTimestamp()});
      });
    }
  } catch (error) {
    console.error("[MarketingEmail] bounded execution failed", {campaignId: campaign.campaignId, executionId: snapshot.id, code: (error as {code?: string}).code ?? "unknown"});
    const attempts = Number(execution.attemptCount ?? 0) + 1;
    const terminal = attempts >= 5;
    await executionRef.set({status: terminal ? "FAILED" : "QUEUED", lastFailureCode: "worker_failure", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (terminal) await campaignRef.set({status: "FAILED", failureCode: "worker_failure", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  }
}

export const processMarketingEmailCampaignsV3 = onSchedule(
  {schedule: "every 1 minutes", region: "asia-south1", secrets: [RESEND_MARKETING_API_KEY], timeoutSeconds: 300, maxInstances: 1},
  async () => {
    const due = await campaigns.where("status", "==", "SCHEDULED").where("scheduledAt", "<=", Timestamp.now()).orderBy("scheduledAt").limit(5).get();
    for (const doc of due.docs) {
      try {
        await queueCampaign({id: doc.id, actor: {uid: "system-scheduler", role: "superAdmin"}, initiationId: `scheduled:${doc.id}`, expectedStatus: "SCHEDULED"});
      } catch (error) {
        console.error("[MarketingEmail] scheduled claim failed", {campaignId: doc.id, code: (error as {code?: string}).code ?? "unknown"});
      }
    }
    const queued = await executions.where("status", "==", "QUEUED").limit(3).get();
    for (const execution of queued.docs) await processExecution(execution);
  },
);

function unsubscribePage(success: boolean): string {
  const heading = success ? "You’re unsubscribed" : "We couldn’t update that preference";
  const message = success ? "You will no longer receive Pettxo offers and updates. Essential account and service emails are unchanged." : "This link is invalid. You can still manage email preferences in the Pettxo app.";
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta charset="utf-8"><title>Pettxo email preferences</title></head><body style="margin:0;background:#FBF6EF;font-family:Arial,sans-serif;color:#302B27"><main style="max-width:560px;margin:60px auto;padding:36px;background:white;border-radius:28px"><div style="font-size:28px;font-weight:800;color:#F47B35">Pettxo</div><h1>${heading}</h1><p style="line-height:1.6">${message}</p></main></body></html>`;
}

export const unsubscribeMarketingEmailV3 = onRequest({region: "asia-south1", invoker: "public"}, async (request, response) => {
  const token = text(request.query.token ?? request.body?.token);
  if (!isMarketingUnsubscribeToken(token)) {
    response.status(400).type("html").send(unsubscribePage(false));
    return;
  }
  const ref = unsubscribeTokens.doc(sha256(token));
  try {
    const result = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      const data = snapshot.data() ?? {};
      const uid = durableMarketingUnsubscribeUid(snapshot.exists, data);
      if (!uid) return false;
      transaction.set(db.collection("userPrivate").doc(uid), {
        uid,
        ...marketingEmailPreferencePatch(false, "unsubscribe", FieldValue.serverTimestamp()),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(ref, {usedAt: FieldValue.serverTimestamp()}, {merge: true});
      return true;
    });
    response.status(result ? 200 : 400).type("html").send(unsubscribePage(result));
  } catch (_) {
    response.status(400).type("html").send(unsubscribePage(false));
  }
});
