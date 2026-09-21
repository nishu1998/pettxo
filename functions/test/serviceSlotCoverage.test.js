const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {buildServiceSlotCandidates, SERVICE_BOOKING_HORIZON_DAYS, serviceSlotConfigChanged} = require('../lib/services/serviceSlotCandidates');
const {validateSlotBookingSelection} = require('../lib/booking/domain/slotBooking');
const now = Date.parse('2026-09-14T00:00:00+05:30');
const service = {ownerUserId:'provider', status:'active', isActive:true, isVisibleToMarketplace:true,
  isDeleted:false, isPaused:false, availableDays:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
  startMinutes:540, endMinutes:720, sessionDurationMinutes:90, capacity:2};
const plan = (patch={}, time=now) => buildServiceSlotCandidates('service', {...service,...patch}, time);

test('legacy fixed duration and current service produce identical candidates and deterministic IDs', () => {
  assert.deepEqual(plan(), plan({schedulingMode:'fixedDuration'}));
  assert.equal(plan().candidates[0].id, '2026-09-14_0540');
  assert.equal(plan().candidates.length, 64);
});
test('fixed sessions remain contiguous with unchanged duration and payload metadata', () => {
  const [a,b] = plan().candidates;
  assert.equal(a.endAtMs,b.startAtMs);
  assert.equal(a.endAtMs-a.startAtMs,90*60000);
  assert.equal(a.capacity,2); assert.equal(a.timezone,'Asia/Kolkata');
});
test('candidate slots separated by overnight gaps cannot form one booking', () => {
  const slots = plan().candidates.slice(0,4).map(c=>({slotId:c.id, serviceId:c.serviceId,providerId:'provider',
    timezone:c.timezone,dateKey:c.dateKey,serviceDateKey:c.dateKey,startAt:new Date(c.startAtMs),endAt:new Date(c.endAtMs),
    durationMinutes:c.durationMinutes,unitPricePaise:100,schedulingMode:'fixedDuration'}));
  const result=validateSlotBookingSelection({bookingType:'SLOT',slots,slotCount:4,
    scheduledStartAt:slots[0].startAt,scheduledEndAt:slots[3].endAt,totalDurationMinutes:360});
  assert.equal(result.ok,false,JSON.stringify(result));
});
test('day care retains full-window IDs and one slot per enabled date', () => {
  const p=plan({schedulingMode:'dayCare'});
  assert.equal(p.candidates.length,32); assert.equal(p.candidates[0].id,'2026-09-14_0540_0720');
  assert.equal(p.candidates[0].durationMinutes,180);
});
test('overnight retains IDs and next-day boundaries', () => {
  const p=plan({schedulingMode:'overnight',startMinutes:1200,endMinutes:480});
  assert.equal(p.candidates[0].id,'2026-09-14_1200_0480');
  assert.equal(p.candidates[0].endAtMs,Date.parse('2026-09-15T08:00:00+05:30'));
  assert.equal(p.candidates[0].durationMinutes,720);
});
test('24-hour slots retain duration-based ID and 1440-minute duration', () => {
  const p=plan({schedulingMode:'twentyFourHours'});
  assert.equal(p.candidates[0].id,'2026-09-14_0540_1440');
  assert.equal(p.candidates[0].endAtMs-p.candidates[0].startAtMs,86400000);
});
test('available weekdays are respected',()=>assert.ok(plan({availableDays:['Mon']}).candidates.every(c=>new Date(c.startAtMs+330*60000).getUTCDay()===1)));
for(const patch of [{isActive:false},{isPaused:true},{isDeleted:true},{isVisibleToMarketplace:false},{status:'pending'}]) {
  test(`ineligible service produces diagnostic and no slots: ${JSON.stringify(patch)}`,()=>{
    assert.equal(plan(patch).candidates.length,0);assert.ok(plan(patch).eligibilitySkipReason);
  });
}
for(const patch of [{availableDays:[]},{availableDays:['Monday']},{schedulingMode:'fixedDuration',sessionDurationMinutes:0},
  {startMinutes:1440},{startMinutes:720,endMinutes:540},{sessionDurationMinutes:240}]) {
  test(`invalid schedule fails closed: ${JSON.stringify(patch)}`,()=>{
    assert.equal(plan(patch).candidates.length,0);assert.ok(plan(patch).invalidScheduleReason);
  });
}
test('calendar includes today through day 30; reserve covers the following midnight',()=>{
  const p=plan(); assert.equal(SERVICE_BOOKING_HORIZON_DAYS,30);
  assert.equal(p.coverageStartDate,'2026-09-14'); assert.equal(p.coverageEndDate,'2026-10-15');
  assert.ok(p.candidates.some(c=>c.dateKey==='2026-10-14'));
  assert.ok(p.candidates.some(c=>c.dateKey==='2026-10-15'));
  assert.ok(!p.candidates.some(c=>c.dateKey==='2026-10-16'));
  const dart=fs.readFileSync(path.join(__dirname,'../../lib/features/bookings/domain/utils/service_booking_horizon.dart'),'utf8');
  assert.equal(Number(dart.match(/serviceBookingHorizonDays = (\d+)/)[1]),SERVICE_BOOKING_HORIZON_DAYS);
});
test('coverage rolls exactly at IST midnight',()=>{
  assert.equal(plan({},Date.parse('2026-09-13T18:29:59Z')).coverageStartDate,'2026-09-13');
  assert.equal(plan({},Date.parse('2026-09-13T18:30:00Z')).coverageStartDate,'2026-09-14');
});
test('unchanged service re-save does not reconcile slots',()=>{
  assert.equal(serviceSlotConfigChanged(service,{...service,updatedAt:'later',title:'new title'}),false);
  assert.equal(serviceSlotConfigChanged(service,{...service,capacity:3}),true);
});
