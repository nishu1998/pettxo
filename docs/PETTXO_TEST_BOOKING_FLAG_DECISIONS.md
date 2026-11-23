# Test-booking flag — owner decisions

Recorded 23 Nov 2026. This replaces handover item 28's **account** flag: user accounts are never flagged. Testers use their real accounts, and their future bookings may be real.

Design basis: `TEST_BOOKING_FLAG_DESIGN.md` (owner reports folder, 23 Nov 2026), sections 0, 4, 5, 9 and 10. Where this record and the design differ, this record wins. In particular, the owner chose **approach B** below instead of the design's booking-field approach.

## Approach B: a separate admin-only list

- **Collection `bookingTestFlags/{bookingId}`.** A document exists = a test booking. No document = a real booking.
- **Purpose: a cleaner admin dashboard only.**
  - Booking documents, the booking schema, booking and payment code, and the app are **never touched**.
  - Nothing in the app changes or is hidden.
  - No full functions deploy and no new indexes are needed.
- **Why not a field on the booking.** Booking lifecycle writes rebuild the whole document from the canonical parser. The parser keeps only the fields it knows, so an unknown `isTest` field would be erased on the next state change (design section 0). A field would also be readable by the booking's customer and provider.
- **Document shape:** `{bookingId, source: "backfill" | "admin", markedAt, markedByUid, backfillLogId?}`.
  - Who and why are also recorded in `adminAuditLogs`.
  - The reason is stored **only** in the log.
- **Access.** Only an active Super Admin can read the collection. No client can write it. The only writer is the callable `setBookingTestFlagForAdmin`.

## Marking

1. **One-time backfill.** Every booking created before the cutoff is marked as test. The owner attested on 22 Nov that all 115 existing production bookings are test data.
2. **New bookings are real by default.** Nothing is written for them.
3. **Later changes.** A Super Admin can mark or unmark a single booking as test, with a reason. Each change is audited.

## Dashboard behaviour (step 2)

- The dashboard **hides test bookings and all their related data on every page by default**: payments, refunds, payouts, disputes, reviews, chats and numbers. List pages have a switch to show them.
- **Exceptions:**
  - **Direct open by id or link.** The booking opens and shows a "Test booking" label.
  - **Money items with money still owed** (Q2). These are shown with a Test chip until settled.
  - **The Team activity log.** It is never filtered.

## Decisions

| # | Question | Decision |
|---|---|---|
| Q1 | Who and why on the booking? | **No.** With approach B the booking is not touched at all. Who is on the flag document (`markedByUid`); why is only in `adminAuditLogs`. |
| Q2 | Money items with money still owed on a test booking | **Shown** with a Test chip until settled. |
| Q3 | Log backfill dry runs? | **No.** Only the apply is logged: one summary row. |
| Q4 | Kill switch for the callable | **None.** Super Admin only. Bulk mode is guarded by the cutoff ceiling plus the count and fingerprint checks. |
| Q5 | Exclude test bookings from app-visible stats | **No.** App stats are unchanged. |
| Q6 | Hide reviews written on test bookings | **Not in the app.** The dashboard may hide them. |
| Q7 | Fix the lifecycle helper that reads outside its transaction | Not needed with approach B: bookings are never written. |
| Q8 | Backfill cutoff | **2026-11-23T00:00:00+05:30.** This is also the hard ceiling in code. Proceed only if the dry run counts **115**. |
| Q9 | "Hide test bookings" switch | **Always starts on "hidden".** It is not remembered. |
| Q10 | Old Customer Support and Finance pages | **Unchanged.** |
| Q11 | Bookings CSV export | Gets a **Test** column. |

## Step plan

1. **Backend (local only).**
   - The `bookingTestFlags` collection.
   - The callable `setBookingTestFlagForAdmin`, with a `single` mode and a `backfill` mode.
   - New `adminAuditLogs` action and target types.
   - One additive `firestore.rules` block.
   - Emulator and rules tests.
2. **Dashboard.**
   - Read `bookingTestFlags`; hide test bookings and their related data by default.
   - Test chip and "Test booking" label.
   - Mark as test / Mark as real with a reason.
   - The backfill dry run and apply screen.
   - Replace or remove the account-level placeholders ("Hide test accounts", "Mark as test account", "Exclude test accounts").
3. **Production.**
   - Deploy `functions:setBookingTestFlagForAdmin`, then `firestore:rules`.
   - Run the Cloud Run invoker step for the new service.
   - Deploy the dashboard.
   - Run the backfill dry run, then the apply, from the dashboard.
