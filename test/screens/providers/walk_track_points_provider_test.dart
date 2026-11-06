import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/domain/entities/lat_lng.dart' as domain;
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/domain/usecases/walk/end_walk.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/providers/walk_track_points_provider.dart';

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

/// 散歩中として保存された状態（アプリ再起動時に WalkSessionNotifier が復元する）
Map<String, Object> _walkingPrefs(String walkId) => {
      'walk_id': walkId,
      'walk_status': WalkStatus.walking.index,
      'walk_started_at': DateTime.now().millisecondsSinceEpoch,
      'walk_elapsed': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Position> positions;

  /// アプリの起動に相当する（同じ SharedPreferences で新しいコンテナを作る）
  Future<ProviderContainer> launch(SharedPreferences prefs) async {
    positions = StreamController<Position>.broadcast();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWith((ref) async => prefs),
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
    // 位置の更新を受け取れるよう購読しておく
    container.listen(walkTrackPointsProvider, (_, __) {});
    return container;
  }

  Future<void> addPosition(double lat, double lng) async {
    positions.add(_pos(lat, lng));
    await Future<void>.delayed(Duration.zero);
  }

  group('WalkTrackPointsNotifier', () {
    test('記録途中のルートを保存し、アプリ再起動後の同じ散歩で復元する', () async {
      SharedPreferences.setMockInitialValues(_walkingPrefs('walk-1'));
      final prefs = await SharedPreferences.getInstance();

      final first = await launch(prefs);
      await addPosition(35.0, 139.0);
      await addPosition(35.001, 139.0);
      first.read(walkTrackPointsProvider.notifier).flush();
      first.dispose();

      final relaunched = await launch(prefs);
      expect(relaunched.read(walkTrackPointsProvider), const [
        domain.LatLng(35.0, 139.0),
        domain.LatLng(35.001, 139.0),
      ]);

      // 復元後に届いた点は続きとして追加される
      await addPosition(35.002, 139.0);
      expect(relaunched.read(walkTrackPointsProvider).length, 3);
    });

    test('最初の点はすぐに保存する', () async {
      SharedPreferences.setMockInitialValues(_walkingPrefs('walk-1'));
      final prefs = await SharedPreferences.getInstance();

      await launch(prefs);
      await addPosition(35.0, 139.0);

      final saved = jsonDecode(
        prefs.getString(WalkTrackPointsNotifier.storageKey)!,
      ) as Map<String, dynamic>;
      expect(saved['walkId'], 'walk-1');
      expect(saved['points'], [
        [35.0, 139.0],
      ]);
    });

    test('別の散歩の途中保存は読み戻さない', () async {
      SharedPreferences.setMockInitialValues({
        ..._walkingPrefs('walk-2'),
        WalkTrackPointsNotifier.storageKey: jsonEncode({
          'walkId': 'walk-1',
          'points': [
            [35.0, 139.0],
          ],
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await launch(prefs);

      expect(container.read(walkTrackPointsProvider), isEmpty);
    });

    test('散歩を終えたら途中保存を消す', () async {
      SharedPreferences.setMockInitialValues(_walkingPrefs('walk-1'));
      final prefs = await SharedPreferences.getInstance();
      final container = await launch(prefs);
      await addPosition(35.0, 139.0);
      expect(prefs.getString(WalkTrackPointsNotifier.storageKey), isNotNull);

      await container.read(walkSessionProvider.notifier).resetWalk();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(walkTrackPointsProvider), isEmpty);
      expect(prefs.getString(WalkTrackPointsNotifier.storageKey), isNull);
    });

    test('壊れた途中保存は無視して、新しく記録を始める', () async {
      SharedPreferences.setMockInitialValues({
        ..._walkingPrefs('walk-1'),
        WalkTrackPointsNotifier.storageKey: '{not json',
      });
      final prefs = await SharedPreferences.getInstance();

      final container = await launch(prefs);
      await addPosition(35.0, 139.0);

      expect(container.read(walkTrackPointsProvider), const [
        domain.LatLng(35.0, 139.0),
      ]);
    });
  });
}
