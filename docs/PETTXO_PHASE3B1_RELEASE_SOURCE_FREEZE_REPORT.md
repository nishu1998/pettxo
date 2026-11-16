# PETTXO PHASE 3B-1 — RELEASE SOURCE FREEZE REPORT

Prepared: 2026-11-16 (Asia/Kolkata)

Scope: local source preservation and release preparation only. No production Firebase access, deployment, migration, activation, Git stage/commit/push, store build, or upload was performed.

## 1. Verified Phase 3A findings

- No `CLAUDE.md` exists in either repository.
- The complete Phase 3A report was read and checked against the source.
- The blocking implementation is server-gated and disabled when rollout metadata is absent.
- Booking creation/acceptance and payment order/QR/finalization paths use the canonical relationship transaction boundary.
- The historical verifier independently traverses sources, checks run/version/evidence/guards, performs a second scan, fingerprints the source, rejects anomalies/mismatches, and issues a 15-minute activation lease.
- Firestore Rules deny client mutations of blocks, relationship guards, rollout/migration/evidence records, reports, and moderated reviews as applicable.
- Storage Rules preserve historical chat media reads and deny new uploads across either block direction.
- Existing Android booking/payment calls remain server-based. Old direct block writes will stop working after the Rules release; that is intentional and requires the new callable-backed client for blocking UX.
- Production Firestore remains unaudited. The migration scenario and activation eligibility are unknown.
- Android Gradle wrapper launchers/JAR are ignored, so a clean-clone Android build is not yet reproducible.
- iOS remains blocked on signing/team, APNs entitlement/key, remote-notification mode, Phone Auth URL scheme, release Maps key, device-family decision, export compliance, physical-device testing, and App Store metadata.

## 2. Source and Git state

### Main repository

- Path: `/Users/nishantgautam/development/pettexo`
- Branch: `chore/reporting-source-sync`
- HEAD: `1652aac6732273b945843a418b3273a88109ab42`
- Index: empty
- Before this report: 51 modified tracked paths and 22 untracked paths.
- One untracked editor/log artifact, `profile_tour_final_test.log~`, is not release source and must not be staged.

### Admin Dashboard

- Path: `/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard`
- Branch: `chore/admin-reporting-compatibility`
- HEAD: `3c87df109d7cc5d9beb8467b241897e8168e66b5`
- Index: empty; untracked paths: none.
- Ten modified tracked paths: four reporting paths and six unrelated finance/offer-wall paths.

## 3. Backup verification

The Phase 3A backup exists at:

`/Users/nishantgautam/PettxoReleaseBackups/phase3a-2026-11-16-001`

Verification performed:

- `shasum -a 256 -c SHA256SUMS`: every artifact passed.
- Current main binary patch equals `main-working-tree.patch` byte-for-byte.
- Current whitelisted untracked list equals `main-untracked-files.txt`.
- Every archived untracked source file equals its current workspace file byte-for-byte after extraction.
- Current Admin ten-file binary patch equals `admin-working-tree.patch` byte-for-byte.
- Both index patches are correctly empty.
- The shareable archive excludes `.env*`, keystores, `Local.xcconfig`, generated logs, caches, and the `profile_tour_final_test.log~` artifact.

Important source is recoverable from the Phase 3A backup. After this report was added, a new immutable snapshot was created and checksum-verified at:

`/Users/nishantgautam/PettxoReleaseBackups/phase3b1-2026-11-16-001`

## 4. Exact commit groups

Recommended commit order is designed to keep practical checkpoints buildable. Categories are all preserved, but canonical reporting must precede Flutter blocking UI, and the activation gate must accompany the blocking core.

### Main commit 1 — Admin moderation backend

Message: `feat(moderation): secure report resolution workflows`

Paths:

- `functions/src/moderation/moderationFunctions.ts`
- `functions/src/moderation/reportModeration.ts`
- `functions/src/moderation/reportModerationFunctions.ts`
- `functions/test/reportModeration.test.js`
- `functions/test/reportModerationEmulator.test.js`
- moderation-only hunks in `functions/test/functionExports.test.js`

The Rules test stays with the Firestore Rules commit.

### Main commit 2 — Canonical user reporting

Message: `feat(reporting): add canonical user safety reports`

Paths:

- `functions/src/moderation/reportContract.ts`
- `functions/src/moderation/reportSubmission.ts`
- `functions/test/reportContract.test.js`
- `functions/test/reportContractEmulator.test.js`
- `functions/test/reportSubmission.test.js`
- `functions/test/reportSubmissionEmulator.test.js`
- `lib/features/moderation/data/repositories/report_repository.dart`
- `test/features/moderation/data/report_repository_test.dart`
- `test/features/moderation/presentation/report_sheet_test.dart`

This creates user-report support without yet exposing the blocking UI entry points.

### Main commit 3 — Blocking and booking guards

Message: `feat(blocking): enforce booking-safe relationship guards`

Paths:

- `functions/src/blocking/blockingActivationGate.ts`
- `functions/src/blocking/blockingFunctions.ts`
- `functions/src/blocking/relationshipGuard.ts`
- `functions/src/blocking/userBlocking.ts`
- `functions/src/blocking/userBlockingFunctions.ts`
- `functions/src/booking/application/bookingStateMachine.ts`
- `functions/src/booking/application/paymentOrchestrationV3.ts`
- `functions/src/booking/bookingV3FlowFunctions.ts`
- `functions/src/booking/domain/bookingContracts.ts`
- `functions/src/booking/schema/bookingDocumentV3.ts`
- `functions/src/index.ts`
- `functions/test/bookingLifecycleV3.test.js`
- `functions/test/serviceSlotCoverageEmulator.test.js`
- `functions/test/userBlocking.test.js`
- `functions/test/userBlockingEmulator.test.js`
- blocking-only hunks in `functions/test/functionExports.test.js`

The activation gate is placed here because `userBlocking.ts` imports it; separating it would create a broken intermediate commit. Historical audit/migration operators remain in commit 6.

### Main commit 4 — Cross-feature backend security

Message: `feat(security): enforce bilateral blocks across chat and social`

Paths:

- `functions/src/chat/chatImageFunctions.ts`
- `functions/src/legacyFunctions.ts`
- `functions/src/social/followFunctions.ts`
- `functions/test/blockingChatEmulator.test.js`
- `functions/test/chatImageFunctionsEmulator.test.js`
- `functions/test/followFunctionsEmulator.test.js`

Rules-specific coverage remains in commit 7 or 8.

### Main commit 5 — Flutter blocking UX

Message: `feat(flutter): add authoritative blocking and reporting UX`

Paths:

- `lib/features/blocking/**`
- `test/features/blocking/**`
- `lib/features/explore/data/explore_viewer_context_repository.dart`
- `lib/features/explore/presentation/screens/explore_screen.dart`
- `lib/features/home/data/home_feed_repository.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/messages/data/repositories/chat_repository.dart`
- `lib/features/messages/presentation/screens/chat_detail_screen.dart`
- `lib/features/messages/presentation/screens/messages_screen.dart`
- `lib/features/profile/data/repositories/profile_repository.dart`
- `lib/features/profile/presentation/screens/profile_screen.dart`
- `lib/features/profile/presentation/screens/service_detail_screen.dart`
- `lib/features/services/data/repositories/services_repository.dart`
- `lib/features/services/presentation/screens/services_screen.dart`
- `lib/features/settings/presentation/screens/settings_screen.dart`
- `lib/features/social/data/social_post_repository.dart`
- `lib/features/social/presentation/screens/user_list_screen.dart`
- `lib/features/social/presentation/widgets/comment_sheet.dart`

Profile/chat user-report entry points are inseparable from the new blocking UX and rely on commit 2.

### Main commit 6 — Historical audit, migration, and activation verification

Message: `feat(migration): add independently verified blocking readiness audit`

Paths:

- `functions/src/blocking/historicalRelationshipMigration.ts`
- `functions/scripts/read_only_relationship_audit.js`
- `functions/test/historicalRelationshipMigrationEmulator.test.js`
- `docs/PETTXO_PHASE3A_PRODUCTION_RELEASE_READINESS_REPORT.md`
- this Phase 3B-1 report

The operator script is excluded from Firebase deployment by `firebase.json` and is not a public Function.

### Main commit 7 — Firestore Rules

Message: `security(firestore): enforce moderation and bilateral block boundaries`

Paths:

- `firestore.rules`
- `functions/test/blockingCrossFeatureRulesEmulator.test.js`
- `functions/test/firestoreRulesBlockMuteProtections.test.js`
- `functions/test/reportModerationRulesEmulator.test.js`
- `functions/test/userRelationshipGuardRulesEmulator.test.js`

### Main commit 8 — Storage Rules

Message: `security(storage): block new chat media across blocked relationships`

Paths:

- `storage.rules`
- `functions/test/storageRulesChatMedia.test.js`

### Admin commit 1 — Dashboard reporting

Message: `feat(reports): support canonical user moderation records`

Paths:

- `lib/features/reports/data/admin_reports_repository.dart`
- `lib/features/reports/models/admin_report.dart`
- `lib/features/reports/presentation/reports_page.dart`
- `test/features/reports/report_compatibility_test.dart`

### Main unrelated commit — iOS configuration and version

Message: `chore(ios): prepare first App Store build configuration`

Paths:

- `ios/.gitignore`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Profile.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Flutter/Maps.xcconfig`
- `ios/Flutter/Local.xcconfig.example`
- `ios/Podfile`
- `ios/Podfile.lock`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner.xcworkspace/contents.xcworkspacedata`
- `pubspec.yaml`
- `docs/IOS_APP_STORE_CHECKLIST.md`

No real `Local.xcconfig`, signing credential, APNs key, or secret may be staged.

### Admin unrelated commit — Finance and offer-wall tests

Message: `fix(finance): preserve settlement and offer-wall compatibility work`

Paths:

- `lib/features/finance/models/admin_finance_records.dart`
- `lib/features/finance/presentation/cancellation_refunds_page.dart`
- `test/core/services/admin_functions_service_test.dart`
- `test/features/finance/presentation/cancellation_refunds_page_test.dart`
- `test/features/offer_wall/data/offer_wall_campaign_service_test.dart`
- `test/features/offer_wall/models/offer_wall_audience_test.dart`

## 5. Shared-file conflicts

- `functions/test/functionExports.test.js`: moderation names belong to main commit 1; blocking names belong to main commit 3. Use interactive hunk staging and verify the cached diff.
- `lib/features/profile/presentation/screens/profile_screen.dart` and `lib/features/messages/presentation/screens/chat_detail_screen.dart`: blocking and user-report entry points are structurally interwoven. Keep them wholly in main commit 5 after canonical reporting commit 2.
- `lib/features/blocking/presentation/user_safety_dialogs.dart`: blocking failure flows call the canonical user report sheet; it belongs wholly in main commit 5.
- `functions/src/blocking/userBlocking.ts` imports `blockingActivationGate.ts`; keep the gate with the core in main commit 3.
- `historicalRelationshipMigration.ts` imports the blocking classifier; commit 6 must follow commit 3.
- `firestore.rules` contains moderation, block ownership, guard privacy, and social enforcement changes. Keep it atomic in the dedicated Rules commit rather than splitting a security policy file.
- `pubspec.yaml` contains only the `+23` version change and stays with the iOS/version commit.
- Admin reporting and Admin finance/offer-wall changes do not overlap and must remain separate.

## 6. Test results

Phase 3B-1 focused validation:

| Check | Result |
|---|---|
| TypeScript build | Pass |
| Focused backend unit/export suite | 80/80 pass |
| Firestore + Storage emulator suite | 191/191 pass |
| Flutter blocking/reporting suite | 31/31 pass |
| Admin report compatibility suite | 17/17 pass |
| Main `git diff --check` | Pass |
| Admin scoped `git diff --check` | Pass |
| Main `git fsck --no-dangling` | Pass |
| Phase 3A backup/current-source comparison | Pass |

Phase 3A full-suite evidence remains applicable because the current source matched the verified backup before this report was added:

- Flutter 888/888 pass.
- Admin Dashboard 271/271 pass; analyzer clean.
- Full backend: 1,088 total, 923 pass, 17 known failures, 148 emulator skips; unchanged pass/fail baseline.
- Main analyzer: six known booking-screen findings (four info, two warning).

## 7. Release dependency inventory

All listed Functions are `asia-south1`, Node.js 22. Existing/new status comes from the prior read-only inventory and was not re-read from production in Phase 3B-1.

### Booking/payment — update nine existing Functions first

- `createBookingRequestV3`
- `acceptBookingRequestV3`
- `createRazorpayPaymentOrderV3`
- `createBookingQrPaymentV3`
- `previewBookingPaymentPricingV3`
- `verifyBookingPaymentV3`
- `razorpayWebhook`
- `reconcileBookingPaymentsV3`
- `expireAwaitingPaymentsV3`

`expireAwaitingPaymentsV3` is required because it calls the modified reconciliation/finalization path before expiry.

### Reporting/moderation

Existing updates:

- `submitReport`
- `enqueueReportModeration`

New:

- `resolveReport`
- `rejectReport`
- `hideReportedService`
- `hideReportedReview`

### Cross-feature backend security — update existing Functions

- `getChatImageMessagingCapability`
- `sendChatImageMessage`
- `startProviderChat`
- `startDirectUserChat`
- `sendChatMessage`
- `markChatDelivered`
- `markChatRead`
- `setFollowState`
- `getProfileFollowCounts`
- `createSocialNotification`
- `sendPushForNotification`

Reviewed with no handler change requiring deployment: `getFollowState`, `syncProfileFollowCounts`.

### Blocking callables — new

- `blockUserV1`
- `unblockUserV1`
- `getUserRelationshipStateV1`

`blockUserV1` remains fail-closed until a valid rollout, migration record, fingerprint, and activation audit exist. Deploying it does not activate blocking.

### Rules and indexes

- Firestore Rules update is required after the guarded Functions and before activation.
- Storage Rules update is required after chat/security Functions.
- No new composite index is required by the local changes.
- Never roll back guarded booking/payment Functions alone after blocking activation. Deactivate blocking first, then use a coordinated rollback.

Proposed deployment order, not executed:

1. Nine guarded booking/payment Functions.
2. Reporting/moderation Functions.
3. Cross-feature chat/social/notification Functions.
4. Three blocking callables, with gate still disabled.
5. Firestore Rules.
6. Storage Rules.
7. Legacy-client smoke tests.
8. Separately approved production read-only audit and migration decision.
9. Activation only after fresh independent verification.

## 8. Exact safe commit commands

These commands are prepared only. Do not run until approval. Start from the current dirty branches; create release branches before the first staged commit.

### Main release branch

```bash
cd /Users/nishantgautam/development/pettexo
git switch -c release/phase3b1-blocking-reporting-2026-11-16
```

For every main commit use this review envelope:

```bash
git diff --check
git diff --cached --check
git status --short
git diff --cached --stat
git diff --cached
# Only after the cached diff contains exactly one group:
git commit -m '<approved message>'
```

Commit 1:

```bash
git add functions/src/moderation/moderationFunctions.ts \
  functions/src/moderation/reportModeration.ts \
  functions/src/moderation/reportModerationFunctions.ts \
  functions/test/reportModeration.test.js \
  functions/test/reportModerationEmulator.test.js
git add -p functions/test/functionExports.test.js
# Select only resolveReport, rejectReport, hideReportedService, hideReportedReview.
```

Commit 2:

```bash
git add functions/src/moderation/reportContract.ts \
  functions/src/moderation/reportSubmission.ts \
  functions/test/reportContract.test.js \
  functions/test/reportContractEmulator.test.js \
  functions/test/reportSubmission.test.js \
  functions/test/reportSubmissionEmulator.test.js \
  lib/features/moderation/data/repositories/report_repository.dart \
  test/features/moderation/data/report_repository_test.dart \
  test/features/moderation/presentation/report_sheet_test.dart
```

Commit 3:

```bash
git add functions/src/blocking/blockingActivationGate.ts \
  functions/src/blocking/blockingFunctions.ts \
  functions/src/blocking/relationshipGuard.ts \
  functions/src/blocking/userBlocking.ts \
  functions/src/blocking/userBlockingFunctions.ts \
  functions/src/booking/application/bookingStateMachine.ts \
  functions/src/booking/application/paymentOrchestrationV3.ts \
  functions/src/booking/bookingV3FlowFunctions.ts \
  functions/src/booking/domain/bookingContracts.ts \
  functions/src/booking/schema/bookingDocumentV3.ts \
  functions/src/index.ts \
  functions/test/bookingLifecycleV3.test.js \
  functions/test/serviceSlotCoverageEmulator.test.js \
  functions/test/userBlocking.test.js \
  functions/test/userBlockingEmulator.test.js
git add -p functions/test/functionExports.test.js
# Select only blockUserV1, unblockUserV1, getUserRelationshipStateV1.
```

Commit 4:

```bash
git add functions/src/chat/chatImageFunctions.ts \
  functions/src/legacyFunctions.ts \
  functions/src/social/followFunctions.ts \
  functions/test/blockingChatEmulator.test.js \
  functions/test/chatImageFunctionsEmulator.test.js \
  functions/test/followFunctionsEmulator.test.js
```

Commit 5:

```bash
git add lib/features/blocking \
  test/features/blocking \
  lib/features/explore/data/explore_viewer_context_repository.dart \
  lib/features/explore/presentation/screens/explore_screen.dart \
  lib/features/home/data/home_feed_repository.dart \
  lib/features/home/presentation/screens/home_screen.dart \
  lib/features/messages/data/repositories/chat_repository.dart \
  lib/features/messages/presentation/screens/chat_detail_screen.dart \
  lib/features/messages/presentation/screens/messages_screen.dart \
  lib/features/profile/data/repositories/profile_repository.dart \
  lib/features/profile/presentation/screens/profile_screen.dart \
  lib/features/profile/presentation/screens/service_detail_screen.dart \
  lib/features/services/data/repositories/services_repository.dart \
  lib/features/services/presentation/screens/services_screen.dart \
  lib/features/settings/presentation/screens/settings_screen.dart \
  lib/features/social/data/social_post_repository.dart \
  lib/features/social/presentation/screens/user_list_screen.dart \
  lib/features/social/presentation/widgets/comment_sheet.dart
```

Commit 6:

```bash
git add functions/src/blocking/historicalRelationshipMigration.ts \
  functions/scripts/read_only_relationship_audit.js \
  functions/test/historicalRelationshipMigrationEmulator.test.js \
  docs/PETTXO_PHASE3A_PRODUCTION_RELEASE_READINESS_REPORT.md \
  docs/PETTXO_PHASE3B1_RELEASE_SOURCE_FREEZE_REPORT.md
```

Commit 7:

```bash
git add firestore.rules \
  functions/test/blockingCrossFeatureRulesEmulator.test.js \
  functions/test/firestoreRulesBlockMuteProtections.test.js \
  functions/test/reportModerationRulesEmulator.test.js \
  functions/test/userRelationshipGuardRulesEmulator.test.js
```

Commit 8:

```bash
git add storage.rules functions/test/storageRulesChatMedia.test.js
```

Unrelated iOS commit, only after separate approval:

```bash
git add ios/.gitignore ios/Flutter/Debug.xcconfig \
  ios/Flutter/Profile.xcconfig ios/Flutter/Release.xcconfig \
  ios/Flutter/Maps.xcconfig ios/Flutter/Local.xcconfig.example \
  ios/Podfile ios/Podfile.lock \
  ios/Runner.xcodeproj/project.pbxproj \
  ios/Runner.xcworkspace/contents.xcworkspacedata \
  pubspec.yaml docs/IOS_APP_STORE_CHECKLIST.md
```

### Admin release branch

```bash
cd '/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard'
git switch -c release/phase3b1-admin-reporting-2026-11-16
```

Admin reporting commit:

```bash
git add lib/features/reports/data/admin_reports_repository.dart \
  lib/features/reports/models/admin_report.dart \
  lib/features/reports/presentation/reports_page.dart \
  test/features/reports/report_compatibility_test.dart
git diff --cached --check
git diff --cached
git commit -m 'feat(reports): support canonical user moderation records'
```

Admin unrelated commit, only after separate approval:

```bash
git add lib/features/finance/models/admin_finance_records.dart \
  lib/features/finance/presentation/cancellation_refunds_page.dart \
  test/core/services/admin_functions_service_test.dart \
  test/features/finance/presentation/cancellation_refunds_page_test.dart \
  test/features/offer_wall/data/offer_wall_campaign_service_test.dart \
  test/features/offer_wall/models/offer_wall_audience_test.dart
git diff --cached --check
git diff --cached
git commit -m 'fix(finance): preserve settlement and offer-wall compatibility work'
```

After all approved commits and a clean full validation, recommended local annotated tags are:

```bash
git tag -a phase3b1-source-freeze-2026-11-16 -m 'Pettxo Phase 3B-1 release source freeze'
git -C '/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard' \
  tag -a admin-phase3b1-source-freeze-2026-11-16 \
  -m 'Pettxo Admin Phase 3B-1 release source freeze'
```

Tags and branches must not be pushed until separately approved.

## 9. Remaining deployment blockers

1. Production Firestore audit counts and source fingerprint are not verified.
2. No migration scenario has been selected or executed.
3. Blocking activation prerequisites do not exist in production and activation remains prohibited.
4. Source commits, independent code review, and final clean-clone reproducibility are pending.
5. Production Function inventory was not refreshed in this phase.
6. The 17 known backend baseline failures remain.
7. Android Play Console version and real-device upgrade/booking/payment tests are pending.
8. Android Gradle wrapper files are ignored.
9. iOS signing, APNs, Phone Auth, Maps, entitlements, privacy/export settings, physical-device QA, and store metadata are incomplete.
10. No selective deployment, legacy-client production smoke test, monitoring plan rehearsal, or rollback rehearsal has occurred.

## 10. Decision

**CONDITIONAL GO for executing the prepared source commits after human review of each cached diff.**

Conditions before the first commit:

- retain the verified Phase 3B-1 backup and recheck it if source changes before staging;
- approve the release branch names and commit ordering;
- keep iOS and Admin finance/offer-wall changes separate;
- never stage `profile_tour_final_test.log~`, secrets, local signing files, or generated artifacts.

**NO-GO for deployment, migration, blocking activation, or store release.**
