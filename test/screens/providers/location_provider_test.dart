import 'dart:async';

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
import 'package:tekushare/infrastructure/location_service.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this._controller);

  final StreamController<Position> _controller;
  int subscribeCount = 0;

  @override
  Stream<Position> rawPositionStream() {
    subscribeCount++;
    return _controller.stream;
  }
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

Position _pos(double accuracy) => Position(
      latitude: 35,
      longitude: 139,
      timestamp: DateTime(2026),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late StreamController<Position> positions;
  late _FakeLocationService service;

  Future<ProviderContainer> makeWalkingContainer() async {
    // 散歩中として保存された状態（起動時に WalkSessionNotifier が復元する）
    SharedPreferences.setMockInitialValues({
      'walk_id': 'walk-1',
      'walk_status': WalkStatus.walking.index,
      'walk_started_at': DateTime.now().millisecondsSinceEpoch,
      'walk_elapsed': 0,
    });
    final prefs = await SharedPreferences.getInstance();
    positions = StreamController<Position>.broadcast();
    service = _FakeLocationService(positions);
    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
        walkSessionProvider.overrideWith(
          (ref) => WalkSessionNotifier(
            endWalk:
                EndWalk(_FakeWalkSessionRepository(), _FakeRouteRepository()),
            prefs: prefs,
            walkStatusRepository: _FakeWalkStatusRepository(),
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      positions.close();
    });
    container.listen(rawLocationProvider, (_, __) {});
    container.listen(locationProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  group('rawLocationProvider / locationProvider', () {
    test('誤差の大きい位置は表示用にだけ流し、記録用には流さない', () async {
      final container = await makeWalkingContainer();

      positions.add(_pos(65));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(rawLocationProvider).valueOrNull?.accuracy, 65);
      expect(container.read(locationProvider).hasValue, isFalse);
    });

    test('精度の良い位置は表示用・記録用の両方に流す', () async {
      final container = await makeWalkingContainer();

      positions.add(_pos(10));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(rawLocationProvider).valueOrNull?.accuracy, 10);
      expect(container.read(locationProvider).valueOrNull?.accuracy, 10);
    });

    test('GPS の購読は1本だけにする', () async {
      await makeWalkingContainer();

      expect(service.subscribeCount, 1);
    });
  });
}
