# Pettxo Backend Firestore Schema

This document defines the production Firestore data model for Pettxo's open service marketplace, booking request flow, OTP-based service start, payout readiness, moderation, and future admin tooling.

## Core Business Rules

- Any authenticated user can create a service listing.
- Any authenticated user can request a booking.
- A booking is created as a request, not an immediate confirmation.
- The service owner must accept or reject the request.
- Confirmation notifications are sent only after the owner accepts.
- Service start requires OTP verification from the customer.
- Completion should mark the provider as eligible for payout when all platform rules are satisfied.
- Admin moderation and dispute handling must be supported from the schema level.

## Collection Overview

```text
users/{userId}
services/{serviceId}
bookings/{bookingId}
bookingEvents/{eventId}
payoutReadiness/{bookingId}
payouts/{payoutId}
reports/{reportId}
disputes/{disputeId}
moderationQueue/{moderationItemId}
adminAuditLogs/{logId}
notifications/{notificationId}
userPrivate/{userId}
```

Recommended subcollections:

```text
users/{userId}/notificationTokens/{tokenId}
users/{userId}/adminNotes/{noteId}
services/{serviceId}/reviews/{reviewId}
services/{serviceId}/moderationEvents/{eventId}
bookings/{bookingId}/events/{eventId}
bookings/{bookingId}/messages/{messageId}
bookings/{bookingId}/statusHistory/{historyId}
disputes/{disputeId}/messages/{messageId}
disputes/{disputeId}/evidence/{evidenceId}
```

Use top-level `services` and `bookings` collections for marketplace queries, cross-user reads, admin moderation, and scalable indexing.

## Users

Path:

```text
users/{userId}
```

Document shape:

```js
{
  uid: string,
  email: string,
  phone: string,
  mobileNumber: string,
  name: string,
  username: string,
  usernameLowercase: string,
  role: "petParent" | "petLover" | "serviceProvider" | "admin",
  accountType: "user" | "admin",
  profileImage: string,
  bio: string,
  state: string,
  city: string,
  location: string,
  createdAt: timestamp,
  updatedAt: timestamp,
  lastActiveAt: timestamp,
  status: "active" | "disabled" | "deleted" | "underReview",
  moderationStatus: "clear" | "flagged" | "restricted",
  stats: {
    servicesCount: number,
    completedBookingsCount: number,
    cancelledBookingsCount: number,
    ratingAverage: number,
    ratingCount: number
  }
}
```

Private user data:

```text
userPrivate/{userId}
```

```js
{
  uid: string,
  email: string,
  phone: string,
  payoutAccountStatus: "notStarted" | "pending" | "verified" | "rejected",
  payoutProviderCustomerId: string,
  payoutProviderAccountId: string,
  adminFlags: string[],
  createdAt: timestamp,
  updatedAt: timestamp
}
```

Use `users/{userId}` for public profile data. Use `userPrivate/{userId}` for sensitive fields and payout-provider references.

## Services

Path:

```text
services/{serviceId}
```

Document shape:

```js
{
  id: string,
  ownerId: string,
  ownerName: string,
  ownerUsername: string,
  ownerPhotoUrl: string,
  ownerCity: string,
  ownerState: string,

  title: string,
  animalType: string,
  animalTypeLowercase: string,
  category: string,
  categoryLowercase: string,
  description: string,
  privateNotes: string,

  pricePerSession: number,
  currency: "INR",
  durationMinutes: number,
  capacity: number,

  availableDays: string[],
  startMinutes: number,
  endMinutes: number,
  sameForAllDays: boolean,
  timezone: string,

  serviceType: "providerLocation" | "homeVisit",
  serviceRadiusKm: number,
  location: {
    displayAddress: string,
    latitude: number,
    longitude: number,
    geohash: string,
    city: string,
    state: string,
    country: string
  },

  photoUrls: string[],
  primaryPhotoUrl: string,

  status: "draft" | "active" | "paused" | "removed" | "underReview" | "rejected",
  moderationStatus: "pending" | "approved" | "flagged" | "removed",
  moderationReason: string,

  stats: {
    ratingAverage: number,
    ratingCount: number,
    completedBookingsCount: number,
    activeBookingsCount: number,
    requestCount: number
  },

  createdAt: timestamp,
  updatedAt: timestamp,
  publishedAt: timestamp,
  pausedAt: timestamp,
  removedAt: timestamp
}
```

Subcollection:

```text
services/{serviceId}/reviews/{reviewId}
```

```js
{
  id: string,
  serviceId: string,
  bookingId: string,
  reviewerId: string,
  reviewerName: string,
  reviewerPhotoUrl: string,
  providerId: string,
  rating: number,
  comment: string,
  moderationStatus: "pending" | "approved" | "flagged" | "removed",
  createdAt: timestamp,
  updatedAt: timestamp
}
```

## Bookings

Use one top-level `bookings` collection. A booking begins as a request.

Path:

```text
bookings/{bookingId}
```

Document shape:

```js
{
  id: string,
  serviceId: string,
  serviceOwnerId: string,
  customerId: string,

  serviceSnapshot: {
    title: string,
    animalType: string,
    category: string,
    pricePerSession: number,
    currency: "INR",
    durationMinutes: number,
    serviceType: "providerLocation" | "homeVisit",
    primaryPhotoUrl: string
  },

  providerSnapshot: {
    name: string,
    username: string,
    photoUrl: string,
    phoneMasked: string
  },

  customerSnapshot: {
    name: string,
    username: string,
    photoUrl: string,
    phoneMasked: string
  },

  locationSnapshot: {
    displayAddress: string,
    latitude: number,
    longitude: number,
    geohash: string
  },

  scheduledStartAt: timestamp,
  scheduledEndAt: timestamp,
  timezone: string,

  status: "requested" |
    "accepted" |
    "rejected" |
    "cancelledByCustomer" |
    "cancelledByProvider" |
    "expired" |
    "inProgress" |
    "completed" |
    "disputed" |
    "noShow",

  request: {
    message: string,
    expiresAt: timestamp,
    respondedAt: timestamp,
    responseReason: string
  },

  pricing: {
    grossAmount: number,
    platformFee: number,
    providerEarnings: number,
    currency: "INR",
    paymentStatus: "notStarted" | "authorized" | "paid" | "refunded" | "failed"
  },

  otp: {
    status: "notGenerated" | "generated" | "verified" | "failed" | "expired",
    attempts: number,
    maxAttempts: number,
    generatedAt: timestamp,
    expiresAt: timestamp,
    verifiedAt: timestamp,
    verifiedBy: string
  },

  payoutReadiness: {
    status: "notEligible" | "eligible" | "onHold" | "paid",
    reason: string,
    eligibleAt: timestamp,
    payoutId: string
  },

  dispute: {
    hasDispute: boolean,
    disputeId: string,
    status: "none" | "open" | "underReview" | "resolved"
  },

  notificationState: {
    acceptanceNotificationSent: boolean,
    reminderNotificationSent: boolean,
    completionNotificationSent: boolean
  },

  createdAt: timestamp,
  updatedAt: timestamp,
  acceptedAt: timestamp,
  rejectedAt: timestamp,
  cancelledAt: timestamp,
  startedAt: timestamp,
  completedAt: timestamp
}
```

Subcollections:

```text
bookings/{bookingId}/events/{eventId}
bookings/{bookingId}/statusHistory/{historyId}
bookings/{bookingId}/messages/{messageId}
```

Booking event shape:

```js
{
  id: string,
  bookingId: string,
  actorId: string,
  actorType: "customer" | "provider" | "admin" | "system",
  type: "created" |
    "accepted" |
    "rejected" |
    "cancelled" |
    "otpGenerated" |
    "otpVerified" |
    "started" |
    "completed" |
    "disputed" |
    "payoutEligible",
  fromStatus: string,
  toStatus: string,
  message: string,
  metadata: map,
  createdAt: timestamp
}
```

## OTP And Session Verification

Do not store raw OTP values in Firestore.

Recommended server-managed fields on `bookings/{bookingId}`:

```js
{
  otp: {
    status: "notGenerated" | "generated" | "verified" | "failed" | "expired",
    hash: string,
    saltVersion: string,
    attempts: number,
    maxAttempts: number,
    generatedAt: timestamp,
    expiresAt: timestamp,
    verifiedAt: timestamp,
    verifiedBy: string
  },
  startedAt: timestamp,
  completedAt: timestamp
}
```

Client-visible OTP fields should be limited. The customer may receive the OTP through app UI after acceptance, but the provider should only submit an OTP attempt to a trusted backend function. The backend validates the attempt and updates `otp.status`, `startedAt`, and booking status.

## Payout Readiness And Payouts

Path:

```text
payoutReadiness/{bookingId}
```

```js
{
  bookingId: string,
  serviceId: string,
  providerId: string,
  customerId: string,
  grossAmount: number,
  platformFee: number,
  providerEarnings: number,
  currency: "INR",
  status: "notEligible" | "eligible" | "onHold" | "paid" | "cancelled",
  eligibilityReason: string,
  eligibleAt: timestamp,
  holdUntil: timestamp,
  payoutId: string,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

Path:

```text
payouts/{payoutId}
```

```js
{
  id: string,
  providerId: string,
  bookingIds: string[],
  amount: number,
  currency: "INR",
  status: "pending" | "processing" | "paid" | "failed" | "cancelled",
  payoutProvider: string,
  payoutProviderTransferId: string,
  failureReason: string,
  createdAt: timestamp,
  processedAt: timestamp,
  updatedAt: timestamp
}
```

Payout readiness should be created by backend logic only after:

- booking status is `completed`
- OTP status is `verified`
- no active dispute exists
- payment is captured/settled
- cancellation/no-show windows are resolved

## Reports And Disputes

Reports are for moderation. Disputes are for transactional booking issues.

Path:

```text
reports/{reportId}
```

```js
{
  id: string,
  reporterId: string,
  targetType: "user" | "service" | "review" | "message" | "booking",
  targetId: string,
  targetOwnerId: string,
  reason: string,
  description: string,
  evidenceUrls: string[],
  status: "open" | "triaged" | "actioned" | "dismissed",
  assignedAdminId: string,
  resolution: string,
  createdAt: timestamp,
  updatedAt: timestamp,
  resolvedAt: timestamp
}
```

Path:

```text
disputes/{disputeId}
```

```js
{
  id: string,
  bookingId: string,
  serviceId: string,
  providerId: string,
  customerId: string,
  openedBy: string,
  reason: string,
  description: string,
  evidenceUrls: string[],
  status: "open" | "underReview" | "waitingForCustomer" | "waitingForProvider" | "resolved" | "closed",
  assignedAdminId: string,
  resolution: "refundCustomer" | "releasePayout" | "partialRefund" | "dismissed" | "other",
  payoutHoldApplied: boolean,
  createdAt: timestamp,
  updatedAt: timestamp,
  resolvedAt: timestamp
}
```

Recommended subcollections:

```text
disputes/{disputeId}/messages/{messageId}
disputes/{disputeId}/evidence/{evidenceId}
```

## Moderation Queue And Admin Logs

Path:

```text
moderationQueue/{moderationItemId}
```

```js
{
  id: string,
  targetType: "user" | "service" | "review" | "post" | "message" | "booking",
  targetId: string,
  targetOwnerId: string,
  source: "auto" | "report" | "admin" | "system",
  reportId: string,
  severity: "low" | "medium" | "high" | "critical",
  status: "pending" | "reviewing" | "approved" | "restricted" | "removed" | "dismissed",
  reason: string,
  assignedAdminId: string,
  createdAt: timestamp,
  updatedAt: timestamp,
  resolvedAt: timestamp
}
```

Path:

```text
adminAuditLogs/{logId}
```

```js
{
  id: string,
  adminId: string,
  adminEmail: string,
  action: string,
  targetType: "user" | "service" | "booking" | "report" | "dispute" | "payout",
  targetId: string,
  before: map,
  after: map,
  reason: string,
  metadata: map,
  createdAt: timestamp
}
```

Admin permissions should be based on Firebase Auth custom claims, not on a client-writable `role` field.

## Notifications

Path:

```text
notifications/{notificationId}
```

```js
{
  id: string,
  userId: string,
  type: "bookingRequested" |
    "bookingAccepted" |
    "bookingRejected" |
    "bookingReminder" |
    "otpRequired" |
    "bookingCompleted" |
    "disputeUpdated" |
    "moderationAction",
  title: string,
  body: string,
  data: map,
  readAt: timestamp,
  createdAt: timestamp
}
```

Acceptance confirmation notification must be created by backend logic only when booking status changes from `requested` to `accepted`.

## Denormalized Fields For Fast Reads

Denormalize these fields intentionally:

- On `services`: owner name, username, owner photo, city, state, rating stats, primary photo URL.
- On `bookings`: service snapshot, provider snapshot, customer snapshot, price snapshot, location snapshot.
- On `reports`: target owner ID, target type, target ID.
- On `disputes`: booking ID, service ID, provider ID, customer ID, current status.
- On `payoutReadiness`: booking ID, provider ID, amount fields, current eligibility status.

Denormalization prevents expensive fan-out reads for list screens, booking detail screens, admin queues, and notifications.

## Server-Managed Only Fields

These fields should be created or updated only by trusted backend logic, Cloud Functions, or admin tooling:

- `createdAt`
- `updatedAt`
- `publishedAt`
- `acceptedAt`
- `rejectedAt`
- `cancelledAt`
- `startedAt`
- `completedAt`
- `status` transitions on bookings
- `otp.hash`
- `otp.saltVersion`
- `otp.status`
- `otp.attempts`
- `otp.generatedAt`
- `otp.expiresAt`
- `otp.verifiedAt`
- `payoutReadiness.status`
- `payoutReadiness.eligibleAt`
- `payoutReadiness.payoutId`
- `pricing.platformFee`
- `pricing.providerEarnings`
- `notificationState.*`
- `moderationStatus`
- `moderationReason`
- `assignedAdminId`
- `adminAuditLogs/*`
- aggregate stats such as rating averages and booking counts

## Fields That Should Never Be Client-Controlled

Clients must never directly control:

- `ownerId` on services, except the backend/rules should force it to equal `request.auth.uid`.
- `serviceOwnerId` on bookings, except derived from the service document.
- `customerId` on bookings, except the backend/rules should force it to equal `request.auth.uid` on creation.
- Any raw OTP or OTP hash.
- Booking status transitions after creation.
- Payout amounts and payout eligibility.
- Platform fees and provider earnings.
- Moderation status or admin assignments.
- Admin role/custom claims.
- Audit log content.
- Notification sent flags.
- Review aggregate stats.
- Dispute resolution.

## Recommended Indexes

Firestore composite indexes:

```json
[
  {
    "collectionGroup": "services",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "moderationStatus", "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "services",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "ownerId", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "updatedAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "services",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "animalTypeLowercase", "order": "ASCENDING" },
      { "fieldPath": "categoryLowercase", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "moderationStatus", "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "services",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "location.geohash", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "moderationStatus", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "bookings",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "customerId", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "scheduledStartAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "bookings",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "serviceOwnerId", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "scheduledStartAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "bookings",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "serviceId", "order": "ASCENDING" },
      { "fieldPath": "scheduledStartAt", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "reports",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "disputes",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "updatedAt", "order": "DESCENDING" }
    ]
  },
  {
    "collectionGroup": "moderationQueue",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "severity", "order": "DESCENDING" },
      { "fieldPath": "createdAt", "order": "ASCENDING" }
    ]
  },
  {
    "collectionGroup": "payoutReadiness",
    "queryScope": "COLLECTION",
    "fields": [
      { "fieldPath": "providerId", "order": "ASCENDING" },
      { "fieldPath": "status", "order": "ASCENDING" },
      { "fieldPath": "eligibleAt", "order": "ASCENDING" }
    ]
  }
]
```

For geospatial discovery, store `location.geohash` and query geohash ranges, then calculate exact distance client-side or in backend logic.

## Recommended Security Rule Direction

High-level rules:

- Authenticated users can read active, approved services.
- Authenticated users can create services only with `ownerId == request.auth.uid`.
- Service owners can update safe editable fields only while no conflicting active bookings exist.
- Service owners cannot self-approve moderation fields.
- Authenticated users can create booking requests only with `customerId == request.auth.uid`.
- Booking accept/reject/start/complete transitions should go through Cloud Functions, not direct client writes.
- Users can read bookings where they are `customerId` or `serviceOwnerId`.
- Admins can read/write moderation/admin collections only through custom claims.
- Storage paths should require ownership and validate content type/size where possible.

## Recommended Build Order

1. Add `firestore.rules`, `storage.rules`, and `firestore.indexes.json`.
2. Create Firestore-backed service model/repository.
3. Move Add Service publishing from local storage to `services/{serviceId}`.
4. Upload service photos to Storage and store URLs.
5. Connect Profile > Services and Services marketplace to Firestore.
6. Add booking request creation with status `requested`.
7. Add backend-controlled accept/reject transition and acceptance notification.
8. Add OTP generation/verification through backend functions.
9. Add completion and payout readiness creation.
10. Add reports, disputes, moderation queue, and admin audit logs.
