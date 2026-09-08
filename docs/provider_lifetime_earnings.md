# Provider Lifetime Total Earned — implementation report

## A. Previous problem

`ProviderEarningsScreen` calculates its Total card with `earnings.fold<int>(..., item.amountPaise)`. `BookingRepository.watchProviderEarnings` filters by provider ID, orders by `createdAt` descending and defaults to `limit = 120`. Thus the card only totals the returned recent rows. The Total fold has no status filter; separate status cards do. Deleted rows cannot contribute; rows missing the ordered timestamp are omitted; the existing history parser accepts legacy rupee amounts as a fallback. Malformed/legacy projections can therefore distort that old client total. No full-history backend total existed. This audit was completed before implementation.

## B. Architecture chosen

An authenticated callable, `getProviderLifetimeEarningsV3`, executes Firestore server-side count/sum aggregations. There is no materialized summary document. It returns a full-history snapshot and downloads no earning documents to the function or Flutter.

A maintained summary would make reads cheaper at very large scale, but introduce delta bookkeeping across every writer, retry, historical repair and ownership correction. Read-time aggregation avoids that extra financial state and immediately reflects canonical repairs. For histories around 500–1,000 rows, this is a practical tradeoff; the emulator test exercises 1,000. The handler performs six aggregate queries per request, with index work proportional to matching history rather than six constant-cost document reads. Costs and latency should be measured before enabling frequent refreshes for much larger providers. A later materialized design would require independent transactional/idempotency work.

All six reads run in a read-only transaction at one consistent snapshot. They validate total projection count, schema-version count, numeric finalized count/sum, null-final count, obsolete unpaid audit count and paid-booking count. No history query limit or `createdAt` ordering participates. Index definitions accompany the change.

The response is online-only and represents `asOf`, not a live subscription. Network/index/deadline errors propagate; there is no cached-history fallback. Firestore documents describe [server aggregation behavior and limitations](https://firebase.google.com/docs/firestore/query-data/aggregation-queries) and [aggregation read billing](https://firebase.google.com/docs/firestore/pricing).

## C. Exact lifetime definition

For the requested provider, sum `providerFinalEntitlementPaise` in schema-version-1 canonical `providerEarnings` documents. Every included value must be non-negative and within the safe integer range; the resulting sum must also be a safe integer. The validated lifecycle writer remains responsible for per-record integer paise. Neither legacy `amount`, compatibility `amountPaise`, customer payment amounts nor payout balances supply the total.

| Canonical outcome | Contribution |
| --- | --- |
| Normal finalized earning ₹850 | +85000 paise |
| Customer cancellation compensation ₹350 | +35000 paise |
| Provider cancellation | +0; retain the finalized audit/history record |
| No-show | Recorded final canonical allocation |
| Resolved dispute | Final canonical provider allocation |
| Duplicate-payment refund | No change |
| Historical amount correction | Current corrected final amount replaces the old contribution |

Negative recoveries elsewhere are not part of this earned-entitlement field. The canonical writer rejects negative/fractional/unsafe values. Aggregate validation rejects detectable malformed history with `failed-precondition` and details code `EARNINGS_RECONCILIATION_REQUIRED`; it does not silently omit a detected invalid row and return a partial total.

Integrity boundary: counts are defensive checks, not a document-by-document audit or join. Balanced corruption (for example one missing projection plus one extra projection), a stale but valid schema-1 allocation, or multiple manually inserted fractional values whose sum is an integer cannot be conclusively detected by these aggregates. The trusted backend canonical writers and both Step 4 audit scans are prerequisites. Arbitrary Admin SDK edits must not bypass them. This limitation is why historical verification remains required before rollout.

## D. Provisional / held / paid behavior

A null final entitlement contributes nothing, including confirmed/in-progress/review bookings and unresolved held entitlements. `providerProvisionalEntitlementPaise` is never summed. HELD with a non-null final entitlement contributes its full final amount. READY, PROCESSING, PAID and other payout statuses neither include nor exclude amounts: payment to the provider does not undo earning it. Finalized zero remains a counted final record with zero contribution. An obsolete unpaid projection retained by Step 4 has `NO_EARNING_RECORD_REQUIRED`, a null final entitlement and zero compatible amount; it is excluded from the reported provisional count.

## E. Write consistency

There are no aggregate writes, increments or deltas. The total is derived at read time from the canonical projections at one transaction snapshot. Existing lifecycle transactions and Step 4 per-booking repair transactions retain their boundaries. After a correction commits, a later snapshot sees the corrected contribution; repeating the same assignment cannot double count. A concurrent response may legitimately show the earlier snapshot identified by `asOf`.

The count of paid bookings (`lifecycle.paidAt >` Unix epoch) must match canonical projection count minus obsolete unpaid audit records. Common missing/deleted/extra/incorrectly owned projections therefore fail closed. The lifetime operation does not lock or write hundreds of documents: it issues six aggregate reads in a read-only transaction.

## F. Historical backfill

Reuse `reconcileProviderEarningsBatchV3` from Step 4. There is no separate aggregate collection to initialize or rebuild. Reconciling each canonical booking projection immediately updates the next lifetime query.

Follow [the historical reconciliation runbook](provider_earnings_backfill.md): dry-run the projection scan first to identify duplicates/orphans, then the bookings scan to discover missing projections; retain cursors and retry IDs; review anomalies; apply bounded approved repairs. Batches default to 10 and cap at 20, with one transaction per booking and atomic projection/audit writes. Re-run both scans because their pagination is restartable rather than a global historical snapshot. Repeat repairs converge to unchanged results.

Ownership repairs use the existing Step 4 policy. Once the corrected provider ID commits, the next read excludes that record for the old provider and includes it for the correct provider; no transfer of summary counters is necessary. Ambiguous/duplicate cases still require review. No production backfill was run.

## G. Security

The callable requires Firebase Authentication. Omitted provider ID defaults to the authenticated UID. Cross-provider requests use existing `loadAdminActor(..., "financial")`; only financeAdmin or superAdmin can read them. Support admins and ordinary users cannot. Inputs reject invalid provider IDs.

The endpoint declares public transport invocation for Firebase clients, while the handler enforces authentication and authorization. Firebase's callable protocol verifies client Auth tokens; Cloud Run IAM is not a substitute for provider authorization. The installed SDK publishes callable-trigger metadata with the standard callable transport. See [Firebase callable authentication](https://firebase.google.com/docs/functions/callable).

No new collection or client write path exists. Existing owner-read/backend-write providerEarnings rules and the authorization fix remain unchanged. Safe structured logs contain provider ID, counts, amount and version, with no payout credentials or customer payloads. Repair auditability remains in Step 4.

## H. Flutter contract

`BookingRepository.getProviderEarningsSummary()` calls `getProviderLifetimeEarningsV3` separately from `watchProviderEarnings`. The returned `ProviderEarningsSummary` contains `providerId`, `lifetimeEarnedPaise`, final/provisional record counts and `asOf`. The wire contract also fixes `projectionVersion: 1` and `currency: "INR"`. Parsing rejects missing, negative, fractional, non-finite, unsafe or incompatible summary values instead of defaulting to zero.

The repository uses the existing Functions client/region and sends no provider ID for ordinary app reads. Errors propagate for later UI handling. The history stream still defaults to 120 records. The screen is deliberately not wired or redesigned in this task; its existing displayed Total is still the old calculation until Step 6 consumes this new method.

## I. Tests

26 new backend cases cover real emulator count/sum transaction behavior; zero and one-record histories; ₹850+₹500+₹350; 1,000 records totaling 500500 paise; customer/provider cancellation corrections and retries; no-show; final and provisional dispute adjustments; held final amounts; zero records; READY→PAID; duplicate refund ledger independence; legacy amount/timestamp independence; malformed/negative/unsafe values; missing/legacy projections; obsolete unpaid audit records; historical dry-run/apply/repeat; missing projection creation; ownership repair; authorization and callable protocol.

The correction tests exercise assignments using the canonical projection helper; the full suite additionally covers actual lifecycle/refund handlers. Historical integration tests invoke the actual Step 4 reconciler. Scale fixtures are written in batches of at most 400 writes, outside any giant transaction. Integration cases use an isolated `demo-lifetime-*` emulator project and skip without a localhost emulator; the reported full run had no skips.

Flutter adds 10 summary/parser/repository tests. Six existing booking-repository tests were also run.

## J. Validation results

- TypeScript build: passed.
- Lifetime backend tests in the final full run: 26 passed, 0 failed.
- Full backend suite: 604 tests, 603 passed, 1 failed, 0 skipped. Includes Step 3, Step 4, duplicate refunds, cancellation/no-show/disputes, settlement and existing authorization regressions.
- Remaining backend failure is the previously present `firestoreRulesBlockMuteProtections.test.js:29`: “Explore viewer context queries blocks and mutes by ownerUserId only,” a source-pattern assertion unrelated to earnings. The pre-task suite already had this failure.
- New Flutter tests: 10 passed, 0 failed; existing repository tests: 6 passed, 0 failed.
- Full `flutter analyze`: 0 errors, 2 warnings, 4 informational findings, all in unchanged `canonical_booking_detail_screen.dart` and `canonical_booking_qr_payment_screen.dart`. Analyzer exits nonzero for these existing issues; it is not a clean full-app analysis.
- `git diff --check`: passed.
- Emulator verification does not validate deployed index provisioning or production IAM; those require staging verification during rollout.

## K. Files changed

1. `functions/src/booking/application/providerLifetimeEarningsV3.ts` — authenticated, validated snapshot aggregation.
2. `functions/src/booking/providerLifetimeEarningsFunctions.ts` — callable endpoint.
3. `functions/src/booking/bookingFunctions.ts` — endpoint export.
4. `functions/test/providerLifetimeEarningsV3.test.js` — full-history/emulator/security/reconciliation tests.
5. `functions/test/functionExports.test.js` — exported function contract.
6. `firestore.indexes.json` — four aggregation/count composite indexes.
7. `lib/features/bookings/domain/models/provider_earnings_summary.dart` — strict summary model.
8. `lib/features/bookings/data/repositories/booking_repository.dart` — separate summary retrieval.
9. `test/features/bookings/data/provider_earnings_summary_test.dart` — Flutter contract tests.
10. `docs/provider_lifetime_earnings.md` — this audit, implementation report and rollout plan.

The pre-existing `pubspec.yaml` version edit is outside this change and remains uncommitted.

## L. Production rollout plan — not executed

1. Review this change and establish the Step 3/4 canonical writers/reconciler as prerequisites. Verify the endpoint, auth denial cases, indexes and latency in staging with reconciled fixtures.
2. In a future authorized release, deploy only the required indexes and lifetime callable; wait for indexes to become ready. Verify callable access using a real signed-in client, and verify anonymous/cross-provider rejection. Do not enable the UI yet.
3. Through authorized super-admin tooling, run both Step 4 dry-run scans in bounded pages. Archive findings/cursors; investigate duplicate, orphan, malformed and ambiguous cases. Do not use count equality as a replacement for this audit.
4. Apply reviewed projection repairs in small restartable pages, preserving audit records and retry IDs. This is the only backfill required; no aggregate document needs a second migration.
5. Repeat dry-runs, resolve skips/failures, and compare callable totals against independently reviewed canonical history for representative providers, including >120 records, zero/provisional/held/paid states and ownership repairs. Verify repeated calls and repairs remain stable.
6. Monitor reconciliation-required responses, latency and read costs. Then implement Step 6 screen consumption with explicit loading/error/retry/refresh behavior. Stop rollout on unresolved financial discrepancies.

## M. Remaining work

Step 6 still owns screen redesign and replacing the displayed Total with this contract, history pagination UX, loading/error/retry states, record presentation, and date/service/booking labels. Full-app analyzer findings and the unrelated Explore test failure remain outside this financial change.

## N. Conclusion

**Yes, at the implemented backend/data-layer level:** the main app has a separate API to retrieve a full-history lifetime earned snapshot from reconciled canonical projections, independent of the 120-row history query. Detectable incomplete history returns an explicit error. Deployment, historical audit/repair and Step 6 UI consumption remain required before users see the corrected total in production. Nothing was deployed or run against production.
