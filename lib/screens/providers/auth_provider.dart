import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── ドメイン型 ─────────────────────────────────────────────────────────────────

class AuthUser {
  const AuthUser({
    required this.uid,
    this.displayName,
    this.email,
    this.emailVerified = false,
  });
  final String uid;
  final String? displayName;
  final String? email;
  final bool emailVerified;
}

class AuthException implements Exception {
  const AuthException(this.code);
  final String code;
}

// ── Auth state stream ─────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authServiceProvider).watchAuthState();
});

// ── Email auth UI state ───────────────────────────────────────────────────────

sealed class EmailAuthState {
  const EmailAuthState();
}

class EmailAuthIdle extends EmailAuthState {
  const EmailAuthIdle();
}

class EmailAuthLoading extends EmailAuthState {
  const EmailAuthLoading();
}

class EmailAuthError extends EmailAuthState {
  const EmailAuthError(this.message);
  final String message;
}

class EmailAuthRegistered extends EmailAuthState {
  const EmailAuthRegistered();
}

// ── Auth service interface ────────────────────────────────────────────────────

abstract interface class AuthService {
  Stream<AuthUser?> watchAuthState();
  Future<void> registerWithEmail(
      String email, String displayName, String password);
  Future<void> signInWithEmail(String email, String password);
  Future<void> setDisplayName(String name);
  Future<void> signOut();

  /// アカウントを削除する。最後のログインから時間が経っていると
  /// `AuthException('requires-recent-login')` を投げるので、
  /// [reauthenticateWithPassword] で再認証してからやり直す
  Future<void> deleteUser();

  /// 現在のユーザーをパスワードで再認証する（アカウント削除など重要な操作の前に必要）
  Future<void> reauthenticateWithPassword(String password);
  Future<void> sendPasswordResetEmail(String email);
  Future<void> sendEmailVerification();
  Future<void> reloadCurrentUser();
  Future<String> verifyPasswordResetCode(String code);
  Future<void> confirmPasswordReset(String code, String newPassword);
  Future<void> applyEmailVerificationCode(String oobCode);
}

// ── Provider declaration ──────────────────────────────────────────────────────
// 実装は ProviderScope.overrides（main_*.dart）で注入する。

final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError(
      'authServiceProvider must be overridden in ProviderScope');
});

// ── Email auth notifier ───────────────────────────────────────────────────────

/// 認証エラーのコードを画面に出すメッセージに変換する
String authErrorMessage(String code) => _mapErrorCode(code);

String _mapErrorCode(String code) {
  return switch (code) {
    'email-already-in-use' => 'このメールアドレスはすでに使われています',
    'invalid-email' => 'メールアドレスの形式が正しくありません',
    'weak-password' => 'パスワードは6文字以上で入力してください',
    'user-not-found' => 'このメールアドレスは登録されていません',
    'wrong-password' => 'パスワードが間違っています',
    'invalid-credential' => 'メールアドレスまたはパスワードが間違っています',
    'too-many-requests' => 'しばらく時間をおいてから再度お試しください',
    'network-request-failed' => 'ネットワークエラーが発生しました。接続を確認してください',
    'requires-recent-login' => '安全のため、もう一度パスワードを入力してください',
    'email-not-verified' =>
      'メールアドレスの確認が完了していません。\nお届けしたメール内のリンクをクリックしてからログインしてください。',
    _ => '認証エラーが発生しました（$code）',
  };
}

class EmailAuthNotifier extends StateNotifier<EmailAuthState> {
  EmailAuthNotifier(this._service) : super(const EmailAuthIdle());

  final AuthService _service;

  Future<void> register(
      String email, String displayName, String password) async {
    state = const EmailAuthLoading();
    try {
      await _service.registerWithEmail(email, displayName, password);
      state = const EmailAuthRegistered();
    } on AuthException catch (e) {
      state = EmailAuthError(_mapErrorCode(e.code));
    } catch (_) {
      state = const EmailAuthError('エラーが発生しました');
    }
  }

  Future<void> signIn(String email, String password) async {
    state = const EmailAuthLoading();
    try {
      await _service.signInWithEmail(email, password);
      state = const EmailAuthIdle();
    } on AuthException catch (e) {
      state = EmailAuthError(_mapErrorCode(e.code));
    } catch (_) {
      state = const EmailAuthError('エラーが発生しました');
    }
  }

  void reset() => state = const EmailAuthIdle();
}

final emailAuthProvider =
    StateNotifierProvider<EmailAuthNotifier, EmailAuthState>((ref) {
  return EmailAuthNotifier(ref.watch(authServiceProvider));
});

// ── Password reset notifier ───────────────────────────────────────────────────

sealed class PasswordResetState {
  const PasswordResetState();
}

class PasswordResetIdle extends PasswordResetState {
  const PasswordResetIdle();
}

class PasswordResetLoading extends PasswordResetState {
  const PasswordResetLoading();
}

class PasswordResetSuccess extends PasswordResetState {
  const PasswordResetSuccess();
}

class PasswordResetError extends PasswordResetState {
  const PasswordResetError(this.message);
  final String message;
}

class PasswordResetNotifier extends StateNotifier<PasswordResetState> {
  PasswordResetNotifier(this._service) : super(const PasswordResetIdle());

  final AuthService _service;

  Future<void> send(String email) async {
    state = const PasswordResetLoading();
    try {
      await _service.sendPasswordResetEmail(email);
      state = const PasswordResetSuccess();
    } on AuthException catch (e) {
      state = PasswordResetError(_mapErrorCode(e.code));
    } catch (_) {
      state = const PasswordResetError('エラーが発生しました');
    }
  }

  void reset() => state = const PasswordResetIdle();
}

final passwordResetProvider =
    StateNotifierProvider<PasswordResetNotifier, PasswordResetState>((ref) {
  return PasswordResetNotifier(ref.watch(authServiceProvider));
});

// ── Display name notifier ─────────────────────────────────────────────────────

class DisplayNameNotifier extends StateNotifier<AsyncValue<void>> {
  DisplayNameNotifier(this._service) : super(const AsyncData(null));

  final AuthService _service;

  Future<void> save(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.setDisplayName(name));
  }
}

final displayNameProvider =
    StateNotifierProvider<DisplayNameNotifier, AsyncValue<void>>((ref) {
  return DisplayNameNotifier(ref.watch(authServiceProvider));
});
