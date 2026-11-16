# PETTXO PHASE 3B-2 — RELEASE SOURCE MANIFEST

Prepared: 2026-11-16 (Asia/Kolkata)

Scope: immutable local Git source only. No push, tag, Firebase production read/write, deployment, migration, blocking activation, store build, or store upload was performed.

## Snapshot identity

### Main application and Firebase source

- Repository: `/Users/nishantgautam/development/pettexo`
- Branch: `release/phase3b1-blocking-reporting-2026-11-16`
- Base: `1652aac6732273b945843a418b3273a88109ab42`
- Feature/rules snapshot: `662c2d0746e537d7911e79790c17079a3bed3175`
- This manifest is committed separately after the feature/rules snapshot. The resulting documentation commit is the release branch HEAD reported in the Phase 3B-2 completion report.

Committed sequence:

1. `9ad48a1e0465033da81eef6ebc315df7031673d9` — `feat(moderation): secure report resolution workflows`
2. `bf2f26e76b82678463e65e125739c6fce3856107` — `feat(reporting): add canonical user safety reports`
3. `0f92eafc280de0d00f3e23dd69510766b8c7e09d` — `feat(blocking): enforce booking-safe relationship guards`
4. `198a965e8bbd229dc99a5e217f8ee4d8b8699c40` — `feat(security): enforce bilateral blocks across chat and social`
5. `609d25f1abafc06ef3f147a3680c330a2788896f` — `feat(flutter): add authoritative blocking and reporting UX`
6. `3d4a7d2a70f9cb5e249b9a251b476fd75f7a74db` — `feat(migration): add independently verified blocking readiness audit`
7. `413b57ab9f4f4a9ba37eb1c112a0bb1e3de37a92` — `security(firestore): enforce moderation and bilateral block boundaries`
8. `662c2d0746e537d7911e79790c17079a3bed3175` — `security(storage): block new chat media across blocked relationships`

### Admin Dashboard source

- Repository: `/Users/nishantgautam/Desktop/Pettxo/admin_ Dashboard`
- Branch: `release/phase3b1-admin-reporting-2026-11-16`
- Base: `3c87df109d7cc5d9beb8467b241897e8168e66b5`
- Reporting snapshot: `d07df166a73503a2da4bf95bc0ec1dca799717ca`
- Commit: `feat(reports): support canonical user moderation records`

## Deliberately excluded work

The following main-repository paths remain uncommitted and are not part of this release source:

- `docs/IOS_APP_STORE_CHECKLIST.md`
- `ios/.gitignore`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Flutter/Maps.xcconfig`
- `ios/Flutter/Profile.xcconfig`
- `ios/Flutter/Local.xcconfig.example`
- `ios/Podfile`
- `ios/Podfile.lock`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner.xcworkspace/contents.xcworkspacedata`
- `pubspec.yaml`
- `profile_tour_final_test.log~`

The following dashboard finance/offer-wall paths remain uncommitted and are not part of the reporting snapshot:

- `lib/features/finance/models/admin_finance_records.dart`
- `lib/features/finance/presentation/cancellation_refunds_page.dart`
- `test/core/services/admin_functions_service_test.dart`
- `test/features/finance/presentation/cancellation_refunds_page_test.dart`
- `test/features/offer_wall/data/offer_wall_campaign_service_test.dart`
- `test/features/offer_wall/models/offer_wall_audience_test.dart`

## Local validation of the committed source

- TypeScript build: pass.
- Focused backend unit/export tests: 80/80 pass.
- Firestore and Storage emulator matrix: 191/191 pass.
- Focused Flutter blocking/reporting tests: 31/31 pass.
- Full Flutter application suite: 888/888 pass.
- Focused Admin reporting compatibility tests: 17/17 pass.
- Full Admin Dashboard suite: 271/271 pass.
- Cached and worktree whitespace checks: pass for committed release groups.
- Secret-pattern review: no private-key, AWS access-key, Google API-key, live Stripe-key, or live Razorpay-key match in committed release diffs.

The Phase 3A full backend baseline remains 1,088 total, 923 pass, 17 known failures, and 148 emulator skips. It was not used to conceal or override the focused and emulator results above.

## Firebase deployment dependency inventory

All listed Functions are intended for `asia-south1` on Node.js 22. This inventory is local/prior-observed evidence; production was not re-read in Phase 3B-2.

Update nine existing booking/payment Functions first:

- `createBookingRequestV3`
- `acceptBookingRequestV3`
- `createRazorpayPaymentOrderV3`
- `createBookingQrPaymentV3`
- `previewBookingPaymentPricingV3`
- `verifyBookingPaymentV3`
- `razorpayWebhook`
- `reconcileBookingPaymentsV3`
- `expireAwaitingPaymentsV3`

Reporting/moderation updates: `submitReport`, `enqueueReportModeration`. New reporting/moderation Functions: `resolveReport`, `rejectReport`, `hideReportedService`, `hideReportedReview`.

Update existing cross-feature security Functions: `getChatImageMessagingCapability`, `sendChatImageMessage`, `startProviderChat`, `startDirectUserChat`, `sendChatMessage`, `markChatDelivered`, `markChatRead`, `setFollowState`, `getProfileFollowCounts`, `createSocialNotification`, `sendPushForNotification`.

New blocking callables: `blockUserV1`, `unblockUserV1`, `getUserRelationshipStateV1`.

Firestore Rules must follow the guarded Functions and precede any activation. Storage Rules must follow chat/security Functions. No new composite index is required by this source.

## Safety gates and remaining blockers

- `blockUserV1` remains fail-closed until a valid rollout, independently verified migration record, matching run/version/source fingerprint, zero anomalies or reconciliation mismatches, and a matching fresh activation audit exist.
- Production Firestore has not been audited in this phase. Historical data counts, migration choice, source fingerprint, and activation eligibility remain unknown.
- No production Functions/Rules deployment or legacy-client smoke test has occurred.
- The 17 known non-emulator backend baseline failures remain unresolved.
- Clean-clone Android reproducibility remains blocked by ignored Gradle wrapper artifacts.
- Play Console live-version and physical Android upgrade behavior remain unverified.
- iOS signing, APNs, entitlements, Phone Auth URL scheme, release Maps key, device-family choice, export compliance, physical-device QA, and App Store metadata remain outside this snapshot and incomplete.
- Production monitoring and rollback rehearsal remain outstanding.

## Authorized next boundary

The committed source is suitable for independent review and, only after separate explicit approval and least-privilege credential confirmation, a production **read-only** historical audit. It is not approval to deploy, migrate, activate blocking, push, tag, or upload a store release.
