# Canonical slot capacity

Provider schedules generate concrete `services/{serviceId}/slots/{slotId}`
documents for the rolling booking horizon. Each slot has a fixed time interval
`[startAt, endAt)`, capacity, and a customer-visible `acceptedCount`.

`services/{serviceId}/slotOccupancy/{slotId}` is the authoritative capacity
ledger. Payment confirmation claims one unit for each selected slot in the
same transaction that confirms the booking. Confirmed cancellation releases
the claim. The slot document's `acceptedCount` is a read projection of
`confirmedUnits`; it is updated in those same transactions so customer
Firestore listeners immediately see a full slot. Clients cannot write either
document under Firestore Rules.

Pending requests and provider-accepted requests awaiting payment do not claim
capacity. This preserves the existing unreserved request policy. Request
creation and payment order creation read current occupancy and reject a slot
whose capacity is already claimed. Confirmation rechecks capacity in its
transaction. A later captured payment that loses a true race follows the
existing refund-required path.

`CONFIRMED`, `IN_PROGRESS`, `COMPLETED_PENDING_REVIEW`, `UNDER_DISPUTE`,
`COMPLETED_FINAL`, and `NO_SHOW` retain the payment claim. Completion and
no-show concern elapsed service intervals, so their retained claim does not
block an unrelated future recurrence. Declined, expired, failed-payment, and
pre-confirmation cancelled requests never claim capacity. A successful
confirmed-booking cancellation releases its claim. Service and slot IDs scope
the ledger, so other providers, services, and dates remain independent.

The production projection predates this change. Run
`python3 functions/scripts/slot_capacity_projection_dry_run.py --project pettexo-d9409`
to list proposed `acceptedCount` corrections. It is read-only. Any backfill
must be reviewed and separately approved before production mutation.
