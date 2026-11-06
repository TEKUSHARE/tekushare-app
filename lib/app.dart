import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/infrastructure/fcm_token_registrar.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/pages/account_link/view/accept_invite_page.dart';
import 'package:tekushare/screens/pages/auth/view/display_name_page.dart';
import 'package:tekushare/screens/pages/auth/view/email_auth_page.dart';
import 'package:tekushare/screens/pages/auth/view/email_verification_page.dart';
import 'package:tekushare/screens/pages/auth/view/password_set_page.dart';
import 'package:tekushare/screens/pages/home/view/home_page.dart';
import 'package:tekushare/screens/providers/account_link_provider.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/widgets/common/app_update_gate.dart';
import 'package:tekushare/screens/widgets/walk/walk_monitor_host.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();
final navigatorKey = GlobalKey<NavigatorState>();

/// アプリのルートWidget
class TekuShareApp extends ConsumerStatefulWidget {
  const TekuShareApp({super.key});

  @override
  ConsumerState<TekuShareApp> createState() => _TekuShareAppState();
}

class _TekuShareAppState extends ConsumerState<TekuShareApp> {
  final _appLinks = AppLinks();

  // getInitialLink() と uriLinkStream の両方から同じ起動時リンクが
  // 届くことがあるため、処理済みトークンを覚えて二重に画面を開かないようにする。
  final _handledTokens = <String>{};

  final _fcmTokenRegistrar = FcmTokenRegistrar(
    getToken: FirebaseMessaging.instance.getToken,
    saveToken: _saveFcmToken,
  );
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  late final AppLifecycleListener _lifecycleListener;

  static Future<void> _saveFcmToken(String uid, String token) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    // トークンは本人のみ読めるサブコレクションに保存する
    await userRef
        .collection('private')
        .doc('fcm')
        .set({'fcmToken': token}, SetOptions(merge: true));
    // 旧仕様で users/{uid} に保存していたトークンを削除する
    await userRef
        .set({'fcmToken': FieldValue.delete()}, SetOptions(merge: true));
  }

  /// 表示名の登録まで済んだログイン中ユーザーの UID（未ログインなら null）
  String? get _registrableUid {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || user.displayName == null || user.displayName == '') {
      return null;
    }
    return user.uid;
  }

  @override
  void initState() {
    super.initState();
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri);
    });
    _appLinks.uriLinkStream.listen(_handleUri);
    // トークンが更新されたら保存し直す
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      final uid = _registrableUid;
      if (uid == null) return;
      _fcmTokenRegistrar.markStale();
      unawaited(_fcmTokenRegistrar.register(uid));
    });
    // 保存に失敗したままなら、前面に戻ったときにも保存し直す
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        final uid = _registrableUid;
        if (uid == null) return;
        unawaited(_fcmTokenRegistrar.retryNow(uid));
      },
    );
    _listenForegroundMessages();
  }

  /// アプリを開いている間に届いたプッシュ通知も表示する。
  /// 連携相手の安否通知を、アプリを使用中でも見逃さないようにするため。
  void _listenForegroundMessages() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS は OS に表示を任せる
      unawaited(
        FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          sound: true,
        ),
      );
      return;
    }
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      unawaited(
        NotificationService.instance.showRemoteNotification(
          title: notification.title ?? '',
          body: notification.body ?? '',
        ),
      );
    });
  }

  @override
  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
    _lifecycleListener.dispose();
    _fcmTokenRegistrar.dispose();
    super.dispose();
  }

  /// ディープリンクを受け取り、種別に応じて画面遷移する。
  /// 対応スキーム:
  ///   - https://tekushare.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=...
  ///   - https://tekushare.firebaseapp.com/__/auth/action?mode=verifyEmail&oobCode=...
  ///   - https://tekushare.web.app/auth/action?mode=...  (カスタムパス、将来用)
  ///   - tekushare://link/[token]
  ///   - https://tekushare.web.app/link/[token]
  void _handleUri(Uri uri) {
    if (_isPasswordResetAction(uri)) {
      final oobCode = uri.queryParameters['oobCode']!;
      if (!_handledTokens.add('reset:$oobCode')) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => PasswordSetPage(oobCode: oobCode)),
      );
      return;
    }

    if (_isEmailVerificationAction(uri)) {
      final oobCode = uri.queryParameters['oobCode']!;
      if (!_handledTokens.add('verify:$oobCode')) return;
      _applyEmailVerification(oobCode);
      return;
    }

    final token = _extractToken(uri);
    if (token == null) return;
    if (!_handledTokens.add(token)) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null && user.displayName?.isNotEmpty == true) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => AcceptInvitePage(token: token)),
      );
    } else {
      ref.read(pendingInviteTokenProvider.notifier).state = token;
    }
  }

  bool _isAuthActionUri(Uri uri) {
    return uri.scheme == 'https' &&
        uri.queryParameters['oobCode'] != null &&
        ((uri.host == 'tekushare.web.app' &&
                uri.path.startsWith('/auth/action')) ||
            (uri.host == 'tekushare.firebaseapp.com' &&
                uri.path.startsWith('/__/auth/action')));
  }

  bool _isPasswordResetAction(Uri uri) {
    return _isAuthActionUri(uri) &&
        uri.queryParameters['mode'] == 'resetPassword';
  }

  bool _isEmailVerificationAction(Uri uri) {
    return _isAuthActionUri(uri) &&
        uri.queryParameters['mode'] == 'verifyEmail';
  }

  Future<void> _applyEmailVerification(String oobCode) async {
    final authService = ref.read(authServiceProvider);
    final wasSignedIn = ref.read(authStateProvider).valueOrNull != null;
    try {
      await authService.applyEmailVerificationCode(oobCode);
      if (wasSignedIn) {
        // サインイン中なら reload してメール確認済み状態に更新 → 自動でホームへ遷移
        await authService.reloadCurrentUser();
      } else {
        // 未サインイン状態でリンクを開いた場合（新規登録後の通常フロー）、
        // applyActionCode が一時的にサインインを引き起こすことがあるため即座にサインアウト
        await authService.signOut();
      }
    } on Exception {
      // コードが無効・期限切れの場合は無視する（ユーザーは再送信できる）
    }
  }

  String? _extractToken(Uri uri) {
    if (uri.scheme == 'tekushare' && uri.host == 'link') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (uri.scheme == 'https' &&
        uri.host == 'tekushare.web.app' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 'link') {
      return uri.pathSegments[1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(appReadyProvider);
    final authState = ref.watch(authStateProvider);

    ref.listen<AsyncValue<dynamic>>(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      // サインアウト後に同じアカウントへ再ログインしても保存し直せるようにする
      if (user == null) _fcmTokenRegistrar.reset();
      if (user == null || user.displayName == null || user.displayName == '') {
        return;
      }
      unawaited(_fcmTokenRegistrar.register(user.uid));
      final token = ref.read(pendingInviteTokenProvider);
      if (token == null) return;
      ref.read(pendingInviteTokenProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => AcceptInvitePage(token: token)),
        );
      });
    });

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.zenMaruGothicTextTheme(),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final sw = MediaQuery.sizeOf(context).width;
        return Theme(
          data: Theme.of(context).copyWith(
            extensions: [AppSizingTheme.fromScreenWidth(sw)],
          ),
          child: AppUpdateGate(
            child: WalkMonitorHost(
              navigatorKey: navigatorKey,
              isEnabled: ready.hasValue && authState.valueOrNull != null,
              child: child!,
            ),
          ),
        );
      },
      home: ready.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('DB初期化エラー: $e'))),
        data: (_) {
          return authState.when(
            loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator())),
            error: (e, _) => Scaffold(body: Center(child: Text('認証エラー: $e'))),
            data: (user) {
              if (user == null) return const EmailAuthPage();
              if (!user.emailVerified) return const EmailVerificationPage();
              final name = user.displayName;
              // null は Firebase がプロフィールを同期中の一時状態。
              // ローディングを挟み DisplayNamePage が誤表示されるのを防ぐ。
              if (name == null) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (name.isEmpty) return const DisplayNamePage();
              return const HomePage();
            },
          );
        },
      ),
    );
  }
}
