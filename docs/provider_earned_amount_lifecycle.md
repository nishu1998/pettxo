# Canonical provider earned amount lifecycle

## A. Previous earnings model

Payment confirmation wrote the expected provider share into `providerEarnings.amountPaise` before service completion. Completion wrote that amount again while the review window was still open. Cancellation and no-show handlers wrote compensation/reversal fields without replacing `amountPaise`, so a cancelled booking could continue exposing the original share as earned. Dispute resolution already assigned its final provider allocation, but the projection did not distinguish that final amount from provisional earnings. Its `status` field mostly described payout readiness/payment.

Audited sources and their meanings:

| Source | Financial meaning |
| --- | --- |
| `booking.financials.providerPayoutPaise` | Canonical expected service entitlement at payment confirmation; dispute resolution can replace it with the final allocation |
| `bookingFinancials.providerAmountPaise` | Booking financial snapshot/projection; completion and dispute writers update it |
| Cancellation decision, `bookingCancellations.providerCompensationPaise`, `bookingFinancialAdjustments.providerCompensationPaise` | Policy-determined cancellation compensation; adjustments retain the original earning/reversal for audit |
| `bookingNoShows.providerCompensationPaise` and no-show allocation | Current supported no-show policy entitlement |
| Dispute outcome/resolution `providerFinalEntitlementPaise` | Explicit final entitlement decided by the dispute allocation |
| `providerPayouts.providerEntitlementPaise` | Payout accounting entitlement; not proof of earned finality, and some constructors depend on payout status |
| `providerPayouts.priorPaidPaise`, `remainingPayablePaise` | Amount already transferred and still payable, not earned amount |
| `manualSettlementObligations.amountPaise` | A payable/refundable obligation, potentially the remaining amount rather than the total earned |
| `bookingFinancialLedger` | Captures, refunds, payouts and adjustments; raw amounts cannot all be summed as provider earnings |
| `payoutReadiness` and legacy `providerEarnings.status` | Operational payout readiness/hold/payment, not earnings finality |

Backend payout/dispute calculations do not consume `providerEarnings.amountPaise` as their allocation input. The Flutter record reads this field directly, with a fallback to legacy rupee amounts. Keeping the field while correcting its semantics is compatible with that reader; no Flutter code was changed.

## B. Canonical definition

Reuse **`providerFinalEntitlementPaise`** for the final provider entitlement in `providerEarnings/{bookingId}`. **`amountPaise` is its public projection: final entitlement, or zero when no final entitlement exists yet.** No separate `providerEarnedAmountPaise` alias was added.

The projection also stores:

- `providerProvisionalEntitlementPaise`: the current expected or allocated entitlement supplied by the authoritative lifecycle handler.
- `earningsStatus`: `PROVISIONAL`, `HELD`, `FINALIZED`, or `ADJUSTED`.
- `earningsOutcome`: the financial outcome that supplied the amount.
- `earningsSchemaVersion: 1`: identifies documents written under this contract.

`providerFinalEntitlementPaise: null` means not finalized. `providerFinalEntitlementPaise: 0` means a finalized zero entitlement. These are deliberately different. A hold can preserve a previously finalized amount while its consequences are reviewed.

## C. Lifecycle rules

| Actual booking/outcome | Earned projection |
| --- | --- |
| `CONFIRMED` | `PROVISIONAL`; expected provider share retained separately; final entitlement null and `amountPaise = 0` |
| `IN_PROGRESS` | Remains provisional; starting service does not finalize earnings |
| `COMPLETED_PENDING_REVIEW` | Provisional through the review/dispute window |
| `COMPLETED_FINAL`, ordinary completion | `FINALIZED`; final entitlement equals the canonical service provider share |
| `CANCELLED`, customer cancellation | `FINALIZED`; replace the original share with the exact cancellation compensation |
| `CANCELLED`, provider cancellation | `FINALIZED`; current policy compensation is zero |
| `NO_SHOW` | `FINALIZED` from the existing terminal no-show allocation; payout may remain held during the 24-hour dispute window |
| Open completion dispute | `HELD`; preserve provisional entitlement and keep the unfinalized amount at zero |
| Resolved dispute | `ADJUSTED`; assign the resolution's `providerFinalEntitlementPaise`, including zero/custom/full allocations |
| Excess-payment refund | No change to any earnings field |
| Canonical cancellation/no-show/dispute refund | Preserve the outcome's allocated earned amount; returning customer money does not recompute provider compensation |
| Other canonical refund | `HELD` for allocation review; preserve an explicitly known final entitlement, otherwise keep it null and retain the provisional amount separately |

Normal economics remain subtotal minus commission: a ₹1,000 service earns ₹850 after final completion. A ₹200 or ₹1,000 Pettxo-funded coupon does not reduce that normal-completion entitlement.

Existing customer cancellation bands are unchanged:

| Time before service start | Provider compensation percentage |
| --- | --- |
| More than 24 hours | 0% |
| 12 through 24 hours | 15% |
| 6 through less than 12 hours | 35% |
| 2 through less than 6 hours | 60% |
| Less than 2 hours, before start | 85% |

Those percentages use the current policy's remaining refundable customer-paid basis and caps—not a newly introduced subtotal calculation. Cancellation at/after service start or after OTP entry remains restricted by existing policy. No commission or cancellation percentage was changed.

The supported no-show implementation is the generic `OTP_NOT_ENTERED_BY_SERVICE_END` outcome. It retains the canonical provider share, including Pettxo-funded coupon support. There are no separate customer-fault/provider-fault no-show allocation branches to test or change; this task does not invent them.

An unexplained full or partial canonical refund is not itself an entitlement decision. Current rules provide allocation decisions through cancellation and dispute flows. The implementation therefore flags an unexplained refund for review instead of inventing a zero entitlement or silently finalizing provisional earnings. Partial refunds are detected even when payment status remains `CONFIRMED` but a refund identity is present.

## D. ProviderEarnings projection

`buildProviderEarningsProjectionV3` constructs the same validated fields for all outcome writers. It rejects negative, fractional, unsafe or non-finite paise values. Each existing lifecycle transaction assigns the projection on the deterministic booking document:

- Payment finalization: provisional expected share.
- Provider completion and automatic completion reconciliation: provisional completion-review share.
- Review-window finalization: normal final share, or an unresolved-refund hold.
- Cancellation: actual policy compensation.
- No-show: actual supported no-show compensation.
- Dispute opening/resolution: held provisional/final allocated outcome as appropriate.
- Ordinary canonical refunds: read the current projection in the refund transaction and preserve allocation-based earnings or add an unresolved-refund hold.

Existing booking/payment records, ledger writes and payout operations retain their own contracts. The Flutter screen will not need to reconstruct the earned amount from compensation, reversals, refund state or payout records.

## E. Payout separation

Legacy `status`, `eligibleAt`, `paidAt`, payout transaction references and obligation states remain payout metadata. `earningsStatus` and the final amount are separate. Missing bank details can produce `status: HELD` with `earningsStatus: FINALIZED` and ₹850 earned. Both manual payout recording and the existing payout processor preserve that earned amount when moving to `PAID`; they do not subtract or zero it.

## F. Idempotency and consistency

Amounts are assigned from authoritative outcomes, never incremented. Existing transactions and terminal-event replay guards remain in place. Repeated cancellation persistence, no-show finalization, completion finalization, dispute resolution, refund processing and reconciliation leave one amount on one document. The previous excess-refund isolation and stale-payment guards remain intact.

The completion reconciliation regression exposed a production-relevant date issue: completion writes a Firestore `Timestamp`, but review-window finalization called `getTime()` directly. Finalization now normalizes that timestamp through the existing date helper. `UNDER_REVIEW` disputes also block finalization alongside `OPEN` disputes.

## G. Tests added and updated

**43 additional test cases** cover:

- Nine single-slot/multi-slot/range completion combinations with no, partial and full Pettxo-funded discounts; ₹1,000 always finalizes to ₹850.
- All customer cancellation bands and their boundary assignments, replacing a stale original amount and retrying persistence.
- Provider cancellation's finalized zero amount.
- Customer/provider dispute wins, custom percentage, custom amount, zero allocation and an explicit full allocation above the standard share.
- Canonical/excess refunds against normal completion, cancellation, no-show and dispute outcomes; replay preserves the final amount.
- Payment reconciliation producing one provisional earning, and completion reconciliation reaching one final earning after Firestore timestamp normalization.
- Full/partial canonical refund holds and under-review dispute protection.
- Rejection of invalid entitlement amounts.

Existing tests were strengthened for completion's provisional amount, open disputes, single/multi-day no-show assignment and replay, and both manual and processor payout preservation. Existing pricing, coupon, service-start, cancellation-policy, refund-isolation, settlement and real-emulator concurrency/rollback tests remain covered by the full run.

## H. Validation results

- TypeScript build: **passed**.
- Full backend suite against a fresh local Firestore emulator: **529 tests, 528 passed, 1 failed, 0 skipped**.
- All **43 additional cases passed**.
- Remaining failure: the previously known “Explore viewer context queries blocks and mutes by ownerUserId only” assertion at `functions/test/firestoreRulesBlockMuteProtections.test.js:29`. This is unrelated to financial logic and was failing before this task.
- `git diff --check`: passed.
- No separate lint command is configured in `functions/package.json`.

No deployment or production data modification was performed.

## I. Files changed

Backend:

1. `functions/src/booking/application/providerEarningsV3.ts` (new contract and projection helpers)
2. `functions/src/booking/application/paymentOrchestrationV3.ts`
3. `functions/src/booking/application/serviceCompletionOrchestrationV3.ts`
4. `functions/src/booking/application/cancellationOrchestrationV3.ts`
5. `functions/src/booking/application/serviceStartOrchestrationV3.ts`
6. `functions/src/booking/application/financialSettlementV3.ts`
7. `functions/src/booking/application/paymentRefundsV3.ts`

Tests/documentation:

8. `functions/test/providerEarningsLifecycleV3.test.js` (new)
9. `functions/test/bookingCompletionV3.test.js`
10. `functions/test/bookingCancellationV3.test.js`
11. `functions/test/bookingServiceStartV3.test.js`
12. `functions/test/bookingFinancialSettlementV3.test.js`
13. `functions/test/bookingManualSettlementOperationsV3.test.js`
14. `docs/provider_earned_amount_lifecycle.md`

The pre-existing `pubspec.yaml` build-number edit is unchanged and excluded from this work.

## J. Historical data risk

Historical documents can still contain the original amount after customer/provider cancellation, compensation-only no-show writes, or an unfinalized/open-dispute booking. Resolved disputes may already have the correct numeric amount but lack explicit earnings lifecycle metadata. Paid records must not be reconstructed from their now-zero remaining payable amount. Records corrupted by old duplicate-refund handling also require separate investigation.

A later audited backfill can use booking state/lifecycle, canonical payment identity, immutable pricing context, cancellation records and financial adjustments, no-show allocation records, and the authoritative dispute resolution/final entitlement. Payout transfers and obligations provide supporting audit evidence, not the earnings definition. A generic refund without a supported allocation requires manual review rather than guessing from refund totals. Reconciliation may need to repair a stale projection even when a historical terminal handler correctly returns an idempotent no-op.

No historical scan, migration or backfill was implemented or executed.

## K. Remaining work

Explicitly deferred: historical earnings reconciliation, lifetime aggregation, removal of the 120-record query limit, the Provider Earnings Flutter screen, and UI status presentation. Automatic payouts, RazorpayX settings and admin payout UI remain outside this task. Unallocated canonical refunds remain flagged for an authoritative allocation decision under existing operations.

## L. Conclusion

**Yes—for supported booking outcomes processed by the updated handlers.** Each booking has one explicit final entitlement and a directly usable `amountPaise` projection, with provisional amounts and holds identified separately. Cancellation/no-show/dispute outcomes replace stale expectations, retries cannot add earnings twice, excess refunds cannot change earnings, and payout status does not define the amount. Historical documents still require the separately planned backfill; an unexplained refund deliberately does not invent a new final entitlement.
