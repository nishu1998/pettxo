const assert = require('node:assert/strict');
module.exports = function assertCanonicalEarning(earning, bookingId) {
  assert.equal(earning.earningsSchemaVersion, 1);
  assert.equal(earning.bookingId, bookingId);
  assert.ok(typeof earning.providerId === 'string' && earning.providerId.length > 0);
  assert.ok(['PROVISIONAL','HELD','FINALIZED','ADJUSTED'].includes(earning.earningsStatus));
  const final = earning.providerFinalEntitlementPaise;
  assert.ok(final === null || (Number.isSafeInteger(final) && final >= 0));
  if (['FINALIZED','ADJUSTED'].includes(earning.earningsStatus)) assert.notEqual(final, null);
  assert.ok(Number.isSafeInteger(earning.providerProvisionalEntitlementPaise));
  assert.ok(earning.createdAt, 'history order requires createdAt');
  assert.ok(earning.updatedAt, 'writer requires updatedAt');
};
