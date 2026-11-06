// iOS 実機・シミュレーターでネイティブプラグインが動くかを確認するスモークテスト。
// Firebase などを偽物に差し替えず、本物のプラグインを呼び出す。
//
// 実行例:
//   flutter test integration_test/ios_platform_smoke_test.dart \
//     --flavor dev -d <シミュレーターのUDID>
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/app.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/firebase_options.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/objectbox.g.dart';
import 'package:tekushare/screens/providers/firebase_providers.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // iOS 専用（期待値に iOS の Bundle ID・Firebase アプリ ID を使う）
  final skipReason = Platform.isIOS ? null : 'iOS 専用のスモークテスト';

  setUpAll(() async {
    if (!Platform.isIOS) return;
    AppConfig.setFlavor(Flavor.dev);
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  });

  group('iOS ネイティブプラグイン', skip: skipReason, () {
    test('Firebase の設定が新しい Bundle ID の iOS アプリを指している', () {
      final options = Firebase.app().options;
      expect(options.iosBundleId, 'com.tekushare.app');
      expect(options.appId, '1:607979997790:ios:e0bfb99dbdad7a8f5742cf');
    });

    test('Firebase Auth・Firestore に接続できる', () async {
      final user = FirebaseAuth.instance.currentUser;
      // ログイン済みなら本人のドキュメントをサーバーから読めること
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
        expect(doc.exists, isTrue);
      }
    });

    test('起動時アップデート案内の設定を取得できる', () async {
      // firestore.rules の appUpdates（#176）がデプロイされるまでは
      // permission-denied になる。プラットフォームに依存しないため skip 扱い。
      try {
        await FirebaseFirestore.instance
            .collection('appUpdates')
            .doc('dev_ios')
            .get(const GetOptions(source: Source.server));
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          markTestSkipped('appUpdates のルールが未デプロイ');
          return;
        }
        rethrow;
      }
    });

    test('FCM の通知許可リクエストが例外にならない', () async {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: false,
        sound: true,
      );
      expect(settings.authorizationStatus, isNotNull);
    });

    test('ObjectBox の Store を開いて読み書きできる', () async {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/objectbox_smoke_${DateTime.now().millisecondsSinceEpoch}';
      final store = await openStore(directory: path);
      addTearDown(() {
        store.close();
        Directory(path).deleteSync(recursive: true);
      });
      expect(store.isClosed(), isFalse);
    });

    test('SharedPreferences に保存・読み込みできる', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ios_smoke_test', 'ok');
      expect(prefs.getString('ios_smoke_test'), 'ok');
      await prefs.remove('ios_smoke_test');
    });

    test('ローカル通知を初期化して表示できる', () async {
      await NotificationService.instance.initialize();
      await NotificationService.instance.showWalkReminderNotification(1);
    });

    test('位置情報サービスと現在地を取得できる', () async {
      expect(await Geolocator.isLocationServiceEnabled(), isTrue);
      // テスト実行時はアプリが再インストールされ許可がリセットされるため、
      // `xcrun simctl privacy <UDID> grant location-always <BundleID>` で
      // 外から許可されるまで待つ
      var permission = await Geolocator.checkPermission();
      for (var i = 0; i < 60 && permission == LocationPermission.denied; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        permission = await Geolocator.checkPermission();
      }
      expect(
        permission,
        anyOf(LocationPermission.always, LocationPermission.whileInUse),
      );
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 20));
      expect(pos.latitude, isNonZero);
    });

    test('URL スキームの問い合わせができる', () async {
      expect(
          await canLaunchUrl(Uri.parse('https://tekushare.web.app')), isTrue);
      // sms / instagram は LSApplicationQueriesSchemes に登録済みなら例外にならない
      await canLaunchUrl(Uri(scheme: 'sms', path: '0000'));
      await canLaunchUrl(Uri.parse('instagram://app'));
    });

    test('アプリ情報（ビルド番号）を取得できる', () async {
      final info = await PackageInfo.fromPlatform();
      expect(info.packageName, 'com.tekushare.app.dev');
      expect(int.tryParse(info.buildNumber), isNotNull);
    });

    test('app_links の初期リンク取得が例外にならない', () async {
      await AppLinks().getInitialLink();
    });
  });

  group('iOS 画面遷移', skip: skipReason, () {
    testWidgets('本物の Provider で全タブを開いても例外が出ない', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = original);

      await tester.pumpWidget(
        ProviderScope(
          overrides: firebaseProviderOverrides(),
          child: const TekuShareApp(),
        ),
      );
      await _settle(tester);

      if (FirebaseAuth.instance.currentUser == null) {
        markTestSkipped('未ログインのため画面遷移の確認は省略');
        return;
      }

      for (final tab in [
        AppStrings.navList,
        AppStrings.navRoute,
        AppStrings.navSettings,
        AppStrings.navHome,
      ]) {
        await tester.tap(find.text(tab).last);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: '$tab タブで例外');
      }

      FlutterError.onError = original;
      expect(
        errors.map((e) => e.exceptionAsString()).toList(),
        isEmpty,
      );
    });
  });
}

/// 地図タイルの読み込みや Stream でアニメーションが終わらないことがあるため、
/// pumpAndSettle ではなく一定時間だけ描画を進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
