import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/** 自分と連携しているアカウントの UID 一覧を返す */
async function findPartnerUids(uid: string): Promise<string[]> {
  const linksSnap = await db
    .collection("accountLinks")
    .where("uids", "array-contains", uid)
    .get();
  return linksSnap.docs.flatMap((doc) => {
    const uids = doc.data().uids as string[];
    return uids.filter((u) => u !== uid);
  });
}

/**
 * 指定ユーザーの端末へ FCM を送る。送れたら true。
 * トークン未登録・無効などで送れない場合は false（他の相手への送信を止めないため例外は投げない）。
 */
async function sendPushToUser(
  partnerUid: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
): Promise<boolean> {
  const tokenDoc = await db
    .collection("users")
    .doc(partnerUid)
    .collection("private")
    .doc("fcm")
    .get();
  const fcmToken = tokenDoc.data()?.fcmToken as string | undefined;
  if (!fcmToken) return false;

  try {
    await messaging.send({
      token: fcmToken,
      notification,
      data,
      apns: {
        payload: {
          aps: { sound: "default" },
        },
      },
      android: {
        priority: "high",
        notification: { sound: "default" },
      },
    });
    return true;
  } catch (e) {
    functions.logger.warn("[sendPushToUser] FCM の送信に失敗しました", {
      partnerUid,
      type: data.type,
      error: String(e),
    });
    // アプリの削除などで無効になったトークンは、毎回失敗するので削除する
    if ((e as { code?: string }).code === "messaging/registration-token-not-registered") {
      await tokenDoc.ref.delete().catch(() => undefined);
    }
    return false;
  }
}

/**
 * users/{uid} の walkingStatus が 'walking' に変わったとき、
 * 連携アカウントへ FCM プッシュ通知を送信する。
 */
export const onWalkStarted = functions
  .region("asia-northeast1")
  .firestore.document("users/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const before = change.before.data();
    const after = change.after.data();

    // walkingStatus が 'walking' になった瞬間だけ処理する
    const isNowWalking = after?.walkingStatus === "walking";
    const wasWalking = before?.walkingStatus === "walking";
    if (!isNowWalking || wasWalking) return;

    const displayName =
      (after?.displayName as string | undefined) ?? "お友達";

    const partnerUids = await findPartnerUids(uid);
    await Promise.all(
      partnerUids.map((partnerUid) =>
        sendPushToUser(
          partnerUid,
          { title: "散歩開始", body: `${displayName}が散歩を始めました` },
          { type: "walk_started", partnerUid: uid },
        ),
      ),
    );
  });

/**
 * safetyAlerts/{uid} の requestedAt が更新されたとき（散歩中に一定時間反応がないとき）、
 * 連携アカウントへ安否通知を FCM で送り、結果を result に書き戻す。
 * iOS はアプリから SMS を自動送信できないため、OS に関係なく届くサーバー送信で知らせる。
 */
export const onSafetyAlertRequested = functions
  .region("asia-northeast1")
  .firestore.document("safetyAlerts/{uid}")
  .onWrite(async (change, context) => {
    const uid = context.params.uid;
    const after = change.after.data();
    const requestedAt = after?.requestedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (!requestedAt) return;

    // 自分が書き戻した result の更新や、同じ依頼の再実行では送らない
    const handledAt = after?.result?.requestedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (handledAt?.isEqual(requestedAt)) return;
    const beforeRequestedAt = change.before.data()?.requestedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (beforeRequestedAt?.isEqual(requestedAt)) return;

    const userDoc = await db.collection("users").doc(uid).get();
    const displayName =
      (userDoc.data()?.displayName as string | undefined) ?? "お友達";

    const partnerUids = await findPartnerUids(uid);
    const results = await Promise.all(
      partnerUids.map((partnerUid) =>
        sendPushToUser(
          partnerUid,
          {
            title: "安否確認",
            body: `${displayName}さんから一定時間反応がありません。確認してください。`,
          },
          { type: "safety_alert", partnerUid: uid },
        ),
      ),
    );
    const sentCount = results.filter((sent) => sent).length;

    await change.after.ref.set(
      {
        result: {
          requestedAt,
          sentCount,
          failedCount: results.length - sentCount,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );
  });

const DELETION_JOBS = "deletionJobs";

/**
 * ユーザーの個人データをすべて削除する。何度実行しても結果が同じ（冪等）。
 * 一部が失敗しても残りを続行し、失敗した項目名を返す。
 */
async function deleteUserData(uid: string): Promise<string[]> {
  const failures: string[] = [];
  const run = async (label: string, task: () => Promise<unknown>) => {
    try {
      await task();
    } catch (e) {
      functions.logger.error(`[deleteUserData] ${label} の削除に失敗しました`, {
        uid,
        error: String(e),
      });
      failures.push(label);
    }
  };

  await run("accountLinks", async () => {
    const snap = await db
      .collection("accountLinks")
      .where("uids", "array-contains", uid)
      .get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  });

  await run("linkInvites", async () => {
    const snap = await db
      .collection("linkInvites")
      .where("fromUid", "==", uid)
      .get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  });

  await run("users", () => db.recursiveDelete(db.collection("users").doc(uid)));

  await run("safetyAlerts", () =>
    db.collection("safetyAlerts").doc(uid).delete(),
  );

  await run("storage", () =>
    admin.storage().bucket().deleteFiles({ prefix: `users/${uid}/` }),
  );

  return failures;
}

/**
 * 削除を実行し、結果を deletionJobs/{uid} に記録する（クライアントからは読み書き不可）。
 * 失敗時は例外を投げる。
 */
async function runDeletionJob(uid: string): Promise<void> {
  const jobRef = db.collection(DELETION_JOBS).doc(uid);
  const failures = await deleteUserData(uid);
  if (failures.length === 0) {
    await jobRef.set(
      {
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        failures: [],
      },
      { merge: true },
    );
    return;
  }
  await jobRef.set(
    {
      status: "failed",
      failures,
      lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      attempts: admin.firestore.FieldValue.increment(1),
    },
    { merge: true },
  );
  // ERROR ログはログベースアラートで通知する想定（docs 参照）
  functions.logger.error("[deletion-failed] 退会データの削除が未完了です", {
    uid,
    failures,
  });
  throw new Error(`uid=${uid} の削除に失敗: ${failures.join(", ")}`);
}

/**
 * Firebase Auth のユーザーが削除されたとき、そのユーザーの個人データをすべて削除する。
 * - Firestore: users/{uid}（サブコレクション含む）、自分が関わる accountLinks、自分が発行した linkInvites
 * - Storage: users/{uid}/ 配下の写真
 * 失敗時は failurePolicy による自動再試行に加え、retryFailedDeletions が毎日再実行する。
 */
export const onUserDeleted = functions
  .region("asia-northeast1")
  .runWith({ failurePolicy: true })
  .auth.user()
  .onDelete(async (user) => {
    const jobRef = db.collection(DELETION_JOBS).doc(user.uid);
    // 先に「未完了」を永続化しておく（関数が途中で落ちても回収できるようにする）
    await jobRef.set(
      {
        status: "pending",
        requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await runDeletionJob(user.uid);
  });

/**
 * 未完了（pending / failed）の退会削除を毎日再実行する。
 * 自動再試行の期限切れや、関数が途中で落ちた場合の回収用。
 */
export const retryFailedDeletions = functions
  .region("asia-northeast1")
  .pubsub.schedule("every 24 hours")
  .onRun(async () => {
    const snap = await db
      .collection(DELETION_JOBS)
      .where("status", "in", ["pending", "failed"])
      .get();
    for (const doc of snap.docs) {
      try {
        await runDeletionJob(doc.id);
      } catch {
        // 失敗は runDeletionJob が記録・ログ済み。次のジョブへ進む
      }
    }
  });

const DOWNLOAD_TOKEN_KEY = "firebaseStorageDownloadTokens";

/** ファイルのダウンロードトークンを削除する（トークンが無ければ何もしない） */
async function revokeToken(bucketName: string, name: string): Promise<boolean> {
  const file = admin.storage().bucket(bucketName).file(name);
  const [metadata] = await file.getMetadata();
  if (!metadata.metadata?.[DOWNLOAD_TOKEN_KEY]) return false;
  await file.setMetadata({ metadata: { [DOWNLOAD_TOKEN_KEY]: null } });
  return true;
}

/**
 * 写真がアップロードされたら、ダウンロードトークンを削除する。
 * トークン付きURLは長期間有効で連携解除・共有OFFでも失効しないため、
 * 写真はルール（認証付き）経由の取得だけに限定する。
 * 失敗時は自動再試行し、取りこぼしは sweepDownloadTokens が回収する。
 */
export const revokeDownloadToken = functions
  .region("asia-northeast1")
  .runWith({ failurePolicy: true })
  .storage.object()
  .onFinalize(async (object) => {
    const name = object.name;
    if (!name || !name.startsWith("users/")) return;
    if (!object.metadata?.[DOWNLOAD_TOKEN_KEY]) return;
    await revokeToken(object.bucket, name);
  });

/**
 * トークンが残っている写真を毎日探して削除する（revokeDownloadToken の取りこぼし回収用）。
 */
export const sweepDownloadTokens = functions
  .region("asia-northeast1")
  .pubsub.schedule("every 24 hours")
  .onRun(async () => {
    const [files] = await admin.storage().bucket().getFiles({ prefix: "users/" });
    let revoked = 0;
    for (const file of files) {
      if (!file.metadata.metadata?.[DOWNLOAD_TOKEN_KEY]) continue;
      try {
        if (await revokeToken(file.bucket.name, file.name)) revoked++;
      } catch (e) {
        functions.logger.error("[sweepDownloadTokens] トークン削除に失敗", {
          file: file.name,
          error: String(e),
        });
      }
    }
    functions.logger.info(`[sweepDownloadTokens] ${revoked}件のトークンを削除`);
  });

/** users/{uid} の共有設定から、連携に持たせる共有設定を作る（未設定はデフォルトON） */
function shareOf(user: FirebaseFirestore.DocumentData | undefined) {
  return {
    wantToGo: user?.shareWantToGo !== false,
    visited: user?.shareVisited !== false,
  };
}

/**
 * 連携の shares を、各ユーザーの最新の共有設定に合わせる。
 * クライアントが共有設定を変えている最中に連携が作られた場合や、
 * クライアントが途中で終了した場合の補正用（トランザクションで最新値を読み直す）。
 */
async function reconcileLinkShares(
  linkRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  await db.runTransaction(async (tx) => {
    const link = await tx.get(linkRef);
    if (!link.exists) return;
    const uids = (link.data()?.uids ?? []) as string[];
    const users = await Promise.all(
      uids.map((u) => tx.get(db.collection("users").doc(u))),
    );
    const shares: Record<string, unknown> = {};
    uids.forEach((u, i) => (shares[u] = shareOf(users[i].data())));
    if (JSON.stringify(link.data()?.shares) !== JSON.stringify(shares)) {
      tx.update(linkRef, { shares });
    }
  });
}

/** 連携が作られたら、その時点の最新の共有設定に合わせる */
export const reconcileSharesOnLinkCreated = functions
  .region("asia-northeast1")
  .runWith({ failurePolicy: true })
  .firestore.document("accountLinks/{linkId}")
  .onCreate(async (snap) => reconcileLinkShares(snap.ref));

/** 共有設定が変更されたら、そのユーザーの全連携を最新の設定に合わせる */
export const reconcileSharesOnSettingsChange = functions
  .region("asia-northeast1")
  .runWith({ failurePolicy: true })
  .firestore.document("users/{uid}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (
      before.shareWantToGo === after.shareWantToGo &&
      before.shareVisited === after.shareVisited
    ) {
      return;
    }
    const links = await db
      .collection("accountLinks")
      .where("uids", "array-contains", context.params.uid)
      .get();
    await Promise.all(links.docs.map((d) => reconcileLinkShares(d.ref)));
  });
