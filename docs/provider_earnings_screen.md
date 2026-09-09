# Settings → Provider Earnings — Step 6 report

## A. Previous screen behavior

Before editing, the screen was audited together with its repository, projection model, Settings entry, named route, loading widget and canonical booking-detail navigation. It recreated its history stream in `build`, folded at most 120 returned rows into Total, and rendered raw payout/source strings. Pending/Eligible/Paid/On Hold cards used legacy status filters. History errors fell through to “No earnings yet.” The model rounded legacy rupee values; the screen omitted dates, grouping and consistently displayed decimal places. Fixed light colors and narrow summary cards also limited theme/responsive support.

The existing named route is `/settings/provider-earnings`; no route replacement was needed. Settings previously described the destination as “Pending, payout-eligible, paid” with a wallet icon.

## B. New screen structure

One primary **Total Earned** card displays the backend value with “Lifetime provider earnings” and the last refresh date. A separate **Earnings History** section says “Recent records · Up to 120 bookings.” Records show the booking reference, friendly outcome, canonical final amount or provisional explanation, friendly status and date. Rows open the existing `CanonicalBookingDetailScreen` and refresh the lifetime snapshot on return.

The old category totals are removed. Settings now uses a receipt icon and “Lifetime earnings and recent bookings.” The screen uses inherited Material theme colors, flexible vertical cards, tappable booking rows and a refresh action with a tooltip. The app's `PettxoLoadingAnimation` is reused with accessible loading labels. No wallet, withdrawal or automatic payment promises are introduced.

## C. Lifetime total wiring

`ProviderEarningsScreen` → `BookingRepository.getProviderEarningsSummary()` → `getProviderLifetimeEarningsV3` from `ea0a742`.

The card exclusively renders `ProviderEarningsSummary.lifetimeEarnedPaise`. There is no fold, percentage calculation or other summation of history rows. History remains a separate live stream. A summary result for a different UID is rejected, rather than displayed after an account change.

The summary is an online snapshot, not a live listener. Pull-to-refresh, the toolbar action, retry and returning from booking detail fetch a new snapshot. Live history changes alone do not trigger repeated callable requests. Thus a new live row may precede the next refreshed lifetime value; the refresh date and action make the snapshot behavior explicit. There is no offline/history-sum fallback.

## D. History record contract

The record model now consumes schema-1 canonical fields directly: `bookingId`, `providerId`, `providerFinalEntitlementPaise`, `earningsStatus`, `earningsOutcome`, payout `status`, `earningsOutcomeAt`, `updatedAt`, and `createdAt`. The final entitlement is the authoritative Step 3 equivalent behind compatible `amountPaise`. It is intentionally preferred over stale legacy amount fields. Null final entitlement means provisional, not a definitive ₹0 earning.

The parser rejects missing schema/final-field/identity, unsupported lifecycle phase and negative, fractional, non-finite or unsafe monetary values. It no longer rounds legacy rupees into financial history. A malformed or unreconciled document produces the history error state rather than a misleading partial list. Existing Step 4 reconciliation is the remedy; no financial reconstruction is performed in Flutter.

There are no new per-row Firestore lookups. Friendly service/customer metadata is not reliably projected, so the screen uses the complete booking reference and a generic outcome label. Missing dates show “Date unavailable.” `earningsOutcomeAt` takes precedence; otherwise `updatedAt` or `createdAt` is explicitly labeled “Updated” or “Recorded.” Live writers do not uniformly expose an earning finalization timestamp, so these fallbacks are not presented as finalization dates. Dates use the app's day/month/year convention in local time.

`formatEarningsPaise` uses integer division, integer remainder and string grouping throughout: `85000 → ₹850.00`, `123456789 → ₹1,234,567.89`. It does not convert stored amounts to floating-point rupees.

## E. Status mapping

Order matters: a hold takes precedence, then provisional state, then payment status.

| Canonical input | Provider-facing status |
| --- | --- |
| `earningsStatus == HELD` or payout `status == HELD` | On Hold |
| Null final entitlement without a hold | Not final yet |
| Non-null final entitlement and payout `PAID` | Paid |
| Other non-null final entitlement, including READY/PROCESSING/FAILED payout | Earned |

“Earned” describes entitlement, not successful transfer or availability. All payout states leave the lifetime definition unchanged. No raw enums or refund identifiers appear. Provisional rows say “Amount not final yet” and “Not included in Total Earned yet,” including unresolved held disputes. HELD with an existing final entitlement still shows that amount.

## F. Cancellation / no-show / dispute behavior

- Customer cancellation: show the final allocated amount with **Cancellation compensation**, e.g. ₹350.00.
- Finalized zero: hide from the normal list, including provider cancellation. The backend audit/history document is retained; no client deletion or financial write occurs.
- Obsolete unpaid `NO_EARNING_RECORD_REQUIRED` audit records: hidden.
- No-show: **No-show earning**, using the final allocation.
- Open dispute: **Under review**, **On Hold**, and no definitive amount when final entitlement is null.
- Resolved dispute: **Dispute resolved**, using the adjusted final allocation.
- Canonical refund review: neutral **Under review** wording, following final/null entitlement semantics.
- Duplicate refunds: no separate client adjustment, negative row or reduced amount; refund metadata is not a source of earnings.

If the latest 120 records are all hidden zero/audit entries, the list says “No recent earnings to show.” It does not claim that older positive earnings are absent.

## G. Loading / empty / error / refresh

Initial loading never displays a false ₹0. Summary and history load independently. One branded loader is shown when both are pending, with a simple history-loading caption; either successful section remains usable if the other is pending or fails.

Backend-confirmed zero plus empty visible history shows **No earnings yet**. Other empty recent results show **No recent earnings to show**. Summary failure and history failure have distinct neutral messages and retry buttons; raw Firebase exception text is not exposed.

Pull-to-refresh and the toolbar refresh the summary. A failed history subscription is cancelled and replaced on retry; a healthy live subscription is retained. Concurrent refresh actions share one in-flight request. Streams and calls initialize in state, not on every build, and subscriptions are disposed on exit. Authentication changes key the content by UID, clearing old data and disposing old listeners. Signed-out/auth-error views perform no financial reads and show a sign-in message. Cross-account row data is rejected defensively. Firestore rules remain unchanged; the screen makes no financial writes.

## H. History limit

**Lifetime total = full reconciled history. Visible history = up to the latest 120 projection records ordered by creation time, with zero/audit rows hidden.** This is not complete-history pagination. Documents without `createdAt` remain outside the existing ordered history query even though they can contribute to the backend lifetime sum. The UI makes no complete-history claim. Pagination and richer projected metadata remain separate work.

## I. Tests added

24 targeted widget/model/presentation cases cover:

- Backend ₹10,000 total with only ₹850 + ₹500 visible rows.
- 120 returned rows with a larger full-history summary.
- Initial loading without false zero; independently available history.
- Confirmed zero/empty state and hidden final-zero records.
- Separate safe summary/history errors and successful retry.
- Canonical cancellation amount and preferred outcome date.
- Held provisional versus held final entitlements; paid records.
- No-show and resolved-dispute final allocations.
- Stable subscriptions/call counts across rebuild and refresh.
- Pull-to-refresh without unnecessary history resubscription.
- Signed-out reads, sign-out during an in-flight request, account switching and cross-account response/row rejection.
- Long booking references and a ₹12,345,678.90 total on a 320px phone with 2× text scaling in dark mode, without overflow.
- Integer formatting, malformed/legacy data rejection, duplicate-refund metadata isolation and date fallback labels.

## J. Validation results

- Targeted Provider Earnings tests: **24 passed, 0 failed**.
- Full `flutter test --no-pub`: **376 tests: 370 passed, 6 failed**.
- `flutter analyze --no-pub`: **0 errors, 2 warnings, 4 informational findings**. All six findings are in unchanged `canonical_booking_detail_screen.dart` and `canonical_booking_qr_payment_screen.dart`; no new findings remain.
- `git diff --check`: passed.

Full-suite failures are in unchanged tests:

1. Booking detail: in-progress customer service-started wording.
2. Booking detail: provider OTP verification → Complete service action.
3. Booking detail: provider completion → completed-pending-review action/spinner.
4. Request status: payment-expired terminal screen (Firebase default-app initialization).
5. Request status: provider-cancelled-after-payment terminal screen.
6. Request status: pending-provider shared booking summary.

An isolated archive of committed baseline `ea0a742` reproduced all six identical failures: the two affected test files ran 40 cases, with 34 passed and 6 failed. These unrelated tests were not edited to make the suite green.

No backend changes, deployment, production backfill or production reads were performed.

## K. Files changed

1. `lib/features/bookings/presentation/screens/provider_earnings_screen.dart` — stateful authenticated summary/history UI, refresh, errors, booking navigation and responsive theme-aware cards.
2. `lib/features/bookings/domain/models/provider_earning_record.dart` — canonical final/provisional record contract and date/visibility rules.
3. `lib/features/bookings/presentation/utils/provider_earnings_presentation.dart` — integer currency formatting and friendly outcome/status/date labels.
4. `lib/features/settings/presentation/screens/settings_screen.dart` — accurate earnings subtitle and icon.
5. `test/features/bookings/presentation/provider_earnings_screen_test.dart` — 24 focused regressions.
6. `docs/provider_earnings_screen.md` — this audit and A–N report.

The pre-existing `pubspec.yaml` version edit remains outside this task and uncommitted.

## L. Screens requiring manual testing

Automated tests do not replace authenticated device/staging checks. For **Settings → Provider Earnings**, verify:

- [ ] New provider: confirmed ₹0.00 and the genuine empty state.
- [ ] One completed booking: final amount, Earned label and appropriate date.
- [ ] Multiple earnings, including >120 historical records: full lifetime total and clearly limited recent list.
- [ ] Customer cancellation: actual compensation, e.g. ₹350.00; zero provider cancellation hidden.
- [ ] No-show: recorded allocation and friendly label.
- [ ] Held unresolved dispute: On Hold, no final amount claim.
- [ ] Held finalized entitlement: final amount retained.
- [ ] Resolved dispute: adjusted allocation and Dispute resolved label.
- [ ] Paid earning: still visible and still included in lifetime total.
- [ ] Large total, long booking ID, small phone and increased system text size: readable with no clipping.
- [ ] Offline/callable/history failure: distinct friendly errors, no false zero/empty claim; retry after reconnection.
- [ ] Dark mode and screen reader: readable contrast, meaningful amounts/statuses, refresh tooltip and loading announcements.
- [ ] Pull-to-refresh and toolbar retry: new summary without duplicate healthy history subscriptions.
- [ ] Tap a booking: existing authorized canonical detail opens; return refreshes lifetime.
- [ ] Sign out/switch account while loading: old financial data disappears.

Use staging with the Step 5 callable/indexes and reconciled projections. No deployment was executed in this task.

## M. Remaining work

Production use still requires the already documented Step 5 deployment/index and historical reconciliation rollout, plus the device/staging checklist above. Recent history remains capped at 120; friendly service metadata and precise live outcome timestamps are not uniformly projected. Legacy/malformed history deliberately requires reconciliation rather than client guessing. The six baseline test failures and existing analyzer findings are separate app issues.

## N. Conclusion

**Yes, in the implemented Flutter flow:** Settings → Provider Earnings now shows the backend Lifetime Total Earned and canonical, clearly labeled recent records, independently of the 120-row list, without presenting a wallet or automatic payout balance. Full-history accuracy retains Step 5's reconciled-data prerequisites. Production deployment and manual device verification remain unexecuted.
