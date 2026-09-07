# Duplicate capture refund isolation — implementation report

## A. Original bug

`routeCanonicalWebhookEventV3` resolved a Razorpay refund's payment ID to a booking and payment attempt, then updated booking-wide payment status, refund amount, cancellation records, payments, invoices, booking financials, provider earnings eligibility, and payout readiness without comparing the refunded payment with the booking's funding payment. Its separate `Promise.all` writes were not atomic. The ordinary path also treated each processed refund as a full refund, regardless of amount.

The four incident regressions were run against a temporary compilation of the original Git HEAD webhook handler: all four failed. Both winner orderings corrupted canonical financial state for confirmed and completed bookings. The same regressions pass against the fixed handler. Temporary baseline code was removed.

## B. Authoritative payment definition

`authoritativePaymentIdV3` reads `bookings/{bookingId}.payment.razorpayPaymentId`. This existing canonical identity is compared with the refund entity's `payment_id`, after resolving and verifying the payment attempt. Neither booking ID nor order ID establishes refund authority. The comparison and all affected financial writes happen in one transaction. No new winning-payment field was introduced.

## C. Refund classification

A matching payment ID uses the existing booking-scoped `refunds/{bookingId}` instruction. A different or not-yet-authoritative payment uses `refunds/excess_{sha256(paymentId)}`. Individual refund facts are recorded in `paymentRefunds/{sha256(paymentId:refundId)}`. Excess refunds update only their own attempt, refund summary, individual refund fact, and `EXCESS_PAYMENT_REFUND` ledger entry. Their ledger type is excluded from canonical customer-refund reconciliation totals. Canonical manual-dispute refunds retain their existing handler, with an additional authoritative-payment guard.

## D. Code changes

- `paymentRefundsV3.ts`: payment authority, deterministic refund identities, refund evidence guard, transactional event application, cumulative accounting, and isolated ledger writes.
- `canonicalPaymentWebhookV3.ts`: use the refund entity's payment identity, reject invalid amounts, delegate ordinary writes to the transaction, and send canonical notifications only for changed authoritative refunds.
- `paymentOrchestrationV3.ts`: scope duplicate instructions, protect completed bookings, reject stale confirmation/compensation writes, preserve existing submission identities, block confirmation after a refund claim, and retry ambiguous submissions with an immutable idempotent request.
- `paymentWebhookEventsV3.ts`: leave refund deliveries retryable when capture mapping has not arrived.
- `razorpayGateway.ts`: preserve pending/processed/failed processor statuses and send `X-Refund-Idempotency`.
- `paymentAttemptDocumentV3.ts`: preserve captured, refunded, net-captured, refund-status, and per-refund history fields.
- `financialSettlementV3.ts`: include the separate excess-refund audit entry type in the ledger contract.

The retry header and unchanged-body requirement follow [Razorpay's idempotent refund API](https://razorpay.com/docs/api/refunds/normal-refunds-idempotent/?preferred-country=IN).

## E. Full versus partial refunds

Only processed refund IDs contribute to `refundedAmountPaise`. `netCapturedAmountPaise` is captured minus processed refunds. `refundStatus` distinguishes `NONE`, `PARTIALLY_REFUNDED`, `REFUNDED`, `REFUND_PENDING`, and `REFUND_FAILED`; aggregate pending/failed status can coexist with a nonzero refunded amount. Duplicate delivery cannot increment totals twice, and cumulative refunds cannot exceed the capture.

An authoritative partial refund keeps the canonical payment identity, records the remaining funding, and holds existing payout readiness without zeroing provider earnings. Only a full refund sets the payment to refunded and cancels payout readiness. Pending and failed events do not count money as returned. Captures that never reached paid confirmation do not create provider earnings projections.

## F. Atomicity and consistency

One Firestore transaction reads the booking, attempt, individual refund fact, and instruction, then atomically writes the attempt, refund records, ledger, and—only when authoritative—the booking and financial projections. Processed events are terminal; delayed created/failed events cannot reverse them. Delayed created events cannot revive failed refunds.

Finalization rechecks current funding identity and refund evidence before committing. Outgoing submission claims mark the attempt refund-pending before contacting Razorpay, preventing a stale confirmation from winning during that gap. Ambiguous transport retries reuse the same stored amount, reason, and idempotency key. Legacy instructions are checked against their payment attempt before submission.

## G. Original incident after the fix

A capture can arrive without being finalized; a retry can produce another capture. Whichever payment is confirmed becomes the booking's canonical payment ID. The other attempt receives its own excess-refund instruction.

| Record | After excess refund processing |
| --- | --- |
| Canonical payment | Still the winning captured payment |
| Duplicate payment | Attempt fully refunded, net captured zero |
| Duplicate refund | Payment-scoped instruction and individual refund fact processed |
| Booking | Confirmed/completed lifecycle preserved |
| Provider entitlement | Existing financial entitlement preserved |
| Provider earnings | Amount, eligibility, and status unchanged |
| Payout readiness | Existing readiness and amount unchanged |
| Audit history | Exactly one excess-refund ledger entry per processed refund ID |

Both A-winning/B-refunded and B-winning/A-refunded cases are covered, including completed bookings.

## H. Tests added

25 unit/integration scenarios cover both winner orderings and lifecycle states, excess pending/failed/processed events, cumulative canonical partial/full refunds, canonical failure, duplicate and out-of-order deliveries, invalid amounts, over-refund rejection, rollback and retry, stale confirmation, a refund before any winner, later winner confirmation, missing capture mapping and redelivery, manual-dispute isolation, outgoing refund claims, immutable gateway retries, gateway status/header handling, and legacy instruction identity.

Three additional local Firestore emulator tests verify concurrent duplicate delivery, concurrent partial-refund accumulation, and rollback after financial writes have been queued. The existing orphan-refund retry test now expects an actually processed full refund to leave the attempt refunded.

## I. Validation results

- TypeScript build: passed.
- New refund regressions: **28 passed, 0 failed** (25 unit/integration, 3 real-emulator).
- Full backend suite with fresh local emulator fixtures: **486 tests; 485 passed, 1 failed; 0 skipped**.
- Remaining failure: existing `functions/test/firestoreRulesBlockMuteProtections.test.js:29`, “Explore viewer context queries blocks and mutes by ownerUserId only.” It is unrelated to the refund changes and existed at the previous checkpoint.
- Previously completed authorization suite revalidated: **76 passed, 0 failed**.
- `git diff --check`: passed. No separate lint script is configured in `functions/package.json`.

The social-post emulator tests reuse fixed document IDs, so the final backend run used fresh local emulator fixtures. No production data was accessed or modified.

## J. Remaining risks and deferred work

- No historical financial repair or migration was performed; records already corrupted by older code need a separate audited repair task.
- Submitted refunds still rely on processor webhooks for completion. Ambiguous submissions retry idempotently; known failed processor refunds are not blindly reissued under new identities.
- Existing manual dispute allocation policy remains separate and unchanged.
- The unrelated Explore assertion remains failing.
- No Provider Earnings UI, totals, commissions, cancellation/dispute policy, automatic payouts, deployment, or production changes were made.

## K. Files changed

Refund implementation and report:

1. `functions/src/booking/application/paymentRefundsV3.ts`
2. `functions/src/booking/application/canonicalPaymentWebhookV3.ts`
3. `functions/src/booking/application/paymentOrchestrationV3.ts`
4. `functions/src/booking/application/paymentWebhookEventsV3.ts`
5. `functions/src/booking/application/razorpayGateway.ts`
6. `functions/src/booking/application/financialSettlementV3.ts`
7. `functions/src/booking/schema/paymentAttemptDocumentV3.ts`
8. `functions/test/bookingRefundIsolationV3.test.js`
9. `functions/test/bookingRefundIsolationEmulator.test.js`
10. `functions/test/bookingPaymentsV3.test.js`
11. `docs/duplicate_refund_isolation_report.md`

Previously completed authorization work is committed separately: `firestore.rules` and `firebase_rules_tests/firestore.rules.test.mjs`. The pre-existing `pubspec.yaml` build-number edit remains unchanged and uncommitted.

## L. Conclusion

**Can refunding an excess/duplicate Razorpay capture now alter the legitimate booking payment or provider entitlement? No, through the corrected ordinary refund and payment reconciliation paths.** The transaction verifies the canonical payment identity and exits the excess branch before any booking/provider financial mutation. Stale capture finalization cannot overwrite refund evidence or a different committed winner. Both winner orderings and real Firestore transaction behavior are covered by passing regressions. This conclusion does not imply that already-corrupted historical records have been repaired.
