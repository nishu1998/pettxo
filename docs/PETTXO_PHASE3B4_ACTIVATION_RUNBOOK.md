# Pettxo user-blocking activation runbook (Phase 3B-4d)

**For:** the owner. **Takes:** about 30–45 minutes, plus tester time afterwards.
**Tool:** `functions/scripts/blocking_activation.js`, which runs on your Mac with your own owner login. It creates no Cloud Function, no service account and no new account.
**Decisions this follows:** `docs/PETTXO_PHASE3B4_DECISIONS.md`.

Blocking is OFF today. This runbook turns it ON in one audited step, and explains how to turn it OFF again.

---

## 0. What changes when blocking is ON

- **On 1.0.5 (25) and later,** users can block and unblock each other.
- **Already enforced today, whatever the switch says:** blocks that exist are honoured everywhere (chat, follow, likes, comments, bookings, payments), and unblocking works.
- **1.0.4 (23) has no block button.** Its users can still be blocked by 1.0.5 users.
- **Turning it OFF later** only stops *new* blocks. Existing blocks stay enforced, and unblock keeps working.

## 1. Before you start

1. **Pick a quiet time.** Late night IST is best: few bookings and payments in progress. The tool reads every booking twice and refuses if anything changes in between. If that happens, you simply run it again (step 4.6).
2. **Testers ready.** Check that the 1.0.5 (25) closed-testing testers can test right after activation (section 6).
3. **Check that `userBlocks` is empty.** Firebase console → Firestore Database → Data. The `userBlocks` collection should not exist, or be empty. If it has documents, stop and tell your developer before continuing.
4. **Find your owner Firebase UID:**
   - Firebase console → **Authentication** → **Users** → search your owner email → copy the **User UID**.
   - Then Firestore Database → `users` → open the document with that UID. Check that `adminRole` is **`superAdmin`**. The tool refuses any other role.
5. **Get the code ready** on your Mac, in the release worktree, on the agreed commit:
   ```bash
   cd /Users/nishantgautam/development/pettexo-android-release
   git status --short          # must print nothing
   git log --oneline -1        # the agreed commit
   cd functions && npm ci && npm run build
   ```
6. **Create the two input files** with the template commands. They are written readable only by you (mode 0600) and never overwrite an existing file:
   ```bash
   mkdir -p ~/PettxoReleaseBackups/activation
   node scripts/blocking_activation.js template-attestation --out=$HOME/PettxoReleaseBackups/activation/attestation.json
   node scripts/blocking_activation.js template-decisions   --out=$HOME/PettxoReleaseBackups/activation/decisions.json
   ```
7. **Fill in the attestation file.** Open `attestation.json` and replace:
   - `attestedByUid` with your Firebase UID (step 4);
   - `attestedByEmail` with your owner email;
   - `attestedAt` with the current time, for example `2026-11-23T23:30:00+05:30`.

   Do **not** change the `statement` or the `scope` values; the tool checks them word for word. By filling this in, you attest that no real-user bookings, payments, disputes or refunds exist. That replaces the production audit.
8. **Fill in the decisions file.** Put your Firebase UID in `decidedByUid`. Leave `decisions` as `[]` for now; you fill it in at step 4.3.

## 2. Log in

```bash
gcloud auth application-default login
```
- A browser opens. Sign in with **your owner Google account**.
- If a later step complains about a missing "quota project", run:
  ```bash
  gcloud auth application-default set-quota-project pettexo-d9409
  ```

**While you are logged in, do NOT run any of these scripts.** They would act on production with your login:
- `functions/scripts/audit_follow_consistency.js`
- `functions/scripts/audit_hashtag_search_metadata.js`
- `functions/scripts/migrate_service_private_data.js` (can write)
- `functions/scripts/initialize_preproduction_marketing_preferences.js` (can write)
- `functions/scripts/read_only_relationship_audit.js`
- `functions/scripts/slot_capacity_projection_dry_run.py` (uses your gcloud login; can write)
- `functions/scripts/provider_earnings_reconcile.cjs`

Run only `blocking_activation.js` until you have logged out (step 5). `repair_completed_booking_nested_fields.js` refuses production by design.

## 3. Check the starting state

```bash
cd /Users/nishantgautam/development/pettexo-android-release/functions
node scripts/blocking_activation.js status --project=pettexo-d9409
```
**Expected:**
- `project: pettexo-d9409 (production)`;
- `principal:` your owner email;
- `credential type: authorized_user`;
- `functions/lib built from this SHA: yes`;
- under `== Gate ==`: `"enabled": false` and `"reasonCode": "USER_BLOCKING_DISABLED"`.

The last line is always the reminder to run `gcloud auth application-default revoke`.

If the principal is not your owner email, or the project is not `pettexo-d9409`, stop.

## 4. Verify, decide, activate

### 4.1 First verify (read-only)

```bash
node scripts/blocking_activation.js verify --project=pettexo-d9409 \
  --flagged-out=$HOME/PettxoReleaseBackups/activation/flagged.json
```
- This reads every booking and block twice, and **writes nothing to Firebase**. The client is technically read-only.
- **Expected output:**
  - a JSON summary (`bookingsScanned`, `directedBlocks` = 0, `flaggedRecords`, and so on);
  - a list of **flagged records**;
  - the planned writes;
  - `== Result: READY ==` or `NOT READY`;
  - `fingerprint12: <12 characters>`.
- **Flagged records** are your test bookings that are either old-format (`INVALID_OR_LEGACY_BOOKING`) or still "protected" right now (for example `PROTECTED_STATE_CONFIRMED`). Each one needs a decision from you.
- `flagged.json` (mode 0600) holds every flagged record, ready to edit.
- **If `flaggedRecords` is 0,** the result is `READY`. Go to 4.4 with `"decisions": []`.

### 4.2 What each decision means (D3)

| Decision | Meaning | Effect |
|---|---|---|
| `NO_OBLIGATION` | "This test record carries no real obligation." | Counted as safe. Nothing is written to the record itself. |
| `PROTECT_PAIR` | "Treat these two users as having an obligation." | The pair cannot block each other until the obligation ends (D2). Only possible when the record names two users. |
| `BLOCK_ACTIVATION` | "Not sure; do not activate yet." | Activation is refused. |

The original records are never changed, whatever you decide. A malformed `userBlocks` document stays as it is, and is still honoured by its ID.

### 4.3 Fill in the decisions

- Copy the entries from `flagged.json` into `decisions.json`. Or use `flagged.json` itself: set its `decidedByUid` and pick a decision in each entry.
- **Do not change** `phase`, `sourceId`, `expectedReasonCode` or `expectedSourceUpdateTimeMillis`. They tie your decision to the exact record version. If a record changes later, its decision becomes "stale" and must be redone.
- You may write a short `note` in each entry.

Example:
```json
{
  "schemaVersion": 1,
  "decidedByUid": "YOUR_UID",
  "decisions": [
    {"phase": "bookings", "sourceId": "abc123", "expectedReasonCode": "INVALID_OR_LEGACY_BOOKING",
     "expectedSourceUpdateTimeMillis": 1763800000000, "pairKey": "pair_…", "anomaly": true,
     "decision": "NO_OBLIGATION", "note": "My test booking, Oct 2026"}
  ]
}
```

### 4.4 Verify again with your decisions

```bash
node scripts/blocking_activation.js verify --project=pettexo-d9409 \
  --decisions=$HOME/PettxoReleaseBackups/activation/decisions.json
```
- **Expected:** `"decidedRecords"` equals `"flaggedRecords"`, `"undecidedRecords": []`, `"extraDecisions": []`, and `== Result: READY ==`.
- Write down the **fingerprint12**.
- If you see `STALE_DECISION`, a record changed. Run 4.1 again and copy the new values.

### 4.5 Activate

Do this straight after 4.4, within a few minutes:
```bash
node scripts/blocking_activation.js activate --project=pettexo-d9409 \
  --decisions=$HOME/PettxoReleaseBackups/activation/decisions.json \
  --attestation=$HOME/PettxoReleaseBackups/activation/attestation.json \
  --confirm=<fingerprint12 from 4.4>
```

The tool checks everything again and then prints, **before writing anything**:
- the project, your email, the credential type and the git SHA;
- the gate state and the counts;
- the attestation ID and hash;
- the decision set hash;
- the migration run ID and audit ID;
- the **exact list of documents it will write**.

Then it asks:
```
Type "ACTIVATE <fingerprint12>" to write, anything else aborts:
```
- Type it exactly (capital letters, one space).
- Anything else aborts with nothing written.
- You have **14 minutes** from the scan to answer; after that it refuses and you start again at 4.4.

**Expected end:**
- `== Done ==`;
- `"transition"` with `"enabled": true` and `"idempotentReplay": false`;
- `"gate"` with `"enabled": true` and `"reasonCode": ""`.

### 4.6 If something is refused

| Message | What to do |
|---|---|
| `the data changed since verify` / `relationship_migration_concurrent_source_change` | A booking changed while scanning, which is normal under live traffic. **Run 4.4 again** and use the new fingerprint. |
| `not ready: …` | Some flagged record has no, a stale, or a `BLOCK_ACTIVATION` decision, or there is an extra decision. Fix `decisions.json` and repeat from 4.4. |
| `is not a superAdmin` | `decidedByUid` is wrong, or that user's `adminRole` is not `superAdmin`. |
| `more than 14 minutes passed` / `relationship_migration_not_verified` | Too slow; nothing was enabled. Repeat from 4.4. |
| `already active under audit …` | Blocking is already ON. Nothing to do. Running the exact same command again is safe and reports `"idempotentReplay": true`. |
| Anything else | Stop. Copy the output for your developer. Nothing is enabled unless the output says `"enabled": true`. |

## 5. Log out

```bash
gcloud auth application-default revoke
```
Do this even if something failed. Then run `node scripts/blocking_activation.js status --project=pettexo-d9409`: it must now refuse (no credentials). That is expected.

## 6. Tester smoke test (1.0.5 (25), two test accounts A and B; a third account C where noted)

1. **A blocks B** from B's profile. A sees the confirmation, and B disappears from A's lists.
2. **B's view:**
   - chat with A is refused **both ways** (text and photo);
   - B cannot follow A, and A cannot follow B;
   - likes and comments between them are refused;
   - each is hidden from the other's Home, Explore, search and suggestions.
3. **Unblock:** A → Settings → Account → Blocked accounts → unblock B. Chat, follow, likes and comments work again, and B reappears.
4. **Accepted but unpaid booking:** A requests B's service, and B accepts, but A does not pay. A blocks B. The booking is **cancelled**, and both get a "Booking request cancelled" notice. No money is involved.
5. **Confirmed booking:** with a paid, CONFIRMED booking between A and C, A tries to block C. It is **refused** ("You can't block this user while you have an active paid booking…").
6. **Report from a blocked relationship:** after blocking, A reports B. The report appears in the **admin dashboard** Reports list.
7. **1.0.4 (23) user:** a 1.0.4 user who was blocked by a 1.0.5 user cannot chat with, follow, like or comment on that user. The 1.0.4 app shows its usual errors.

## 7. The OFF switch

**Preferred (audited):** log in as in step 2, then:
```bash
node scripts/blocking_activation.js deactivate --project=pettexo-d9409 \
  --operator-uid=<your Firebase UID> --reason="why" --confirm=DEACTIVATE
gcloud auth application-default revoke
```
**Expected:** `"gate": {"enabled": false, "reasonCode": "USER_BLOCKING_DISABLED"}` and the line "New blocks are now refused. Existing blocks stay enforced and unblock keeps working."

**Emergency console fallback (not audited; write down what you did):** Firebase console → Firestore → `_rollouts` → `userBlockingV1` → set `enabled` to `false` → Save. The server refuses new blocks immediately.

**What stays after OFF:**
- Existing blocks stay enforced everywhere.
- Unblock works.
- The Blocked accounts screen works.
- The block button shows "Blocking isn't available yet. If you feel unsafe, you can report this user and our team will review it."

To turn it ON again later, repeat sections 1–6. A new activation creates a new audit record.

## 8. What gets written (for the record)

- `relationshipActivationDecisions/{phase}__{sourceId}`: one per decision.
- `blockingActivationAttestations/{attestationId}`: your attestation and its hash.
- `relationshipMigrationEvidence/…` and `userRelationshipGuards/…`: only for existing blocks (expected none) and `PROTECT_PAIR` decisions.
- `_migrations/userRelationshipGuardV1`: the verified scan.
- `userBlockingActivationAudit/{auditId}`: ACTIVATE or DEACTIVATE, with your UID, email, the hashes and the tool's git SHA.
- `_rollouts/userBlockingV1`: the switch.

Clients cannot read or write any of these.
