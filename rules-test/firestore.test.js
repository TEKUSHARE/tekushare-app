const { test, before, after, beforeEach } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc, getDoc, getDocs, collection, setDoc, writeBatch, Timestamp, serverTimestamp,
} = require("firebase/firestore");

const future = () => Timestamp.fromDate(new Date(Date.now() + 86400000));

test("更新案内は未ログインでも単一取得でき、一覧取得・変更はできない", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(db, "appUpdates/prod_android")));
  await assertFails(getDocs(collection(db, "appUpdates")));
  await assertFails(setDoc(doc(db, "appUpdates/prod_android"), { latestBuild: 99 }));
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(alice, "appUpdates/prod_android"), { latestBuild: 99 }));
});
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-tekushare",
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, "../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "linkInvites/t1"), {
      fromUid: "alice", used: false, expiresAt: future(),
    });
    await setDoc(doc(db, "users/alice"), { displayName: "A" });
    await setDoc(doc(db, "users/bob"), { displayName: "B" });
    await setDoc(doc(db, "users/alice/private/fcm"), { fcmToken: "x" });
  });
});

const on = { wantToGo: true, visited: true };
const linkData = (token = "t1", shares = { alice: on, bob: on }) => ({
  uids: ["alice", "bob"], inviteToken: token, createdAt: Timestamp.now(), shares,
});

test("招待は list 不可・get 可", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  await assertFails(getDocs(collection(db, "linkInvites")));
  await assertSucceeds(getDoc(doc(db, "linkInvites/t1")));
});

test("users は list 不可・get 可、private は本人のみ", async () => {
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDocs(collection(bob, "users")));
  await assertSucceeds(getDoc(doc(bob, "users/alice")));
  await assertFails(getDoc(doc(bob, "users/alice/private/fcm")));
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(getDoc(doc(alice, "users/alice/private/fcm")));
});

test("連携作成は招待の使用済み化とセットなら成功", async () => {
  const db = env.authenticatedContext("bob").firestore();
  const b = writeBatch(db);
  b.set(doc(db, "accountLinks/alice_bob"), linkData());
  b.update(doc(db, "linkInvites/t1"), { used: true });
  await assertSucceeds(b.commit());
});

test("招待を使用済みにしない連携作成は失敗", async () => {
  const db = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(db, "accountLinks/alice_bob"), linkData()));
});

test("期限切れ招待・不正な linkId は失敗", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "linkInvites/old"), {
      fromUid: "alice", used: false,
      expiresAt: Timestamp.fromDate(new Date(Date.now() - 1000)),
    });
  });
  const db = env.authenticatedContext("bob").firestore();
  const b1 = writeBatch(db);
  b1.set(doc(db, "accountLinks/alice_bob"), linkData("old"));
  b1.update(doc(db, "linkInvites/old"), { used: true });
  await assertFails(b1.commit());

  const b2 = writeBatch(db);
  b2.set(doc(db, "accountLinks/bob_alice"), linkData());
  b2.update(doc(db, "linkInvites/t1"), { used: true });
  await assertFails(b2.commit());
});

test("contacts は本人のみ。連携相手・他人は読めない", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice/contacts/c1"), { name: "n", phone: "090" });
    await setDoc(doc(db, "accountLinks/alice_bob"), { uids: ["alice", "bob"] });
  });
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(getDoc(doc(alice, "users/alice/contacts/c1")));
  for (const uid of ["bob", "mallory"]) {
    const db = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(db, "users/alice/contacts/c1")));
    await assertFails(getDocs(collection(db, "users/alice/contacts")));
    await assertFails(setDoc(doc(db, "users/alice/contacts/c2"), { name: "x", phone: "1" }));
  }
});

test("users への書き込みは許可フィールド・型のみ", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  const mallory = env.authenticatedContext("mallory").firestore();
  await assertSucceeds(setDoc(doc(alice, "users/alice"),
    { displayName: "A2", shareVisited: false, updatedAt: Timestamp.now() }, { merge: true }));
  await assertFails(setDoc(doc(alice, "users/alice"), { isAdmin: true }, { merge: true }));
  await assertFails(setDoc(doc(alice, "users/alice"), { shareVisited: "yes" }, { merge: true }));
  await assertFails(setDoc(doc(alice, "users/alice"), { displayName: "x".repeat(51) }, { merge: true }));
  await assertFails(setDoc(doc(mallory, "users/alice"), { displayName: "hacked" }, { merge: true }));
});

test("旧 fcmToken の削除は許可される", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), { displayName: "A", fcmToken: "old" });
  });
  const alice = env.authenticatedContext("alice").firestore();
  const { deleteField } = require("firebase/firestore");
  await assertSucceeds(setDoc(doc(alice, "users/alice"), { fcmToken: deleteField() }, { merge: true }));
});

test("共有OFFのステータスは一覧取得できない", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { displayName: "A", shareVisited: false });
    await setDoc(doc(db, "users/alice/spots/s1"), { status: "wantToGo", title: "a" });
    await setDoc(doc(db, "users/alice/spots/s2"), { status: "visited", title: "b" });
    await setDoc(doc(db, "accountLinks/alice_bob"), { uids: ["alice", "bob"] });
  });
  const { query, where } = require("firebase/firestore");
  const spots = (uid) => collection(env.authenticatedContext(uid).firestore(), "users/alice/spots");
  const bob = "bob";
  await assertSucceeds(getDocs(query(spots(bob), where("status", "==", "wantToGo"))));
  await assertFails(getDocs(query(spots(bob), where("status", "==", "visited"))));
  await assertFails(getDocs(spots(bob)));
  await assertFails(getDocs(query(spots("mallory"), where("status", "==", "wantToGo"))));
});

test("deletionJobs はクライアントから読み書きできない", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(getDoc(doc(alice, "deletionJobs/alice")));
  await assertFails(setDoc(doc(alice, "deletionJobs/alice"), { status: "completed" }));
});

test("連携作成時の shares が users の設定と違えば失敗", async () => {
  const db = env.authenticatedContext("bob").firestore();
  const b = writeBatch(db);
  b.set(doc(db, "accountLinks/alice_bob"),
    linkData("t1", { alice: on, bob: { wantToGo: false, visited: true } }));
  b.update(doc(db, "linkInvites/t1"), { used: true });
  await assertFails(b.commit());
});

test("shares は自分の分だけ、users の設定と同じバッチで更新できる", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "accountLinks/alice_bob"),
      { uids: ["alice", "bob"], shares: { alice: on, bob: on } });
  });
  const alice = env.authenticatedContext("alice").firestore();
  const off = { wantToGo: false, visited: false };
  const batch = writeBatch(alice);
  batch.set(doc(alice, "users/alice"), { shareWantToGo: false, shareVisited: false }, { merge: true });
  batch.update(doc(alice, "accountLinks/alice_bob"), { "shares.alice": off });
  await assertSucceeds(batch.commit());

  // users と食い違う更新・相手の分の更新は失敗
  const mismatch = writeBatch(alice);
  mismatch.update(doc(alice, "accountLinks/alice_bob"), { "shares.alice": on });
  await assertFails(mismatch.commit());
  const other = writeBatch(alice);
  other.update(doc(alice, "accountLinks/alice_bob"), { "shares.bob": off });
  await assertFails(other.commit());
  const mallory = env.authenticatedContext("mallory").firestore();
  await assertFails(setDoc(doc(mallory, "accountLinks/alice_bob"), { "shares": { alice: on, bob: on } }, { merge: true }));
});

test("安否通知の依頼は本人だけがサーバー時刻で作成・取得でき、他人はできない", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(setDoc(doc(alice, "safetyAlerts/alice"), { requestedAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(alice, "safetyAlerts/alice")));

  const mallory = env.authenticatedContext("mallory").firestore();
  await assertFails(getDoc(doc(mallory, "safetyAlerts/alice")));
  await assertFails(setDoc(doc(mallory, "safetyAlerts/alice"), { requestedAt: serverTimestamp() }));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(anon, "safetyAlerts/alice"), { requestedAt: serverTimestamp() }));
});

test("安否通知の依頼はクライアント時刻や結果(result)を書き込めない", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(alice, "safetyAlerts/alice"), { requestedAt: Timestamp.now() }));
  await assertFails(setDoc(doc(alice, "safetyAlerts/alice"), {
    requestedAt: serverTimestamp(), result: { sentCount: 1 },
  }));
});

test("安否通知の再依頼は前回から5分経過後だけ受け付け、結果は変更できない", async () => {
  const minutesAgo = (m) => Timestamp.fromDate(new Date(Date.now() - m * 60000));
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "safetyAlerts/alice"), {
      requestedAt: minutesAgo(1), result: { requestedAt: minutesAgo(1), sentCount: 1 },
    });
    await setDoc(doc(db, "safetyAlerts/bob"), {
      requestedAt: minutesAgo(6), result: { requestedAt: minutesAgo(6), sentCount: 1 },
    });
  });

  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(alice, "safetyAlerts/alice"), { requestedAt: serverTimestamp() }, { merge: true }));

  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(bob, "safetyAlerts/bob"), {
    requestedAt: serverTimestamp(), result: { sentCount: 99 },
  }, { merge: true }));
  await assertSucceeds(setDoc(doc(bob, "safetyAlerts/bob"), { requestedAt: serverTimestamp() }, { merge: true }));
});
