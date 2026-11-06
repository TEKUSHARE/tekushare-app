import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tekushare/domain/repositories/safety_alert_repository.dart';

/// `safetyAlerts/{uid}` に送信依頼を書き込み、Cloud Functions
/// （onSafetyAlertRequested）が書き戻す送信結果を待つ。
///
/// ドキュメントの形:
/// - `requestedAt`：依頼時刻（クライアントがサーバー時刻で書き込む）
/// - `result`：`{requestedAt, sentCount, failedCount, processedAt}`（Functions のみ書き込む）
class FirestoreSafetyAlertRepositoryImpl implements SafetyAlertRepository {
  const FirestoreSafetyAlertRepositoryImpl(
    this._firestore,
    this._auth, {
    Duration resultTimeout = const Duration(seconds: 30),
  }) : _resultTimeout = resultTimeout;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Functions のコールドスタートを考慮した待ち時間
  final Duration _resultTimeout;

  @override
  Future<int> requestAlert() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('未ログインのため安否通知を送れません');

    final ref = _firestore.collection('safetyAlerts').doc(uid);
    await ref.set(
      {'requestedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    // 書き込まれたサーバー時刻を取得し、どの依頼に対する結果かを照合する
    final saved = await ref.get(const GetOptions(source: Source.server));
    final requestedAt = saved.data()?['requestedAt'] as Timestamp?;
    if (requestedAt == null) {
      throw StateError('安否通知の依頼時刻を取得できませんでした');
    }

    final result = await ref
        .snapshots()
        .map((snap) => snap.data()?['result'] as Map<String, dynamic>?)
        .firstWhere((r) => r != null && r['requestedAt'] == requestedAt)
        .timeout(_resultTimeout);
    return (result!['sentCount'] as num?)?.toInt() ?? 0;
  }
}
