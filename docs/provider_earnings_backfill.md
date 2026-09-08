# Historical provider earnings reconciliation

## A. Historical risk confirmed

Older projections may retain the original provider share after cancellation, store compensation only in auxiliary fields, reflect a pre-dispute allocation, expose provisional bookings as earned, use rupee-only `amount`, or contain stale identities/statuses. Missing projections are also possible. An alternate document ID can duplicate a booking; a missing/deleted booking can leave an orphan. Payout balance and transfer status cannot reconstruct the earned amount.

## B. Canonical reconstruction source

`reconstructProviderEarningsV3` consumes canonical booking state, provider identity, financials, paid/finalized lifecycle timestamps, and the relevant outcome records. It calls the same `buildProviderEarningsProjectionV3` used by live lifecycle writers; no new commission, cancellation or dispute formula is introduced.

| Outcome | Reconstruction input |
| --- | --- |
| Confirmed/in-progress/pending review | Canonical `financials.providerPayoutPaise`, lifecycle/payment evidence |
| Normal final completion | Canonical provider share plus `lifecycle.finalizedAt` |
| Cancellation | `bookingCancellations/{bookingId}.providerCompensationPaise`; `bookingFinancialAdjustments/{bookingId}` is a fallback/cross-check; actor must agree |
| No-show | `bookingNoShows/{bookingId}.providerCompensationPaise` |
| Resolved dispute | Final entitlement in `bookingDisputeResolutions` or the booking-keyed dispute's embedded resolution; conflicting/multiple resolutions require review |
| Open completion dispute | Canonical expected share, held and unfinalized |
| Canonical refund | Payment identity and refund evidence; preserve cancellation/no-show/dispute allocation; hold an unfinalized booking |
| Excess refund | A different payment ID does not reduce the canonical earning |
| Unpaid request/decline/expiry | No earning record required |

Provider payout documents contribute status/paid timestamps only. Remaining payable and prior transferred amounts never determine earnings. Ledger entries and manual settlement obligations were audited but are not summed or used as allocation substitutes. Payment attempts are unnecessary for the reconcilable cases: missing canonical payment evidence is reported rather than guessed from captures.

The existing projection is used only for comparison, safe audit output and preservation of legacy payout metadata—not for reconstructing earned or provisional amounts.

## C. Reconciliation design

New callable: **`reconcileProviderEarningsBatchV3`**. It uses private invocation configuration and the existing `loadAdminActor(..., "financial")` authorization, followed by an explicit **superAdmin-only** check. Finance/support/ordinary users and unauthenticated requests cannot dry-run or apply.

Inputs:

```json
{
  "scan": "bookings",
  "dryRun": true,
  "limit": 10,
  "cursor": "optional-last-document-id"
}
```

- `scan`: `bookings` or `providerEarnings`; defaults to bookings.
- `dryRun`: defaults to true; only the boolean false enables writes.
- `limit`: defaults to 10, maximum 20.
- `cursor`: exclusive last document ID, used with ascending document-ID ordering.
- `ids`: optional 1–20 explicit source document IDs for review/retry; cannot be combined with a cursor.

The response includes safe current/expected projections, action, classification, anomalies, summary counts (`scanned`, `unchanged`, `created`, `updated`, `zeroed`, `skipped`, `failed`), `nextCursor`, and `retryIds`. Dry-run counts describe planned actions, not applied writes. A null cursor ends that scan. A page containing failed records can still advance; retain and retry its explicit `retryIds`, or replay the page.

Bookings scan discovers missing projections. Projection scan discovers alternate keys, identity conflicts and orphans. Both are necessary for a complete historical audit. Document-ID ordering uses built-in indexes. Duplicate and resolution checks use single-field `bookingId` equality queries capped at two documents. No composite index or index-file change is required; the repository has no exemption removing these indexes.

## D. Projection rules

- Missing reconcilable projection: create one document at `providerEarnings/{bookingId}`.
- Existing correct projection: no writes, including no timestamp-only rewrite.
- Stale amount: assign the canonical amount; never increment/decrement.
- Provider cancellation: retain a finalized zero-entitlement document, as the live lifecycle does.
- Non-final booking: amount zero, final entitlement null, expected share stored separately.
- Open completion dispute: held provisional projection.
- Resolved dispute: final allocation with `ADJUSTED` earnings status.
- Unpaid booking with no projection: skip creation. An existing provably unpaid projection is retained and zeroed with the explicit `NO_EARNING_RECORD_REQUIRED` outcome.
- Unexplained canonical refund on a final booking: skip with `UNALLOCATED_FINAL_REFUND_REQUIRES_REVIEW`. Historical timestamps may not prove whether finalization preceded or followed the refund; the old projection cannot settle that ambiguity.
- Unsupported states, missing required financial evidence, conflicting allocations and ambiguous prior-final disputes: report for review without financial mutation.

Classifications are `NO_EARNING_RECORD_REQUIRED`, `PROVISIONAL_EARNING`, `FINAL_EARNING`, and `HELD_FINAL_OR_PROVISIONAL_EARNING`.

## E. Legacy data handling

- Legacy rupee `amount` remains untouched and receives `legacyAmountDeprecated: true` when present. The canonical integer `amountPaise` is reconstructed from authoritative sources. This preserves compatibility with deployed consumers while identifying the obsolete value.
- Earnings fields follow schema version 1 from the live lifecycle. Payout `status` is normalized to `READY`, `HELD`, `PAID`, `PROCESSING`, `FAILED`, or `CANCELLED`, preferring canonical payout/booking metadata. Changed legacy status is preserved as `legacyPayoutStatus`.
- Existing payment references and other unrelated fields survive merge writes. Canonical payout timestamps are used when available; old payout evidence is not deleted.
- Missing nonessential outcome timestamps are represented as null and reported. Paid/finalization evidence required to establish an earning is not replaced with the current time.
- A wrong provider on the booking-keyed projection is corrected to the booking's provider and reported as a HIGH-severity anomaly. Missing/conflicting canonical identities block repair.
- Alternate-key duplicates, wrong booking mappings, orphan projections and multiple/conflicting dispute resolutions are not deleted or consolidated automatically.
- An alternate-key legacy document with no booking identity cannot be safely associated. Projection-scan anomalies must be investigated before proceeding with materialization for potentially related bookings.

On an actual repair, `earningsReconciliationVersion: 1` and `reconciledAt` identify the writer and time. Already-correct records are not touched just to stamp an inspection; structured logs provide that inspection record.

## F. Safety and atomicity

Each booking is reconstructed inside a Firestore transaction that reads the current booking, outcome documents, projection, payout metadata and bounded duplicate/resolution queries. The projection and a deterministic audit entry commit atomically. A failure cannot leave an unaudited projection update. Concurrent invocations conflict/retry and converge to one projection.

`providerEarningsReconciliationAudit` stores the actor, version, action, canonical outcome, anomalies, safe before/expected projection and timestamp. Audit IDs hash booking identity plus before/expected data. No financial counters, customer payments, payouts, obligations, bookings or ledger balances are changed.

Dry-run performs the same authorization and transactional reads with no database writes, including no audit-document writes. Structured logs contain booking/provider identity, action, previous/new paise amount, outcome, dry-run flag and error category. They do not include bank/UPI credentials, private customer records or raw exception payloads. Per-record transaction failures return generic categories and retry IDs.

Concurrent lifecycle changes are re-read by transaction retries. Pagination is restartable but is not a point-in-time snapshot of the whole database; repeat both scans after repairs to catch records inserted behind an earlier cursor.

## G. Tests added

**46 unit/integration cases** cover correct/missing projections; cancellation compensation and finalized zero; adjustment fallback/conflicts; no-show; resolved and open disputes; provisional states; canonical and excess refunds; legacy rupees/statuses; wrong provider; missing provider/booking/evidence; duplicate projections; unpaid states; dry-run; both scan cursors; explicit retry IDs after commit failure; unchanged second runs; invalid inputs and role authorization; missing timestamps; and reuse of the live projection helper.

**Three real Firestore emulator tests** verify concurrent reruns create one projection/audit, dry-run and duplicate protection perform no repair writes, and an audit failure rolls back the projection before a successful retry.

The function-export contract test is updated for the new callable.

## H. Validation results

- TypeScript build: passed.
- New tests: **49 passed, 0 failed** (46 unit/integration, 3 emulator).
- Full backend suite with fresh local emulator fixtures: **578 total, 577 passed, 1 failed, 0 skipped**.
- Remaining failure is the pre-existing “Explore viewer context queries blocks and mutes by ownerUserId only” assertion at `functions/test/firestoreRulesBlockMuteProtections.test.js:29`.
- The full run includes earned lifecycle, refunds/isolation, cancellation/no-show/dispute, payment/reconciliation and manual settlement tests.
- `git diff --check`: passed. No separate lint script is configured.

No deployment or production reconciliation was performed.

## I. Files changed

1. `functions/src/booking/application/providerEarningsBackfillV3.ts`
2. `functions/src/booking/providerEarningsBackfillFunctions.ts`
3. `functions/src/booking/bookingFunctions.ts`
4. `functions/src/booking/application/providerEarningsV3.ts` — explicit no-earning outcome added to the existing helper contract.
5. `functions/test/providerEarningsBackfillV3.test.js`
6. `functions/test/providerEarningsBackfillEmulatorV3.test.js`
7. `functions/test/functionExports.test.js`
8. `docs/provider_earnings_backfill.md`

The existing `pubspec.yaml` edit remains unchanged and excluded.

## J. Future production execution plan — not executed

1. Review this implementation and the remaining known suite failure. Take the normal financial-data backup/export before approving repairs.
2. Deploy the callable and supporting functions through the normal reviewed release. No new rules/composite indexes are needed. Audit documents use backend-only access under the existing rules.
3. Invoke through authorized private callable tooling using a verified super-admin identity. Run a **projection-scan dry run first** with `{"scan":"providerEarnings","dryRun":true,"limit":5}`. Preserve each response/cursor and continue with the exact returned cursor.
4. Review all orphan, duplicate, wrong-booking and missing-identity anomalies. Do not blindly delete alternate records; establish their canonical relationship first. Resolve these before materializing possibly related missing projections.
5. Dry-run the bookings scan with `{"scan":"bookings","dryRun":true,"limit":5}` and continue its separate cursor chain. Inspect expected allocations, high-severity identity corrections, holds and skipped records. Save failures separately.
6. Choose a small reviewed set and apply explicitly, for example `{"scan":"bookings","ids":["reviewed-booking-id"],"dryRun":false}`. Each apply re-reads current canonical state, so a dry run is not a frozen write plan.
7. Inspect projection and audit records, compare canonical financial outcomes, and rerun the same IDs in dry-run mode expecting `unchanged` and zero planned financial changes.
8. Continue small live pages, retaining the current and next cursor and every `retryIds` list. A response with failures is not a completed migration. Retry only those IDs or replay the preceding page safely.
9. Repeat both full dry-run scans from the beginning. Expect no planned changes for reconcilable records. Skipped anomalies remain outstanding manual-review work and must not be represented as a successful full backfill.
10. Archive responses, audit evidence and unresolved anomaly decisions before considering future aggregation.

No execution script in this task runs a production scan automatically; the callable defaults to dry-run and requires explicit invocation and authorization.

## K. Remaining work

Deferred: lifetime Total Earned aggregation, Provider Earnings Flutter UI, the 120-record history limit, UI error/loading improvements and payout-history UI. Production deployment/execution and manual resolution of ambiguous historical records remain separate reviewed operations.

## L. Conclusion

**Yes, for reconcilable canonical records.** Historical earnings can be assigned deterministically to the live lifecycle definition without incrementing totals, duplicating booking-keyed projections or leaving partial financial/audit writes. Unreconstructable records are reported and left untouched; the tool does not claim to repair ambiguity by trusting stale earnings or payout balances. Production data has not been modified.
