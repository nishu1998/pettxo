const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {deleteDoc, doc, serverTimestamp, setDoc} = require("firebase/firestore");

const projectId = "pettexo-d9409";
const rules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");

async function withFollowEnvironment(run) {
  const testEnv = await initializeTestEnvironment({projectId, firestore: {rules}});
  try {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", "a"), {uid: "a", accountStatus: "active"});
      await setDoc(doc(context.firestore(), "users", "b"), {uid: "b", accountStatus: "active"});
    });
    await run(testEnv);
  } finally {
    await testEnv.cleanup();
  }
}

test("legacy client follow create remains constrained to the authenticated follower", async () => {
  await withFollowEnvironment(async (testEnv) => {
    const firestore = testEnv.authenticatedContext("a").firestore();
    await assertSucceeds(setDoc(doc(firestore, "follows", "a_b"), {
      followerId: "a",
      followeeId: "b",
      createdAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(firestore, "follows", "a_b"), {
      followerId: "a",
      followeeId: "b",
      createdAt: serverTimestamp(),
    }));
  });
});

test("another user cannot delete a relationship and self-follow is rejected", async () => {
  await withFollowEnvironment(async (testEnv) => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "follows", "a_b"), {
        followerId: "a",
        followeeId: "b",
        createdAt: new Date(),
      });
    });
    await assertFails(deleteDoc(doc(
      testEnv.authenticatedContext("b").firestore(),
      "follows",
      "a_b",
    )));
    await assertFails(setDoc(doc(
      testEnv.authenticatedContext("a").firestore(),
      "follows",
      "a_a",
    ), {
      followerId: "a",
      followeeId: "a",
      createdAt: serverTimestamp(),
    }));
  });
});
