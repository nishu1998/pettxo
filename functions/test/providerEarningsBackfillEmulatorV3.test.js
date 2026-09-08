const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {reconcileProviderEarningsBatchDataV3: reconcile} = require('../lib/booking/application/providerEarningsBackfillV3');
const enabled = /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? '');
async function fixture(fn) {
  const app=initializeApp({projectId:'demo-earnings-backfill'},randomUUID());
  const db=getFirestore(app); const id=randomUUID(); const at=Timestamp.now();
  await db.doc('users/admin').set({adminRole:'superAdmin'});
  await db.doc(`bookings/${id}`).set({providerId:'provider',parentId:'parent',serviceId:'service',state:'COMPLETED_FINAL',
    lifecycle:{paidAt:at,finalizedAt:at},financials:{providerPayoutPaise:85000,currency:'INR'},
    payment:{status:'CONFIRMED',razorpayPaymentId:'winner'},dispute:{status:'none'},payout:{status:'READY'}});
  const run=(options={})=>reconcile({firestore:db,auth:{uid:'admin'},input:{ids:[id],dryRun:false,...options}});
  try {await fn({db,id,run});} finally {await db.terminate();await deleteApp(app);}
}
test('backfill emulator: concurrent reruns create one projection and one audit', {skip:!enabled}, async()=>{
  await fixture(async({db,id,run})=>{
    const results=await Promise.all([run(),run()]);
    assert.equal(results.reduce((n,r)=>n+r.counts.created,0),1);
    assert.equal(results.reduce((n,r)=>n+r.counts.unchanged,0),1);
    assert.equal((await db.doc(`providerEarnings/${id}`).get()).data().amountPaise,85000);
    assert.equal((await db.collection('providerEarningsReconciliationAudit').where('bookingId','==',id).get()).size,1);
  });
});
test('backfill emulator: dry run writes nothing and a duplicate blocks materialization', {skip:!enabled}, async()=>{
  await fixture(async({db,id,run})=>{
    assert.equal((await run({dryRun:true})).counts.created,1);
    assert.equal((await db.doc(`providerEarnings/${id}`).get()).exists,false);
    assert.equal((await db.collection('providerEarningsReconciliationAudit').where('bookingId','==',id).get()).size,0);
    await db.doc(`providerEarnings/duplicate_${id}`).set({bookingId:id,providerId:'provider',amountPaise:85000});
    assert.equal((await run()).counts.skipped,1);
    assert.equal((await db.doc(`providerEarnings/${id}`).get()).exists,false);
  });
});
test('backfill emulator: audit failure rolls projection back and retry succeeds', {skip:!enabled}, async()=>{
  await fixture(async({db,id,run})=>{
    const failing={collection:name=>db.collection(name),runTransaction:fn=>db.runTransaction(tx=>fn({
      get:ref=>tx.get(ref),set:(ref,data,options)=>{
        tx.set(ref,data,...(options?[options]:[]));
        if(ref.path.startsWith('providerEarningsReconciliationAudit/')) throw Error('injected audit failure');
      },
    }))};
    const result=await reconcile({firestore:failing,auth:{uid:'admin'},input:{ids:[id],dryRun:false}});
    assert.deepEqual(result.retryIds,[id]);
    assert.equal((await db.doc(`providerEarnings/${id}`).get()).exists,false);
    assert.equal((await db.collection('providerEarningsReconciliationAudit').where('bookingId','==',id).get()).size,0);
    assert.equal((await run()).counts.created,1);
  });
});
