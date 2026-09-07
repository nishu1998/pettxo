const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {applyPaymentRefundEventV3} = require('../lib/booking/application/paymentRefundsV3');

// Never open a production connection. These checks need the local emulator.
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = Boolean(emulator && /^(127\.0\.0\.1|localhost):\d+$/.test(emulator));
async function withFixture(run) {
  const app = initializeApp({projectId: 'demo-refund-isolation'}, `refund-${randomUUID()}`);
  const db = getFirestore(app);
  const id = randomUUID();
  const booking = {bookingId: id, providerId: 'provider', state: 'COMPLETED',
    payment: {razorpayPaymentId: `winner_${id}`, status: 'CONFIRMED'},
    lifecycle: {paidAt: new Date()}, financials: {customerPaidPaise: 10000, refundAmountPaise: 0}};
  const paths = ['bookings','payments','invoices','bookingFinancials','providerEarnings','providerPayouts','payoutReadiness'];
  const batch = db.batch();
  for (const path of paths) batch.set(db.doc(`${path}/${id}`), path === 'bookings' ? booking :
    {bookingId: id, amountPaise: 8500, eligibleForPayout: true, status: 'ready'});
  for (const key of ['winner','excess']) batch.set(db.doc(`bookings/${id}/paymentAttempts/${key}`),
    {razorpayPaymentId: `${key}_${id}`, amountPaise: 10000, currency: 'INR', state: key === 'winner' ? 'CONFIRMED' : 'REFUND_REQUIRED'});
  await batch.commit();
  const snapshot = async () => Promise.all(paths.map(async path => (await db.doc(`${path}/${id}`).get()).data()));
  const apply = (key, refundId, amountPaise = 10000, firestore = db) => applyPaymentRefundEventV3({
    firestore, bookingId: id, paymentAttemptId: key, paymentId: `${key}_${id}`, refundId: `${refundId}_${id}`,
    amountPaise, eventName: 'refund.processed', now: new Date(),
  });
  try { await run({db, id, apply, snapshot}); }
  finally { await db.terminate(); await deleteApp(app); }
}
test('emulator: concurrent duplicate deliveries produce one excess ledger entry and preserve provider state', {skip: !enabled}, async () => {
  await withFixture(async ({db, id, apply, snapshot}) => {
    const before = await snapshot();
    await Promise.all(Array.from({length: 4}, () => apply('excess','same')));
    assert.deepEqual(await snapshot(), before);
    const ledger = await db.collection('bookingFinancialLedger').where('bookingId','==',id).get();
    assert.equal(ledger.size, 1);
    assert.equal(ledger.docs[0].data().type, 'EXCESS_PAYMENT_REFUND');
    assert.equal((await db.doc(`bookings/${id}/paymentAttempts/excess`).get()).data().refundedAmountPaise, 10000);
  });
});
test('emulator: concurrent partial refunds do not lose cumulative amounts', {skip: !enabled}, async () => {
  await withFixture(async ({db, id, apply}) => {
    await Promise.all([apply('winner','part1',2000), apply('winner','part2',8000)]);
    const attempt = (await db.doc(`bookings/${id}/paymentAttempts/winner`).get()).data();
    assert.equal(attempt.refundedAmountPaise, 10000);
    assert.equal(attempt.netCapturedAmountPaise, 0);
    assert.equal(attempt.state, 'REFUNDED');
    assert.equal((await db.collection('bookingFinancialLedger').where('bookingId','==',id).get()).size, 2);
  });
});
test('emulator: exception after queuing financial writes rolls back the entire refund', {skip: !enabled}, async () => {
  await withFixture(async ({db, id, apply, snapshot}) => {
    const before = await snapshot();
    const failingFirestore = {
      collection: name => db.collection(name),
      runTransaction: handler => db.runTransaction(tx => handler({
        get: ref => tx.get(ref),
        set: (ref, data, options) => {
          tx.set(ref, data, options);
          if (ref.path.startsWith('providerEarnings/')) throw Error('injected financial write failure');
        },
      })),
    };
    await assert.rejects(apply('winner','rollback',10000,failingFirestore), /injected financial write failure/);
    assert.deepEqual(await snapshot(), before);
    assert.equal((await db.collection('paymentRefunds').where('bookingId','==',id).get()).size, 0);
    assert.equal((await db.collection('bookingFinancialLedger').where('bookingId','==',id).get()).size, 0);
    assert.equal((await db.doc(`bookings/${id}/paymentAttempts/winner`).get()).data().refundedAmountPaise, undefined);
    await apply('winner','rollback');
    assert.equal((await db.doc(`bookings/${id}/paymentAttempts/winner`).get()).data().state, 'REFUNDED');
  });
});
