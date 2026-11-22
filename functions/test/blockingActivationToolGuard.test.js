// Phase 3B-4d: target refusals for scripts/blocking_activation.js, and proof
// that verify cannot write. Production mode is never exercised beyond the
// refusal checks, which run before any Firebase module or network call.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-activation-guard",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {Writable} = require("node:stream");

const tool = require("../scripts/blocking_activation.js");
const {PRODUCTION_PROJECT_ID: GUARD_DENY} = require("../scripts/lib/targetGuard");

// Never written literally in test files (test/firebaseTestSafety.test.js).
const PROD = tool.PRODUCTION_PROJECT_ID;
const LOOPBACK = "127.0.0.1:8080";

function adcHome(type) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "adc-home-"));
  if (type) {
    const dir = path.join(home, ".config", "gcloud");
    fs.mkdirSync(dir, {recursive: true});
    fs.writeFileSync(path.join(dir, "application_default_credentials.json"), JSON.stringify({
      type,
      client_id: "test-client",
      client_secret: "test-secret",
      refresh_token: "test-refresh",
    }));
  }
  return home;
}

function refuses(argv, env, pattern) {
  assert.throws(() => tool.resolveTarget(argv, env), (error) => {
    assert.match(error.message, pattern);
    return true;
  });
}

test("the tool's production project matches the repository and the script guard's deny", () => {
  const firebaserc = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", ".firebaserc"), "utf8"));
  assert.equal(PROD, firebaserc.projects.default);
  assert.equal(PROD, GUARD_DENY);
});

test("production mode refusals happen before any Firebase or network use", () => {
  const userHome = adcHome("authorized_user");
  try {
    refuses([], {HOME: userHome}, /--project=<id>/);
    refuses([`--project=${PROD}`, `--project=${PROD}`], {HOME: userHome}, /exactly once/);
    refuses([`--project=${PROD}`], {HOME: userHome, FIRESTORE_EMULATOR_HOST: LOOPBACK}, /FIRESTORE_EMULATOR_HOST is set/);
    refuses([`--project=${PROD}`], {HOME: userHome, FIREBASE_AUTH_EMULATOR_HOST: LOOPBACK}, /FIREBASE_AUTH_EMULATOR_HOST is set/);
    refuses([`--project=${PROD}`], {HOME: userHome, GCLOUD_PROJECT: "demo-other"}, /GCLOUD_PROJECT=demo-other disagrees/);
    refuses([`--project=${PROD}`], {HOME: userHome, GOOGLE_CLOUD_PROJECT: "staging-x"}, /GOOGLE_CLOUD_PROJECT=staging-x disagrees/);
    refuses([`--project=${PROD}`], {HOME: userHome, FIREBASE_CONFIG: "{}"}, /FIREBASE_CONFIG is set/);
  } finally {
    fs.rmSync(userHome, {recursive: true, force: true});
  }
});

test("production mode requires the owner's own ADC login (authorized_user)", () => {
  const noAdc = adcHome(null);
  const serviceAccount = adcHome("service_account");
  const impersonated = adcHome("impersonated_service_account");
  const user = adcHome("authorized_user");
  try {
    refuses([`--project=${PROD}`], {HOME: noAdc}, /no Application Default Credentials/);
    refuses([`--project=${PROD}`], {HOME: serviceAccount}, /ADC type is "service_account"/);
    refuses([`--project=${PROD}`], {HOME: impersonated}, /ADC type is "impersonated_service_account"/);
    const saFile = path.join(serviceAccount, ".config", "gcloud", "application_default_credentials.json");
    refuses([`--project=${PROD}`], {HOME: user, GOOGLE_APPLICATION_CREDENTIALS: saFile}, /service_account/);
    const target = tool.resolveTarget([`--project=${PROD.toUpperCase()}`], {
      HOME: user, GCLOUD_PROJECT: PROD,
    });
    assert.equal(target.mode, "production");
    assert.equal(target.projectId, PROD);
  } finally {
    for (const home of [noAdc, serviceAccount, impersonated, user]) fs.rmSync(home, {recursive: true, force: true});
  }
});

test("emulator mode: loopback + demo-* only, and never the production project", () => {
  refuses([`--project=${PROD}`], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /production mode never talks to an emulator/);
  refuses(["--project=demo-x"], {}, /FIRESTORE_EMULATOR_HOST is not set/);
  refuses(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: "10.0.0.2:8080"}, /not a loopback/);
  refuses(["--project=staging-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /requires a demo-\* project/);
  refuses(["--project=demo-x", "--allow-project=staging-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /--allow-project is not supported/);
  refuses(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK, GCLOUD_PROJECT: PROD}, /can never target production/);
  assert.deepEqual(tool.resolveTarget(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK}),
    {projectId: "demo-x", mode: "emulator", adcPath: ""});
});

test("git state reports the HEAD SHA and whether lib matches every source file", () => {
  const state = tool.gitState();
  assert.match(state.sha, /^[0-9a-f]{40}$/);
  assert.equal(typeof state.dirty, "boolean");
  assert.equal(typeof state.libBuiltFromHead, "boolean");
  if (state.dirty) assert.equal(state.libBuiltFromHead, false);
});

test("every command prints the revoke reminder, even when refused", async () => {
  let out = "";
  const sink = new Writable({write(chunk, _e, cb) {
    out += chunk.toString(); cb();
  }});
  const result = await tool.runActivationCli({argv: ["activate", `--project=${PROD}`], env: {}, stdout: sink, stderr: sink});
  assert.equal(result.exitCode, 1);
  assert.match(out, /REFUSED:/);
  assert.match(out, /gcloud auth application-default revoke/);
});

test("verify runs on a read-only client and writes nothing", {skip: firebaseEmulator.skip}, async () => {
  const {initializeApp, deleteApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const projectId = firebaseEmulator.projectId;
  const app = initializeApp({projectId}, `guard-seed-${Date.now()}`);
  const db = getFirestore(app);
  try {
    await db.doc("bookings/legacy-guard").set({customerId: "c-1", serviceOwnerId: "p-1", status: "confirmed"});
    const collections = async () => (await db.listCollections()).map((ref) => ref.id).sort();
    const before = await collections();
    const docCount = async () => {
      let total = 0;
      for (const id of await collections()) total += (await db.collection(id).get()).size;
      return total;
    };
    const countBefore = await docCount();

    // The read-only client refuses writes outright.
    const lib = {readOnly: require("../lib/audit/readOnlyFirestore.js")};
    const roApp = initializeApp({projectId}, `guard-ro-${Date.now()}`);
    const ro = lib.readOnly.enforceReadOnlyFirestore(getFirestore(roApp));
    await assert.rejects(ro.doc("_rollouts/userBlockingV1").set({enabled: true}), /read-only audit refused/);
    await assert.rejects(ro.collection("relationshipActivationDecisions").add({x: 1}), /read-only audit refused/);
    assert.throws(() => ro.batch(), /read-only audit refused/);
    await deleteApp(roApp);

    let out = "";
    const sink = new Writable({write(chunk, _e, cb) {
      out += chunk.toString(); cb();
    }});
    const result = await tool.runActivationCli({
      argv: ["verify", `--project=${projectId}`],
      env: {FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST},
      stdout: sink,
      stderr: sink,
      deps: {gitState: () => ({sha: "test", dirty: false, libBuiltFromHead: true})},
    });
    assert.equal(result.exitCode, 0, out);
    assert.match(out, /read-only/);
    assert.deepEqual(await collections(), before);
    assert.equal(await docCount(), countBefore);
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
});
