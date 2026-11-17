# Pettxo Phase 3C: production deployment record

**Deployed:** 17 November 2026 (IST), owner-run, Firebase project `pettexo-d9409`.
**Recorded:** Phase 3C-6, from the owner's account of the deploy plus local git verification. No production system was read while writing this record. Times are approximate.

Related documents:
- `docs/PETTXO_PHASE3C_DEPLOYMENT_RUNBOOK.md`: the plan, commands and rollback procedure.
- `docs/PETTXO_PHASE3C_DEPLOY_DAY_CHECKLIST.md`: the owner checklist.
- `~/PettxoReleaseBackups/reports/PETTXO_PHASE3C4_REPORT.md`: the Storage Rules incident.

## Source commits

| Ref | Full SHA | Used for |
|---|---|---|
| `e8f97f3` | `e8f97f32db0c293e441cc51f343d51d5fdf83587` | Firestore Rules deploy |
| `6f576f1` | `6f576f135ee873157c484d5654422228c11d4a0f` | All Functions waves |
| `2e7a67a` | `2e7a67a65e33cc9ede4a53e16e61d9b9ef906a02` | AAB 1.0.5+24 |
| Admin Dashboard `d07df16` | `d07df166a73503a2da4bf95bc0ec1dca799717ca` | `hosting:admin` |
| Base (rollback) | `1652aac6732273b945843a418b3273a88109ab42` | Rollback reference |

The three app commits are all on `release/android-1.0.5-closed-testing`. Verified locally:
- **Firestore Rules:** `firestore.rules` is byte-identical at `9ce090a`, `e8f97f3`, `6f576f1` and `2e7a67a`.
- **Functions source:** `functions/src`, `functions/package.json`, `functions/package-lock.json` and `firebase.json` are identical at `9ce090a`, `6f576f1` and `2e7a67a`. So `2e7a67a` (the AAB commit) needs no backend redeploy.
- **Storage Rules:** `storage.rules` at `6f576f1` and `2e7a67a` is byte-identical to base `1652aac`, to `main`, and to the saved previous-live copy.

## Timeline (17 Nov 2026, IST)

| Time | Action | Result |
|---|---|---|
| Before 05:00 | Saved the live Rules to `~/PettxoReleaseBackups/rules-live-2026-11-17/` | Firestore console version-history entry for the previous Rules: **"Oct 20, 2026 1:57 AM"** |
| ~05:00 | **Firestore Rules** deployed from `e8f97f3` | Live and working |
| ~05:00 | **Storage Rules** deployed from the same commit | **Chat photos failed** with "do not have permission" |
| After 05:00 | Owner **rolled back the Storage Rules** in the console to the previous version | Chat photos work again. The Storage Rules deploy is **cancelled** for this release. |
| ~06:10 | **Functions Wave 1** (9 updates) from `6f576f1` | OK |
| ~06:20 | **Functions Wave 2** (2 updates, 4 creates) | Code deployed, but the CLI could not set the invoker on the 4 new functions; fixed manually (see below) |
| Later | **Waves 3, 5a, 5b, 5c, 5d** (56 updates) | OK |
| Later | **Wave 4** (3 creates) | Same invoker fix applied; verified |
| Later | **Admin Dashboard** `hosting:admin` from the prebuilt clean worktree at `d07df166` | Live |
| Later | **AAB 1.0.5+24** (built from `2e7a67a`) uploaded to Play **closed testing** | Submitted for review |

### Storage Rules incident (Phase 3C-4)

**Cause.** The new chat-media `create` rule read three Firestore documents: `chats/{id}`, `userBlocks/{a_b}` and `userBlocks/{b_a}`. Production Storage Rules may access at most **two** Firestore documents per evaluation, so every chat-photo upload was denied. The Storage emulator does not enforce that limit, so the tests passed locally.

**Fix and safeguard.** Commit `d1c5c85` restored `storage.rules` to base. It also added a static test that fails any Storage rule reaching more than two Firestore documents, and an end-to-end chat-photo emulator test.

**Block enforcement for chat images.** The server already refuses chat images between blocked users, in `getChatImageMessagingCapability` and `sendChatImageMessage` (Wave 3).

### Wave details

| Wave | Functions | Operation |
|---|---|---|
| 1 | `createBookingRequestV3`, `acceptBookingRequestV3`, `createRazorpayPaymentOrderV3`, `createBookingQrPaymentV3`, `previewBookingPaymentPricingV3`, `verifyBookingPaymentV3`, `razorpayWebhook`, `reconcileBookingPaymentsV3`, `expireAwaitingPaymentsV3` | 9 updates |
| 2 | `submitReport`, `enqueueReportModeration` | 2 updates |
| 2 | `resolveReport`, `rejectReport`, `hideReportedService`, `hideReportedReview` | 4 **creates** (invoker fix applied) |
| 3 | 11 chat, social and notification functions (runbook §2) | 11 updates |
| 4 | `blockUserV1`, `unblockUserV1`, `getUserRelationshipStateV1` | 3 **creates** (invoker fix applied) |
| 5a–5d | 45 schema-consistency functions (13 + 12 + 13 + 7, runbook §2) | 45 updates |
| **Total** | **74** | **67 updates, 7 creates** |

### New functions and the invoker policy (domain-restricted sharing)

**What happened.** For each of the 7 new functions the CLI created the function but failed to grant public invoke access. Granting it means adding `allUsers` as Cloud Run invoker, and the organisation policy `iam.allowedPolicyMemberDomains` (domain-restricted sharing) forbids that principal. Until this is fixed, Cloud Run rejects every call with HTTP 403 before the code runs.

**The fix.** The owner disabled the Cloud Run invoker IAM check on each new function, by either route:
- **Console:** Cloud Run → the function's service → Security → Authentication → **Allow public access**.
- **CLI:** `gcloud run services update <service> --region=asia-south1 --no-invoker-iam-check`.

**Verification.** Unauthenticated calls return **HTTP 401**: the request reaches the function, which rejects the missing Firebase Auth token. A 403 would mean Cloud Run is still blocking.

**Why this is safe.** It is the same exposure as the standard `invoker: "public"` setting the code declares. Every one of the 7 still checks Firebase Auth itself and returns `unauthenticated` without a signed-in user: the blocking callables through `requireUid`, the moderation callables through `moderateReportData`. The moderation callables also require an admin.

**Updates were unaffected.** The 67 updated functions already had their invoker set.

The permanent procedure is in runbook §2, "New Cloud Functions under domain-restricted sharing".

## What is live now

| Component | Live version | Notes |
|---|---|---|
| Firestore Rules | **New**: `e8f97f3` (= `9ce090a` = `6f576f1` = `2e7a67a`) | Deployed ~05:00 |
| Storage Rules | **Previous** version (= base `1652aac` = repo `storage.rules` at `d1c5c85` and later) | New version deployed, then rolled back; deploy cancelled |
| Firestore indexes | Unchanged | No index deploy in this release |
| Cloud Functions (74 in scope) | `6f576f1` (code-identical to `2e7a67a`) | 67 updated, 7 created; Gen 2, `asia-south1`, Node 22 |
| Invoker on the 7 new functions | Invoker IAM check **disabled** | Verified with 401 on unauthenticated calls |
| Other functions (not in the 74) | Unchanged from before the deploy | Not redeployed |
| Blocking activation gate | **OFF**: no `_rollouts/userBlockingV1` document | Block creation is refused; `unblockUserV1` and the "Blocked accounts" screen work with the gate off (empty list) |
| Admin Dashboard | `d07df166`, hosting target `admin`, site `pettxo-admin` (admin.pettxo.com) | Replaces the old Dashboard (`93503bd`), whose report-status action broke under the new Firestore Rules |
| Main site hosting (default target) | Unchanged | Not part of this release |
| Android, Play production | Build 23 (unchanged) | |
| Android, Play closed testing | **1.0.5 (24)**, AAB SHA-256 `0724e335fbc2b9934d8ad97cd46ffb3fa2a56f037f0becaa235db26cbb104204` | In review. Upload certificate SHA-256 `53:77:95:53:24:F0:13:E6:1D:AC:47:45:5B:1C:00:E6:34:E3:3C:D5:89:9E:37:57:42:13:4A:9B:B4:8A:33:3C`. Includes the Settings → Account → "Blocked accounts" entry. |

## Post-deploy observations

**Bots and scanners on the new revision URLs.** Automated `GET` requests (Windows Chrome user agents) hit the new Cloud Run revision URLs and log 400/404 errors.
- **Harmless:** callables accept only `POST` with a Firebase payload.
- **Action:** ignore these when scanning logs for real errors.

**`pauseServicesForExpiredProviderVerification` fails every hour.**
- It was already failing before the deploy, and it is not among the 74 deployed functions, so it is **pre-existing and unrelated**.
- **Action:** investigate (open item 1).

**`firebase-functions` outdated warning.** The CLI warns that the `firebase-functions` SDK is outdated.
- The upgrade was deferred so the release did not change the runtime SDK (open item 2).

## Rollback references

Full procedure: runbook §5.

**Firestore Rules**
- Saved previous live copy: `~/PettxoReleaseBackups/rules-live-2026-11-17/firestore.rules`, SHA-256 `1d838806c4da362bf110e1e3a770ec30fdae7799c82ff9ca6fbdf4828c8a68a0`. It equals base `1652aac` and `main`.
- Console version history: **"Oct 20, 2026 1:57 AM"**.
- These saved files must never be modified.

**Storage Rules**
- **Nothing to roll back:** production already runs the previous version.
- Saved copy: `~/PettxoReleaseBackups/rules-live-2026-11-17/storage.rules`, SHA-256 `8e47f9d2827917dca9ff5679f51b61cbd06142c5d3ba1dca12b13f24aaaa45d0`. It equals the repository file.
- **Never deploy the `storage.rules` from `release/phase3b1-blocking-reporting-2026-11-16`** (`c74fbd4`). That branch still holds the version that broke chat photos.

**Functions (67 updated)**
- Redeploy from base `1652aac` with the exact list in runbook §5.
- These are updates, so the invoker policy does not affect them.

**Functions (7 created)**
- Delete them, as in runbook §5. The new Dashboard's report actions stop working.
- If they are ever recreated, apply the invoker fix again.

**Admin Dashboard**
- Firebase Hosting → site `pettxo-admin` → release history → roll back to the previous release (the old `93503bd` Dashboard).
- Its report-status action stays broken under the new Firestore Rules.

**Android**
- Play Console: halt the 1.0.5 (24) closed-testing release.
- Superseded AABs are in `~/PettxoReleaseBackups/builds/1.0.5+24/superseded-3C1/` and `superseded-3C2/`. **Never upload them.**

**What rollback does not undo:** documents written by the new code, such as open relationship guards, canonical reports and notifications. See runbook §5.

## Open items

1. **Investigate the hourly `pauseServicesForExpiredProviderVerification` failures** (pre-existing). Find the error in the logs and fix it in a separate change.
2. **Upgrade `firebase-functions`** (deferred). Do it as its own release, with the full emulator suite and a staged deploy.
3. **Phase 3B-4: blocking activation.**
   - Run the production migration and audit, then write the activation documents through the audited transition.
   - Only then is `_rollouts/userBlockingV1` enabled. All 45 Wave 5 functions are already live, as activation requires.
   - Any **new** function created in that phase needs the invoker fix.
4. **Merge the release branches into `main`.**
   - App repo: merge `release/android-1.0.5-closed-testing`. It contains all of `release/phase3b1-blocking-reporting-2026-11-16` plus the fixes. Do **not** merge the phase3b1 branch on its own: it has the incident `storage.rules` and lacks the legacy-post Firestore Rules fix.
   - Admin Dashboard: merge `release/phase3b1-admin-reporting-2026-11-16`.
   - Both merges are fast-forwards (Phase 3C-6 git report).
5. **iOS work outstanding.** The main working tree holds uncommitted iOS changes (Xcode project, Podfile, xcconfigs, `pubspec.yaml`, `docs/IOS_APP_STORE_CHECKLIST.md`). These were deliberately left out of this release and still need their own branch, review and build.
6. **Promote 1.0.5 (24)** from closed testing to production after review and tester feedback. Gate that on the open items above as the owner decides.
