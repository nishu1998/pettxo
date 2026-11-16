# Pettxo Phase 3B-3b: production audit approval package

Prepared: 2026-11-17 (Asia/Kolkata). **This document is for owner approval only. Nothing in it has been run against production.**

## What the audit is and what it is not

This audit is a read-only snapshot of production Firestore. It reports what blocking activation would run into: booking, payment, refund, settlement, block and guard records, with IDs for manual reconciliation.

It **does not**:
- write anything;
- migrate or create guards;
- verify the migration;
- activate blocking;
- decide policy.

The Phase 3B-4 migration verifier and activation tooling are still required, and neither exists yet.

| Item | Value |
|---|---|
| Repository | `/Users/nishantgautam/development/pettexo` |
| Branch | `release/phase3b1-blocking-reporting-2026-11-16` |
| Audit code commit | `14a8ed915e9044443b27b6e3255c8be915ba7147` (`security(audit): production-safe read-only audit CLI and emulator rehearsal`) |
| Audit engine commit | `8434a43cccffafe33f53dcab79aa6afe277a581f` |
| Test isolation commit | `9acc649d684c97e43d8c2a237dc427c851bb4ac9` |
| Script | `functions/scripts/read_only_relationship_audit.js` (code under `functions/src/audit/`) |
| Project | `pettexo-d9409`, Firestore `(default)` |

### Safety layers built into the script

These all take effect before any production document is read:

1. **Write lock.** Every Firestore write method (`set/update/create/delete/add`, batches, bulk writers, transaction writes) is replaced with a throwing stub before any other project code loads. The Firestore client forwards only the `batchGetDocuments`, `runQuery` and `runAggregationQuery` RPCs.
2. **Flag gate.**
   - Production needs both `--project=pettexo-d9409` and `--confirm-production-read`.
   - Any other project, a missing flag, the retired `--confirm-read-only`, or any `*_EMULATOR_HOST` variable causes exit 1.
3. **Credential gate.**
   - A user credential (ADC type `authorized_user`) is refused.
   - Only a service-account credential is accepted, preferably impersonated.
   - Its principal must equal `pettxo-audit-readonly@pettexo-d9409.iam.gserviceaccount.com`.
   - The check uses the same `google-auth-library` instance the Firestore client authenticates with. firebase-admin 12.7.0's own impersonated credential returns the source user's token, so it is deliberately not used.
4. **Permission gate.** `projects.testIamPermissions` must report **none** of these 21 write-capable permissions, and must report both `datastore.entities.get` and `datastore.entities.list`:

   ```
   datastore.entities.create   datastore.entities.update   datastore.entities.delete
   datastore.databases.create  datastore.databases.update  datastore.databases.delete
   datastore.databases.import  datastore.databases.export
   datastore.indexes.create    datastore.indexes.update    datastore.indexes.delete
   firebaserules.releases.create  firebaserules.releases.update  firebaserules.rulesets.create
   cloudfunctions.functions.create  cloudfunctions.functions.update  cloudfunctions.functions.delete
   storage.objects.create      storage.objects.delete
   resourcemanager.projects.setIamPolicy   iam.serviceAccountKeys.create
   ```
5. **Project assertion.** The initialised app and the Firestore client must both resolve to `projects/pettexo-d9409/databases/(default)`.
6. **Snapshot.** All reads run in one read-only transaction pinned to a single `readTime` (start time minus 2 s, truncated to the second). Every collection describes the same moment. The run aborts INCOMPLETE if the snapshot passes 55 minutes, inside Firestore's 1-hour version retention.

## 1. IAM setup (owner performs manually)

Run these in a terminal you control. Replace `<OWNER_EMAIL>` with your Google account. Each command changes production IAM, so read it before running it.

```bash
PROJECT=pettexo-d9409
SA=pettxo-audit-readonly@${PROJECT}.iam.gserviceaccount.com

# 1. Create the service account (no keys are ever created for it).
gcloud iam service-accounts create pettxo-audit-readonly \
  --project="$PROJECT" --display-name="Pettxo read-only relationship audit"

# 2. Grant ONLY roles/datastore.viewer on the project.
#    Optional but recommended: make the grant expire automatically.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA}" --role="roles/datastore.viewer" \
  --condition='expression=request.time < timestamp("2026-11-24T00:00:00Z"),title=pettxo-audit-window'

# 3. Let ONLY you mint short-lived tokens for that service account
#    (bound on the service account, not on the project).
gcloud iam service-accounts add-iam-policy-binding "$SA" --project="$PROJECT" \
  --member="user:<OWNER_EMAIL>" --role="roles/iam.serviceAccountTokenCreator"

# 4. Confirm the service account holds exactly one project role.
gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA}" --format="value(bindings.role)"
#    Expected output: roles/datastore.viewer   (nothing else)
```

### Why `roles/datastore.viewer` is the minimum

- **Needed.** Server-side Firestore reads (Admin SDK) bypass Security Rules and need IAM `datastore.entities.get` and `datastore.entities.list`. `roles/datastore.viewer` is the narrowest predefined role that includes both.
- **What it allows.** Read every document and index/database metadata in the project's Firestore. List the exact permissions with `gcloud iam roles describe roles/datastore.viewer`. That reads the public role definition and does not touch the project.
- **What it does not allow.** No create, update or delete of documents. No import or export, which needs `roles/datastore.importExportAdmin`. No index or database changes. No Rules, Functions, Storage or IAM changes. The audit's permission gate checks this independently.
- **The caveat.** It can read **all** data, including user profiles. The audit itself only reads the 14 collections below, plus `users/{uid}` existence for UIDs in `userBlocks`, with a field mask so no profile fields are returned. Outputs contain no names, emails, phone numbers, addresses, images or bank details.
- **A narrower option.** A custom role with only `datastore.entities.get`, `datastore.entities.list` and `datastore.databases.getMetadata` would be tighter. It needs `iam.roles.create` on the project, so it is offered here only as an option.

### Logging in with impersonated credentials

This uses an isolated gcloud configuration, so your normal gcloud setup and your owner ADC at `~/.config/gcloud` are not changed.

```bash
export AUDIT_GCLOUD_DIR="$(mktemp -d)/gcloud"
export CLOUDSDK_CONFIG="$AUDIT_GCLOUD_DIR"
gcloud auth application-default login --impersonate-service-account="$SA"
# gcloud writes ADC into $CLOUDSDK_CONFIG. google-auth-library does NOT read
# CLOUDSDK_CONFIG, so point it at that file explicitly:
export GOOGLE_APPLICATION_CREDENTIALS="$AUDIT_GCLOUD_DIR/application_default_credentials.json"
```

The APIs `iamcredentials.googleapis.com` (impersonation) and `cloudresourcemanager.googleapis.com` (permission check) must be enabled on the project. If either is disabled, the script refuses. Enabling an API is a separate owner decision.

### Revoking and removing everything afterwards

```bash
gcloud auth application-default revoke          # uses CLOUDSDK_CONFIG=$AUDIT_GCLOUD_DIR
rm -rf "$AUDIT_GCLOUD_DIR"
unset GOOGLE_APPLICATION_CREDENTIALS CLOUDSDK_CONFIG AUDIT_GCLOUD_DIR

gcloud iam service-accounts remove-iam-policy-binding "$SA" --project="$PROJECT" \
  --member="user:<OWNER_EMAIL>" --role="roles/iam.serviceAccountTokenCreator"
gcloud projects remove-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA}" --role="roles/datastore.viewer" --all
gcloud iam service-accounts delete "$SA" --project="$PROJECT"

# Verify: both commands must print nothing.
gcloud projects get-iam-policy "$PROJECT" --flatten="bindings[].members" \
  --filter="bindings.members:pettxo-audit-readonly" --format="value(bindings.role)"
gcloud iam service-accounts list --project="$PROJECT" --filter="email:${SA}" --format="value(email)"
```

## 2. Exact command sequence

Run everything from `functions/` in the same terminal as the login above. Stop at the first abort criterion that fires; do not improvise around it.

### (a) Project and credential verification (no Firestore data read)

```bash
cd /Users/nishantgautam/development/pettexo/functions
git rev-parse HEAD                     # must be the approved commit (≥ 14a8ed9…, on the release branch)
git status --porcelain -- src/audit scripts/read_only_relationship_audit.js   # must print nothing
npm run build
npm run test:unit                      # isolated runner; expect the 3 known pre-existing failures only
env | grep -E '_EMULATOR_HOST' || echo "no emulator variables"   # must print "no emulator variables"
node -p 'require(process.env.GOOGLE_APPLICATION_CREDENTIALS).type'
#   must print: impersonated_service_account   (prints only the type, never secrets)
node -p 'require(process.env.GOOGLE_APPLICATION_CREDENTIALS).service_account_impersonation_url.split("/").pop()'
#   must print: pettxo-audit-readonly@pettexo-d9409.iam.gserviceaccount.com:generateAccessToken
```

**Abort if** any of these fail:
- the commit differs or the audit sources are dirty;
- the build or the unit run shows new failures;
- an emulator variable is set;
- the credential type or principal differs;
- step 1.4 showed any role other than `roles/datastore.viewer`.

### (b) Count-only run

```bash
node scripts/read_only_relationship_audit.js --project=pettexo-d9409 --confirm-production-read --count-only
echo "exit=$?"
```

This uses about 43 reads plus 1 per 1,000 documents counted.

- **Before any read**, the script prints `credential impersonated_service_account principal=pettxo-audit-readonly@… write permissions: none; read permissions: ok`.
- **Output** goes to `~/PettxoReleaseBackups/audits/<UTC timestamp>/`. Pass `--out-dir=` to choose another location outside the repository.
- **What it does:**
  - counts every audited collection;
  - counts bookings per canonical state, and reports bookings with a non-canonical state as total minus the sum;
  - probes each full-mode query shape with `limit(1)`, so a missing index or permission fails here cheaply.

**Abort if:**
- the exit code is not 0;
- any `[audit] REFUSED` or `INCOMPLETE` appears;
- `summary.json` `status` is not `COMPLETE`, or `queryShapesProbed` is not 14;
- counts are implausible, for example `bookings` is 0;
- `estimatedFullRunReads` is above the read budget you are willing to pay for (see §3).

### (c) Full run with a budget derived from (b)

```bash
MAX=$(node -p 'require(process.argv[1]).countOnlyResult.suggestedMaxReads' ~/PettxoReleaseBackups/audits/<count-only-folder>/summary.json)
node scripts/read_only_relationship_audit.js --project=pettexo-d9409 --confirm-production-read --max-reads="$MAX"
echo "exit=$?"
```

`suggestedMaxReads` is `ceil(1.25 × estimatedFullRunReads) + 500`.

**Abort or stop if:**
- **Exit 1.** Read `incompleteReason`, then stop. Do **not** rerun with a larger `--max-reads` without fresh owner approval.
- **Manifest mismatch.** `manifest.json` `gitSha` differs from (a), `auditSourcesDirty` is `true`, `credential.principal` is not the audit service account, or `readCount > maxReads`.

**Then** revoke and remove access (§1) the same day, whatever the result.

## 3. Read volume, cost, runtime

Let `n_c` be the document count of collection `c` from step (b), across the 14 audited collections, and `B = n_userBlocks`.

| Run | Billed document reads |
|---|---|
| Count-only | `29 + Σ_c max(1, ceil(n_c / 1000))` for the aggregations, `+ 14` for the probes. About 43 when every collection has under 1,000 documents. |
| Full | Upper bound used for `estimatedFullRunReads`: `Σ_c n_c + Σ_c (floor(n_c / 300) + 1) + 2·B`. The actual cost is every document once, plus one minimum-charge read for each empty final page, plus one field-masked `users/{uid}` read per **distinct** UID referenced by blocks. |

- **Cost.** Billed reads × Firestore's per-100,000-read price for the database location, after the daily free read quota. Check the current Firestore pricing page; it is not reproduced here because it changes. As an illustration only: 100,000 reads costs a few US cents. Egress is negligible because outputs are local and small.
- **Runtime.** It is dominated by page round-trips: 300 documents per page, usually around 0.1–0.5 s each from India to asia-south1. That is roughly 1,000–3,000 documents per second, so a 100,000-document run takes about 1–2 minutes. **Not Verified against production.** The hard ceiling is 55 minutes, after which the snapshot-age guard aborts with `SNAPSHOT_AGE_LIMIT`.
- **Rehearsal reference (emulator).** 45 seeded documents, 35 of them in audited collections. Count-only used 43 reads and estimated 63. The full run used 46 reads (35 documents plus 11 distinct block UIDs), against `--max-reads=579`.

## 4. Indexes

| Query | Index needed | In `firestore.indexes.json`? |
|---|---|---|
| 13 collections and the `paymentAttempts` collection group: `orderBy(__name__)`, paginated, no filter | Built-in document-ID ordering; no composite index | Not applicable |
| `count()` of each collection and of the `paymentAttempts` group, no filter | None | Not applicable |
| `bookings` `where("state","==",X).count()` (count-only) | Automatic single-field index on `bookings.state` | No field override exempts `bookings.state`. Existing `paymentAttempts.state` overrides add collection-group scope only. |
| `users/{uid}` batch get with field mask | None | Not applicable |

- **Production index state is Not Verified.** The file shows what is deployable, not what is live. If a required index is missing or exempted in production, Firestore returns `FAILED_PRECONDITION` and the audit stops with `INCOMPLETE` (`ERROR:9`) and exit 1. It cannot silently under-count:
  - the full run uses no filtered queries;
  - in count-only mode, a missing state index is an error, not a zero.
- **Cross-check.** `bookingsWithNonCanonicalState` should equal the number of malformed or legacy bookings later reported by the full run. A large mismatch is an abort signal.

## 5. Interpreting the result

| Exit | Meaning | Action |
|---|---|---|
| 0 (full) | Complete; no record needs review at `readTime`. | Keep `summary.*` and the manifest; activation still requires the Phase 3B-4 verifier. |
| 0 (count-only) | Counts complete; review need **not evaluated** (`reviewDetermination: NOT_EVALUATED_IN_COUNT_ONLY_MODE`). | Proceed to (c). |
| 2 | Complete; some records need manual review. | Reconcile each record in `review_records.json`. |
| 1 | Refused, incomplete (read budget, snapshot age, permission, index, network) or error. | Stop. Results are partial and marked INCOMPLETE; do not use them. |

### Review categories

All of these drive exit code 2.

| Category | Meaning |
|---|---|
| `MALFORMED_BOOKING` | Unknown or missing state, legacy schema, invalid canonical document, or invalid or conflicting participants. Treated as protected (fail-closed). |
| `STRANDED_MONEY` | A captured or pending payment on a booking not in CONFIRMED / IN_PROGRESS / COMPLETED_* / DISPUTED. Reason is `PENDING_PAYMENT_ON_UNCONFIRMED_BOOKING`, `CAPTURED_NO_REFUND_RECORD`, `CAPTURED_REFUND_OPEN` or `CAPTURED_REFUND_SETTLED_PARTIAL`. |
| `BLOCK_BOOKING_CONFLICT` | A blocked pair (any direction) with a non-terminal or protected booking, open payment evidence, or an open customer-provider financial record. `BLOCK_WITH_OPEN_PAYMENT_ORDER` marks the webhook-capture risk described in 3B-3a. |
| `USER_BLOCK_MISSING_USER` / `INVALID_USER_BLOCK` | A block referencing a missing `users/{uid}`, or a block with invalid participants or a document-ID or pair-key mismatch. |
| `RELATIONSHIP_GUARD_INCONSISTENT` | A guard that does not match the directed blocks, or has a bad pair key, or **any** `historicalProtectionBlocked` mark. Before deployment, the expected guard count is 0. |
| `UNKNOWN_FINANCIAL_STATUS` | A financial record whose status is outside the known vocabulary. It is counted as open. |
| `PAYMENT_EVIDENCE_INCONSISTENT` | An orphan order or QR mapping, an attempt whose `bookingId` differs from its parent, or an unknown attempt or QR state. |
| `MULTI_DAY_PACKAGE_INCONSISTENT` | A package marked completed before its last day ends. |

### Informational categories

These are reported for owner policy decisions and do not change the exit code.

- `CUSTOMER_PROVIDER_PROTECTION`: open disputes, refunds, refund events, reconciliations and customer-refund obligations.
- `PETTXO_PROVIDER_SETTLEMENT`: open provider payouts, earnings and payout readiness, plus holds. These are reported **separately**, as the owner is still deciding whether they affect blocking.
- `BLOCK_WITH_PETTXO_PROVIDER_SETTLEMENT_ONLY`: a blocked pair whose only open item is Pettxo-to-provider settlement.
- `RECIPROCAL_BLOCK_PAIR`, `DIRECTED_BLOCK_WITHOUT_GUARD` (expected before migration), and `MULTI_DAY_PACKAGE`.

### What a clean result proves

- At `readTime`, none of the audited records were in a reviewable state, and every audited collection was fully read inside one consistent snapshot.
- The credential used could not write, as checked both by IAM and in code.

### What a clean result does not prove

- **Nothing after `readTime`.** Android is live. New bookings, payment orders, captures, refunds and, until the new Rules deploy, client-written `userBlocks` can appear at any moment. The snapshot ages from the second it is taken.
- **Not migration readiness or activation safety.** Activation needs the Phase 3B-4 migration verifier and activation tooling, which do not exist yet. The verifier's 15-minute freshness window is a separate, later check.
- **Collections it does not read:** legacy `payments`, `paymentWebhookEvents`, `bookingFinancials`, `bookingFinancialLedger`, `bookingCancellations`, chats, follows, Storage objects, and Razorpay's own records. External money state is not reconciled with Razorpay.
- **Production indexes, rules and deployed functions** are not proven to match the repository.
- **Not a full user-existence check.** Only UIDs referenced by `userBlocks` are checked against `users/{uid}`.

## 6. Privacy handling

- **Location.** Output goes to `~/PettxoReleaseBackups/audits/<timestamp>/` (folder mode 0700, every file 0600), never inside the repository; the script refuses that. `~/PettxoReleaseBackups` is in the home folder, not Desktop or Documents, so iCloud Desktop & Documents sync does not cover it. Time Machine **does** include it; exclude it before the run if that matters to you (`tmutil addexclusion ~/PettxoReleaseBackups/audits`).
- **`summary.json` and `summary.md`.** Counts plus `h_`-prefixed salted HMAC-SHA256 hashes of UIDs, pair keys and record references. No raw IDs. These may be shared with the release architect.
- **`review_records.json`.** Raw document IDs, booking IDs and UIDs, plus the per-run salt.
  - Never paste it into chat, tickets, email or a repository.
  - Never upload it.
  - It holds no names, emails, phone numbers, addresses, images or bank details.
- **Deletion.** After reconciliation, run `rm ~/PettxoReleaseBackups/audits/<timestamp>/review_records.json`, and remove any Time Machine snapshot copy if one was taken. Keep `summary.*` and `manifest.json`; the manifest SHA-256 of the deleted file stays as evidence that it existed.

## 7. Owner checklist (tick all before approving)

- [ ] I have read §5 "what a clean result does not prove" and accept that this audit does not authorise activation.
- [ ] Both GitHub release branches are pushed (done in Phase 3B-3b-0) and the audit commits are pushed or otherwise backed up.
- [ ] I confirmed, manually in the Firebase console, whether `users/follower`, `users/followee`, `follows/follower_followee` and `userBlocks/followee_follower` exist in production (Phase 3B-3a B2), and recorded the result.
- [ ] Service account `pettxo-audit-readonly` created, with **only** `roles/datastore.viewer` (step 1.4 output checked), preferably time-bound.
- [ ] `roles/iam.serviceAccountTokenCreator` granted to me on that service account only.
- [ ] Impersonated ADC created in an isolated `CLOUDSDK_CONFIG`; `GOOGLE_APPLICATION_CREDENTIALS` points to it; no emulator variables set.
- [ ] Step (a) passed: correct commit, clean audit sources, build and unit run OK, credential type and principal correct.
- [ ] Read budget accepted after step (b): `estimatedFullRunReads = ____`, `--max-reads = ____`.
- [ ] Time Machine exclusion decided for the audit output folder.
- [ ] Revocation and removal (§1) scheduled for the same day, and done.
- [ ] `review_records.json` deletion date set: ____.

Approved by: ____________________  Date: __________
