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
  getFirestore,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-pettexo';
const firestoreRules = readFileSync('../firestore.rules', 'utf8');

let testEnv;

function authedDb(uid) {
  return getFirestore(testEnv.authenticatedContext(uid).app);
}

async function seedUser(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = getFirestore(context.app);
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

function ownerPayload(uid, overrides = {}) {
  return {
    userId: uid,
    status: 'pending',
    documentType: 'aadhaar',
    documentFrontUrl: 'https://example.com/front.png',
    documentBackUrl: '',
    documentFrontContentType: 'image/png',
    documentBackContentType: null,
    documentFrontFileName: 'front.png',
    documentBackFileName: null,
    submittedAt: serverTimestamp(),
    reviewedAt: null,
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
