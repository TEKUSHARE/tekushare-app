import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/screens/pages/auth/view/email_verification_page.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  bool resendCalled = false;
  bool reloadCalled = false;
  bool resendShouldThrow = false;
  String? resendErrorCode;

  @override
  Stream<AuthUser?> watchAuthState() => Stream.value(
        const AuthUser(
          uid: 'uid',
          email: 'test@example.com',
          emailVerified: false,
        ),
      );

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
  Future<void> sendEmailVerification() async {
    if (resendShouldThrow) {
      throw AuthException(resendErrorCode ?? 'unknown');
    }
    resendCalled = true;
  }

  @override
  Future<void> reloadCurrentUser() async {
    reloadCalled = true;
  }

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
    child: const MaterialApp(home: EmailVerificationPage()),
  );
}

void main() {
  group('EmailVerificationPage', () {
    void setDisplaySize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    // ページタイトルが表示される
    testWidgets('shows page title', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.emailVerificationPageTitle), findsOneWidget);
    });

    // 送信済みメッセージが表示される（確認メール）
    testWidgets('shows sent message', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(
          find.text(AppStrings.emailVerificationSentMessage), findsOneWidget);
    });

    // メールアドレスが表示される
    testWidgets('shows email address in description', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      expect(
        find.textContaining('test@example.com'),
        findsOneWidget,
      );
    });

    // 確認中インジケーターが表示される
    testWidgets('shows checking indicator', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.emailVerificationChecking), findsOneWidget);
    });

    // 再送信ボタンが表示される
    testWidgets('shows resend button', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(
          find.text(AppStrings.emailVerificationResendButton), findsOneWidget);
    });

    // 再送信ボタンを押すと sendEmailVerification が呼ばれる（パスワードリセットではなくメール確認）
    testWidgets('calls sendEmailVerification on resend tap', (tester) async {
      setDisplaySize(tester);
      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await tester.tap(find.text(AppStrings.emailVerificationResendButton));
      await tester.pump();
      expect(service.resendCalled, isTrue);
    });

    // 再送信成功後に完了メッセージが表示される
    testWidgets('shows resend success message after resend', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.tap(find.text(AppStrings.emailVerificationResendButton));
      await tester.pump();
      expect(
          find.text(AppStrings.emailVerificationResendSuccess), findsOneWidget);
    });

    // too-many-requests エラー時にエラーメッセージが表示される
    testWidgets('shows error message on too-many-requests', (tester) async {
      setDisplaySize(tester);
      final service = _FakeAuthService()
        ..resendShouldThrow = true
        ..resendErrorCode = 'too-many-requests';
      await tester.pumpWidget(_buildPage(service));
      await tester.tap(find.text(AppStrings.emailVerificationResendButton));
      await tester.pump();
      expect(find.text('しばらく時間をおいてから再度お試しください'), findsOneWidget);
    });

    // その他エラー時に汎用メッセージが表示される
    testWidgets('shows generic error message on unknown error', (tester) async {
      setDisplaySize(tester);
      final service = _FakeAuthService()
        ..resendShouldThrow = true
        ..resendErrorCode = 'unknown';
      await tester.pumpWidget(_buildPage(service));
      await tester.tap(find.text(AppStrings.emailVerificationResendButton));
      await tester.pump();
      expect(find.text(AppStrings.operationError), findsOneWidget);
    });

    // ログアウトボタンが表示される
    testWidgets('shows logout button', (tester) async {
      setDisplaySize(tester);
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      expect(find.text(AppStrings.settingsLogout), findsOneWidget);
    });
  });
}
