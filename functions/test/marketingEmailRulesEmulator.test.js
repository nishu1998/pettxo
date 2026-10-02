const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const hasEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let environment;

test.before(async () => {
  if (!hasEmulator) return;
  environment = await initializeTestEnvironment({
    projectId: "pettexo-d9409",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "users/super"), {
      uid: "super",
      adminRole: "superAdmin",
      accountStatus: "active",
    });
    await setDoc(doc(firestore, "users/member"), {
      uid: "member",
      role: "petParent",
      accountStatus: "active",
    });
    await setDoc(doc(firestore, "userPrivate/member"), {
      uid: "member",
      accountStatus: "active",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(firestore, "marketingCampaigns/campaign-1"), {
      campaignId: "campaign-1",
      status: "DRAFT",
    });
    await setDoc(doc(firestore, "marketingCampaigns/campaign-1/deliveries/member"), {
      campaignId: "campaign-1",
      uid: "member",
    });
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test("campaign and delivery records stay inaccessible even to a Super Admin client", {skip: !hasEmulator}, async () => {
  const firestore = environment.authenticatedContext("super").firestore();
  await assertFails(getDoc(doc(firestore, "marketingCampaigns/campaign-1")));
  await assertFails(setDoc(doc(firestore, "marketingCampaigns/campaign-2"), {status: "DRAFT"}));
  await assertFails(getDoc(doc(firestore, "marketingCampaigns/campaign-1/deliveries/member")));
  await assertFails(setDoc(doc(firestore, "marketingCampaignExecutions/execution-1"), {status: "QUEUED"}));
});

test("a user cannot write the callable-owned marketing preference directly", {skip: !hasEmulator}, async () => {
  const firestore = environment.authenticatedContext("member").firestore();
  await assertFails(updateDoc(doc(firestore, "userPrivate/member"), {
    marketingEmailEnabled: true,
    updatedAt: serverTimestamp(),
  }));
});

test("another user cannot read or mutate unsubscribe and rate-limit records", {skip: !hasEmulator}, async () => {
  const firestore = environment.authenticatedContext("member").firestore();
  await assertFails(getDoc(doc(firestore, "marketingUnsubscribeTokens/token")));
  await assertFails(setDoc(doc(firestore, "marketingEmailTestRateLimits/member"), {lastSentAt: serverTimestamp()}));
  assert.ok(true);
});
