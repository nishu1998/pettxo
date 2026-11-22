import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import test, {after, before, beforeEach} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  deleteField,
  collection,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-pettexo';
const firestoreRules = readFileSync('../firestore.rules', 'utf8');

let testEnv;

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

async function seedUser(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', uid), {
      uid,
      username: uid,
      usernameLowercase: uid,
      displayName: uid,
      name: uid,
      role: 'serviceProvider',
      photoUrl: '',
      profileImage: '',
      city: 'Mumbai',
      state: 'Maharashtra',
      createdAt: new Date(),
      updatedAt: new Date(),
      ...data,
    });
  });
}

function verificationDoc(db, uid) {
  return doc(db, 'users', uid, 'providerVerification', 'main');
}

function bookingDoc(db, bookingId) {
  return doc(db, 'bookings', bookingId);
}

function bookingPrivateDoc(db, bookingId) {
  return doc(db, 'bookingPrivate', bookingId);
}

function bookingPrivateParticipantsDoc(db, bookingId) {
  return doc(db, 'bookingPrivateParticipants', bookingId);
}

function bookingChatDoc(db, bookingId) {
  return doc(db, 'bookingChats', bookingId);
}

function bookingCancellationDoc(db, bookingId) {
  return doc(db, 'bookingCancellations', bookingId);
}

function bookingFinancialAdjustmentDoc(db, bookingId) {
  return doc(db, 'bookingFinancialAdjustments', bookingId);
}

function providerPayoutDoc(db, payoutId) {
  return doc(db, 'providerPayouts', payoutId);
}

function bookingFinancialLedgerDoc(db, entryId) {
  return doc(db, 'bookingFinancialLedger', entryId);
}

function bookingDisputeResolutionDoc(db, resolutionId) {
  return doc(db, 'bookingDisputeResolutions', resolutionId);
}

function bookingFinancialReconciliationDoc(db, bookingId) {
  return doc(db, 'bookingFinancialReconciliation', bookingId);
}

function capacityReleaseDoc(db, bookingId) {
  return doc(db, 'capacityReleases', bookingId);
}

function supportTicketDoc(db, ticketId) {
  return doc(db, 'supportTickets', ticketId);
}

function supportTicketMessageDoc(db, ticketId, messageId) {
  return doc(db, 'supportTickets', ticketId, 'messages', messageId);
}

function ownerPayload(uid, overrides = {}) {
  const submissionId = 'submission-current';
  return {
    userId: uid,
    status: 'pending',
    submissionId,
    documentType: 'aadhaar',
    documentFrontPath: `providerVerification/${uid}/identity/${submissionId}/front.png`,
    documentBackPath: '',
    documentFrontUrl: '',
    documentBackUrl: '',
    documentFrontContentType: 'image/png',
    documentBackContentType: null,
    documentFrontFileName: 'front.png',
    documentBackFileName: null,
    verificationMethod: 'manual',
    submittedAt: serverTimestamp(),
    reviewedAt: null,
    documentDeletionScheduledAt: null,
    documentDeletedAt: null,
    reviewedBy: null,
    rejectionReason: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function servicePayload(uid, overrides = {}) {
  return {
    ownerUserId: uid,
    ownerName: 'Provider',
    ownerUsername: uid,
    ownerPhotoUrl: '',
    ownerSnapshot: {name: 'Provider', username: uid, photoUrl: '', city: 'Mumbai', state: 'Maharashtra'},
    title: 'Dog Walking',
    titleLowercase: 'dog walking',
    animalType: 'Dog',
    animalTypeLowercase: 'dog',
    category: 'Walking',
    categoryLowercase: 'walking',
    description: 'Safe neighbourhood walks',
    pricePerSession: 500,
    currency: 'INR',
    schedulingMode: 'fixedDuration',
    sessionDurationMinutes: 60,
    capacity: 2,
    availableDays: ['monday', 'tuesday'],
    startMinutes: 540,
    endMinutes: 1020,
    sameForAllDays: true,
    serviceType: 'atProviderLocation',
    location: {
      approximateLatitude: 19.08,
      approximateLongitude: 72.88,
      geohash: 'te7ud',
      city: 'Mumbai',
      state: 'Maharashtra',
      country: 'IN',
    },
    photoUrls: [],
    primaryPhotoUrl: '',
    status: 'active',
    isActive: true,
    isDeleted: false,
    isPaused: false,
    moderationStatus: 'pending',
    isVisibleToMarketplace: true,
    providerVerificationStatus: 'pending',
    providerVerificationGraceEndsAt: null,
    isPausedByVerification: false,
    pauseReason: '',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    publishedAt: serverTimestamp(),
    ...overrides,
  };
}

function servicePrivatePayload(uid, serviceId, overrides = {}) {
  return {
    serviceId,
    ownerUserId: uid,
    privateNotes: 'Ring the bell',
    location: {displayAddress: 'Exact building, Mumbai', latitude: 19.076, longitude: 72.8777},
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function socialPostPayload(uid, postId, overrides = {}) {
  return {
    id: postId,
    authorId: uid,
    authorType: 'user',
    authorDisplayName: 'Synthetic User',
    authorUsername: uid,
    authorPhotoUrl: '',
    authorCategoryLabel: '',
    authorCity: 'Mumbai',
    authorState: 'Maharashtra',
    imageUrls: ['https://example.test/image.jpg'],
    thumbnailUrls: ['https://example.test/thumb.jpg'],
    imageAspectRatio: 'square',
    caption: 'Synthetic rules test',
    hashtags: ['pets'],
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
    reportCount: 0,
    visibilityStatus: 'visible',
    moderationStatus: 'approved',
    createdAtEpoch: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedPendingProvider(uid) {
  await seedUser(uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(verificationDoc(context.firestore(), uid), {
      userId: uid,
      status: 'pending',
      firstServiceListedAt: null,
      gracePeriodEndsAt: null,
    });
  });
}

async function createServicePair(db, uid, serviceId, publicOverrides = {}, privateOverrides = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'services', serviceId), servicePayload(uid, publicOverrides));
  batch.set(doc(db, 'servicePrivate', serviceId), servicePrivatePayload(uid, serviceId, privateOverrides));
  return batch.commit();
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules: firestoreRules},
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

test('offer campaigns and code indexes are backend-readable but not customer-enumerable', async () => {
  await seedUser('customer', {role: 'petParent'});
  await seedUser('admin', {adminRole: 'superAdmin'});
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'offerCampaigns', 'secret-offer'), {
      isActive: true,
      visibility: 'secret',
      couponCode: 'HIDDEN50',
    });
    await setDoc(doc(db, 'offerCodeIndex', 'hash-1'), {
      campaignId: 'secret-offer',
      state: 'active',
    });
  });

  const customerDb = authedDb('customer');
  await assertFails(getDoc(doc(customerDb, 'offerCampaigns', 'secret-offer')));
  await assertFails(getDocs(collection(customerDb, 'offerCampaigns')));
  await assertFails(getDoc(doc(customerDb, 'offerCodeIndex', 'hash-1')));
  await assertFails(setDoc(doc(customerDb, 'offerCodeIndex', 'hash-2'), {
    campaignId: 'secret-offer',
  }));

  const adminDb = authedDb('admin');
  await assertSucceeds(getDoc(doc(adminDb, 'offerCampaigns', 'secret-offer')));
  await assertSucceeds(getDoc(doc(adminDb, 'offerCodeIndex', 'hash-1')));
  await assertFails(updateDoc(doc(adminDb, 'offerCodeIndex', 'hash-1'), {
    state: 'retired',
  }));
});

// Exercise real client writes, including added/removed keys and the alternate
// profile-bootstrap allow branch. Trusted fixtures never use client rules.
const adminRoles = ['superAdmin', 'financeAdmin', 'customerSupportAdmin'];
const protectedUserFields = {
  adminRole: 'superAdmin',
  canModerateReports: true,
  isAdmin: true,
  permissions: {manageFinance: true},
  claims: {admin: true},
  accountStatus: 'active',
  restrictions: {hard: {isBanned: false}},
  verificationStatus: 'approved',
  emailVerified: true,
  phoneVerified: true,
  providers: ['password'],
  accountType: 'admin',
  unexpectedPrivilege: true,
};

function publicProfile(uid, overrides = {}) {
  return {
    uid, role: 'petParent', displayName: 'Test Person', name: 'Test Person',
    username: uid, usernameLowercase: uid, photoUrl: '', profileImage: '',
    state: 'Maharashtra', city: 'Mumbai', bio: '',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides,
  };
}

function createProfile(db, uid, overrides = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'users', uid), publicProfile(uid, overrides));
  batch.set(doc(db, 'usernames', uid), {
    uid, username: uid, usernameLowercase: uid,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

async function seedFinancialAccessFixtures() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'providerEarnings', 'other-earning'), {
      providerId: 'other-provider', amountPaise: 85000,
    });
    await setDoc(doc(db, 'bookingFinancialLedger', 'protected-entry'), {amountPaise: 85000});
    await setDoc(doc(db, 'manualSettlementObligations', 'protected-obligation'), {status: 'READY'});
    await setDoc(doc(db, 'reports', 'admin-action'), {
      reporterId: 'other-provider', reportedBy: 'other-provider', status: 'pending',
    });
  });
}

for (const role of ['petParent', 'serviceProvider', 'petLover']) {
  test(`authorization: legitimate create and profile role selection ${role}`, async () => {
    const uid = 'profile_owner';
    const db = authedDb(uid);
    await assertSucceeds(createProfile(db, uid, {role}));
    await assertSucceeds(getDoc(doc(db, 'users', uid)));
    await assertSucceeds(updateDoc(doc(db, 'users', uid), {
      role: role === 'serviceProvider' ? 'petParent' : 'serviceProvider',
      updatedAt: serverTimestamp(),
    }));
  });
}

for (const role of adminRoles) {
  test(`authorization: create rejects adminRole ${role}`, async () => {
    await assertFails(createProfile(authedDb('new_owner'), 'new_owner', {adminRole: role}));
  });
  test(`authorization: escalation to ${role} cannot unlock financial reads or admin actions`, async () => {
    const uid = 'ordinary_owner';
    await seedUser(uid);
    await seedFinancialAccessFixtures();
    const db = authedDb(uid);
    await assertFails(updateDoc(doc(db, 'users', uid), {
      displayName: 'Changed', name: 'Changed', adminRole: role,
      updatedAt: serverTimestamp(),
    }));
    assert.equal((await getDoc(doc(db, 'users', uid))).data().displayName, uid);
    await assertFails(getDoc(doc(db, 'providerEarnings', 'other-earning')));
    await assertFails(getDoc(doc(db, 'bookingFinancialLedger', 'protected-entry')));
    await assertFails(getDoc(doc(db, 'manualSettlementObligations', 'protected-obligation')));
    await assertFails(updateDoc(doc(db, 'reports', 'admin-action'), {status: 'resolved'}));
    await assertFails(updateDoc(doc(db, 'manualSettlementObligations', 'protected-obligation'), {status: 'COMPLETED'}));
  });
  test(`authorization: trusted ${role} retains access but cannot self-edit admin metadata`, async () => {
    const uid = 'trusted_admin';
    await seedUser(uid, {adminRole: role});
    await seedFinancialAccessFixtures();
    const db = authedDb(uid);
    await assertSucceeds(getDoc(doc(db, 'providerEarnings', 'other-earning')));
    await assertSucceeds(getDoc(doc(db, 'bookingFinancialLedger', 'protected-entry')));
    await assertSucceeds(getDoc(doc(db, 'manualSettlementObligations', 'protected-obligation')));
    await assertSucceeds(updateDoc(doc(db, 'reports', 'admin-action'), {status: 'resolved'}));
    await assertSucceeds(updateDoc(doc(db, 'users', uid), {bio: 'Updated', updatedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(db, 'users', uid), {adminRole: role === 'superAdmin' ? 'financeAdmin' : 'superAdmin', updatedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(db, 'users', uid), {adminRole: deleteField(), updatedAt: serverTimestamp()}));
    await assertFails(setDoc(doc(db, 'users', uid), publicProfile(uid)));
    await assertFails(updateDoc(doc(db, 'bookingFinancialLedger', 'protected-entry'), {amountPaise: 1}));
  });
}

for (const [field, value] of Object.entries(protectedUserFields)) {
  test(`authorization: create rejects protected/unknown field ${field}`, async () => {
    await assertFails(createProfile(authedDb('new_owner'), 'new_owner', {[field]: value}));
  });
  test(`authorization: update rejects adding, changing, and removing ${field}`, async () => {
    const uid = 'ordinary_owner';
    const db = authedDb(uid);
    await seedUser(uid);
    await assertFails(updateDoc(doc(db, 'users', uid), {[field]: value, updatedAt: serverTimestamp()}));
    await seedUser(uid, {[field]: value});
    await assertFails(updateDoc(doc(db, 'users', uid), {[field]: null, updatedAt: serverTimestamp()}));
    await assertFails(updateDoc(doc(db, 'users', uid), {[field]: deleteField(), updatedAt: serverTimestamp()}));
  });
}

test('authorization: bootstrap preserves trusted fields and rejects privilege additions/removals', async () => {
  const uid = 'bootstrap_owner';
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', uid), {uid, accountStatus: 'active'});
    await setDoc(doc(db, 'usernames', uid), {uid, username: uid, usernameLowercase: uid});
  });
  const db = authedDb(uid);
  const {uid: ignoredUid, ...payload} = publicProfile(uid);
  await assertFails(updateDoc(doc(db, 'users', uid), {...payload, adminRole: 'superAdmin'}));
  await assertFails(updateDoc(doc(db, 'users', uid), {...payload, canModerateReports: true}));
  await assertFails(updateDoc(doc(db, 'users', uid), {...payload, accountStatus: deleteField()}));
  await assertSucceeds(updateDoc(doc(db, 'users', uid), payload));
  assert.equal((await getDoc(doc(db, 'users', uid))).data().accountStatus, 'active');
});

test('authorization: Edit Profile can add optional fields and delete legacy location fields', async () => {
  const uid = 'edit_owner';
  await seedUser(uid, {address: 'Old address', country: 'India', accountStatus: 'active', canModerateReports: false});
  const db = authedDb(uid);
  await assertSucceeds(setDoc(doc(db, 'users', uid), {
    displayName: 'New Name', name: 'New Name', bio: 'Provider bio',
    photoUrl: 'https://example.com/avatar.png', profileImage: 'https://example.com/avatar.png',
    state: 'Maharashtra', city: 'Pune', location: 'Pune, Maharashtra',
    address: deleteField(), country: deleteField(), profileType: 'serviceProvider',
    updatedAt: serverTimestamp(),
  }, {merge: true}));
  const data = (await getDoc(doc(db, 'users', uid))).data();
  assert.equal(data.location, 'Pune, Maharashtra');
  assert.equal(data.canModerateReports, false);
  assert.equal(data.address, undefined);
});

test('authorization: cross-user and unauthenticated profile writes are denied', async () => {
  await seedUser('victim_owner');
  await assertFails(updateDoc(doc(authedDb('attacker'), 'users', 'victim_owner'), {adminRole: 'superAdmin'}));
  await assertFails(createProfile(authedDb('attacker'), 'new_victim'));
  await assertFails(createProfile(testEnv.unauthenticatedContext().firestore(), 'new_owner'));
  await assertFails(updateDoc(doc(testEnv.unauthenticatedContext().firestore(), 'users', 'victim_owner'), {bio: 'Changed'}));
});

for (const role of [undefined, null, '', 'admin', 'SUPERADMIN', 'superAdmin ', true, ['superAdmin'], {role: 'superAdmin'}]) {
  test(`authorization: malformed/missing admin role ${JSON.stringify(role)} grants no financial access`, async () => {
    const uid = 'invalid_admin';
    await seedUser(uid, role === undefined ? {} : {adminRole: role});
    await seedFinancialAccessFixtures();
    const db = authedDb(uid);
    await assertFails(getDoc(doc(db, 'providerEarnings', 'other-earning')));
    await assertFails(getDoc(doc(db, 'bookingFinancialLedger', 'protected-entry')));
    await assertFails(updateDoc(doc(db, 'reports', 'admin-action'), {status: 'resolved'}));
  });
}

test('authorization: profile role cannot substitute for adminRole', async () => {
  await assertFails(createProfile(authedDb('new_owner'), 'new_owner', {role: 'superAdmin'}));
  await seedUser('ordinary_owner');
  await assertFails(updateDoc(doc(authedDb('ordinary_owner'), 'users', 'ordinary_owner'), {role: 'financeAdmin', updatedAt: serverTimestamp()}));
  await seedUser('ordinary_owner', {role: 'superAdmin'});
  await seedFinancialAccessFixtures();
  await assertFails(getDoc(doc(authedDb('ordinary_owner'), 'bookingFinancialLedger', 'protected-entry')));
});

test('authorization: provider own earnings remain readable and immutable', async () => {
  await seedUser('other-provider');
  await seedFinancialAccessFixtures();
  const db = authedDb('other-provider');
  await assertSucceeds(getDoc(doc(db, 'providerEarnings', 'other-earning')));
  await assertFails(updateDoc(doc(db, 'providerEarnings', 'other-earning'), {amountPaise: 1, status: 'PAID'}));
});

test('authorization: bootstrap rejects privileged profile role values', async () => {
  const uid = 'bootstrap_owner';
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {uid});
    await setDoc(doc(context.firestore(), 'usernames', uid), {uid, username: uid, usernameLowercase: uid});
  });
  const {uid: ignoredUid, ...payload} = publicProfile(uid, {role: 'superAdmin'});
  await assertFails(updateDoc(doc(authedDb(uid), 'users', uid), payload));
});

test('authorization: legal acceptance remains private and profile edits preserve trusted identity', async () => {
  const uid = 'legal_owner';
  await seedUser(uid, {providers: ['phone'], emailVerified: true, accountStatus: 'active'});
  const db = authedDb(uid);
  await assertSucceeds(setDoc(doc(db, 'userPrivate', uid), {
    uid, acceptedTermsAt: serverTimestamp(), acceptedPrivacyAt: serverTimestamp(),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(db, 'userPrivate', uid), {
    uid, acceptedProviderAgreementAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }, {merge: true}));
  await assertSucceeds(updateDoc(doc(db, 'users', uid), {
    role: 'petParent', bio: 'New bio', updatedAt: serverTimestamp(),
  }));
  const data = (await getDoc(doc(db, 'users', uid))).data();
  assert.deepEqual(data.providers, ['phone']);
  assert.equal(data.emailVerified, true);
});

const existingConsentAndMarketingFields = {
  termsCommunicationsAcceptedAt: new Date('2026-01-02T03:04:05Z'),
  termsCommunicationsPolicyVersion: '2026-01',
  marketingEmailEnabled: true,
  marketingEmailPreferenceSource: 'onboarding',
  marketingEmailPreferenceUpdatedAt: new Date('2026-01-02T03:04:05Z'),
};

async function seedPrivateUserDocument(uid, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'userPrivate', uid), {
      uid,
      email: `${uid}@example.test`,
      accountStatus: 'active',
      createdAt: new Date('2025-01-01T00:00:00Z'),
      updatedAt: new Date('2025-01-01T00:00:00Z'),
      ...existingConsentAndMarketingFields,
      ...overrides,
    });
  });
}

async function seedPrivateUserDocumentWithoutProtectedConsent(uid) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'userPrivate', uid), {
      uid,
      email: `${uid}@example.test`,
      accountStatus: 'active',
      createdAt: new Date('2025-01-01T00:00:00Z'),
      updatedAt: new Date('2025-01-01T00:00:00Z'),
    });
  });
}

async function seedProductionShapedPrivateUserDocument(uid) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'userPrivate', uid), {
      uid,
      email: `${uid}@example.test`,
      emailVerified: true,
      phoneNumber: '+910000000000',
      phone: '+910000000000',
      mobileNumber: '+910000000000',
      phoneVerified: true,
      providers: ['password', 'phone'],
      acceptedTermsAt: new Date('2025-01-01T00:00:00Z'),
      acceptedPrivacyAt: new Date('2025-01-01T00:00:00Z'),
      ...existingConsentAndMarketingFields,
      exploreLocation: {
        latitude: 19.076,
        longitude: 72.8777,
        city: 'Mumbai',
        state: 'Maharashtra',
        country: 'India',
        geohash3: 'te7',
        geohash4: 'te7u',
        geohash5: 'te7ud',
        updatedAt: new Date('2026-01-02T03:04:05Z'),
      },
      createdAt: new Date('2025-01-01T00:00:00Z'),
      updatedAt: new Date('2026-01-02T03:04:05Z'),
    });
  });
}

test('authorization: provider agreement update accepts production-shaped private document with historical explore location', async () => {
  const uid = 'agreement_production_shape';
  await seedUser(uid);
  await seedProductionShapedPrivateUserDocument(uid);

  await assertSucceeds(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
    uid,
    acceptedProviderAgreementAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: explore location changes still require a fresh nested timestamp', async () => {
  const uid = 'agreement_location_freshness';
  await seedUser(uid);
  await seedProductionShapedPrivateUserDocument(uid);
  const db = authedDb(uid);

  await assertFails(setDoc(doc(db, 'userPrivate', uid), {
    exploreLocation: {
      latitude: 18.5204,
      longitude: 73.8567,
      city: 'Pune',
      state: 'Maharashtra',
      country: 'India',
      geohash3: 'tek',
      geohash4: 'tek1',
      geohash5: 'tek1x',
      updatedAt: new Date('2026-01-02T03:04:05Z'),
    },
    updatedAt: serverTimestamp(),
  }, {merge: true}));

  await assertSucceeds(setDoc(doc(db, 'userPrivate', uid), {
    exploreLocation: {
      latitude: 18.5204,
      longitude: 73.8567,
      city: 'Pune',
      state: 'Maharashtra',
      country: 'India',
      geohash3: 'tek',
      geohash4: 'tek1',
      geohash5: 'tek1x',
      updatedAt: serverTimestamp(),
    },
    updatedAt: serverTimestamp(),
  }, {merge: true}));

  await assertSucceeds(setDoc(doc(db, 'userPrivate', uid), {
    exploreLocation: deleteField(),
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: adding explore location requires a fresh nested timestamp', async () => {
  const uid = 'agreement_location_addition';
  await seedUser(uid);
  await seedPrivateUserDocument(uid);
  const db = authedDb(uid);
  const location = {
    latitude: 18.5204,
    longitude: 73.8567,
    city: 'Pune',
    state: 'Maharashtra',
    country: 'India',
    geohash3: 'tek',
    geohash4: 'tek1',
    geohash5: 'tek1x',
  };

  await assertFails(setDoc(doc(db, 'userPrivate', uid), {
    exploreLocation: {
      ...location,
      updatedAt: new Date('2026-01-02T03:04:05Z'),
    },
    updatedAt: serverTimestamp(),
  }, {merge: true}));

  await assertSucceeds(setDoc(doc(db, 'userPrivate', uid), {
    exploreLocation: {...location, updatedAt: serverTimestamp()},
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: null or missing optional explore location is accepted', async () => {
  for (const [uid, privateOverrides] of [
    ['agreement_location_missing', {}],
    ['agreement_location_null', {exploreLocation: null}],
  ]) {
    await seedUser(uid);
    await seedPrivateUserDocument(uid, privateOverrides);
    await assertSucceeds(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
      acceptedProviderAgreementAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));
  }
});

test('authorization: malformed explore location maps and invalid types are denied', async () => {
  const uid = 'agreement_location_malformed';
  await seedUser(uid);
  await seedPrivateUserDocument(uid);
  const db = authedDb(uid);

  for (const exploreLocation of [
    {},
    {
      latitude: '18.5204',
      longitude: 73.8567,
      city: 'Pune',
      state: 'Maharashtra',
      country: 'India',
      geohash3: 'tek',
      geohash4: 'tek1',
      geohash5: 'tek1x',
      updatedAt: serverTimestamp(),
    },
    {
      latitude: 18.5204,
      longitude: 73.8567,
      city: 'Pune',
      state: 'Maharashtra',
      country: 'India',
      geohash3: 'tek',
      geohash4: 'tek1',
      geohash5: 'tek1x',
      updatedAt: serverTimestamp(),
      injected: true,
    },
  ]) {
    await assertFails(setDoc(doc(db, 'userPrivate', uid), {
      exploreLocation,
      updatedAt: serverTimestamp(),
    }, {merge: true}));
  }
});

for (const uid of ['official_account_shape', 'normal_account_shape']) {
  test(`authorization: provider agreement update accepts legitimate consent field shape for ${uid}`, async () => {
    await seedUser(uid);
    await seedPrivateUserDocument(uid);

    await assertSucceeds(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
      acceptedProviderAgreementAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }, {merge: true}));

    const data = (await getDoc(doc(authedDb(uid), 'userPrivate', uid))).data();
    assert.equal(data.marketingEmailEnabled, true);
    assert.equal(data.marketingEmailPreferenceSource, 'onboarding');
  });
}

test('authorization: provider agreement update cannot target another user', async () => {
  const ownerUid = 'agreement_owner';
  const attackerUid = 'agreement_attacker';
  await seedUser(ownerUid);
  await seedUser(attackerUid);
  await seedPrivateUserDocument(ownerUid);

  await assertFails(setDoc(doc(authedDb(attackerUid), 'userPrivate', ownerUid), {
    acceptedProviderAgreementAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: inactive account cannot update provider agreement', async () => {
  const uid = 'agreement_inactive_owner';
  await seedUser(uid, {accountStatus: 'suspended'});
  await seedPrivateUserDocument(uid);

  await assertFails(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
    acceptedProviderAgreementAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: provider agreement update cannot change consent or marketing fields', async () => {
  const uid = 'agreement_protected_fields';
  await seedUser(uid);
  await seedPrivateUserDocument(uid);
  const db = authedDb(uid);

  for (const protectedChange of [
    {termsCommunicationsAcceptedAt: serverTimestamp()},
    {termsCommunicationsPolicyVersion: 'attacker-version'},
    {marketingEmailEnabled: false},
    {marketingEmailPreferenceSource: 'agreement-update'},
    {marketingEmailPreferenceUpdatedAt: serverTimestamp()},
  ]) {
    await assertFails(setDoc(doc(db, 'userPrivate', uid), {
      acceptedProviderAgreementAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...protectedChange,
    }, {merge: true}));
  }
});

test('authorization: provider agreement update cannot add protected consent or marketing fields', async () => {
  const uid = 'agreement_protected_field_additions';
  await seedUser(uid);
  await seedPrivateUserDocumentWithoutProtectedConsent(uid);
  const db = authedDb(uid);

  for (const protectedAddition of [
    {termsCommunicationsAcceptedAt: serverTimestamp()},
    {termsCommunicationsPolicyVersion: '2026-01'},
    {marketingEmailEnabled: true},
    {marketingEmailPreferenceSource: 'agreement-update'},
    {marketingEmailPreferenceUpdatedAt: serverTimestamp()},
  ]) {
    await assertFails(setDoc(doc(db, 'userPrivate', uid), {
      acceptedProviderAgreementAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...protectedAddition,
    }, {merge: true}));
  }
});

test('authorization: provider agreement update cannot remove protected consent or marketing fields', async () => {
  const uid = 'agreement_protected_field_removals';
  await seedUser(uid);
  await seedPrivateUserDocument(uid);
  const db = authedDb(uid);

  for (const protectedField of Object.keys(existingConsentAndMarketingFields)) {
    await assertFails(setDoc(doc(db, 'userPrivate', uid), {
      acceptedProviderAgreementAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      [protectedField]: deleteField(),
    }, {merge: true}));
  }
});

test('authorization: mixed permitted and prohibited private update is denied', async () => {
  const uid = 'agreement_mixed_update';
  await seedUser(uid);
  await seedPrivateUserDocument(uid);

  await assertFails(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
    acceptedProviderAgreementAt: serverTimestamp(),
    marketingEmailEnabled: false,
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: provider agreement update still rejects unknown document fields', async () => {
  const uid = 'agreement_unknown_field';
  await seedUser(uid);
  await seedPrivateUserDocument(uid, {unexpectedPrivateField: 'blocked'});

  await assertFails(setDoc(doc(authedDb(uid), 'userPrivate', uid), {
    acceptedProviderAgreementAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }, {merge: true}));
});

test('authorization: social post and location intent remain owner-bound', async () => {
  const ownerUid = 'social_owner';
  const otherUid = 'social_other';
  const postId = 'social-post-1';
  await seedUser(ownerUid);
  await seedUser(otherUid);
  const ownerDb = authedDb(ownerUid);
  const ownerBatch = writeBatch(ownerDb);
  ownerBatch.set(
    doc(ownerDb, 'socialPosts', postId),
    socialPostPayload(ownerUid, postId),
  );
  ownerBatch.set(doc(ownerDb, 'socialPostLocationIntents', postId), {
    ownerUid,
    source: 'freshDeviceAtPublish',
    location: {
      latitude: 19.076,
      longitude: 72.8777,
      city: 'Mumbai',
      state: 'Maharashtra',
      country: 'India',
    },
    capturedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(ownerBatch.commit());

  await assertFails(setDoc(
    doc(authedDb(otherUid), 'socialPosts', 'forged-social-post'),
    socialPostPayload(ownerUid, 'forged-social-post'),
  ));
  await assertFails(updateDoc(
    doc(authedDb(otherUid), 'socialPosts', postId),
    {caption: 'Hijacked'},
  ));
  await assertFails(setDoc(
    doc(authedDb(otherUid), 'socialPostLocationIntents', 'forged-intent'),
    {
      ownerUid,
      source: 'freshDeviceAtPublish',
      location: {
        latitude: 19.076,
        longitude: 72.8777,
        city: 'Mumbai',
        state: 'Maharashtra',
        country: 'India',
      },
      capturedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    },
  ));
});

test('authorization: username changes stay server-owned after profile completion', async () => {
  const uid = 'username_owner';
  await seedUser(uid);
  await assertFails(updateDoc(doc(authedDb(uid), 'users', uid), {
    username: 'new_username', usernameLowercase: 'new_username', updatedAt: serverTimestamp(),
  }));
  // The existing changeUsername callable uses the Admin SDK, which bypasses
  // these client rules. Simulate its trusted write boundary, not its business logic.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'users', uid), {
      username: 'new_username', usernameLowercase: 'new_username', updatedAt: serverTimestamp(),
    });
  });
  await assertSucceeds(updateDoc(doc(authedDb(uid), 'users', uid), {bio: 'Updated', updatedAt: serverTimestamp()}));
});

test('authorization: clients cannot directly claim the protected pettxo username', async () => {
  const uid = 'official_username_attempt';
  const db = authedDb(uid);
  await assertFails(setDoc(doc(db, 'usernames', 'pettxo'), {
    uid,
    username: 'pettxo',
    usernameLowercase: 'pettxo',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('authorization: a username reservation cannot outlive an interrupted profile write', async () => {
  const uid = 'reserve_no_profile';
  const db = authedDb(uid);
  await assertFails(setDoc(doc(db, 'usernames', 'abandoned_name'), {
    uid,
    username: 'abandoned_name',
    usernameLowercase: 'abandoned_name',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));

  await assertSucceeds(createProfile(db, uid));
});

async function seedCanonicalConfirmedBooking({
  bookingId,
  parentId,
  providerId,
  paid = true,
}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(bookingDoc(db, bookingId), {
      customerId: parentId,
      serviceOwnerId: providerId,
      state: paid ? 'CONFIRMED' : 'ACCEPTED_AWAITING_PAYMENT',
      lifecycle: {
        paidAt: paid ? new Date() : null,
      },
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(bookingPrivateDoc(db, bookingId), {
      bookingId,
      parentId,
      providerId,
      parentOtpCode: '123456',
      providerOtpHash: 'hash',
      otpState: paid ? 'ACTIVE' : 'REVOKED',
      failedAttemptCount: 0,
      lastFailedAttemptAt: null,
      lockedUntil: null,
      verifiedAt: null,
      successfulAttemptNumber: null,
      lastVerificationAttemptId: '',
      lastVerificationOutcome: '',
      contactUnlockedAt: paid ? new Date() : null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(bookingPrivateParticipantsDoc(db, bookingId), {
      bookingId,
      parentId,
      providerId,
      unlockedAfterPaidOnly: true,
      parentPrivate: {
        fullName: 'Parent User',
        phoneNumber: '+919999999999',
        email: 'parent@example.com',
        exactAddress: 'Mumbai',
        latitude: 19.076,
        longitude: 72.8777,
      },
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(bookingChatDoc(db, bookingId), {
      bookingId,
      participantIds: [parentId, providerId],
      status: paid ? 'unlocked' : 'locked',
      unlockedAt: paid ? new Date() : null,
      createdBy: 'system',
      updatedAt: new Date(),
    });
  });
}

async function seedCanonicalCancellationArtifacts({
  bookingId,
  parentId,
  providerId,
}) {
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId,
    providerId,
    paid: true,
  });
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(bookingDoc(db, bookingId), {
      parentId,
      providerId,
      customerId: parentId,
      serviceOwnerId: providerId,
      state: 'CANCELLED',
      lifecycle: {
        paidAt: new Date(),
        cancelledAt: new Date(),
      },
      updatedAt: new Date(),
    }, {merge: true});
    await setDoc(bookingCancellationDoc(db, bookingId), {
      bookingId,
      actorId: parentId,
      refundStatus: 'REFUND_PENDING',
      status: 'CANCELLED',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(bookingFinancialAdjustmentDoc(db, bookingId), {
      bookingId,
      userId: parentId,
      providerId,
      refundPaise: 9000,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await setDoc(capacityReleaseDoc(db, bookingId), {
      bookingId,
      state: 'RELEASED',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

test('owner can create own provider verification with metadata fields', async () => {
  const uid = 'owner1';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertSucceeds(setDoc(verificationDoc(db, uid), ownerPayload(uid)));
});

test('another user cannot create or update someone else verification', async () => {
  const ownerUid = 'owner2';
  const otherUid = 'other2';
  await seedUser(ownerUid);
  await seedUser(otherUid);

  const ownerDb = authedDb(ownerUid);
  const otherDb = authedDb(otherUid);

  await assertSucceeds(
    setDoc(verificationDoc(ownerDb, ownerUid), ownerPayload(ownerUid)),
  );
  await assertFails(
    setDoc(verificationDoc(otherDb, ownerUid), ownerPayload(ownerUid)),
  );
  await assertFails(
    updateDoc(verificationDoc(otherDb, ownerUid), {updatedAt: serverTimestamp()}),
  );
});

test('owner cannot set approved status', async () => {
  const uid = 'owner3';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertFails(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {status: 'approved'}),
    ),
  );
});

test('owner cannot set reviewedBy or reviewedAt', async () => {
  const uid = 'owner4';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertFails(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {
        reviewedBy: 'admin1',
        reviewedAt: serverTimestamp(),
      }),
    ),
  );
});

test('H-03 owner cannot replace submitted verification metadata while pending', async () => {
  const uid = 'owner-pending-immutable';
  await seedUser(uid);
  const db = authedDb(uid);
  await assertSucceeds(setDoc(verificationDoc(db, uid), ownerPayload(uid)));
  await assertFails(setDoc(verificationDoc(db, uid), ownerPayload(uid, {
    submissionId: 'submission-replacement',
    documentFrontPath: `providerVerification/${uid}/identity/submission-replacement/front.png`,
  })));
});

test('H-03 rejected verification can be resubmitted as a new immutable version', async () => {
  const uid = 'owner-rejected-resubmit';
  await seedUser(uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(verificationDoc(context.firestore(), uid), {
      ...ownerPayload(uid),
      status: 'rejected',
      rejectionReason: 'Unreadable',
      reviewedBy: 'reviewer',
      reviewedAt: new Date(),
      createdAt: new Date(),
      submittedAt: new Date(),
      updatedAt: new Date(),
    });
  });
  const db = authedDb(uid);
  const resubmission = ownerPayload(uid, {
    submissionId: 'submission-resubmitted',
    documentFrontPath: `providerVerification/${uid}/identity/submission-resubmitted/front.png`,
  });
  delete resubmission.createdAt;
  await assertSucceeds(setDoc(
    verificationDoc(db, uid),
    resubmission,
    {merge: true},
  ));
});

test('provider payout reads stay provider-or-admin only and clients cannot write', async () => {
  const providerUid = 'providerPayoutOwner';
  const otherUid = 'providerPayoutOther';
  const adminUid = 'providerPayoutAdmin';
  await seedUser(providerUid);
  await seedUser(otherUid);
  await seedUser(adminUid, {adminRole: 'financeAdmin'});

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(providerPayoutDoc(db, 'booking-1'), {
      payoutId: 'booking-1',
      bookingId: 'booking-1',
      providerId: providerUid,
      status: 'READY',
      remainingPayablePaise: 20000,
      accountNumberMasked: 'XXXX1234',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });

  await assertSucceeds(getDoc(providerPayoutDoc(authedDb(providerUid), 'booking-1')));
  await assertSucceeds(getDoc(providerPayoutDoc(authedDb(adminUid), 'booking-1')));
  await assertFails(getDoc(providerPayoutDoc(authedDb(otherUid), 'booking-1')));
  await assertFails(
    updateDoc(providerPayoutDoc(authedDb(providerUid), 'booking-1'), {
      status: 'PAID',
    }),
  );
});

test('support tickets are readable by the owning customer and support admins only', async () => {
  const ownerUid = 'supportOwner';
  const otherUid = 'supportOther';
  const supportAdminUid = 'supportAdmin';
  const financeAdminUid = 'supportFinance';
  await seedUser(ownerUid);
  await seedUser(otherUid);
  await seedUser(supportAdminUid, {adminRole: 'customerSupportAdmin'});
  await seedUser(financeAdminUid, {adminRole: 'financeAdmin'});

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(supportTicketDoc(db, 'ticket-1'), {
      ticketId: 'ticket-1',
      userId: ownerUid,
      category: 'technical_issue',
      subject: 'App issue',
      initialMessage: 'Something broke.',
      status: 'open',
      customerUnreadCount: 0,
      adminUnreadCount: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastMessageAt: new Date(),
      lastMessagePreview: 'Something broke.',
      lastMessageSenderType: 'customer',
    });
    await setDoc(supportTicketMessageDoc(db, 'ticket-1', 'message-1'), {
      messageId: 'message-1',
      senderId: ownerUid,
      senderType: 'customer',
      message: 'Something broke.',
      createdAt: new Date(),
    });
  });

  await assertSucceeds(getDoc(supportTicketDoc(authedDb(ownerUid), 'ticket-1')));
  await assertSucceeds(
    getDoc(supportTicketDoc(authedDb(supportAdminUid), 'ticket-1')),
  );
  await assertFails(getDoc(supportTicketDoc(authedDb(otherUid), 'ticket-1')));
  await assertFails(
    getDoc(supportTicketDoc(authedDb(financeAdminUid), 'ticket-1')),
  );

  await assertSucceeds(
    getDoc(supportTicketMessageDoc(authedDb(ownerUid), 'ticket-1', 'message-1')),
  );
  await assertSucceeds(
    getDoc(
      supportTicketMessageDoc(
        authedDb(supportAdminUid),
        'ticket-1',
        'message-1',
      ),
    ),
  );
  await assertFails(
    getDoc(supportTicketMessageDoc(authedDb(otherUid), 'ticket-1', 'message-1')),
  );
  await assertFails(
    getDoc(
      supportTicketMessageDoc(
        authedDb(financeAdminUid),
        'ticket-1',
        'message-1',
      ),
    ),
  );
});

test('support ticket documents remain client write blocked', async () => {
  const ownerUid = 'supportWriteOwner';
  const supportAdminUid = 'supportWriteAdmin';
  await seedUser(ownerUid);
  await seedUser(supportAdminUid, {adminRole: 'customerSupportAdmin'});

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(supportTicketDoc(db, 'ticket-2'), {
      ticketId: 'ticket-2',
      userId: ownerUid,
      category: 'account',
      subject: 'Need help',
      initialMessage: 'Hello',
      status: 'open',
      customerUnreadCount: 0,
      adminUnreadCount: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastMessageAt: new Date(),
      lastMessagePreview: 'Hello',
      lastMessageSenderType: 'customer',
    });
  });

  await assertFails(
    updateDoc(supportTicketDoc(authedDb(ownerUid), 'ticket-2'), {
      status: 'resolved',
    }),
  );
  await assertFails(
    setDoc(
      supportTicketMessageDoc(authedDb(ownerUid), 'ticket-2', 'message-2'),
      {
        messageId: 'message-2',
        senderId: ownerUid,
        senderType: 'customer',
        message: 'Client should not write directly.',
        createdAt: new Date(),
      },
    ),
  );
  await assertFails(
    updateDoc(supportTicketDoc(authedDb(supportAdminUid), 'ticket-2'), {
      status: 'awaiting_customer',
    }),
  );
});

test('financial ledger is admin-read-only and client-write-blocked', async () => {
  const providerUid = 'ledgerProvider';
  const customerUid = 'ledgerCustomer';
  const adminUid = 'ledgerAdmin';
  await seedUser(providerUid);
  await seedUser(customerUid);
  await seedUser(adminUid, {adminRole: 'financeAdmin'});

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(bookingFinancialLedgerDoc(db, 'entry-1'), {
      entryId: 'entry-1',
      bookingId: 'booking-1',
      providerId: providerUid,
      type: 'PROVIDER_PAYOUT',
      amountPaise: 20000,
      createdAt: new Date(),
    });
  });

  await assertSucceeds(getDoc(bookingFinancialLedgerDoc(authedDb(adminUid), 'entry-1')));
  await assertFails(getDoc(bookingFinancialLedgerDoc(authedDb(providerUid), 'entry-1')));
  await assertFails(getDoc(bookingFinancialLedgerDoc(authedDb(customerUid), 'entry-1')));
  await assertFails(
    setDoc(bookingFinancialLedgerDoc(authedDb(adminUid), 'entry-2'), {
      entryId: 'entry-2',
      bookingId: 'booking-1',
    }),
  );
});

test('dispute resolutions and reconciliation remain admin-only collections', async () => {
  const providerUid = 'financialProvider';
  const customerUid = 'financialCustomer';
  const financeUid = 'financialFinance';
  const supportUid = 'financialSupport';
  await seedUser(providerUid);
  await seedUser(customerUid);
  await seedUser(financeUid, {adminRole: 'financeAdmin'});
  await seedUser(supportUid, {adminRole: 'customerSupportAdmin'});

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(bookingDisputeResolutionDoc(db, 'resolution-1'), {
      resolutionId: 'resolution-1',
      bookingId: 'booking-1',
      createdAt: new Date(),
    });
    await setDoc(bookingFinancialReconciliationDoc(db, 'booking-1'), {
      bookingId: 'booking-1',
      status: 'BALANCED',
      createdAt: new Date(),
    });
  });

  await assertSucceeds(
    getDoc(bookingDisputeResolutionDoc(authedDb(financeUid), 'resolution-1')),
  );
  await assertSucceeds(
    getDoc(bookingDisputeResolutionDoc(authedDb(supportUid), 'resolution-1')),
  );
  await assertFails(
    getDoc(bookingDisputeResolutionDoc(authedDb(providerUid), 'resolution-1')),
  );
  await assertFails(
    updateDoc(bookingDisputeResolutionDoc(authedDb(financeUid), 'resolution-1'), {
      note: 'mutate',
    }),
  );

  await assertSucceeds(
    getDoc(
      bookingFinancialReconciliationDoc(authedDb(financeUid), 'booking-1'),
    ),
  );
  await assertSucceeds(
    getDoc(
      bookingFinancialReconciliationDoc(authedDb(supportUid), 'booking-1'),
    ),
  );
  await assertFails(
    getDoc(
      bookingFinancialReconciliationDoc(authedDb(customerUid), 'booking-1'),
    ),
  );
  await assertFails(
    setDoc(
      bookingFinancialReconciliationDoc(authedDb(financeUid), 'booking-2'),
      {bookingId: 'booking-2'},
    ),
  );
});

test('admin can still review the request', async () => {
  const ownerUid = 'owner5';
  const adminUid = 'admin5';
  await seedUser(ownerUid);
  await seedUser(adminUid, {adminRole: 'superAdmin'});

  const ownerDb = authedDb(ownerUid);
  const adminDb = authedDb(adminUid);

  await assertSucceeds(
    setDoc(verificationDoc(ownerDb, ownerUid), ownerPayload(ownerUid)),
  );
  await assertSucceeds(
    updateDoc(verificationDoc(adminDb, ownerUid), {
      status: 'approved',
      reviewedBy: adminUid,
      reviewedAt: serverTimestamp(),
      rejectionReason: '',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('invalid metadata types are rejected', async () => {
  const uid = 'owner6';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertFails(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {documentFrontContentType: 123}),
    ),
  );
});

test('overlong file names are rejected', async () => {
  const uid = 'owner7';
  await seedUser(uid);
  const db = authedDb(uid);
  const longName = `${'a'.repeat(256)}.png`;

  await assertFails(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {documentFrontFileName: longName}),
    ),
  );
});

test('unexpected extra fields are rejected', async () => {
  const uid = 'owner8';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertFails(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {unexpectedField: true}),
    ),
  );
});

test('pan card document type is allowed for owner submission', async () => {
  const uid = 'owner9';
  await seedUser(uid);
  const db = authedDb(uid);

  await assertSucceeds(
    setDoc(
      verificationDoc(db, uid),
      ownerPayload(uid, {documentType: 'panCard'}),
    ),
  );
});

test('provider cannot read booking private data before payment confirmation', async () => {
  const parentUid = 'parent10';
  const providerUid = 'provider10';
  const bookingId = 'booking10';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: false,
  });

  await assertFails(
    getDoc(bookingPrivateDoc(authedDb(providerUid), bookingId)),
  );
  await assertFails(
    getDoc(bookingPrivateDoc(authedDb(parentUid), bookingId)),
  );
});

test('provider may not read OTP-bearing booking private data after canonical paid confirmation', async () => {
  const parentUid = 'parent11';
  const providerUid = 'provider11';
  const bookingId = 'booking11';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: true,
  });

  await assertFails(getDoc(bookingPrivateDoc(authedDb(providerUid), bookingId)));
  await assertSucceeds(
    getDoc(bookingPrivateDoc(authedDb(parentUid), bookingId)),
  );
});

test('participants may read provider-safe paid booking details after canonical confirmation', async () => {
  const parentUid = 'parent11b';
  const providerUid = 'provider11b';
  const bookingId = 'booking11b';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: true,
  });

  await assertSucceeds(
    getDoc(bookingPrivateParticipantsDoc(authedDb(providerUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(bookingPrivateParticipantsDoc(authedDb(parentUid), bookingId)),
  );
});

test('unrelated user cannot read booking private data', async () => {
  const parentUid = 'parent12';
  const providerUid = 'provider12';
  const otherUid = 'other12';
  const bookingId = 'booking12';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedUser(otherUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: true,
  });

  await assertFails(
    getDoc(bookingPrivateDoc(authedDb(otherUid), bookingId)),
  );
  await assertFails(
    getDoc(bookingPrivateParticipantsDoc(authedDb(otherUid), bookingId)),
  );
});

test('booking chat stays locked until canonical paid confirmation', async () => {
  const parentUid = 'parent13';
  const providerUid = 'provider13';
  const bookingId = 'booking13';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: false,
  });

  await assertFails(getDoc(bookingChatDoc(authedDb(parentUid), bookingId)));
  await assertFails(getDoc(bookingChatDoc(authedDb(providerUid), bookingId)));
});

test('booking chat unlocks for canonical paid participants only', async () => {
  const parentUid = 'parent14';
  const providerUid = 'provider14';
  const otherUid = 'other14';
  const bookingId = 'booking14';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedUser(otherUid);
  await seedCanonicalConfirmedBooking({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
    paid: true,
  });

  await assertSucceeds(getDoc(bookingChatDoc(authedDb(parentUid), bookingId)));
  await assertSucceeds(getDoc(bookingChatDoc(authedDb(providerUid), bookingId)));
  await assertFails(getDoc(bookingChatDoc(authedDb(otherUid), bookingId)));
});

test('participants can read canonical cancellation artifacts but unrelated users cannot', async () => {
  const parentUid = 'parent15';
  const providerUid = 'provider15';
  const otherUid = 'other15';
  const bookingId = 'booking15';
  await seedUser(parentUid);
  await seedUser(providerUid);
  await seedUser(otherUid);
  await seedCanonicalCancellationArtifacts({
    bookingId,
    parentId: parentUid,
    providerId: providerUid,
  });

  await assertSucceeds(
    getDoc(bookingCancellationDoc(authedDb(parentUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(bookingCancellationDoc(authedDb(providerUid), bookingId)),
  );
  await assertFails(
    getDoc(bookingCancellationDoc(authedDb(otherUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(bookingFinancialAdjustmentDoc(authedDb(parentUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(bookingFinancialAdjustmentDoc(authedDb(providerUid), bookingId)),
  );
  await assertFails(
    getDoc(bookingFinancialAdjustmentDoc(authedDb(otherUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(capacityReleaseDoc(authedDb(parentUid), bookingId)),
  );
  await assertSucceeds(
    getDoc(capacityReleaseDoc(authedDb(providerUid), bookingId)),
  );
  await assertFails(
    getDoc(capacityReleaseDoc(authedDb(otherUid), bookingId)),
  );
});

test('customers and providers cannot rewrite slot capacity or occupancy', async () => {
  await seedUser('slotCustomer');
  await seedUser('slotProvider');
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'services', 'capacityService'), {
      ownerUserId: 'slotProvider', isVisibleToMarketplace: true, isDeleted: false,
    });
    await setDoc(doc(db, 'services', 'capacityService', 'slots', 'slotOne'), {
      capacity: 1, acceptedCount: 1, status: 'open', isBookable: true,
    });
    await setDoc(doc(db, 'services', 'capacityService', 'slotOccupancy', 'slotOne'), {
      confirmedUnits: 1, capacitySnapshot: 1, bookingClaims: {bookingA: 1},
    });
  });
  for (const uid of ['slotCustomer', 'slotProvider']) {
    const db = authedDb(uid);
    const slot = doc(db, 'services', 'capacityService', 'slots', 'slotOne');
    const occupancy = doc(db, 'services', 'capacityService', 'slotOccupancy', 'slotOne');
    await assertSucceeds(getDoc(slot));
    await assertFails(updateDoc(slot, {acceptedCount: 0}));
    await assertFails(setDoc(slot, {capacity: 99, acceptedCount: 0}));
    await assertFails(getDoc(occupancy));
    await assertFails(updateDoc(occupancy, {confirmedUnits: 0}));
  }
});

test('H-01 canonical booking, slot, occupancy, and financial writes are server-only for every client role', async () => {
  const actors = [
    ['customer', {}],
    ['provider', {}],
    ['support', {adminRole: 'customerSupportAdmin'}],
    ['finance', {adminRole: 'financeAdmin'}],
    ['super', {adminRole: 'superAdmin'}],
  ];
  for (const [uid, fields] of actors) await seedUser(uid, fields);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'bookings', 'canonical-h01'), {customerId: 'customer', serviceOwnerId: 'provider', state: 'CONFIRMED'});
    await setDoc(doc(db, 'services', 'canonical-service'), {ownerUserId: 'provider', isVisibleToMarketplace: true, isDeleted: false});
    await setDoc(doc(db, 'services', 'canonical-service', 'slots', 'slot-1'), {capacity: 1, acceptedCount: 1});
    await setDoc(doc(db, 'services', 'canonical-service', 'slotOccupancy', 'slot-1'), {confirmedUnits: 1});
    await setDoc(doc(db, 'payments', 'payment-h01'), {userId: 'customer', providerId: 'provider', status: 'captured'});
  });
  for (const [uid] of actors) {
    const db = authedDb(uid);
    await assertFails(setDoc(doc(db, 'bookings', `forged-${uid}`), {state: 'COMPLETED_FINAL'}));
    await assertFails(updateDoc(doc(db, 'bookings', 'canonical-h01'), {state: 'COMPLETED_FINAL'}));
    await assertFails(updateDoc(doc(db, 'services', 'canonical-service', 'slots', 'slot-1'), {acceptedCount: 0}));
    await assertFails(updateDoc(doc(db, 'services', 'canonical-service', 'slotOccupancy', 'slot-1'), {confirmedUnits: 0}));
    await assertFails(updateDoc(doc(db, 'payments', 'payment-h01'), {status: 'refunded'}));
  }
  await assertSucceeds(getDoc(doc(authedDb('customer'), 'bookings', 'canonical-h01')));
  await assertSucceeds(getDoc(doc(authedDb('provider'), 'bookings', 'canonical-h01')));
  await assertSucceeds(getDoc(doc(authedDb('support'), 'bookings', 'canonical-h01')));
  await assertSucceeds(getDoc(doc(authedDb('finance'), 'payments', 'payment-h01')));
  await assertSucceeds(getDoc(doc(authedDb('super'), 'payments', 'payment-h01')));
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'bookings', 'canonical-h01'), {state: 'IN_PROGRESS'});
  });
});

test('H-02 legitimate provider service creation and pause remain allowed', async () => {
  const uid = 'service-owner-legitimate';
  const serviceId = 'service-legitimate';
  await seedPendingProvider(uid);
  const db = authedDb(uid);
  await assertSucceeds(createServicePair(db, uid, serviceId));
  await assertSucceeds(updateDoc(doc(db, 'services', serviceId), {
    isPaused: true,
    isActive: false,
    status: 'paused',
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(db, 'servicePrivate', serviceId), {
    privateNotes: 'Use side entrance',
    updatedAt: serverTimestamp(),
  }));
});

test('H-02 legacy providers can pause and remove without broad schema mutation access', async () => {
  const uid = 'legacy-lifecycle-owner';
  const serviceId = 'legacy-lifecycle-service';
  await seedUser(uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'services', serviceId), {
      ownerUserId: uid,
      title: 'Legacy service',
      status: 'active',
      isActive: true,
      isDeleted: false,
      isPaused: false,
      isVisibleToMarketplace: true,
      location: {
        displayAddress: 'Legacy exact address',
        latitude: 19.076,
        longitude: 72.8777,
      },
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
  const ref = doc(authedDb(uid), 'services', serviceId);
  await assertSucceeds(updateDoc(ref, {
    status: 'paused',
    isActive: false,
    isPaused: true,
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    pricePerSession: 1,
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(ref, {
    status: 'removed',
    isActive: false,
    isDeleted: true,
    isVisibleToMarketplace: false,
    removedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

const invalidServiceCreates = [
  ['self-approved moderation', {moderationStatus: 'approved'}],
  ['negative price', {pricePerSession: -1}],
  ['zero capacity', {capacity: 0}],
  ['invalid capacity type', {capacity: 'two'}],
  ['forged verification state', {providerVerificationStatus: 'approved'}],
  ['unknown dangerous field', {adminApproved: true}],
];
for (const [caseName, overrides] of invalidServiceCreates) {
  test(`H-02 service create denies ${caseName}`, async () => {
    const uid = `service-create-${caseName.replaceAll(' ', '-')}`;
    await seedPendingProvider(uid);
    await assertFails(createServicePair(authedDb(uid), uid, `service-${uid}`, overrides));
  });
}

test('H-02 rejected provider cannot force marketplace-visible creation', async () => {
  const uid = 'service-owner-rejected';
  await seedUser(uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(verificationDoc(context.firestore(), uid), {userId: uid, status: 'rejected'});
  });
  await assertFails(createServicePair(authedDb(uid), uid, 'service-rejected'));
});

test('H-02 protected additions, deletions, ownership, and type mutations are denied', async () => {
  const uid = 'service-owner-update';
  const serviceId = 'service-update';
  await seedPendingProvider(uid);
  const db = authedDb(uid);
  await assertSucceeds(createServicePair(db, uid, serviceId));
  const ref = doc(db, 'services', serviceId);
  await assertFails(updateDoc(ref, {moderationReason: 'self approved', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {moderationStatus: deleteField(), updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {ownerUserId: 'attacker', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {capacity: 'unlimited', updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {providerVerificationStatus: 'approved', updatedAt: serverTimestamp()}));
});

test('H-02 moderation writes require the callable and finance cannot write moderation directly', async () => {
  const owner = 'moderated-owner';
  await seedPendingProvider(owner);
  await createServicePair(authedDb(owner), owner, 'moderated-service');
  for (const [uid, role] of [['support-moderator', 'customerSupportAdmin'], ['finance-moderator', 'financeAdmin'], ['super-moderator', 'superAdmin']]) {
    await seedUser(uid, {adminRole: role});
    await assertFails(updateDoc(doc(authedDb(uid), 'services', 'moderated-service'), {
      moderationStatus: 'approved', isVisibleToMarketplace: true, updatedAt: serverTimestamp(),
    }));
  }
});

test('H-04 public marketplace service exposes only coarse location and private data is role-scoped', async () => {
  const owner = 'private-service-owner';
  const customer = 'private-service-customer';
  const support = 'private-service-support';
  const finance = 'private-service-finance';
  await seedPendingProvider(owner);
  await seedUser(customer);
  await seedUser(support, {adminRole: 'customerSupportAdmin'});
  await seedUser(finance, {adminRole: 'financeAdmin'});
  await createServicePair(authedDb(owner), owner, 'private-service');
  const publicSnapshot = await assertSucceeds(getDoc(doc(authedDb(customer), 'services', 'private-service')));
  assert.equal(publicSnapshot.data().privateNotes, undefined);
  assert.equal(publicSnapshot.data().location.latitude, undefined);
  assert.equal(publicSnapshot.data().location.displayAddress, undefined);
  await assertFails(getDoc(doc(authedDb(customer), 'servicePrivate', 'private-service')));
  await assertSucceeds(getDoc(doc(authedDb(owner), 'servicePrivate', 'private-service')));
  await assertSucceeds(getDoc(doc(authedDb(support), 'servicePrivate', 'private-service')));
  await assertSucceeds(getDoc(doc(authedDb(finance), 'servicePrivate', 'private-service')));
});

test('H-04 marketplace query can read sanitized visible services', async () => {
  const owner = 'marketplace-query-owner';
  const customer = 'marketplace-query-customer';
  await seedPendingProvider(owner);
  await seedUser(customer);
  await createServicePair(authedDb(owner), owner, 'marketplace-query-service');
  const servicesQuery = query(
    collection(authedDb(customer), 'services'),
    where('status', '==', 'active'),
    where('isActive', '==', true),
    where('isDeleted', '==', false),
    where('isPaused', '==', false),
    where('isVisibleToMarketplace', '==', true),
  );
  const snapshot = await assertSucceeds(getDocs(servicesQuery));
  assert.equal(snapshot.size, 1);
});

test('H-04 clients cannot create or restore exact location in public services', async () => {
  const owner = 'public-location-owner';
  const serviceId = 'public-location-service';
  await seedPendingProvider(owner);
  const db = authedDb(owner);
  await assertFails(createServicePair(db, owner, 'exact-create-service', {
    location: {
      displayAddress: 'Exact address', latitude: 19.076, longitude: 72.8777,
      geohash: 'te7ud', city: 'Mumbai', state: 'Maharashtra', country: 'IN',
    },
  }));
  await assertSucceeds(createServicePair(db, owner, serviceId));
  await assertFails(updateDoc(doc(db, 'services', serviceId), {
    location: {
      displayAddress: 'Exact address', latitude: 19.076, longitude: 72.8777,
      geohash: 'te7ud', city: 'Mumbai', state: 'Maharashtra', country: 'IN',
    },
    updatedAt: serverTimestamp(),
  }));
});

test('item 27: adminRateLimits is server-only for every role, including Super Admin', async () => {
  await seedUser('member', {role: 'petParent'});
  for (const role of adminRoles) await seedUser(`rl-${role}`, {adminRole: role});
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'adminRateLimits', 'rl-superAdmin_contactReveal'), {
      adminUid: 'rl-superAdmin',
      bucket: 'contactReveal',
      events: [1],
    });
  });
  const contexts = [
    testEnv.unauthenticatedContext().firestore(),
    authedDb('member'),
    ...adminRoles.map((role) => authedDb(`rl-${role}`)),
  ];
  for (const db of contexts) {
    await assertFails(getDoc(doc(db, 'adminRateLimits', 'rl-superAdmin_contactReveal')));
    await assertFails(getDocs(collection(db, 'adminRateLimits')));
    await assertFails(setDoc(doc(db, 'adminRateLimits', 'rl-superAdmin_contactReveal'), {events: []}));
    await assertFails(setDoc(doc(db, 'adminRateLimits', 'new-bucket'), {events: []}));
    await assertFails(updateDoc(doc(db, 'adminRateLimits', 'rl-superAdmin_contactReveal'), {events: []}));
  }
});
