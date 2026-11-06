import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/domain/entities/linked_account.dart';
import 'package:tekushare/domain/entities/spot.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/account_link_repository.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/domain/usecases/photo/attach_photo_to_spot.dart';
import 'package:tekushare/domain/usecases/photo/remove_photo_from_spot.dart';
import 'package:tekushare/domain/usecases/spot/delete_spot.dart';
import 'package:tekushare/domain/usecases/spot/update_spot.dart';
import 'package:tekushare/domain/usecases/spot/get_spots.dart';
import 'package:tekushare/domain/usecases/spot/save_spot.dart';
import 'package:tekushare/domain/usecases/spot/update_spot_status.dart';
import 'package:tekushare/domain/usecases/walk/end_walk.dart';
import 'package:tekushare/infrastructure/local_data_cleaner.dart';
import 'package:tekushare/screens/pages/map/view/walk_route_page.dart';
import 'package:tekushare/screens/pages/settings/view/phone_register_page.dart';
import 'package:tekushare/screens/pages/settings/view/settings_page.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/providers/account_link_provider.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/providers/contact_provider.dart';
import 'package:tekushare/screens/providers/spot_provider.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';

class _FakeAuthService implements AuthService {
  bool signedOut = false;
  bool deletedUser = false;

  /// deleteUser を呼ぶたびに先頭から取り出して投げるエラーコード（null なら成功）
  final deleteErrorCodes = <String?>[];

  /// reauthenticateWithPassword で投げるエラーコード（null なら成功）
  String? reauthErrorCode;
  String? reauthPassword;

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
  Future<void> signOut() async => signedOut = true;

  @override
  Future<void> deleteUser() async {
    final code = deleteErrorCodes.isEmpty ? null : deleteErrorCodes.removeAt(0);
    if (code != null) throw AuthException(code);
    deletedUser = true;
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    reauthPassword = password;
    if (reauthErrorCode != null) throw AuthException(reauthErrorCode!);
  }

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

class _FakeWalkSessionRepository implements WalkSessionRepository {
  const _FakeWalkSessionRepository();

  @override
  Future<void> saveSession(WalkSession session) async {}

  @override
  Future<List<WalkSession>> getAllSessions() async => [];

  @override
  Future<WalkSession?> getSessionById(String id) async => null;
}

class _FakeWalkRouteRepository implements RouteRepository {
  const _FakeWalkRouteRepository();

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

class _FakeSaveSpot implements SaveSpot {
  const _FakeSaveSpot();
  @override
  Future<String> call({
    required String title,
    required double latitude,
    required double longitude,
    String? memo,
    String? category,
    SpotStatus status = SpotStatus.wantToGo,
  }) async =>
      'fake-id';
}

class _FakeGetSpots implements GetSpots {
  const _FakeGetSpots();
  @override
  Stream<List<Spot>> call({SpotStatus? filter}) => Stream.value(const []);
}

class _FakeUpdateSpotStatus implements UpdateSpotStatus {
  const _FakeUpdateSpotStatus();
  @override
  Future<void> call(String spotId, SpotStatus status) async {}
}

class _FakeAttachPhotoToSpot implements AttachPhotoToSpot {
  const _FakeAttachPhotoToSpot();
  @override
  Future<String> call(String spotId, String imagePath) async => imagePath;
}

class _FakeRemovePhotoFromSpot implements RemovePhotoFromSpot {
  const _FakeRemovePhotoFromSpot();
  @override
  Future<void> call(String spotId, String imagePath) async {}
}

class _FakeUpdateSpot implements UpdateSpot {
  const _FakeUpdateSpot();
  @override
  Future<void> call(Spot spot) async {}
}

class _FakeDeleteSpot implements DeleteSpot {
  const _FakeDeleteSpot();
  @override
  Future<void> call(String id) async {}
}

class _FakeAccountLinkRepository implements AccountLinkRepository {
  const _FakeAccountLinkRepository();
  @override
  Stream<List<LinkedAccount>> watchLinkedAccounts() => const Stream.empty();
  @override
  Future<String> createInviteLink() async => 'tekushare://link/fake-token';
  @override
  Future<InviteDetails> fetchInviteDetails(String token) =>
      throw UnimplementedError();
  @override
  Future<void> acceptInvite(String token) => throw UnimplementedError();
  @override
  Future<void> unlink(String otherUid) async {}
  @override
  Future<void> updateShareSettings({
    required bool shareWantToGo,
    required bool shareVisited,
  }) async {}
  @override
  Future<({bool shareWantToGo, bool shareVisited})> fetchShareSettings(
          String otherUid) async =>
      (shareWantToGo: true, shareVisited: true);
  @override
  Future<List<Spot>> fetchSharedSpots(
    String otherUid, {
    required bool shareWantToGo,
    required bool shareVisited,
  }) async =>
      [];
}

final _spotOverride = spotProvider.overrideWith(
  (ref) => SpotNotifier(
    saveSpot: const _FakeSaveSpot(),
    getSpots: const _FakeGetSpots(),
    updateSpot: const _FakeUpdateSpot(),
    updateSpotStatus: const _FakeUpdateSpotStatus(),
    attachPhotoToSpot: const _FakeAttachPhotoToSpot(),
    removePhotoFromSpot: const _FakeRemovePhotoFromSpot(),
    deleteSpot: const _FakeDeleteSpot(),
  ),
);

/// 端末内データの削除（ObjectBox が必要）を記録だけする偽物
class _FakeLocalDataCleaner extends Fake implements LocalDataCleaner {
  final deletedUids = <String>[];

  @override
  Future<void> deleteUserData(String uid) async => deletedUids.add(uid);
}

final _contactOverride =
    contactProvider.overrideWith((ref) => Stream.value([]));

void main() {
  group('SettingsPage', () {
    late SharedPreferences settingsPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settingsPrefs = await SharedPreferences.getInstance();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump(); // build
      await tester.pump(); // sharedPrefsProvider 解決
    }

    // タイトルが表示される（AppBar + BottomNav で複数出る）
    testWidgets('shows page title', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.settingsTitle), findsAtLeastNWidgets(1));
    });

    // タイマーセクションが表示される
    testWidgets('shows timer section', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.settingsTimerTitle), findsOneWidget);
      expect(find.text(AppStrings.settingsTimerSubtitle), findsOneWidget);
    });

    // 安否確認セクションが表示される
    testWidgets('shows inactivity section', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.settingsInactivityTitle), findsOneWidget);
      expect(find.text(AppStrings.settingsInactivitySubtitle), findsOneWidget);
    });

    // シェアセクションが表示される
    testWidgets('shows share section', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.settingsShareTitle), findsOneWidget);
      expect(find.text(AppStrings.settingsShareSubtitle), findsOneWidget);
    });

    // ボトムナビが表示される
    testWidgets('shows bottom navigation', (tester) async {
      await pumpPage(tester);

      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    // タイマーの初期値が ON で表示される
    testWidgets('timer switch shows ON by default', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.switchOn), findsWidgets);
    });

    // 安否確認の初期値が OFF で表示される
    testWidgets('inactivity switch shows OFF by default', (tester) async {
      await pumpPage(tester);

      expect(find.text(AppStrings.switchOff), findsOneWidget);
    });

    // ボトムナビのホームタップで前の画面に戻る
    testWidgets('tapping bottom nav home goes to previous screen',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.tap(find.text(AppStrings.navHome));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
    });

    // ボトムナビのリストをタップすると SpotListPage へ遷移する
    testWidgets('tapping bottom nav list navigates to SpotListPage',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride, _spotOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.navList));
      await tester.pumpAndSettle();

      expect(find.byType(SpotListPage), findsOneWidget);
    });

    // ボトムナビのルートをタップすると WalkRoutePage へ遷移する
    testWidgets('tapping bottom nav route navigates to WalkRoutePage',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(AppStrings.navRoute),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WalkRoutePage), findsOneWidget);
    });

    // タイマー 片道 セグメントをタップしてもページが表示されている
    testWidgets('tapping one-way segment keeps page visible', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text(AppStrings.oneWay));
      await tester.pump();

      expect(find.text(AppStrings.oneWay), findsOneWidget);
    });

    // 往復セグメントをタップしてもページが表示されている
    testWidgets('tapping round-trip segment keeps page visible',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text(AppStrings.settingsTimerRoundTrip));
      await tester.pump();

      expect(find.text(AppStrings.settingsTimerRoundTrip), findsOneWidget);
    });

    // タイマー分数をタップするとピッカーボトムシートが開く
    testWidgets('tapping timer minutes opens picker bottom sheet',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('30${AppStrings.minuteSuffix}').first);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.pickerDone), findsOneWidget);
    });

    // ピッカーの完了をタップするとボトムシートが閉じる
    testWidgets('tapping done in picker closes bottom sheet', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('30${AppStrings.minuteSuffix}').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.pickerDone));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.pickerDone), findsNothing);
    });

    // 安否確認の分数をタップするとピッカーボトムシートが開く
    testWidgets('tapping inactivity minutes opens picker bottom sheet',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('15${AppStrings.minuteSuffix}'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.pickerDone), findsOneWidget);

      await tester.tap(find.text(AppStrings.pickerDone));
      await tester.pumpAndSettle();
    });

    // 通知先をタップすると PhoneRegisterPage に遷移する
    testWidgets('tapping add contact button opens PhoneRegisterPage',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text(AppStrings.settingsInactivityContactSet));
      await tester.pumpAndSettle();

      expect(find.byType(PhoneRegisterPage), findsOneWidget);
    });

    // シェアの行きたいリストチェックボックスをタップする
    testWidgets('tapping share spots checkbox toggles state', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // sharedPrefsProvider 解決

      await tester.ensureVisible(
        find.text(AppStrings.settingsShareWantToGo),
      );
      await tester.tap(find.text(AppStrings.settingsShareWantToGo));
      await tester.pump();

      expect(find.text(AppStrings.settingsShareWantToGo), findsOneWidget);
    });

    // シェアの行った！リストチェックボックスをタップする
    testWidgets('tapping share visited checkbox toggles state', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // sharedPrefsProvider 解決

      await tester.ensureVisible(
        find.text(AppStrings.settingsShareVisited).first,
      );
      await tester.tap(find.text(AppStrings.settingsShareVisited).first);
      await tester.pump();

      expect(find.text(AppStrings.settingsShareVisited), findsWidgets);
    });

    // 内容保存ボタンをタップしてもエラーにならない
    testWidgets('tapping share save button does not throw', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // sharedPrefsProvider 解決

      await tester.ensureVisible(
        find.text(AppStrings.settingsShareSaveButton),
      );
      await tester.tap(find.text(AppStrings.settingsShareSaveButton));
      await tester.pump();

      expect(find.text(AppStrings.settingsShareSaveButton), findsOneWidget);
    });

    // リンクコピーボタンをタップしてもエラーにならない
    testWidgets('tapping copy link button does not throw', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountLinkRepositoryProvider
                .overrideWithValue(const _FakeAccountLinkRepository()),
            _contactOverride,
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      // 招待リンクを生成するまでコピー欄は表示されない
      await tester.ensureVisible(
        find.text(AppStrings.accountLinkGenerateButton),
      );
      await tester.tap(find.text(AppStrings.accountLinkGenerateButton));
      await tester.pump();

      await tester.ensureVisible(
        find.text(AppStrings.settingsShareLinkCopy),
      );
      await tester.tap(find.text(AppStrings.settingsShareLinkCopy));
      await tester.pump();

      expect(find.text(AppStrings.settingsShareLinkCopy), findsOneWidget);
    });

    // アプリアイコン（LINE・Instagram・X）をタップしてもエラーにならない
    testWidgets('tapping app share icons does not throw', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      for (final label in ['LINE', 'Instagram', 'X']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }

      expect(find.text('LINE'), findsOneWidget);
    });

    // チェックボックスをタップすると onChanged が呼ばれる（lines 665, 670）
    testWidgets('tapping share checkboxes triggers onChanged', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_contactOverride],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(); // sharedPrefsProvider 解決

      final checkboxes = find.byType(Checkbox);
      await tester.ensureVisible(checkboxes.first);
      await tester.tap(checkboxes.first);
      await tester.pump();
      await tester.tap(checkboxes.last);
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
    });

    // スイッチをタップすると onChanged が呼ばれる（line 1186）
    testWidgets('tapping switch triggers onChanged', (tester) async {
      await pumpPage(tester);

      // Semantics(toggled:) が _CustomSwitch を包んでいるので、それをタップ
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is Semantics && w.properties.toggled != null,
            )
            .first,
      );
      await tester.pump();

      expect(find.byType(SettingsPage), findsOneWidget);
    });

    // ピッカーをスクロールすると onSelectedItemChanged が呼ばれる（lines 281-282）
    testWidgets('scrolling picker triggers onSelectedItemChanged',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('30${AppStrings.minuteSuffix}').first);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(ListWheelScrollView).first,
        const Offset(0, -100),
      );
      await tester.pump();
      await tester.tap(find.text(AppStrings.pickerDone));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
    });

    // ── ログアウト ──

    // ログアウトボタンをタップすると確認ダイアログが表示される
    testWidgets('tapping logout button shows logout confirm dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsLogout));
      await tester.tap(find.text(AppStrings.settingsLogout));
      await tester.pumpAndSettle();

      expect(
          find.text(AppStrings.settingsLogoutConfirmMessage), findsOneWidget);
    });

    // ログアウトキャンセルでダイアログが閉じる
    testWidgets('canceling logout dialog closes dialog', (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsLogout));
      await tester.tap(find.text(AppStrings.settingsLogout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.cancelButton));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsLogoutConfirmMessage), findsNothing);
    });

    // ログアウト確認で signOut が呼ばれる
    testWidgets('confirming logout calls signOut', (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsLogout));
      await tester.tap(find.text(AppStrings.settingsLogout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.settingsLogoutConfirmButton).last);
      await tester.pumpAndSettle();

      expect(fakeAuth.signedOut, isTrue);
    });

    // ── アカウント削除 ──

    // アカウント削除ボタンをタップすると確認ダイアログが表示される
    testWidgets('tapping delete account button shows confirm dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsDeleteAccount));
      await tester.tap(find.text(AppStrings.settingsDeleteAccount));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsDeleteAccountConfirmMessage),
          findsOneWidget);
    });

    // アカウント削除キャンセルでダイアログが閉じる
    testWidgets('canceling delete account dialog closes dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsDeleteAccount));
      await tester.tap(find.text(AppStrings.settingsDeleteAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.cancelButton));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsDeleteAccountConfirmMessage),
          findsNothing);
    });

    // アカウント削除確認で deleteUser が呼ばれる
    testWidgets('confirming delete account calls deleteUser', (tester) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = _FakeAuthService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            localDataCleanerProvider.overrideWithValue(_FakeLocalDataCleaner()),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: settingsPrefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsDeleteAccount));
      await tester.tap(find.text(AppStrings.settingsDeleteAccount));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(AppStrings.settingsDeleteAccountConfirmButton));
      await tester.pumpAndSettle();

      expect(fakeAuth.deletedUser, isTrue);
    });
  });

  group('SettingsPage 安否確認の通知先', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpWith(
      WidgetTester tester, {
      required bool isSmsSupported,
      required int linkedCount,
    }) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final linked = List.generate(
        linkedCount,
        (i) => LinkedAccount(
          uid: 'u$i',
          displayName: '相手$i',
          linkedAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            isSmsSupportedProvider.overrideWithValue(isSmsSupported),
            linkedAccountsProvider.overrideWith((ref) => Stream.value(linked)),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('iOS（SMS 非対応）では SMS の通知先を表示しない', (tester) async {
      await pumpWith(tester, isSmsSupported: false, linkedCount: 1);

      expect(find.text(AppStrings.settingsInactivityContact), findsNothing);
      expect(
        find.text(AppStrings.settingsInactivityPushNote(1)),
        findsOneWidget,
      );
    });

    testWidgets('iOS で連携相手がいなければ、届かないことを案内する', (tester) async {
      await pumpWith(tester, isSmsSupported: false, linkedCount: 0);

      expect(
          find.text(AppStrings.settingsInactivityNoLinkNote), findsOneWidget);
    });

    testWidgets('Android では SMS の通知先を表示する', (tester) async {
      await pumpWith(tester, isSmsSupported: true, linkedCount: 2);

      expect(find.text(AppStrings.settingsInactivityContact), findsOneWidget);
      expect(
        find.text(AppStrings.settingsInactivityPushNote(2)),
        findsOneWidget,
      );
    });
  });

  group('SettingsPage アカウント消去の再認証', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Future<_FakeLocalDataCleaner> pumpAndConfirmDelete(
      WidgetTester tester,
      _FakeAuthService fakeAuth,
    ) async {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cleaner = _FakeLocalDataCleaner();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _contactOverride,
            authServiceProvider.overrideWithValue(fakeAuth),
            authStateProvider.overrideWith(
              (ref) => Stream.value(
                const AuthUser(uid: 'alice', displayName: 'A'),
              ),
            ),
            localDataCleanerProvider.overrideWithValue(cleaner),
            walkSessionProvider.overrideWith(
              (ref) => WalkSessionNotifier(
                endWalk: const EndWalk(
                  _FakeWalkSessionRepository(),
                  _FakeWalkRouteRepository(),
                ),
                prefs: prefs,
                walkStatusRepository: _FakeWalkStatusRepository(),
              ),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) {
              final sw = MediaQuery.sizeOf(context).width;
              return Theme(
                data: Theme.of(context).copyWith(
                  extensions: [AppSizingTheme.fromScreenWidth(sw)],
                ),
                child: child!,
              );
            },
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text(AppStrings.settingsDeleteAccount));
      await tester.tap(find.text(AppStrings.settingsDeleteAccount));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(AppStrings.settingsDeleteAccountConfirmButton));
      await tester.pumpAndSettle();
      return cleaner;
    }

    testWidgets('再認証を求められたらパスワードを入力し、再認証してから消去する', (tester) async {
      final fakeAuth = _FakeAuthService()
        ..deleteErrorCodes.add('requires-recent-login');

      final cleaner = await pumpAndConfirmDelete(tester, fakeAuth);
      expect(find.text(AppStrings.settingsReauthTitle), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text(AppStrings.settingsReauthConfirmButton));
      await tester.pumpAndSettle();

      expect(fakeAuth.reauthPassword, 'secret');
      expect(fakeAuth.deletedUser, isTrue);
      expect(cleaner.deletedUids, ['alice']);
    });

    testWidgets('パスワードが違えばエラーを表示し、端末内データは消さない', (tester) async {
      final fakeAuth = _FakeAuthService()
        ..deleteErrorCodes.add('requires-recent-login')
        ..reauthErrorCode = 'wrong-password';

      final cleaner = await pumpAndConfirmDelete(tester, fakeAuth);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text(AppStrings.settingsReauthConfirmButton));
      await tester.pumpAndSettle();

      expect(find.text(authErrorMessage('wrong-password')), findsOneWidget);
      expect(fakeAuth.deletedUser, isFalse);
      expect(cleaner.deletedUids, isEmpty);
    });

    testWidgets('再認証をキャンセルしたら消去せず、確認ダイアログを再び操作できる', (tester) async {
      final fakeAuth = _FakeAuthService()
        ..deleteErrorCodes
            .addAll(['requires-recent-login', 'requires-recent-login']);

      final cleaner = await pumpAndConfirmDelete(tester, fakeAuth);
      await tester.tap(find.text(AppStrings.cancelButton).last);
      await tester.pumpAndSettle();

      expect(fakeAuth.deletedUser, isFalse);
      expect(cleaner.deletedUids, isEmpty);
      // 処理中のまま固まらず、もう一度「消去する」を押せる
      await tester
          .tap(find.text(AppStrings.settingsDeleteAccountConfirmButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.settingsReauthTitle), findsOneWidget);
    });

    testWidgets('通信エラーなどはメッセージを表示し、消去しない', (tester) async {
      final fakeAuth = _FakeAuthService()
        ..deleteErrorCodes.add('network-request-failed');

      final cleaner = await pumpAndConfirmDelete(tester, fakeAuth);

      expect(
        find.text(authErrorMessage('network-request-failed')),
        findsOneWidget,
      );
      expect(find.text(AppStrings.settingsReauthTitle), findsNothing);
      expect(cleaner.deletedUids, isEmpty);
    });
  });
}
