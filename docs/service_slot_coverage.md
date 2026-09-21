# Rolling service slot coverage

## Contract

Customers can select the service's IST calendar date today through today + 30,
**inclusive**. The backend materializes through today + 31, inclusive, providing
one midnight of reserve. `SERVICE_BOOKING_HORIZON_DAYS` and the Dart calendar
constant are checked for equality by `serviceSlotCoverage.test.js`.

`buildServiceSlotCandidates` reuses `serviceScheduling.ts`. IDs, scheduling modes,
capacity defaults, weekday conventions, and the generation-time one-hour lead
threshold retain the previous behavior. Flutter's existing 150-minute request
runway remains unchanged.

## Persistence and safety

`ensureServiceSlotCoverage` defaults to additive coverage. Every chunk rereads the
service, reads deterministic slot IDs and creates missing documents with a
transactional `create` (exists=false precondition). Existing slots are not written.
An existing slotOccupancy document or booking reference on a missing ID blocks its
recreation. Occupied windows under different IDs block overlapping replacements.
Booking documents, slotOccupancy, range occupancy, claims, and financial documents
are never written by the coverage code.

Only `syncServiceSlots` requests schedule reconciliation. It reads the current
service instead of trusting a potentially stale event payload. It may delete
obsolete **future, unreferenced** slots, with service, slot, occupancy and booking
reads inside a transaction. Any slot/range occupancy document, non-generation status, nonzero/invalid acceptedCount,
or current/future booking reference protects a slot, including pending and
cancelled booking references. Invalid schedules leave the last valid slots intact.
No remaining field of a protected slot is changed.

`createBookingRequestV3` now rereads service/selected slots within its request
transaction. An edit and a request therefore serialize on their common reads.
A retained booked slot whose old capacity/window no longer matches the current
service cannot receive a new request; its existing booking is unaffected.
Existing idempotent request replay bypasses this new-request guard.

## Bounded worker

- Gen 2 function: `replenishServiceSlots`, region `asia-south1`.
- Every 60 minutes, timeout 540 seconds, 512 MiB, maxInstances 1, retryCount 3.
- Active services are queried in document-ID order, 10 per page, at most 100 per
  invocation, with the existing visibility/deletion/pause/status gates applied.
- Persistent cursor and a ten-minute transactional lease are stored at
  `_maintenance/serviceSlotCoverage`. This is server-owned maintenance state.
- Seven-minute scan budget; coverage stops starting chunks after 7.5 minutes.
- A failed service is logged and the cursor advances so it cannot starve others.
  It is revisited on the next scan cycle. A crash before checkpoint may repeat work;
  create-only persistence makes that safe. A timeout leaves the lease to expire.
- Slots are created at most 50 per transaction. Reconciliation pages future slots
  50 at a time. No historical slot collection is rewritten.

Monitor `cycleComplete` and cursor progress: all eligible services must be scanned
within the reserve day. Hourly repeated scans also incur reads of existing slots;
this is a bounded implementation, not a zero-read incremental watermark system.

## Fail-closed conditions

For safe handling of current and legacy booking references, each transaction reads
at most 501 service bookings. More than 500 bookings causes
`booking_protection_limit_exceeded`, **not** an assumption of no occupancy.
Unrecognized nonhistorical booking schedules similarly require review.
Overlap checks read at most 301 neighboring slot documents; more than 300 causes
`overlap_protection_limit_exceeded`. Very dense or inconsistent legacy schedules
may need a separately reviewed scalable reference index before automatic recovery.
These limits must not be removed by simply truncating the protected references.

A service change mid-run aborts remaining chunks (`service_changed_retry_required`).
The retrying service-write trigger or next scheduler pass uses current data.
Successfully created earlier chunks remain legitimate records; reconciliation
protects any that have since been referenced by a booking.

## Logs

`service-slot-coverage` reports service ID, coverage dates, candidate/existing/
created/skipped/protected counts, unbooked deletions and eligibility/invalid-schedule
reasons. `service-slot-coverage-failed` additionally reports a sanitized error code.
`service-slot-coverage-pass` reports scanned/eligible/replenished services, created
slots, failures, cursor, completion and elapsed time. No customer/provider details
or booking claim contents are logged.

## Rollout — NOT executed

Run from the repository root only after approving production rollout:

1. Build and deploy the transactional request guard **before** enabling safe
   reconciliation. This order closes the preexisting in-flight-request race:

   ```sh
   npm --prefix functions run build
   firebase deploy --project pettexo-d9409 --only functions:createBookingRequestV3
   ```

2. Deploy the safe service trigger and additive scheduler together:

   ```sh
   firebase deploy --project pettexo-d9409 --only functions:syncServiceSlots,functions:replenishServiceSlots
   ```

3. The hourly job restores expired eligible services without a separate migration.
   To start a controlled pass immediately (up to 100 active services):

   ```sh
   gcloud scheduler jobs run firebase-schedule-replenishServiceSlots-asia-south1 --location=asia-south1 --project=pettexo-d9409
   ```

   If more services remain, repeat only after the prior lease/run completes, until
   the logs show `cycleComplete: true`. A currently leased job safely skips.

4. Inspect coverage logs and compare scheduling-only snapshots of existing slots,
   referenced bookings and slotOccupancy before/after. Verify the previously expired
   service IDs gVwxrZoNq0gdoHOouOwM, a5plL0LZD3hJhXyLk59f and eFrXTGxANnm3vY0W5tCO.
   Investigate every protection-limit/unknown-schema error instead of resetting data.
5. Test current-date, day-30, continuous and multi-day requests. Recheck occupied
   slots and capacity rejection. Deploy the Flutter build for consistent IST date
   selection on devices outside India; the 30-day customer horizon is unchanged.
6. Monitor failed services, scan duration/cycle completion and read volume.

No new Firestore composite index is needed: new queries use a single filtered field
and/or document ID order. The existing dateKey/startAt client index remains required.

## Rollback

Pause the new scheduled job:

```sh
gcloud scheduler jobs pause firebase-schedule-replenishServiceSlots-asia-south1 --location=asia-south1 --project=pettexo-d9409
```

Pause does not cancel an already running invocation; it can finish create-only
chunks. Leave all newly created legitimate slots, bookings and occupancy intact.
Keep the safe trigger and transaction guard. **Do not redeploy the old destructive
regenerator as a rollback.** A code rollback must retain their preservation checks.
The Flutter date helper can be rolled back independently; backend data needs no
rollback or deletion. Fix any worker issue before resuming its scheduler job.

## Local validation (2026-09-14 IST)

- `npm --prefix functions run build`: passed.
- With a freshly started Firestore emulator on localhost:8085:
  `FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 node --test functions/test/*.test.js`
  completed 646 tests: 645 passed, 1 failed, 0 skipped. This includes all 42 new
  candidate/coverage/emulator tests and 8 existing service-scheduling tests passing,
  along with booking v3, occupancy/capacity, payment race and multi-day regressions.
- The sole failure is the existing source-text assertion
  `Explore viewer context queries blocks and mutes by ownerUserId only` in
  `firestoreRulesBlockMuteProtections.test.js`. Reproduced using the test, rules and
  Explore repository copied directly from untouched HEAD: 2 passed, the same 1 failed.
  No Explore or rules changes were made.
- Social-create tests use fixed IDs and do not clear their database on cleanup;
  rerunning the full suite on a dirty emulator can produce unrelated update-denied
  failures. The final counts above are from a fresh emulator.
- Flutter: 24 passed, 0 failed:

  ```sh
  flutter test --no-pub test/core/utils/service_duration_test.dart test/features/bookings/domain/booking_v3_models_test.dart test/features/bookings/domain/booking_runway_test.dart test/features/bookings/domain/service_booking_horizon_test.dart test/features/bookings/presentation/slot_selection_screen_test.dart
  ```

- Affected Flutter code and new tests: no analyzer issues:

  ```sh
  flutter analyze --no-pub lib/features/bookings/presentation/screens/slot_selection_screen.dart lib/features/bookings/domain/utils/service_booking_horizon.dart test/features/bookings/domain/service_booking_horizon_test.dart test/features/bookings/presentation/slot_selection_screen_test.dart
  ```

- `git diff --check`: passed. The pre-existing pubspec version edit is untouched.
- No deployment, production mutation, commit or push was performed.
