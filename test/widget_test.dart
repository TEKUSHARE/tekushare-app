import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tekushare/app.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/domain/entities/spot.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/photo_repository.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/spot_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/screens/pages/auth/view/email_auth_page.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class _FakeSpotRepository implements SpotRepository {
  @override
  Stream<List<Spot>> getSpots() => const Stream.empty();
  @override
  Future<void> saveSpot(Spot spot) async {}
  @override
  Future<void> updateSpotStatus(String id, SpotStatus status) async {}
  @override
  Future<void> deleteSpot(String id) async {}
}

class _FakeAuthService implements AuthService {
  @override
  Stream<AuthUser?> watchAuthState() => const Stream.empty();
  @override
  Future<void> registerWithEmail(
      String email, String displayName, String password) async {}
  @override
  Future<void> signInWithEmail(String email, String password) async {}
  @override
  Future<void> setDisplayName(String name) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteUser() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> reloadCurrentUser() async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async => '';

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {}

  @override
  Future<void> applyEmailVerificationCode(String oobCode) async {}
}

class _FakePhotoRepository implements PhotoRepository {
  @override
  Future<String> attachPhoto(String spotId, String imagePath) async =>
      imagePath;
  @override
  Future<void> removePhoto(String spotId, String imagePath) async {}
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

void main() {
  testWidgets('未認証時はメール認証画面を表示する', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppConfig.setFlavor(Flavor.dev);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appReadyProvider.overrideWith((ref) async {}),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
          // 未認証状態（null）を返す
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          spotRepositoryProvider.overrideWithValue(_FakeSpotRepository()),
          photoRepositoryProvider.overrideWithValue(_FakePhotoRepository()),
          walkSessionRepositoryProvider
              .overrideWithValue(_FakeWalkSessionRepository()),
          routeRepositoryProvider.overrideWithValue(_FakeRouteRepository()),
        ],
        child: const TekuShareApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(EmailAuthPage), findsOneWidget);
  });
}
