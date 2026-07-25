# Pettxo Booking v3.2 Schema

This document now covers Block 1 foundations plus Block 2 schema, read-model,
query-compatibility, privacy-separation, index/rules design, and Block 3
internal lifecycle foundations. It still does not activate the request-first
lifecycle for production users.

## Non-goals in This Block

- The active payment-first booking flow remains live.
- No new v3.2 writer is active in Cloud Functions.
- No canonical request callable is exported for production clients.
- No canonical scheduler is exported or running.
- No payment, Razorpay, capacity, OTP, scheduler, reminder, or notification
  behavior changed.
- No Firestore migration ran.
- No Functions, rules, or indexes were deployed.

## Rollout Gate Foundation

Canonical booking activation now has a server-owned rollout foundation:

- Firestore config document path:
  `runtimeConfig/bookingV32Rollout`
- Default behavior when the document is missing:
  canonical booking stays disabled
- Resolver callable:
  `resolveBookingFlowV3`

Current precedence:

1. global `enabled`
2. supported booking type allowlist
3. explicit user allowlist
4. explicit provider allowlist
5. explicit service allowlist
6. explicit category allowlist
7. deterministic rollout bucket percentage
8. fallback to legacy

The client is allowed to read the decision, but it is not allowed to enable
canonical flow on its own.

## Canonical Schema Markers

Every canonical booking document must include:

```json
{
  "schemaVersion": 3,
  "bookingModelVersion": "3.2",
  "documentFormat": "canonical_v3"
}
```

Version detection never relies only on legacy `status` spelling.

## Canonical Root Shape

Canonical bookings live at `bookings/{bookingId}` and use:

```json
{
  "schemaVersion": 3,
  "bookingModelVersion": "3.2",
  "documentFormat": "canonical_v3",
  "bookingType": "SLOT | RANGE",
  "state": "REQUESTED | ...",
  "participants": {},
  "service": {},
  "schedule": {},
  "lifecycle": {},
  "payment": {},
  "financials": {},
  "privacy": {},
  "cancellation": {},
  "dispute": {},
  "payout": {},
  "statistics": {},
  "audit": {},
  "parentId": "...",
  "providerId": "...",
  "serviceId": "...",
  "stateQueryValue": "...",
  "bookingTypeQueryValue": "...",
  "serviceAnchorAt": "Timestamp",
  "scheduledStartAt": "Timestamp | null",
  "checkInDateTime": "Timestamp | null",
  "acceptDeadlineAt": "Timestamp | null",
  "payDeadlineAt": "Timestamp | null",
  "completedAt": "Timestamp | null",
  "customerId": "...",
  "serviceOwnerId": "...",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

## Query-friendly Top-level Duplicates

These intentionally duplicate nested canonical fields so current and future
queries remain practical:

- `parentId`
- `providerId`
- `serviceId`
- `stateQueryValue`
- `bookingTypeQueryValue`
- `serviceAnchorAt`
- `scheduledStartAt`
- `checkInDateTime`
- `acceptDeadlineAt`
- `payDeadlineAt`
- `completedAt`
- `customerId`
- `serviceOwnerId`

Compatibility duplicates kept for legacy query parity:

- `customerId = parentId`
- `serviceOwnerId = providerId`

Current Flutter repository queries still read `customerId`, `serviceOwnerId`,
and `scheduledStartAt`, so canonical docs keep those fields instead of forcing
dual query strategies.

## Participants and Privacy Separation

`participants.parent` is deliberately request-safe and excludes:

- full legal name
- full phone number
- email
- exact address
- exact coordinates
- private profile metadata

Public parent snapshot keeps only:

- `parentId`
- `displayFirstName`
- `lastInitial`
- `photoUrl`
- `completedBookingCount`
- `rating`

Private contact/address data is designed for a separate document, for example:

```json
bookingPrivate/{bookingId}
```

with:

- `documentFormat: "canonical_v3_private"`
- `unlockedAfterPaidOnly: true`
- `parentPrivate.fullName`
- `parentPrivate.phoneNumber`
- `parentPrivate.email`
- `parentPrivate.exactAddress`
- `parentPrivate.latitude`
- `parentPrivate.longitude`

Why this is safer:

- Firestore rules cannot redact fields within a readable document.
- Keeping private contact data outside `bookings/{bookingId}` prevents a
  provider from reading it before payment through a normal document fetch.
- UI hiding is not part of the security model.

## Immutable Service Snapshot

Canonical service snapshot embeds the immutable Block 1 contract.

Common fields:

- `serviceId`
- `providerId`
- `serviceTitle`
- `animalType`
- `category`
- `bookingType`
- `timezone`
- `currency`
- `serviceLocationType`
- `snapshotVersion`

SLOT fields:

- `serviceUnitPricePaise`
- `durationMinutes`
- `selectedSlotCount`
- `totalDurationMinutes`

RANGE fields:

- `pricePerNightPaise`
- `minNightsSnapshot`
- `maxNightsSnapshot`
- `maxConcurrentPetsSnapshot`
- `petQuantity`

## Schedule Structure

### SLOT

```json
{
  "bookingType": "SLOT",
  "slots": [
    {
      "slotId": "slot-1",
      "dateKey": "2026-07-23",
      "startAt": "Timestamp",
      "endAt": "Timestamp",
      "durationMinutes": 60,
      "unitPricePaise": 25000,
      "serviceId": "service-1",
      "providerId": "provider-1",
      "timezone": "Asia/Kolkata"
    }
  ],
  "slotCount": 1,
  "scheduledStartAt": "Timestamp",
  "scheduledEndAt": "Timestamp",
  "totalDurationMinutes": 60,
  "timezone": "Asia/Kolkata",
  "serviceAnchorAt": "Timestamp"
}
```

### Multi-slot SLOT

Same structure, but `slots` holds multiple continuous segments and
`slotCount/totalDurationMinutes` must match the derived values.

### RANGE

```json
{
  "bookingType": "RANGE",
  "checkInDateTime": "Timestamp",
  "checkOutDateTime": "Timestamp",
  "nights": 2,
  "timezone": "Asia/Kolkata",
  "minNightsSnapshot": 1,
  "maxNightsSnapshot": 14,
  "maxConcurrentPetsSnapshot": 2,
  "petQuantity": 1,
  "serviceAnchorAt": "Timestamp"
}
```

Derived anchor rule:

- SLOT `serviceAnchorAt = scheduledStartAt`
- RANGE `serviceAnchorAt = checkInDateTime`

Both backend and Flutter readers validate the anchor consistency.

## Lifecycle Timestamp Spine

Canonical lifecycle fields:

- `requestedAt`
- `timerStartsAt`
- `wasQueuedOutsideWorkingHours`
- `notifiedAt`
- `acceptDeadlineAt`
- `viewedByProviderAt`
- `respondedAt`
- `providerResponseType`
- `responseSeconds`
- `payDeadlineAt`
- `paymentStartedAt`
- `paidAt`
- `paymentSeconds`
- `otpGeneratedAt`
- `otpEnteredAt`
- `serviceEndedAt`
- `disputeDeadlineAt`
- `completedAt`
- `cancelledAt`

Validation rejects impossible combinations such as:

- `paidAt` without `respondedAt`
- `otpGeneratedAt` before `paidAt`
- `completedAt` without `serviceEndedAt`
- `payDeadlineAt` without provider response

## Payment and Financial Structure

`payment` stores reconciliation metadata and attempt state. `financials` stores
the immutable paise-only snapshot.

Important rule:

- any booking that appears paid/captured/verified must also include canonical
  `financials`

Financial snapshot fields:

- `serviceSubtotalPaise`
- `couponDiscountPaise`
- `customerPaidPaise`
- `platformCommissionRateBasisPoints`
- `platformCommissionPaise`
- `providerPayoutPaise`
- `pettxoCouponFundingPaise`
- `gatewayFeeSunkPaise`
- `providerFaultCostPaise`
- `refundAmountPaise`
- `pettxoNetBeforeGatewayPaise`
- `currency`
- `pricingVersion`

## Cancellation, Dispute, and Payout

Canonical nested sections exist for:

- `cancellation`
- `dispute`
- `payout`

They define the read/write contract only. Live execution behavior has not
changed in this block.

## Dual Legacy/V3 Parsing

Backend:

- canonical documents are detected by schema markers
- legacy documents are read separately and normalized through explicit
  legacy-status compatibility
- malformed canonical docs become structured invalid read results rather than
  crashing the reader

Flutter:

- legacy `BookingModel` stays intact
- new canonical reader lives in separate files
- repository now exposes additional dual-read methods
- legacy UI remains on current repository methods unless explicitly migrated

## Legacy Compatibility

Current production writers still create legacy booking documents.

This block keeps:

- existing `BookingModel`
- existing repository methods
- existing query fields
- existing booking screens compiling

Canonical readers are additive only.

## Block 3 Internal Lifecycle

The internal canonical lifecycle implemented in Block 3 supports:

- `REQUESTED -> PENDING_PROVIDER`
- `REQUESTED -> CANCELLED_BY_PARENT`
- `PENDING_PROVIDER -> ACCEPTED_AWAITING_PAYMENT`
- `PENDING_PROVIDER -> DECLINED`
- `PENDING_PROVIDER -> EXPIRED`
- `PENDING_PROVIDER -> CANCELLED_BY_PARENT`
- `ACCEPTED_AWAITING_PAYMENT -> PAYMENT_EXPIRED`

Not implemented in Block 3:

- `ACCEPTED_AWAITING_PAYMENT -> CONFIRMED`

That connection remains deferred to Block 4 so production users cannot enter an
accepted-but-unpayable state.

## Working-hours Timer Model

Block 3 normalizes the current real service schema:

- `availableDays`
- `startMinutes`
- `endMinutes`
- `timezone`
- `status`
- `isActive`
- `isDeleted`
- `isPaused`
- `isVisibleToMarketplace`
- `providerVerificationStatus`
- `providerVerificationGraceEndsAt`
- `isPausedByVerification`

Current source support is explicitly single-interval-per-day.

Timer behavior:

- during working hours: `timerStartsAt = requestedAt`
- outside working hours: `timerStartsAt = next working opening`
- queued requests are created immediately but remain `REQUESTED`
- active response clock begins only after transition to `PENDING_PROVIDER`

RUNWAY rule:

- `serviceAnchorAt >= timerStartsAt + 150 minutes`

This is validated for both SLOT and RANGE requests without consuming capacity.

## Block 3 Notifications and Events

Block 3 adds internal request-safe notification builders for:

- queued request created
- provider action required
- payment required after acceptance
- decline
- acceptance expiry
- parent cancellation
- payment expiry

Implemented event intents:

- `requested`
- `timer_started`
- `viewed_by_provider`
- `accepted`
- `declined`
- `expired`
- `payment_abandoned`
- `cancelled`

These are internal foundations only and are not yet connected to deployed
canonical triggers.

## Block 3 Stats Foundations

Provider stats foundation fields:

- `requestsReceived`
- `requestsAccepted`
- `requestsDeclined`
- `requestsExpired`
- `consecutiveDeclines`
- `consecutiveExpiries`
- `responseSamples`
- `parentPaymentAbandoned`
- `updatedAt`

Parent stats foundation fields:

- `requestsSent`
- `paymentsCompleted`
- `paymentsAbandoned`
- `cancellationsAfterPayment`
- `requiresUpfrontPayment`

Upfront-payment enforcement remains intentionally inactive due product-policy
conflict with the locked post-acceptance payment model.

## Firestore Rules Design

Rules were not changed in this block and were not deployed.

Required future rule shape:

- booking docs are server-written only
- clients cannot modify canonical `state`, `financials`, `payment`, or capacity
- parent/provider can read only their own bookings
- private contact doc must not be readable before `paidAt`
- unrelated users cannot query bookings
- admin access must remain explicit
- booking events remain append-only and non-updatable

Because the safest privacy design depends on separate private documents, these
rule updates should ship together with the future private-data reader flow.

## Firestore Index Strategy

Indexes were not changed in this block and were not deployed.

Planned composite indexes:

- `parentId + stateQueryValue + serviceAnchorAt`
- `providerId + stateQueryValue + serviceAnchorAt`
- `stateQueryValue + acceptDeadlineAt`
- `stateQueryValue + payDeadlineAt`
- `stateQueryValue + completedAt`
- `stateQueryValue + serviceAnchorAt`
- `payout.status + payout.eligibleAt`

RANGE overlap limitation:

- Firestore cannot solve arbitrary interval overlap with one simple query.
- Future RANGE capacity should use deterministic daily occupancy documents,
  date-bucket counters, or another per-date allocation model.

## Sample Canonical Fixtures

Developer-only fixtures now exist for:

1. requested single-slot booking
2. requested multi-slot booking
3. accepted-awaiting-payment slot booking
4. confirmed slot booking
5. requested range booking
6. confirmed range booking
7. cancelled booking with refund snapshot
8. completed-final booking

These live in code/tests only and are not written to Firestore.

## Block 4 Canonical Payment Orchestration

Block 4 adds internal, inactive canonical payment foundations for the
post-acceptance flow:

- `ACCEPTED_AWAITING_PAYMENT -> CONFIRMED`
- backend-only authoritative pricing in integer paise
- deterministic payment attempts
- pre-checkout availability validation
- paid-only contact and chat unlock
- transactional SLOT/RANGE capacity claiming at confirmation time
- captured-payment compensation via refund-required outcomes
- shared callable/webhook/reconciliation finalization helpers

No production canonical callable was exported in this block.

### Canonical Payment States

Implemented payment-state contract:

- `NOT_STARTED`
- `ORDER_CREATING`
- `ORDER_CREATED`
- `CHECKOUT_OPENED`
- `CAPTURE_REPORTED`
- `CONFIRMING`
- `CONFIRMED`
- `CAPTURED_REQUIRES_RECONCILIATION`
- `FAILED`
- `EXPIRED`
- `REFUND_REQUIRED`
- `REFUND_PENDING`
- `REFUNDED`

These are intentionally separate from booking state.

### Payment Attempt Schema

Canonical payment attempts are designed under:

- `bookings/{bookingId}/paymentAttempts/{paymentAttemptId}`

Implemented fields include:

- `paymentAttemptId`
- `bookingId`
- `parentId`
- `providerId`
- `razorpayOrderId`
- `razorpayPaymentId`
- `amountPaise`
- `currency`
- `couponId`
- `couponClaimId`
- `pricingHash`
- `availabilityHash`
- `state`
- `orderExpiresAt`
- `captureReportedAt`
- `confirmedAt`
- `refundRequiredAt`
- `lastReconciledAt`
- `verificationSource`
- `failureCode`
- `failureMessage`
- `retryCount`
- `pricingSnapshot`
- `couponSnapshot`

### Pricing Rules

Pricing stays authoritative on the backend:

- currency: `INR`
- money unit: integer paise
- Pettxo commission: `15%` of original service subtotal
- provider payout: `85%` of original service subtotal
- Pettxo-funded coupons do not reduce provider payout
- refunds are based on `customerPaidPaise`, not service subtotal

Worked examples:

- `₹1,000` normal booking
  - service subtotal: `100000`
  - customer paid: `100000`
  - provider payout: `85000`
  - Pettxo commission: `15000`

- `₹1,000` booking with `₹300` Pettxo coupon
  - service subtotal: `100000`
  - coupon discount: `30000`
  - customer paid: `70000`
  - provider payout: `85000`
  - Pettxo coupon funding: `30000`
  - Pettxo net before gateway: `-15000`

- `100%` coupon
  - service subtotal: `25000`
  - customer paid: `0`
  - provider payout: `21250`
  - Pettxo commission: `3750`

- three-slot booking
  - subtotal is the sum of all selected slot unit prices
  - payout and commission are still derived from the full original subtotal

### Capacity Strategy

Capacity is still never reserved during:

- `REQUESTED`
- `PENDING_PROVIDER`
- `ACCEPTED_AWAITING_PAYMENT`

Block 4 prepares authoritative claim documents only at paid confirmation:

- SLOT occupancy path: `services/{serviceId}/slotOccupancy/{slotId}`
- RANGE occupancy path: `services/{serviceId}/occupancy/{dateKey}`

Each claim is deterministic by booking ID to prevent double increments on replay.

Current MVP range limit:

- maximum `30` nights in canonical transactional occupancy claiming

### Paid-Only Private Data

Canonical paid-only private contact storage is prepared at:

- `bookingPrivate/{bookingId}`

Stored fields include:

- `fullParentName`
- `phoneNumber`
- `serviceAddress`
- `latitude`
- `longitude`
- `parentOtpCode`
- `providerOtpHash`
- `contactUnlockedAt`

Public canonical booking documents continue to exclude private contact fields.

### Chat Unlock

Canonical booking chat unlock metadata is prepared at:

- `bookingChats/{bookingId}`

Unlock is tied to:

- booking state `CONFIRMED`
- `lifecycle.paidAt != null`

Direct social chat behavior remains untouched in this block.

### Rules and Indexes

This block adds source-only, additive rules/index definitions for:

- `paymentAttempts`
- `bookingPrivate`
- `bookingChats`
- `services/{serviceId}/slotOccupancy/{slotId}`
- `services/{serviceId}/occupancy/{dateKey}`

No deployment occurred in this block.
