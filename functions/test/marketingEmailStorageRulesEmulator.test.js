const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, setDoc} = require("firebase/firestore");
const {
  deleteObject,
  getBytes,
  listAll,
  ref,
  uploadBytes,
} = require("firebase/storage");

const hasEmulators = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST &&
  process.env.FIREBASE_STORAGE_EMULATOR_HOST,
);
let environment;

test.before(async () => {
  if (!hasEmulators) return;
  environment = await initializeTestEnvironment({
    projectId: "pettexo-d9409",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
    storage: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../storage.rules"), "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "users/super"), {adminRole: "superAdmin"});
    await setDoc(doc(firestore, "users/finance"), {adminRole: "financeAdmin"});
    await setDoc(doc(firestore, "users/member"), {role: "petParent"});
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test("only a Super Admin can upload a valid marketing image", {skip: !hasEmulators}, async () => {
  const bytes = new Uint8Array([137, 80, 78, 71]);
  const path = "marketingCampaigns/campaign-1/hero.png";
  const superRef = ref(environment.authenticatedContext("super").storage(), path);
  await assertSucceeds(uploadBytes(superRef, bytes, {contentType: "image/png"}));
  await assertFails(uploadBytes(
    ref(environment.authenticatedContext("finance").storage(), "marketingCampaigns/campaign-1/finance.png"),
    bytes,
    {contentType: "image/png"},
  ));
  await assertFails(uploadBytes(
    ref(environment.authenticatedContext("member").storage(), "marketingCampaigns/campaign-1/member.png"),
    bytes,
    {contentType: "image/png"},
  ));
  await assertFails(uploadBytes(
    ref(environment.authenticatedContext("super").storage(), "marketingCampaigns/campaign-1/not-image.txt"),
    bytes,
    {contentType: "text/plain"},
  ));
});

test("email clients can fetch an image but cannot list campaign assets", {skip: !hasEmulators}, async () => {
  const storage = environment.unauthenticatedContext().storage();
  await assertSucceeds(getBytes(ref(storage, "marketingCampaigns/campaign-1/hero.png")));
  await assertFails(listAll(ref(storage, "marketingCampaigns/campaign-1")));
});

test("only a Super Admin can delete a marketing image", {skip: !hasEmulators}, async () => {
  await assertFails(deleteObject(
    ref(environment.authenticatedContext("finance").storage(), "marketingCampaigns/campaign-1/hero.png"),
  ));
  await assertSucceeds(deleteObject(
    ref(environment.authenticatedContext("super").storage(), "marketingCampaigns/campaign-1/hero.png"),
  ));
});
