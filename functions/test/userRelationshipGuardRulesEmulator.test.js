const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-user-relationship-guard-rules"});
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc, deleteDoc} = require("firebase/firestore");

const enabled = firebaseEmulator.enabled;
let environment;

test.before(async () => {
  if (!enabled) return;
  environment = await initializeTestEnvironment({
    projectId: "demo-user-relationship-guard-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "userRelationshipGuards/pair-1"), {
      uidA: "user-a",
      uidB: "user-b",
      blocked: false,
      status: "open",
    });
    await setDoc(doc(firestore, "userBlocks/user-a_user-b"), {
      ownerUserId: "user-a",
      blockerUid: "user-a",
      blockedUserId: "user-b",
      status: "active",
    });
  });
});

test("legacy directed blocks are visible to both participants but immutable to clients", {
  skip: !enabled,
}, async () => {
  const owner = environment.authenticatedContext("user-a").firestore();
  const target = environment.authenticatedContext("user-b").firestore();
  const outsider = environment.authenticatedContext("outsider").firestore();
  const blockPath = "userBlocks/user-a_user-b";
  await assertSucceeds(getDoc(doc(owner, blockPath)));
  await assertSucceeds(getDoc(doc(target, blockPath)));
  await assertFails(getDoc(doc(outsider, blockPath)));
  await assertFails(deleteDoc(doc(owner, blockPath)));
  await assertFails(updateDoc(doc(owner, blockPath), {status: "removed"}));
  await assertFails(setDoc(doc(owner, "userBlocks/user-a_outsider"), {
    ownerUserId: "user-a",
    blockedUserId: "outsider",
    createdAt: new Date(),
  }));
});

test.after(async () => environment?.cleanup());

test("participants can read but no client can mutate relationship guards", {
  skip: !enabled,
}, async () => {
  const participant = environment.authenticatedContext("user-a").firestore();
  const outsider = environment.authenticatedContext("outsider").firestore();
  const guardRef = doc(participant, "userRelationshipGuards/pair-1");
  await assertSucceeds(getDoc(guardRef));
  await assertFails(getDoc(doc(outsider, "userRelationshipGuards/pair-1")));
  await assertFails(updateDoc(guardRef, {blocked: true}));
  await assertFails(deleteDoc(guardRef));
  await assertFails(setDoc(doc(participant, "userRelationshipGuards/forged"), {
    uidA: "user-a", uidB: "user-b", blocked: true,
  }));
});

test("blocking rollout, migration, and audit records are never client-accessible", {
  skip: !enabled,
}, async () => {
  const firestore = environment.authenticatedContext("user-a").firestore();
  for (const documentPath of [
    "_rollouts/userBlockingV1",
    "_migrations/userRelationshipGuardV1",
    "userBlockingActivationAudit/audit-1",
    "relationshipMigrationEvidence/evidence-1",
  ]) {
    await assertFails(getDoc(doc(firestore, documentPath)));
    await assertFails(setDoc(doc(firestore, documentPath), {enabled: true}));
  }
});
