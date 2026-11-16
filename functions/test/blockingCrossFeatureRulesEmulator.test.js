const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-blocking-cross-feature-rules"});
const test = require("node:test");
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
  serverTimestamp,
  setDoc,
  writeBatch,
} = require("firebase/firestore");

const enabled = firebaseEmulator.enabled;
let environment;

function commentPayload() {
  return {
    id: "comment-a",
    postId: "post-b",
    authorId: "user-a",
    authorDisplayName: "User A",
    authorUsername: "user-a",
    authorPhotoUrl: "",
    parentPostAuthorId: "user-b",
    parentPostPreview: "Post",
    text: "blocked comment",
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
  };
}

test.before(async () => {
  if (!enabled) return;
  environment = await initializeTestEnvironment({
    projectId: "demo-blocking-cross-feature-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    for (const uid of ["user-a", "user-b", "user-c"]) {
      await setDoc(doc(firestore, "users", uid), {uid, accountStatus: "active"});
    }
    await setDoc(doc(firestore, "userBlocks", "user-b_user-a"), {
      ownerUserId: "user-b",
      blockedUserId: "user-a",
      createdAt: new Date(),
    });
    await setDoc(doc(firestore, "socialPosts", "post-b"), {
      id: "post-b",
      authorId: "user-b",
      visibilityStatus: "visible",
      moderationStatus: "approved",
      likeCount: 0,
      commentCount: 0,
      shareCount: 0,
      reportCount: 0,
    });
    await setDoc(doc(firestore, "chats", "chat_user-a_user-b"), {
      chatType: "directUser",
      customerId: "user-a",
      providerId: "user-b",
      participantIds: ["user-a", "user-b"],
      status: "active",
    });
  });
});

test.after(async () => environment?.cleanup());

test("either block direction denies new direct follow, like, and comment writes", {
  skip: !enabled,
}, async () => {
  const a = environment.authenticatedContext("user-a").firestore();
  const b = environment.authenticatedContext("user-b").firestore();

  await assertFails(setDoc(doc(a, "follows", "user-a_user-b"), {
    followerId: "user-a", followeeId: "user-b", createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(b, "follows", "user-b_user-a"), {
    followerId: "user-b", followeeId: "user-a", createdAt: serverTimestamp(),
  }));

  const likeBatch = writeBatch(a);
  likeBatch.set(doc(a, "socialPosts/post-b/likes/user-a"), {
    userId: "user-a", createdAt: serverTimestamp(),
  });
  likeBatch.update(doc(a, "socialPosts/post-b"), {likeCount: 1});
  await assertFails(likeBatch.commit());

  const commentBatch = writeBatch(a);
  commentBatch.set(doc(a, "socialPosts/post-b/comments/comment-a"), commentPayload());
  commentBatch.update(doc(a, "socialPosts/post-b"), {commentCount: 1});
  await assertFails(commentBatch.commit());
});

test("unblocked interaction succeeds and blocked reporting remains available", {
  skip: !enabled,
}, async () => {
  const c = environment.authenticatedContext("user-c").firestore();
  await assertSucceeds(setDoc(doc(c, "follows", "user-c_user-b"), {
    followerId: "user-c", followeeId: "user-b", createdAt: serverTimestamp(),
  }));

  const a = environment.authenticatedContext("user-a").firestore();
  const reportBatch = writeBatch(a);
  reportBatch.set(doc(a, "socialPosts/post-b/reports/user-a"), {
    reporterId: "user-a",
    reason: "harassment",
    createdAt: serverTimestamp(),
  });
  reportBatch.update(doc(a, "socialPosts/post-b"), {
    reportCount: 1,
    lastReportedAt: serverTimestamp(),
  });
  await assertSucceeds(reportBatch.commit());
});

test("historical public content, profile, and chat remain readable for evidence", {
  skip: !enabled,
}, async () => {
  const a = environment.authenticatedContext("user-a").firestore();
  await assertSucceeds(getDoc(doc(a, "users/user-b")));
  await assertSucceeds(getDoc(doc(a, "socialPosts/post-b")));
  await assertSucceeds(getDoc(doc(a, "chats/chat_user-a_user-b")));
});
