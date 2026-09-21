const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {ensureServiceSlotCoverage} = require('../lib/services/serviceSlotCoverage');
const {buildServiceSlotCandidates} = require('../lib/services/serviceSlotCandidates');
const {assertPreCheckoutSlotCapacity,lockServiceSlotSelection} = require('../lib/services/serviceSlotBookingGuard');
const {buildCanonicalPaymentRaceFixture}=require('./helpers/canonicalPaymentRaceFixture');
const {finalizeCapturedBookingPaymentV3,persistFinalizePaymentResultV3}=require('../lib/booking/application/paymentOrchestrationV3');
const enabled=!!process.env.FIRESTORE_EMULATOR_HOST;
const now=Date.parse('2026-09-14T00:00:00+05:30');
const source={ownerUserId:'provider',status:'active',isActive:true,isVisibleToMarketplace:true,
  isDeleted:false,isPaused:false,availableDays:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
  startMinutes:540,endMinutes:720,sessionDurationMinutes:90,capacity:2};
async function fixture(run, patch={}) {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST,/^(127\.0\.0\.1|localhost):/);
  const app=initializeApp({projectId:'demo-slot-coverage'},`slots-${randomUUID()}`);
  const db=getFirestore(app);db.settings({ignoreUndefinedProperties:true});const id=randomUUID();const ref=db.doc(`services/${id}`);
  await ref.set({...source,...patch});
  const ensure=(opts={},database=db)=>ensureServiceSlotCoverage(database,id,{nowMs:now,...opts});
  const all=async()=> (await ref.collection('slots').orderBy('__name__').get()).docs.map(d=>({id:d.id,data:d.data(),updateTime:d.updateTime}));
  try {await run({db,id,ref,ensure,all});} finally {await db.terminate();await deleteApp(app);}
}
function emulator(name, run) {test(`emulator: ${name}`,{skip:!enabled},()=>fixture(run));}
function slotPayload(candidate, patch={}) {
  const {id,startAtMs,endAtMs,...data}=candidate;
  return {...data,startAt:Timestamp.fromMillis(startAtMs),endAt:Timestamp.fromMillis(endAtMs),...patch};
}
function selection(candidate,id) {
  return {bookingType:'SLOT',slots:[{slotId:candidate.id,startAt:new Date(candidate.startAtMs),endAt:new Date(candidate.endAtMs)}],
    slotCount:1,scheduledStartAt:new Date(candidate.startAtMs),scheduledEndAt:new Date(candidate.endAtMs),totalDurationMinutes:90};
}
emulator('expired legacy service receives future slots and keeps historical slots unchanged',async({ref,ensure,all})=>{
  await ref.collection('slots').doc('historical').set({startAt:Timestamp.fromMillis(now-86400000),acceptedCount:2,status:'closed'});
  const before=(await ref.collection('slots').doc('historical').get());
  const result=await ensure();assert.equal(result.createdCount,64);
  assert.deepEqual((await ref.collection('slots').doc('historical').get()).data(),before.data());
  assert.equal((await all()).length,65);
});
emulator('existing slots, timestamps, occupancy, claims and immutable confirmed bookings remain identical',async({db,id,ref,ensure,all})=>{
  const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  const slot=ref.collection('slots').doc(c.id),occ=ref.collection('slotOccupancy').doc(c.id),booking=db.doc(`bookings/${id}`);
  await slot.set(slotPayload(c,{acceptedCount:2,status:'full',isBookable:false,generatedAt:Timestamp.fromMillis(12345),custom:{bookingClaim:'keep'}}));
  await occ.set({confirmedUnits:2,capacitySnapshot:2,bookingClaims:{[id]:2}});
  await booking.set({serviceId:id,state:'CONFIRMED',schedule:selection(c,id),service:{capacitySnapshot:2}});
  const before=await Promise.all([slot,occ,booking].map(r=>r.get()));
  await ensure();
  const after=await Promise.all([slot,occ,booking].map(r=>r.get()));
  after.forEach((d,i)=>{assert.deepEqual(d.data(),before[i].data());assert.ok(d.updateTime.isEqual(before[i].updateTime));});
  const first=await all(); const again=await ensure();assert.equal(again.createdCount,0);assert.equal(again.existingCount,64);assert.deepEqual(await all(),first);
});
emulator('parallel replenishments create each ID once',async({ensure,all})=>{
  const results=await Promise.all([ensure(),ensure(),ensure()]);
  assert.equal(results.reduce((sum,r)=>sum+r.createdCount,0),64);assert.equal((await all()).length,64);
});
emulator('partial failure resumes with only remaining missing documents',async({db,ensure,all})=>{
  let calls=0;
  const failing=new Proxy(db,{get(target,key){if(key==='runTransaction')return async(...args)=>{if(++calls===2)throw new Error('injected');return target.runTransaction(...args);};const v=target[key];return typeof v==='function'?v.bind(target):v;}});
  await assert.rejects(ensure({},failing),/injected/);
  assert.equal((await all()).length,50);
  const before=await all();assert.equal((await ensure()).createdCount,14);
  const after=await all();for(const entry of before)assert.deepEqual(after.find(d=>d.id===entry.id),entry);
});
emulator('explicit current schedule fills partial coverage',async({id,ref,ensure,all})=>{
  await ref.update({schedulingMode:'fixedDuration'});
  const candidates=buildServiceSlotCandidates(id,source,now).candidates;
  await ref.collection('slots').doc(candidates[0].id).set(slotPayload(candidates[0]));
  assert.equal((await ensure()).createdCount,63);assert.equal((await all()).length,64);
});
emulator('service edit before a coverage transaction prevents stale writes',async({db,ref,ensure,all})=>{
  let injected=false;
  const edited=new Proxy(db,{get(target,key){if(key==='runTransaction')return async(...args)=>{if(!injected){injected=true;await ref.update({isPaused:true});}return target.runTransaction(...args);};const v=target[key];return typeof v==='function'?v.bind(target):v;}});
  await assert.rejects(ensure({},edited),/service_changed_retry_required/);assert.equal((await all()).length,0);
  assert.equal((await ensure()).eligibilitySkipReason,'paused');
});
emulator('schedule edits replace only obsolete unreferenced slots',async({ref,ensure})=>{
  await ensure();await ref.update({startMinutes:570,endMinutes:750});
  const result=await ensure({reconcileChangedSchedule:true});
  assert.equal(result.deletedUnbookedCount,64);assert.equal(result.createdCount,64);
  assert.equal((await ref.collection('slots').doc('2026-09-14_0540').get()).exists,false);
});
emulator('schedule edits protect pending requests, booked counts, and orphan occupancy across shifted IDs',async({db,id,ref,ensure})=>{
  await ensure();const candidates=buildServiceSlotCandidates(id,source,now).candidates;
  const pending=candidates[0],legacy=candidates[2],orphan=candidates[4];
  await db.doc(`bookings/${id}`).set({serviceId:id,state:'PENDING_PROVIDER',schedule:selection(pending,id)});
  await ref.collection('slots').doc(legacy.id).update({acceptedCount:1});
  await ref.collection('slotOccupancy').doc(orphan.id).set({confirmedUnits:1,bookingClaims:{orphan:1}});
  const refs=[pending,legacy,orphan].map(c=>ref.collection('slots').doc(c.id));const before=await Promise.all(refs.map(r=>r.get()));
  await ref.update({startMinutes:570,endMinutes:750});
  const result=await ensure({reconcileChangedSchedule:true});assert.ok(result.protectedCount>=3);
  const after=await Promise.all(refs.map(r=>r.get()));after.forEach((d,i)=>{assert.deepEqual(d.data(),before[i].data());assert.ok(d.updateTime.isEqual(before[i].updateTime));});
  for(const c of [pending,legacy,orphan])assert.equal((await ref.collection('slots').doc(`${c.dateKey}_0570`).get()).exists,false);
});
emulator('orphan occupancy on a missing ID is never resurrected with zero acceptedCount',async({id,ref,ensure})=>{
  const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  await ref.collection('slotOccupancy').doc(c.id).set({confirmedUnits:1,bookingClaims:{orphan:1}});
  const result=await ensure();assert.equal(result.createdCount,63);assert.equal(result.protectedCount,1);
  assert.equal((await ref.collection('slots').doc(c.id).get()).exists,false);
});
emulator('invalid edit does not erase the last valid slot schedule',async({ref,ensure,all})=>{
  await ensure();const before=await all();await ref.update({availableDays:[]});
  const result=await ensure({reconcileChangedSchedule:true});assert.ok(result.invalidScheduleReason);assert.deepEqual(await all(),before);
});
emulator('pause removes unreferenced future slots and retains confirmed references',async({db,id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  await db.doc(`bookings/${id}`).set({serviceId:id,state:'CONFIRMED',schedule:selection(c,id)});
  await ref.update({isPaused:true});const result=await ensure({reconcileChangedSchedule:true});
  assert.equal(result.createdCount,0);assert.equal(result.deletedUnbookedCount,63);assert.equal(result.protectedCount,1);
});
emulator('request transaction refuses a selected slot removed by a schedule edit',async({db,id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  await ref.update({startMinutes:570,endMinutes:750});await ensure({reconcileChangedSchedule:true});
  await assert.rejects(db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,source,selection(c,id))),/Service availability changed/);
});
emulator('a later customer cannot request a slot after payment confirmed its sole capacity',async({db,id,ref,ensure})=>{
  await ref.update({capacity:1});
  await ensure();
  const one={...source,capacity:1};
  const c=buildServiceSlotCandidates(id,one,now).candidates[0];
  const slot=ref.collection('slots').doc(c.id);
  const occupancy=ref.collection('slotOccupancy').doc(c.id);
  // Confirmation currently commits this occupancy claim without changing the
  // customer-visible slot document. A second customer arrives afterwards.
  await occupancy.set({slotId:c.id,confirmedUnits:1,capacitySnapshot:1,bookingClaims:{customerA:1}});
  assert.equal((await slot.get()).data().acceptedCount,0);
  const competing=db.collection('bookings').doc('customer-b-request');
  await assert.rejects(db.runTransaction(async tx=>{
    await lockServiceSlotSelection(db,tx,id,one,selection(c,id));
    tx.create(competing,{serviceId:id,state:'PENDING_PROVIDER'});
  }),
    /time slot was just booked/i);
  assert.equal((await competing.get()).exists,false);
  await assert.rejects(assertPreCheckoutSlotCapacity(db,{bookingType:'SLOT',state:'ACCEPTED_AWAITING_PAYMENT',
    serviceId:id,service:{capacitySnapshot:1},schedule:selection(c,id)},'customerB'),/time slot was just booked/i);
});
emulator('payment confirmation immediately removes the last slot from a fresh read and rejects a later request',async({db,id,ref})=>{
  const paymentNow=Date.parse('2026-07-22T10:00:00Z');
  const one={...source,ownerUserId:'provider-1',capacity:1,availableDays:['Thu'],
    startMinutes:690,endMinutes:750,sessionDurationMinutes:60};
  await ref.set(one);
  await ensureServiceSlotCoverage(db,id,{nowMs:paymentNow});
  const c=buildServiceSlotCandidates(id,one,paymentNow).candidates.find(c=>c.startAtMs===Date.parse('2026-07-23T06:00:00Z'));
  assert.ok(c);
  const fixture=buildCanonicalPaymentRaceFixture({ids:{bookingId:'customerA',paymentAttemptId:'attempt-customerA',
    razorpayOrderId:'order_customerA',razorpayPaymentId:'pay_customerA'}});
  fixture.booking.serviceId=id;
  fixture.booking.schedule.slots[0].slotId=c.id;
  fixture.booking.schedule.slots[0].serviceId=id;
  const result=finalizeCapturedBookingPaymentV3({...fixture,bookingId:'customerA',verificationSource:'callable'});
  assert.equal(result.ok,true);
  await persistFinalizePaymentResultV3({firestore:db,result,bookingId:'customerA'});
  const slot=await ref.collection('slots').doc(c.id).get();
  const claim=await ref.collection('slotOccupancy').doc(c.id).get();
  assert.equal(claim.data().confirmedUnits,1);
  assert.equal(slot.data().acceptedCount,1);
  assert.equal(slot.data().acceptedCount<slot.data().capacity,false);
  await assert.rejects(db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,one,selection(c,id))),
    /time slot was just booked/i);
  assert.equal((await db.collection('bookings').doc('customerB').get()).exists,false);
});
emulator('confirmed continuous and consecutive-day slots block only their occupied windows',async({db,id,ref})=>{
  const one={...source,capacity:1,sessionDurationMinutes:60,startMinutes:540,endMinutes:780};
  await ref.set(one);
  await ensureServiceSlotCoverage(db,id,{nowMs:now});
  const candidates=buildServiceSlotCandidates(id,one,now).candidates;
  const day=candidates.filter(c=>c.dateKey===candidates[0].dateKey);
  assert.equal(day.length,4);
  const selected=[day[1],day[2],candidates.find(c=>c.dateKey!==day[0].dateKey&&c.startMinutes===600)];
  for(const c of selected){
    await ref.collection('slotOccupancy').doc(c.id).set({slotId:c.id,confirmedUnits:1,capacitySnapshot:1,bookingClaims:{customerA:1}});
    await ref.collection('slots').doc(c.id).update({acceptedCount:1});
  }
  const snapshots=await Promise.all(day.map(c=>ref.collection('slots').doc(c.id).get()));
  const visible=day.filter((_,i)=>snapshots[i].data().isBookable===true&&
    snapshots[i].data().acceptedCount<snapshots[i].data().capacity);
  assert.deepEqual(visible.map(c=>c.startMinutes),[540,720]);
  for(const c of selected){
    await assert.rejects(db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,one,selection(c,id))),
      /time slot was just booked/i);
  }
  const packageSelection={...selection(day[0],id),slots:[day[0],selected[2]].map(c=>({
    slotId:c.id,startAt:new Date(c.startAtMs),endAt:new Date(c.endAtMs),
  }))};
  await assert.rejects(db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,one,packageSelection)),
    /time slot was just booked/i);
  for(const c of visible){
    await db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,one,selection(c,id)));
  }
  const nextDayFree=candidates.find(c=>c.dateKey!==day[0].dateKey&&c.startMinutes===540);
  await db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,one,selection(nextDayFree,id)));
  const otherServiceId=`${id}-other`;
  const otherRef=db.doc(`services/${otherServiceId}`);
  await otherRef.set({...one,ownerUserId:'another-provider'});
  await ensureServiceSlotCoverage(db,otherServiceId,{nowMs:now});
  const other=buildServiceSlotCandidates(otherServiceId,{...one,ownerUserId:'another-provider'},now).candidates[1];
  await db.runTransaction(tx=>lockServiceSlotSelection(db,tx,otherServiceId,{...one,ownerUserId:'another-provider'},selection(other,otherServiceId)));
});
emulator('booking occupancy updates and replenishment do not lose capacity claims',async({db,id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  const occ=ref.collection('slotOccupancy').doc(c.id);await occ.set({confirmedUnits:1,capacitySnapshot:2,bookingClaims:{first:1}});
  await Promise.all([ensure(),db.runTransaction(async tx=>{const d=(await tx.get(occ)).data();tx.update(occ,{confirmedUnits:d.confirmedUnits+1,bookingClaims:{...d.bookingClaims,second:1}});})]);
  assert.deepEqual((await occ.get()).data(),{confirmedUnits:2,capacitySnapshot:2,bookingClaims:{first:1,second:1}});
});
emulator('unknown booking schemas fail closed without mutation',async({db,id,ensure,all})=>{
  await db.doc(`bookings/${id}`).set({serviceId:id,state:'CONFIRMED',slotId:'legacy'});
  await assert.rejects(ensure(),/unrecognized_booking_schedule/);assert.equal((await all()).length,0);
});
emulator('preserved booked slots cannot accept new requests under an incompatible edited schedule',async({db,id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  await db.doc(`bookings/${id}`).set({serviceId:id,state:'CONFIRMED',schedule:selection(c,id)});
  await ref.update({capacity:3});await ensure({reconcileChangedSchedule:true});
  assert.equal((await ref.collection('slots').doc(c.id).get()).data().capacity,2);
  await assert.rejects(db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,{...source,capacity:3},selection(c,id))),/Service availability changed/);
});
emulator('new request and schedule reconciliation serialize without orphaning a committed request',async({db,id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];const booking=db.doc(`bookings/${id}`);
  const results=await Promise.allSettled([
    db.runTransaction(async tx=>{await lockServiceSlotSelection(db,tx,id,source,selection(c,id));tx.create(booking,{serviceId:id,state:'PENDING_PROVIDER',schedule:selection(c,id)});}),
    (async()=>{await ref.update({startMinutes:570,endMinutes:750});await ensure({reconcileChangedSchedule:true});})(),
  ]);
  assert.equal(results[1].status,'fulfilled');
  if((await booking.get()).exists)assert.equal((await ref.collection('slots').doc(c.id).get()).exists,true);
  else assert.equal(results[0].status,'rejected');
});
emulator('booking protection query never treats a truncated history as unbooked',async({db,id,ensure,all})=>{
  for(let offset=0;offset<501;offset+=400){const batch=db.batch();for(let i=offset;i<Math.min(offset+400,501);i++)batch.set(db.doc(`bookings/${id}_${i}`),{serviceId:id});await batch.commit();}
  await assert.rejects(ensure(),/booking_protection_limit_exceeded/);assert.equal((await all()).length,0);
});

test('emulator: scheduler paginates, checkpoints, respects lease and finishes the next pass',{skip:!enabled},async()=>{
  const {runServiceSlotCoveragePass}=require('../lib/services/serviceSlotCoverageScheduler');
  const app=initializeApp({projectId:`demo-slot-scheduler-${randomUUID().slice(0,8)}`},`scheduler-${randomUUID()}`);
  const db=getFirestore(app);
  try {
    const batch=db.batch();
    for(let i=0;i<111;i++)batch.set(db.doc(`services/service-${String(i).padStart(3,'0')}`),{...source,availableDays:[]});
    batch.set(db.doc('services/service-112'),{...source,isPaused:true});
    batch.set(db.doc('services/service-113'),{...source,isActive:false});
    await batch.commit();
    await runServiceSlotCoveragePass(db);
    const state=db.doc('_maintenance/serviceSlotCoverage');let data=(await state.get()).data();
    assert.equal(data.lastSummary.servicesScanned,100);assert.equal(data.cursor,'service-099');
    await state.update({leaseUntil:Timestamp.fromMillis(Date.now()+60000)});
    await runServiceSlotCoveragePass(db);assert.equal((await state.get()).data().cursor,'service-099');
    await state.update({leaseUntil:Timestamp.fromMillis(0)});
    await runServiceSlotCoveragePass(db);data=(await state.get()).data();
    assert.equal(data.lastSummary.servicesScanned,12);assert.equal(data.lastSummary.eligibleServices,11);
    assert.equal(data.lastSummary.cycleComplete,true);assert.equal(data.cursor,null);
  } finally {await db.terminate();await deleteApp(app);}
});
emulator('orphan range occupancy preserves existing slots and prevents overlapping new coverage',async({id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];
  const occ=ref.collection('occupancy').doc(c.dateKey);await occ.set({confirmedUnits:1,capacitySnapshot:2,bookingClaims:{orphanRange:1}});
  const slot=ref.collection('slots').doc(c.id);const before=await slot.get();const beforeOcc=await occ.get();
  await ref.update({startMinutes:570,endMinutes:750});await ensure({reconcileChangedSchedule:true});
  assert.deepEqual((await slot.get()).data(),before.data());assert.ok((await slot.get()).updateTime.isEqual(before.updateTime));
  assert.deepEqual((await occ.get()).data(),beforeOcc.data());assert.ok((await occ.get()).updateTime.isEqual(beforeOcc.updateTime));
  assert.equal((await ref.collection('slots').doc(`${c.dateKey}_0570`).get()).exists,false);
});
emulator('non-generation slot status is protected during schedule changes',async({id,ref,ensure})=>{
  await ensure();const c=buildServiceSlotCandidates(id,source,now).candidates[0];const slot=ref.collection('slots').doc(c.id);
  await slot.update({status:'booked',acceptedCount:0});const before=await slot.get();
  await ref.update({startMinutes:570,endMinutes:750});await ensure({reconcileChangedSchedule:true});
  assert.deepEqual((await slot.get()).data(),before.data());assert.ok((await slot.get()).updateTime.isEqual(before.updateTime));
});
emulator('valid legacy day-care slot IDs remain requestable without renaming existing slots',async({db,id,ref})=>{
  const legacy={...source,sessionDurationMinutes:0};await ref.set(legacy);
  const c=buildServiceSlotCandidates(id,legacy,now).candidates[0];c.id='2026-09-14_0540';
  await ref.collection('slots').doc(c.id).set(slotPayload(c));
  await db.runTransaction(tx=>lockServiceSlotSelection(db,tx,id,legacy,selection(c,id)));
});
