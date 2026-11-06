import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/domain/usecases/walk/end_walk.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/walk_monitor_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/providers/walk_timer_provider.dart';

class _FakeNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  final shownIds = <int>[];

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async =>
      shownIds.add(id);

  @override
  Future<void> cancel({required int id, String? tag}) async {}
}

class _FakeWalkSessionRepository implements WalkSessionRepository {
  @override
  Future<void> saveSession(WalkSession session) async {}
  @override
  Future<List<WalkSession>> getAllSessions() async => [];
  @override
  Future<WalkSession?> getSessionById(String id) async => null;
}

class _FakeRouteRepository implements RouteRepository {
  @override
  Future<void> saveRoute(WalkRoute route) async {}
  @override
  Future<WalkRoute?> getRouteBySessionId(String sessionId) async => null;
  @override
  Future<List<WalkRoute>> getAllRoutes() async => [];
}

class _FakeWalkStatusRepository implements WalkStatusRepository {
  @override
  Future<void> setWalking() async {}
  @override
  Future<void> clearWalking() async {}
}

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  // ルートの途中保存がアプリのライフサイクルを監視するため
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<Position> positions;

  Future<ProviderContainer> makeContainer({
    Map<String, Object> prefsData = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsData);
    final prefs = await SharedPreferences.getInstance();
    positions = StreamController<Position>.broadcast();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith((ref) async => prefs),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        notificationServiceProvider.overrideWithValue(
          NotificationService.forTest(_FakeNotificationsPlugin()),
        ),
        walkSessionProvider.overrideWith(
          (ref) => WalkSessionNotifier(
            endWalk:
                EndWalk(_FakeWalkSessionRepository(), _FakeRouteRepository()),
            prefs: prefs,
            walkStatusRepository: _FakeWalkStatusRepository(),
          ),
        ),
        locationProvider.overrideWith((ref) => positions.stream),
      ],
    );
    addTearDown(() {
      container.dispose();
      positions.close();
    });
    await container.read(sharedPrefsProvider.future);
    return container;
  }

  /// 監視を有効にして散歩を始める（画面は一切使わない）
  Future<WalkMonitor> startWalk(ProviderContainer container) async {
    final monitor = container.read(walkMonitorProvider);
    await container.read(walkSessionProvider.notifier).startWalk();
    await Future<void>.delayed(Duration.zero);
    return monitor;
  }

  group('WalkMonitor', () {
    test('散歩を始めると画面に関係なく監視を始め、終えると止める', () async {
      final container = await makeContainer();
      final monitor = await startWalk(container);

      expect(monitor.isRunning, isTrue);
      expect(container.read(walkTimerProvider).initialized, isTrue);

      await container.read(walkSessionProvider.notifier).resetWalk();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.isRunning, isFalse);
    });

    test('動きがないまま設定時間が過ぎたら安否確認のできごとを知らせる', () async {
      final container = await makeContainer(prefsData: {
        'settings_inactivityEnabled': true,
        'settings_inactivityMinutes': 15,
      });
      final monitor = await startWalk(container);
      final events = <WalkMonitorEvent>[];
      final sub = monitor.events.listen(events.add);
      addTearDown(sub.cancel);

      for (var i = 0; i < 15 * 60; i++) {
        await monitor.tick();
      }
      await Future<void>.delayed(Duration.zero);

      expect(events, [WalkMonitorEvent.inactivityDetected]);
    });

    test('一定距離以上動いたら不活動タイマーを戻す', () async {
      final container = await makeContainer(prefsData: {
        'settings_inactivityEnabled': true,
        'settings_inactivityMinutes': 15,
      });
      final monitor = await startWalk(container);
      positions.add(_pos(35.0, 139.0));
      await Future<void>.delayed(Duration.zero);

      for (var i = 0; i < 60; i++) {
        await monitor.tick();
      }
      expect(container.read(walkTimerProvider).inactSecondsLeft, 15 * 60 - 60);

      // 約 110m 移動
      positions.add(_pos(35.001, 139.0));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(walkTimerProvider).inactSecondsLeft, 15 * 60);
    });

    test('ほとんど動いていなければ不活動タイマーを戻さない', () async {
      final container = await makeContainer(prefsData: {
        'settings_inactivityEnabled': true,
        'settings_inactivityMinutes': 15,
      });
      final monitor = await startWalk(container);
      positions.add(_pos(35.0, 139.0));
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 60; i++) {
        await monitor.tick();
      }

      // 約 1m の揺れ
      positions.add(_pos(35.00001, 139.0));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(walkTimerProvider).inactSecondsLeft, 15 * 60 - 60);
    });

    test('タイマーが終了したらタイマー終了のできごとを知らせる', () async {
      final container = await makeContainer(prefsData: {
        'settings_timerEnabled': true,
        'settings_timerRoundTrip': false,
        'settings_timerMinutes': 1,
      });
      final monitor = await startWalk(container);
      final events = <WalkMonitorEvent>[];
      final sub = monitor.events.listen(events.add);
      addTearDown(sub.cancel);

      for (var i = 0; i < 60; i++) {
        await monitor.tick();
      }
      await Future<void>.delayed(Duration.zero);

      expect(events, [WalkMonitorEvent.timerFinished]);
    });
  });
}
