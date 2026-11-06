import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/screens/pages/auth/view/password_reset_page.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  bool sendCalled = false;
  String? sentEmail;
  bool shouldThrow = false;

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
  Future<void> sendPasswordResetEmail(String email) async {
    if (shouldThrow) throw const AuthException('user-not-found');
    sendCalled = true;
    sentEmail = email;
  }

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> reloadCurrentUser() async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'test@example.com';

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {}

  @override
  Future<void> applyEmailVerificationCode(String oobCode) async {}
}

Widget _buildPage(_FakeAuthService service) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(service),
    ],
    child: const MaterialApp(home: PasswordResetPage()),
  );
}

void main() {
  group('PasswordResetPage', () {
    // ページタイトルが表示される
    testWidgets('shows page title', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.passwordResetPageTitle), findsOneWidget);
    });

    // 説明文が表示される
    testWidgets('shows description', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.passwordResetDescription), findsOneWidget);
    });

    // 送信ボタンが表示される
    testWidgets('shows send button', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.passwordResetSendButton), findsOneWidget);
    });

    // メール未入力で送信するとSnackBarが表示される
    testWidgets('shows snackbar when email is empty', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pump();
      expect(find.text('メールアドレスを入力してください'), findsOneWidget);
    });

    // メールを入力して送信すると sendPasswordResetEmail が呼ばれる
    testWidgets('calls sendPasswordResetEmail with entered email',
        (tester) async {
      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await tester.enterText(find.byType(TextField), 'test@example.com');
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pumpAndSettle();
      expect(service.sendCalled, isTrue);
      expect(service.sentEmail, 'test@example.com');
    });

    // 送信成功後に完了メッセージが表示される
    testWidgets('shows success message after send', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.enterText(find.byType(TextField), 'test@example.com');
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.passwordResetSuccessMessage), findsOneWidget);
    });

    // 送信成功後は送信ボタンが非表示になる
    testWidgets('hides send button after success', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.enterText(find.byType(TextField), 'test@example.com');
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.passwordResetSendButton), findsNothing);
    });

    // エラー時にエラーメッセージが表示される
    testWidgets('shows error message on failure', (tester) async {
      final service = _FakeAuthService()..shouldThrow = true;
      await tester.pumpWidget(_buildPage(service));
      await tester.enterText(find.byType(TextField), 'notfound@example.com');
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pumpAndSettle();
      expect(find.text('このメールアドレスは登録されていません'), findsOneWidget);
    });

    // ページを再度開いたとき Success 状態がリセットされる
    testWidgets('resets to idle when page is reopened after success',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeAuthService();
      // Navigator で push/pop を使い、initState が2回呼ばれることを確認する
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PasswordResetPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      // 1回目: ページを開いてメール送信 → Success 状態
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'test@example.com');
      await tester.tap(find.text(AppStrings.passwordResetSendButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.passwordResetSuccessMessage), findsOneWidget);

      // ページを閉じる
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // 2回目: ページを再度開く → initState でリセットされ Idle 状態になる
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.passwordResetSuccessMessage), findsNothing);
      expect(find.text(AppStrings.passwordResetSendButton), findsOneWidget);
    });
  });
}
