import {readFileSync} from 'node:fs';
import test, {after, before} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {getFirestore, doc, setDoc} from 'firebase/firestore';
import {
  deleteObject,
  getBytes,
  getStorage,
  ref,
  uploadBytes,
} from 'firebase/storage';

const projectId = 'demo-pettexo';
const bucket = 'demo-pettexo.firebasestorage.app';
const storageRules = readFileSync('../storage.rules', 'utf8');
const firestoreRules = readFileSync('../firestore.rules', 'utf8');

let testEnv;

function authedStorage(uid) {
  return getStorage(testEnv.authenticatedContext(uid).app, `gs://${bucket}`);
}

function unauthedStorage() {
  return getStorage(testEnv.unauthenticatedContext().app, `gs://${bucket}`);
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

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules: firestoreRules},
    storage: {rules: storageRules},
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('owner can upload a supported image under their own UID', async () => {
  const uid = 'owner-storage-1';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const imageRef = ref(
    storage,
    `providerVerification/${uid}/identity/front.png`,
  );

  await assertSucceeds(
    uploadBytes(imageRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
});

test('owner can upload a supported PDF', async () => {
  const uid = 'owner-storage-2';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const pdfRef = ref(
    storage,
    `providerVerification/${uid}/identity/front.pdf`,
  );

  await assertSucceeds(
    uploadBytes(pdfRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'application/pdf',
    }),
  );
});

test('files larger than 10 MB are rejected', async () => {
  const uid = 'owner-storage-3';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const largeRef = ref(
    storage,
    `providerVerification/${uid}/identity/large.pdf`,
  );
  const tooLarge = new Uint8Array(10 * 1024 * 1024 + 1);

  await assertFails(
    uploadBytes(largeRef, tooLarge, {
      contentType: 'application/pdf',
    }),
  );
});

test('unsupported content types are rejected', async () => {
  const uid = 'owner-storage-4';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const textRef = ref(
    storage,
    `providerVerification/${uid}/identity/front.txt`,
  );

  await assertFails(
    uploadBytes(textRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'text/plain',
    }),
  );
});

test('owner can delete their own uploaded verification file', async () => {
  const uid = 'owner-storage-5';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const fileRef = ref(
    storage,
    `providerVerification/${uid}/identity/front.png`,
  );

  await assertSucceeds(
    uploadBytes(fileRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertSucceeds(deleteObject(fileRef));
});

test('another user cannot delete uploaded verification file', async () => {
  const ownerUid = 'owner-storage-6';
  const otherUid = 'other-storage-6';
  await seedUser(ownerUid);
  await seedUser(otherUid);

  const ownerStorage = authedStorage(ownerUid);
  const otherStorage = authedStorage(otherUid);
  const ownerRef = ref(
    ownerStorage,
    `providerVerification/${ownerUid}/identity/front.png`,
  );
  const otherRef = ref(
    otherStorage,
    `providerVerification/${ownerUid}/identity/front.png`,
  );

  await assertSucceeds(
    uploadBytes(ownerRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertFails(deleteObject(otherRef));
});

test('unauthenticated users cannot read, upload, or delete verification files', async () => {
  const uid = 'owner-storage-7';
  await seedUser(uid);
  const ownerStorage = authedStorage(uid);
  const publicStorage = unauthedStorage();
  const ownerRef = ref(
    ownerStorage,
    `providerVerification/${uid}/identity/front.png`,
  );
  const publicRef = ref(
    publicStorage,
    `providerVerification/${uid}/identity/front.png`,
  );

  await assertSucceeds(
    uploadBytes(ownerRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertFails(getBytes(publicRef));
  await assertFails(
    uploadBytes(publicRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertFails(deleteObject(publicRef));
});
