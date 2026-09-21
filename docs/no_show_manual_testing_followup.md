# NO_SHOW financial read audit

## Confirmed code defects and correction

Booking Details previously selected `refunds/{bookingId}.refundAmountPaise`
ahead of `bookingFinancials/{bookingId}.customerRefundPaise`. It also used that
processor record's `state` to label the no-show allocation Refunded. A generic
record containing 190 and processed therefore displayed ₹1.90 Refunded even
when the no-show allocation was zero. The refund model discards origin/scope
and payment identity, so it cannot establish settlement ownership.

The no-show customer view now reads only the customer settlement allocation.
It does not subscribe to generic processor refunds. Zero means No refund;
positive canonical allocation means Refund approved, not proof of execution.
Missing/error data remains unavailable. Completed/dispute and cancellation
views retain their existing separate paths. No Flutter financial arithmetic
or backend financial writes were added. Both no-show Important Information
cards are suppressed; other states retain theirs.

## What cannot yet be established

No affected booking IDs or production record snapshots were supplied. The exact
stored source of the reported 190 and the cause affecting the reported provider
cannot be verified from source alone. The selection defect is reproduced, not
proof of what the live documents contain. A canonical allocation of 190 is NOT
silently replaced with zero by this fix.

## Backend paths inspected

- `finalizeCanonicalNoShowV3` writes customerRefundPaise=0 and FINALIZED/NO_SHOW
  provider earnings from canonical financials.providerPayoutPaise, in the same
  transaction as the terminal booking. Listed-price pricing already accounts
  for Pettxo-funded coupons; no new percentage formula is needed.
- The local manual settlement integration writes payout obligations atomically.
  Entitlement finalization and payout release are separate.
- Flutter's effective state can derive NO_SHOW from elapsed CONFIRMED or
  unstarted IN_PROGRESS before the backend scheduler runs (every 30 minutes).
  Thus a terminal-looking screen does not prove persisted terminal state.
- The finalizer returns ALREADY_FINALIZED for stored NO_SHOW or an existing
  bookingNoShows document. It does not repair historical missing projections.
  The scheduler scans CONFIRMED and IN_PROGRESS, not stored NO_SHOW.
- A valid earnings projection with null providerFinalEntitlementPaise produces
  both Awaiting finalization and Earning pending finalization. Missing documents
  produce only the former; malformed documents cause a read error. The reported
  two labels therefore indicate a parsed, non-final projection in this client.
- Canonical processor refunds can put provisional earnings into
  HELD/CANONICAL_REFUND_REVIEW. Existing finalized NO_SHOW outcomes are preserved.
- `paymentRefundsV3` isolates non-winning capture refunds under
  `refunds/excess_<sha256(paymentId)>`, scope EXCESS; it returns before touching
  canonical booking financials, earnings, and payout readiness. Winning-capture
  refunds use refunds/{bookingId}, scope AUTHORITATIVE. These processor summaries
  are not no-show allocation decisions. Manual cancellation/dispute refunds have
  explicit origins and separate obligation identities.

## Safe investigation and repair path (not executed)

For each supplied booking ID, read bookings, bookingNoShows, bookingFinancials,
providerEarnings, refunds/{id}, payment attempts/refund events, dispute resolution,
providerPayouts and manualSettlementObligations; compare payment identity and
scope, persisted state versus derived state, allocation amounts, and timestamps.
Inspect deployed finalizer version and scheduler errors. Do not infer a provider
share or a refund origin from the number 190 alone.

If persisted NO_SHOW has missing/provisional earnings but an unambiguous canonical
bookingNoShows allocation, preview the existing admin-only
reconcileProviderEarningsBatchV3 with {ids:[bookingId],dryRun:true}. Review the
expected allocation, identities, conflicts and payout state before an explicitly
approved write run. It reconstructs from canonical no-show evidence, logs an audit,
and skips ambiguous evidence. It repairs earnings only, not customer allocations
or missing manual obligations. Review/reconcile those separately through the
existing manual settlement path after source validation.

If customerRefundPaise itself is wrong, investigate its writer/history and real
processor refunds before designing an audited per-booking repair. Do not overwrite
it with zero or rerun terminal finalization blindly. If the state is still stored
CONFIRMED/IN_PROGRESS, diagnose scheduler eligibility/failure rather than treating
it as a historical terminal backfill.

No production read, repair, backfill or deployment was performed. This Flutter
change needs an app release; backend rollout/repair requirements for these real
records remain conditional on the evidence above.
