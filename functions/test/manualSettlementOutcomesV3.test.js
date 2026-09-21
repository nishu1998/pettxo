const test = require('node:test');
const assert = require('node:assert/strict');
const {FakeFirestore} = require('./helpers/canonicalPaymentRaceHarness');
const {buildConfirmedSlotBookingFixture, buildCompletedFinalBookingFixture} = require('../lib/booking/schema/bookingFixtures');
const {calculateBookingFinancialSnapshot} = require('../lib/booking/domain/bookingPricing');
const {applyConfirmedBookingCancellationV3, persistConfirmedBookingCancellationV3} = require('../lib/booking/application/cancellationOrchestrationV3');
const {finalizeCanonicalNoShowV3} = require('../lib/booking/application/serviceStartOrchestrationV3');
const {synchronizeManualSettlementBookingV3} = require('../lib/booking/application/manualSettlementSyncV3');
const {recordManualCustomerRefundDataV3, recordManualProviderPayoutDataV3} = require('../lib/booking/bookingManualSettlementOperationsV3');
const {applyPaymentRefundEventV3} = require('../lib/booking/application/paymentRefundsV3');
const {submitRefundInstructionV3} = require('../lib/booking/application/paymentOrchestrationV3');
const {parseManualSettlementSourceV3} = require('../lib/booking/application/manualSettlementTypesV3');
const gateway = require('../lib/booking/application/razorpayGateway');

function merge(a, b) {
  const out = {...a};
  for (const [key, value] of Object.entries(b)) {
    if (key.includes('.')) {
      const [head, ...tail] = key.split('.'); out[head] = merge(out[head] ?? {}, {[tail.join('.')]: value});
    } else out[key] = value?.constructor?.name === 'ServerTimestampTransform' ? new Date() : value && value.constructor === Object ? merge(out[key] ?? {}, value) : value;
  }
  return out;
}
class StrictFirestore extends FakeFirestore {
  _set(path, data, options = {}) { this.store.set(path, options.merge ? merge(this.store.get(path) ?? {}, data) : data); }
  async runTransaction(fn) {
    const writes = [];
    const tx = {
      get: async (ref) => { assert.equal(writes.length, 0, 'Firestore reads must precede writes'); return ref.get(); },
      set: (ref, data, options) => writes.push([ref.path, data, options]),
    };
    const result = await fn(tx);
    for (const args of writes) this._set(...args);
    return result;
  }
}
function omitUndefined(value) {
  if (Array.isArray(value)) return value.map(omitUndefined);
  if (value?.constructor === Object) return Object.fromEntries(Object.entries(value).filter(([,v])=>v!==undefined).map(([k,v])=>[k,omitUndefined(v)]));
  return value;
}
function seed(coupon = 0) {
  const booking = omitUndefined(buildConfirmedSlotBookingFixture());
  booking.financials = calculateBookingFinancialSnapshot({currency:'INR', serviceSubtotalPaise:100000, couponDiscountPaise:coupon});
  const id = 'root-booking';
  const attempt = {paymentAttemptId:booking.payment.paymentAttemptId, bookingId:id,
    razorpayPaymentId:booking.payment.razorpayPaymentId, razorpayOrderId:booking.payment.razorpayOrderId,
    state:'CONFIRMED', amountPaise:booking.financials.customerPaidPaise, currency:'INR'};
  const db = new StrictFirestore({
    [`bookings/${id}`]:booking,
    [`bookings/${id}/paymentAttempts/${attempt.paymentAttemptId}`]:attempt,
    'users/super':{role:'admin', adminRole:'superAdmin', isActive:true},
    [`users/${booking.providerId}/providerBankDetails/main`]:{schemaVersion:2, status:'submitted',
      hasBankAccount:true, accountNumberMasked:'****1234', preferredPayoutMethod:'BANK_ACCOUNT'},
  });
  return {db, id, booking, attempt};
}
const op = (f, type) => f.db.store.get(`manualSettlementObligations/${type === 'refund' ? 'customer_refund_cancellation_' : 'provider_payout_'}${f.id}`);
async function cancel(f, hours, actor = 'CUSTOMER', extra = {}) {
  const result = applyConfirmedBookingCancellationV3({bookingId:f.id, booking:f.booking,
    paymentAttempt:f.attempt, actorType:actor, actorId:actor === 'CUSTOMER' ? f.booking.parentId : f.booking.providerId,
    reasonCode:'requested', authoritativeNow:new Date(f.booking.serviceAnchorAt.getTime() - hours*3600000), ...extra});
  await persistConfirmedBookingCancellationV3({firestore:f.db, bookingId:f.id, result});
  return result;
}
async function sync(f, now = new Date('2030-01-01')) { return synchronizeManualSettlementBookingV3({firestore:f.db, bookingId:f.id, now}); }
async function auto(f) { return submitRefundInstructionV3({firestore:f.db, bookingId:f.id,
  paymentAttemptId:f.attempt.paymentAttemptId, keyId:'unused', keySecret:'unused'}); }
async function record(f, refundId = 'rf_manual') { return recordManualCustomerRefundDataV3({firestore:f.db,
  auth:{uid:'super'}, input:{obligationId:op(f,'refund').obligationId, razorpayRefundId:refundId}}); }
async function confirm(f, eventName = 'refund.processed', overrides = {}) { return applyPaymentRefundEventV3({
  firestore:f.db, bookingId:f.id, paymentAttemptId:f.attempt.paymentAttemptId,
  paymentId:f.attempt.razorpayPaymentId, refundId:'rf_manual', amountPaise:op(f,'refund').amountPaise,
  eventName, now:new Date(), ...overrides}); }

for (const [hours, refund, provider] of [[25,95000,0],[24,75000,15000],[10,50000,35000],[4,25000,60000],[1,0,85000]]) {
  test(`cancellation ${hours}h creates exact root obligations and is manual-only`, async () => {
    const f = seed(); const result = await cancel(f,hours);
    assert.equal(op(f,'refund')?.amountPaise ?? 0, refund);
    assert.equal(op(f,'provider')?.amountPaise ?? 0, provider);
    if (refund) { assert.equal(op(f,'refund').source,'CUSTOMER_CANCELLATION'); assert.equal(op(f,'refund').status,'READY'); }
    if (provider) assert.equal(op(f,'provider').source,'CUSTOMER_CANCELLATION');
    const original = gateway.processRazorpayRefundV3;
    let calls = 0; gateway.processRazorpayRefundV3 = async () => { calls++; throw Error('must not submit'); };
    try { assert.equal(await auto(f),'SKIPPED'); assert.equal(calls,0); } finally { gateway.processRazorpayRefundV3 = original; }
    await persistConfirmedBookingCancellationV3({firestore:f.db, bookingId:f.id, result:{...result,idempotentReplay:true}});
    await sync(f); await sync(f);
    assert.equal([...f.db.store.keys()].filter(p=>p.startsWith('manualSettlementObligations/')).length, Number(refund>0)+Number(provider>0));
  });
}
test('coupon cancellation preserves paid-money basis, including zero-paid coupon', async () => {
  for (const coupon of [30000,100000]) {
    const f=seed(coupon); await cancel(f,10);
    assert.equal(op(f,'refund')?.amountPaise ?? 0, Math.floor((100000-coupon)*.5));
    assert.equal(op(f,'provider')?.amountPaise ?? 0, Math.floor((100000-coupon)*.35));
  }
});
test('provider cancellation is a full manual customer refund with no provider payout', async () => {
  const f=seed(30000); await cancel(f,10,'PROVIDER');
  assert.equal(op(f,'refund').source,'PROVIDER_CANCELLATION'); assert.equal(op(f,'refund').amountPaise,70000);
  assert.equal(op(f,'provider'),undefined); assert.equal(await auto(f),'SKIPPED');
});
test('instruction is not completed money; an existing execution cannot be overwritten', async () => {
  const f=seed(); await assert.rejects(cancel(f,25,'CUSTOMER',{existingRefund:{state:'submitting',refundAmountPaise:1000}}), /reconciled/);
  assert.equal(op(f,'refund'),undefined);
});
test('prior completed refund reduces cancellation basis without subtracting it twice', async () => {
  const f=seed(); await cancel(f,25,'CUSTOMER',{existingRefund:{state:'processed',refundAmountPaise:20000}});
  assert.equal(op(f,'refund').amountPaise,76000);
});
test('manual refund record, confirmation, delayed events, and materialization cannot repay completed money', async () => {
  const f=seed(); await cancel(f,10); const earning=f.db.store.get(`providerEarnings/${f.id}`);
  assert.equal((await record(f)).code,'RECORDED'); assert.equal((await record(f)).code,'ALREADY_PROCESSING');
  await assert.rejects(record(f,'different'), /different execution/);
  assert.equal(await auto(f),'SKIPPED'); await sync(f); assert.equal(op(f,'refund').status,'PROCESSING');
  await assert.rejects(confirm(f,'refund.processed',{amountPaise:50001}), /amount/);
  await confirm(f); await confirm(f); await confirm(f,'refund.failed'); await sync(f);
  assert.equal(op(f,'refund').status,'COMPLETED'); assert.equal(f.db.store.get(`refunds/${f.id}`).refundedAmountPaise,50000);
  assert.equal((await record(f)).code,'ALREADY_COMPLETED');
  assert.equal(f.db.store.get(`providerEarnings/${f.id}`).providerFinalEntitlementPaise,earning.providerFinalEntitlementPaise);
  assert.equal([...f.db.store.keys()].some(p=>p.startsWith('disputes/')||p.startsWith('bookingDisputeResolutions/')),false);
  assert.equal([...f.db.store.values()].filter(v=>v.type==='CUSTOMER_REFUND').length,1);
  assert.equal(op(f,'provider').status,'READY');
});
test('manual refund rejects stale amount and unauthorized role', async () => {
  const f=seed(); await cancel(f,25); op(f,'refund').amountPaise++;
  await assert.rejects(record(f),/Stale/);
  await assert.rejects(recordManualCustomerRefundDataV3({firestore:f.db, auth:{uid:'nobody'},input:{obligationId:op(f,'refund').obligationId}}));
});
async function noShow(f) {
  const now=new Date(f.booking.schedule.scheduledEndAt.getTime()+1);
  await finalizeCanonicalNoShowV3({firestore:f.db,bookingId:f.id,authoritativeNow:now});
}
test('no-show automatically creates HELD root payout then releases the same obligation after 24 hours', async () => {
  const f=seed(); await noShow(f);
  assert.equal(op(f,'provider').source,'NO_SHOW'); assert.equal(op(f,'provider').status,'HELD');
  const id=op(f,'provider').obligationId; await sync(f,new Date(f.booking.schedule.scheduledEndAt.getTime()+23*3600000));
  assert.equal(op(f,'provider').status,'HELD'); await sync(f); assert.equal(op(f,'provider').status,'READY');
  assert.equal(op(f,'provider').obligationId,id); await sync(f);
  assert.equal([...f.db.store.keys()].filter(p=>p.startsWith('manualSettlementObligations/')).length,1);
});
test('no-show preserves coupon-funded listed-price entitlement and missing profile does not erase it', async () => {
  const f=seed(90000); f.db.store.delete(`users/${f.booking.providerId}/providerBankDetails/main`);
  await noShow(f); await sync(f); assert.equal(op(f,'provider').amountPaise,85000); assert.equal(op(f,'provider').status,'HELD');
  assert.match(op(f,'provider').holdReason,/profile/);
});
test('active no-show dispute remains visible HELD and cannot execute', async () => {
  const f=seed(); f.booking.dispute.status='OPEN'; await noShow(f); await sync(f);
  assert.equal(op(f,'provider').status,'HELD'); assert.match(op(f,'provider').holdReason,/dispute/);
  await assert.rejects(recordManualProviderPayoutDataV3({firestore:f.db,auth:{uid:'super'},input:{obligationId:op(f,'provider').obligationId,transactionReference:'tx'}}));
});
test('provider execution rejects stale amounts then records once from final cancellation entitlement', async () => {
  const f=seed(); await cancel(f,1); await sync(f); const obligation=op(f,'provider');
  obligation.amountPaise=100000;
  await assert.rejects(recordManualProviderPayoutDataV3({firestore:f.db,auth:{uid:'super'},input:{obligationId:obligation.obligationId,transactionReference:'tx'}}),/Stale/);
  await sync(f);
  const args={firestore:f.db,auth:{uid:'super'},input:{obligationId:obligation.obligationId,transactionReference:'tx'}};
  await recordManualProviderPayoutDataV3(args); await recordManualProviderPayoutDataV3(args); await sync(f);
  assert.equal(op(f,'provider').status,'COMPLETED'); assert.equal(f.db.store.get(`providerPayouts/${f.id}`).priorPaidPaise,85000);
});
test('sync preserves PROCESSING and NEEDS_ATTENTION obligations', async () => {
  for (const status of ['PROCESSING','NEEDS_ATTENTION']) {
    const f=seed(); await noShow(f); op(f,'provider').status=status; await sync(f); assert.equal(op(f,'provider').status,status);
  }
});
test('unknown sources fail closed', () => { assert.throws(()=>parseManualSettlementSourceV3('OLD_UNKNOWN'),/Unsupported/); });
test('no-show executes once at its canonical listed-price entitlement', async () => {
  const f=seed(90000); await noShow(f); await sync(f);
  // Fixture dates are historical; recording evaluates current time.
  const args={firestore:f.db,auth:{uid:'super'},input:{obligationId:op(f,'provider').obligationId,transactionReference:'coupon-payout'}};
  await recordManualProviderPayoutDataV3(args); await recordManualProviderPayoutDataV3(args);
  assert.equal(f.db.store.get(`providerPayouts/${f.id}`).priorPaidPaise,85000);
});
test('failed refund remains non-executable; processed evidence may resolve the same refund', async () => {
  const f=seed(); await cancel(f,10); await record(f); await confirm(f,'refund.failed'); await sync(f);
  assert.equal(op(f,'refund').status,'NEEDS_ATTENTION'); assert.equal(op(f,'provider').status,'HELD');
  await assert.rejects(record(f,'new-refund'),/not ready/); await confirm(f); await sync(f);
  assert.equal(op(f,'refund').status,'COMPLETED'); assert.equal(op(f,'provider').status,'READY');
});
test('already processed cancellation with missing obligation does not create a second READY refund', async () => {
  const f=seed(); await cancel(f,25); await record(f); await confirm(f);
  f.db.store.delete(`manualSettlementObligations/${op(f,'refund').obligationId}`);
  await sync(f); assert.equal(op(f,'refund'),undefined);
});
test('in-flight payout cannot be recorded even when the obligation is stale READY', async () => {
  const f=seed(); await cancel(f,1); await sync(f); f.db.store.get(`providerPayouts/${f.id}`).status='PROCESSING';
  await assert.rejects(recordManualProviderPayoutDataV3({firestore:f.db,auth:{uid:'super'},input:{obligationId:op(f,'provider').obligationId,transactionReference:'tx'}}),/reconciliation/);
  await sync(f); assert.equal(op(f,'provider').status,'NEEDS_ATTENTION');
  assert.equal(f.db.store.get(`providerPayouts/${f.id}`).status,'PROCESSING');
});

const emulatorEnabled = /^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? '');
test('emulator: concurrent confirmations and payout recordings settle once', {skip: !emulatorEnabled}, async () => {
  const {initializeApp, deleteApp} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const app = initializeApp({projectId:'demo-pettxo-phase1'}, 'manual-settlement-integration');
  const db = getFirestore(app);
  const f = seed(); await cancel(f,10);
  try {
    // Dedicated demo project and explicit loopback emulator only.
    const batch=db.batch(); for (const [path,data] of f.db.store) batch.set(db.doc(path), omitUndefined(data));
    await batch.commit();
    const refundId=op(f,'refund').obligationId, payoutId=op(f,'provider').obligationId;
    const recordArgs={firestore:db,auth:{uid:'super'},input:{obligationId:refundId,razorpayRefundId:'rf_concurrent'}};
    await Promise.all([recordManualCustomerRefundDataV3(recordArgs),recordManualCustomerRefundDataV3(recordArgs)]);
    const confirmation={firestore:db,bookingId:f.id,paymentAttemptId:f.attempt.paymentAttemptId,
      paymentId:f.attempt.razorpayPaymentId,refundId:'rf_concurrent',amountPaise:50000,eventName:'refund.processed',now:new Date()};
    await Promise.all(Array.from({length:4},()=>applyPaymentRefundEventV3(confirmation)));
    assert.equal((await db.doc(`refunds/${f.id}`).get()).data().refundedAmountPaise,50000);
    await synchronizeManualSettlementBookingV3({firestore:db,bookingId:f.id});
    const payoutArgs={firestore:db,auth:{uid:'super'},input:{obligationId:payoutId,transactionReference:'utr_concurrent'}};
    await Promise.all(Array.from({length:3},()=>recordManualProviderPayoutDataV3(payoutArgs)));
    assert.equal((await db.doc(`providerPayouts/${f.id}`).get()).data().priorPaidPaise,35000);
    assert.equal((await db.doc(`manualSettlementObligations/${payoutId}`).get()).data().status,'COMPLETED');
  } finally { await deleteApp(app); }
});
test('scheduler refreshes only enrolled existing obligations, without historical booking discovery', async () => {
  const {synchronizeExistingManualPayoutsV3}=require('../lib/booking/bookingManualSettlementSchedulerV3');
  const f=seed(); await noShow(f);
  f.db.store.set('bookings/historical-missing', f.booking);
  f.db.store.set('manualSettlementObligations/provider_payout_old', {bookingId:'historical-missing',obligationType:'PROVIDER_PAYOUT',status:'HELD'});
  const original=f.db.collection.bind(f.db);
  f.db.collection=(name)=>{
    const collection=original(name);
    collection.orderBy=()=>{
      let after='', limit=100;
      const query={limit(n){limit=n;return query;},startAfter(id){after=id;return query;},async get(){
        const docs=f.db._docsForCollection(name).filter(d=>d.id>after).sort((a,b)=>a.id.localeCompare(b.id)).slice(0,limit);
        return {docs,empty:docs.length===0,size:docs.length};
      }}; return query;
    };return collection;
  };
  await synchronizeExistingManualPayoutsV3(f.db,new Date('2030-01-01'));
  assert.equal(op(f,'provider').status,'READY');
  assert.equal(f.db.store.get('manualSettlementObligations/provider_payout_old').status,'HELD');
  assert.equal(f.db.store.has('manualSettlementObligations/provider_payout_historical-missing'),false);
});
test('resolved no-show uses final dispute entitlement and retains profile/deadline holds', async () => {
  const f=seed(); await noShow(f);
  f.db.store.set(`bookingDisputeResolutions/resolution_${f.id}`,{resolutionId:`resolution_${f.id}`,disputeId:f.id,
    providerFinalEntitlementPaise:25000,customerRefundPaise:10000});
  f.db.store.set(`refunds/${f.id}`,{origin:'DISPUTE_RESOLUTION',executionMode:'MANUAL',state:'pending',refundAmountPaise:10000});
  f.db.store.delete(`users/${f.booking.providerId}/providerBankDetails/main`);
  await sync(f);
  assert.equal(op(f,'provider').source,'DISPUTE_RESOLUTION'); assert.equal(op(f,'provider').amountPaise,25000);
  assert.equal(op(f,'provider').status,'HELD'); assert.match(op(f,'provider').holdReason,/profile/);
  assert.equal(f.db.store.get(`manualSettlementObligations/customer_refund_resolution_${f.id}`).amountPaise,10000);
});
test('authoritative attempt refund totals also reduce the cancellation basis', async () => {
  const f=seed(); f.attempt.refundedAmountPaise=20000;
  await cancel(f,25);
  assert.equal(op(f,'refund').amountPaise,76000);
  assert.equal(f.db.store.get(`refunds/${f.id}`).refundedBeforeCancellationPaise,20000);
});
test('emulator: cancellation and no-show create obligations in their outcome transactions', {skip: !emulatorEnabled}, async () => {
  const {initializeApp,deleteApp}=require('firebase-admin/app');
  const {getFirestore}=require('firebase-admin/firestore');
  for (const outcome of ['cancel','noshow']) {
    const app=initializeApp({projectId:`demo-pettxo-phase1-${outcome}`},`manual-outcome-${outcome}`);
    const db=getFirestore(app);const f=seed();
    try {
      const batch=db.batch();for(const [path,data] of f.db.store) batch.set(db.doc(path),omitUndefined(data));await batch.commit();
      if(outcome==='cancel') {
        const result=applyConfirmedBookingCancellationV3({bookingId:f.id,booking:f.booking,paymentAttempt:f.attempt,
          actorType:'CUSTOMER',actorId:f.booking.parentId,reasonCode:'requested',
          authoritativeNow:new Date(f.booking.serviceAnchorAt.getTime()-10*3600000)});
        await persistConfirmedBookingCancellationV3({firestore:db,bookingId:f.id,result});
        assert.equal((await db.doc(`manualSettlementObligations/customer_refund_cancellation_${f.id}`).get()).data().amountPaise,50000);
        assert.equal((await db.doc(`refunds/${f.id}`).get()).data().executionMode,'MANUAL');
      } else {
        await finalizeCanonicalNoShowV3({firestore:db,bookingId:f.id,
          authoritativeNow:new Date(f.booking.schedule.scheduledEndAt.getTime()+1)});
        assert.equal((await db.doc(`manualSettlementObligations/provider_payout_${f.id}`).get()).data().status,'HELD');
        await synchronizeManualSettlementBookingV3({firestore:db,bookingId:f.id,now:new Date('2030-01-01')});
        assert.equal((await db.doc(`manualSettlementObligations/provider_payout_${f.id}`).get()).data().status,'READY');
      }
    } finally {await deleteApp(app);}
  }
});
test('unresolved canonical refund earnings cannot be released by normal completion synchronization', async () => {
  const f=seed(); f.booking=omitUndefined(buildCompletedFinalBookingFixture());
  f.db.store.set(`bookings/${f.id}`,f.booking);
  f.db.store.set(`providerEarnings/${f.id}`,{earningsStatus:'HELD',earningsOutcome:'CANONICAL_REFUND_REVIEW',providerFinalEntitlementPaise:null});
  await sync(f); assert.equal(op(f,'provider').status,'HELD');assert.match(op(f,'provider').holdReason,/canonical review/);
});


test('settlement metadata sync with absent earnings preserves payout entitlement without creating a projection', async () => {
  const f=seed(); await cancel(f,1);
  const amount=op(f,'provider').amountPaise;
  f.db.store.delete(`providerEarnings/${f.id}`);
  await sync(f);
  assert.equal(f.db.store.has(`providerEarnings/${f.id}`),false);
  assert.equal(op(f,'provider').amountPaise,amount);
  assert.equal(f.db.store.get(`providerPayouts/${f.id}`).providerEntitlementPaise,amount);
});
