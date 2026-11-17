# Pettxo Phase 3C: production deployment runbook

Prepared: 2026-11-17 (Asia/Kolkata). Updated in Phase 3C-2: legacy-post Rules fix and the blocking-disabled message. Updated in Phase 3C-3: local deploy-day verification, prebuilt Dashboard, Play checks. Updated in Phase 3C-4: chat-photo incident after the Rules deploy; Storage Rules restored to base. Updated in Phase 3C-6: the deploy is **done**. See `docs/PETTXO_PHASE3C_PRODUCTION_DEPLOYMENT_RECORD.md` for what is live, and the new permanent section "New Cloud Functions under domain-restricted sharing" in §2. **For owner approval.**

> **Production status (2026-11-17, about 05:00 IST, owner-run).**
>
> **What is live now:**
> - **Firestore Rules: the NEW version** (from `e8f97f3`, identical to `9ce090a`). They are working: feed, likes, comments, old-post like and comment, and chat text all pass.
> - **Storage Rules: the PREVIOUS live version** (rolled back). This equals base `1652aac`, and the repository `storage.rules` at `d1c5c85c171c08d9c1192f898e7ee9a0e0d353da` is now byte-identical to it.
> - **Functions:** still all base `1652aac`; none are deployed yet.
>
> **Incident.** The new `storage.rules` (`9ce090a`) denied every chat photo in production. The chat-media `create` rule read three Firestore documents: `chats/{id}`, `userBlocks/a_b` and `userBlocks/b_a`. Production Storage Rules may access at most **two** Firestore documents per evaluation. The emulator does not enforce this limit, so the tests passed. Details are in `PETTXO_PHASE3C4_REPORT.md`.
>
> **The fix (`d1c5c85c171c08d9c1192f898e7ee9a0e0d353da`)** restores `storage.rules` to base. It adds a static test (`storageRulesFirestoreBudget.test.js`) that fails any Storage rule reaching more than two Firestore documents, and an end-to-end chat-photo emulator test. Blocked pairs remain refused at the server: `getChatImageMessagingCapability` and `sendChatImageMessage`, which ship in Wave 3. **Do not deploy Storage Rules again for this release.**
>
> **Live Admin Dashboard.** The live (old) Dashboard updates `reports` status with a client-side transaction. The new Firestore Rules deny that (`reports` update/delete is `false`), so its report-status action fails until Wave 2 and the new Dashboard (§6) are deployed. Reading reports still works.

**What the deploy does:**
- Deploys the new backend (74 Cloud Functions) and the new Firestore and Storage Rules, with user blocking **disabled**.
- Then the Admin Dashboard hosting.
- Then the Android 1.0.5 (24) closed-testing upload.

Blocking activation is Phase 3B-4 and is **not** part of this runbook.

| Item | Value |
|---|---|
| Firebase project | `pettexo-d9409` (pass `--project pettexo-d9409` on **every** command) |
| Functions | Gen 2, `asia-south1`, Node 22 |
| Deploy source (main) | Clean worktree `/Users/nishantgautam/development/pettexo-android-release`, branch `release/android-1.0.5-closed-testing` (also on GitHub). **Deploy commit: `d1c5c85c171c08d9c1192f898e7ee9a0e0d353da`** (Phase 3C-4), or a later commit on this branch that changes only `docs/`.
- **Functions source:** byte-identical to `9ce090a` and to `c74fbd46…`. The fix changed only `functions/test` and `functions/scripts`, which are not deployed.
- **`firestore.rules`:** identical to `9ce090a`; already live.
- **`storage.rules`:** byte-identical to base `1652aac`, which is what is live. Do not redeploy it. |
| Base (rollback) commit | `1652aac6732273b945843a418b3273a88109ab42` |
| Admin Dashboard source | `d07df166a73503a2da4bf95bc0ec1dca799717ca` (`release/phase3b1-admin-reporting-2026-11-16`) |
| Android build | `1.0.5+24`, built at `9ce090a`: `/Users/nishantgautam/PettxoReleaseBackups/builds/1.0.5+24/pettxo-1.0.5+24-release.aab` (SHA-256 `edc72148234c23d7d28c639228fff97b1f7ff65be64679d78f47ec219cdcbc87`). The 3C-1 AAB in `superseded-3C1/` must not be uploaded. |

**Never deploy from:**
- the main working tree `/Users/nishantgautam/development/pettexo`, which holds uncommitted iOS and `pubspec.yaml` work;
- the Admin Dashboard repo (Functions or a bare deploy).

**Never run** `npm run deploy`, a bare `firebase deploy`, or `firebase deploy --only functions`. Each of these deploys every function or every service. Also never run `firebase deploy --only hosting` from this repo. Its `firebase.json` has a default `hosting` block (public `web/`, the main site's `assetlinks.json` and `/post/**` redirect) that is not part of this release.

**Config verified in Phase 3C-3:**
- `--only firestore:rules` deploys `firestore.rules` to the **(default)** database only; no named databases are configured.
- `--only storage` deploys `storage.rules` to the **default bucket** only: a single `storage` object with no targets or bucket list.
- `.firebaserc` has `default: pettexo-d9409` and no targets.
- The functions predeploy hook is `npm --prefix "$RESOURCE_DIR" run build` (= `tsc` in `functions/`).
- The CLI reads `functions/.env.pettexo-d9409` (param `CHAT_IMAGE_MESSAGING_ENABLED`) from the source directory at deploy time. The `.env.*` entry in `ignore` only keeps the file out of the upload.

## 1. Pre-deploy checks (all must pass)

```bash
cd /Users/nishantgautam/development/pettexo-android-release
git status --porcelain                       # must print nothing
git rev-parse HEAD                           # the approved branch HEAD (see Phase 3C-1 report)
git diff --stat d1c5c85c171c08d9c1192f898e7ee9a0e0d353da HEAD -- functions/src firestore.rules storage.rules firestore.indexes.json firebase.json lib android pubspec.yaml
#   must print nothing (deploy source identical to the approved Phase 3C-4 commit)
git diff 1652aac6732273b945843a418b3273a88109ab42 HEAD -- storage.rules
#   must print nothing (Storage Rules = base = what production runs)
firebase --version                           # recorded during 3C-1: 15.24.0
firebase login:list                          # must show the owner account you intend to deploy with
node --version                               # v22.x
ls -l functions/.env.pettexo-d9409           # symlink to the main tree's file; must exist (see below)
(cd functions && npm ci && npm run build)    # lockfile install, no upgrades
(cd functions && npm run test:emulator)      # expected (Phase 3C-4): 1137 tests, 1134 passed, 3 known failures (#206, #209, #599)
#   printed as two batches: 1125 tests run in parallel, then 12 tests from Storage-Rules files run serially
```

All of the above was re-verified locally on 2026-11-17 in Phase 3C-3 (see `PETTXO_PHASE3C3_REPORT.md`). The keystore, AAB checksum and symlink targets were also checked after the disk clean-up. The deploy-day command list is in `docs/PETTXO_PHASE3C_DEPLOY_DAY_CHECKLIST.md`.

**Play Console check (owner).** Play Console → Testing → Closed testing:
- The closed-testing track you will release to exists.
- Your own tester account is on its tester list (email list or Google Group), and you have accepted the opt-in link.

Without this you cannot install 1.0.5 from Play to verify it.

**Secrets and params.** Secret values are never printed. Check each one exists in Google Cloud Console → Security → Secret Manager (project `pettexo-d9409`), with an enabled latest version.

| Name | Kind | Used by functions in this deploy | Owner console check |
|---|---|---|---|
| `RAZORPAY_KEY_ID` | `defineSecret` | 8 (Wave 1: `razorpayWebhook`, `createBookingQrPaymentV3`, `createRazorpayPaymentOrderV3`, `verifyBookingPaymentV3`, `expireAwaitingPaymentsV3`, `reconcileBookingPaymentsV3`; Wave 5a: `cancelConfirmedBookingByCustomerV3`, `cancelConfirmedBookingByProviderV3`) | **Required** |
| `RAZORPAY_KEY_SECRET` | `defineSecret` | Same 8 | **Required** |
| `RAZORPAY_WEBHOOK_SECRET` | `defineSecret` | `razorpayWebhook` | **Required** |
| `RESEND_API_KEY` | `defineSecret` | None in this deploy (4 unchanged email functions) | Not needed for this deploy |
| `RESEND_MARKETING_API_KEY` | `defineSecret` | None in this deploy (2 unchanged functions) | Not needed for this deploy |
| `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_GRAPH_API_VERSION` | `defineSecret` | Not bound to any exported function | Not needed |
| `CHAT_IMAGE_MESSAGING_ENABLED` | `defineBoolean` param | `getChatImageMessagingCapability`, `sendChatImageMessage` (Wave 3) | Value comes from `functions/.env.pettexo-d9409` (`true`), a gitignored file symlinked into the worktree. If it is missing, the CLI prompts or fails, so do not deploy Wave 3 without it. |

**Owner console data checks** (read-only, in the Firebase console):
- `userBlocks` is still empty. You verified this on 2026-11-17; re-check on deploy day.
- `_rollouts/userBlockingV1` does **not** exist.
- `userRelationshipGuards` is empty or absent.
- Optional: note whether any `socialPosts` document lacks a string `authorId`. After the Phase 3C-2 fix such posts are no longer refused by Rules: the block check is skipped when no author resolves. If you find another author field name, report it so it can be added to `socialPostAuthorUid` in `firestore.rules`.

**Save the currently-live Rules.** Firebase console → Firestore Database → Rules, and Storage → Rules: copy the full text of each into `~/PettxoReleaseBackups/rules-live-<date>/firestore.rules` and `storage.rules`. This is the exact rollback source. Production Rules provenance is Not Verified, so do not assume it equals the base commit.

## 2. Deploy order and exact commands

Run everything from `/Users/nishantgautam/development/pettexo-android-release`. After each step, wait for success, then check the logs (§4) before continuing.

### Step 1: Firestore Rules (DONE 2026-11-17, about 05:00 IST); Storage Rules: do NOT deploy

```bash
# Already done, and live and working. Re-run ONLY if the Firestore Rules were rolled back:
firebase deploy --only firestore:rules --project pettexo-d9409
# Do NOT run `firebase deploy --only storage`. Production already runs exactly
# the repository storage.rules (base 1652aac); the 9ce090a version broke chat photos.
```

**Phase 3C-4 lesson: the Storage Rules cross-service limit.** Production Storage Rules may access at most **2 distinct Firestore documents** per evaluation; a third is permission-denied. Repeat access to the same document is cached and counted once. The Storage emulator does **not** enforce this, so emulator tests cannot catch it. `functions/test/storageRulesFirestoreBudget.test.js` now checks every Storage rule statically. Firestore Rules have their own, larger limits: 10 per single-document request and 20 per batch or transaction.

**Why Rules go first.** This changes the 3B-3a recommendation, which deployed Rules right after the functions.
- **What the new Rules depend on.** They only check whether `userBlocks/{a}_{b}` documents exist, and read existing `chats` and `socialPosts`. They do not depend on anything the new functions create.
- **Safe with old functions.** The old functions use the Admin SDK and are unaffected by Rules.
- **The gap they close.** Deploying them first means there is **no window** in which a client can still write `userBlocks` directly (the old Rules allow owner create and delete) while new functions already honour directed blocks. That window is the "direct userBlocks write" gap (3B-3a §D/C4): a crafted block plus a new function could fail a payment capture.
- **Build 23 behaviour.** The live app is unaffected while `userBlocks` is empty. Rules no longer refuse likes, comments or shares on posts without a string `authorId` (fixed in `5bb2661`). The app itself already hides authorless posts and refuses those actions client-side, unchanged from before the deploy.

### Step 2: Functions, in waves (74 functions = 7 new + 17 direct + 5 shared + 45 schema-consistency)

The inventory was re-verified on the deploy source: 146 exports, endpoint metadata identical to the 3B-3a HEAD inventory, all `asia-south1`. No function changes kind, trigger, region or secrets, so nothing needs delete-and-recreate.

**Wave 1: guarded booking and payment (9).** Deploy first, so every booking and payment entry point checks the relationship guard before any block can exist.

```bash
firebase deploy --project pettexo-d9409 --only "functions:createBookingRequestV3,functions:acceptBookingRequestV3,functions:createRazorpayPaymentOrderV3,functions:createBookingQrPaymentV3,functions:previewBookingPaymentPricingV3,functions:verifyBookingPaymentV3,functions:razorpayWebhook,functions:reconcileBookingPaymentsV3,functions:expireAwaitingPaymentsV3"
```

**Wave 2: reporting and moderation (6).** The Admin Dashboard's four new actions depend on these.

```bash
firebase deploy --project pettexo-d9409 --only "functions:submitReport,functions:enqueueReportModeration,functions:resolveReport,functions:rejectReport,functions:hideReportedService,functions:hideReportedReview"
```

**Wave 3: chat, social and notifications (11).** Needs `CHAT_IMAGE_MESSAGING_ENABLED`.

```bash
firebase deploy --project pettexo-d9409 --only "functions:getChatImageMessagingCapability,functions:sendChatImageMessage,functions:startProviderChat,functions:startDirectUserChat,functions:sendChatMessage,functions:markChatDelivered,functions:markChatRead,functions:setFollowState,functions:getProfileFollowCounts,functions:createSocialNotification,functions:sendPushForNotification"
```

**Wave 4: blocking callables (3).** The gate stays disabled, so they report "unavailable" (see §3).

```bash
firebase deploy --project pettexo-d9409 --only "functions:blockUserV1,functions:unblockUserV1,functions:getUserRelationshipStateV1"
```

**Wave 5: schema consistency (45).** These functions only gained the `user_blocked` cancellation type through the shared parser and state machine. They are batched by module so each deploy stays small:
- **5a and 5b:** `bookingV3FlowFunctions`.
- **5c:** admin operations, metrics and earnings.
- **5d:** manual settlement.

With the gate off, no `user_blocked` cancellation can occur, so the order relative to Waves 1–4 is not safety-critical. All 45 must be deployed **before** any Phase 3B-4 activation.

```bash
# Wave 5a (13)
firebase deploy --project pettexo-d9409 --only "functions:cancelBookingRequestByParentV3,functions:cancelConfirmedBookingByCustomerV3,functions:cancelConfirmedBookingByProviderV3,functions:completeBookingServiceV3,functions:createBookingDisputeV3,functions:declineBookingRequestV3,functions:expirePendingProviderBookingsV3,functions:finalizeCanonicalNoShowsV3,functions:finalizeCompletedBookingsV3,functions:getBookingFinancialLedgerV3,functions:getCanonicalDisputeV3,functions:getProviderPayoutV3,functions:listBookableServiceSlotsV3"
# Wave 5b (12)
firebase deploy --project pettexo-d9409 --only "functions:listCanonicalDisputesV3,functions:listProviderPayoutsV3,functions:markBookingViewedByProviderV3,functions:previewBookingCancellationV3,functions:previewBookingDisputeResolutionV3,functions:resolveBookingDisputeV3,functions:retryProviderPayoutV3,functions:runBookingFinancialReconciliationV3,functions:runProviderPayoutProcessingBatchV3,functions:sendProviderRequestRemindersV3,functions:submitBookingReviewV3,functions:verifyBookingStartOtpV3"
# Wave 5c (13)
firebase deploy --project pettexo-d9409 --only "functions:getAdminDashboardMetricsV3,functions:getCanonicalBookingAdminDetailV3,functions:getCanonicalDisputeAdminDetailV3,functions:getCanonicalFinancialSummaryV3,functions:getCanonicalProviderPayoutAdminDetailV3,functions:getCanonicalRefundAdminDetailV3,functions:getProviderLifetimeEarningsV3,functions:listCanonicalBookingsForAdminV3,functions:listCanonicalDisputesForAdminV3,functions:listCanonicalNoShowCasesV3,functions:listCanonicalProviderPayoutsForAdminV3,functions:listCanonicalRefundsForAdminV3,functions:reconcileProviderEarningsBatchV3"
# Wave 5d (7)
firebase deploy --project pettexo-d9409 --only "functions:getManualSettlementObligationV3,functions:listManualSettlementObligationsV3,functions:materializeManualSettlementObligationsForBookingV3,functions:recordManualCustomerRefundV3,functions:recordManualProviderPayoutV3,functions:revealManualSettlementProviderDestinationV3,functions:synchronizeManualSettlementPayoutsV3"
```

**Batching rationale:**
- Smaller deploys avoid Cloud Build and deploy-rate quotas.
- They make a failure attributable to one module.
- They let you stop between waves.
- Each `--only` list names exactly the intended functions, so the CLI never offers to delete anything.
- The predeploy hook builds `functions/lib` from source. `functions/src/audit` is compiled and uploaded as code, but is **not** exported and creates no function.

### New Cloud Functions under domain-restricted sharing (permanent; applies to every deploy)

**Why.** The Google Cloud organisation enforces `iam.allowedPolicyMemberDomains` (domain-restricted sharing).
- When the CLI **creates** a function whose code declares `invoker: "public"`, it tries to grant `allUsers` the Cloud Run invoker role. The policy refuses that principal.
- The function's code is deployed, but the CLI reports that it could not set the invoker or IAM policy.
- Until this is fixed, Cloud Run rejects every request with **HTTP 403** before the code runs.
- This happened on 17 Nov 2026 to all 7 new functions (Waves 2 and 4).

**After creating any NEW function, do this for each one:**

1. **Disable the Cloud Run invoker IAM check.** The service name is normally the function name in lower case (for example `resolveReport` → `resolvereport`). Confirm it under Cloud Run → Services.

   ```bash
   gcloud run services update <service> --region=asia-south1 --project=pettexo-d9409 --no-invoker-iam-check
   ```

   Console alternative: Google Cloud console → **Cloud Run** → **Services** → `<service>` → **Security** tab → Authentication: **Allow public access** → **Save**.

2. **Verify** with an unauthenticated POST:

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{"data":{}}' "https://asia-south1-pettexo-d9409.cloudfunctions.net/<functionName>"
   ```

   - **Expected: `401`.** The request reached the function, which rejected the missing Firebase Auth token.
   - **`403`:** Cloud Run is still blocking. Repeat step 1.
   - **Any other code:** STOP and investigate.

3. **Record** the function and the result in the deployment record.

**Updates to existing functions are unaffected.** They keep their existing invoker setting and need no action. Only **creates** need this, including any function recreated after a rollback deleted it.

**Why this is safe.** It gives the same exposure as the intended `invoker: "public"`. Callables still authenticate every request themselves, using Firebase Auth and, where needed, admin checks. Do **not** try to work around the policy by adding `allUsers` IAM bindings.

### Step 3: Firestore indexes

**None required.**
- `firestore.indexes.json` is unchanged between base `1652aac` and the release.
- The new pair-booking queries (`bookings` where `parentId ==` and `providerId ==`) use equality filters only, which single-field indexes serve.

Do **not** run `firebase deploy --only firestore:indexes`. It would also prompt about deleting indexes that exist in production but not in the file.

## 3. Activation gate after the deploy

No write is needed, and the gate stays **OFF**:
- **Disabled unless fully enabled.** `activationState` (`functions/src/blocking/blockingActivationGate.ts:44-76`) returns `enabled: false` with `USER_BLOCKING_DISABLED` unless `_rollouts/userBlockingV1` exists with `enabled === true` and `status === "active"`. It also needs a verified `_migrations/userRelationshipGuardV1` and a matching `userBlockingActivationAudit` record. A missing or malformed document means disabled.
- **Nothing can turn it on.** No deployed function writes these documents: `recordBlockingRolloutTransition` and `verifyAndRecordRelationshipMigration` are not called by any export. The new Rules deny all client access to `_rollouts`, `_migrations` and `userBlockingActivationAudit`.
- **What blocking calls do:**
  - `blockUserV1` throws `failed-precondition` "User blocking is not available yet. Reporting remains available." (`blockingActivationGate.ts:110-116`);
  - `getUserRelationshipStateV1` returns `canBlock: false` (`functions/src/blocking/userBlocking.ts:561-570`).

## 4. Post-deploy smoke checks

The owner does these in about 15 minutes, on a real phone running the **live build 23 (1.0.4)**, with two test accounts A and B:
1. Log in as A. The feed loads.
2. Like and unlike a post by B. Comment on B's post.
   - **Old-post Rules check:** also like and comment on an **OLD** post, one created months ago, for example from the earliest posts in the feed or on a profile. It must succeed. A `permission-denied` here means the legacy-author Rules fix is not live; roll back the Rules.
3. Follow, then unfollow B. Check the profile follow counts.
4. Chat: A↔B text message, then a **chat photo, both ways** (A→B and B→A). Each photo must upload, appear for the other user, and open full-size. A "You do not have permission to send this photo" error means a Storage Rules denial: check that no one deployed `storage.rules`, and re-publish the saved live Storage Rules if they did.
5. Browse services and open a service detail.
6. Booking request as A to B's service. Do **not** pay with real money; cancel it.
7. Legacy report: report a service and a review from the app. The document appears in `reports`, and `enqueueReportModeration` runs.
8. **Logs.** In Cloud Console → Logging, set the resource type to Cloud Run revision (Gen 2 functions) and the severity to ≥ ERROR, covering the deploy window. Or run `firebase functions:log --project pettexo-d9409`. Expect no new errors, especially:
   - `USER_RELATIONSHIP_BLOCKED`;
   - `permission-denied` from Rules;
   - missing secret or param errors;
   - `razorpayWebhook` 5xx.
9. **Admin Dashboard** (after §6): open a report and confirm the Resolve and Reject actions load.

**Abort and roll back if** any of these appear:
- login, feed, chat, follow or booking fails for unblocked users;
- comments fail broadly;
- the webhook returns 5xx;
- functions show repeated ERRORs after the deploy.

## 5. Rollback plan

### Rules

**Storage Rules (Phase 3C-4):** production already runs the previous live Storage Rules, which equal base and the repository file. There is nothing to roll back unless someone deploys `storage.rules` again.

1. **Preferred.** Re-publish the saved live Rules from §1:
   - Firebase console → Firestore Database → Rules: paste the saved `firestore.rules`, then **Publish**.
   - Storage → Rules: paste the saved `storage.rules`, then **Publish**.

   Alternatively, use the Rules editor's version-history panel: open the release published before the deploy and publish that version again.
2. **CLI fallback, from the base commit.** The live Rules may differ from base, so prefer step 1.

   ```bash
   git -C /Users/nishantgautam/development/pettexo worktree add --detach /Users/nishantgautam/development/pettexo-rollback-1652aac 1652aac6732273b945843a418b3273a88109ab42
   cd /Users/nishantgautam/development/pettexo-rollback-1652aac
   firebase deploy --only firestore:rules --project pettexo-d9409
   firebase deploy --only storage --project pettexo-d9409
   ```

### Functions

Redeploy from base `1652aac`, using the same names minus the 7 that are new.

```bash
cd /Users/nishantgautam/development/pettexo-rollback-1652aac       # created above
ln -s /Users/nishantgautam/development/pettexo/functions/.env.pettexo-d9409 functions/.env.pettexo-d9409
(cd functions && npm ci)
firebase deploy --project pettexo-d9409 --only "functions:acceptBookingRequestV3,functions:cancelBookingRequestByParentV3,functions:cancelConfirmedBookingByCustomerV3,functions:cancelConfirmedBookingByProviderV3,functions:completeBookingServiceV3,functions:createBookingDisputeV3,functions:createBookingQrPaymentV3,functions:createBookingRequestV3,functions:createRazorpayPaymentOrderV3,functions:createSocialNotification,functions:declineBookingRequestV3,functions:enqueueReportModeration,functions:expireAwaitingPaymentsV3,functions:expirePendingProviderBookingsV3,functions:finalizeCanonicalNoShowsV3,functions:finalizeCompletedBookingsV3,functions:getAdminDashboardMetricsV3,functions:getBookingFinancialLedgerV3,functions:getCanonicalBookingAdminDetailV3,functions:getCanonicalDisputeAdminDetailV3,functions:getCanonicalDisputeV3,functions:getCanonicalFinancialSummaryV3,functions:getCanonicalProviderPayoutAdminDetailV3,functions:getCanonicalRefundAdminDetailV3,functions:getChatImageMessagingCapability,functions:getManualSettlementObligationV3,functions:getProfileFollowCounts,functions:getProviderLifetimeEarningsV3,functions:getProviderPayoutV3,functions:listBookableServiceSlotsV3,functions:listCanonicalBookingsForAdminV3,functions:listCanonicalDisputesForAdminV3,functions:listCanonicalDisputesV3,functions:listCanonicalNoShowCasesV3,functions:listCanonicalProviderPayoutsForAdminV3,functions:listCanonicalRefundsForAdminV3,functions:listManualSettlementObligationsV3,functions:listProviderPayoutsV3,functions:markBookingViewedByProviderV3,functions:markChatDelivered,functions:markChatRead,functions:materializeManualSettlementObligationsForBookingV3,functions:previewBookingCancellationV3,functions:previewBookingDisputeResolutionV3,functions:previewBookingPaymentPricingV3,functions:razorpayWebhook,functions:reconcileBookingPaymentsV3,functions:reconcileProviderEarningsBatchV3,functions:recordManualCustomerRefundV3,functions:recordManualProviderPayoutV3,functions:resolveBookingDisputeV3,functions:retryProviderPayoutV3,functions:revealManualSettlementProviderDestinationV3,functions:runBookingFinancialReconciliationV3,functions:runProviderPayoutProcessingBatchV3,functions:sendChatImageMessage,functions:sendChatMessage,functions:sendProviderRequestRemindersV3,functions:sendPushForNotification,functions:setFollowState,functions:startDirectUserChat,functions:startProviderChat,functions:submitBookingReviewV3,functions:submitReport,functions:synchronizeManualSettlementPayoutsV3,functions:verifyBookingPaymentV3,functions:verifyBookingStartOtpV3"
# Optional: remove the 7 functions that do not exist at base. The Dashboard's report actions stop working.
# If any of the 7 are later recreated, apply "New Cloud Functions under domain-restricted sharing" (§2) again.
firebase functions:delete blockUserV1 unblockUserV1 getUserRelationshipStateV1 resolveReport rejectReport hideReportedService hideReportedReview --region asia-south1 --project pettexo-d9409
```

**What rollback does NOT undo:**
- **Documents written while the new code ran.** These include:
  - `userRelationshipGuards/*` "open" guards created by booking operations;
  - canonical `reports` written by `submitReport`;
  - notifications;
  - any booking or payment state changes.

  Base functions ignore guards, so they are harmless, but they remain.
- **The Admin Dashboard Hosting release.** Roll it back separately: Hosting → release history → Rollback.
- **The Android closed-testing release.** Halt it in Play Console.
- **Base code fidelity.** The base commit is assumed to be what production ran before. That is Not Verified: production function source cannot be read back.

## 6. Admin Dashboard deploy (separate step, after Functions Wave 2)

**Background:**
- The current `build/web` is stale: `index.html` is from 2026-10-12.
- The Dashboard working tree has 6 uncommitted finance and offer-wall files, including `lib/`.
- The repo is on the iCloud-synced Desktop.

So build from a **clean detached checkout outside iCloud**.

**Already prebuilt (Phase 3C-3, 2026-11-17).** The Dashboard is prebuilt at `/Users/nishantgautam/development/pettxo-admin-build`: a detached worktree at `d07df166…`, `git status` clean.
- `flutter pub get --enforce-lockfile`: `pubspec.lock` unchanged.
- Full `flutter test`: **264 passed, 0 failed**. The "271" seen before was counted on the Dashboard's dirty working tree; its uncommitted diff adds exactly 7 tests.
- `flutter build web --release` succeeded.
- The four report actions are called through `FirebaseFunctions.instanceFor(region: 'asia-south1')`.

On deploy day, **skip** the `worktree add` and the build below. Just `cd` there, re-run the `git rev-parse HEAD`, `git status --porcelain` and `"functions"` checks, then deploy. Do not run `worktree add` again: the path already exists, so it would fail.

Full procedure (for a rebuild from scratch):

```bash
D="/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard"
git -C "$D" worktree add --detach /Users/nishantgautam/development/pettxo-admin-build d07df166a73503a2da4bf95bc0ec1dca799717ca
cd /Users/nishantgautam/development/pettxo-admin-build
git status --porcelain                               # must print nothing
flutter pub get --enforce-lockfile
flutter build web --release
grep -n '"functions"' firebase.json || echo "no functions key"   # must print "no functions key"
firebase deploy --only hosting:admin --project pettexo-d9409
```

- **Target.** `.firebaserc` maps the hosting target `admin` to site **`pettxo-admin`**, and the Dashboard `firebase.json` has only a `hosting` block. `--only hosting:admin` deploys nothing else.
- **Never** run `firebase deploy` without `--only hosting:admin` from the Dashboard. Never deploy its `functions/` folder: it contains obsolete `us-central1` functions with colliding names.
- **Functions it calls.** The Dashboard calls `asia-south1` functions, so it must follow Functions Wave 2.

## 7. Android closed testing (owner, manual, after the smoke checks pass)

1. **Verify the file.** Run `shasum -a 256 -c SHA256SUMS` in `~/PettxoReleaseBackups/builds/1.0.5+24/`.
2. **Check the signing key.** Compare the AAB's upload certificate SHA-256 with Play Console → Setup → App signing → **Upload key certificate**:

   `53:77:95:53:24:F0:13:E6:1D:AC:47:45:5B:1C:00:E6:34:E3:3C:D5:89:9E:37:57:42:13:4A:9B:B4:8A:33:3C`
3. **Create the release.** Play Console → Testing → Closed testing → (track) → Create release. Upload `pettxo-1.0.5+24-release.aab` and check that it shows **versionCode 24**, versionName **1.0.5**.
4. Paste the release notes, review, and roll out to the closed track only.

**Play review time.** Google Play reviews closed-testing releases too. The release can stay "In review" for **a few hours up to several days**, especially for an app's first releases or after policy-relevant changes such as reporting or user-generated content. Testers only see 1.0.5 after review completes. Plan the smoke tests on 1.0.5 for later. The backend deploy does not depend on it, because the live build 23 is what runs against the new backend in the meantime.

**Draft release notes for testers (en-IN):**

```
Pettxo 1.0.5 (closed testing)
- Report users and content: report a profile, post, service, review or chat directly from the app.
- Blocking: the Block option is visible but switched off for this test ("Blocking temporarily unavailable"). Please check that this message is clear and that "Report User" still works from it.
- Safety and reliability improvements to chat, follows, likes, comments, bookings and payments.
Please test: login, feed, likes/comments, follow, chat (text and photos), service browsing, booking requests, and reporting. Do not make real payments unless asked.
```

**Blocking-disabled message (fixed in `9ce090a`).** With blocking disabled, the dialog shows "Blocking isn't available yet. If you feel unsafe, you can report this user and our team will review it." with Report User and Contact Support. The 3C-1 copy issue is resolved in this AAB.
