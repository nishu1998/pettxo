const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {deleteDoc, doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const enabled = /^(127\.0\.0\.1|localhost):\d+$/.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
let environment;

test.before(async () => {
  if (!enabled) return;
  environment = await initializeTestEnvironment({
    projectId: "demo-report-moderation-rules",
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8",
      ),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all([
      setDoc(doc(firestore, "users/reporter"), {accountStatus: "active"}),
      setDoc(doc(firestore, "users/finance"), {
        adminRole: "financeAdmin", accountStatus: "active",
      }),
      setDoc(doc(firestore, "users/support"), {
        adminRole: "customerSupportAdmin", accountStatus: "active",
      }),
      setDoc(doc(firestore, "users/super"), {
        adminRole: "superAdmin", accountStatus: "active",
      }),
      setDoc(doc(firestore, "users/disabled-support"), {
        adminRole: "customerSupportAdmin", accountStatus: "disabled",
      }),
      setDoc(doc(firestore, "reports/existing"), {
        type: "service", targetId: "service-1", reportedBy: "reporter",
        status: "pending",
      }),
      setDoc(doc(firestore, "services/service-1"), {
        ownerUserId: "provider", isVisibleToMarketplace: true,
      }),
      setDoc(doc(firestore, "services/service-1/reviews/review-1"), {
        reviewerId: "reporter", moderationStatus: "approved",
      }),
    ]);
  });
});

test.after(async () => environment?.cleanup());

test("finance admin cannot mutate reports or nested reviews", {skip: !enabled}, async () => {
  const firestore = environment.authenticatedContext("finance").firestore();
  await assertFails(updateDoc(doc(firestore, "reports/existing"), {status: "resolved"}));
  await assertFails(deleteDoc(doc(firestore, "reports/existing")));
  await assertFails(updateDoc(
    doc(firestore, "services/service-1/reviews/review-1"),
    {moderationStatus: "hidden"},
  ));
  await assertFails(deleteDoc(
    doc(firestore, "services/service-1/reviews/review-1"),
  ));
});

test("regular users cannot mutate reports or nested reviews", {skip: !enabled}, async () => {
  const firestore = environment.authenticatedContext("reporter").firestore();
  await assertFails(updateDoc(doc(firestore, "reports/existing"), {status: "resolved"}));
  await assertFails(deleteDoc(doc(firestore, "reports/existing")));
  await assertFails(updateDoc(
    doc(firestore, "services/service-1/reviews/review-1"),
    {moderationStatus: "hidden"},
  ));
  await assertFails(deleteDoc(
    doc(firestore, "services/service-1/reviews/review-1"),
  ));
});

test("support and super admins cannot bypass secure moderation callables", {
  skip: !enabled,
}, async () => {
  const support = environment.authenticatedContext("support").firestore();
  const superAdmin = environment.authenticatedContext("super").firestore();
  await assertFails(updateDoc(
    doc(support, "services/service-1/reviews/review-1"),
    {moderationStatus: "hidden"},
  ));
  await assertFails(deleteDoc(
    doc(support, "services/service-1/reviews/review-1"),
  ));
  await assertFails(updateDoc(
    doc(superAdmin, "reports/existing"),
    {status: "resolved"},
  ));
  await assertFails(deleteDoc(doc(superAdmin, "reports/existing")));
});

test("disabled admins cannot mutate moderation decisions", {skip: !enabled}, async () => {
  const firestore = environment.authenticatedContext("disabled-support").firestore();
  await assertFails(updateDoc(doc(firestore, "reports/existing"), {status: "resolved"}));
  await assertFails(updateDoc(
    doc(firestore, "services/service-1/reviews/review-1"),
    {moderationStatus: "hidden"},
  ));
});

test("legacy Android direct report creation and reporter read remain valid", {
  skip: !enabled,
}, async () => {
  const firestore = environment.authenticatedContext("reporter").firestore();
  const legacyRef = doc(firestore, "reports/legacy-android");
  await assertSucceeds(setDoc(legacyRef, {
    type: "service",
    targetId: "service-1",
    reportedBy: "reporter",
    status: "pending",
    reason: "Spam",
  }));
  await assertSucceeds(getDoc(legacyRef));
  await assertFails(updateDoc(legacyRef, {description: "More detail"}));
});

test("ordinary review creation and reads remain valid", {skip: !enabled}, async () => {
  const firestore = environment.authenticatedContext("reporter").firestore();
  const reviewRef = doc(firestore, "services/service-1/reviews/review-2");
  await assertSucceeds(setDoc(reviewRef, {
    reviewerId: "reporter",
    rating: 5,
    comment: "Great service",
  }));
  await assertSucceeds(getDoc(reviewRef));
});

test("rules patch contains backend-only queue and audit writes", () => {
  const rules = fs.readFileSync(
    path.resolve(__dirname, "../../firestore.rules"),
    "utf8",
  );
  assert.match(rules, /match \/moderationQueue\/\{moderationItemId\}[\s\S]*?allow write: if false;/);
  assert.match(rules, /match \/adminAuditLogs\/\{logId\}[\s\S]*?allow write: if false;/);
});
