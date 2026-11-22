# Admin item 27: logged contact reveal — owner decisions

Recorded 22 Nov 2026. Scope: **Super Admin only** for now; Customer Support and
Finance later, through the same callables by widening the role set.

Design basis: the item 27 contact-reveal design (owner reports folder,
`admin-audit-refresh-2026-11-22/ITEM27_CONTACT_REVEAL_DESIGN.md`, sections 4,
5 and 8) and the admin audit refresh of the same date. Where the owner's step 1
brief and that design differ from an older draft of the design, the brief wins.
Two additions from the older draft were approved for step 1:

- every new `adminAuditLogs` row also carries `createdAt` (same value as `at`),
  because the dashboard Team log orders and reads rows by `createdAt`;
- a kill switch `_rollouts/adminContactReveal` (`enabled: true` to allow
  reveals). It is **off** until the owner creates the document. `_rollouts` is
  already deny-all in `firestore.rules`, so no rules change is needed for it.

## Decisions

| # | Question | Decision |
|---|---|---|
| Q1 | Is a reason required? | **Always.** Every reveal carries a quick-reason code; `OTHER` also requires free text of 3–200 characters. |
| Q2 | Quick reasons | `CALLBACK_REQUESTED` "Customer asked for a call back" · `BOOKING_PROBLEM` "Booking problem" · `PAYMENT_HOLD` "Payment hold" · `SAFETY_MODERATION` "Safety or moderation" · `PROVIDER_VERIFICATION` "Provider verification" · `OTHER` (requires free text) |
| Q3 | Rate limit | **20 per hour and 100 per day per admin** (rolling windows). No alerts. |
| Q4 | Auto-hide | **30 s** in the dashboard. The reveal callable returns `expiresInSeconds: 30`. |
| Q5 | Email | Email reveals are **logged exactly like phone** reveals. Email is **masked in display**. |
| Q6 | Support tickets | The new Support thread uses the logged reveal (the ticket's typed `contactNumber`). The old Customer Support page is **untouched** for now. |
| Q7 | Hash of the revealed value | **No hash.** The log stores only the masked value. No pepper, no secret. |
| Q8 | Contact search logging | Log a **match count only**: no raw query and no hash. |
| Q9 | Server-side context checks | **booking, support and paymentHold only.** Other context types are accepted with a non-empty id. |
| Q10 | Masked phones on the Bookings list | **No.** |
| Q11 | Team page emails | A separate `listAdminMembersForSuperAdmin` callable for **admin accounts only**. Not a contact reveal, not logged, not rate limited. |
| Q12 | Copy to clipboard | **Allowed and logged**, modelled as a reveal with purpose `copy`. |
| Q13 | Admin read of `bookingPrivate` / `bookingPrivateParticipants` | **Drop later** (step 3), not now. |
| Q14 | Later roles | Customer Support and Finance reuse the same callables via the role set passed to `requireActiveAdmin`. |
| Q15 | Payment-hold screen | A **separate later item**. `paymentHold` is already a reveal context type. |

## Step plan

1. **Backend (this step, local only):** shared admin log writer, active-admin
   guard, contact masking, the four callables (`getMaskedContactsForAdmin`,
   `findUsersByContactForAdmin`, `revealContactForAdmin`,
   `listAdminMembersForSuperAdmin`), masked contact on
   `getCanonicalBookingAdminDetailV3` (fixes item 22), and the additive
   `adminRateLimits` deny-all rules block.
2. **Dashboard:** move every screen off direct `userPrivate` reads and switch
   on the Show / Call / WhatsApp placeholders.
3. **Rules:** remove the admin read of `userPrivate`, `bookingPrivate` and
   `bookingPrivateParticipants` once nothing reads them directly.

Nothing in step 1 is deployed by this change. Deploying needs a targeted
functions deploy, the Cloud Run invoker step for each new function, a
`firestore:rules` deploy and, to allow reveals, the owner creating
`_rollouts/adminContactReveal {enabled: true}`.
