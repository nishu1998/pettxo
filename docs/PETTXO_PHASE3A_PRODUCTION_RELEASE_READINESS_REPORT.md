# PETTXO — SIMPLIFIED PHASE 3A PRODUCTION RELEASE READINESS REPORT

Prepared: 2026-11-16 (Asia/Kolkata)

Status vocabulary used below:

- **Local verified**: inspected or executed against local source/emulators.
- **Proposed**: prepared for later approval; not executed against production.
- **Previously production-observed**: read-only evidence collected before Phase 3A; not rechecked in this phase.
- **Not verified**: requires an explicitly approved production or console check.

No production Firestore access, migration, Firebase/Hosting deployment, Git stage/commit/push, release build/upload, live payment, user mutation, signing change, blocking activation, or mandatory-update action was performed in Phase 3A.

## 1. Verified current source state

**Local verified**

- Main repository: `/Users/nishantgautam/development/pettexo`
  - Branch: `chore/reporting-source-sync`
  - HEAD: `1652aac6732273b945843a418b3273a88109ab42`
  - Staged files: none
  - Before adding this report: 51 modified tracked paths and 21 untracked paths.
- Admin repository: `/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard`
  - Branch: `chore/admin-reporting-compatibility`
  - HEAD: `3c87df109d7cc5d9beb8467b241897e8168e66b5`
  - Staged files: none; untracked files: none; ten modified tracked paths.
- Root and Admin `CLAUDE.md`: absent.
- Stage 0M moderation, Stage 1A booking-aware blocking, Stage 1B cross-feature enforcement, Stage 1C Flutter UI, Stage 1D reporting/Admin integration, Phase 2 migration utilities, activation gate, and Rules were inspected in their actual local paths.
- Unrelated iOS, Admin finance, offer-wall, versioning, and documentation work remains preserved. No reset or cleanup was performed.

**Previously production-observed**

- A prior read-only Functions inventory found 139 active deployed functions, in `asia-south1`, on Node.js 22. That observation was not refreshed in Phase 3A.
- Existing production reporting source matched the old repository HEAD at the time of that observation. All accumulated local changes remain undeployed.

## 2. Local development status

**Local verified**

- Added a fully read-only historical relationship audit API and an operator wrapper:
  - `functions/src/blocking/historicalRelationshipMigration.ts`
  - `functions/scripts/read_only_relationship_audit.js`
- Replaced caller-declared migration totals with independent full traversal, source classification, evidence-to-guard reconciliation, migration version/run checks, SHA-256 source fingerprinting, and a second source scan.
- Activation now requires a fresh, independently verified migration record, matching run/version/fingerprint, zero anomalies/mismatches, a matching append-only activation audit, and server-side gate approval.
- Zero-baseline migration does not create guards for harmless settled history. It allows clean accepted-unpaid records because the backend can atomically cancel them, but rejects payment attempts/orders/QR mappings, malformed records, protected bookings, and unresolved financial evidence.
- No migration or activation operator is exported as a public Firebase Function.

## 3. Proposed production data audit

**Proposed; not executed**

The read-only audit performs complete document-ID cursor traversal of bookings, directed blocks, relationship guards, disputes, refunds, payout readiness, financial reconciliation, and manual settlement obligations. Booking classification also checks payment-attempt subcollections, Razorpay order mappings, QR mappings, the canonical backend state machine, dispute windows, no-show/financial states, and multi-day canonical bookings.

Required production output:

| Production metric | Result |
|---|---:|
| Total historical booking count | **Not verified** |
| Currently protected paid bookings | **Not verified** |
| Accepted-unpaid bookings | **Not verified** |
| Bookings with uncertain payment state | **Not verified** |
| Open disputes | **Not verified** |
| Pending refunds | **Not verified** |
| Other protected financial obligations | **Not verified** |
| Existing directed blocks | **Not verified** |
| Existing relationship guards | **Not verified** |
| Inconsistent historical block/booking pairs | **Not verified** |
| Records requiring manual review | **Not verified** |

Synthetic emulator proof used one harmless settled booking and one directed block. Before reconciliation it reported one booking, zero protected/accepted/uncertain/financial exceptions, one block, zero guards, one inconsistency, and one manual-review record. After block reconciliation it reported one guard and zero inconsistencies/manual-review records. These are fixture counts, not production counts.

After explicit approval, use a dedicated service identity limited to `datastore.entities.get` and `datastore.entities.list`, build locally, then run:

```bash
cd /Users/nishantgautam/development/pettexo/functions
npm run build
GOOGLE_APPLICATION_CREDENTIALS=/secure/path/pettexo-read-only-audit.json \
  node scripts/read_only_relationship_audit.js \
  --project pettexo-d9409 --confirm-read-only
```

Run it twice, retain both JSON outputs, compare fingerprints/counts, and stop if they differ. The command has not been run against production.

## 4. Decision tree: minimal versus exceptional migration

**Proposed**

1. Keep blocking disabled.
2. Run and independently review the approved read-only audit.
3. If protected/uncertain/malformed/financial/conflict counts are all zero:
   - reconcile only existing directed blocks;
   - independently verify all block evidence and clean accepted-unpaid records;
   - record the zero-protected baseline and source fingerprint;
   - activate only within the 15-minute verification validity window.
4. If any exception exists:
   - do not activate;
   - backfill only affected relationship pairs;
   - preserve all booking/payment/block evidence;
   - resolve or explicitly review anomalies;
   - rerun full traversal and independent verification.

No historical booking is deleted and no old block is erased in either path.

## 5. Live-traffic booking safety

**Local verified**

- New booking creation and acceptance read/write the canonical relationship guard in the same transaction-conflict boundary.
- Razorpay order creation, QR payment creation, payment verification/persistence, webhook persistence, and reconciliation use relationship checks/guard mutations.
- A block transaction and a protected payment transition cannot both commit across the same relationship boundary.
- Blocking creation defaults disabled, while booking and payment operations remain available.
- Clean accepted-unpaid bookings remain cancellable without creating refunds; any persisted payment attempt/order/QR mapping fails closed for manual reconciliation.
- Existing directed blocks are read in both directions, so historical blocks remain effective even before guard reconciliation.
- Updated Rules prevent old clients from creating/deleting direct block documents. Older booking/payment clients continue through the existing server Functions.

**Proposed barrier**

Deploy guarded booking/payment Functions before auditing. Then deploy blocking callables with the gate disabled, followed by Rules. The verifier performs two scans and issues a 15-minute activation lease. New protected traffic is still accounted for by transactional guards; a protected or uncertain audit state prevents zero-baseline verification. No broad service outage or maintenance window is required.

## 6. Migration verifier improvements

**Local verified**

- The verifier accepts no processed totals from a caller.
- It independently paginates all booking and block sources to completion.
- Evidence binds source ID, source update time, pair key, classification, run ID, and migration version.
- Marker count must exactly equal required evidence count.
- Guard state must match directed-block/protected evidence.
- A second scan must match the first fingerprint and counts.
- Anomalies, mismatches, changed evidence, skipped records, and concurrent source changes fail closed.
- Verification stores a derived fingerprint and expires after 15 minutes for activation purposes.
- Emulator coverage validates resumption, idempotency, reconciliation, malformed/legacy records, payment uncertainty, harmless-history minimization, and concurrent accepted-unpaid traffic.

## 7. Blocking activation-gate verification

**Local verified**

- Default disabled and missing metadata: rejected.
- Failed/incomplete migration or mismatched run: rejected.
- Missing evidence/version/fingerprint: rejected.
- Nonzero anomaly/mismatch: rejected.
- Expired verification lease: rejected.
- Client activation or migration writes: denied by Rules.
- Legacy direct block create/update/delete: denied by Rules.
- Activation requires matching rollout, migration, and append-only audit documents.
- Deactivation is append-only/audited, clears the active fingerprint/audit pointer, and immediately restores disabled behavior.
- Flutter does not directly write block/guard/rollout state; backend callables remain authoritative.

## 8. Complete Function deployment inventory

All rows target `asia-south1` / Node.js 22. “Existing” is based on the previous production inventory; “New” means absent then. Every required row differs locally and is safe to deploy while blocking is disabled. `F` means Firestore Rules dependency, `S` Storage Rules dependency, and `G` relationship-guard dependency.

| Export | Source module | Prod state | Dependencies | Old Android / rollback |
|---|---|---|---|---|
| `createBookingRequestV3` | `booking/bookingV3FlowFunctions.ts` | Existing | G,F | Compatible; rollback only before any block activation |
| `acceptBookingRequestV3` | same | Existing | G,F | Compatible; rollback only before activation |
| `createRazorpayPaymentOrderV3` | same | Existing | G,F | Compatible; rollback only before activation |
| `createBookingQrPaymentV3` | same | Existing | G,F | Compatible; rollback only before activation |
| `previewBookingPaymentPricingV3` | same | Existing | G,F | Compatible; additive denial for blocked pairs |
| `verifyBookingPaymentV3` | same + `paymentOrchestrationV3.ts` | Existing | G,F | Compatible; never rollback alone after guarded writes |
| `razorpayWebhook` | same + payment orchestration | Existing | G,F | Client-independent; preserve webhook compatibility |
| `reconcileBookingPaymentsV3` | same + payment orchestration | Existing | G,F | Scheduler; rollback with payment group only |
| `expireAwaitingPaymentsV3` | same | Existing | G,F | Scheduler; deploy with booking group |
| `blockUserV1` | `blocking/userBlockingFunctions.ts` | New | G,F,gate | Old apps do not call it; disabled until activation |
| `unblockUserV1` | same | New | G,F | New UI only; preserve evidence on rollback |
| `getUserRelationshipStateV1` | same | New | G,F | New UI only; read-only |
| `submitReport` | `moderation/reportFunctions.ts` | Existing | F | Service/review schema remains compatible; user is additive |
| `enqueueReportModeration` | `legacyFunctions.ts` + `reportContract.ts` | Existing | F | Existing targets remain compatible |
| `resolveReport` | `moderation/reportModerationFunctions.ts` | New | F | Admin-only checks; remove UI first if rolled back |
| `rejectReport` | same | New | F | Same |
| `hideReportedService` | same | New | F | Same; transactional audit preserved |
| `hideReportedReview` | same | New | F | Same; transactional audit preserved |
| `getChatImageMessagingCapability` | `chat/chatImageFunctions.ts` | Existing | G,F,S | Compatible; blocked pairs now disabled |
| `sendChatImageMessage` | same | Existing | G,F,S | Compatible; historical media preserved |
| `startProviderChat` | `legacyFunctions.ts` | Existing | G,F | Compatible; blocked pairs denied |
| `startDirectUserChat` | same | Existing | G,F | Compatible; blocked pairs denied |
| `sendChatMessage` | same | Existing | G,F | Compatible; blocked pairs denied transactionally |
| `markChatDelivered` | same | Existing | G,F | Compatible; blocked history remains readable |
| `markChatRead` | same | Existing | G,F | Compatible; blocked history remains readable |
| `setFollowState` | `social/followFunctions.ts` | Existing | G,F | Legacy direct creates are also Rules-protected |
| `getProfileFollowCounts` | `legacyFunctions.ts` | Existing | G,F | Compatible; cross-block profile access denied |
| `createSocialNotification` | `legacyFunctions.ts` | Existing | G,F | Compatible; blocked notifications suppressed |
| `sendPushForNotification` | `legacyFunctions.ts` | Existing | G,F | Trigger safely skips blocked relationships |

Reviewed but no handler change requiring deployment: `getFollowState` and `syncProfileFollowCounts`. No new composite index is required by the added document-ID scans, direct document reads, or single-field equality queries. Validate the final Firebase deploy planner before any selective deployment. Do not use a broad Functions deployment.

## 9. Firestore/Storage Rules rollout plan

**Local verified; proposed rollout**

1. Selectively deploy guarded booking/payment Functions.
2. Deploy reporting/moderation and chat/social Functions.
3. Deploy new blocking callables with activation still disabled.
4. Deploy Firestore Rules, which:
   - disable client block mutations;
   - make guards/rollout/migration/evidence backend-only;
   - enforce bilateral blocks on follow/like/comment/share interactions;
   - require moderation Functions for report/review mutations.
5. Deploy Storage Rules, which deny new chat-media uploads across a bilateral block while preserving reads/history.
6. Rerun legacy-client smoke tests before any audit/activation.

Emulator tests confirm legacy follow creation remains constrained, ordinary unblocked social/chat writes work, old service/review report creation remains supported, blocked cross-feature writes fail, and chat-media history is preserved. Rules were not deployed.

## 10. Git source-preservation plan

**Local verified / proposed commands**

Use `git diff --check` before every commit and inspect `git diff --cached`. Do not use `git add .`.

Logical review groups:

1. Secure moderation: `functions/src/moderation/reportModeration*.ts`, moderation exports, and moderation tests.
2. Booking/blocking guards: booking state/payment/flow/schema/contract files, `relationshipGuard.ts`, `userBlocking*.ts`, `blockingFunctions.ts`, blocking export, and booking/blocking tests.
3. Chat/social enforcement: chat image, selected `legacyFunctions.ts` hunks, follow Functions, and chat/social tests.
4. Flutter blocking UI: `lib/features/blocking/**`, `test/features/blocking/**`, plus blocking-only hunks in profile/chat/discovery files.
5. Canonical user reporting: report contract/submission, Flutter report repository/tests, and reporting-only profile/chat hunks.
6. Admin reporting: the four `lib/test/features/reports` paths in the Admin repository.
7. Migration/activation controls: `historicalRelationshipMigration.ts`, `blockingActivationGate.ts`, read-only audit script, and migration/gate test hunks. Groups 2 and 7 are coupled and must be reviewed consecutively; neither alone is a deployment candidate.
8. Rules: `firestore.rules`, `storage.rules`, and their Rules tests.
9. iOS: only `ios/**`, `pubspec.yaml`, and `docs/IOS_APP_STORE_CHECKLIST.md` after removing local key material.
10. Admin finance/offer wall: the six non-report Admin paths listed below, separately.

Representative safe command pattern:

```bash
git add <exact non-overlapping paths>
git add -p functions/src/index.ts functions/src/legacyFunctions.ts \
  lib/features/profile/presentation/screens/profile_screen.dart \
  lib/features/messages/presentation/screens/chat_detail_screen.dart
git diff --cached --check
git diff --cached
# Stop for approval before: git commit
```

Admin report group:

```bash
git -C '/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard' add \
  lib/features/reports/data/admin_reports_repository.dart \
  lib/features/reports/models/admin_report.dart \
  lib/features/reports/presentation/reports_page.dart \
  test/features/reports/report_compatibility_test.dart
```

Admin unrelated group (do not mix with reporting):

```bash
git -C '/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard' add \
  lib/features/finance/models/admin_finance_records.dart \
  lib/features/finance/presentation/cancellation_refunds_page.dart \
  test/core/services/admin_functions_service_test.dart \
  test/features/finance/presentation/cancellation_refunds_page_test.dart \
  test/features/offer_wall/data/offer_wall_campaign_service_test.dart \
  test/features/offer_wall/models/offer_wall_audience_test.dart
```

No staging, commit, or push was performed.

## 11. Android release checklist

**Local verified**

- Local app version: `1.0.4+23`; application ID: `com.pettexo.app`.
- Flutter tests pass. Backend/Rules compatibility coverage includes old booking/payment paths and constrained legacy social/report operations.
- Gradle wrapper JAR and launcher scripts are ignored, which is a reproducible-build blocker until intentionally corrected and reviewed.

**Not verified / proposed**

- Verify the current Play Console production version code; choose a new code strictly greater than live (do not assume 23 is sufficient).
- Produce a closed-test build only after source freeze, backup, selective backend/Rules rollout, and real-device regression.
- QA blocking/reporting, booking/payment/QR/Razorpay, notifications, chat media, account deletion, upgrade from the current store build, and rollback.
- Use staged production rollout with monitoring. Do not enable mandatory update until the backend is compatible with both old and new clients and rollout health is accepted.
- No production AAB was built or uploaded.

## 12. iOS App Store readiness checklist

**Local verified**

- Bundle ID and Firebase plist agree on `com.pettexo.app`; iOS deployment target is 15.0.
- Google Maps is wired through `MAPS_API_KEY`, but the committed value is intentionally empty and requires ignored `Local.xcconfig` on the release machine.
- Location and photo-library privacy strings exist.
- In-app account deletion exists under Account & Security.
- CocoaPods lockfile exists locally; signing credentials were not changed.

**Remaining before TestFlight**

- Set Apple team/provisioning in Xcode; `DEVELOPMENT_TEAM` is currently unset.
- Add Push Notifications entitlement, remote-notification background mode, APNs key in Firebase, and physical-device notification validation.
- Add Firebase Phone Auth reCAPTCHA fallback URL scheme and reviewer test phone/OTP.
- Add `ITSAppUsesNonExemptEncryption = NO` if legal review confirms standard exempt encryption only.
- Decide and configure iPhone-only support; project currently declares device families `1,2`.
- Add required UPI query schemes if Razorpay flows depend on external apps.
- Verify deep/universal links, App Privacy answers, screenshots, review notes/demo account, privacy/terms/support URLs, and deletion behavior.
- Test Maps, OTP, APNs, Razorpay, uploads, camera/photo behavior, and account deletion on a physical iPhone; then prepare TestFlight.
- No archive or App Store submission was performed.

## 13. Test results

**Local verified**

| Validation | Result |
|---|---|
| TypeScript build | Pass |
| Focused migration + activation Firestore emulator | 13/13 pass |
| Broad Firestore + Storage emulator matrix | 191/191 pass (matching project-ID harness) |
| Full backend non-emulator run | 1,088 total: 923 pass, 17 fail, 148 skip |
| Previous backend baseline | 1,086 total: 923 pass, 17 fail, 146 skip |
| Flutter app | 888/888 pass |
| Flutter analyzer | Same six known booking-screen findings (four info, two warning) |
| Admin Dashboard | 271/271 pass |
| Admin analyzer | No issues |
| Main/Admin `git diff --check` | Pass |

The backend pass/fail totals are unchanged from baseline; the two additional skipped tests are emulator-gated Phase 3A tests. Focused and broad emulator runs execute those paths successfully. The initial broad Storage run under a mismatched demo project ID failed cross-service lookups; rerunning under the test suite's configured emulator project ID passed completely and did not access production.

## 14. Remaining blockers

1. Every production Firestore audit count is **Not verified**.
2. Production source fingerprint, migration choice, and activation prerequisites are unknown.
3. Changes are uncommitted and not yet independently code-reviewed.
4. Selective Function/Rules deployment plans have not been executed or verified in production.
5. The 17 known backend failures remain in the non-emulator baseline.
6. Play Console live version and Android real-device upgrade behavior are not verified.
7. Android Gradle wrapper files are ignored.
8. iOS signing, APNs, entitlements, Phone Auth URL scheme, Maps release key, export compliance, device-family decision, physical-device QA, and App Store metadata remain incomplete.
9. No production monitoring/rollback rehearsal has occurred.

## 15. Decision

**CONDITIONAL GO for source freeze, independent review, checksum backup, and a later selectively approved deployment preparation.**

**NO-GO for production blocking activation, migration, Rules/Functions deployment, Android production release, or iOS submission at this time.** The next production-facing step must be a separately approved, read-only Firestore audit using least-privilege credentials. Its actual results determine the minimal or exceptional migration path.
