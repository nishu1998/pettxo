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
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
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

function ownerPayload(uid, overrides = {}) {
  return {
    userId: uid,
    status: 'pending',
    documentType: 'aadhaar',
    documentFrontPath: `providerVerification/${uid}/identity/front.png`,
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
