const test = require('node:test');
const assert = require('node:assert/strict');
const {Timestamp} = require('firebase-admin/firestore');
const {reconcileProviderEarningsBatchDataV3: reconcile, reconstructProviderEarningsV3: reconstruct} =
  require('../lib/booking/application/providerEarningsBackfillV3');
const {buildProviderEarningsProjectionV3} = require('../lib/booking/application/providerEarningsV3');

class DB {
  constructor(seed = {}) { this.store = new Map(Object.entries({'users/admin': {adminRole: 'superAdmin'}, ...seed})); }
  collection(name) { return new Query(this, name); }
  async runTransaction(fn) {
    const writes = [];
    const result = await fn({get: async ref => { assert.equal(writes.length, 0); return ref.get(); },
      set: (ref, value, options) => writes.push([ref.path, value, options])});
    if (this.failId && writes.some(([path]) => path === `providerEarnings/${this.failId}`)) throw Error('injected failure');
    for (const [path, value, options] of writes) this.store.set(path, options?.merge ? {...this.store.get(path), ...value} : value);
    return result;
  }
}
class Query {
  constructor(db, name) { this.db = db; this.name = name; this.maximum = Infinity; }
  doc(id) { const path = `${this.name}/${id}`; return {path, id, get: async () => ({id, exists: this.db.store.has(path), data: () => this.db.store.get(path)})}; }
  orderBy() { return this; }
  limit(value) { this.maximum = value; return this; }
  startAfter(value) { this.after = value; return this; }
  where(field, op, value) { assert.equal(op, '=='); this.filter = [field,value]; return this; }
  async get() {
    const entries = [...this.db.store].filter(([path, d]) => path.startsWith(`${this.name}/`) && path.split('/').length === 2 &&
      (!this.after || path.split('/')[1] > this.after) && (!this.filter || d[this.filter[0]] === this.filter[1]))
      .sort(([a],[b]) => a < b ? -1 : a > b ? 1 : 0).slice(0,this.maximum);
    const docs = entries.map(([path,d]) => ({id:path.split('/')[1], data:()=>d}));
    return {docs, size:docs.length};
  }
}
const at = Timestamp.fromDate(new Date('2026-07-24T12:00:00Z'));
function booking(overrides = {}) { return {schemaVersion:3,bookingModelVersion:'3.2',documentFormat:'canonical_v3',providerId:'provider', parentId:'parent', serviceId:'service', state:'COMPLETED_FINAL',
  financials:{providerPayoutPaise:85000, currency:'INR'}, lifecycle:{paidAt:at, finalizedAt:at, cancelledAt:at},
  payment:{razorpayPaymentId:'winner',status:'CONFIRMED'}, dispute:{status:'none'}, payout:{status:'READY'}, ...overrides}; }
const run = (db, input = {}) => reconcile({firestore:db, auth:{uid:'admin'}, input:{dryRun:false, ids:['b'], ...input}});
const seed = (b = booking(), extra = {}) => new DB({'bookings/b':b, ...extra});

test('missing completed earning is created from canonical data and second run is unchanged', async () => {
  const db=seed(); const first=await run(db); assert.equal(first.counts.created,1);
  const p=db.store.get('providerEarnings/b'); assert.equal(p.amountPaise,85000); assert.equal(p.providerFinalEntitlementPaise,85000);
  const before=[...db.store]; const second=await run(db); assert.equal(second.counts.unchanged,1); assert.deepEqual([...db.store],before);
});
test('correct normalized projection requires no reconciliation-only metadata write', async () => {
  const db=seed(); const preview=await run(db,{dryRun:true});
  db.store.set('providerEarnings/b',preview.items[0].expected);
  assert.equal((await run(db)).counts.unchanged,1);
  assert.equal(db.store.has('providerEarningsReconciliationAudit/b'),false);
});
for (const [actor,amount] of [['CUSTOMER',35000],['PROVIDER',0]]) test(`${actor} cancellation replaces stale expected share`, async()=>{
  const db=seed(booking({state:'CANCELLED'}),{'bookingCancellations/b':{bookingId:'b',actorType:actor,providerCompensationPaise:amount},
    'providerEarnings/b':{amountPaise:85000}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').amountPaise,amount);
  assert.equal(db.store.get('providerEarnings/b').earningsStatus,'FINALIZED');
});
test('cancellation adjustment is an authoritative fallback',async()=>{
  const db=seed(booking({state:'CANCELLED'}),{'bookingFinancialAdjustments/b':{bookingId:'b',actorType:'CUSTOMER',providerCompensationPaise:35000}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').amountPaise,35000);
});
test('conflicting cancellation allocations are not guessed',async()=>{
  const db=seed(booking({state:'CANCELLED'}),{'bookingCancellations/b':{actorType:'CUSTOMER',providerCompensationPaise:35000},
    'bookingFinancialAdjustments/b':{actorType:'CUSTOMER',providerCompensationPaise:45000}});
  assert.equal((await run(db)).counts.skipped,1); assert.equal(db.store.has('providerEarnings/b'),false);
});
test('no-show amount comes from recorded compensation, not original share',async()=>{
  const db=seed(booking({state:'NO_SHOW'}),{'bookingNoShows/b':{bookingId:'b',providerCompensationPaise:50000,noShowAt:at}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').amountPaise,50000);
});
test('resolved dispute restores final allocation independently of PAID payout balance',async()=>{
  const db=seed(booking({dispute:{status:'RESOLVED'}}),{'bookingDisputeResolutions/r':{bookingId:'b',providerFinalEntitlementPaise:50000,resolvedAt:at},
    'providerPayouts/b':{status:'PAID',remainingPayablePaise:0,providerEntitlementPaise:50000,paidAt:at}});
  await run(db); const p=db.store.get('providerEarnings/b'); assert.equal(p.amountPaise,50000); assert.equal(p.status,'PAID');
  assert.equal(p.earningsStatus,'ADJUSTED');
});
test('embedded dispute final allocation is supported without a separate resolution document',async()=>{
  const db=seed(booking({dispute:{status:'RESOLVED',resolvedAt:at}}),{'disputes/b':{bookingId:'b',status:'RESOLVED',resolution:{providerFinalEntitlementPaise:0}}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').amountPaise,0);
});
for (const state of ['CONFIRMED','IN_PROGRESS','COMPLETED_PENDING_REVIEW']) test(`${state} is provisional`,async()=>{
  const db=seed(booking({state}),{'providerEarnings/b':{amountPaise:85000}}); await run(db);
  const p=db.store.get('providerEarnings/b'); assert.equal(p.amountPaise,0); assert.equal(p.providerFinalEntitlementPaise,null);
  assert.equal(p.providerProvisionalEntitlementPaise,85000);
});
test('open dispute is held and unfinalized',async()=>{
  const db=seed(booking({state:'COMPLETED_PENDING_REVIEW',dispute:{status:'OPEN'}})); await run(db);
  assert.equal(db.store.get('providerEarnings/b').earningsStatus,'HELD'); assert.equal(db.store.get('providerEarnings/b').amountPaise,0);
});
test('duplicate refund does not affect normal final earnings',async()=>{
  const db=seed(booking(),{'refunds/b':{razorpayPaymentId:'duplicate',state:'processed'}}); await run(db);
  assert.equal(db.store.get('providerEarnings/b').amountPaise,85000);
});
test('canonical refund with cancellation allocation retains compensation',async()=>{
  const db=seed(booking({state:'CANCELLED',payment:{status:'refunded',razorpayPaymentId:'winner'}}),{
    'refunds/b':{razorpayPaymentId:'winner',state:'processed'},'bookingCancellations/b':{actorType:'CUSTOMER',providerCompensationPaise:35000}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').amountPaise,35000);
});
test('unallocated final canonical refund is flagged without using old earning as truth',async()=>{
  const db=seed(booking(),{'refunds/b':{razorpayPaymentId:'winner',state:'processed'},'providerEarnings/b':{amountPaise:85000}});
  const before=[...db.store]; const r=await run(db); assert.equal(r.counts.skipped,1); assert.deepEqual([...db.store],before);
});
test('canonical refund before finalization reconstructs a held provisional amount',async()=>{
  const db=seed(booking({state:'COMPLETED_PENDING_REVIEW'}),{'refunds/b':{razorpayPaymentId:'winner',state:'submitted'}});
  await run(db); assert.equal(db.store.get('providerEarnings/b').earningsStatus,'HELD'); assert.equal(db.store.get('providerEarnings/b').amountPaise,0);
});
test('legacy rupees are preserved but never used as earnings truth',async()=>{
  const db=seed(booking(),{'providerEarnings/b':{amount:999999,status:'payoutEligible',bankReference:'retain'}}); await run(db);
  const p=db.store.get('providerEarnings/b'); assert.equal(p.amountPaise,85000); assert.equal(p.amount,999999);
  assert.equal(p.legacyAmountDeprecated,true); assert.equal(p.bankReference,'retain'); assert.equal(p.status,'READY');
});
test('wrong provider identity is reported and never reassigned',async()=>{
  const db=seed(booking(),{'providerEarnings/b':{providerId:'wrong',amountPaise:1}});
  const before=[...db.store]; const r=await run(db);
  assert.equal(r.items[0].errorCategory,'PROVIDER_MISMATCH');
  assert.equal(r.summary.providerMismatch,1); assert.deepEqual([...db.store],before);
});
test('missing booking leaves orphan projection untouched',async()=>{
  const db=new DB({'providerEarnings/orphan':{amountPaise:50000}}); const before=[...db.store];
  const r=await run(db,{scan:'providerEarnings',ids:['orphan']}); assert.equal(r.counts.skipped,1); assert.deepEqual([...db.store],before);
});
test('alternate-key duplicate is reported and missing canonical projection is not created',async()=>{
  const db=seed(booking(),{'providerEarnings/duplicate':{bookingId:'b',amountPaise:85000}});
  assert.equal((await run(db)).items[0].errorCategory,'DUPLICATE_PROJECTION'); assert.equal(db.store.has('providerEarnings/b'),false);
  assert.equal((await run(db,{scan:'providerEarnings',ids:['duplicate']})).counts.skipped,1);
});
for(const state of ['REQUESTED','DECLINED','PAYMENT_EXPIRED','ACCEPTED_AWAITING_PAYMENT','EXPIRED','REQUEST_EXPIRED','CANCELLED']) test(`${state} does not materialize fake earnings`,async()=>{
  const db=seed(booking({state,lifecycle:{}})); assert.equal((await run(db)).counts.skipped,1); assert.equal(db.store.has('providerEarnings/b'),false);
  db.store.set('providerEarnings/b',{amountPaise:85000}); assert.equal((await run(db)).counts.skipped,1);
  assert.equal(db.store.get('providerEarnings/b').amountPaise,85000);
});
test('dry run is default and writes neither projections nor audits',async()=>{
  const db=seed(); const before=[...db.store]; const result=await reconcile({firestore:db,auth:{uid:'admin'},input:{ids:['b']}});
  assert.equal(result.dryRun,true); assert.equal(result.counts.created,1); assert.deepEqual([...db.store],before);
});
test('pagination and retry IDs support restart after a per-record commit failure',async()=>{
  const db=new DB({'bookings/a':booking(),'bookings/b':booking(),'bookings/c':booking()}); db.failId='b';
  const first=await reconcile({firestore:db,auth:{uid:'admin'},input:{dryRun:false,limit:2}});
  assert.equal(first.nextCursor,'b'); assert.equal(first.counts.created,1); assert.deepEqual(first.retryIds,['b']);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('providerEarningsReconciliationAudit/')).length,1);
  db.failId=null; await run(db,{ids:first.retryIds});
  const last=await reconcile({firestore:db,auth:{uid:'admin'},input:{dryRun:false,limit:2,cursor:first.nextCursor}});
  assert.equal(last.nextCursor,null); assert.equal(last.counts.created,1);
  const rerun=await run(db,{ids:['a','b','c']}); assert.equal(rerun.counts.unchanged,3);
});
for(const role of [null,'financeAdmin','customerSupportAdmin','petParent','provider','customer']) test(`unauthorized role ${role} cannot dry-run or apply`,async()=>{
  const db=seed(); db.store.set('users/admin',{adminRole:role});
  for(const dryRun of [true,false]) await assert.rejects(run(db,{dryRun}),e=>e.code==='permission-denied');
});
test('unauthenticated invocation is rejected',async()=>{
  await assert.rejects(reconcile({firestore:seed(),auth:undefined,input:{}}),e=>e.code==='unauthenticated');
});
for(const input of [{limit:21},{limit:0},{cursor:'bad/path'},{dryRun:'false'},{ids:[]},{scan:'users'}]) test(`invalid options ${JSON.stringify(input)}`,async()=>{
  await assert.rejects(reconcile({firestore:seed(),auth:{uid:'admin'},input}),e=>e.code==='invalid-argument');
});
test('unsafe and missing canonical data are not inferred from old amounts',()=>{
  for(const b of [booking({providerId:''}), booking({financials:{}}), booking({financials:{providerPayoutPaise:-1}}),booking({lifecycle:{}})]) {
    assert.throws(()=>reconstruct({bookingId:'b',booking:b}));
  }
});
test('reconstruction uses the same live final entitlement projection',()=>{
  assert.deepEqual(reconstruct({bookingId:'b',booking:booking()}).projection,
    buildProviderEarningsProjectionV3({entitlementPaise:85000,phase:'FINALIZED',outcome:'NORMAL_COMPLETION'}));
});
for(const state of ['PENDING_PROVIDER','CANCELLED_BY_PARENT']) test(`${state} requires no projection`,async()=>{
  const db=seed(booking({state,lifecycle:{}})); assert.equal((await run(db)).counts.skipped,1); assert.equal(db.store.has('providerEarnings/b'),false);
});
test('missing outcome timestamp requires review without invented time',async()=>{
  const db=seed(booking({state:'NO_SHOW'}),{'bookingNoShows/b':{providerCompensationPaise:85000}});
  const before=[...db.store]; const r=await run(db);
  assert.equal(r.items[0].errorCategory,'MISSING_OUTCOME_TIMESTAMP'); assert.deepEqual([...db.store],before);
});
test('projection scan uses cursor continuation to cover orphan and canonical keys',async()=>{
  const db=seed(booking(),{'providerEarnings/a':{bookingId:'missing'},'providerEarnings/b':{amountPaise:1}});
  const first=await reconcile({firestore:db,auth:{uid:'admin'},input:{scan:'providerEarnings',limit:1,dryRun:true}});
  assert.equal(first.counts.skipped,1); assert.equal(first.nextCursor,'a');
  const last=await reconcile({firestore:db,auth:{uid:'admin'},input:{scan:'providerEarnings',limit:1,cursor:'a',dryRun:true}});
  assert.equal(last.counts.updated,1); assert.equal(last.nextCursor,null);
});
test('conflicting terminal records and multiple dispute resolutions block repair',async()=>{
  const db=seed(booking(),{'bookingCancellations/b':{actorType:'CUSTOMER',providerCompensationPaise:35000}});
  assert.equal((await run(db)).counts.skipped,1);
  db.store.delete('bookingCancellations/b');
  db.store.set('bookingDisputeResolutions/r1',{bookingId:'b',providerFinalEntitlementPaise:1});
  db.store.set('bookingDisputeResolutions/r2',{bookingId:'b',providerFinalEntitlementPaise:2});
  assert.equal((await run(db)).items[0].errorCategory,'MULTIPLE_DISPUTE_RESOLUTIONS');
});
test('status normalization preserves old payout evidence without driving earned amount',async()=>{
  const db=seed(booking({payout:{status:'HELD'}}),{'providerEarnings/b':{amountPaise:1,status:'paid',paidAt:at,transactionReference:'historical-reference'}});
  await run(db); const p=db.store.get('providerEarnings/b');
  assert.equal(p.amountPaise,85000); assert.equal(p.status,'HELD'); assert.equal(p.legacyPayoutStatus,'paid');
  assert.equal(p.paidAt,at); assert.equal(p.transactionReference,'historical-reference');
  assert.equal((await run(db)).counts.unchanged,1);
});

for (const fields of [['earningsSchemaVersion'], ['earningsStatus'], ['providerFinalEntitlementPaise'],
  ['earningsSchemaVersion','earningsStatus','providerFinalEntitlementPaise']]) {
  test(`global scan reconstructs missing ${fields.join(',')}`, async()=>{
    const db=seed(); const expected=(await run(db,{dryRun:true})).items[0].expected;
    const legacy={...expected}; for(const field of fields) delete legacy[field];
    db.store.set('providerEarnings/b',legacy);
    const before=[...db.store]; const preview=await run(db,{dryRun:true,scan:'providerEarnings'});
    assert.equal(preview.summary.wouldUpdate,1); assert.deepEqual([...db.store],before);
    assert.equal((await run(db,{scan:'providerEarnings'})).summary.applied,1);
    const repaired=db.store.get('providerEarnings/b');
    assert.equal(repaired.providerFinalEntitlementPaise,85000);
    assert.deepEqual(require('../lib/booking/application/providerEarningsSchemaV3').providerEarningsSchemaIssuesV3(repaired),[]);
    const after=[...db.store]; assert.equal((await run(db)).summary.canonicalValid,1);
    assert.deepEqual([...db.store],after);
  });
}
test('known missing-field failure repairs from source, not legacy amount',async()=>{
  const id='A4z2ypododCBhp1GGH8Q', providerId='sSI3muWZg4Ma1z5VNsHaTcFzksF2';
  // Identities/missing fields are reported evidence; source amounts/state are synthetic.
  const db=new DB({[`bookings/${id}`]:booking({providerId,state:'NO_SHOW'}),
    [`bookingNoShows/${id}`]:{bookingId:id,providerId,providerCompensationPaise:43210,noShowAt:at},
    [`providerPayouts/${id}`]:{bookingId:id,providerId,providerEntitlementPaise:777,status:'PAID'},
    [`refunds/${id}`]:{refundAmountPaise:1234},
    [`providerEarnings/${id}`]:{bookingId:id,providerId,amount:1.9,amountPaise:999,createdAt:at}});
  const r=await run(db,{scan:'providerEarnings',ids:[id]});
  assert.equal(r.summary.applied,1); assert.equal(db.store.get(`providerEarnings/${id}`).providerFinalEntitlementPaise,43210);
  assert.equal(db.store.get(`providerEarnings/${id}`).earningsOutcome,'NO_SHOW');
});
test('fully valid projection is never normalized from changed sources',async()=>{
  const db=seed(); await run(db);
  const p=db.store.get('providerEarnings/b'); p.status='COMPLETED'; p.providerFinalEntitlementPaise=123;
  const before=[...db.store]; const r=await run(db);
  assert.equal(r.items[0].classification,'CANONICAL_VALID'); assert.deepEqual([...db.store],before);
});
test('canonical provisional is unchanged',async()=>{
  const db=seed(booking({state:'CONFIRMED'})); await run(db);
  const before=[...db.store]; assert.equal((await run(db)).summary.canonicalValid,1); assert.deepEqual([...db.store],before);
});
test('future schema is never downgraded',async()=>{
  const db=seed(booking(),{'providerEarnings/b':{earningsSchemaVersion:2}});
  const before=[...db.store]; assert.equal((await run(db)).items[0].errorCategory,'UNKNOWN_SCHEMA'); assert.deepEqual([...db.store],before);
});
test('global projection pages visit each document once and resume',async()=>{
  const db=new DB(Object.fromEntries(['a','b','c','d','e'].flatMap(id=>[
    [`bookings/${id}`,booking()], [`providerEarnings/${id}`,{bookingId:id,providerId:'provider'}]])));
  let cursor, seen=[];
  do { const page=await reconcile({firestore:db,auth:{uid:'admin'},input:{scan:'providerEarnings',limit:2,cursor}});
    seen.push(...page.items.map(i=>i.id)); assert.ok(page.items.length<=2);
    assert.equal(page.hasMore,page.nextCursor!==null); cursor=page.nextCursor;
  } while(cursor);
  assert.deepEqual(seen,['a','b','c','d','e']); assert.equal(new Set(seen).size,5);
});
test('unknown booking schema is never promoted to canonical earnings',async()=>{
  const db=seed(booking({schemaVersion:2}),{'providerEarnings/b':{amount:500}});
  const before=[...db.store]; assert.equal((await run(db)).items[0].errorCategory,'UNKNOWN_BOOKING_SCHEMA');
  assert.deepEqual([...db.store],before);
});
test('dry-run repair projection matches shared Flutter parser fixture',async()=>{
  const fixture=require('./fixtures/reconciled_provider_earning.json');
  const result=await run(seed(),{dryRun:true});
  for(const [key,value] of Object.entries(fixture)) {
    const actual=result.items[0].expected[key];
    assert.equal(actual instanceof Timestamp ? actual.toDate().toISOString() : actual, value, key);
  }
});
test('missing timestamp does not authorize replacing a newer canonical allocation',async()=>{
  const db=seed(); const expected=(await run(db,{dryRun:true})).items[0].expected;
  delete expected.createdAt;
  expected.providerFinalEntitlementPaise=123;
  db.store.set('providerEarnings/b',expected);
  const before=[...db.store]; const result=await run(db);
  assert.equal(result.items[0].errorCategory,'CANONICAL_FINANCIAL_CONFLICT');
  assert.deepEqual([...db.store],before);
});
