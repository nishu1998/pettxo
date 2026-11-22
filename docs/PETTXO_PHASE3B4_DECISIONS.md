# Pettxo Phase 3B-4: owner decisions for blocking activation

**Recorded:** 22 November 2026, from the owner's answers to the open questions in `~/PettxoReleaseBackups/reports/PHASE3B4_DESIGN.md`.
**Scope:** user blocking activation (Phase 3B-4a to 3B-4d). These decisions bind the implementation. Any change needs a new owner decision recorded here.

## Earlier decisions (17 Nov 2026), restated

| ID | Decision |
|---|---|
| **D1** | **Payment captured for an already-blocked pair.** Record the payment and acknowledge the Razorpay webhook so it stops retrying. Flag it for Super Admin. Never confirm the booking. No automatic refund. *(Scope narrowed by answer 1 below.)* |
| **D2** | **Historical "protected" marks expire** when the real obligation ends, judged from live booking state. They never act as a permanent ban on blocking. |
| **D3** | **Malformed or old-format records** each get a Super Admin decision, recorded separately. The original records are never changed. Activation is allowed only when every flagged record has a decision. |
| **D4** | **A pending Pettxo→provider settlement does not prevent blocking.** |
| Attestation | The owner attests that no real-user bookings, payments, disputes or refunds exist. **This attestation replaces the production historical audit.** |

## Earlier decisions (22 Nov 2026), restated

- **Activation tool:** a **local script** run by the owner with their own owner login through `gcloud auth application-default login`. The owner revokes the login afterwards (`gcloud auth application-default revoke`).
- **Not used:** new accounts, service accounts, and **new Cloud Functions**. Only existing functions may be updated.
- **No Storage Rules changes.** The chat-media block rule stays out. Chat-image blocks are enforced in Cloud Functions.

## Answers to the design's open questions (22 Nov 2026)

1. **PAYMENT_EXPIRED + blocked pair.** **Keep the existing automatic refund.** D1's "no automatic refund / hold" applies **only to captures that would confirm a booking**.
2. **D4 scope confirmed.**
   - **No longer protect a pair:** provider payouts (`booking.payout.status`, `payoutReadiness`, `PROVIDER_PAYOUT` manual settlement obligations).
   - **Still protect:** customer refunds (`payment.status` `refund_*`, `refunds/{bookingId}`, `CUSTOMER_REFUND` obligations), and disputes.
3. **D1 hold, booking state.** The booking is **left in its current state**, and normal expiry applies. There is no immediate cancel.
4. **D1 hold, customer notice.** The customer gets a short, neutral notice: *"We received your payment. It's being reviewed and our team will contact you."*
5. **Activation identity.**
   - The owner's email **may** be recorded in the activation audit.
   - The owner's Firebase UID is supplied at activation time.
   - Whether an ADC quota project is needed is decided when activation is first tried.
6. **Quiet window.** Booking schedulers are **not** paused. Activate in a quiet window. If the fingerprint check aborts (`relationship_migration_concurrent_source_change`), simply re-run.
7. **D3 vocabulary approved:** `NO_OBLIGATION | PROTECT_PAIR | BLOCK_ACTIVATION`. Malformed `userBlocks` documents are **left as is**. They stay enforced by their document ID.
8. **Super Admin payment-hold UI** comes later, on the admin dashboard backlog. Until then, holds are visible in the Firebase console.
9. **`functions/scripts/reset_test_data.js` is retired** (deleted), together with its `reset-test-data` npm script.

## Related

- Design: `~/PettxoReleaseBackups/reports/PHASE3B4_DESIGN.md`
- Deployment history: `docs/PETTXO_PHASE3C_PRODUCTION_DEPLOYMENT_RECORD.md`
