# Phase 1 lifecycle release boundary and isolation plan

Status: implementation ready for final deployment review; no deployment performed.
This working directory is NOT an isolated deployment candidate.

## Contract and error handling

`continuousSlotDeadlineV3` is shared by creation validation and the lifecycle
resolver. Slots and segments must form one continuous, nonoverlapping package;
identities, durations, bounds, and segment membership must agree. Creation still
performs its existing ownership, pricing, service-date, and runway checks.
One booking retains one OTP, and completion/no-show use its final end. Cancellation
policy and financial formulas are unchanged.

The no-show scan isolates application HttpsError failed-precondition/invalid-argument
validation failures. Numeric, uppercase, hyphenated, and Firebase-prefixed transport
codes for UNAVAILABLE, DEADLINE_EXCEEDED, RESOURCE_EXHAUSTED, ABORTED and INTERNAL
propagate. Native Firestore FAILED_PRECONDITION and unknown errors also propagate.
Both candidate and outer scheduler diagnostics use bounded codes, IDs, and time;
neither prints arbitrary messages, stacks, or exception payloads. An infrastructure
failure prevents the successful-completion log. Document-ID pagination is unchanged.

## Default historical protection

`allowHistoricalRecovery` defaults to false/absent. No exported callable or scheduler
passes true. Missing nested OTP timestamps are not restored from service-start
artifacts during ordinary scheduling, including for bookings with a release marker.
Successful new OTP verification writes nested timestamps normally and does not need
recovery. Existing canonical starts and completion processing continue.

Corrected creation writes `bookingLifecycleReleaseBoundaries/{bookingId}` atomically
with the new booking, and ONLY in the CREATED branch, never on idempotent replay.
The server-only document contains booking/provider/customer identity, policyVersion
`continuous_v1`, and a server timestamp. It is not a date-based heuristic and does
not depend on deployment wall-clock time. The current rules grant no client access
to this collection; no rules changes are required.

A sidecar is intentional: older deployed acceptance/payment handlers can replace a
booking using a parser that discards new top-level fields. Such replacements cannot
erase this creation boundary. No additional acceptance/payment deployments are
needed merely to preserve it.

For a continuous multi-slot no-show that the former resolver would have rejected
(notably a combined segment spanning multiple slots), finalization requires either:
- a matching creation-boundary document, including all three identities; or
- explicit internal Phase 2 `allowHistoricalRecovery: true`.

Unversioned canonical schedules that the former resolver accepted still process.
Single-slot and RANGE no-show behavior is unchanged. The release marker is read in
the same no-show transaction before any writes. Deferred no-shows return NOT_DUE
with no resolved deadline; scheduler reconciliation returns NOOP. This is an
intentional rollout hold, not a new timing/financial policy.

The Phase 2 option is a server-side application parameter, not a client option or
new deployed endpoint. It retains all start evidence, identity, payment, schedule,
conflict, and transaction checks. A future bounded administrative operation must
explicitly opt in for reviewed IDs. No such operation was run or exposed here.

After historical remediation, removal of the guards requires separate review.
Do not blanket-enable historical recovery on a schedule.

## Historical evidence: read-only review, 18 September 2026 IST

The latest check still found 13 provisional records, all without boundary documents.
No production writes or repair calls were made.

| Booking | Default deployment effect |
|---|---|
| CNuYHE89WW9Ar4cstoxl | Remains IN_PROGRESS; missing nested start not recovered |
| FCxsk8oIjX4qvdqZuRNq | Same |
| LsZ8ufgTxSTbkpPUauoW | Same |
| MrvTTUvLHsvxufJNfwco | Same |
| PAaouBrYrszwayAG0BtI | Same |
| W5cXp7yje6GDm1zoFsSv | Same |
| YOfqDzlRFPJHqSzdb8AN | Same |
| fRtM38an4FBWti2mZlj6 | Same |
| jAbF1SL9kqsudE7NjUYm | Same |
| lstcSZY1DYFaJjWCZmmz | Same |
| er8WkA9CFl5v4pYUQ6CZ | Same; gapped schedule also prevents explicit recovery |
| fNM1DXj7y0dXDhSrtlMz | Remains pending review: canonical review deadline missing |
| GV5bKdxMzX0pZ9CMiwU4 | Remains CONFIRMED: new no-show semantics require boundary/opt-in |

None of these progresses solely because this release is deployed. This is not a
freeze on ordinary processing of other canonical bookings or later user actions.
The prematurely recorded completion on fNM and gapped er8 require Phase 2 review.

## Isolated candidate: required construction, not yet deployed

The allowed alternative in this task is a described candidate. No production-based
candidate has been built or certified in this turn. Do NOT deploy this dirty tree,
use Git HEAD as an assumed production baseline, or copy entire changed source files.

1. Read current Gen2 metadata for each of the five targeted exports below. Record
   its deployed revision, build ID, source bucket/object/generation, and dependency
   lockfile. Use the resolved source provenance, not an unpinned latest archive.
   Prior review identified verifybookingstartotpv3-00018-ban,
   finalizecompletedbookingsv3-00017-jak and finalizecanonicalnoshowsv3-00018-qot;
   these historical identifiers must be rechecked before candidate construction.
2. Download those exact deployed source generations into an isolated directory and
   hash them. Different functions can have different baselines: preserve each
   target's deployed dependency graph or review all differences when consolidating.
3. Apply only the lifecycle changes listed below onto verified deployed source.
   Keep the production versions of cancellation/refund/financial/manual settlement
   modules and existing unrelated behavior. No wholesale copy from the workspace.
4. Build and test that exact isolated candidate, including emulator tests. Review
   source/lockfile hashes and a final diff before approving deployment. Workspace
   test success does not substitute for candidate verification.

Allowed runtime changes:
- domain/continuousSlotScheduleV3.ts: shared lifecycle/creation schedule validation.
- domain/slotBooking.ts: invoke that validation before accepting selection.
- domain/lifecycleRolloutV3.ts: durable release boundary and legacy no-show gate.
- application/lifecycleSchedulerErrorsV3.ts: bounded error classification.
- application/serviceStartOrchestrationV3.ts: nested OTP write, shared deadline,
  transactional evidence recovery with default-off guard, protected no-show rollout.
- application/serviceCompletionOrchestrationV3.ts: only nested finalization/payout/
  audit persistence in the normal finalization transaction (from the earlier Phase 1).
- bookingV3FlowFunctions.ts: atomic boundary write in CREATED branch; no-show
  candidate isolation, infrastructure propagation, and safe diagnostics.
- Supporting lifecycle/domain/emulator regression tests and Firestore merge fake.

Explicitly excluded: earlier dotted-key corrections in financialSettlementV3,
canonicalPaymentWebhookV3, bookingManualSettlementOperationsV3; other manual
settlement/cancellation/refund/earnings migration/slot-generation changes; Flutter,
rules, dependency upgrades, and all unrelated exports. Preserve the user's working
copy of all excluded work. The finalization's own nested payout metadata is part
of the required lifecycle fix, not an expansion into payout execution.

## Later deployment commands (NOT executed)

Run from the verified, tested isolated candidate only. Deploy corrected writers
before schedulers; do not rely on multi-function deployment being atomic. Keep the
old entry points quiescent for new test traffic until writer deployment completes.

```sh
firebase deploy --project pettexo-d9409 --only functions:verifyBookingStartOtpV3,functions:completeBookingServiceV3
firebase deploy --project pettexo-d9409 --only functions:createBookingRequestV3
firebase deploy --project pettexo-d9409 --only functions:finalizeCompletedBookingsV3
firebase deploy --project pettexo-d9409 --only functions:finalizeCanonicalNoShowsV3
firebase functions:log --project pettexo-d9409 --only createBookingRequestV3,verifyBookingStartOtpV3,completeBookingServiceV3,finalizeCompletedBookingsV3,finalizeCanonicalNoShowsV3
```

The six dispute/payout/manual/webhook entry points from the previous expanded list
are deferred. No historical recovery switch is enabled by these commands.

Post-release: verify atomic boundary creation for new bookings, no boundary on old
idempotent replays, nested OTP/finalization fields, 24-hour review window, safe
infrastructure failure logs, and unchanged historical records. Recheck the inventory
before Phase 2. Rollback uses the captured per-function production artifacts; code
rollback does not reverse notifications or financial/lifecycle writes. Preserve
boundary documents; do not delete them as part of code rollback.

## Validation completed for the working tree

- TypeScript build: passed.
- Full Firestore emulator suite: 753 tests, 752 passed, 1 failed, 0 skipped.
- The failure remains the pre-existing Explore userBlocks source-contract test;
  neither its source nor test was changed.
- Final log: /tmp/blockers-release-review-emulator.log.
- git diff --check: passed.
- Financial settlement, payment/refund, cancellation, provider earnings, manual
  settlement, and normal completion source files are byte-identical to the
  start-of-this-task snapshot. Earlier Phase 1 changes remain in the working tree.
- 24 additional tests cover transport forms, default-off recovery, durable/identity-
  checked boundaries, canonical legacy continuation, application-vs-native failures,
  actual malformed-candidate isolation, and creation/lifecycle agreement. Existing
  gapped-package acceptance tests now assert rejection under the requested contract.
- Existing emulator coverage still verifies nested OTP/finalization sibling
  preservation, no literal keys, 24-hour review, earnings finality, and replay safety.
