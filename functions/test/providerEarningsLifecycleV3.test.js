const test = require('node:test');
const assert = require('node:assert/strict');
const {FakeFirestore, createRaceFixture} = require('./helpers/canonicalPaymentRaceHarness');
const {applyPaymentRefundEventV3} = require('../lib/booking/application/paymentRefundsV3');
const {buildProviderEarningsProjectionV3} = require('../lib/booking/application/providerEarningsV3');

for (const outcome of ['CUSTOMER_CANCELLATION','PROVIDER_CANCELLATION','NO_SHOW','DISPUTE_RESOLUTION','NORMAL_COMPLETION']) {
  for (const excess of [false,true]) test(`${outcome}: ${excess ? 'excess' : 'canonical'} refund preserves final allocation`, async () => {
    const amount = outcome === 'PROVIDER_CANCELLATION' ? 0 : outcome === 'CUSTOMER_CANCELLATION' ? 35000 : 85000;
    const earning = {...buildProviderEarningsProjectionV3({entitlementPaise: amount, phase: 'FINALIZED', outcome}),
      status: 'READY', eligibleForPayout: true};
    const db = new FakeFirestore({
      'bookings/b': {providerId: 'provider', state: 'COMPLETED_FINAL', lifecycle: {paidAt: new Date()},
        financials: {}, payment: {razorpayPaymentId: 'winner', status: 'CONFIRMED'}},
      'bookings/b/paymentAttempts/a': {razorpayPaymentId: excess ? 'extra' : 'winner', amountPaise: 100000, currency: 'INR'},
      'providerEarnings/b': earning,
    });
    const args = {firestore: db, bookingId: 'b', paymentAttemptId: 'a', paymentId: excess ? 'extra' : 'winner',
      refundId: 'refund', amountPaise: 100000, eventName: 'refund.processed', now: new Date()};
    await applyPaymentRefundEventV3(args);
    const after = db.store.get('providerEarnings/b');
    assert.equal(after.amountPaise, amount);
    assert.equal(after.providerFinalEntitlementPaise, amount);
    if (excess) assert.deepEqual(after, earning);
    else assert.equal(after.earningsStatus, outcome === 'NORMAL_COMPLETION' ? 'HELD' : 'FINALIZED');
    await applyPaymentRefundEventV3(args);
    assert.deepEqual(db.store.get('providerEarnings/b'), after);
  });
}
test('payment reconciliation produces one provisional earning and replay cannot accumulate it', async () => {
  const fixture = createRaceFixture();
  fixture.firestore._set(`bookings/${fixture.ids.bookingId}/paymentAttempts/${fixture.ids.paymentAttemptId}`, {
    state: 'CAPTURE_REPORTED', razorpayPaymentId: fixture.ids.razorpayPaymentId,
  }, {merge: true});
  await fixture.runReconciliation();
  const earning = fixture.firestore.store.get(`providerEarnings/${fixture.ids.bookingId}`);
  assert.equal(earning.amountPaise, 0);
  assert.equal(earning.providerFinalEntitlementPaise, null);
  assert.ok(earning.providerProvisionalEntitlementPaise > 0);
  await fixture.runReconciliation();
  assert.deepEqual(fixture.firestore.store.get(`providerEarnings/${fixture.ids.bookingId}`), earning);
});
for (const amount of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) test(`invalid final entitlement ${amount} is rejected`, () => {
  assert.throws(() => buildProviderEarningsProjectionV3({entitlementPaise: amount, phase: 'FINALIZED', outcome: 'NORMAL_COMPLETION'}));
});
