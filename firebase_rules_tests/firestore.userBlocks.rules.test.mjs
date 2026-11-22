// Phase 3C-8: userBlocks point reads and the like/comment/share/service client
// sequences of app 1.0.4 (build 23) and 1.0.5 (build 24).
//
// 1.0.5 probes userBlocks/{me}_{other} and userBlocks/{other}_{me} by ID
// (lib/features/blocking/data/blocked_relationship_repository.dart
// isEffectivelyBlocked). Before Phase 3C-8 the rules denied a get on a missing
// doc, which broke like, comment, share and service open in 1.0.5.
//
// Uses its own project ID so it can run in parallel with
// firestore.rules.test.mjs on the same emulator.
import {readFileSync} from 'node:fs';
import test, {after, before, beforeEach} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const projectId = 'demo-pettexo-userblocks';
const firestoreRules = readFileSync('../firestore.rules', 'utf8');

const ME = 'alice';
const OTHER = 'bob';
const THIRD = 'carol';

let testEnv;

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
  await seed(async (db) => {
    for (const uid of [ME, OTHER, THIRD]) {
      await setDoc(doc(db, 'users', uid), {
        uid,
        username: uid,
        usernameLowercase: uid,
        displayName: uid,
        name: uid,
        role: 'petParent',
        accountStatus: 'active',
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await setDoc(doc(db, 'userPrivate', uid), {uid});
    }
    const post = {
      visibilityStatus: 'visible',
      moderationStatus: 'approved',
      likeCount: 0,
      commentCount: 0,
      shareCount: 0,
      reportCount: 0,
      caption: 'hello',
      createdAt: new Date(),
    };
    await setDoc(doc(db, 'socialPosts', 'othersPost'), {...post, authorId: OTHER});
    await setDoc(doc(db, 'socialPosts', 'ownPost'), {...post, authorId: ME});
    await setDoc(doc(db, 'socialPosts', 'legacyPost'), {...post}); // no authorId
    await setDoc(doc(db, 'follows', `${ME}_${OTHER}`), {
      followerId: ME,
      followeeId: OTHER,
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'services', 'othersService'), {
      ownerUserId: OTHER,
      title: 'Dog Walking',
      status: 'active',
      isActive: true,
      isDeleted: false,
      isPaused: false,
      isVisibleToMarketplace: true,
      createdAt: new Date(),
    });
  });
});

function seed(fn) {
  return testEnv.withSecurityRulesDisabled((context) => fn(context.firestore()));
}

function db(uid = ME) {
  return testEnv.authenticatedContext(uid).firestore();
}

function seedBlock(owner, blocked) {
  return seed((sdb) => setDoc(doc(sdb, 'userBlocks', `${owner}_${blocked}`), {
    ownerUserId: owner,
    blockedUserId: blocked,
    createdAt: new Date(),
  }));
}

function blockDoc(fdb, id) {
  return doc(fdb, 'userBlocks', id);
}

// ---------------------------------------------------------------------------
// userBlocks reads and writes
// ---------------------------------------------------------------------------

test('userBlocks: a party can get a missing {me}_{other} and {other}_{me}', async () => {
  const fdb = db(ME);
  await assertSucceeds(getDoc(blockDoc(fdb, `${ME}_${OTHER}`)));
  await assertSucceeds(getDoc(blockDoc(fdb, `${OTHER}_${ME}`)));
});

test('userBlocks: a third party cannot get a missing or an existing pair doc', async () => {
  const fdb = db(THIRD);
  await assertFails(getDoc(blockDoc(fdb, `${ME}_${OTHER}`)));
  await assertFails(getDoc(blockDoc(fdb, `${OTHER}_${ME}`)));
  await seedBlock(ME, OTHER);
  await assertFails(getDoc(blockDoc(fdb, `${ME}_${OTHER}`)));
});

test('userBlocks: malformed pair ids are denied', async () => {
  const fdb = db(ME);
  for (const id of [
    `${ME}_${OTHER}_${THIRD}`,
    `x${ME}_${OTHER}`,
    `${ME}_`,
    `_${ME}`,
    `${ME}`,
  ]) {
    await assertFails(getDoc(blockDoc(fdb, id)));
  }
});

test('userBlocks: a missing self-pair {me}_{me} is readable by me (expected, harmless)', async () => {
  // The server never writes self-pairs, so this reveals nothing. Documented so
  // a future tightening is a deliberate choice.
  await assertSucceeds(getDoc(blockDoc(db(ME), `${ME}_${ME}`)));
  await assertFails(getDoc(blockDoc(db(OTHER), `${ME}_${ME}`)));
});

test('userBlocks: owner and blocked user can get an existing doc', async () => {
  await seedBlock(ME, OTHER);
  await assertSucceeds(getDoc(blockDoc(db(ME), `${ME}_${OTHER}`)));
  await assertSucceeds(getDoc(blockDoc(db(OTHER), `${ME}_${OTHER}`)));
});

test('userBlocks: unfiltered list denied, owner/blocked filtered lists allowed', async () => {
  await seedBlock(ME, OTHER);
  await seedBlock(THIRD, ME);
  const fdb = db(ME);
  await assertFails(getDocs(collection(fdb, 'userBlocks')));
  await assertSucceeds(getDocs(query(collection(fdb, 'userBlocks'), where('ownerUserId', '==', ME))));
  await assertSucceeds(getDocs(query(collection(fdb, 'userBlocks'), where('blockedUserId', '==', ME))));
});

test('userBlocks: client writes stay denied', async () => {
  const fdb = db(ME);
  await assertFails(setDoc(blockDoc(fdb, `${ME}_${OTHER}`), {
    ownerUserId: ME,
    blockedUserId: OTHER,
    createdAt: serverTimestamp(),
  }));
  await seedBlock(ME, OTHER);
  await assertFails(updateDoc(blockDoc(fdb, `${ME}_${OTHER}`), {blockedUserId: THIRD}));
  await assertFails(deleteDoc(blockDoc(fdb, `${ME}_${OTHER}`)));
});

// ---------------------------------------------------------------------------
// Client sequences, mirroring lib/features/social/data/social_post_repository.dart
// ---------------------------------------------------------------------------

// BlockedRelationshipRepository.isEffectivelyBlocked (1.0.5 only).
async function isEffectivelyBlocked(fdb, other) {
  if (!other || other === ME) return false;
  const snaps = await Promise.all([
    getDoc(blockDoc(fdb, `${ME}_${other}`)),
    getDoc(blockDoc(fdb, `${other}_${ME}`)),
  ]);
  return snaps.some((snap) => snap.exists());
}

// BlockedRelationshipRepository.loadEffectiveBlockedUserIds (1.0.5 only).
async function loadEffectiveBlockedUserIds(fdb) {
  await getDocs(query(collection(fdb, 'userBlocks'), where('ownerUserId', '==', ME)));
  await getDocs(query(collection(fdb, 'userBlocks'), where('blockedUserId', '==', ME)));
}

// ProfileRepository.fetchPublicVisibilityByIds.
async function fetchPublicVisibility(fdb, version, ids) {
  if (version === '1.0.5') await loadEffectiveBlockedUserIds(fdb);
  await getDocs(query(collection(fdb, 'users'), where('uid', 'in', ids)));
}

// SocialPostRepository._isUserVisible. Like the app, an empty authorId is
// rejected client-side before any further read, so the sequence stops there.
async function isUserVisible(fdb, version, userId) {
  if (!userId) return false;
  if (version === '1.0.5' && await isEffectivelyBlocked(fdb, userId)) return false;
  await fetchPublicVisibility(fdb, version, [userId]);
  return true;
}

async function likeSequence(fdb, version, postId) {
  const postRef = doc(fdb, 'socialPosts', postId);
  const likeRef = doc(fdb, 'socialPosts', postId, 'likes', ME);
  await runTransaction(fdb, async (tx) => {
    const post = (await tx.get(postRef)).data();
    await isUserVisible(fdb, version, (post.authorId ?? '').trim());
    const like = await tx.get(likeRef);
    if (like.exists()) {
      tx.delete(likeRef);
      tx.update(postRef, {likeCount: Math.max(0, post.likeCount - 1)});
    } else {
      tx.set(likeRef, {userId: ME, createdAt: serverTimestamp()});
      tx.update(postRef, {likeCount: post.likeCount + 1});
    }
  });
}

async function commentSequence(fdb, version, postId) {
  await getDoc(doc(fdb, 'users', ME));
  await getDoc(doc(fdb, 'userPrivate', ME));
  const postRef = doc(fdb, 'socialPosts', postId);
  const commentRef = doc(collection(fdb, 'socialPosts', postId, 'comments'));
  await runTransaction(fdb, async (tx) => {
    const post = (await tx.get(postRef)).data();
    const authorId = (post.authorId ?? '').trim();
    await isUserVisible(fdb, version, authorId);
    tx.set(commentRef, {
      id: commentRef.id,
      postId,
      authorId: ME,
      authorDisplayName: ME,
      authorUsername: ME,
      authorPhotoUrl: '',
      parentPostAuthorId: authorId,
      parentPostPreview: 'hello',
      text: 'nice',
      likeCount: 0,
      reportCount: 0,
      visibilityStatus: 'visible',
      moderationStatus: 'approved',
      moderationReason: '',
      moderatedBy: '',
      moderatedAt: null,
      lastReportedAt: null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    tx.update(postRef, {commentCount: post.commentCount + 1});
  });
  await getDoc(commentRef);
}

async function shareSequence(fdb, version, postId) {
  const postRef = doc(fdb, 'socialPosts', postId);
  await runTransaction(fdb, async (tx) => {
    const post = (await tx.get(postRef)).data();
    await isUserVisible(fdb, version, (post.authorId ?? '').trim());
    tx.update(postRef, {shareCount: post.shareCount + 1});
  });
}

for (const version of ['1.0.4', '1.0.5']) {
  for (const postId of ['othersPost', 'ownPost', 'legacyPost']) {
    test(`client ${version}: like, unlike, comment and share on ${postId} are allowed`, async () => {
      const fdb = db(ME);
      await assertSucceeds(likeSequence(fdb, version, postId));   // like
      await assertSucceeds(likeSequence(fdb, version, postId));   // unlike
      await assertSucceeds(commentSequence(fdb, version, postId));
      await assertSucceeds(shareSequence(fdb, version, postId));
    });
  }
}

for (const [owner, blocked] of [[ME, OTHER], [OTHER, ME]]) {
  test(`client: with block ${owner}_${blocked}, like create and comment create are denied`, async () => {
    await seedBlock(owner, blocked);
    const fdb = db(ME);
    // The 1.0.5 probe can read the existing block and its missing twin.
    await assertSucceeds(isEffectivelyBlocked(fdb, OTHER));
    // The writes themselves are refused server-side regardless of the client.
    await assertFails(setDoc(doc(fdb, 'socialPosts', 'othersPost', 'likes', ME), {
      userId: ME,
      createdAt: serverTimestamp(),
    }));
    const commentRef = doc(collection(fdb, 'socialPosts', 'othersPost', 'comments'));
    await assertFails(setDoc(commentRef, {
      id: commentRef.id,
      postId: 'othersPost',
      authorId: ME,
      authorDisplayName: ME,
      authorUsername: ME,
      authorPhotoUrl: '',
      parentPostAuthorId: OTHER,
      parentPostPreview: 'hello',
      text: 'nice',
      likeCount: 0,
      reportCount: 0,
      visibilityStatus: 'visible',
      moderationStatus: 'approved',
      moderationReason: '',
      moderatedBy: '',
      moderatedAt: null,
      lastReportedAt: null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }));
  });
}

// ServicesRepository.fetchServiceById (1.0.5) for a non-owner: service get,
// isEffectivelyBlocked(owner), then _isOwnerVisible -> isEffectivelyBlocked
// again and fetchPublicVisibilityByIds.
test('client 1.0.5: fetchServiceById for a non-owner is allowed', async () => {
  const fdb = db(ME);
  await assertSucceeds((async () => {
    const snap = await getDoc(doc(fdb, 'services', 'othersService'));
    const ownerUserId = snap.data().ownerUserId;
    await isEffectivelyBlocked(fdb, ownerUserId);
    await isEffectivelyBlocked(fdb, ownerUserId);
    await fetchPublicVisibility(fdb, '1.0.5', [ownerUserId]);
  })());
});
