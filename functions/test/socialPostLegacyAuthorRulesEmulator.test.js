const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-legacy-post-author-rules"});
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
} = require("firebase/firestore");

/*
 * Phase 3C-2: block checks on social posts must resolve the post author and
 * must not fail closed when a post has no author field.
 *
 * Users: user-b is the post author; user-b has blocked user-a; user-c has no
 * block with anyone. Writes use the build-23 (1.0.4+23, ff9da9f) transaction
 * shapes from lib/features/social/data/social_post_repository.dart.
 */

const enabled = firebaseEmulator.enabled;
let environment;

const POSTS = {
  // (a) canonical post written by every app version.
  withAuthor: {authorId: "user-b"},
  // (b) author-like legacy field. No app version ever wrote one (the create rule
  // has required authorId since the first socialPosts rules), so it is not
  // used to resolve the author: the post behaves like (c).
  legacyUserIdOnly: {userId: "user-b"},
  // (c) no author field at all.
  noAuthor: {},
};

function postData(id, authorFields) {
  return {
    id,
    ...authorFields,
    caption: "Post",
    visibilityStatus: "visible",
    moderationStatus: "approved",
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
    reportCount: 0,
  };
}

test.before(async () => {
  if (!enabled) return;
  environment = await initializeTestEnvironment({
    projectId: "demo-legacy-post-author-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    const {setDoc} = require("firebase/firestore");
    for (const uid of ["user-a", "user-b", "user-c"]) {
      await setDoc(doc(firestore, "users", uid), {uid, accountStatus: "active"});
    }
    await setDoc(doc(firestore, "userBlocks", "user-b_user-a"), {
      ownerUserId: "user-b",
      blockedUserId: "user-a",
      createdAt: new Date(),
    });
    for (const [id, fields] of Object.entries(POSTS)) {
      await setDoc(doc(firestore, "socialPosts", id), postData(id, fields));
    }
  });
});

test.after(async () => environment?.cleanup());

function client(uid) {
  return environment.authenticatedContext(uid).firestore();
}

/** Build-23 toggleLike (like branch): create likes/{uid} and likeCount + 1 in one transaction. */
function likeAsBuild23(uid, postId) {
  const firestore = client(uid);
  return runTransaction(firestore, async (transaction) => {
    const postRef = doc(firestore, "socialPosts", postId);
    const post = await transaction.get(postRef);
    transaction.set(doc(firestore, `socialPosts/${postId}/likes/${uid}`), {
      userId: uid,
      createdAt: serverTimestamp(),
    });
    transaction.update(postRef, {likeCount: (post.data().likeCount ?? 0) + 1});
  });
}

/** Build-23 toggleLike (unlike branch). */
function unlikeAsBuild23(uid, postId) {
  const firestore = client(uid);
  return runTransaction(firestore, async (transaction) => {
    const postRef = doc(firestore, "socialPosts", postId);
    const post = await transaction.get(postRef);
    transaction.delete(doc(firestore, `socialPosts/${postId}/likes/${uid}`));
    transaction.update(postRef, {likeCount: Math.max(0, (post.data().likeCount ?? 0) - 1)});
  });
}

/** Build-23 addComment: parentPostAuthorId = trimmed post authorId, or '' when absent. */
function commentAsBuild23(uid, postId, commentId) {
  const firestore = client(uid);
  return runTransaction(firestore, async (transaction) => {
    const postRef = doc(firestore, "socialPosts", postId);
    const post = await transaction.get(postRef);
    const postData = post.data();
    transaction.set(doc(firestore, `socialPosts/${postId}/comments/${commentId}`), {
      id: commentId,
      postId,
      authorId: uid,
      authorDisplayName: uid,
      authorUsername: uid,
      authorPhotoUrl: "",
      parentPostAuthorId: typeof postData.authorId === "string" ? postData.authorId.trim() : "",
      parentPostPreview: "Post",
      text: "hello",
      likeCount: 0,
      reportCount: 0,
      visibilityStatus: "visible",
      moderationStatus: "approved",
      moderationReason: "",
      moderatedBy: "",
      moderatedAt: null,
      lastReportedAt: null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.update(postRef, {commentCount: (postData.commentCount ?? 0) + 1});
  });
}

/** Build-23 incrementShareCount. */
function shareAsBuild23(uid, postId) {
  const firestore = client(uid);
  return runTransaction(firestore, async (transaction) => {
    const postRef = doc(firestore, "socialPosts", postId);
    const post = await transaction.get(postRef);
    transaction.update(postRef, {shareCount: (post.data().shareCount ?? 0) + 1});
  });
}

const CASES = [
  {post: "withAuthor", blockedOutcome: "DENY"},
  {post: "legacyUserIdOnly", blockedOutcome: "ALLOW"},
  {post: "noAuthor", blockedOutcome: "ALLOW"},
];

for (const {post, blockedOutcome} of CASES) {
  test(`${post}: like, comment and share ALLOWED without a block (user-c)`, {skip: !enabled}, async () => {
    await assertSucceeds(likeAsBuild23("user-c", post));
    await assertSucceeds(commentAsBuild23("user-c", post, `c-${post}`));
    await assertSucceeds(shareAsBuild23("user-c", post));
    await assertSucceeds(unlikeAsBuild23("user-c", post));
  });

  test(`${post}: like, comment and share ${blockedOutcome} with a block between commenter and resolved author (user-a)`,
    {skip: !enabled}, async () => {
      const expect = blockedOutcome === "DENY" ? assertFails : assertSucceeds;
      await expect(likeAsBuild23("user-a", post));
      await expect(commentAsBuild23("user-a", post, `a-${post}`));
      await expect(shareAsBuild23("user-a", post));
    });
}

test("comment create still requires parentPostAuthorId to match the resolved author", {skip: !enabled}, async () => {
  const firestore = client("user-c");
  const spoof = (postId, parentPostAuthorId, commentId) => runTransaction(firestore, async (transaction) => {
    const postRef = doc(firestore, "socialPosts", postId);
    const post = await transaction.get(postRef);
    transaction.set(doc(firestore, `socialPosts/${postId}/comments/${commentId}`), {
      id: commentId, postId, authorId: "user-c", authorDisplayName: "c", authorUsername: "c",
      authorPhotoUrl: "", parentPostAuthorId, parentPostPreview: "Post", text: "x", likeCount: 0,
      reportCount: 0, visibilityStatus: "visible", moderationStatus: "approved", moderationReason: "",
      moderatedBy: "", moderatedAt: null, lastReportedAt: null,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    transaction.update(postRef, {commentCount: (post.data().commentCount ?? 0) + 1});
  });
  // Lying about the author of a post that has one is still refused.
  await assertFails(spoof("withAuthor", "", "spoof-1"));
  await assertFails(spoof("withAuthor", "user-x", "spoof-2"));
  // For an authorless post the resolved author is '', so a made-up author is refused.
  await assertFails(spoof("noAuthor", "user-b", "spoof-3"));
});

test("the reverse block direction is also enforced for posts with an author", {skip: !enabled}, async () => {
  // user-b (author) blocked user-a; user-b interacting with its own post is unaffected,
  // and user-a's writes were denied above. Here: a block owned by the commenter.
  await environment.withSecurityRulesDisabled(async (context) => {
    const {setDoc} = require("firebase/firestore");
    await setDoc(doc(context.firestore(), "userBlocks", "user-c_user-b"), {
      ownerUserId: "user-c", blockedUserId: "user-b", createdAt: new Date(),
    });
  });
  try {
    await assertFails(likeAsBuild23("user-c", "withAuthor"));
    await assertSucceeds(likeAsBuild23("user-c", "noAuthor"));
  } finally {
    await environment.withSecurityRulesDisabled(async (context) => {
      const {deleteDoc} = require("firebase/firestore");
      await deleteDoc(doc(context.firestore(), "userBlocks", "user-c_user-b"));
    });
  }
  await environment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await getDoc(doc(context.firestore(), "socialPosts", "noAuthor"));
    assert.equal(snapshot.data().likeCount, 2); // user-a (allowed: no author) + user-c
  });
});
