const test = require('node:test');
const assert = require('node:assert/strict');
const {FakeFirestore} = require('./helpers/canonicalPaymentRaceHarness');
const {buildCanonicalPaymentRaceFixture} = require('./helpers/canonicalPaymentRaceFixture');
const {applyPaymentRefundEventV3, excessRefundIdV3} = require('../lib/booking/application/paymentRefundsV3');
const {finalizeCapturedBookingPaymentV3, persistFinalizePaymentResultV3, submitRefundInstructionV3,
  reconcilePaymentAttemptsV3} = require('../lib/booking/application/paymentOrchestrationV3');
const {routeCanonicalWebhookEventV3} = require('../lib/booking/application/canonicalPaymentWebhookV3');
const gateway = require('../lib/booking/application/razorpayGateway');

// Stage all writes so failures reproduce transaction rollback, including a
// processor retry after a failed commit. Enforce Firestore's read-before-write rule.
class AtomicFirestore extends FakeFirestore {
  async runTransaction(handler) {
    const writes = [];
    const result = await handler({
      get: async (ref) => { assert.equal(writes.length, 0); return ref.get(); },
      set: (ref, data, options) => writes.push([ref.path, data, options]),
    });
    if (this.failCommit) throw new Error('injected commit failure');
    for (const args of writes) this._set(...args);
    return result;
  }
}
const protectedCollections = ['bookings', 'payments', 'invoices', 'bookingFinancials',
  'providerEarnings', 'providerPayouts', 'payoutReadiness', 'refunds'];
const snapshot = (db, id) => protectedCollections.map(c => db.store.get(`${c}/${id}`));
async function scenario(winner = 'A', completed = false) {
  const f = buildCanonicalPaymentRaceFixture();
  const id = f.ids.bookingId;
  const attempts = Object.fromEntries(['A','B'].map(key => [key, {...f.paymentAttempt,
    paymentAttemptId: key, razorpayOrderId: `order_${key}`} ]));
  const capture = key => ({...f.razorpayPayment, id: `pay_${key}`, orderId: `order_${key}`});
  const db = new AtomicFirestore({[`bookings/${id}`]: f.booking,
    ...Object.fromEntries(['A','B'].map(key => [`bookings/${id}/paymentAttempts/${key}`, attempts[key]]))});
  const finalize = (key, booking = f.booking, attempt = attempts[key]) => finalizeCapturedBookingPaymentV3({
    ...f, bookingId: id, booking, paymentAttempt: attempt, razorpayPayment: capture(key), verificationSource: 'webhook',
  });
  const result = finalize(winner);
  assert.equal(result.ok, true);
  await persistFinalizePaymentResultV3({firestore: db, bookingId: id, result});
  const booking = {...result.booking, ...(completed ? {state: 'COMPLETED'} : {})};
  db._set(`bookings/${id}`, booking);
  db._set(`providerPayouts/${id}`, {amountPaise: 12345, status: 'ready'});
  const loser = winner === 'A' ? 'B' : 'A';
  const duplicate = finalize(loser, booking);
  assert.equal(duplicate.ok, false);
  await persistFinalizePaymentResultV3({firestore: db, bookingId: id, result: duplicate});
  const amount = f.paymentAttempt.amountPaise;
  const apply = (key, eventName, refundId = `rfnd_${key}`, amountPaise = amount) => applyPaymentRefundEventV3({
    firestore: db, bookingId: id, paymentAttemptId: key, paymentId: `pay_${key}`,
    refundId, amountPaise, eventName, now: f.authoritativeNow,
  });
  const webhook = (key, eventName, refundId = `rfnd_${key}`, value = amount) => routeCanonicalWebhookEventV3({
    firestore: db, eventId: `${eventName}:${refundId}`, eventName, paymentEntity: {},
    refundEntity: {id: refundId, payment_id: `pay_${key}`, amount: value},
    keyId: 'key', keySecret: 'secret', authoritativeNow: f.authoritativeNow,
  });
  return {f, db, id, winner, loser, amount, apply, webhook, finalize};
}
for (const winner of ['A','B']) for (const completed of [false,true]) {
  test(`original duplicate capture incident: ${winner} wins, booking ${completed ? 'completed' : 'confirmed'}`, async () => {
    const s = await scenario(winner, completed);
    const before = snapshot(s.db, s.id);
    for (const event of ['refund.created','refund.processed','refund.processed','refund.created','refund.failed']) {
      await s.webhook(s.loser, event);
      assert.deepEqual(snapshot(s.db, s.id), before);
    }
    const attempt = s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.loser}`);
    assert.equal(attempt.state, 'REFUNDED');
    assert.equal(attempt.refundedAmountPaise, s.amount);
    assert.equal(attempt.netCapturedAmountPaise, 0);
    assert.equal(s.db.store.get(`refunds/${excessRefundIdV3(`pay_${s.loser}`)}`).state, 'processed');
    const ledger = [...s.db.store.values()].filter(d => d.type === 'EXCESS_PAYMENT_REFUND');
    assert.equal(ledger.length, 1);
    assert.equal(ledger[0].amountPaise, s.amount);
    let verificationCalls = 0;
    await reconcilePaymentAttemptsV3({firestore: s.db, keyId: 'key', keySecret: 'secret',
      authoritativeNow: s.f.authoritativeNow, deps: {verifyCapturedPayment: async () => { verificationCalls++; throw Error('unexpected'); }}});
    assert.equal(verificationCalls, 0);
    assert.deepEqual(snapshot(s.db, s.id), before);
    const replay = s.finalize(s.loser, s.db.store.get(`bookings/${s.id}`), attempt);
    assert.equal(replay.ok, false);
    await persistFinalizePaymentResultV3({firestore: s.db, bookingId: s.id, result: replay});
    assert.deepEqual(snapshot(s.db, s.id), before);
  });
}
for (const event of ['refund.created','refund.failed']) test(`excess ${event} preserves all canonical financial records`, async () => {
  const s = await scenario(); const before = snapshot(s.db, s.id);
  await s.webhook(s.loser, event);
  assert.deepEqual(snapshot(s.db, s.id), before);
  assert.equal(s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.loser}`).refundedAmountPaise, 0);
});
test('authoritative partial refunds accumulate by refund ID and only full refund cancels payout', async () => {
  const s = await scenario();
  const partial = Math.floor(s.amount / 5);
  const earning = s.db.store.get(`providerEarnings/${s.id}`).amountPaise;
  await s.webhook(s.winner, 'refund.created', 'part1', partial);
  assert.equal(s.db.store.get(`payoutReadiness/${s.id}`).status, 'held');
  await s.webhook(s.winner, 'refund.processed', 'part1', partial);
  await s.webhook(s.winner, 'refund.processed', 'part1', partial);
  let attempt = s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.winner}`);
  assert.equal(attempt.refundStatus, 'PARTIALLY_REFUNDED');
  assert.equal(attempt.refundedAmountPaise, partial);
  assert.equal(attempt.netCapturedAmountPaise, s.amount - partial);
  assert.notEqual(s.db.store.get(`bookings/${s.id}`).payment.status, 'refunded');
  assert.equal(s.db.store.get(`providerEarnings/${s.id}`).amountPaise, earning);
  await s.webhook(s.winner, 'refund.processed', 'part2', s.amount - partial);
  attempt = s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.winner}`);
  assert.equal(attempt.refundStatus, 'REFUNDED');
  assert.equal(attempt.netCapturedAmountPaise, 0);
  assert.equal(s.db.store.get(`bookings/${s.id}`).payment.razorpayPaymentId, `pay_${s.winner}`);
  assert.equal(s.db.store.get(`payoutReadiness/${s.id}`).status, 'cancelled');
  assert.equal(s.db.store.get(`refunds/${s.id}`).refundAmountPaise, s.amount);
  assert.equal([...s.db.store.values()].filter(d => d.type === 'CUSTOMER_REFUND').length, 2);
});
test('failed canonical refund records no returned money and delayed created cannot revive it', async () => {
  const s = await scenario();
  await s.webhook(s.winner, 'refund.failed');
  const before = [...s.db.store];
  await s.webhook(s.winner, 'refund.created');
  assert.deepEqual([...s.db.store], before);
  const attempt = s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.winner}`);
  assert.equal(attempt.refundStatus, 'REFUND_FAILED');
  assert.equal(attempt.refundedAmountPaise, 0);
  assert.equal(attempt.netCapturedAmountPaise, s.amount);
});
test('refund commit failure leaves all financial documents unchanged and delivery can retry', async () => {
  const s = await scenario(); const before = [...s.db.store];
  s.db.failCommit = true;
  await assert.rejects(s.apply(s.winner, 'refund.processed'), /commit failure/);
  assert.deepEqual([...s.db.store], before);
  s.db.failCommit = false;
  await s.apply(s.winner, 'refund.processed');
  assert.equal(s.db.store.get(`bookings/${s.id}`).payment.status, 'refunded');
});
for (const amount of [0,-1,1.5,Number.MAX_SAFE_INTEGER]) test(`invalid refund amount ${amount} makes no writes`, async () => {
  const s = await scenario(); const before = [...s.db.store];
  await assert.rejects(s.apply(s.loser, 'refund.processed', 'bad', amount));
  assert.deepEqual([...s.db.store], before);
});
test('different refund IDs cannot refund more than the capture', async () => {
  const s = await scenario(); await s.apply(s.loser, 'refund.processed');
  const before = [...s.db.store];
  await assert.rejects(s.apply(s.loser, 'refund.processed', 'extra', 1));
  assert.deepEqual([...s.db.store], before);
});
test('stale successful capture cannot overwrite a refund committed before finalization', async () => {
  const s = await scenario();
  const stale = s.finalize(s.winner);
  await s.apply(s.winner, 'refund.processed');
  const before = [...s.db.store];
  await assert.rejects(persistFinalizePaymentResultV3({firestore: s.db, bookingId: s.id, result: stale}), /refund history/);
  assert.deepEqual([...s.db.store], before);
});
test('ambiguous gateway retry preserves request body and idempotency key and isolates excess', async () => {
  const s = await scenario(); const before = snapshot(s.db, s.id); const calls = [];
  const original = gateway.processRazorpayRefundV3;
  gateway.processRazorpayRefundV3 = async args => { calls.push(args);
    if (calls.length === 1) throw Error('timeout');
    return {status: 'processed', razorpayRefundId: 'retry_refund'};
  };
  try {
    const args = {firestore: s.db, bookingId: s.id, paymentAttemptId: s.loser, keyId: 'key', keySecret: 'secret'};
    assert.equal(await submitRefundInstructionV3(args), 'RETRY_LATER');
    assert.equal(await submitRefundInstructionV3(args), 'REFUNDED');
    assert.deepEqual(calls[0], calls[1]);
    assert.match(calls[0].idempotencyKey, /^[\w-]{10,}$/);
    assert.deepEqual(snapshot(s.db, s.id), before);
  } finally { gateway.processRazorpayRefundV3 = original; }
});
for (const status of ['pending','processed','failed']) test(`gateway preserves processor refund status ${status} and sends idempotency header`, async () => {
  const original = global.fetch;
  global.fetch = async (_url, options) => {
    assert.equal(options.headers['X-Refund-Idempotency'], 'refund-key-12345');
    return {ok: true, text: async () => JSON.stringify({id: 'refund1', status})};
  };
  try {
    const result = await gateway.processRazorpayRefundV3({keyId: 'key', keySecret: 'secret',
      razorpayPaymentId: 'pay1', refundAmountPaise: 100, reason: 'duplicate', idempotencyKey: 'refund-key-12345'});
    assert.equal(result.status, status);
    assert.equal(Boolean(result.processedAt), status === 'processed');
  } finally { global.fetch = original; }
});
test('refund processed before any winner prevents the refunded capture winning later', async () => {
  const f = buildCanonicalPaymentRaceFixture(); const id = f.ids.bookingId;
  const attempt = {...f.paymentAttempt, razorpayPaymentId: f.ids.razorpayPaymentId};
  const db = new AtomicFirestore({[`bookings/${id}`]: f.booking,
    [`bookings/${id}/paymentAttempts/${attempt.paymentAttemptId}`]: attempt});
  await applyPaymentRefundEventV3({firestore: db, bookingId: id, paymentAttemptId: attempt.paymentAttemptId,
    paymentId: attempt.razorpayPaymentId, refundId: 'early', amountPaise: attempt.amountPaise,
    eventName: 'refund.processed', now: f.authoritativeNow});
  const result = finalizeCapturedBookingPaymentV3({...f, bookingId: id, verificationSource: 'webhook',
    paymentAttempt: db.store.get(`bookings/${id}/paymentAttempts/${attempt.paymentAttemptId}`)});
  assert.equal(result.ok, false);
  assert.equal(db.store.get(`bookings/${id}`).payment.razorpayPaymentId, f.booking.payment.razorpayPaymentId);
  const winner = finalizeCapturedBookingPaymentV3({...f, bookingId: id, verificationSource: 'webhook',
    paymentAttempt: {...f.paymentAttempt, paymentAttemptId: 'B', razorpayOrderId: 'order_B'},
    razorpayPayment: {...f.razorpayPayment, id: 'pay_B', orderId: 'order_B'}});
  assert.equal(winner.ok, true);
  await persistFinalizePaymentResultV3({firestore: db, bookingId: id, result: winner});
  assert.equal(db.store.get(`bookings/${id}`).payment.razorpayPaymentId, 'pay_B');
});
test('excess refund bypasses canonical manual dispute records', async () => {
  const s = await scenario();
  s.db._set(`refunds/${s.id}`, {executionMode: 'MANUAL', origin: 'DISPUTE_RESOLUTION', amountPaise: 200});
  const before = snapshot(s.db, s.id);
  await s.webhook(s.loser, 'refund.processed');
  assert.deepEqual(snapshot(s.db, s.id), before);
});
test('unmapped refund delivery is retryable and succeeds once capture mapping arrives', async () => {
  const {processRazorpayWebhookEnvelopeV3} = require('../lib/booking/application/paymentWebhookEventsV3');
  const s = await scenario();
  const path = `bookings/${s.id}/paymentAttempts/${s.loser}`;
  const attempt = s.db.store.get(path);
  s.db.store.delete(path);
  const args = {firestore: s.db, signature: 'signature', rawBody: Buffer.from('{}'),
    payload: {event: 'refund.processed', payload: {refund: {entity: {
      id: 'unmapped', payment_id: `pay_${s.loser}`, amount: s.amount}}}},
    webhookSecret: 'secret', keyId: 'key', keySecret: 'secret', verifySignature: () => true,
    authoritativeNow: s.f.authoritativeNow, routeCanonicalWebhook: routeCanonicalWebhookEventV3};
  await assert.rejects(processRazorpayWebhookEnvelopeV3(args), /mapping/);
  assert.ok([...s.db.store.values()].some(d => d.processingState === 'RETRYABLE_FAILURE'));
  s.db._set(path, attempt);
  const result = await processRazorpayWebhookEnvelopeV3(args);
  assert.equal(result.statusCode, 200);
  assert.equal(s.db.store.get(path).state, 'REFUNDED');
});
test('refund webhook rejects fractional amounts without rounding', async () => {
  const s = await scenario(); const before = [...s.db.store];
  await assert.rejects(s.webhook(s.loser, 'refund.processed', 'fractional', 1.5));
  assert.deepEqual([...s.db.store], before);
});
test('outgoing refund claim blocks stale confirmation while gateway response is pending', async () => {
  const s = await scenario(); const original = gateway.processRazorpayRefundV3;
  gateway.processRazorpayRefundV3 = async () => {
    const pending = s.db.store.get(`bookings/${s.id}/paymentAttempts/${s.loser}`);
    const result = s.finalize(s.loser, s.f.booking, pending);
    assert.equal(result.ok, false);
    return {status: 'pending', razorpayRefundId: 'outgoing'};
  };
  try {
    assert.equal(await submitRefundInstructionV3({firestore: s.db, bookingId: s.id,
      paymentAttemptId: s.loser, keyId: 'key', keySecret: 'secret'}), 'REFUND_PENDING');
  } finally { gateway.processRazorpayRefundV3 = original; }
});
test('winning attempt cannot submit a legacy instruction belonging to an excess attempt', async () => {
  const s = await scenario();
  s.db._set(`bookings/${s.id}/paymentAttempts/${s.winner}`, {state: 'REFUND_REQUIRED'}, {merge: true});
  s.db._set(`refunds/${s.id}`, {paymentAttemptId: s.loser, refundAmountPaise: s.amount, state: 'required'});
  const before = [...s.db.store];
  assert.equal(await submitRefundInstructionV3({firestore: s.db, bookingId: s.id,
    paymentAttemptId: s.winner, keyId: 'key', keySecret: 'secret'}), 'SKIPPED');
  assert.deepEqual([...s.db.store], before);
});
