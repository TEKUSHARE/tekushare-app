import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/screens/pages/auth/view/email_auth_page.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  bool registerCalled = false;
  bool signInCalled = false;

  @override
  Stream<AuthUser?> watchAuthState() => const Stream.empty();

  @override
  Future<void> registerWithEmail(
      String email, String displayName, String password) async {
    registerCalled = true;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    signInCalled = true;
  }

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

Widget _buildPage(_FakeAuthService service) {
  return ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(home: EmailAuthPage()),
  );
}

/// 新規登録モードに切り替えてフォームを埋めるヘルパー
/// フィールド順: [0]=ニックネーム [1]=メール [2]=パスワード [3]=確認
Future<void> _fillRegisterForm(
  WidgetTester tester, {
  String name = 'テスト太郎',
  String email = 'test@example.com',
  String password = 'abc123',
  String? confirm,
}) async {
  await tester.tap(find.text('アカウントをお持ちでない方はこちら'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);
  await tester.enterText(fields.at(3), confirm ?? password);
}

void main() {
  group('EmailAuthPage - 新規登録バリデーション', () {
    testWidgets('数字のみのパスワードは登録できない', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await _fillRegisterForm(tester, password: '123456');

      await tester.tap(find.text('登録する'));
      await tester.pump();

      expect(find.text(AppStrings.emailAuthPasswordAlphanumericError),
          findsOneWidget);
      expect(service.registerCalled, isFalse);
    });

    testWidgets('英字のみのパスワードは登録できない', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await _fillRegisterForm(tester, password: 'abcdefg');

      await tester.tap(find.text('登録する'));
      await tester.pump();

      expect(find.text(AppStrings.emailAuthPasswordAlphanumericError),
          findsOneWidget);
      expect(service.registerCalled, isFalse);
    });

    testWidgets('英数字混在のパスワードは登録できる', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await _fillRegisterForm(tester, password: 'abc123');

      await tester.tap(find.text('登録する'));
      await tester.pump();

      expect(find.text(AppStrings.emailAuthPasswordAlphanumericError),
          findsNothing);
      expect(service.registerCalled, isTrue);
    });

    testWidgets('6文字未満のパスワードは登録できない', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await _fillRegisterForm(tester, password: 'ab1');

      await tester.tap(find.text('登録する'));
      await tester.pump();

      expect(find.text('パスワードは6文字以上で入力してください'), findsOneWidget);
      expect(service.registerCalled, isFalse);
    });
  });
}
