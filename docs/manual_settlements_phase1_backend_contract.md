# Manual Settlements — Phase 1 backend contract

Scope: main Pettxo backend only. The separate Admin Dashboard has not been modified. No deployment or historical repair is part of this change.

## Authorization and money

Every callable below requires Firebase Authentication and `adminRole: superAdmin`. Finance Admin and Support Admin cannot list, reveal, materialize, or execute through these endpoints. Callables retain their existing private invoker configuration.

Amounts are integer paise. The UI must not calculate entitlements or submit an editable amount. Dates exposed by list/detail are ISO-8601 strings or null. Empty optional identifier fields in `obligation` are empty strings; list summaries often use null instead.

Sources (exact): `NORMAL_COMPLETION`, `DISPUTE_RESOLUTION`, `CUSTOMER_CANCELLATION`, `PROVIDER_CANCELLATION`, `NO_SHOW`. Unknown stored sources fail with `failed-precondition`; they are not reclassified as normal completion.

Obligation statuses (exact): `READY`, `HELD`, `PROCESSING`, `COMPLETED`, `NEEDS_ATTENTION`, `CANCELLED`.

Types: `PROVIDER_PAYOUT`, `CUSTOMER_REFUND`. Recipients: `PROVIDER`, `CUSTOMER`.

`financialSettlementStatus`: `NONE`, `PENDING`, `PARTIALLY_COMPLETED`, `COMPLETED`. This is distinct from obligation status.

## Identity and lifecycle

- Provider: `provider_payout_{bookingId}` for all mutually exclusive booking outcomes.
- Cancellation customer refund: `customer_refund_cancellation_{bookingId}` for either cancellation actor.
- Dispute customer refund: `customer_refund_resolution_{bookingId}` (existing convention).
- Refund instruction: `refunds/{bookingId}` for the authoritative booking capture.
- Excess refunds retain `refunds/excess_{sha256(paymentId)}` and separate refund-event identities. They are not manual settlement obligations.
- Multi-day schedules use the root booking ID, never segment IDs.

Cancellation allocation is unchanged: >24h 95/0; 12–24h 75/15; 6–12h 50/35; 2–6h 25/60; <2h 0/85 (refund/provider percentages). Calculations use remaining customer-paid money and integer floor rounding. Existing exact boundary and cancellation cutoff rules remain unchanged. Provider cancellation refunds 100% of the remaining customer-paid money with zero provider compensation.

No-show entitlement remains the canonical listed-price provider share. Eligibility starts at the existing service-end-plus-24-hour deadline. Missing payout details and disputes keep positive obligations visible as HELD. Cancellation provider compensation is also held while its customer refund is pending.

New obligations carry `settlementSyncVersion: 1`; the 15-minute scheduler refreshes existing version-1 provider obligations in READY/HELD. It does not scan terminal bookings to discover historical missing obligations. Completed, processing, and needs-attention records are not reopened. Conflicting completed/in-flight money requires review.

## listManualSettlementObligationsV3

Request (all optional):

```ts
{
  limit?: number; // default 20, clamped 1..50
  cursor?: string;
  status?: string; // omit for all statuses
  obligationType?: "PROVIDER_PAYOUT" | "CUSTOMER_REFUND";
  recipientType?: "PROVIDER" | "CUSTOMER";
  source?: Source;
  recipientUserId?: string;
  search?: string; // exact booking ID or exact obligation ID, not free text
}
```

Response:

```ts
{
  items: Array<{
    obligationId: string; bookingId: string;
    disputeId: string | null; disputeResolutionId: string | null;
    recipientUserId: string; recipientDisplayName: string;
    recipientType: "PROVIDER" | "CUSTOMER";
    obligationType: "PROVIDER_PAYOUT" | "CUSTOMER_REFUND";
    amountPaise: number; currency: string; source: Source;
    executionMode: "MANUAL"; status: Status;
    createdAt: string | null; readyAt: string | null; completedAt: string | null;
    reasonCode: string | null; holdReason: string | null;
    payoutMethodSummary: PayoutMethodSummary | null;
  }>;
  nextCursor: string | null;
}
```

Recipient display name is a **top-level `recipientDisplayName`**, not a nested recipient object. Search by booking ID checks all three canonical obligation IDs. Results are ordered by descending createdAt. Type/source/recipient filters are applied after query scanning; the pre-existing bounded-pagination limitations are not redesigned in Phase 1. A READY filter excludes HELD obligations; the UI should make this explicit.

## getManualSettlementObligationV3

Request: `{ obligationId: string }`.

Response is nested; do not flatten or assume top-level amount/type/status:

```ts
{
  obligation: {
    obligationId: string; bookingId: string;
    disputeId: string; disputeResolutionId: string;
    recipientType: "PROVIDER" | "CUSTOMER";
    obligationType: "PROVIDER_PAYOUT" | "CUSTOMER_REFUND";
    recipientUserId: string; amountPaise: number; currency: string;
    source: Source; status: Status; executionMode: "MANUAL";
    financialSettlementStatus: FinancialSettlementStatus;
    reasonCode: string; holdReason: string;
    relatedPayoutId: string; relatedRefundId: string;
    paymentAttemptId: string; razorpayOrderId: string; razorpayPaymentId: string;
    createdAt: string | null; updatedAt: string | null;
    readyAt: string | null; completedAt: string | null;
    completedByAdminUid: string;
    metadata: Record<string, unknown>;
  };
  booking: {
    bookingId: string; serviceId: string; providerId: string; parentId: string;
    bookingType: string; state: string; serviceTitle: string;
    cancellation: null | {
      cancelledAt: string | null; cancelledBy: string | null;
      cancelReasonCode: string; cancelReasonText: string;
      hoursBeforeServiceAtCancel: number | null;
      refundBand: string; refundBasisPoints: number | null;
      refundAmountPaise: number; providerCompensationPaise: number;
      pettxoRetainedPaise: number; cancellationType: string | null;
    };
  };
  recipient: { userId: string; type: "PROVIDER" | "CUSTOMER"; displayName: string };
  financials: {
    customerPaidPaise: number; serviceSubtotalPaise: number;
    pettxoCouponFundingPaise: number; platformCommissionPaise: number;
    canonicalProviderBasePaise: number; canonicalProviderEntitlementPaise: number;
    finalProviderPayablePaise: number; pettxoRetainedPaise: number;
    customerRefundPaise: number;
  };
  dispute: null | {
    disputeId: string | null; resolutionId: string | null;
    resolutionType: string | null; financialSettlementStatus: FinancialSettlementStatus;
    customerRefundAllocationPaise: number; providerFinalEntitlementPaise: number;
    pettxoFinalRetainedPaise: number; resolutionNotes: string | null;
  };
  payout: {
    status: string | null; holdReason: string | null;
    payoutReadinessStatus: string | null; manualSettlementStatus: string | null;
    payoutMethodSummary: PayoutMethodSummary | null;
  };
  refund: null | {
    refundId: string; state: string | null; executionMode: string | null;
    origin: string | null; razorpayOrderId: string | null;
    razorpayPaymentId: string | null; paymentAttemptId: string | null;
    razorpayRefundId: string | null; manualRefundStatus: string | null;
  };
}
```

`financials.canonicalProviderBasePaise` is the original pricing share. On cancellation it is not the final compensation. Use `canonicalProviderEntitlementPaise`, and use `obligation.amountPaise` for the action. `financials.customerRefundPaise` is the related refund allocation/instruction; it is not necessarily the outstanding action amount. Use `obligation.amountPaise` and status for that purpose.

Cancellation refund metadata includes timingBand. Recording evidence lives in obligation.metadata (`razorpayRefundId`, `manualReference`, `manualAdminNote`, `recordedByAdminUid`, `proofStoragePath`), not in a top-level executionRecord. Provider evidence uses `manualTransactionReference`, `manualSettlementMethod`, `manualAdminNote`, `proofStoragePath`, `completedByAdminRole`.

PayoutMethodSummary is nullable and contains the exact existing safe fields:

```ts
{
  preferredPayoutMethod: string | null;
  status: string | null;
  hasBankAccount: boolean; hasUpi: boolean;
  accountNumberMasked: string | null;
  upiIdMasked: string | null;
  bankName: string | null;
  accountHolderName: string | null;
  accountType: string | null;
}
```

## revealManualSettlementProviderDestinationV3

Request: `{ obligationId: string }`.

Requires a provider payout obligation that is not COMPLETED/CANCELLED. Provider identity is derived from the obligation; no arbitrary provider ID is accepted.

BANK response (method enum is BANK_ACCOUNT):

```ts
{
  obligationId: string; bookingId: string; providerId: string;
  payoutMethod: "BANK_ACCOUNT"; preferredPayoutMethod: "BANK_ACCOUNT";
  bankAccount: {
    accountHolderName: string; bankName: string; accountType: string;
    accountNumber: string; ifscCode: string;
  };
  upi: null;
}
```

UPI response:

```ts
{
  obligationId: string; bookingId: string; providerId: string;
  payoutMethod: "UPI"; preferredPayoutMethod: "UPI";
  bankAccount: null;
  upi: { upiId: string };
}
```

Sensitive fields are nested and only the selected method is returned.

## recordManualProviderPayoutV3

Request:

```ts
{
  obligationId: string;
  transactionReference: string; // required, nonempty
  paymentMethod?: string;
  adminNote?: string;
  proofStoragePath?: string;
}
```

Response: `{ok:true, code:"RECORDED"|"ALREADY_COMPLETED", obligationId:string, bookingId:string, payoutId:string, idempotentReplay:boolean}`.

Requires canonical provider obligation identity, provider recipient, positive amount, matching source/currency, READY status, current final outstanding entitlement equal to obligation amount, eligible payment/profile/deadline/refund/dispute state, and no in-flight payout. Replays of completed records accept compatible evidence; conflicting references fail. Completion is recorded atomically. This callable records an externally executed payment; it does not send money.

## recordManualCustomerRefundV3

Request:

```ts
{
  obligationId: string;
  razorpayRefundId?: string; // REQUIRED for cancellation sources
  reference?: string;
  adminNote?: string;
  proofStoragePath?: string;
}
```

Response: `{ok:true, code:"RECORDED"|"ALREADY_PROCESSING"|"ALREADY_COMPLETED", obligationId:string, bookingId:string, refundId?:string, idempotentReplay:boolean}`.

Cancellation sources require a matching MANUAL cancellation instruction, parent/payment identity, matching origin/reason/source/currency, exact outstanding amount, READY status, and a nonempty Razorpay refund ID. Existing processing/completed records replay only with the same refund ID. NEEDS_ATTENTION requires evidence reconciliation before a new recording. Required/submitted/processing instructions do not count as completed money.

Existing dispute recording retains its prior validation and READY/PROCESSING/NEEDS_ATTENTION acceptance. Do not treat those dispute rules as permission to retry a cancellation refund with new evidence.

Recording returns PROCESSING, not COMPLETED, and never invokes the refund gateway. The verified processor webhook confirms matching funding identity/refund ID/amount, caps cumulative returned money, and completes the obligation. Failed evidence becomes NEEDS_ATTENTION; delayed events cannot reopen a completed refund. Cancellation confirmation creates no dispute documents and does not change provider final entitlement. An arbitrary free-text reference alone cannot prove a processor refund completed.

## materializeManualSettlementObligationsForBookingV3

Request: `{ bookingId: string }`.

Response:

```ts
{
  ok: true;
  code: "MATERIALIZED" | "SYNCHRONIZED";
  bookingId: string;
  obligationId: string | null; // provider first, otherwise customer
  obligationIds: string[];
}
```

This is an explicit Super Admin synchronization action, not a screen-load side effect. It detects final completion/no-show/cancellation/dispute outcome, derives final outstanding money, creates missing obligations, refreshes READY/HELD, and preserves protected records. Unsupported/nonfinal outcomes, conflicting final earnings, or increased entitlement against a completed payout fail closed. It must not be invoked as an unreviewed historical backfill.

## Storage additions

No new collection or index is required. Added sources and fields:

- Obligations: source values above, `executionMode: MANUAL`, `settlementSyncVersion: 1`, cancellation reason/timing metadata.
- Cancellation refund instruction: `executionMode: MANUAL`, source-specific `origin`, `refundEntitlementPaise`, `refundedBeforeCancellationPaise`, cumulative `refundedAmountPaise`, manual evidence/status fields.
- Provider payout: source, MANUAL mode, final entitlement and outstanding money; existing identity retained.
- Confirmation: deterministic paymentRefunds event and CUSTOMER_REFUND ledger evidence, cumulative attempt refund totals, cancellation refund status.

NO HISTORICAL BACKFILL PERFORMED

NOT DEPLOYED

## Validation and changed files

- TypeScript build: passed.
- Focused booking, cancellation, service-start/no-show, financial/manual settlement, payment/refund, earnings, and export regression run: 466 passed, 0 failed, 8 emulator-dependent tests skipped.
- Dedicated local Firestore emulator run: 26 passed, 0 failed. Includes concurrent refund confirmation, concurrent payout recording, atomic cancellation creation, and no-show HELD-to-READY synchronization. Uses Java 21 and demo projects only.
- Broader backend run: 626 passed, 5 failed, 54 skipped. One failure is the unchanged Explore viewer-context source assertion in firestoreRulesBlockMuteProtections.test.js; four are firestoreRulesSocialPostCreateEmulator.test.js tests requiring an emulator in that non-emulator run. None is a settlement test failure.
- git diff --check: passed.

Files changed by this task (other pre-existing workspace changes were retained):

```text
functions/src/booking/application/cancellationOrchestrationV3.ts
functions/src/booking/application/financialSettlementV3.ts
functions/src/booking/application/manualCancellationRefundV3.ts
functions/src/booking/application/manualSettlementSyncV3.ts
functions/src/booking/application/manualSettlementTypesV3.ts
functions/src/booking/application/paymentRefundsV3.ts
functions/src/booking/application/serviceStartOrchestrationV3.ts
functions/src/booking/bookingFunctions.ts
functions/src/booking/bookingManualSettlementOperationsV3.ts
functions/src/booking/bookingManualSettlementSchedulerV3.ts
functions/src/booking/bookingV3FlowFunctions.ts
functions/test/bookingCancellationPolicyV3.test.js
functions/test/bookingManualSettlementOperationsV3.test.js
functions/test/bookingServiceStartV3.test.js
functions/test/functionExports.test.js
functions/test/manualSettlementOutcomesV3.test.js
docs/manual_settlements_phase1_backend_contract.md
```
