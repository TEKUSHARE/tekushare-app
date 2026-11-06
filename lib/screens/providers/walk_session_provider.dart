import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/domain/usecases/walk/end_walk.dart';
import 'package:tekushare/domain/usecases/walk/start_walk.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/providers/app_providers.dart';

class WalkSessionNotifier extends StateNotifier<WalkSession> {
  WalkSessionNotifier({
    required EndWalk endWalk,
    required SharedPreferences prefs,
    required WalkStatusRepository walkStatusRepository,
    NotificationService? notificationService,
  })  : _endWalk = endWalk,
        _prefs = prefs,
        _walkStatusRepository = walkStatusRepository,
        _notificationService = notificationService,
        super(_restore(prefs));

  static const _startWalk = StartWalk();
  final EndWalk _endWalk;
  final SharedPreferences _prefs;
  final WalkStatusRepository _walkStatusRepository;
  final NotificationService? _notificationService;

  static const _kId = 'walk_id';
  static const _kStatus = 'walk_status';
  static const _kStartedAt = 'walk_started_at';
  static const _kElapsed = 'walk_elapsed';

  static WalkSession _restore(SharedPreferences prefs) {
    final id = prefs.getString(_kId);
    final statusIndex = prefs.getInt(_kStatus);
    if (id == null || statusIndex == null) {
      return const WalkSession(id: '', status: WalkStatus.idle);
    }
    // 範囲外インデックスはクラッシュを防ぐため idle に戻す
    if (statusIndex < 0 || statusIndex >= WalkStatus.values.length) {
      return const WalkSession(id: '', status: WalkStatus.idle);
    }
    final status = WalkStatus.values[statusIndex];
    if (status != WalkStatus.walking) {
      return const WalkSession(id: '', status: WalkStatus.idle);
    }
    final startedAtMs = prefs.getInt(_kStartedAt);
    final elapsed = prefs.getInt(_kElapsed) ?? 0;
    // 8時間以上経過していた場合はフォアグラウンドサービスが停止した可能性があるため自動リセット
    if (startedAtMs != null) {
      final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
      if (DateTime.now().difference(startedAt).inSeconds >= 8 * 3600) {
        return const WalkSession(id: '', status: WalkStatus.idle);
      }
    }
    return WalkSession(
      id: id,
      status: status,
      startedAt: startedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
          : null,
      elapsedSeconds: elapsed,
    );
  }

  Future<void> _persist(WalkSession session) async {
    if (session.status == WalkStatus.walking) {
      await Future.wait([
        _prefs.setString(_kId, session.id),
        _prefs.setInt(_kStatus, session.status.index),
        if (session.startedAt != null)
          _prefs.setInt(_kStartedAt, session.startedAt!.millisecondsSinceEpoch)
        else
          _prefs.remove(_kStartedAt),
        _prefs.setInt(_kElapsed, session.elapsedSeconds),
      ]);
    } else {
      await Future.wait([
        _prefs.remove(_kId),
        _prefs.remove(_kStatus),
        _prefs.remove(_kStartedAt),
        _prefs.remove(_kElapsed),
      ]);
    }
  }

  Future<void> startWalk() async {
    final session = _startWalk.call();
    await _persist(session);
    state = session;
    _syncWalkingStatus(_walkStatusRepository.setWalking);
    await _notificationService?.showWalkOngoingNotification();
  }

  Future<void> endWalk(WalkRoute route) async {
    if (state.status != WalkStatus.walking) return;
    final finished = await _endWalk.call(state, route);
    await _persist(finished);
    state = finished;
    _syncWalkingStatus(_walkStatusRepository.clearWalking);
    await _notificationService?.cancelWalkOngoingNotification();
  }

  Future<void> resetWalk() async {
    const session = WalkSession(id: '', status: WalkStatus.idle);
    await _persist(session);
    state = session;
    _syncWalkingStatus(_walkStatusRepository.clearWalking);
    await _notificationService?.cancelWalkOngoingNotification();
  }

  /// 連携相手向けの散歩中ステータスをサーバーへ同期する。
  /// Firestore の書き込みはサーバーの応答まで完了しないため、待つとオフライン時に
  /// 散歩の開始・終了が進まなくなる。ローカルの記録とは切り離し、完了を待たない
  /// （オフライン中の書き込みは Firestore が保持し、通信が戻ると送られる）。
  void _syncWalkingStatus(Future<void> Function() write) {
    unawaited(
      write().catchError((Object e) {
        debugPrint('散歩中ステータスの同期に失敗しました: $e');
      }),
    );
  }
}

final walkSessionProvider =
    StateNotifierProvider<WalkSessionNotifier, WalkSession>((ref) {
  return WalkSessionNotifier(
    endWalk: EndWalk(
      ref.watch(walkSessionRepositoryProvider),
      ref.watch(routeRepositoryProvider),
    ),
    prefs: ref.watch(sharedPrefsProvider).requireValue,
    walkStatusRepository: ref.watch(walkStatusRepositoryProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
});
