# Account-specific Provider Earnings loading audit

## Evidence boundary

The supplied report contains UI errors and an App Check warning, not the
exceptions from either earnings request. No failing/working provider UID,
earnings document snapshots, deployed index status, or deployed enforcement
configuration was supplied. No production data was read or changed. The exact
account-specific failure remains unproven. Do not classify records as legacy/test,
run reconciliation, deploy an index, or change enforcement on this evidence.

## Complete paths inspected before edits

History: ProviderEarningsScreen listens to FirebaseAuth.authStateChanges(), maps
uid, and keys _EarningsContent by uid. The repository queries top-level
providerEarnings where providerId == uid, orderBy createdAt descending, limit120.
Each snapshot maps every document through ProviderEarningRecord.fromDocument /
fromMap. Any parser error fails the snapshot; no documents are silently dropped.
The screen additionally rejects records whose providerId differs from its uid.
Subscription errors clear history and display the generic retry message.

Total: the screen independently calls BookingRepository.getProviderEarningsSummary,
which invokes getProviderLifetimeEarningsV3 in asia-south1 with no payload. The
callable uses request.auth.uid; a requested other provider requires financial-admin
authorization. The Flutter summary parser validates version, currency, integer
fields, provider identity, and timestamp; the screen rejects a mismatched uid.
Failures clear only the total. Auth changes dispose the old screen and subscription;
late results cannot populate the new account's screen.

Backend: getProviderLifetimeEarningsDataV3 uses one read-only transaction for
full-collection count/sum aggregates, not a 120-row list or client sum. It compares
all provider records, version1 records, nonnegative safe-range final entitlements,
null/provisional entitlements, no-earning outcomes, and paid-booking counts. It
sums providerFinalEntitlementPaise independently of payout status. Count mismatch
or an unsafe total throws failed-precondition with details.code
EARNINGS_RECONCILIATION_REQUIRED and logs safe reconciliation counts. It does not
read individual earnings documents, so that error alone cannot name a bad record.

## Account-specific candidates, not conclusions

A versionless earnings record can fail the history parser and the lifetime
version-count check for only its owner. Missing/invalid final amounts also fail
closed. Missing projections/duplicate records can fail the lifetime paid-booking
count check. These are demonstrable source paths, not proof about the live account.

Parser requirements: schemaVersion1, present providerFinalEntitlementPaise
(null allowed for non-final records), recognized earningsStatus, safe integer
amount when present, valid bookingId and providerId. Legacy `amount` is never
financial truth. Optional date fields accept Timestamp/DateTime/parseable String;
unrecognized dates are unavailable. Missing createdAt is excluded by Firestore's
orderBy query; this does not exclude the record from backend aggregate checks.

Rules remain providerId == auth.uid or admin, reads only. The local history index
is already providerId ASC + createdAt DESC. Lifetime indexes already cover
providerId + earningsSchemaVersion, plus providerFinalEntitlementPaise or
earningsOutcome, and bookings providerId + lifecycle.paidAt. Deployment state was
not verified. Do not add duplicate definitions or broaden read access.

Local initialization has no App Check setup. The callable and global options do
not enable enforceAppCheck. Firestore service-level enforcement is not in local
rules. The warning alone cannot distinguish unrelated noise from an enforced
request failure. Working-account warning parity is unknown. No App Check change
was made. CanonicalBookingsQuery is a separate booking path and was untouched.

## Proven local defects fixed

Both retry buttons previously called the shared refresh path: Retry history also
retried total, and Retry total restarted failed history. They now retry only their
own section. Global refresh still refreshes total and restarts failed history.
Valid realtime history stays subscribed.

Useful error context was discarded. Debug-only repository logs now record the
actual Firestore snapshot boundary and callable response boundary. Parser errors
carry document ID and invalid field names, never values. UI account-validation
and subscription errors also have safe diagnostics. Raw exception messages,
Firestore data, service error details, tokens, payment/customer/bank data are
never logged. Firebase codes and the allowlisted reconciliation reason are logged.
Strict financial validation, query limit, and error UI remain unchanged.

## Manual verification / remaining investigation

1. Use a debug build containing these changes. Sign out/in as the failing provider;
   record auth UID and capture ProviderEarningsHistory / ProviderEarningsTotal
   lines when opening the screen. Distinguish repository responseReceived from
   UI summaryReceived (a response can arrive and fail parsing).
2. Repeat on the same app/build/network for a working provider; compare UID,
   Firebase codes, snapshot/response flags, invalid field names and document IDs.
   Note whether the App Check warning occurs for both accounts.
3. If snapshotReceived=true with ProviderEarningFormatException, inspect ONLY
   the identified records via authorized read-only access. Compare canonical
   booking/no-show/cancellation evidence; never infer an amount or rewrite them.
4. If total reports EARNINGS_RECONCILIATION_REQUIRED, inspect its server counts
   and compare the provider's canonical projections against paid bookings. The
   existing bounded reconcileProviderEarningsBatchV3 dry run can propose a repair
   after identity/evidence validation; no dry run or write was executed here.
5. For permission-denied/unauthenticated verify request auth and deployed rules;
   for failed-precondition without reconciliation inspect server missing-index
   diagnostics and deployed index status; verify App Check enforcement/request
   metrics before assigning the warning as cause.
6. Check Total Earned and up-to120 history independently. Trigger a total-only
   failure and Retry total: history must not resubscribe. Trigger a history-only
   failure and Retry history: total must not be called. Global refresh can recover
   both. Neither error should display zero/empty success.
7. Confirm provisional rows show Amount not final yet / Earning pending
   finalization, no payout label, and are excluded from lifetime totals. Positive
   final rows show Earned and separate Eligible/On hold payout labels. Zero-final
   rows retain existing hiding behavior.
8. Switch providers/sign out with requests in flight: old earnings must disappear;
   sign in again and verify both new sources use the new UID.

Only a Flutter release is needed for these diagnostics and retry fixes. Resolving
the real account's data/configuration issue may require a separately evidenced
repair or deployment. No Functions, rules, indexes, financial logic, or production
records were changed by this task. The live root-cause investigation is pending
the requested account IDs and actual request errors.
