import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/domain/entities/spot.dart';
import 'package:tekushare/domain/usecases/photo/attach_photo_to_spot.dart';
import 'package:tekushare/domain/usecases/photo/remove_photo_from_spot.dart';
import 'package:tekushare/domain/usecases/spot/delete_spot.dart';
import 'package:tekushare/domain/usecases/spot/update_spot.dart';
import 'package:tekushare/domain/usecases/spot/get_spots.dart';
import 'package:tekushare/domain/usecases/spot/save_spot.dart';
import 'package:tekushare/domain/usecases/spot/update_spot_status.dart';
import 'package:tekushare/infrastructure/camera_service.dart';
import 'package:tekushare/infrastructure/notification_service.dart';
import 'package:tekushare/screens/pages/map/view/walk_route_page.dart';
import 'package:tekushare/screens/pages/settings/view/settings_page.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/providers/contact_provider.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/pages/spot/view/want_to_go_page.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/domain/repositories/route_repository.dart';
import 'package:tekushare/domain/repositories/walk_session_repository.dart';
import 'package:tekushare/screens/pages/walk/view/end_walk_page.dart';
import 'package:tekushare/screens/pages/walk/view/walk_page.dart';
import 'package:tekushare/domain/repositories/walk_status_repository.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/spot_provider.dart';
import 'package:tekushare/screens/providers/walk_timer_provider.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';

// ──────────────────────────────────────────
// フェイク実装
// ──────────────────────────────────────────

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

class _FakeWalkStatusRepository implements WalkStatusRepository {
  @override
  Future<void> setWalking() async {}
  @override
  Future<void> clearWalking() async {}
}

final _walkSessionRepoOverride = walkSessionRepositoryProvider
    .overrideWithValue(_FakeWalkSessionRepository());
final _routeRepoOverride =
    routeRepositoryProvider.overrideWithValue(_FakeRouteRepository());
final _walkStatusRepoOverride =
    walkStatusRepositoryProvider.overrideWithValue(_FakeWalkStatusRepository());

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

class _FakeCameraService extends Fake implements CameraService {
  _FakeCameraService(this._returnPath);
  final String? _returnPath;

  @override
  Future<String?> takePhoto() async => _returnPath;
}

class _FakeNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {}

  @override
  Future<void> cancelAll() async {}
}

final _notificationOverride = notificationServiceProvider.overrideWithValue(
  NotificationService.forTest(_FakeNotificationsPlugin()),
);

class _TimerEnabledSettingsViewModel extends SettingsViewModel {
  @override
  SettingsState build() => const SettingsState(
        timerEnabled: true,
        timerMinutes: 30,
        inactivityEnabled: true,
        inactivityMinutes: 15,
      );
}

class _TimerDisabledSettingsViewModel extends SettingsViewModel {
  @override
  SettingsState build() => const SettingsState(
        timerEnabled: false,
        inactivityEnabled: false,
      );
}

final _timerEnabledOverride = settingsViewModelProvider.overrideWith(
  _TimerEnabledSettingsViewModel.new,
);

// 散歩開始時に WalkMonitor が初期化した後のタイマー（30分・見守り15分）
class _InitializedTimerNotifier extends WalkTimerNotifier {
  _InitializedTimerNotifier() {
    state = const WalkTimerState(
      turnSecondsLeft: 30 * 60,
      inactSecondsLeft: 15 * 60,
      initialized: true,
    );
  }
}

final _initializedTimerOverride =
    walkTimerProvider.overrideWith((_) => _InitializedTimerNotifier());

final _timerDisabledOverride = settingsViewModelProvider.overrideWith(
  _TimerDisabledSettingsViewModel.new,
);

Position _makePosition(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

// ──────────────────────────────────────────
// テスト
// ──────────────────────────────────────────

void main() {
  group('WalkPage', () {
    void setDisplaySize(WidgetTester tester) {
      tester.view.physicalSize = const Size(1170, 3000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpWalkPage(
      WidgetTester tester, {
      Stream<Position>? locationStream,
      CameraService? camera,
    }) async {
      setDisplaySize(tester);

      // 表示用（精度を問わない）と記録用の両方に同じ位置を流す
      final positions = (locationStream ?? const Stream<Position>.empty())
          .asBroadcastStream();
      final overrides = <Override>[
        locationProvider.overrideWith((ref) => positions),
        rawLocationProvider.overrideWith((ref) => positions),
        _notificationOverride,
        _walkSessionRepoOverride,
        _routeRepoOverride,
        _walkStatusRepoOverride,
        contactProvider.overrideWith((ref) => Stream.value([])),
        if (camera != null) cameraServiceProvider.overrideWith((ref) => camera),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
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
            home: const WalkPage(),
          ),
        ),
      );
      await tester.pump();
    }

    // 3つのボタンが表示される
    testWidgets('shows three buttons', (tester) async {
      await pumpWalkPage(tester);

      expect(find.text(AppStrings.takePhoto), findsOneWidget);
      expect(find.text(AppStrings.wantToGo), findsOneWidget);
      expect(find.text(AppStrings.endWalk), findsOneWidget);
    });

    // ボトムナビが表示される
    testWidgets('shows bottom navigation', (tester) async {
      await pumpWalkPage(tester);

      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    // GPS 取得中は loading インジケーターが表示される
    testWidgets('shows loading indicator while GPS is acquiring',
        (tester) async {
      await pumpWalkPage(tester, locationStream: const Stream.empty());

      expect(find.text(AppStrings.gpsAcquiring), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // GPS 取得失敗時はエラーテキストが表示される
    testWidgets('shows error text when GPS is unavailable', (tester) async {
      final errorStream = Stream<Position>.error(Exception('GPS error'));

      await pumpWalkPage(tester, locationStream: errorStream);
      await tester.pump();

      expect(find.text(AppStrings.gpsUnavailableError), findsOneWidget);
    });

    // GPS 未取得でカメラボタンをタップするとエラー SnackBar が表示される
    testWidgets('shows snackbar when camera tapped without GPS',
        (tester) async {
      await pumpWalkPage(tester, locationStream: const Stream.empty());

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pump();

      expect(find.text(AppStrings.gpsUnavailableError), findsWidgets);
    });

    // GPS 取得済みで撮影すると pendingPhotoProvider に保存される
    testWidgets('stores photo path in pendingPhotoProvider when photo taken',
        (tester) async {
      const imagePath = '/fake/photo.jpg';
      final position = _makePosition(35.6895, 139.6917);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
        camera: _FakeCameraService(imagePath),
      );
      await tester.pump();

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WalkPage)),
      );
      expect(container.read(pendingPhotoProvider), contains(imagePath));
    });

    // GPS 取得済みで撮影すると photoTaken SnackBar が表示される
    testWidgets('shows photoTaken snackbar after photo is taken',
        (tester) async {
      const imagePath = '/fake/photo.jpg';
      final position = _makePosition(35.6895, 139.6917);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
        camera: _FakeCameraService(imagePath),
      );
      await tester.pump();

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.photoTaken), findsOneWidget);
    });

    // カメラをキャンセルした場合は pendingPhotoProvider に保存しない
    testWidgets('does not store photo when camera is cancelled',
        (tester) async {
      final position = _makePosition(35.0, 139.0);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
        camera: _FakeCameraService(null),
      );
      await tester.pump();

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WalkPage)),
      );
      expect(container.read(pendingPhotoProvider), isEmpty);
    });

    // 行きたいボタンをタップすると WantToGoPage へ遷移する
    testWidgets('navigates to WantToGoPage when want-to-go button is tapped',
        (tester) async {
      setDisplaySize(tester);

      final locationStream =
          Stream<Position>.error(Exception('GPS unavailable'))
              .asBroadcastStream();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationProvider.overrideWith((ref) => locationStream),
            rawLocationProvider.overrideWith((ref) => locationStream),
            _notificationOverride,
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
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalkPage()),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.wantToGo));
      await tester.pumpAndSettle();

      expect(find.byType(WantToGoPage), findsOneWidget);
    });

    // 散歩を終了するボタンをタップすると EndWalkPage へ遷移する
    testWidgets('navigates to EndWalkPage when end walk button is tapped',
        (tester) async {
      setDisplaySize(tester);

      final locationStream =
          Stream<Position>.error(Exception('GPS unavailable'))
              .asBroadcastStream();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationProvider.overrideWith((ref) => locationStream),
            rawLocationProvider.overrideWith((ref) => locationStream),
            _notificationOverride,
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
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalkPage()),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      expect(find.byType(WalkPage), findsOneWidget);

      await tester.tap(find.text(AppStrings.endWalk));
      await tester.pumpAndSettle();
      expect(find.byType(EndWalkPage), findsOneWidget);
    });

    // ボトムナビのホームをタップしても WalkPage に留まる（散歩中はホームが WalkPage）
    testWidgets('tapping bottom nav home stays on WalkPage', (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
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
                  MaterialPageRoute(builder: (_) => const WalkPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.navHome));
      await tester.pumpAndSettle();

      expect(find.byType(WalkPage), findsOneWidget);
    });

    // ボトムナビのリストをタップすると SpotListPage へ遷移する
    testWidgets('tapping bottom nav list navigates to SpotListPage',
        (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [_spotOverride],
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
                  MaterialPageRoute(builder: (_) => const WalkPage()),
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
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
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
                  MaterialPageRoute(builder: (_) => const WalkPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.navRoute));
      await tester.pumpAndSettle();

      expect(find.byType(WalkRoutePage), findsOneWidget);
    });

    // ボトムナビの設定をタップすると SettingsPage へ遷移する
    testWidgets('tapping bottom nav settings navigates to SettingsPage',
        (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactProvider.overrideWith((ref) => Stream.value([])),
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
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WalkPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.navSettings));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
    });

    // GPS 取得済みのとき FlutterMap が表示される
    testWidgets('shows FlutterMap when GPS position is available',
        (tester) async {
      final position = _makePosition(35.6895, 139.6917);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
      );
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
    });

    // GPS 未取得のとき FlutterMap は表示されない
    testWidgets('does not show FlutterMap when GPS is not yet available',
        (tester) async {
      await pumpWalkPage(tester, locationStream: const Stream.empty());

      expect(find.byType(FlutterMap), findsNothing);
    });

    // 撮影すると地図上に ClipOval サムネイルが追加される
    testWidgets('adds photo marker on map after taking photo', (tester) async {
      const imagePath = '/fake/photo.jpg';
      final position = _makePosition(35.6895, 139.6917);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
        camera: _FakeCameraService(imagePath),
      );
      await tester.pump();

      expect(find.byType(ClipOval), findsNothing);

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsOneWidget);
    });

    // 撮影をキャンセルした場合は地図上にサムネイルが追加されない
    testWidgets('does not add photo marker when camera is cancelled',
        (tester) async {
      final position = _makePosition(35.0, 139.0);

      await pumpWalkPage(
        tester,
        locationStream: Stream.value(position),
        camera: _FakeCameraService(null),
      );
      await tester.pump();

      await tester.tap(find.text(AppStrings.takePhoto));
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsNothing);
    });

    // タイマー有効時はチップが表示される
    testWidgets('shows timer chips when timers are enabled', (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationProvider.overrideWith((ref) => const Stream.empty()),
            rawLocationProvider.overrideWith((ref) => const Stream.empty()),
            _timerEnabledOverride,
            _initializedTimerOverride,
            _notificationOverride,
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
            home: const WalkPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.timerInactivity), findsOneWidget);
    });

    // タイマー有効時はリセットアイコンが ClockHeader 横に表示される
    testWidgets('shows reset icon when timer is enabled', (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationProvider.overrideWith((ref) => const Stream.empty()),
            rawLocationProvider.overrideWith((ref) => const Stream.empty()),
            _timerEnabledOverride,
            _initializedTimerOverride,
            _notificationOverride,
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
            home: const WalkPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    // タイマー無効時はチップが表示されない
    testWidgets('hides timer chips when timers are disabled', (tester) async {
      setDisplaySize(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationProvider.overrideWith((ref) => const Stream.empty()),
            rawLocationProvider.overrideWith((ref) => const Stream.empty()),
            _timerDisabledOverride,
            _notificationOverride,
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
            home: const WalkPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.timerTurnaround), findsNothing);
      expect(find.text(AppStrings.timerInactivity), findsNothing);
    });
  });
}
