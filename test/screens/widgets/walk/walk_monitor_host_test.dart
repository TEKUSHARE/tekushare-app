import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/core/constants/app_strings.dart';
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
import 'package:tekushare/screens/widgets/walk/safety_confirm_dialog.dart';
import 'package:tekushare/screens/widgets/walk/walk_monitor_host.dart';

class _FakeNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {}

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

void main() {
  /// 散歩画面ではない画面（スポット一覧などの代わり）を表示した状態で、監視を動かす
  Future<WalkMonitor> pumpOtherPageWhileWalking(
    WidgetTester tester, {
    required Map<String, Object> prefsData,
  }) async {
    SharedPreferences.setMockInitialValues(prefsData);
    final prefs = await SharedPreferences.getInstance();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWith((ref) async => prefs),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          notificationServiceProvider.overrideWithValue(
            NotificationService.forTest(_FakeNotificationsPlugin()),
          ),
          walkSessionProvider.overrideWith(
            (ref) => WalkSessionNotifier(
              endWalk: EndWalk(
                _FakeWalkSessionRepository(),
                _FakeRouteRepository(),
              ),
              prefs: prefs,
              walkStatusRepository: _FakeWalkStatusRepository(),
            ),
          ),
          locationProvider
              .overrideWith((ref) => const Stream<Position>.empty()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => WalkMonitorHost(
            navigatorKey: navigatorKey,
            isEnabled: true,
            child: child!,
          ),
          home: const Scaffold(body: Text('スポット一覧')),
        ),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WalkMonitorHost)),
    );
    // 設定値の読み込みが終わってから散歩を始める（タイマーは開始時の設定で初期化される）
    await tester.runAsync(() => container.read(sharedPrefsProvider.future));
    await tester.pump();
    await container.read(walkSessionProvider.notifier).startWalk();
    await tester.pump();
    return container.read(walkMonitorProvider);
  }

  group('WalkMonitorHost', () {
    testWidgets('散歩画面以外を開いていても、タイマー終了のダイアログを表示する', (tester) async {
      final monitor = await pumpOtherPageWhileWalking(tester, prefsData: {
        'settings_timerEnabled': true,
        'settings_timerRoundTrip': false,
        'settings_timerMinutes': 1,
      });

      for (var i = 0; i < 60; i++) {
        await monitor.tick();
      }
      await tester.pump();

      expect(find.text('スポット一覧'), findsOneWidget);
      expect(find.text(AppStrings.timerFinishedTitle), findsOneWidget);
    });

    testWidgets('タイマー終了のダイアログでリセットすると、タイマーが初期値に戻る', (tester) async {
      final monitor = await pumpOtherPageWhileWalking(tester, prefsData: {
        'settings_timerEnabled': true,
        'settings_timerRoundTrip': false,
        'settings_timerMinutes': 1,
      });
      for (var i = 0; i < 60; i++) {
        await monitor.tick();
      }
      await tester.pump();

      await tester.tap(find.text(AppStrings.timerReset));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.timerFinishedTitle), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WalkMonitorHost)),
      );
      expect(container.read(walkTimerProvider).turnSecondsLeft, 60);
    });

    testWidgets('散歩画面以外を開いていても、動きがなければ安否確認を表示する', (tester) async {
      final monitor = await pumpOtherPageWhileWalking(tester, prefsData: {
        'settings_inactivityEnabled': true,
        'settings_inactivityMinutes': 15,
      });

      for (var i = 0; i < 15 * 60; i++) {
        await monitor.tick();
      }
      await tester.pump();

      expect(find.byType(SafetyConfirmDialog), findsOneWidget);

      // 「元気です」で閉じ、不活動タイマーが戻る
      await tester.tap(find.text(AppStrings.safetyOk));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyConfirmDialog), findsNothing);
    });
  });
}
