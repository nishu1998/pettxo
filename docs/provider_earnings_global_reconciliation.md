# Provider Earnings global reconciliation v2 — review before production use

**NOT DEPLOYED. PRODUCTION DATA NOT MODIFIED.** No production audit/backfill was
invoked. All amounts in tests are synthetic, including the fixture using the
reported provider/document IDs. Production-wide counts require the global dry run.

## Proven failure and historical schema

The supplied runtime proves that provider sSI3muWZg4Ma1z5VNsHaTcFzksF2 received a
successful six-document Firestore snapshot but document A4z2ypododCBhp1GGH8Q lacked
valid earningsSchemaVersion, earningsStatus and providerFinalEntitlementPaise.
The independent lifetime callable returned EARNINGS_RECONCILIATION_REQUIRED.

Git source before commit 831810a shows payment-confirmation projections carrying
bookingId/providerId, amountPaise, totalAmountPaise, source paidBookingCanonical,
status notEligible, schemaVersion3 and timestamps, without the three earnings
fields. `schemaVersion:3` is NOT `earningsSchemaVersion:1`. Older rupee `amount`,
status-only partial projections, missing timestamps and other malformed fields
are also represented in existing historical fixtures; that does not establish
how many production records have each shape. The prior reconciler was introduced
in commit 6df8b35. Neither a legacy amount nor payout readiness is entitlement truth.

## Canonical schema

The Flutter parser requires earningsSchemaVersion1; nonempty bookingId/providerId;
earningsStatus PROVISIONAL/HELD/FINALIZED/ADJUSTED; a present final-entitlement
field which is null or a nonnegative safe integer. FINALIZED/ADJUSTED require a
non-null final amount. HELD may retain a previously finalized entitlement.
PROVISIONAL/null is excluded from Total Earned and displays no fake zero earning.
Final zero remains zero and hidden in history according to existing semantics.

The migration validator additionally requires providerProvisionalEntitlementPaise
(nonnegative safe integer) and valid createdAt/updatedAt timestamps, because current
writers supply them and history orders by createdAt. These extra invariants can
identify records that technically parse but have incomplete history metadata.
Date/Timestamp are accepted server-side. All actual Firestore timestamps persist
as Timestamp. The UI also tolerates optional parseable date strings.

Current projection fields:
- earningsSchemaVersion, bookingId, providerId, earningsStatus,
  providerFinalEntitlementPaise: parser-critical.
- providerProvisionalEntitlementPaise: canonical base/provisional entitlement;
  never substitute it for a null finalized amount.
- amountPaise: compatibility projection of final entitlement, otherwise zero;
  never used as reconstruction authority.
- earningsOutcome: writer outcome (PAYMENT_CONFIRMED, COMPLETION_REVIEW,
  NORMAL_COMPLETION, NO_SHOW, CUSTOMER_CANCELLATION, PROVIDER_CANCELLATION,
  OPEN_DISPUTE, DISPUTE_RESOLUTION, CANONICAL_REFUND_REVIEW,
  NO_EARNING_RECORD_REQUIRED). Not a required Flutter parser field.
- createdAt/updatedAt: history ordering and record metadata. earningsOutcomeAt is
  the explicit outcome-date equivalent; a new finalizedAt field is not required.
- source, currency, userId/serviceId, policyVersion: optional metadata.
- status, eligibleAt, eligibleForPayout, paidAt, payout references: separate payout
  information, never used to calculate entitlement. COMPLETED and NEEDS_ATTENTION
  remain recognizable payout statuses.
- listed price is not an earnings-parser field. Canonical financials persist
  serviceSubtotalPaise/providerPayoutPaise and Pettxo-funded coupon information.
- legacy amount (rupees), schemaVersion, old source/status vocabulary are not
  promoted into financial authority. Existing legacy fields/references are retained;
  the old amount gets legacyAmountDeprecated=true when safely reconstructed.

CANONICAL_VALID means schema/identity/duplicate checks passed, not a fresh
recalculation of already-final financial truth. These records receive zero writes.
An already valid current projection is never overridden by historical sources.
A valid financial core with missing metadata is also left untouched if reconstruction
would change its phase, final amount or known outcome (CANONICAL_FINANCIAL_CONFLICT).

## Writer inventory and fixes

- paymentOrchestrationV3: paid capture creates PROVISIONAL/PAYMENT_CONFIRMED with
  IDs and timestamps. Already complete. Payment replay is idempotent.
- serviceCompletionOrchestrationV3: service completion creates provisional review;
  review-window scheduler finalizes; dispute opening holds. Finalization/dispute
  merge writes previously depended on an existing document for identity/createdAt.
  They now include persisted paid-booking identity and outcome timestamps.
- serviceStartOrchestrationV3: scheduled/reconciled NO_SHOW writes finalized
  compensation. Added history creation/outcome metadata if old projection is absent.
- cancellationOrchestrationV3: customer/provider confirmed cancellation writes
  finalized policy compensation. Added history creation/outcome metadata.
- financialSettlementV3: dispute resolution writes ADJUSTED allocation. Added
  identity and timestamps; payout execution no longer creates a status-only doc.
- paymentRefundsV3: canonical refund execution holds an existing projection and
  preserves known final outcomes. It now skips the earnings metadata write when
  the projection is absent. The refund itself remains recorded; missing history
  remains detectable, not fabricated. Excess refunds remain isolated.
- manualSettlementSyncV3 and bookingManualSettlementOperationsV3: readiness/paid
  metadata updates only affect present earnings data (or an explicit complete
  earnings plan in the same transaction), never create status-only documents.
- providerEarningsBackfillV3: existing historical repair, extended here.
- exported callables/schedulers use these application writers; legacyFunctions
  has no separate current top-level providerEarnings writer in this checkout.

New canonical outcome writers now have complete identity and history metadata.
Metadata-only paths cannot manufacture missing projections. Existing malformed
projections are deliberately left for reconciliation; no writer guesses their
historical financial outcome. Writer metadata changes do not alter allocations.

## Reconstruction authority and precedence

Only bookings marked schemaVersion3, bookingModelVersion3.2, documentFormat
canonical_v3 are eligible reconstruction sources. Unknown booking schemas need
manual review, not automatic schema promotion. Document ID is booking identity;
alternate-key projections, duplicates, conflicting IDs/providers are reported.

| Outcome | Persisted authority | Phase/date |
|---|---|---|
| Confirmed / in progress | booking.financials.providerPayoutPaise + lifecycle.paidAt | PROVISIONAL/PAYMENT_CONFIRMED |
| Completed pending review | same canonical entitlement | PROVISIONAL/COMPLETION_REVIEW |
| Normal final completion | same entitlement + lifecycle.finalizedAt | FINALIZED/NORMAL_COMPLETION |
| NO_SHOW | bookingNoShows.providerCompensationPaise, bounded by persisted base | FINALIZED; noShow.noShowAt or lifecycle.noShowAt |
| Customer/provider cancellation | bookingCancellations and/or bookingFinancialAdjustments.providerCompensationPaise + actorType; supplied sources must agree | FINALIZED; lifecycle.cancelledAt or cancellation.createdAt |
| Resolved dispute | unique bookingDisputeResolutions.providerFinalEntitlementPaise or disputes.resolution.providerFinalEntitlementPaise; allocations must agree | ADJUSTED; resolvedAt evidence |
| Open dispute | only unambiguously pre-final completed-pending-review | HELD/null; paidAt |
| Unallocated processor refund | identified winning payment; final refunded chronology ambiguous => manual review | pre-final HELD/null only |
| Unpaid | no new projection; existing unexpected earnings untouched for review | NO_EARNING_RECORD_REQUIRED / UNSAFE |

Resolved dispute evidence precedes prior terminal outcomes. Conflicting
open/resolved flags, multiple resolutions, missing evidence or mismatched source
identities block reconstruction. No payment percentage is recalculated.
bookingFinancials, manualSettlementObligations, payout balances and old earning
amounts do NOT supply entitlement. providerPayouts/booking.payout supply payout
metadata only. No obligation, refund, ledger, booking or payout is mutated by migration.

## Extended reconciler behaviour

Existing public name: reconcileProviderEarningsBatchV3. Callable remains private;
both dry run and writes require existing financial authorization AND superAdmin.
Normal provider/customer, support admin and finance admin are denied. Firestore
rules remain unchanged and providerEarnings remains client-read-only/scoped.

Input: {scan:'providerEarnings'|'bookings', dryRun:true, limit:10,
cursor?:documentId, ids?:[up to20 IDs]}. Default dryRun=true. Batch limit1..20;
IDs and cursor are mutually exclusive. Explicit IDs may contain up to20 independent
of the paginated limit. There is no provider filter: document-ID pages cover all
providers. An additional bookings scan discovers missing earnings documents that
a providerEarnings-only scan cannot find, and is necessary for lifetime consistency.

Each item runs independently in a transaction reading the booking, projection,
source documents and bounded duplicate/resolution queries before any write.
A typical item reads eight direct documents plus at most two duplicate and two
resolution results; at most two writes per reconstructed item (projection + audit).
20 items bound memory, transaction work and callable response size within the
existing 300-second runtime. Start with limit5 in production; reduce on latency.
The runner requests one page at a time and apply mode cannot run an unattended loop.

Transactions reread current sources and projection on retry. A new valid writer
result is skipped, never overwritten. Deterministic booking-ID projection writes
assign amounts, never increment them. Atomic existing audit records retain safe
previous/expected fields, actor, version2 and timestamp. Projection metadata adds
reconciledAt/earningsReconciliationVersion; replay does not update those fields.
Dry run performs no Firestore writes, including no audit/quarantine-document writes.
Its ordinary platform logs are counters, not Firestore mutations.

Unsafe records remain in place and appear in the bounded admin response/report
with document/booking/provider IDs, reason code, invalid fields and missing source
fields where known. This is report-based quarantine, not destructive relocation.
Use the existing Super Admin booking/dispute inspection and the protected report
for review. No new client read permissions or hidden deletion path is introduced.

History recommendation: retain strict whole-history failure for now. A partial
statement requires an explicit incomplete-state product contract and a clear
separation from unavailable lifetime totals. No automatic filtering or parser
weakening is part of this migration. Unsafe records can still block their owner's
screen/total until separately reviewed; the migration must not conceal them.

## Response and counters

Example structure (illustrative values, NOT production counts):

```json
{
  "migrationVersion": 2, "dryRun": true, "scan": "providerEarnings",
  "counts": {"scanned": 10, "unchanged": 6, "created": 0, "updated": 3, "zeroed": 0, "skipped": 1, "failed": 0},
  "summary": {"canonicalValid": 6, "needsBackfill": 3, "wouldUpdate": 3, "applied": 0,
    "alreadyCorrect": 6, "unsafeToReconstruct": 1, "orphaned": 0, "providerMismatch": 1,
    "bookingMissing": 0, "financialSourceMissing": 0, "errors": 0, "notRequired": 0},
  "breakdown": {"issues": {"MISSING:earningsSchemaVersion": 3},
    "schema": {"VERSION_1": 7, "UNVERSIONED": 3},
    "outcome": {"NORMAL_COMPLETION": 9, "UNKNOWN": 1},
    "reasons": {"PROVIDER_MISMATCH": 1}},
  "items": [], "nextCursor": "last-document-id", "hasMore": true,
  "retryIds": [], "durationMs": 1234
}
```

items is bounded to the batch, not always empty as in this abbreviated example.
- scanned: attempted items. unchanged/canonicalValid/alreadyCorrect: no writes.
- created/updated/zeroed: intended actions in dry run; committed actions in apply.
  zeroed is the compatible amountPaise changing to zero, e.g. provisional final=null;
  it is never an invented finalized zero. needsBackfill is their sum.
- wouldUpdate: safe dry-run actions only. applied: successful real-run actions only.
- skipped: untouched items; unsafeToReconstruct excludes legitimately notRequired
  unpaid bookings. notRequired is useful during the bookings sweep.
- orphaned/bookingMissing: missing deterministic booking source. providerMismatch:
  ownership conflict. financialSourceMissing: unsafe items with missing/invalid
  required reconstruction evidence (including timestamps/schema).
- errors/failed: transaction/infrastructure failures; retryIds must be handled.
- breakdown counts missing/invalid field names, bounded schema/outcome categories,
  and reason codes. nextCursor/hasMore continue deterministic lexicographic scans.
- durationMs: batch elapsed time. Summary subsets overlap; do not add all counters.

## Exact operator commands — DO NOT EXECUTE until approval/deployment

From repository root, after reviewing the working diff and tests:

```sh
npm --prefix functions run build
firebase deploy --project pettexo-d9409 --only functions:reconcileProviderEarningsBatchV3
```

That deploys only the audit/backfill callable. Its private invoker restriction is
preserved. Before real migration, separately release the writer guards in the
reviewed candidate for their affected entry points (not an unrestricted deploy):

```sh
firebase deploy --project pettexo-d9409 --only functions:cancelConfirmedBookingByCustomerV3,functions:cancelConfirmedBookingByProviderV3,functions:finalizeCanonicalNoShowsV3,functions:completeBookingServiceV3,functions:createBookingDisputeV3,functions:finalizeCompletedBookingsV3,functions:resolveBookingDisputeV3,functions:retryProviderPayoutV3,functions:runProviderPayoutProcessingBatchV3,functions:recordManualProviderPayoutV3,functions:materializeManualSettlementObligationsForBookingV3,functions:synchronizeManualSettlementPayoutsV3,functions:razorpayWebhook,functions:reconcileBookingPaymentsV3,functions:verifyBookingStartOtpV3,functions:runBookingFinancialReconciliationV3
```

Shared modules already contain earlier, undeployed session work. Review/package
that dependency diff before approving this release; a function-only deployment
still includes its imported modules. No indexes, rules, Hosting or Flutter release
is needed for this server migration. No change to lifetime callable is needed.

Prerequisites: an IAM principal allowed to invoke this private function, plus a
fresh Firebase Auth ID token for an existing superAdmin in this Firebase project.
Obtain the Firebase token through the trusted admin sign-in session, save it in a
local permission0600 file; NEVER paste tokens into logs/chat or command arguments.
An IAM token alone is not Firebase Super Admin authorization and vice versa.

```sh
RECONCILE_URL="$(gcloud functions describe reconcileProviderEarningsBatchV3 --gen2 --region=asia-south1 --project=pettexo-d9409 --format='value(serviceConfig.uri)')"
# Set MIGRATION_INVOKER_SA to the existing, authorized invoker service account.
gcloud auth print-identity-token --impersonate-service-account="$MIGRATION_INVOKER_SA" --audiences="$RECONCILE_URL" > /secure/earnings-iam-token
chmod 600 /secure/earnings-iam-token /secure/superadmin-firebase-token
node functions/scripts/provider_earnings_reconcile.cjs \
  --url "$RECONCILE_URL" \
  --firebase-token-file /secure/superadmin-firebase-token \
  --iam-token-file /secure/earnings-iam-token \
  --scan providerEarnings --limit 10 --all \
  --checkpoint /secure/earnings-audit-v2.json \
  --report /secure/earnings-audit-v2.jsonl
```

Create the secure directory first; replace /secure paths with an existing private
operator directory. --all is allowed only for dry runs. The runner sends the two
independent credentials using Authorization and X-Serverless-Authorization. It
never writes via Admin SDK or impersonates a Firebase uid in request data.
The existing project IAM policy must allow the chosen invoker; do not make the
callable public to bypass a 403.

Repeat with --scan bookings and NEW checkpoint/report names to discover missing
projections. Aggregate counters and field/reason breakdowns are in the checkpoint's
totals; bounded per-page evidence is streamed to JSONL. Token files are reread
per request. On expiry/network failure refresh tokens and rerun with --resume and
the SAME configuration/files. Failed item IDs are retried before cursor advancement.
Do not count retries as unique inventory: checkpoint totals count attempts; use a
clean final sweep for authoritative inventory totals. Two scans also overlap;
do not sum their earnings counts/amounts.

After review, apply ONLY reviewed IDs in a small batch (new output paths):

```sh
node functions/scripts/provider_earnings_reconcile.cjs \
  --url "$RECONCILE_URL" \
  --firebase-token-file /secure/superadmin-firebase-token \
  --iam-token-file /secure/earnings-iam-token \
  --scan providerEarnings --ids REVIEWED_ID_1,REVIEWED_ID_2 --apply \
  --checkpoint /secure/earnings-canary-v2.json \
  --report /secure/earnings-canary-v2.jsonl
```

Do not substitute the known failing ID until its dry-run sources are proven safe.
For controlled subsequent pages use --scan providerEarnings --limit 5 --apply and
new output paths, then --resume per approved batch.
Never use --all with --apply. Handle missing projection IDs from the bookings
scan using --scan bookings. Repeated reviewed IDs are safe, not double counted.

## Rollout / recovery

1. Approve reviewed code; deploy reconciler and writer guards as above.
2. Run both global dry-run sweeps. Zero Firestore writes.
3. Review totals, every unsafe/error category, and bounded evidence. Stop for
   unexplained allocations/identity conflicts; no automatic manual-review repair.
4. Apply a reviewed canary of1–5 IDs, then inspect safe audit and projection data.
5. Verify history parsing and lifetime total for canary providers. Some providers
   need more than one safe repair before their lifetime count becomes consistent.
6. Continue controlled batches, resolving retryIds. Never automatically process
   unsafe items. Concurrent new documents before a cursor may be seen only by the
   mandatory final fresh sweeps; pagination isn't a frozen global snapshot.
7. Run fresh global dry runs from the beginning. wouldUpdate must be0 for safe
   records; unsafe records remain explicit, not counted as repaired.
8. Verify the known provider and representative previously healthy providers.

Each item is atomic: an audit failure rolls back its projection, other committed
items remain committed. Timeout/unknown response may have committed some items;
rerun the same IDs/page. Transactions and deterministic IDs make replay safe.
A checkpoint is saved atomically after its report; a crash between the two may
repeat a report/page but cannot duplicate financial entitlement. A lock prevents
two runners using one checkpoint; remove a stale .lock only after verifying the
old process is stopped. Keep protected reports/checkpoints outside source control.

Recovery preference is forward reconciliation from current sources. Never bulk
restore old amount fields/audit snapshots over newer financial decisions. Audits
retain safe previous/expected fields, not payout credentials. Any exceptional
rollback requires per-document source review and update-time preconditions; code
rollback alone does not undo already-repaired data. Stop the runner immediately
if unexplained results appear; no automatic rollback is provided.

## Known provider verification after eventual approved migration

For sSI3muWZg4Ma1z5VNsHaTcFzksF2, inspect the bounded report for
A4z2ypododCBhp1GGH8Q AND its other earnings/missing booking projections. Confirm
source certainty, earningsSchemaVersion1, phase, null-or-final entitlement,
provider/booking identities, createdAt and update/audit metadata. No amount is
inferred from the supplied screenshot or missing-field report.

Sign in as this provider, open Provider Earnings: the snapshot must parse; lifetime
callable must succeed if all its history/paid-booking counts are consistent. Check
provisional exclusion, finalized Earned, separate payout labels, zero hiding,
retry independence, account switching and a previously healthy provider. An unsafe
record may legitimately keep EARNINGS_RECONCILIATION_REQUIRED; escalate its reason
rather than weakening validation. Confirm lifetime entitlement counts each booking
once and is not limited to the120-row history. Another provider cannot read these
records. No production verification has yet been performed.

## Changed-file manifest for this task

Existing worktree changes from earlier tasks are retained. This migration changes:

- functions/src/booking/application/providerEarningsBackfillV3.ts — extend existing
  reconciler with schema/source checks, no-touch valid records, report counters,
  safe ownership handling, continuation metadata, and v2 audit metadata.
- functions/src/booking/application/providerEarningsSchemaV3.ts — bounded field-only
  schema issue classifier and reconstructed-output validation.
- functions/src/booking/application/providerEarningsV3.ts — identity/date metadata
  helper for current outcome writers; no arithmetic changes.
- functions/src/booking/application/cancellationOrchestrationV3.ts — complete
  cancellation earnings metadata when materializing a missing projection.
- functions/src/booking/application/serviceStartOrchestrationV3.ts — same for NO_SHOW.
- functions/src/booking/application/serviceCompletionOrchestrationV3.ts — same for
  completion finalization and dispute-open projection.
- functions/src/booking/application/financialSettlementV3.ts — same for dispute
  resolution; prevent payout status update from creating a partial projection.
- functions/src/booking/application/paymentRefundsV3.ts — existing-projection guard.
- functions/src/booking/application/manualSettlementSyncV3.ts — metadata-only guard.
- functions/src/booking/bookingManualSettlementOperationsV3.ts — payout metadata guard.
- functions/scripts/provider_earnings_reconcile.cjs — private callable runner,
  dry-run paging, explicit apply batches, credentials from files, checkpoints,
  output locking, retry IDs, and aggregate counters.
- functions/test/providerEarningsBackfillV3.test.js — global schema, source,
  no-write/ownership, missing-field, fixture, idempotency and pagination cases.
- functions/test/providerEarningsBackfillEmulatorV3.test.js — transaction/audit,
  concurrent rerun and staged stale-read/retry cases.
- functions/test/providerLifetimeEarningsV3.test.js — canonical source fixtures and
  ownership-conflict expectations; preserves reconciliation-required behaviour.
- functions/test/providerEarningsRunner.test.js — mocked-transport runner safety,
  pagination and exact-ID resume tests (no network requests).
- functions/test/providerEarningsLifecycleV3.test.js — provisional writer invariant
  and refund-with-missing-projection protection.
- functions/test/helpers/assertCanonicalEarning.js — common live-writer invariants.
- functions/test/bookingServiceStartV3.test.js — actual NO_SHOW writer invariant.
- functions/test/bookingCompletionV3.test.js — actual completion writer invariant.
- functions/test/bookingCancellationV3.test.js — cancellation writer invariant.
- functions/test/bookingFinancialSettlementV3.test.js — actual dispute writer invariant.
- functions/test/fixtures/reconciled_provider_earning.json — shared synthetic repair
  output verified against the backend preview and strict Flutter parser.
- test/features/bookings/data/reconciled_provider_earning_test.dart — consumes that
  fixture with the unchanged production parser; no Flutter application code changes.
- docs/provider_earnings_global_reconciliation.md — audit, commands, counters,
  source map, security, rollout and recovery plan.

## Validation commands and results

All commands below were local validation, not production operations.

```sh
npm --prefix functions run build
node --test functions/test/providerEarningsRunner.test.js functions/test/providerEarningsBackfillV3.test.js functions/test/providerEarningsLifecycleV3.test.js functions/test/bookingServiceStartV3.test.js functions/test/bookingCompletionV3.test.js functions/test/bookingCancellationV3.test.js functions/test/bookingCancellationPolicyV3.test.js functions/test/bookingFinancialSettlementV3.test.js functions/test/bookingManualSettlementOperationsV3.test.js functions/test/manualSettlementOutcomesV3.test.js functions/test/bookingRefundIsolationV3.test.js
```

TypeScript build passed. Unit/transaction-harness run:251 tests,249 passed,0 failed,
2 skipped emulator-only cases from the manual-settlement suite.

```sh
PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH firebase emulators:exec --only firestore --project demo-pettxo-phase1 --config /tmp/pettxo-phase1-emulators.json 'cd /Users/nishantgautam/development/pettexo/functions && node --test test/providerEarningsBackfillEmulatorV3.test.js test/providerLifetimeEarningsV3.test.js test/bookingRefundIsolationEmulator.test.js'
```

Local Firestore emulator:33 passed,0 failed,0 skipped. Includes full-history1000-record
total, repair/replay feeding total exactly once, cross-provider/admin authorization,
refund isolation, atomic rollback, concurrent reruns, and staged stale-read retry.
The staged-retry test models a stale read followed by a real Firestore transaction
against the newer valid record; it does not claim to force a pessimistic transaction
conflict from inside its own locked callback.

```sh
flutter test --no-pub test/features/bookings/data/reconciled_provider_earning_test.dart test/features/bookings/data/provider_earnings_diagnostics_test.dart test/features/bookings/data/provider_earnings_summary_test.dart test/features/bookings/presentation/provider_earnings_screen_test.dart test/features/bookings/presentation/provider_earnings_presentation_test.dart
```

Flutter strict parser and earnings regressions:47 passed,0 failed.
`git diff --check` passed. Production reads, invocations, deployment and backfill
execution were not performed.
