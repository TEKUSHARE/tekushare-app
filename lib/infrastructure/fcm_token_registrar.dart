import 'dart:async';

import 'package:flutter/foundation.dart';

/// FCM トークンをユーザーに紐づけて保存する。
///
/// 保存に成功してから「登録済み」とし、失敗したら間隔を空けて再試行する。
/// iOS では APNs の準備が終わる前に getToken() が失敗することがあり、
/// 通信エラーでも失敗するため、1回の失敗で以後の登録が止まらないようにする。
class FcmTokenRegistrar {
  FcmTokenRegistrar({
    required Future<String?> Function() getToken,
    required Future<void> Function(String uid, String token) saveToken,
    List<Duration> retryDelays = defaultRetryDelays,
  }) : _getToken = getToken,
       _saveToken = saveToken,
       _retryDelays = retryDelays;

  /// 再試行の間隔（回数はこの要素数まで）
  static const defaultRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  final Future<String?> Function() _getToken;
  final Future<void> Function(String uid, String token) _saveToken;
  final List<Duration> _retryDelays;

  String? _savedUid;
  String? _savingUid;
  String? _retryUid;
  Timer? _retryTimer;
  int _retryCount = 0;

  /// [reset] のたびに進める。保存の途中でサインアウトされた場合に、古い保存結果を無視するために使う
  int _generation = 0;

  /// [uid] のトークン保存が成功済みか
  bool isRegisteredFor(String uid) => _savedUid == uid;

  /// [uid] のトークンを保存する。保存済み・保存中なら何もしない。
  Future<void> register(String uid) async {
    if (_savedUid == uid || _savingUid == uid) return;
    if (_retryUid != uid) {
      // 別ユーザーの再試行は打ち切る
      _cancelRetry();
      _retryUid = uid;
    }
    _savingUid = uid;
    final generation = _generation;
    try {
      final token = await _getToken();
      if (token == null) throw StateError('FCM トークンを取得できませんでした');
      await _saveToken(uid, token);
      // 保存中にサインアウトされていたら、登録済みにしない（再ログイン時に保存し直す）
      if (generation != _generation) return;
      _savedUid = uid;
      _cancelRetry();
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('FCM トークンの保存に失敗しました（$_retryCount回目の再試行）: $e');
      _scheduleRetry(uid);
    } finally {
      if (generation == _generation && _savingUid == uid) _savingUid = null;
    }
  }

  /// トークンが更新されたときに呼ぶ。次の [register] で保存し直す。
  void markStale() {
    _savedUid = null;
    _cancelRetry();
  }

  /// アプリが前面に戻ったときなどに呼ぶ。再試行を使い切っていても改めて保存を試みる。
  Future<void> retryNow(String uid) {
    if (_savedUid == uid) return Future.value();
    _cancelRetry();
    _retryUid = uid;
    return register(uid);
  }

  /// サインアウト時に呼ぶ
  void reset() {
    _generation++;
    _savedUid = null;
    _savingUid = null;
    _cancelRetry();
    _retryUid = null;
  }

  void dispose() => _cancelRetry();

  void _scheduleRetry(String uid) {
    if (_retryCount >= _retryDelays.length) return;
    final delay = _retryDelays[_retryCount];
    _retryCount++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_retryUid == uid) unawaited(register(uid));
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
  }
}
