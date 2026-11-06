/**
 * 退会済みユーザーの残りデータの掃除スクリプト（手動で1回実行する）。
 *
 * 退会時にサーバー上のデータを消す onUserDeleted が本番に未デプロイだった期間
 * （2026-11-06 にデプロイ）に退会したユーザーのデータが残っているため、それを消す。
 * onUserDeleted はデプロイ後に退会したユーザーにしか反応しない。
 *
 * Firebase Auth に存在しない UID を「退会済み」とみなし、onUserDeleted（deleteUserData）と
 * 同じ範囲を削除する。
 *   - Firestore: users/{uid}（サブコレクション含む）、その UID を含む accountLinks、
 *                その UID が発行した linkInvites、safetyAlerts/{uid}
 *   - Storage:   users/{uid}/ 配下の写真
 *
 * 使い方: サービスアカウントの鍵を GOOGLE_APPLICATION_CREDENTIALS に設定し、functions/ で
 *   node cleanup-orphan-data.js <projectId> <bucket> [--apply]
 * --apply を付けない場合は何も削除せず、対象の UID と件数だけを表示する（ドライラン）。
 * 必ず先にドライランで対象を確認すること。
 */
const admin = require("firebase-admin");

const [projectId, bucketName, flag] = process.argv.slice(2);
if (!projectId || !bucketName) {
  console.error(
    "usage: node cleanup-orphan-data.js <projectId> <bucket> [--apply]",
  );
  process.exit(1);
}
const apply = flag === "--apply";
admin.initializeApp({ projectId, storageBucket: bucketName });
const db = admin.firestore();
const bucket = admin.storage().bucket();

// 対象が多すぎるときは、Auth の取得失敗など設定の誤りを疑って止める
const MAX_ORPHAN_RATIO = 0.5;

async function listAuthUids() {
  const uids = new Set();
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    page.users.forEach((u) => uids.add(u.uid));
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

/** Storage の users/{uid}/ にファイルがある UID の一覧 */
async function listStorageUids() {
  const uids = new Set();
  const [files] = await bucket.getFiles({ prefix: "users/" });
  for (const file of files) {
    const uid = file.name.split("/")[1];
    if (uid) uids.add(uid);
  }
  return uids;
}

(async () => {
  const authUids = await listAuthUids();
  console.log(`Auth のユーザー: ${authUids.size}`);
  if (authUids.size === 0) {
    console.error("Auth のユーザーが0件です。プロジェクトの指定を確認してください。");
    process.exit(1);
  }

  // フィールドの無い（サブコレクションだけ残った）ドキュメントも拾うため listDocuments を使う
  const userRefs = await db.collection("users").listDocuments();
  const storageUids = await listStorageUids();
  const safetyAlertRefs = await db.collection("safetyAlerts").listDocuments();

  const candidates = new Set([
    ...userRefs.map((r) => r.id),
    ...storageUids,
    ...safetyAlertRefs.map((r) => r.id),
  ]);
  const orphanUids = [...candidates].filter((uid) => !authUids.has(uid));

  const linkSnap = await db.collection("accountLinks").get();
  const orphanLinks = linkSnap.docs.filter((d) =>
    (d.data().uids ?? []).some((u) => !authUids.has(u)),
  );
  const inviteSnap = await db.collection("linkInvites").get();
  const orphanInvites = inviteSnap.docs.filter(
    (d) => !authUids.has(d.data().fromUid),
  );

  console.log(`退会済みとみなす UID: ${orphanUids.length}`);
  for (const uid of orphanUids) {
    const flags = [
      userRefs.some((r) => r.id === uid) ? "users" : null,
      storageUids.has(uid) ? "storage" : null,
      safetyAlertRefs.some((r) => r.id === uid) ? "safetyAlerts" : null,
    ].filter(Boolean);
    console.log(`  ${uid}  (${flags.join(", ")})`);
  }
  console.log(`削除対象の連携(accountLinks): ${orphanLinks.length}`);
  console.log(`削除対象の招待(linkInvites): ${orphanInvites.length}`);

  const ratio = orphanUids.length / (orphanUids.length + authUids.size);
  if (ratio > MAX_ORPHAN_RATIO) {
    console.error(
      `対象が全体の ${Math.round(ratio * 100)}% あります。設定の誤りの可能性があるため中止します。`,
    );
    process.exit(1);
  }

  if (!apply) {
    console.log("ドライランのため削除していません。内容を確認して --apply を付けて再実行してください。");
    return;
  }

  const failures = [];
  const run = async (label, task) => {
    try {
      await task();
    } catch (e) {
      console.error(`${label} の削除に失敗しました: ${e}`);
      failures.push(label);
    }
  };

  for (const link of orphanLinks) {
    await run(`accountLinks/${link.id}`, () => link.ref.delete());
  }
  for (const invite of orphanInvites) {
    await run(`linkInvites/${invite.id}`, () => invite.ref.delete());
  }
  for (const uid of orphanUids) {
    await run(`users/${uid}`, () =>
      db.recursiveDelete(db.collection("users").doc(uid)),
    );
    await run(`safetyAlerts/${uid}`, () =>
      db.collection("safetyAlerts").doc(uid).delete(),
    );
    await run(`storage users/${uid}/`, () =>
      bucket.deleteFiles({ prefix: `users/${uid}/` }),
    );
  }

  if (failures.length > 0) {
    console.error(`失敗: ${failures.length}件。もう一度実行すると残りを削除します。`);
    process.exit(1);
  }
  console.log("削除が完了しました。");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
