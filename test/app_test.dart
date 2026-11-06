import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/app.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

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

void main() {
  group('TekuShareApp', () {
    testWidgets('can be instantiated and renders', (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      AppConfig.setFlavor(Flavor.dev);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appReadyProvider.overrideWith((ref) async {}),
            authServiceProvider.overrideWithValue(_FakeAuthService()),
          ],
          child: const TekuShareApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
