import {readFileSync} from 'node:fs';
import test, {after, before} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {doc, setDoc} from 'firebase/firestore';
import {
  deleteObject,
  getBytes,
  ref,
  uploadBytes,
} from 'firebase/storage';

const projectId = 'demo-pettexo';
const bucket = 'demo-pettexo.firebasestorage.app';
const storageRules = readFileSync('../storage.rules', 'utf8');
const firestoreRules = readFileSync('../firestore.rules', 'utf8');

let testEnv;

function authedStorage(uid) {
  return testEnv.authenticatedContext(uid).storage(`gs://${bucket}`);
}

function unauthedStorage() {
  return testEnv.unauthenticatedContext().storage(`gs://${bucket}`);
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

async function seedSupportTicket(ticketId, userId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'supportTickets', ticketId), {
      ticketId,
      userId,
      category: 'technical_issue',
      subject: 'Support ticket',
      initialMessage: 'Need help',
      status: 'awaiting_support',
      customerUnreadCount: 0,
      adminUnreadCount: 1,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastMessageAt: new Date(),
      lastMessagePreview: 'Need help',
      lastMessageSenderType: 'customer',
      contactNumber: '+919999999999',
      attachments: [],
    });
  });
}

async function seedVerification(uid, {status, submissionId, path}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users', uid, 'providerVerification', 'main'),
      {
        userId: uid,
        status,
        submissionId,
        documentFrontPath: path,
        documentBackPath: '',
      },
    );
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
    `providerVerification/${uid}/identity/submission-1/front.png`,
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
    `providerVerification/${uid}/identity/submission-1/front.pdf`,
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
    `providerVerification/${uid}/identity/submission-1/large.pdf`,
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
    `providerVerification/${uid}/identity/submission-1/front.txt`,
  );

  await assertFails(
    uploadBytes(textRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'text/plain',
    }),
  );
});

test('owner can delete an unreferenced verification upload after a failed submission', async () => {
  const uid = 'owner-storage-5';
  await seedUser(uid);
  const storage = authedStorage(uid);
  const fileRef = ref(
    storage,
    `providerVerification/${uid}/identity/submission-orphan/front.png`,
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
    `providerVerification/${ownerUid}/identity/submission-1/front.png`,
  );
  const otherRef = ref(
    otherStorage,
    `providerVerification/${ownerUid}/identity/submission-1/front.png`,
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
    `providerVerification/${uid}/identity/submission-1/front.png`,
  );
  const publicRef = ref(
    publicStorage,
    `providerVerification/${uid}/identity/submission-1/front.png`,
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

for (const status of ['pending', 'approved']) {
  test(`${status} verification evidence cannot be overwritten or deleted by owner`, async () => {
    const uid = `immutable-${status}`;
    const submissionId = `submission-${status}`;
    const path = `providerVerification/${uid}/identity/${submissionId}/front.png`;
    await seedUser(uid);
    const storage = authedStorage(uid);
    const fileRef = ref(storage, path);
    await assertSucceeds(
      uploadBytes(fileRef, Uint8Array.from([1, 2, 3]), {contentType: 'image/png'}),
    );
    await seedVerification(uid, {status, submissionId, path});
    await assertSucceeds(getBytes(fileRef));
    await assertFails(
      uploadBytes(fileRef, Uint8Array.from([4, 5, 6]), {contentType: 'image/png'}),
    );
    await assertFails(deleteObject(fileRef));
  });
}

test('rejected provider can create a new immutable submission version', async () => {
  const uid = 'rejected-resubmission';
  const oldPath = `providerVerification/${uid}/identity/submission-old/front.png`;
  const newPath = `providerVerification/${uid}/identity/submission-new/front.png`;
  await seedUser(uid);
  await seedVerification(uid, {
    status: 'rejected',
    submissionId: 'submission-old',
    path: oldPath,
  });
  await assertSucceeds(
    uploadBytes(ref(authedStorage(uid), newPath), Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
});

test('KYC reads remain owner, support, and super-admin only', async () => {
  const ownerUid = 'kyc-read-owner';
  const otherUid = 'kyc-read-other';
  const supportUid = 'kyc-read-support';
  const financeUid = 'kyc-read-finance';
  const superUid = 'kyc-read-super';
  const path = `providerVerification/${ownerUid}/identity/submission-read/front.png`;
  await seedUser(ownerUid);
  await seedUser(otherUid);
  await seedUser(supportUid, {adminRole: 'customerSupportAdmin'});
  await seedUser(financeUid, {adminRole: 'financeAdmin'});
  await seedUser(superUid, {adminRole: 'superAdmin'});
  await assertSucceeds(
    uploadBytes(ref(authedStorage(ownerUid), path), Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertSucceeds(getBytes(ref(authedStorage(ownerUid), path)));
  await assertSucceeds(getBytes(ref(authedStorage(supportUid), path)));
  await assertSucceeds(getBytes(ref(authedStorage(superUid), path)));
  await assertFails(getBytes(ref(authedStorage(financeUid), path)));
  await assertFails(getBytes(ref(authedStorage(otherUid), path)));
  await assertFails(
    uploadBytes(
      ref(authedStorage(otherUid), path),
      Uint8Array.from([4, 5, 6]),
      {contentType: 'image/png'},
    ),
  );
  await assertFails(deleteObject(ref(authedStorage(otherUid), path)));
});

test('support ticket owner can upload and read their own support attachment', async () => {
  const uid = 'support-storage-owner';
  const ticketId = 'support-ticket-1';
  await seedUser(uid);
  await seedSupportTicket(ticketId, uid);
  const storage = authedStorage(uid);
  const imageRef = ref(storage, `supportTickets/${uid}/${ticketId}/one.jpg`);

  await assertSucceeds(
    uploadBytes(imageRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/jpeg',
    }),
  );
  await assertSucceeds(getBytes(imageRef));
});

test('support admins can read support attachments but finance admins cannot', async () => {
  const ownerUid = 'support-storage-owner-2';
  const supportAdminUid = 'support-storage-admin';
  const financeAdminUid = 'support-storage-finance';
  const ticketId = 'support-ticket-2';
  await seedUser(ownerUid);
  await seedUser(supportAdminUid, {adminRole: 'customerSupportAdmin'});
  await seedUser(financeAdminUid, {adminRole: 'financeAdmin'});
  await seedSupportTicket(ticketId, ownerUid);

  const ownerStorage = authedStorage(ownerUid);
  const supportStorage = authedStorage(supportAdminUid);
  const financeStorage = authedStorage(financeAdminUid);
  const ownerRef = ref(
    ownerStorage,
    `supportTickets/${ownerUid}/${ticketId}/one.jpg`,
  );
  const supportRef = ref(
    supportStorage,
    `supportTickets/${ownerUid}/${ticketId}/one.jpg`,
  );
  const financeRef = ref(
    financeStorage,
    `supportTickets/${ownerUid}/${ticketId}/one.jpg`,
  );

  await assertSucceeds(
    uploadBytes(ownerRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/jpeg',
    }),
  );
  await assertSucceeds(getBytes(supportRef));
  await assertFails(getBytes(financeRef));
});

test('super admin can upload an offer wall creative', async () => {
  const uid = 'offer-wall-super';
  await seedUser(uid, {adminRole: 'superAdmin'});
  const storage = authedStorage(uid);
  const imageRef = ref(storage, 'offerWalls/campaign-1/creative.png');

  await assertSucceeds(
    uploadBytes(imageRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
});

test('finance admin can upload an offer wall creative', async () => {
  const uid = 'offer-wall-finance';
  await seedUser(uid, {adminRole: 'financeAdmin'});
  const storage = authedStorage(uid);
  const imageRef = ref(storage, 'offerWalls/campaign-2/creative.webp');

  await assertSucceeds(
    uploadBytes(imageRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/webp',
    }),
  );
});

test('customer support admin cannot upload an offer wall creative', async () => {
  const uid = 'offer-wall-support';
  await seedUser(uid, {adminRole: 'customerSupportAdmin'});
  const storage = authedStorage(uid);
  const imageRef = ref(storage, 'offerWalls/campaign-3/creative.png');

  await assertFails(
    uploadBytes(imageRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
});

test('normal users and unauthenticated users cannot upload an offer wall creative', async () => {
  const uid = 'offer-wall-normal';
  await seedUser(uid);
  const userStorage = authedStorage(uid);
  const guestStorage = unauthedStorage();
  const userRef = ref(userStorage, 'offerWalls/campaign-4/creative.png');
  const guestRef = ref(guestStorage, 'offerWalls/campaign-4/creative.png');

  await assertFails(
    uploadBytes(userRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertFails(
    uploadBytes(guestRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
});

test('offer wall creatives allow jpeg png and webp but deny non-images', async () => {
  const uid = 'offer-wall-mime';
  await seedUser(uid, {adminRole: 'superAdmin'});
  const storage = authedStorage(uid);

  await assertSucceeds(
    uploadBytes(
      ref(storage, 'offerWalls/campaign-5/creative.jpg'),
      Uint8Array.from([1, 2, 3]),
      {contentType: 'image/jpeg'},
    ),
  );
  await assertSucceeds(
    uploadBytes(
      ref(storage, 'offerWalls/campaign-5/creative.png'),
      Uint8Array.from([1, 2, 3]),
      {contentType: 'image/png'},
    ),
  );
  await assertSucceeds(
    uploadBytes(
      ref(storage, 'offerWalls/campaign-5/creative.webp'),
      Uint8Array.from([1, 2, 3]),
      {contentType: 'image/webp'},
    ),
  );
  await assertFails(
    uploadBytes(
      ref(storage, 'offerWalls/campaign-5/creative.txt'),
      Uint8Array.from([1, 2, 3]),
      {contentType: 'text/plain'},
    ),
  );
});

test('offer wall upload still succeeds when admin clients omit contentType metadata but keep a supported extension', async () => {
  const uid = 'offer-wall-no-metadata';
  await seedUser(uid, {adminRole: 'superAdmin'});
  const storage = authedStorage(uid);
  const imageRef = ref(storage, 'offerWalls/campaign-6/creative.png');

  await assertSucceeds(uploadBytes(imageRef, Uint8Array.from([1, 2, 3])));
});

test('authenticated users can read offer wall creatives but unauthenticated users cannot', async () => {
  const adminUid = 'offer-wall-read-admin';
  const userUid = 'offer-wall-read-user';
  await seedUser(adminUid, {adminRole: 'financeAdmin'});
  await seedUser(userUid);

  const adminStorage = authedStorage(adminUid);
  const userStorage = authedStorage(userUid);
  const guestStorage = unauthedStorage();
  const adminRef = ref(adminStorage, 'offerWalls/campaign-7/creative.png');
  const userRef = ref(userStorage, 'offerWalls/campaign-7/creative.png');
  const guestRef = ref(guestStorage, 'offerWalls/campaign-7/creative.png');

  await assertSucceeds(
    uploadBytes(adminRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/png',
    }),
  );
  await assertSucceeds(getBytes(userRef));
  await assertFails(getBytes(guestRef));
});

test('other users cannot upload or read another user support attachment', async () => {
  const ownerUid = 'support-storage-owner-3';
  const otherUid = 'support-storage-other-3';
  const ticketId = 'support-ticket-3';
  await seedUser(ownerUid);
  await seedUser(otherUid);
  await seedSupportTicket(ticketId, ownerUid);

  const ownerStorage = authedStorage(ownerUid);
  const otherStorage = authedStorage(otherUid);
  const ownerRef = ref(
    ownerStorage,
    `supportTickets/${ownerUid}/${ticketId}/one.jpg`,
  );
  const otherRef = ref(
    otherStorage,
    `supportTickets/${ownerUid}/${ticketId}/one.jpg`,
  );

  await assertSucceeds(
    uploadBytes(ownerRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/jpeg',
    }),
  );
  await assertFails(getBytes(otherRef));
  await assertFails(
    uploadBytes(otherRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'image/jpeg',
    }),
  );
});

test('support attachment uploads reject unsupported files and oversize images', async () => {
  const uid = 'support-storage-owner-4';
  const ticketId = 'support-ticket-4';
  await seedUser(uid);
  await seedSupportTicket(ticketId, uid);
  const storage = authedStorage(uid);
  const textRef = ref(storage, `supportTickets/${uid}/${ticketId}/bad.txt`);
  const largeRef = ref(storage, `supportTickets/${uid}/${ticketId}/big.jpg`);
  const tooLarge = new Uint8Array(5 * 1024 * 1024 + 1);

  await assertFails(
    uploadBytes(textRef, Uint8Array.from([1, 2, 3]), {
      contentType: 'text/plain',
    }),
  );
  await assertFails(
    uploadBytes(largeRef, tooLarge, {
      contentType: 'image/jpeg',
    }),
  );
});
