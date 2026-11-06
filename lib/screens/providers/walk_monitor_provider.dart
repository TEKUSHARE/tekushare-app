import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';
import 'package:tekushare/core/constants/map_constants.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/walk_history_provider.dart';
import 'package:tekushare/screens/providers/walk_routes_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/providers/walk_timer_provider.dart';
import 'package:tekushare/screens/providers/walk_track_points_provider.dart';

/// 散歩中の監視で、画面にダイアログを出す必要があるできごと
enum WalkMonitorEvent {
  /// タイマー（折り返し時間）が終了した
  timerFinished,

  /// 一定時間動きがない（安否確認を始める）
  inactivityDetected,
}

/// 散歩中のタイマー・見守り（不活動の検知）・長時間散歩の監視を行う。
///
/// 以前は散歩画面（WalkPage）が持っていたため、散歩中に別の画面へ移って
/// 散歩画面が破棄されると、タイマーも見守りも止まっていた。
/// 散歩中ステータスに連動して動くようにし、表示中の画面に関係なく監視を続ける。
/// ダイアログの表示は [events] を受け取る WalkMonitorHost が行う。
class WalkMonitor {
  WalkMonitor(this._ref);

  final Ref _ref;
  final _events = StreamController<WalkMonitorEvent>.broadcast();
  Timer? _ticker;
  bool _isTicking = false;
  LatLng? _lastMovedPosition;

  /// 画面に知らせるできごと
  Stream<WalkMonitorEvent> get events => _events.stream;

  /// 監視中か
  bool get isRunning => _ticker != null;

  /// 散歩が始まったときに呼ぶ。設定からタイマーを初期化し、1秒ごとの監視を始める。
  void start() {
    if (_ticker != null) return;
    final settings = _ref.read(settingsViewModelProvider);
    _ref.read(walkTimerProvider.notifier).initializeIfNeeded(
          timerEnabled: settings.timerEnabled,
          timerMinutes: settings.timerMinutes,
          timerRoundTrip: settings.timerRoundTrip,
          inactivityEnabled: settings.inactivityEnabled,
          inactivityMinutes: settings.inactivityMinutes,
        );
    _lastMovedPosition = null;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(tick());
    });
  }

  /// 散歩が終わったときに呼ぶ
  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _lastMovedPosition = null;
  }

  /// 破棄済みか
  bool get isDisposed => _isDisposed;
  bool _isDisposed = false;

  void dispose() {
    _isDisposed = true;
    stop();
    _events.close();
  }

  /// 位置が更新されたときに呼ぶ。一定距離以上動いていれば不活動タイマーを戻す。
  void onPosition(Position pos) {
    if (!isRunning) return;
    if (_ref.read(walkTimerProvider).inactSecondsLeft == null) return;
    final point = LatLng(pos.latitude, pos.longitude);
    final prev = _lastMovedPosition;
    final isMoved = prev == null ||
        const Distance().as(LengthUnit.Meter, prev, point) >=
            MapConstants.inactivityMinMovementMeters;
    if (!isMoved) return;
    _lastMovedPosition = point;
    final settings = _ref.read(settingsViewModelProvider);
    _ref
        .read(walkTimerProvider.notifier)
        .resetInact(settings.inactivityMinutes);
  }

  /// 1秒分の監視を行う（テストから直接呼べるよう公開している）
  @visibleForTesting
  Future<void> tick() async {
    // 通知の表示を待つ間に次の tick が来ても二重に処理しない
    if (_isTicking) return;
    _isTicking = true;
    try {
      _ref.read(walkTimerProvider.notifier).tick();
      await _fireIfNeeded();
    } catch (e) {
      debugPrint('散歩中の監視処理でエラーが発生しました: $e');
    } finally {
      _isTicking = false;
    }
  }

  Future<void> _fireIfNeeded() async {
    final svc = _ref.read(notificationServiceProvider);
    final timer = _ref.read(walkTimerProvider.notifier);
    final ts = _ref.read(walkTimerProvider);

    // 往復タイマーの折り返し通知（全体の半分の時間になったとき）
    final midpoint = ts.midpointSeconds;
    if (midpoint != null &&
        ts.turnSecondsLeft == midpoint &&
        !ts.midpointFired) {
      timer.markMidpointFired();
      await svc.showRoundTripNotification();
    }
    if (ts.turnSecondsLeft == 0 && !ts.turnFired) {
      timer.markTurnFired();
      await svc.showTurnaroundNotification();
      _emit(WalkMonitorEvent.timerFinished);
    }
    if (ts.inactSecondsLeft == 0 && !ts.inactFired) {
      timer.markInactFired();
      await svc.showInactivityNotification();
      _emit(WalkMonitorEvent.inactivityDetected);
    }

    // 長時間散歩の監視（2h/4h/6h リマインド、7.5h 警告、8h 自動終了）
    final startedAt = _ref.read(walkSessionProvider).startedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    for (final hour in [2, 4, 6]) {
      if (elapsed.inHours >= hour && !ts.reminderHoursFired.contains(hour)) {
        timer.markReminderFired(hour);
        await svc.showWalkReminderNotification(hour);
      }
    }
    if (elapsed.inSeconds >= 7 * 3600 + 30 * 60 && !ts.autoEndWarningFired) {
      timer.markAutoEndWarningFired();
      await svc.showWalkAutoEndWarningNotification();
    }
    if (elapsed.inSeconds >= 8 * 3600 && !ts.autoEndFired) {
      timer.markAutoEndFired();
      await _autoEndWalk();
    }
  }

  Future<void> _autoEndWalk() async {
    final session = _ref.read(walkSessionProvider);
    final route = WalkRoute(
      id: session.id,
      walkSessionId: session.id,
      points: _ref.read(walkTrackPointsProvider),
      createdAt: DateTime.now(),
    );
    final notifier = _ref.read(walkSessionProvider.notifier);
    await notifier.endWalk(route);
    _ref.invalidate(walkHistoryProvider);
    _ref.invalidate(walkRoutesProvider);
    await notifier.resetWalk();
    _ref.read(walkTimerProvider.notifier).reset();
    await _ref.read(notificationServiceProvider).showWalkAutoEndNotification();
  }

  void _emit(WalkMonitorEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

/// 散歩中の監視。散歩中ステータスに連動して開始・停止する。
/// アプリのルート（WalkMonitorHost）が watch して常に生かしておく。
final walkMonitorProvider = Provider<WalkMonitor>((ref) {
  final monitor = WalkMonitor(ref);
  ref.onDispose(monitor.dispose);

  ref.listen<WalkStatus>(
    walkSessionProvider.select((s) => s.status),
    (_, status) {
      // プロバイダーの初期化中は他のプロバイダー（タイマー）を更新できないため、
      // 初期化が終わってから開始・停止する
      scheduleMicrotask(() {
        if (monitor.isDisposed) return;
        if (status == WalkStatus.walking) {
          monitor.start();
        } else {
          monitor.stop();
        }
      });
    },
    fireImmediately: true,
  );
  ref.listen<AsyncValue<Position>>(locationProvider, (_, next) {
    next.whenData(monitor.onPosition);
  });
  // 散歩中に記録したルートを画面に関係なく溜め続ける
  ref.listen(walkTrackPointsProvider, (_, __) {});

  return monitor;
});
