const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {getProviderLifetimeEarningsDataV3: summary} = require('../lib/booking/application/providerLifetimeEarningsV3');
const {reconcileProviderEarningsBatchDataV3: reconcile} = require('../lib/booking/application/providerEarningsBackfillV3');
const {buildProviderEarningsProjectionV3: projection} = require('../lib/booking/application/providerEarningsV3');

// An isolated emulator project prevents these financial fixtures reaching production.
const enabled = /^127\.0\.0\.1:|^localhost:/.test(process.env.FIRESTORE_EMULATOR_HOST || '');
const integration = (name, fn) => test(name, {skip: !enabled}, fn);
let app, db, sequence = 0;
const at = Timestamp.fromMillis(1780000000000);
before(async () => {
  if (!enabled) return;
  app = initializeApp({projectId: `demo-lifetime-${process.pid}`}, `lifetime-${process.pid}`);
  db = getFirestore(app);
  await db.doc('users/admin').set({adminRole: 'superAdmin'});
});
after(async () => { if (app) { await db.terminate(); await deleteApp(app); } });
const read = providerId => summary({firestore: db, auth: {uid: providerId}});
function booking(providerId) {
  return {providerId, parentId: 'parent', serviceId: 'service', state: 'COMPLETED_FINAL',
    financials: {providerPayoutPaise: 85000, currency: 'INR'},
    lifecycle: {paidAt: at, finalizedAt: at}, payment: {razorpayPaymentId: 'winner', status: 'CONFIRMED'},
    dispute: {status: 'none'}, payout: {status: 'READY'}};
}
async function seed(amounts) {
  const providerId = `provider-${++sequence}`;
  const ids = amounts.map((_, i) => `${providerId}-${i}`);
  for (let start = 0; start < ids.length; start += 200) {
    const batch = db.batch();
    for (let i = start; i < Math.min(start + 200, ids.length); i++) {
      batch.set(db.doc(`bookings/${ids[i]}`), booking(providerId));
      batch.set(db.doc(`providerEarnings/${ids[i]}`), {bookingId: ids[i], providerId, status: 'READY',
        ...projection({entitlementPaise: amounts[i] ?? 85000, phase: amounts[i] === null ? 'PROVISIONAL' : 'FINALIZED',
          outcome: amounts[i] === null ? 'PAYMENT_CONFIRMED' : 'NORMAL_COMPLETION'})});
    }
    await batch.commit();
  }
  return {providerId, ids, earning: db.doc(`providerEarnings/${ids[0]}`)};
}
integration('empty full history is zero', async () => assert.equal((await read('empty')).lifetimeEarnedPaise, 0));
integration('one normal earning is 85000 paise', async () => {
  const {providerId} = await seed([85000]);
  const result = await read(providerId);
  assert.equal(result.lifetimeEarnedPaise, 85000);
  assert.equal(result.finalizedRecordCount, 1);
  assert.equal(result.currency, 'INR');
  assert.ok(Date.parse(result.asOf));
});
integration('multiple bookings include PAID, READY and finalized HELD', async () => {
  const {providerId, ids} = await seed([85000, 50000, 35000]);
  await db.doc(`providerEarnings/${ids[0]}`).update({status: 'PAID'});
  await db.doc(`providerEarnings/${ids[2]}`).update({status: 'HELD', earningsStatus: 'HELD'});
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 170000);
});
integration('1000 historical records are included without loading a history list', async () => {
  const {providerId} = await seed(Array.from({length: 1000}, (_, i) => i + 1));
  const result = await read(providerId);
  assert.equal(result.lifetimeEarnedPaise, 500500);
  assert.equal(result.finalizedRecordCount, 1000);
});
for (const [outcome, amount] of [['CUSTOMER_CANCELLATION', 35000], ['PROVIDER_CANCELLATION', 0], ['NO_SHOW', 42000], ['DISPUTE_RESOLUTION', 50000]]) {
  integration(`${outcome} canonical correction and retry change total exactly once`, async () => {
    const {providerId, earning} = await seed([85000]);
    assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
    const update = projection({entitlementPaise: amount, phase: outcome === 'DISPUTE_RESOLUTION' ? 'ADJUSTED' : 'FINALIZED', outcome});
    await earning.update(update);
    assert.equal((await read(providerId)).lifetimeEarnedPaise, amount);
    await earning.update(update);
    assert.equal((await read(providerId)).lifetimeEarnedPaise, amount);
  });
}
integration('provisional and unresolved held records exclude expected future money; resolution includes allocation', async () => {
  const {providerId, earning} = await seed([null, 0, 85000]);
  await earning.update({earningsStatus: 'HELD', earningsOutcome: 'OPEN_DISPUTE'});
  let result = await read(providerId);
  assert.equal(result.lifetimeEarnedPaise, 85000);
  assert.equal(result.provisionalRecordCount, 1);
  assert.equal(result.finalizedRecordCount, 2);
  await earning.update(projection({entitlementPaise: 50000, phase: 'ADJUSTED', outcome: 'DISPUTE_RESOLUTION'}));
  result = await read(providerId);
  assert.equal(result.lifetimeEarnedPaise, 135000);
  assert.equal(result.provisionalRecordCount, 0);
});
integration('payout READY to PAID and duplicate refund ledger never affect earned total', async () => {
  const {providerId, earning, ids} = await seed([85000]);
  await earning.update({status: 'PAID', remainingPayablePaise: 0});
  await db.doc(`paymentRefunds/${ids[0]}`).set({bookingId: ids[0], refundKind: 'DUPLICATE_PAYMENT', amountPaise: 100000});
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
});
for (const value of [-1, 0.5, '85000', NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, FieldValue.delete()]) {
  integration(`malformed final value ${String(value)} fails closed`, async () => {
    const {providerId, earning} = await seed([85000]);
    await earning.update({providerFinalEntitlementPaise: value});
    await assert.rejects(read(providerId), {code: 'failed-precondition'});
  });
}
integration('unsafe aggregate sum fails closed', async () => {
  const {providerId} = await seed([Number.MAX_SAFE_INTEGER, 1]);
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
});
integration('legacy schema and deleted earning require reconciliation', async () => {
  const {providerId, earning} = await seed([85000]);
  await earning.update({earningsSchemaVersion: FieldValue.delete()});
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
  await earning.delete();
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
});
integration('obsolete unpaid zero audit record does not require a paid booking', async () => {
  const {providerId, earning, ids} = await seed([null]);
  await earning.update({earningsOutcome: 'NO_EARNING_RECORD_REQUIRED', providerProvisionalEntitlementPaise: 0});
  await db.doc(`bookings/${ids[0]}`).update({'lifecycle.paidAt': FieldValue.delete()});
  const result = await read(providerId);
  assert.equal(result.lifetimeEarnedPaise, 0);
  assert.equal(result.provisionalRecordCount, 0);
});
integration('Step 4 dry-run, apply and repeated historical rebuild feed the total directly', async () => {
  const {providerId, earning, ids} = await seed([85000]);
  await earning.set({bookingId: ids[0], providerId, amountPaise: 123});
  const run = dryRun => reconcile({firestore: db, auth: {uid: 'admin'}, input: {dryRun, ids}});
  assert.equal((await run(true)).counts.updated, 1);
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
  assert.equal((await run(false)).counts.updated, 1);
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
  assert.equal((await run(false)).counts.unchanged, 1);
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
});
integration('Step 4 ownership repair moves the amount safely and idempotently', async () => {
  const {providerId, earning, ids} = await seed([85000]);
  const wrong = `${providerId}-wrong`;
  await earning.update({providerId: wrong});
  await assert.rejects(read(wrong), {code: 'failed-precondition'});
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
  const run = () => reconcile({firestore: db, auth: {uid: 'admin'}, input: {dryRun: false, ids}});
  assert.equal((await run()).counts.updated, 1);
  assert.equal((await read(wrong)).lifetimeEarnedPaise, 0);
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
  assert.equal((await run()).counts.unchanged, 1);
});
integration('authentication, ownership and financial admin authorization', async () => {
  const {providerId} = await seed([85000]);
  await assert.rejects(summary({firestore: db}), {code: 'unauthenticated'});
  await assert.rejects(summary({firestore: db, auth: {uid: 'other'}, providerId}), {code: 'permission-denied'});
  await db.doc('users/support').set({adminRole: 'customerSupportAdmin'});
  await assert.rejects(summary({firestore: db, auth: {uid: 'support'}, providerId}), {code: 'permission-denied'});
  await db.doc('users/finance').set({adminRole: 'financeAdmin'});
  for (const uid of ['finance', 'admin']) assert.equal((await summary({firestore: db, auth: {uid}, providerId})).lifetimeEarnedPaise, 85000);
  for (const id of ['', 'a/b', 123]) await assert.rejects(summary({firestore: db, auth: {uid: providerId}, providerId: id}), {code: 'invalid-argument'});
});

test('export uses the Firebase callable protocol and rejects anonymous requests', async () => {
  const {getProviderLifetimeEarningsV3: callable} = require('../lib/booking/providerLifetimeEarningsFunctions');
  assert.ok(callable.__endpoint.callableTrigger);
  assert.equal(callable.__trigger.labels['deployment-callable'], 'true');
  await assert.rejects(callable.run({data: {}}), {code: 'unauthenticated'});
});
integration('canonical final entitlement ignores legacy amount and missing history timestamps', async () => {
  const {providerId, earning} = await seed([85000]);
  await earning.update({amountPaise: 1, amount: 999999});
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
});
integration('Step 4 materializes a missing projection before total becomes available', async () => {
  const {providerId, earning, ids} = await seed([85000]);
  await earning.delete();
  await assert.rejects(read(providerId), {code: 'failed-precondition'});
  assert.equal((await reconcile({firestore: db, auth: {uid: 'admin'}, input: {dryRun: false, ids}})).counts.created, 1);
  assert.equal((await read(providerId)).lifetimeEarnedPaise, 85000);
});
