const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,createHash}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {buildConfirmedSlotBookingFixture}=require('../lib/booking/schema/bookingFixtures');
const {verifyBookingStartOtpV3,reconcileCanonicalServiceStartArtifactsV3,finalizeCanonicalNoShowV3,SERVICE_START_POLICY_VERSION}=require('../lib/booking/application/serviceStartOrchestrationV3');
const {reconcileCanonicalCompletionStateV3,finalizeCompletedBookingV3}=require('../lib/booking/application/serviceCompletionOrchestrationV3');
const {buildProviderEarningsProjectionV3}=require('../lib/booking/application/providerEarningsV3');
const enabled=/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST||'');
async function fixture(fn){
 const app=initializeApp({projectId:'demo-lifecycle-phase1'},randomUUID());const db=getFirestore(app);db.settings({ignoreUndefinedProperties:true});
 const id=randomUUID(),booking=buildConfirmedSlotBookingFixture(),at=new Date('2026-07-23T05:55:00Z');
 try{await db.doc(`bookings/${id}`).set(booking);await fn({db,id,booking,at});}finally{await db.terminate();await deleteApp(app);}
}
test('real Firestore OTP to final earnings preserves nested fields and the 24-hour review window',{skip:!enabled},async()=>{
 await fixture(async({db,id,booking,at})=>{
  await db.doc(`bookingPrivate/${id}`).set({bookingId:id,parentId:booking.parentId,providerId:booking.providerId,
    parentOtpCode:'482913',providerOtpHash:createHash('sha256').update(`${id}:482913`).digest('hex'),
    otpState:'ACTIVE',failedAttemptCount:0,lockedUntil:null,verifiedAt:null,contactUnlockedAt:booking.lifecycle.paidAt});
  await db.doc(`providerEarnings/${id}`).set({bookingId:id,providerId:booking.providerId,createdAt:booking.lifecycle.paidAt,
    ...buildProviderEarningsProjectionV3({entitlementPaise:booking.financials.providerPayoutPaise,phase:'PROVISIONAL',outcome:'PAYMENT_CONFIRMED'})});
  const original=(await db.doc(`bookings/${id}`).get()).data();
  assert.equal((await verifyBookingStartOtpV3({firestore:db,bookingId:id,providerId:booking.providerId,otpCandidate:'482913',requestAttemptId:'phase1',authoritativeNow:at})).code,'VERIFIED_STARTED');
  let stored=(await db.doc(`bookings/${id}`).get()).data();
  assert.equal(stored.lifecycle.otpEnteredAt.toMillis(),at.getTime());
  for(const[k,v]of Object.entries(original.lifecycle))if(k!=='otpEnteredAt')assert.deepEqual(stored.lifecycle[k],v,k);
  assert.equal(Object.keys(stored).some(k=>k.includes('.')),false);
  assert.equal((await db.doc(`providerEarnings/${id}`).get()).data().earningsStatus,'PROVISIONAL');
  assert.equal((await finalizeCanonicalNoShowV3({firestore:db,bookingId:id,authoritativeNow:new Date('2026-08-01')})).code,'STARTED');
  const completedAt=new Date(booking.schedule.scheduledEndAt.getTime()+1);
  assert.equal(await reconcileCanonicalCompletionStateV3({firestore:db,bookingId:id,authoritativeNow:completedAt}),'AUTO_COMPLETED_PENDING_REVIEW');
  stored=(await db.doc(`bookings/${id}`).get()).data();const beforeFinal=stored;
  const deadline=stored.lifecycle.reviewWindowEndsAt.toMillis();
  assert.equal(deadline-completedAt.getTime(),24*60*60*1000);
  assert.equal((await finalizeCompletedBookingV3({firestore:db,bookingId:id,authoritativeNow:new Date(deadline-1)})).code,'NOT_DUE');
  assert.equal((await finalizeCompletedBookingV3({firestore:db,bookingId:id,authoritativeNow:new Date(deadline)})).code,'FINALIZED');
  stored=(await db.doc(`bookings/${id}`).get()).data();
  assert.equal(stored.lifecycle.finalizedAt.toMillis(),deadline);
  for(const[k,v]of Object.entries(beforeFinal.lifecycle))if(k!=='finalizedAt')assert.deepEqual(stored.lifecycle[k],v,k);
  assert.equal(Object.keys(stored).some(k=>k.includes('.')),false);
  const earning=(await db.doc(`providerEarnings/${id}`).get()).data();
  assert.equal(earning.earningsStatus,'FINALIZED');assert.equal(earning.providerFinalEntitlementPaise,booking.financials.providerPayoutPaise);
  assert.equal(earning.status,'HELD'); // Missing bank profile never blocks earnings finality.
  assert.equal((await finalizeCompletedBookingV3({firestore:db,bookingId:id,authoritativeNow:new Date(deadline+1)})).code,'ALREADY_FINAL');
  assert.deepEqual((await db.doc(`providerEarnings/${id}`).get()).data(),earning);
 });
});
async function seedRecovery({db,id,booking,at}){
 await db.doc(`bookings/${id}`).set({state:'IN_PROGRESS',stateQueryValue:'IN_PROGRESS','lifecycle.otpEnteredAt':Timestamp.fromDate(at)},{merge:true});
 await db.doc(`bookingServiceStarts/${id}`).set({bookingId:id,providerId:booking.providerId,parentId:booking.parentId,
  verifiedAt:Timestamp.fromDate(at),otpVerifiedAt:Timestamp.fromDate(at),stateBefore:'CONFIRMED',stateAfter:'IN_PROGRESS',
  serviceAnchorAt:booking.schedule.scheduledStartAt,policyVersion:SERVICE_START_POLICY_VERSION});
}
test('real Firestore concurrent evidence recovery is idempotent',{skip:!enabled},async()=>{
 await fixture(async f=>{
  await seedRecovery(f);const {db,id,booking}=f;
  const args={firestore:db,bookingId:id,allowHistoricalRecovery:true,authoritativeNow:new Date('2026-07-24')};
  const results=await Promise.all([reconcileCanonicalServiceStartArtifactsV3(args),reconcileCanonicalServiceStartArtifactsV3(args)]);
  assert.deepEqual(results.sort(),['NOOP','REPAIRED']);
  const stored=(await db.doc(`bookings/${id}`).get()).data();
  assert.equal(stored.lifecycle.otpEnteredAt.toMillis(),f.at.getTime());
  assert.equal(stored.lifecycle.paidAt.toMillis(),booking.lifecycle.paidAt.getTime());
  assert.equal((await db.doc(`providerEarnings/${id}`).get()).exists,false);
 });
});
test('recovery rechecks concurrent terminal state before committing',{skip:!enabled},async()=>{
 await fixture(async f=>{
  await seedRecovery(f);const {db,id}=f;let calls=0;
  const wrapped={collection:name=>db.collection(name),runTransaction:async fn=>{
   if(calls++===0){
    await db.runTransaction(tx=>fn({get:ref=>tx.get(ref),set(){}}),{readOnly:true});
    await db.doc(`bookings/${id}`).set({state:'CANCELLED',stateQueryValue:'CANCELLED'},{merge:true});
   }
   return db.runTransaction(fn);
  }};
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3({firestore:wrapped,bookingId:id,allowHistoricalRecovery:true,authoritativeNow:new Date('2026-07-24')}),'NOOP');
  const stored=(await db.doc(`bookings/${id}`).get()).data();assert.equal(stored.state,'CANCELLED');assert.equal(stored.lifecycle.otpEnteredAt,null);
 });
});

test('real Firestore rollout leaves historical evidence untouched until explicit Phase 2 opt-in',{skip:!enabled},async()=>{
 await fixture(async f=>{
  await seedRecovery(f);const {db,id}=f;
  const before=(await db.doc(`bookings/${id}`).get()).data();
  const args={firestore:db,bookingId:id,authoritativeNow:new Date('2026-09-17')};
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
  assert.deepEqual((await db.doc(`bookings/${id}`).get()).data(),before);
  assert.equal(await reconcileCanonicalCompletionStateV3(args),'NOOP');
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3({...args,allowHistoricalRecovery:true}),'REPAIRED');
 });
});

test('real Firestore legacy combined-segment no-show requires release boundary or explicit Phase 2',{skip:!enabled},async()=>{
 await fixture(async({db,id,booking})=>{
  const schedule=structuredClone(booking.schedule),slot=schedule.slots[0];
  const middle=new Date((slot.startAt.getTime()+slot.endAt.getTime())/2);
  schedule.slots=[{...slot,slotId:'first',endAt:middle,durationMinutes:slot.durationMinutes/2},
   {...slot,slotId:'second',startAt:middle,durationMinutes:slot.durationMinutes/2}];
  schedule.slotCount=2;schedule.segmentCount=1;
  schedule.firstSegmentEndAt=schedule.finalEndAt=schedule.scheduledEndAt;
  schedule.segments=[{serviceDateKey:slot.dateKey,slotIds:['first','second'],startAt:slot.startAt,endAt:slot.endAt,
   durationMinutes:slot.durationMinutes,schedulingMode:slot.schedulingMode||'fixedDuration'}];
  await db.doc(`bookings/${id}`).set({schedule},{merge:true});
  const args={firestore:db,bookingId:id,authoritativeNow:new Date('2026-09-17')};
  const before=(await db.doc(`bookings/${id}`).get()).data();
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NOOP');
  assert.deepEqual((await db.doc(`bookings/${id}`).get()).data(),before);
  assert.equal((await db.doc(`bookingNoShows/${id}`).get()).exists,false);
  const {writeLifecycleReleaseBoundaryV3}=require('../lib/booking/domain/lifecycleRolloutV3');
  await db.runTransaction(async transaction=>{
   transaction.set(db.doc(`bookings/${id}`),before);
   writeLifecycleReleaseBoundaryV3({firestore:db,transaction,bookingId:id,booking});
  });
  // Older handlers may replace the booking without any new fields.
  await db.doc(`bookings/${id}`).set(before);
  assert.equal(await reconcileCanonicalServiceStartArtifactsV3(args),'NO_SHOW_FINALIZED');
  assert.equal((await db.doc(`bookingNoShows/${id}`).get()).data().expectedServiceEndAt.toMillis(),slot.endAt.getTime());
 });
});
