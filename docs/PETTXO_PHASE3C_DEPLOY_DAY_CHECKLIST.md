# Pettxo Phase 3C: deploy-day checklist (owner)

Prepared 2026-11-17 in Phase 3C-3. Use this alongside `docs/PETTXO_PHASE3C_DEPLOYMENT_RUNBOOK.md`; section numbers like "§5" refer to that runbook.

This list contains **only** production commands and owner checks, in order. The local checks were all verified in Phase 3C-3 and are **not** repeated here:
- clean tree, and deploy source identical to `9ce090a`;
- `firebase` 15.24.0, Node v22.23.1, logged in as the owner account;
- `npm ci` and build;
- backend suite: 1128 passed, 3 known failures;
- keystore and AAB checksum;
- `.env` symlink;
- Dashboard prebuilt.

If you change anything in either worktree before deploying, re-run runbook §1 first.

**How to use it:**
- Do one step at a time.
- At every **STOP**, read the expected result. Continue only if it matches.
- Every command carries `--project pettexo-d9409`. Never remove it.
- Never run a bare `firebase deploy`, `--only functions` or `--only hosting`, and never `npm run deploy`.

Open a terminal and keep it in the release worktree for steps 1–13:

```bash
cd /Users/nishantgautam/development/pettexo-android-release
```

---

## A. Pre-checks (owner, consoles, read-only)

**1. Secrets exist.** Google Cloud Console → Security → Secret Manager (project `pettexo-d9409`). `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` each have an **enabled** latest version. Do not reveal the values.
- Expected: all 3 present and enabled.
- If it fails: do not deploy anything. Waves 1 and 5a would fail at deploy or run time.
- **STOP**

**2. Blocking data is empty.** Firebase console → Firestore, `(default)` database:
- `userBlocks` has no documents;
- `_rollouts/userBlockingV1` does **not** exist;
- `userRelationshipGuards` is empty or absent.
- Expected: all three true.
- If it fails: do not deploy. Report what you found; the safety analysis assumed all three.
- **STOP**

**3. Save the live Rules (rollback source).**

```bash
mkdir -p ~/PettxoReleaseBackups/rules-live-$(date +%Y-%m-%d)
```

Then copy the **full** text of each into that folder:
- Firebase console → Firestore Database → Rules → `firestore.rules`;
- Storage → Rules → `storage.rules`.

- Expected: two non-empty files whose text matches the console exactly. Also note the Rules version-history entry that is live now.
- If it fails (you can't copy): do not continue. Without the saved Rules, the only rollback is the base commit, whose match with production is Not Verified.
- **STOP**

**4. Play Console is ready.**
- Testing → Closed testing: the track exists.
- Your own tester account is on its tester list, and you have accepted the opt-in link.
- Setup → App signing → **Upload key certificate** SHA-256 equals `53:77:95:53:24:F0:13:E6:1D:AC:47:45:5B:1C:00:E6:34:E3:3C:D5:89:9E:37:57:42:13:4A:9B:B4:8A:33:3C`.
- Expected: all three true.
- If it fails: the backend deploy can still go ahead. Fix the Play side before step 16; on a fingerprint mismatch, do **not** upload and report it.
- **STOP**

---

## B. Rules (first)

**5. Firestore Rules.**

```bash
firebase deploy --only firestore:rules --project pettexo-d9409
```

- Expected:
  - `rules file firestore.rules compiled successfully`;
  - `released rules firestore.rules to cloud.firestore`;
  - `Deploy complete!`.
- If it fails:
  - **Compile error:** nothing was released, so STOP and report. Do not edit the Rules.
  - **Auth or permission error:** check `firebase login:list`, then STOP.
- **STOP**

**6. Storage Rules.**

```bash
firebase deploy --only storage --project pettexo-d9409
```

- Expected: `released rules storage.rules to firebase.storage`, then `Deploy complete!`.
- If it fails: STOP. The Firestore Rules alone are safe with the old functions. Report before retrying.
- **STOP**

**7. Quick Rules smoke (live app, build 23).** On your phone:
- like, then unlike, a post;
- comment on a recent post;
- **like and comment on an OLD post** (months old).
- Expected: all succeed.
- If it fails: a `permission-denied` or a failed like or comment means roll back the **Rules** now from the files saved in step 3 (§5, Rules, preferred path). Then STOP.
- **STOP**

---

## C. Functions, waves 1–5d (74 functions)

**For every wave:**
- **Expected:** one line like `✔ functions[<name>(asia-south1)] Successful update operation.` for each name, or `Successful create operation.` for the new ones, then `Deploy complete!`.
- **If the CLI prompts** to delete functions or to enter a param value: answer **No** or press Ctrl-C, then STOP.
- **If it fails:**
  - **Quota or Cloud Build error:** wait about 5 minutes and re-run the **same** command once.
  - **Some names fail:** re-run with only the failed names.
  - **Secret or param error:** STOP, and re-check step 1 or the `.env` symlink.
  - **Repeated failure:** STOP, and roll back per §5 if the app is affected.
- **After each wave,** scan errors:

  ```bash
  firebase functions:log --project pettexo-d9409
  ```

  Look for new ERRORs only.

**8. Wave 1: guarded booking and payment (9, all updates).**

```bash
firebase deploy --project pettexo-d9409 --only "functions:createBookingRequestV3,functions:acceptBookingRequestV3,functions:createRazorpayPaymentOrderV3,functions:createBookingQrPaymentV3,functions:previewBookingPaymentPricingV3,functions:verifyBookingPaymentV3,functions:razorpayWebhook,functions:reconcileBookingPaymentsV3,functions:expireAwaitingPaymentsV3"
```

- Expected: 9 × `Successful update operation`.
- If it fails: see "For every wave" above. On a secret error, STOP.
- **STOP**

**9. Wave 2: reporting and moderation (6: 2 updates, 4 creates).**

```bash
firebase deploy --project pettexo-d9409 --only "functions:submitReport,functions:enqueueReportModeration,functions:resolveReport,functions:rejectReport,functions:hideReportedService,functions:hideReportedReview"
```

- Expected:
  - `submitReport` and `enqueueReportModeration`: update;
  - `resolveReport`, `rejectReport`, `hideReportedService` and `hideReportedReview`: **create**.
- If it fails: STOP. The Dashboard deploy (step 15) depends on this wave.
- **STOP**

**10. Wave 3: chat, social and notifications (11, all updates).**

```bash
firebase deploy --project pettexo-d9409 --only "functions:getChatImageMessagingCapability,functions:sendChatImageMessage,functions:startProviderChat,functions:startDirectUserChat,functions:sendChatMessage,functions:markChatDelivered,functions:markChatRead,functions:setFollowState,functions:getProfileFollowCounts,functions:createSocialNotification,functions:sendPushForNotification"
```

- Expected: 11 × update, with **no prompt** for `CHAT_IMAGE_MESSAGING_ENABLED`.
- If it fails: a prompt for that param means the `.env` file was not read. Press Ctrl-C, STOP, and check that `ls -l functions/.env.pettexo-d9409` resolves.
- **STOP**

**11. Wave 4: blocking callables (3, all creates; the gate stays OFF).**

```bash
firebase deploy --project pettexo-d9409 --only "functions:blockUserV1,functions:unblockUserV1,functions:getUserRelationshipStateV1"
```

- Expected: 3 × **create**. No document writes are needed; blocking stays disabled (§3).
- If it fails: STOP. Nothing else depends on this wave.
- **STOP**

**12. Wave 5a (13, all updates).**

```bash
firebase deploy --project pettexo-d9409 --only "functions:cancelBookingRequestByParentV3,functions:cancelConfirmedBookingByCustomerV3,functions:cancelConfirmedBookingByProviderV3,functions:completeBookingServiceV3,functions:createBookingDisputeV3,functions:declineBookingRequestV3,functions:expirePendingProviderBookingsV3,functions:finalizeCanonicalNoShowsV3,functions:finalizeCompletedBookingsV3,functions:getBookingFinancialLedgerV3,functions:getCanonicalDisputeV3,functions:getProviderPayoutV3,functions:listBookableServiceSlotsV3"
```

- Expected: 13 × update.
- If it fails: see "For every wave". The order within Wave 5 is not safety-critical, but all of 5a–5d must finish eventually.
- **STOP**

**13. Waves 5b, 5c and 5d.** Run them one at a time, with a STOP after each.

```bash
# Wave 5b (12)
firebase deploy --project pettexo-d9409 --only "functions:listCanonicalDisputesV3,functions:listProviderPayoutsV3,functions:markBookingViewedByProviderV3,functions:previewBookingCancellationV3,functions:previewBookingDisputeResolutionV3,functions:resolveBookingDisputeV3,functions:retryProviderPayoutV3,functions:runBookingFinancialReconciliationV3,functions:runProviderPayoutProcessingBatchV3,functions:sendProviderRequestRemindersV3,functions:submitBookingReviewV3,functions:verifyBookingStartOtpV3"
```

- Expected: 12 × update.
- If it fails: see "For every wave".
- **STOP**

```bash
# Wave 5c (13)
firebase deploy --project pettexo-d9409 --only "functions:getAdminDashboardMetricsV3,functions:getCanonicalBookingAdminDetailV3,functions:getCanonicalDisputeAdminDetailV3,functions:getCanonicalFinancialSummaryV3,functions:getCanonicalProviderPayoutAdminDetailV3,functions:getCanonicalRefundAdminDetailV3,functions:getProviderLifetimeEarningsV3,functions:listCanonicalBookingsForAdminV3,functions:listCanonicalDisputesForAdminV3,functions:listCanonicalNoShowCasesV3,functions:listCanonicalProviderPayoutsForAdminV3,functions:listCanonicalRefundsForAdminV3,functions:reconcileProviderEarningsBatchV3"
```

- Expected: 13 × update.
- If it fails: see "For every wave".
- **STOP**

```bash
# Wave 5d (7)
firebase deploy --project pettexo-d9409 --only "functions:getManualSettlementObligationV3,functions:listManualSettlementObligationsV3,functions:materializeManualSettlementObligationsForBookingV3,functions:recordManualCustomerRefundV3,functions:recordManualProviderPayoutV3,functions:revealManualSettlementProviderDestinationV3,functions:synchronizeManualSettlementPayoutsV3"
```

- Expected: 7 × update. That completes 74 functions.
- If it fails: see "For every wave".
- **STOP**

Do **not** run `firebase deploy --only firestore:indexes`; no index changes are needed.

---

## D. Smoke checks (owner, about 15 minutes, live build 23, test accounts A and B)

**14. Run runbook §4, items 1–8:**
1. Feed loads.
2. Like, unlike and comment, including on an old post.
3. Follow and unfollow, and check the counts.
4. Chat text and image, both ways.
5. Browse services.
6. Booking request, then cancel it without paying.
7. Report a service and a review.
8. Check the logs for ERRORs: `USER_RELATIONSHIP_BLOCKED`, `permission-denied`, missing secret or param, `razorpayWebhook` 5xx.

- Expected: everything works; no new ERRORs.
- If it fails:
  - **Login, feed, chat, follow or booking breaks for unblocked users, comments fail broadly, the webhook returns 5xx, or repeated ERRORs appear:** roll back per §5. Do the Rules first (from the step 3 files), then Functions from base `1652aac`.
  - **Anything else:** STOP and report before rolling back.
- **STOP**

---

## E. Admin Dashboard deploy (prebuilt; only after step 9 succeeded)

**15. Deploy hosting from the prebuilt worktree.**

```bash
cd /Users/nishantgautam/development/pettxo-admin-build
git rev-parse HEAD                    # must be d07df166a73503a2da4bf95bc0ec1dca799717ca
git status --porcelain                # must print nothing
grep -n '"functions"' firebase.json || echo "no functions key"   # must print "no functions key"
firebase deploy --only hosting:admin --project pettexo-d9409
```

- Expected:
  - the three guard lines as noted;
  - then `hosting[pettxo-admin]: release complete`, `Deploy complete!` and the `pettxo-admin` Hosting URL.
- Then open the Dashboard, open a report, and check that the **Resolve** and **Reject** actions load (runbook §4, item 9).
- If it fails:
  - **A guard line differs:** do not deploy, and report.
  - **Deploy error:** nothing was released, so STOP.
  - **The deployed Dashboard is broken:** Firebase console → Hosting → `pettxo-admin` → release history → **Rollback**.
- Never run `firebase deploy` here without `--only hosting:admin`.
- **STOP**

---

## F. Android closed testing (only after step 14 passed)

**16. Verify the AAB.**

```bash
cd ~/PettxoReleaseBackups/builds/1.0.5+24 && shasum -a 256 -c SHA256SUMS
```

- Expected: `pettxo-1.0.5+24-release.aab: OK`. The SHA-256 is `edc72148234c23d7d28c639228fff97b1f7ff65be64679d78f47ec219cdcbc87`.
- If it fails: do not upload. Never use the AAB in `superseded-3C1/`.
- **STOP**

**17. Upload to closed testing.** Play Console → Testing → Closed testing → (your track) → Create release:
- upload `pettxo-1.0.5+24-release.aab`;
- check that it shows **versionCode 24 / versionName 1.0.5**;
- paste the release notes from runbook §7;
- review, then roll out to the **closed track only**.
- Expected: the release is accepted, then the status becomes "In review".
- If it fails:
  - **Signing-key error:** STOP and report. Do not create a new key.
  - **Version-code conflict:** STOP and report.
- **STOP**

**18. Wait for Play review.** Closed-testing review can take **a few hours to several days**. When it shows as available, install it from the tester opt-in link on your tester account. Check the blocking-disabled dialog text: "Blocking isn't available yet. If you feel unsafe, you can report this user and our team will review it."
- Expected: 1.0.5 (24) installs; the smoke items from step 14 pass on 1.0.5.
- If it fails: halt the rollout in Play Console (Closed testing → Halt) and report. The backend can stay deployed, because build 23 is unaffected.
- **STOP**: done.
