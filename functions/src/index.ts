import {createHash, randomInt, timingSafeEqual} from "crypto";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import type {DocumentData, Transaction, WriteBatch} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const istOffsetMinutes = 330;
const slotGenerationDays = 30;
const minuteMs = 60 * 1000;
const hourMs = 60 * minuteMs;
const requestResponseWindowMs = 24 * hourMs;
const serviceResponseCutoffMs = hourMs;
const minimumBookingLeadMs = serviceResponseCutoffMs;
const otpAvailabilityWindowMs = hourMs;
const otpValidityMs = hourMs;

type BookingStatus =
  | "requested"
  | "accepted"
  | "rejected"
  | "cancelledByCustomer"
  | "cancelledByProvider"
  | "expired"
  | "inProgress"
  | "completed"
  | "disputed"
  | "noShow";

function requireUid(auth: {uid?: string} | undefined): string {
  const uid = auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function requireAdmin(auth: {token?: {[key: string]: unknown}} | undefined): void {
  if (auth?.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

function hashOtp(bookingId: string, otp: string): string {
  return createHash("sha256").update(`${bookingId}:${otp}`).digest("hex");
}

function assertStatus(current: BookingStatus, expected: BookingStatus): void {
  if (current !== expected) {
    throw new HttpsError(
      "failed-precondition",
      `Booking must be ${expected}; current status is ${current}.`,
    );
  }
}

function toInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function toFiniteNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function nextRatingAverage(currentAverage: number, currentCount: number, nextRating: number): number {
  const safeCount = Math.max(0, currentCount);
  const total = (currentAverage * safeCount) + nextRating;
  return roundTo(total / (safeCount + 1), 2);
}

function computeTrustScore(ratingAverage: number, completedBookingCount: number): number {
  const ratingSignal = Math.min(Math.max(ratingAverage / 5, 0), 1);
  const completionSignal = Math.min(Math.max(completedBookingCount, 0) / 25, 1);
  return Math.round(((ratingSignal * 0.8) + (completionSignal * 0.2)) * 100);
}

function dateKey(year: number, month: number, day: number): string {
  return `${year.toString().padStart(4, "0")}-${month
    .toString()
    .padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function localMidnightUtcMs(year: number, month: number, day: number): number {
  return Date.UTC(year, month - 1, day, 0, 0, 0, 0) - istOffsetMinutes * 60 * 1000;
}

function localDatePartsFromUtcMs(utcMs: number): {
  year: number;
  month: number;
  day: number;
  weekday: string;
} {
  const local = new Date(utcMs + istOffsetMinutes * 60 * 1000);
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return {
    year: local.getUTCFullYear(),
    month: local.getUTCMonth() + 1,
    day: local.getUTCDate(),
    weekday: weekdays[local.getUTCDay()],
  };
}

function serviceSlotConfigChanged(
  before: DocumentData | undefined,
  after: DocumentData,
): boolean {
  if (!before) return true;
  const keys = [
    "ownerUserId",
    "sessionDurationMinutes",
    "capacity",
    "availableDays",
    "startMinutes",
    "endMinutes",
    "status",
    "isActive",
    "isDeleted",
    "isPaused",
    "isVisibleToMarketplace",
  ];
  return keys.some((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]));
}

function effectiveDurationMinutes(service: DocumentData): number {
  const startMinutes = toInt(service.startMinutes, 0);
  const endMinutes = toInt(service.endMinutes, 0);
  const configured = toInt(service.sessionDurationMinutes, 60);
  if (configured > 0) return configured;
  if (endMinutes > startMinutes) return endMinutes - startMinutes;
  return 24 * 60;
}

function computeBookingRequestExpiresAt(nowMs: number, scheduledStartMs: number): Timestamp {
  const responseDeadlineMs = nowMs + requestResponseWindowMs;
  const serviceCutoffMs = scheduledStartMs - serviceResponseCutoffMs;
  return Timestamp.fromMillis(Math.min(responseDeadlineMs, serviceCutoffMs));
}

function requestHasExpired(booking: DocumentData, nowMs = Date.now()): boolean {
  const request = booking.request ?? {};
  const expiresAt = request.expiresAt as Timestamp | undefined;
  return !!expiresAt && expiresAt.toMillis() <= nowMs;
}

async function commitBatches(
  batches: WriteBatch[],
): Promise<void> {
  for (const batch of batches) {
    await batch.commit();
  }
}

async function regenerateServiceSlots(
  serviceId: string,
  service: DocumentData,
): Promise<void> {
  const slotsRef = db.collection("services").doc(serviceId).collection("slots");
  const now = Date.now();
  const existing = await slotsRef
    .where("startAt", ">=", Timestamp.fromMillis(now))
    .get();

  const batches: WriteBatch[] = [];
  let batch = db.batch();
  let writes = 0;

  const queue = (
    action: (targetBatch: WriteBatch) => void,
  ): void => {
    action(batch);
    writes += 1;
    if (writes >= 450) {
      batches.push(batch);
      batch = db.batch();
      writes = 0;
    }
  };

  for (const doc of existing.docs) {
    const acceptedCount = toInt(doc.data().acceptedCount, 0);
    if (acceptedCount <= 0) {
      queue((targetBatch) => targetBatch.delete(doc.ref));
    }
  }

  const isServiceBookable =
    service.status === "active" &&
    service.isActive === true &&
    service.isDeleted !== true &&
    service.isPaused !== true &&
    service.isVisibleToMarketplace === true;

  if (isServiceBookable) {
    const durationMinutes = effectiveDurationMinutes(service);
    const capacity = Math.max(toInt(service.capacity, 1), 1);
    const selectedDays = new Set(
      Array.isArray(service.availableDays) ? service.availableDays.map(String) : [],
    );
    const startMinutes = Math.max(toInt(service.startMinutes, 0), 0);
    const endMinutes = Math.min(toInt(service.endMinutes, 24 * 60), 24 * 60);
    const today = localDatePartsFromUtcMs(now);
    const todayMidnight = localMidnightUtcMs(today.year, today.month, today.day);

    if (
      selectedDays.size > 0 &&
      durationMinutes > 0 &&
      endMinutes > startMinutes
    ) {
      for (let dayOffset = 0; dayOffset < slotGenerationDays; dayOffset += 1) {
        const dayUtcMs = todayMidnight + dayOffset * 24 * 60 * 60 * 1000;
        const parts = localDatePartsFromUtcMs(dayUtcMs);
        if (!selectedDays.has(parts.weekday)) continue;

        const key = dateKey(parts.year, parts.month, parts.day);
        let cursor = startMinutes;
        while (cursor + durationMinutes <= endMinutes) {
          const slotStartMs = dayUtcMs + cursor * 60 * 1000;
          const slotEndMs = slotStartMs + durationMinutes * 60 * 1000;
          const slotId = `${key}_${cursor.toString().padStart(4, "0")}`;
          const slotRef = slotsRef.doc(slotId);
          queue((targetBatch) =>
            targetBatch.set(slotRef, {
              serviceId,
              serviceOwnerId: service.ownerUserId ?? "",
              startAt: Timestamp.fromMillis(slotStartMs),
              endAt: Timestamp.fromMillis(slotEndMs),
              dateKey: key,
              startMinutes: cursor,
              endMinutes: cursor + durationMinutes,
              durationMinutes,
              capacity,
              acceptedCount: 0,
              isBookable: slotStartMs - now >= minimumBookingLeadMs,
              status: slotStartMs - now >= minimumBookingLeadMs ? "open" : "closed",
              timezone: "Asia/Kolkata",
              generatedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            }),
          );
          cursor += durationMinutes;
        }
      }
    }
  }

  if (writes > 0) batches.push(batch);
  await commitBatches(batches);
}

async function writeBookingEvent(params: {
  bookingId: string;
  actorId: string;
  actorType: "customer" | "provider" | "admin" | "system";
  type: string;
  fromStatus: string;
  toStatus: string;
  message: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await db.collection("bookings").doc(params.bookingId).collection("events").add({
    actorId: params.actorId,
    actorType: params.actorType,
    type: params.type,
    fromStatus: params.fromStatus,
    toStatus: params.toStatus,
    message: params.message,
    metadata: params.metadata ?? {},
    createdAt: FieldValue.serverTimestamp(),
  });
}

function safeText(value: unknown, fallback: string): string {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function snapshotName(snapshot: unknown, fallback: string): string {
  if (!snapshot || typeof snapshot !== "object") return fallback;
  const data = snapshot as Record<string, unknown>;
  return safeText(data.name ?? data.username, fallback);
}

function serviceTitleFromBooking(booking: DocumentData): string {
  const serviceSnapshot = booking.serviceSnapshot ?? {};
  return safeText(serviceSnapshot.title, "your service");
}

function queueBookingNotification(params: {
  transaction: Transaction;
  userId: string;
  bookingId: string;
  type: string;
  title: string;
  body: string;
  recipientRole: "customer" | "provider";
  actorId: string;
  status: string;
  booking: DocumentData;
  extraData?: Record<string, unknown>;
}): void {
  if (!params.userId) return;

  const notificationRef = db.collection("notifications").doc();
  params.transaction.set(notificationRef, {
    userId: params.userId,
    category: "booking",
    type: params.type,
    title: params.title,
    body: params.body,
    read: false,
    isRead: false,
    bookingId: params.bookingId,
    serviceId: params.booking.serviceId ?? "",
    recipientRole: params.recipientRole,
    actorId: params.actorId,
    data: {
      bookingId: params.bookingId,
      serviceId: params.booking.serviceId ?? "",
      slotId: params.booking.slotId ?? "",
      status: params.status,
      recipientRole: params.recipientRole,
      ...params.extraData,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function notificationData(data: Record<string, unknown>): Record<string, string> {
  const payload: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined || value === null) continue;
    payload[key] = String(value);
  }
  return payload;
}

function isInvalidMessagingToken(code: string | undefined): boolean {
  return code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token" ||
    code === "messaging/invalid-argument";
}

export const sendPushForNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const notification = event.data?.data();
    if (!notification) return;
    if (notification.category !== "booking") return;

    const userId = String(notification.userId ?? "");
    if (!userId) return;

    const tokenSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("notificationTokens")
      .where("disabled", "!=", true)
      .get();

    const tokenDocs = tokenSnapshot.docs.filter((doc) => {
      const token = String(doc.data().token ?? "");
      return token.length > 0;
    });
    const tokens = tokenDocs.map((doc) => String(doc.data().token));
    if (tokens.length === 0) return;

    const rawData = notification.data;
    const notificationPayload =
      rawData && typeof rawData === "object" && !Array.isArray(rawData) ?
        rawData as Record<string, unknown> :
        {};
    const data = notificationData({
      ...notificationPayload,
      notificationId: event.params.notificationId,
      bookingId: notification.bookingId ?? "",
      serviceId: notification.serviceId ?? "",
      type: notification.type ?? "",
      category: notification.category ?? "booking",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    });

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: safeText(notification.title, "Pettxo booking update"),
        body: safeText(notification.body, "You have a new booking update."),
      },
      data,
      android: {
        priority: "high",
        notification: {
          sound: "default",
          tag: String(notification.bookingId ?? event.params.notificationId),
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    });

    const cleanupBatch = db.batch();
    let cleanupCount = 0;
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (!isInvalidMessagingToken(code)) return;
      cleanupBatch.set(tokenDocs[index].ref, {
        disabled: true,
        disabledAt: FieldValue.serverTimestamp(),
        errorCode: code,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      cleanupCount += 1;
    });

    if (cleanupCount > 0) {
      await cleanupBatch.commit();
    }
  },
);

export const enqueueServiceModeration = onDocumentCreated(
  "services/{serviceId}",
  async (event) => {
    const serviceId = event.params.serviceId;
    const service = event.data?.data();
    if (!service) return;

    await db.collection("moderationQueue").add({
      targetType: "service",
      targetId: serviceId,
      targetOwnerId: service.ownerUserId ?? "",
      source: "system",
      reportId: "",
      severity: "low",
      status: "pending",
      reason: "New service listing pending review",
      assignedAdminId: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

export const syncServiceSlots = onDocumentWritten(
  {document: "services/{serviceId}", timeoutSeconds: 120, memory: "512MiB"},
  async (event) => {
    const serviceId = event.params.serviceId;
    const after = event.data?.after.data();
    if (!after) return;

    const before = event.data?.before.data();
    if (!serviceSlotConfigChanged(before, after)) return;

    await regenerateServiceSlots(serviceId, after);
  },
);

export const enqueueReportModeration = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const reportId = event.params.reportId;
    const report = event.data?.data();
    if (!report) return;

    await db.collection("moderationQueue").add({
      targetType: report.targetType ?? "",
      targetId: report.targetId ?? "",
      targetOwnerId: report.targetOwnerId ?? "",
      source: "report",
      reportId,
      severity: "medium",
      status: "pending",
      reason: report.reason ?? "User report",
      assignedAdminId: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

export const requestBooking = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const serviceId = String(request.data?.serviceId ?? "");
  const slotId = String(request.data?.slotId ?? "");
  const requestedAmount = Number(request.data?.amount ?? 0);
  const userId = String(request.data?.userId ?? uid);

  if (!serviceId || !slotId) {
    throw new HttpsError("invalid-argument", "serviceId and slotId are required.");
  }
  if (userId !== uid) {
    throw new HttpsError("permission-denied", "userId must match the authenticated user.");
  }

  const serviceRef = db.collection("services").doc(serviceId);
  const slotRef = serviceRef.collection("slots").doc(slotId);
  const customerRef = db.collection("users").doc(uid);
  const bookingRef = db.collection("bookings").doc();

  await db.runTransaction(async (transaction) => {
    const serviceSnapshot = await transaction.get(serviceRef);
    const slotSnapshot = await transaction.get(slotRef);
    const customerSnapshot = await transaction.get(customerRef);

    if (!serviceSnapshot.exists) {
      throw new HttpsError("not-found", "Service not found.");
    }
    if (!slotSnapshot.exists) {
      throw new HttpsError("not-found", "Slot not found.");
    }

    const service = serviceSnapshot.data()!;
    const slot = slotSnapshot.data()!;
    if (
      service.status !== "active" ||
      service.isActive !== true ||
      service.isDeleted === true ||
      service.isPaused === true ||
      service.isVisibleToMarketplace !== true
    ) {
      throw new HttpsError("failed-precondition", "This service is not bookable.");
    }

    const serviceOwnerId = String(service.ownerUserId ?? "");
    if (!serviceOwnerId) {
      throw new HttpsError("failed-precondition", "Service owner is missing.");
    }
    if (slot.serviceId !== serviceId || slot.serviceOwnerId !== serviceOwnerId) {
      throw new HttpsError("failed-precondition", "Slot does not belong to this service.");
    }
    if (slot.isBookable !== true || slot.status !== "open") {
      throw new HttpsError("failed-precondition", "This slot is not bookable.");
    }

    const capacity = Math.max(toInt(slot.capacity, 1), 1);
    const acceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
    if (acceptedCount >= capacity) {
      throw new HttpsError("failed-precondition", "This slot is already full.");
    }

    const scheduledStartAt = slot.startAt as Timestamp | undefined;
    const scheduledEndAt = slot.endAt as Timestamp | undefined;
    if (!scheduledStartAt || !scheduledEndAt) {
      throw new HttpsError("failed-precondition", "Slot timing is missing.");
    }
    const nowMs = Date.now();
    if (scheduledStartAt.toMillis() - nowMs < minimumBookingLeadMs) {
      throw new HttpsError("failed-precondition", "This slot is too soon to book.");
    }
    if (scheduledEndAt.toMillis() <= scheduledStartAt.toMillis()) {
      throw new HttpsError("failed-precondition", "Slot timing is invalid.");
    }

    const requestExpiresAt = computeBookingRequestExpiresAt(
      nowMs,
      scheduledStartAt.toMillis(),
    );
    if (requestExpiresAt.toMillis() <= nowMs) {
      throw new HttpsError(
        "failed-precondition",
        "This slot is too soon for the provider response window.",
      );
    }

    const price = Number(service.pricePerSession ?? requestedAmount);
    if (requestedAmount > 0 && price > 0 && requestedAmount !== price) {
      throw new HttpsError("failed-precondition", "Booking amount does not match service price.");
    }

    const durationMinutes = Math.round(
      (scheduledEndAt.toMillis() - scheduledStartAt.toMillis()) / 60000,
    );
    const ownerSnapshot = service.ownerSnapshot ?? {};
    const customer = customerSnapshot.exists ? customerSnapshot.data()! : {};
    const location = service.location ?? {};

    const bookingPayload = {
      serviceId,
      slotId,
      serviceOwnerId,
      customerId: uid,
      serviceSnapshot: {
        title: service.title ?? "",
        animalType: service.animalType ?? "",
        category: service.category ?? "",
        pricePerSession: price,
        currency: service.currency ?? "INR",
        durationMinutes,
        serviceType: service.serviceType ?? "",
        primaryPhotoUrl: service.primaryPhotoUrl ?? "",
      },
      providerSnapshot: {
        name: ownerSnapshot.name ?? "",
        username: ownerSnapshot.username ?? "",
        photoUrl: ownerSnapshot.photoUrl ?? "",
        phoneMasked: "",
      },
      customerSnapshot: {
        name: customer.name ?? "",
        username: customer.username ?? "",
        photoUrl: customer.profileImage ?? "",
        phoneMasked: "",
      },
      locationSnapshot: {
        displayAddress: location.displayAddress ?? "",
        latitude: location.latitude ?? 0,
        longitude: location.longitude ?? 0,
        geohash: location.geohash ?? "",
      },
      scheduledStartAt,
      scheduledEndAt,
      timezone: "Asia/Kolkata",
      status: "requested",
      request: {
        message: "",
        // Provider must respond within 24h or 1h before service, whichever is earlier.
        expiresAt: requestExpiresAt,
        respondedAt: null,
        responseReason: "",
      },
      pricing: {
        grossAmount: price,
        platformFee: 0,
        providerEarnings: price,
        currency: service.currency ?? "INR",
        paymentStatus: "paid",
      },
      otp: {
        status: "notGenerated",
        attempts: 0,
        maxAttempts: 5,
      },
      payoutReadiness: {
        status: "notEligible",
        reason: "Booking has not completed.",
        eligibleAt: null,
        payoutId: "",
      },
      dispute: {
        hasDispute: false,
        disputeId: "",
        status: "none",
      },
      notificationState: {
        requestNotificationSent: true,
        acceptanceNotificationSent: false,
        rejectionNotificationSent: false,
        cancellationNotificationSent: false,
        otpNotificationSent: false,
        startNotificationSent: false,
        reminderNotificationSent: false,
        completionNotificationSent: false,
      },
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    transaction.set(bookingRef, bookingPayload);
    queueBookingNotification({
      transaction,
      userId: serviceOwnerId,
      bookingId: bookingRef.id,
      type: "bookingRequested",
      title: "New booking request",
      body: `${snapshotName(
        bookingPayload.customerSnapshot,
        "A pet parent",
      )} requested ${serviceTitleFromBooking(bookingPayload)}.`,
      recipientRole: "provider",
      actorId: uid,
      status: "requested",
      booking: bookingPayload,
      extraData: {event: "booking_requested"},
    });
  });

  await writeBookingEvent({
    bookingId: bookingRef.id,
    actorId: uid,
    actorType: "customer",
    type: "created",
    fromStatus: "none",
    toStatus: "requested",
    message: "Booking request created after payment simulation.",
    metadata: {serviceId, slotId},
  });

  return {ok: true, bookingId: bookingRef.id};
});

export const acceptBookingRequest = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  let slotId = "";

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the service owner can accept.");
    }

    assertStatus(booking.status as BookingStatus, "requested");
    if (requestHasExpired(booking)) {
      throw new HttpsError(
        "deadline-exceeded",
        "This booking request has expired and can no longer be accepted.",
      );
    }
    slotId = String(booking.slotId ?? "");
    const serviceId = String(booking.serviceId ?? "");
    if (!serviceId || !slotId) {
      throw new HttpsError("failed-precondition", "Booking slot is missing.");
    }

    const slotRef = db.collection("services").doc(serviceId).collection("slots").doc(slotId);
    const slotSnapshot = await transaction.get(slotRef);
    if (!slotSnapshot.exists) {
      throw new HttpsError("not-found", "Slot not found.");
    }

    const slot = slotSnapshot.data()!;
    if (slot.serviceId !== serviceId || slot.serviceOwnerId !== uid) {
      throw new HttpsError("failed-precondition", "Slot does not match this booking.");
    }

    const capacity = Math.max(toInt(slot.capacity, 1), 1);
    const acceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
    if (acceptedCount >= capacity) {
      throw new HttpsError("failed-precondition", "This slot is already full.");
    }

    const nextAcceptedCount = acceptedCount + 1;
    transaction.update(slotRef, {
      acceptedCount: FieldValue.increment(1),
      isBookable: nextAcceptedCount < capacity,
      status: nextAcceptedCount >= capacity ? "full" : "open",
      updatedAt: FieldValue.serverTimestamp(),
    });

    transaction.update(bookingRef, {
      status: "accepted",
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "notificationState.acceptanceNotificationSent": true,
    });

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingAccepted",
      title: "Booking confirmed",
      body: `${snapshotName(
        booking.providerSnapshot,
        "Your provider",
      )} accepted your ${serviceTitleFromBooking(booking)} booking.`,
      recipientRole: "customer",
      actorId: uid,
      status: "accepted",
      booking,
      extraData: {event: "booking_accepted"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "accepted",
    fromStatus: "requested",
    toStatus: "accepted",
    message: "Booking request accepted.",
    metadata: {slotId},
  });

  return {ok: true};
});

export const rejectBookingRequest = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const reason = String(request.data?.reason ?? "Rejected by provider");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the service owner can reject.");
    }

    assertStatus(booking.status as BookingStatus, "requested");
    if (requestHasExpired(booking)) {
      throw new HttpsError(
        "deadline-exceeded",
        "This booking request has expired and can no longer be rejected.",
      );
    }

    transaction.update(bookingRef, {
      status: "rejected",
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "request.respondedAt": FieldValue.serverTimestamp(),
      "request.responseReason": reason,
      "notificationState.rejectionNotificationSent": true,
    });

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingRejected",
      title: "Booking request declined",
      body: `${snapshotName(
        booking.providerSnapshot,
        "The provider",
      )} declined your ${serviceTitleFromBooking(booking)} request.`,
      recipientRole: "customer",
      actorId: uid,
      status: "rejected",
      booking,
      extraData: {event: "booking_rejected"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "rejected",
    fromStatus: "requested",
    toStatus: "rejected",
    message: reason,
  });

  return {ok: true};
});

export const expireStaleBookingRequests = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const now = Timestamp.now();
    const expiredRequests = await db
      .collection("bookings")
      .where("status", "==", "requested")
      .where("request.expiresAt", "<=", now)
      .limit(100)
      .get();

    let expiredCount = 0;

    for (const doc of expiredRequests.docs) {
      let didExpire = false;
      await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(doc.ref);
        if (!freshSnapshot.exists) return;

        const booking = freshSnapshot.data()!;
        if (booking.status !== "requested" || !requestHasExpired(booking)) return;

        transaction.update(doc.ref, {
          status: "expired",
          expiredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          "request.respondedAt": FieldValue.serverTimestamp(),
          "request.responseReason": "Auto-cancelled because provider did not respond in time.",
        });

        queueBookingNotification({
          transaction,
          userId: String(booking.customerId ?? ""),
          bookingId: doc.id,
          type: "bookingExpired",
          title: "Booking request expired",
          body: `${serviceTitleFromBooking(
            booking,
          )} was auto-cancelled because the provider did not respond in time.`,
          recipientRole: "customer",
          actorId: "system",
          status: "expired",
          booking,
          extraData: {event: "booking_expired"},
        });
        queueBookingNotification({
          transaction,
          userId: String(booking.serviceOwnerId ?? booking.providerId ?? ""),
          bookingId: doc.id,
          type: "bookingExpired",
          title: "Booking request expired",
          body: `The response timer ended for ${serviceTitleFromBooking(booking)}.`,
          recipientRole: "provider",
          actorId: "system",
          status: "expired",
          booking,
          extraData: {event: "booking_expired"},
        });

        didExpire = true;
      });

      if (didExpire) {
        expiredCount += 1;
        await writeBookingEvent({
          bookingId: doc.id,
          actorId: "system",
          actorType: "system",
          type: "expired",
          fromStatus: "requested",
          toStatus: "expired",
          message: "Booking request auto-cancelled after provider response timer expired.",
        });
      }
    }

    console.log(`Expired ${expiredCount} stale booking request(s).`);
  },
);

export const cancelBooking = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const reason = String(request.data?.reason ?? "Cancelled by user");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  let fromStatus = "";
  let toStatus: BookingStatus = "cancelledByCustomer";
  let actorType: "customer" | "provider" = "customer";
  let releasedCapacity = false;
  let slotId = "";

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data()!;
    const status = booking.status as BookingStatus;
    fromStatus = String(status);

    const isCustomer = booking.customerId === uid;
    const isProvider = booking.serviceOwnerId === uid || booking.providerId === uid;
    if (!isCustomer && !isProvider) {
      throw new HttpsError("permission-denied", "Only booking participants can cancel.");
    }

    if (status === "requested") {
      if (!isCustomer) {
        throw new HttpsError(
          "failed-precondition",
          "Providers should reject requested bookings instead of cancelling.",
        );
      }
      actorType = "customer";
      toStatus = "cancelledByCustomer";
    } else if (status === "accepted") {
      const scheduledStartAt = booking.scheduledStartAt as Timestamp | undefined;
      if (scheduledStartAt && scheduledStartAt.toMillis() <= Date.now()) {
        throw new HttpsError(
          "failed-precondition",
          "Accepted bookings can only be cancelled before service start.",
        );
      }

      actorType = isProvider && !isCustomer ? "provider" : "customer";
      toStatus = actorType === "provider" ? "cancelledByProvider" : "cancelledByCustomer";

      const serviceId = String(booking.serviceId ?? "");
      slotId = String(booking.slotId ?? "");
      if (!serviceId || !slotId) {
        throw new HttpsError("failed-precondition", "Booking slot is missing.");
      }

      const slotRef = db.collection("services").doc(serviceId).collection("slots").doc(slotId);
      const slotSnapshot = await transaction.get(slotRef);
      if (!slotSnapshot.exists) {
        throw new HttpsError("not-found", "Slot not found.");
      }

      const slot = slotSnapshot.data()!;
      const currentAcceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
      const nextAcceptedCount = Math.max(currentAcceptedCount - 1, 0);
      const capacity = Math.max(toInt(slot.capacity, 1), 1);
      const slotStartAt = slot.startAt as Timestamp | undefined;
      const canBookAgain =
        nextAcceptedCount < capacity &&
        (!slotStartAt || slotStartAt.toMillis() - Date.now() >= 30 * 60 * 1000);

      transaction.update(slotRef, {
        acceptedCount: nextAcceptedCount,
        isBookable: canBookAgain,
        status: canBookAgain ? "open" : "closed",
        updatedAt: FieldValue.serverTimestamp(),
      });
      releasedCapacity = currentAcceptedCount > nextAcceptedCount;
    } else {
      throw new HttpsError(
        "failed-precondition",
        `Booking cannot be cancelled from status ${status}.`,
      );
    }

    transaction.update(bookingRef, {
      status: toStatus,
      cancelledAt: FieldValue.serverTimestamp(),
      cancelledBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
      "notificationState.cancellationNotificationSent": true,
      cancellation: {
        actorId: uid,
        actorType,
        reason,
        releasedCapacity,
        cancelledAt: FieldValue.serverTimestamp(),
      },
    });

    const recipientId =
      actorType === "customer" ?
        String(booking.serviceOwnerId ?? booking.providerId ?? "") :
        String(booking.customerId ?? "");
    const recipientRole = actorType === "customer" ? "provider" : "customer";
    const actorName =
      actorType === "customer" ?
        snapshotName(booking.customerSnapshot, "The customer") :
        snapshotName(booking.providerSnapshot, "The provider");

    queueBookingNotification({
      transaction,
      userId: recipientId,
      bookingId,
      type: "bookingCancelled",
      title: "Booking cancelled",
      body: `${actorName} cancelled ${serviceTitleFromBooking(booking)}.`,
      recipientRole,
      actorId: uid,
      status: toStatus,
      booking,
      extraData: {event: "booking_cancelled", releasedCapacity},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType,
    type: "cancelled",
    fromStatus,
    toStatus,
    message: reason,
    metadata: {releasedCapacity, slotId},
  });

  return {ok: true, releasedCapacity};
});

export const generateBookingOtp = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const otp = randomInt(100000, 999999).toString();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.customerId !== uid) {
      throw new HttpsError("permission-denied", "Only the customer can request the OTP.");
    }

    assertStatus(booking.status as BookingStatus, "accepted");

    const scheduledStartAt = booking.scheduledStartAt as Timestamp | undefined;
    if (
      scheduledStartAt &&
      Date.now() < scheduledStartAt.toMillis() - otpAvailabilityWindowMs
    ) {
      throw new HttpsError(
        "failed-precondition",
        "OTP can be generated 1 hour before service start.",
      );
    }

    transaction.update(bookingRef, {
      "otp.status": "generated",
      "otp.hash": hashOtp(bookingId, otp),
      "otp.attempts": 0,
      "otp.maxAttempts": 5,
      "otp.generatedAt": FieldValue.serverTimestamp(),
      "otp.expiresAt": Timestamp.fromMillis(Date.now() + otpValidityMs),
      "notificationState.otpNotificationSent": true,
      updatedAt: FieldValue.serverTimestamp(),
    });

    queueBookingNotification({
      transaction,
      userId: String(booking.serviceOwnerId ?? ""),
      bookingId,
      type: "bookingOtpGenerated",
      title: "OTP ready",
      body: `${snapshotName(
        booking.customerSnapshot,
        "The customer",
      )} generated the start OTP for ${serviceTitleFromBooking(booking)}.`,
      recipientRole: "provider",
      actorId: uid,
      status: "accepted",
      booking,
      extraData: {event: "otp_generated"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "customer",
    type: "otpGenerated",
    fromStatus: "accepted",
    toStatus: "accepted",
    message: "Booking OTP generated.",
  });

  return {otp};
});

export const verifyBookingOtpAndStart = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const otpAttempt = String(request.data?.otp ?? "");
  if (!bookingId || !otpAttempt) {
    throw new HttpsError("invalid-argument", "bookingId and otp are required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the provider can verify OTP.");
    }

    assertStatus(booking.status as BookingStatus, "accepted");

    const otp = booking.otp ?? {};
    if (otp.status !== "generated" || !otp.hash) {
      throw new HttpsError("failed-precondition", "OTP is not ready.");
    }

    const expiresAt = otp.expiresAt as Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      transaction.update(bookingRef, {
        "otp.status": "expired",
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError("deadline-exceeded", "OTP expired.");
    }

    const expected = Buffer.from(String(otp.hash), "hex");
    const actual = Buffer.from(hashOtp(bookingId, otpAttempt), "hex");
    const isMatch = expected.length === actual.length && timingSafeEqual(expected, actual);
    if (!isMatch) {
      transaction.update(bookingRef, {
        "otp.attempts": FieldValue.increment(1),
        "otp.status": "failed",
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError("permission-denied", "Invalid OTP.");
    }

    transaction.update(bookingRef, {
      status: "inProgress",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "otp.status": "verified",
      "otp.verifiedAt": FieldValue.serverTimestamp(),
      "otp.verifiedBy": uid,
      "notificationState.startNotificationSent": true,
    });

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingStarted",
      title: "Service started",
      body: `${snapshotName(
        booking.providerSnapshot,
        "Your provider",
      )} started ${serviceTitleFromBooking(booking)}.`,
      recipientRole: "customer",
      actorId: uid,
      status: "inProgress",
      booking,
      extraData: {event: "service_started"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "otpVerified",
    fromStatus: "accepted",
    toStatus: "inProgress",
    message: "Booking OTP verified and service started.",
  });

  return {ok: true};
});

export const completeBooking = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const payoutRef = db.collection("payoutReadiness").doc(bookingId);
  const now = FieldValue.serverTimestamp();
  let providerId = "";

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the provider can complete.");
    }
    assertStatus(booking.status as BookingStatus, "inProgress");

    providerId = booking.serviceOwnerId;
    const pricing = booking.pricing ?? {};
    const serviceId = String(booking.serviceId ?? "").trim();
    const serviceRef = serviceId ? db.collection("services").doc(serviceId) : null;
    const providerRef = providerId ? db.collection("users").doc(providerId) : null;
    const [serviceSnapshot, providerSnapshot] = await Promise.all([
      serviceRef ? transaction.get(serviceRef) : Promise.resolve(null),
      providerRef ? transaction.get(providerRef) : Promise.resolve(null),
    ]);

    transaction.update(bookingRef, {
      status: "completed",
      completedAt: now,
      updatedAt: now,
      "payoutReadiness.status": "eligible",
      "payoutReadiness.eligibleAt": now,
      "notificationState.completionNotificationSent": true,
    });

    transaction.set(payoutRef, {
      bookingId,
      serviceId: booking.serviceId,
      providerId,
      customerId: booking.customerId,
      grossAmount: pricing.grossAmount ?? 0,
      platformFee: pricing.platformFee ?? 0,
      providerEarnings: pricing.providerEarnings ?? 0,
      currency: pricing.currency ?? "INR",
      status: "eligible",
      eligibilityReason: "Booking completed after OTP verification.",
      eligibleAt: now,
      payoutId: "",
      createdAt: now,
      updatedAt: now,
    });

    if (serviceRef && serviceSnapshot?.exists == true) {
      const serviceData = serviceSnapshot.data() ?? {};
      const serviceStats = (serviceData.stats as Record<string, unknown> | undefined) ?? {};
      const currentCompletedCount = Math.max(
        0,
        toInt(serviceStats.completedBookingsCount ?? serviceData.completedBookingCount, 0),
      );
      const nextCompletedCount = currentCompletedCount + 1;
      const ratingAverage = toFiniteNumber(
        serviceStats.ratingAverage ?? serviceData.ratingAverage,
        0,
      );

      transaction.set(serviceRef, {
        completedBookingCount: nextCompletedCount,
        trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        stats: {
          ...serviceStats,
          completedBookingsCount: nextCompletedCount,
          trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        },
        updatedAt: now,
      }, {merge: true});
      console.log(
        "[completeBooking] service completedBookingCount updated",
        {
          bookingId,
          serviceId,
          previousCompletedBookingCount: currentCompletedCount,
          nextCompletedBookingCount: nextCompletedCount,
        },
      );
    }

    if (providerRef && providerSnapshot?.exists == true) {
      const providerData = providerSnapshot.data() ?? {};
      const currentCompletedCount = Math.max(
        0,
        toInt(providerData.completedBookingCount ?? providerData.completedBookingsCount, 0),
      );
      const nextCompletedCount = currentCompletedCount + 1;
      const ratingAverage = toFiniteNumber(providerData.ratingAverage, 0);

      transaction.set(providerRef, {
        completedBookingCount: nextCompletedCount,
        completedBookingsCount: nextCompletedCount,
        trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        updatedAt: now,
      }, {merge: true});
      console.log(
        "[completeBooking] provider completedBookingCount updated",
        {
          bookingId,
          providerId,
          previousCompletedBookingCount: currentCompletedCount,
          nextCompletedBookingCount: nextCompletedCount,
        },
      );
    }

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingCompleted",
      title: "Service completed",
      body: `${serviceTitleFromBooking(booking)} has been marked complete.`,
      recipientRole: "customer",
      actorId: uid,
      status: "completed",
      booking,
      extraData: {event: "service_completed"},
    });
    queueBookingNotification({
      transaction,
      userId: providerId,
      bookingId,
      type: "bookingCompleted",
      title: "Payout eligibility updated",
      body: `${serviceTitleFromBooking(booking)} is complete. Payout eligibility is now ready.`,
      recipientRole: "provider",
      actorId: uid,
      status: "completed",
      booking,
      extraData: {event: "service_completed", payoutStatus: "eligible"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "completed",
    fromStatus: "inProgress",
    toStatus: "completed",
    message: "Booking completed and payout marked eligible.",
    metadata: {providerId},
  });

  return {ok: true};
});

export const submitBookingReview = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "").trim();
  const rating = toInt(request.data?.rating, 0);
  const comment = String(request.data?.comment ?? "").trim();
  const rawTags = Array.isArray(request.data?.tags) ? request.data?.tags : [];
  const tags = rawTags
    .map((value: unknown) => String(value ?? "").trim())
    .filter((value: string) => value.length > 0);

  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  if (rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "rating must be between 1 and 5.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  let reviewRefPath = "";
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data()!;
    if ((booking.status as BookingStatus) !== "completed") {
      throw new HttpsError("failed-precondition", "Only completed bookings can be reviewed.");
    }
    if (String(booking.customerId ?? "") !== uid) {
      console.log("[submitBookingReview] invalid reviewer blocked", {
        bookingId,
        requesterUid: uid,
        customerId: String(booking.customerId ?? ""),
      });
      throw new HttpsError("permission-denied", "Only the booking customer can submit a review.");
    }

    const existingReviewId = String(booking.reviewId ?? booking.review?.reviewId ?? "").trim();
    const existingReviewStatus = String(
      booking.reviewStatus ?? booking.review?.status ?? "",
    ).trim();
    if (existingReviewId || existingReviewStatus.toLowerCase() === "submitted") {
      console.log("[submitBookingReview] duplicate review blocked", {
        bookingId,
        existingReviewId,
        existingReviewStatus,
        requesterUid: uid,
      });
      throw new HttpsError("failed-precondition", "Only one review is allowed per booking.");
    }

    const serviceId = String(booking.serviceId ?? "").trim();
    const providerUserId = String(
      booking.serviceOwnerId ?? booking.providerId ?? "",
    ).trim();
    if (!serviceId || !providerUserId) {
      throw new HttpsError(
        "failed-precondition",
        "Booking is missing service or provider details.",
      );
    }

    const reviewRef = db.collection("services").doc(serviceId).collection("reviews").doc(bookingId);
    const serviceRef = db.collection("services").doc(serviceId);
    const providerRef = db.collection("users").doc(providerUserId);
    reviewRefPath = reviewRef.path;

    const [reviewSnapshot, serviceSnapshot, providerSnapshot] = await Promise.all([
      transaction.get(reviewRef),
      transaction.get(serviceRef),
      transaction.get(providerRef),
    ]);
    if (reviewSnapshot.exists) {
      console.log("[submitBookingReview] duplicate review blocked", {
        bookingId,
        reviewPath: reviewRef.path,
        requesterUid: uid,
      });
      throw new HttpsError("failed-precondition", "Only one review is allowed per booking.");
    }
    if (!serviceSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Service no longer exists.");
    }
    if (!providerSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Provider profile no longer exists.");
    }

    const serviceData = serviceSnapshot.data() ?? {};
    const serviceStats = (serviceData.stats as Record<string, unknown> | undefined) ?? {};
    const currentServiceRatingCount = Math.max(
      0,
      toInt(serviceStats.ratingCount ?? serviceData.ratingCount, 0),
    );
    const currentServiceRatingAverage = toFiniteNumber(
      serviceStats.ratingAverage ?? serviceData.ratingAverage,
      0,
    );
    const currentServiceCompletedCount = Math.max(
      0,
      toInt(serviceStats.completedBookingsCount ?? serviceData.completedBookingCount, 0),
    );
    const nextServiceRatingCount = currentServiceRatingCount + 1;
    const nextServiceRatingAverage = nextRatingAverage(
      currentServiceRatingAverage,
      currentServiceRatingCount,
      rating,
    );
    const nextServiceTrustScore = computeTrustScore(
      nextServiceRatingAverage,
      currentServiceCompletedCount,
    );
    const currentServiceReviewedCount = Math.max(
      0,
      toInt(serviceStats.reviewedBookingCount ?? serviceData.reviewedBookingCount, 0),
    );

    const providerData = providerSnapshot.data() ?? {};
    const currentProviderRatingCount = Math.max(
      0,
      toInt(providerData.ratingCount, 0),
    );
    const currentProviderRatingAverage = toFiniteNumber(providerData.ratingAverage, 0);
    const currentProviderCompletedCount = Math.max(
      0,
      toInt(providerData.completedBookingCount ?? providerData.completedBookingsCount, 0),
    );
    const nextProviderRatingCount = currentProviderRatingCount + 1;
    const nextProviderRatingAverage = nextRatingAverage(
      currentProviderRatingAverage,
      currentProviderRatingCount,
      rating,
    );
    const nextProviderTrustScore = computeTrustScore(
      nextProviderRatingAverage,
      currentProviderCompletedCount,
    );
    const currentProviderReviewedCount = Math.max(
      0,
      toInt(providerData.reviewedBookingCount, 0),
    );

    const customerSnapshot = booking.customerSnapshot ?? {};
    transaction.set(reviewRef, {
      bookingId,
      serviceId,
      providerUserId,
      reviewerUserId: uid,
      reviewerId: uid,
      reviewerName: customerSnapshot.name ?? "",
      reviewerPhotoUrl: customerSnapshot.photoUrl ?? "",
      rating,
      comment,
      tags,
      isEdited: false,
      moderationStatus: "approved",
      createdAt: now,
      updatedAt: now,
    });

    transaction.update(bookingRef, {
      reviewStatus: "submitted",
      reviewId: reviewRef.id,
      review: {
        status: "submitted",
        reviewId: reviewRef.id,
        submittedAt: now,
      },
      updatedAt: now,
    });

    transaction.set(serviceRef, {
      ratingAverage: nextServiceRatingAverage,
      ratingCount: nextServiceRatingCount,
      reviewedBookingCount: currentServiceReviewedCount + 1,
      trustScore: nextServiceTrustScore,
      stats: {
        ...serviceStats,
        ratingAverage: nextServiceRatingAverage,
        ratingCount: nextServiceRatingCount,
        reviewedBookingCount: currentServiceReviewedCount + 1,
        trustScore: nextServiceTrustScore,
      },
      updatedAt: now,
    }, {merge: true});

    transaction.set(providerRef, {
      ratingAverage: nextProviderRatingAverage,
      ratingCount: nextProviderRatingCount,
      reviewedBookingCount: currentProviderReviewedCount + 1,
      trustScore: nextProviderTrustScore,
      updatedAt: now,
    }, {merge: true});

    console.log("[submitBookingReview] service rating summary updated", {
      bookingId,
      serviceId,
      ratingAverage: nextServiceRatingAverage,
      ratingCount: nextServiceRatingCount,
      trustScore: nextServiceTrustScore,
      reviewedBookingCount: currentServiceReviewedCount + 1,
    });
    console.log("[submitBookingReview] provider rating summary updated", {
      bookingId,
      providerUserId,
      ratingAverage: nextProviderRatingAverage,
      ratingCount: nextProviderRatingCount,
      trustScore: nextProviderTrustScore,
      reviewedBookingCount: currentProviderReviewedCount + 1,
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "customer",
    type: "reviewSubmitted",
    fromStatus: "completed",
    toStatus: "completed",
    message: "Booking review submitted.",
    metadata: {reviewRefPath, rating},
  });

  return {ok: true, reviewId: bookingId};
});

export const moderateService = onCall(async (request) => {
  requireAdmin(request.auth);
  const adminUid = request.auth!.uid;
  const serviceId = String(request.data?.serviceId ?? "");
  const moderationItemId = String(request.data?.moderationItemId ?? "");
  const action = String(request.data?.action ?? "");
  const reason = String(request.data?.reason ?? "");

  if (!serviceId || !action) {
    throw new HttpsError("invalid-argument", "serviceId and action are required.");
  }

  const serviceRef = db.collection("services").doc(serviceId);
  const auditRef = db.collection("adminAuditLogs").doc();
  const queueRef = moderationItemId
    ? db.collection("moderationQueue").doc(moderationItemId)
    : null;

  const isApproved = action === "approve";
  const servicePatch = isApproved
    ? {
        moderationStatus: "approved",
        isVisibleToMarketplace: true,
        updatedAt: FieldValue.serverTimestamp(),
      }
    : {
        moderationStatus: "removed",
        moderationReason: reason,
        isVisibleToMarketplace: false,
        isActive: false,
        status: "removed",
        updatedAt: FieldValue.serverTimestamp(),
        removedAt: FieldValue.serverTimestamp(),
      };

  const batch = db.batch();
  batch.set(serviceRef, servicePatch, {merge: true});
  if (queueRef) {
    batch.set(queueRef, {
      status: isApproved ? "approved" : "removed",
      assignedAdminId: adminUid,
      reason,
      updatedAt: FieldValue.serverTimestamp(),
      resolvedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  batch.set(auditRef, {
    adminId: adminUid,
    action: isApproved ? "service.approve" : "service.remove",
    targetType: "service",
    targetId: serviceId,
    reason,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return {ok: true};
});
