# Test-booking flag: backend contract (step 1)

Decisions: `docs/PETTXO_TEST_BOOKING_FLAG_DECISIONS.md` (approach B).

Code:
- `functions/src/admin/bookingTestFlag.ts` (logic);
- `functions/src/admin/bookingTestFlagFunctions.ts` (callable).

Tests:
- `functions/test/adminBookingTestFlag.test.js` (unit);
- `functions/test/adminBookingTestFlagEmulator.test.js` (emulator);
- `firebase_rules_tests/firestore.rules.test.mjs` (the "test-booking flag" test).

## Data

`bookingTestFlags/{bookingId}`: a document exists = test booking; no document = real.

| Field | Value |
|---|---|
| `bookingId` | same as the document id |
| `source` | `"admin"` (single mode) or `"backfill"` |
| `markedAt` | server timestamp |
| `markedByUid` | the Super Admin who marked it |
| `backfillLogId` | backfill only: the `adminAuditLogs` id of the summary row |

The reason is stored only in `adminAuditLogs`.

**Rules:** readable by an active Super Admin only. That means `isAdmin()` plus all of these:
- `adminRole == "superAdmin"`;
- `requesterAccountIsActive()`;
- not `disabled`, `isDisabled` or `adminDisabled`;
- not `isActive == false`.

No client can write. Customer Support, Finance, parents and providers cannot read it.

Not touched: booking documents, the booking schema, booking and payment code, the app, `storage.rules` and indexes.

## Callable `setBookingTestFlagForAdmin`

- `asia-south1` (global options), `invoker: "private"`, active Super Admin only (`requireActiveSuperAdmin`).

### `mode: "single"`
```
{mode: "single", bookingId, isTest: boolean, reason: "3-200 chars, no phone/email", requestId: "[A-Za-z0-9_-]{8,64}"}
→ {mode: "single", bookingId, isTest, changed: boolean, logId: string | null}
```
- **`isTest: true`** creates the flag document. **`isTest: false`** deletes it. The booking must exist.
- **Already in that state:** `changed: false`, `logId: null`, and no log row.
- **Same `requestId` sent again for the same change:** returns `changed: false` with the original `logId`.
- **Same `requestId` for a different change:** `REQUEST_ID_REUSED`.
- **Log row** (in the same transaction, id `bookingTestFlag_<adminUid>_<requestId>`):
  - `type: "booking"`;
  - `action: "booking.test_marked" | "booking.test_unmarked"`;
  - `targetType: "booking"`, `targetId: bookingId`;
  - `before: {isTest}`, `after: {isTest}`;
  - `context: {bookingState}`;
  - `reason`, `requestId`, `source: "setBookingTestFlagForAdmin"`.

### `mode: "backfill"`
```
{mode: "backfill", cutoff: "ISO-8601 with zone", dryRun: boolean,
 expectedTestCount?: number, expectedFingerprint?: "12 hex",   // required when dryRun is false
 reason, requestId}
→ {mode, dryRun, cutoff (UTC ISO), testCount, candidateCount, remainingAfterThisCall,
   alreadyTest, afterCutoff, missingCreatedAt, bookingsScanned,
   earliestCreatedAt, latestCreatedAt, sampleIds (first 20), fingerprint, logId}
```
- **Cutoff limit:** `cutoff` must be no later than **2026-11-23T00:00:00+05:30**, which is hard-coded.
- **Scan:** reads all bookings in pages of 500, ordered by document id; it never writes them.
- **Selection:** bookings with `createdAt < cutoff` and no flag document, sorted by id, at most **450** per call. `remainingAfterThisCall` tells you whether another call is needed.
  - Bookings with no `createdAt` timestamp are counted in `missingCreatedAt` and never selected.
- **Fingerprint:** sha256 of the selected ids, sorted and joined with `\n`; the first 12 hex characters.
- **Dry run:** writes nothing and is not logged (Q3).
- **Apply:**
  - `expectedTestCount` and `expectedFingerprint` must match a fresh scan, otherwise `COUNT_MISMATCH` or `FINGERPRINT_MISMATCH`, and nothing is written.
  - In one transaction it writes the flag documents and **one** log row:
    - id `bookingTestBackfill_<adminUid>_<requestId>`;
    - `type: "booking"`, `action: "booking.test_backfill"`;
    - `targetType: "bookingSet"`, `targetId: fingerprint`;
    - `after: {cutoff, testCount, bookingIds}`;
    - `context: {remainingAfterThisCall, alreadyTest, bookingsScanned}`.
  - If a flag appears between the scan and the transaction, it fails with `FINGERPRINT_MISMATCH`.
- **Re-run:** once everything is marked, a re-run shows `testCount: 0`. An apply of 0 returns `logId: null` and writes nothing.
- **Owner rule (Q8):** apply only if the dry run with cutoff `2026-11-23T00:00:00+05:30` shows `testCount` **115**.

### Error appCodes (in `details.appCode`)

| appCode | HttpsError code |
|---|---|
| `UNAUTHENTICATED` | `unauthenticated` |
| `SESSION_REVOKED` | `unauthenticated` |
| `ROLE_NOT_ALLOWED` | `permission-denied` |
| `ADMIN_NOT_ACTIVE` | `permission-denied` |
| `INVALID_INPUT` (with `details.field`) | `invalid-argument` |
| `REQUEST_ID_REUSED` | `invalid-argument` |
| `BOOKING_NOT_FOUND` | `not-found` |
| `COUNT_MISMATCH` (with `expected`, `actual`) | `failed-precondition` |
| `FINGERPRINT_MISMATCH` | `failed-precondition` |
| `AUDIT_WRITE_FAILED` | `internal` (nothing was changed) |

## Known limits
- **Booking ids in the log.** The backfill row lists booking ids in `after.bookingIds`. `writeAdminLog` refuses any string that looks like a phone number, which means 10 or more digits in a row. An auto-generated booking id is very unlikely to contain one. If one did, the apply would fail with `AUDIT_WRITE_FAILED` and write nothing.
- **Size of the log row.** With 450 ids the row is about 10–15 KB, well under Firestore's 1 MiB document limit.
