import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/screens/pages/auth/view/password_set_page.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  bool verifyCodeCalled = false;
  bool confirmCalled = false;
  bool signInCalled = false;
  bool verifyShouldThrow = false;
  bool confirmShouldThrow = false;
  String? verifyErrorCode;
  String? confirmErrorCode;

  @override
  Stream<AuthUser?> watchAuthState() => const Stream.empty();

  @override
  Future<void> registerWithEmail(
      String email, String displayName, String password) async {}

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
  Future<String> verifyPasswordResetCode(String code) async {
    verifyCodeCalled = true;
    if (verifyShouldThrow) {
      throw AuthException(verifyErrorCode ?? 'invalid-action-code');
    }
    return 'test@example.com';
  }

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    confirmCalled = true;
    if (confirmShouldThrow) {
      throw AuthException(confirmErrorCode ?? 'unknown');
    }
  }

  @override
  Future<void> applyEmailVerificationCode(String oobCode) async {}
}

Widget _buildPage(_FakeAuthService service, {String oobCode = 'test-code'}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(home: PasswordSetPage(oobCode: oobCode)),
  );
}

void main() {
  group('PasswordSetPage', () {
    // ページタイトルが表示される
    testWidgets('shows page title after code verification', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      expect(find.text(AppStrings.passwordSetPageTitle), findsNWidgets(2));
    });

    // コード検証中はローディングが表示される
    testWidgets('shows loading indicator while verifying code', (tester) async {
      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // 検証完了後にパスワードフォームが表示される
    testWidgets('shows password form after code is verified', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      expect(find.text(AppStrings.passwordSetLabel), findsOneWidget);
      expect(find.text(AppStrings.passwordSetConfirmLabel), findsOneWidget);
      expect(find.text(AppStrings.passwordSetButton), findsOneWidget);
    });

    // コードが無効なときエラー画面が表示される
    testWidgets('shows error body when code is invalid', (tester) async {
      final service = _FakeAuthService()
        ..verifyShouldThrow = true
        ..verifyErrorCode = 'invalid-action-code';
      await tester.pumpWidget(_buildPage(service));
      await tester.pump();
      expect(find.text(AppStrings.passwordSetInvalidCode), findsOneWidget);
      expect(find.text('戻る'), findsOneWidget);
    });

    // 短いパスワードでエラーが表示される
    testWidgets('shows error when password is too short', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetLabel), 'abc1');
      await tester.tap(find.text(AppStrings.passwordSetButton));
      await tester.pump();
      expect(find.text('パスワードは6文字以上で入力してください'), findsOneWidget);
    });

    // 英数字を含まないパスワードでエラーが表示される
    testWidgets('shows error when password lacks letters or digits',
        (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetLabel),
          'abcdefgh');
      await tester.tap(find.text(AppStrings.passwordSetButton));
      await tester.pump();
      expect(find.text('パスワードは英字と数字を両方含めてください'), findsOneWidget);
    });

    // パスワードが一致しないときエラーが表示される
    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(_buildPage(_FakeAuthService()));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetLabel),
          'abc123');
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetConfirmLabel),
          'abc456');
      await tester.tap(find.text(AppStrings.passwordSetButton));
      await tester.pump();
      expect(find.text(AppStrings.passwordMismatch), findsOneWidget);
    });

    // 正しいパスワードで confirmPasswordReset と signIn が呼ばれる
    testWidgets('calls confirmPasswordReset and signIn on valid submit',
        (tester) async {
      final service = _FakeAuthService();
      await tester.pumpWidget(_buildPage(service));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetLabel),
          'abc123');
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetConfirmLabel),
          'abc123');
      await tester.tap(find.text(AppStrings.passwordSetButton));
      await tester.pump();
      expect(service.confirmCalled, isTrue);
      expect(service.signInCalled, isTrue);
    });

    // confirmPasswordReset 失敗時にエラーメッセージが表示される
    testWidgets('shows error message when confirmPasswordReset fails',
        (tester) async {
      final service = _FakeAuthService()..confirmShouldThrow = true;
      await tester.pumpWidget(_buildPage(service));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetLabel),
          'abc123');
      await tester.enterText(
          find.widgetWithText(TextField, AppStrings.passwordSetConfirmLabel),
          'abc123');
      await tester.tap(find.text(AppStrings.passwordSetButton));
      await tester.pump();
      expect(find.text(AppStrings.operationError), findsOneWidget);
    });
  });
}
