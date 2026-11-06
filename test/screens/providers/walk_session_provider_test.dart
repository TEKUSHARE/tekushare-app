import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/domain/entities/lat_lng.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';

import 'walk_session_provider_test.mocks.dart';

/// 通知プラグインはテスト環境で初期化されないため、何もしない偽物に差し替える
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

@GenerateMocks([WalkSessionRepository, RouteRepository, WalkStatusRepository])
void main() {
  late MockWalkSessionRepository mockSessionRepo;
  late MockRouteRepository mockRouteRepo;
  late MockWalkStatusRepository mockWalkStatusRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSessionRepo = MockWalkSessionRepository();
    mockRouteRepo = MockRouteRepository();
    mockWalkStatusRepo = MockWalkStatusRepository();
    when(mockSessionRepo.saveSession(any))
        .thenAnswer((_) => Future<void>.value());
    when(mockRouteRepo.saveRoute(any)).thenAnswer((_) => Future<void>.value());
    when(mockWalkStatusRepo.setWalking())
        .thenAnswer((_) => Future<void>.value());
    when(mockWalkStatusRepo.clearWalking())
        .thenAnswer((_) => Future<void>.value());
  });

  Future<ProviderContainer> makeContainer({
    Map<String, Object> prefsData = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsData);
    final container = ProviderContainer(
      overrides: [
        walkSessionRepositoryProvider.overrideWithValue(mockSessionRepo),
        routeRepositoryProvider.overrideWithValue(mockRouteRepo),
        walkStatusRepositoryProvider.overrideWithValue(mockWalkStatusRepo),
        notificationServiceProvider.overrideWithValue(
          NotificationService.forTest(_FakeNotificationsPlugin()),
        ),
      ],
    );
    // sharedPrefsProvider (FutureProvider) を先に解決しておく
    await container.read(sharedPrefsProvider.future);
    return container;
  }

  WalkRoute makeRoute() => WalkRoute(
        id: 'route-1',
        walkSessionId: 'session-1',
        points: [const LatLng(35.0, 139.0)],
        createdAt: DateTime(2024, 1, 1),
      );

  group('WalkSessionNotifier', () {
    test('初期状態は idle', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      final session = container.read(walkSessionProvider);
      expect(session.status, WalkStatus.idle);
    });

    test('startWalk で walking 状態になる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();

      final session = container.read(walkSessionProvider);
      expect(session.status, WalkStatus.walking);
      expect(session.startedAt, isNotNull);
    });

    test('endWalk で finished 状態になる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();
      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      final session = container.read(walkSessionProvider);
      expect(session.status, WalkStatus.finished);
      expect(session.finishedAt, isNotNull);
    });

    test('endWalk で saveSession が呼ばれる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();
      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      verify(mockSessionRepo.saveSession(any)).called(1);
    });

    test('endWalk で saveRoute が呼ばれる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();
      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      verify(mockRouteRepo.saveRoute(any)).called(1);
    });

    test('オフラインでサーバー同期が終わらなくても散歩を開始・終了できる', () async {
      // Firestore はオフライン時、サーバーの応答まで書き込みが完了しない
      when(mockWalkStatusRepo.setWalking())
          .thenAnswer((_) => Completer<void>().future);
      when(mockWalkStatusRepo.clearWalking())
          .thenAnswer((_) => Completer<void>().future);
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(walkSessionProvider.notifier);

      await notifier.startWalk().timeout(const Duration(seconds: 1));
      expect(container.read(walkSessionProvider).status, WalkStatus.walking);

      await notifier.endWalk(makeRoute()).timeout(const Duration(seconds: 1));
      expect(container.read(walkSessionProvider).status, WalkStatus.finished);
    });

    test('サーバー同期が失敗しても散歩の終了は完了する', () async {
      when(mockWalkStatusRepo.clearWalking())
          .thenAnswer((_) => Future<void>.error(Exception('not-found')));
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(walkSessionProvider.notifier);

      await notifier.startWalk();
      await notifier.endWalk(makeRoute());

      expect(container.read(walkSessionProvider).status, WalkStatus.finished);
    });

    test('idle 状態で endWalk を呼んでもリポジトリが呼ばれない', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      verifyNever(mockSessionRepo.saveSession(any));
      verifyNever(mockRouteRepo.saveRoute(any));
    });

    test('walking 状態が SharedPreferences に保存されていたら起動時に復元される', () async {
      final container = await makeContainer(prefsData: {
        'walk_id': 'restored_id',
        'walk_status': WalkStatus.walking.index,
        'walk_started_at': DateTime.now().millisecondsSinceEpoch,
        'walk_elapsed': 120,
      });
      addTearDown(container.dispose);

      final session = container.read(walkSessionProvider);
      expect(session.status, WalkStatus.walking);
      expect(session.id, 'restored_id');
      expect(session.elapsedSeconds, 120);
    });

    test('SharedPreferences の状態が idle なら起動時は idle になる', () async {
      final container = await makeContainer(prefsData: {
        'walk_id': 'old_id',
        'walk_status': WalkStatus.idle.index,
      });
      addTearDown(container.dispose);

      final session = container.read(walkSessionProvider);
      expect(session.status, WalkStatus.idle);
    });

    test('startWalk で setWalking が呼ばれる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();

      verify(mockWalkStatusRepo.setWalking()).called(1);
    });

    test('endWalk で clearWalking が呼ばれる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();
      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      verify(mockWalkStatusRepo.clearWalking()).called(1);
    });

    test('resetWalk で clearWalking が呼ばれる', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).startWalk();
      await container.read(walkSessionProvider.notifier).resetWalk();

      verify(mockWalkStatusRepo.clearWalking()).called(1);
    });

    test('idle 状態で endWalk を呼んでも clearWalking が呼ばれない', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);

      await container.read(walkSessionProvider.notifier).endWalk(makeRoute());

      verifyNever(mockWalkStatusRepo.clearWalking());
    });
  });
}
