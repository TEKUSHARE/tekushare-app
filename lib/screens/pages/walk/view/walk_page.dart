import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_spacing.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/constants/app_text_style.dart';
import 'package:tekushare/core/constants/map_constants.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/screens/pages/map/view/walk_route_page.dart';
import 'package:tekushare/screens/pages/settings/view/settings_page.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/pages/spot/view/want_to_go_page.dart';
import 'package:tekushare/screens/pages/walk/view/end_walk_page.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/walk_history_provider.dart';
import 'package:tekushare/screens/providers/walk_routes_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/providers/contact_provider.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/spot_provider.dart';
import 'package:tekushare/screens/providers/walk_timer_provider.dart';
import 'package:tekushare/screens/providers/walk_track_points_provider.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';
import 'package:tekushare/screens/widgets/common/clock_header.dart';
import 'package:tekushare/screens/widgets/common/primary_button.dart';

const _gpsTimeoutSeconds = 60;

/// 散歩モード画面
class WalkPage extends ConsumerStatefulWidget {
  const WalkPage({super.key});

  @override
  ConsumerState<WalkPage> createState() => _WalkPageState();
}

class _WalkPageState extends ConsumerState<WalkPage> {
  final _mapController = MapController();
  final _photoMarkers = <({LatLng point, String imagePath})>[];
  LatLng? _currentPosition;
  LatLng? _lastMovedPosition;
  double? _currentHeading;
  bool _mapControllerAttached = false;

  Timer? _tickTimer;
  Timer? _gpsTimeoutTimer;
  bool _isFiringNotifications = false;

  @override
  void initState() {
    super.initState();
    // プロバイダーへの書き込みはビルド完了後に行う（Riverpod の制約）
    Future.microtask(() {
      if (!mounted) return;
      final settings = ref.read(settingsViewModelProvider);
      ref.read(walkTimerProvider.notifier).initializeIfNeeded(
            timerEnabled: settings.timerEnabled,
            timerMinutes: settings.timerMinutes,
            timerRoundTrip: settings.timerRoundTrip,
            inactivityEnabled: settings.inactivityEnabled,
            inactivityMinutes: settings.inactivityMinutes,
          );
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), _onTick);
    _gpsTimeoutTimer = Timer(
      const Duration(seconds: _gpsTimeoutSeconds),
      _onGpsTimeout,
    );
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    ref.read(walkTimerProvider.notifier).tick();
    _fireNotificationsIfNeeded();
  }

  Future<void> _fireNotificationsIfNeeded() async {
    if (_isFiringNotifications) return;
    _isFiringNotifications = true;
    try {
      await _doFireNotifications();
    } finally {
      _isFiringNotifications = false;
    }
  }

  Future<void> _doFireNotifications() async {
    final svc = ref.read(notificationServiceProvider);
    final ts = ref.read(walkTimerProvider);
    // 往復タイマーの折り返し通知（全体の半分の時間になったとき）
    final midpoint = ts.midpointSeconds;
    if (midpoint != null &&
        ts.turnSecondsLeft == midpoint &&
        !ts.midpointFired) {
      ref.read(walkTimerProvider.notifier).markMidpointFired();
      await svc.showRoundTripNotification();
    }
    if (ts.turnSecondsLeft == 0 && !ts.turnFired) {
      ref.read(walkTimerProvider.notifier).markTurnFired();
      await svc.showTurnaroundNotification();
      _showTimerFinishedAlert();
    }
    if (ts.inactSecondsLeft == 0 && !ts.inactFired) {
      ref.read(walkTimerProvider.notifier).markInactFired();
      await svc.showInactivityNotification();
      _showSafetyConfirmDialog();
    }

    // 長時間散歩の監視（2h/4h/6h リマインド、7.5h 警告、8h 自動終了）
    final startedAt = ref.read(walkSessionProvider).startedAt;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      for (final hour in [2, 4, 6]) {
        if (elapsed.inHours >= hour && !ts.reminderHoursFired.contains(hour)) {
          ref.read(walkTimerProvider.notifier).markReminderFired(hour);
          await svc.showWalkReminderNotification(hour);
        }
      }
      if (elapsed.inSeconds >= 7 * 3600 + 30 * 60 && !ts.autoEndWarningFired) {
        ref.read(walkTimerProvider.notifier).markAutoEndWarningFired();
        await svc.showWalkAutoEndWarningNotification();
      }
      if (elapsed.inSeconds >= 8 * 3600 && !ts.autoEndFired) {
        ref.read(walkTimerProvider.notifier).markAutoEndFired();
        await _autoEndWalk();
      }
    }
  }

  Future<void> _autoEndWalk() async {
    if (!mounted) return;
    final session = ref.read(walkSessionProvider);
    final trackPoints = ref.read(walkTrackPointsProvider);
    final route = WalkRoute(
      id: session.id,
      walkSessionId: session.id,
      points: trackPoints,
      createdAt: DateTime.now(),
    );
    await ref.read(walkSessionProvider.notifier).endWalk(route);
    ref.invalidate(walkHistoryProvider);
    ref.invalidate(walkRoutesProvider);
    ref.read(walkSessionProvider.notifier).resetWalk();
    ref.read(walkTimerProvider.notifier).reset();
    await ref.read(notificationServiceProvider).showWalkAutoEndNotification();
  }

  void _showSafetyConfirmDialog() {
    if (!mounted) return;
    final settings = ref.read(settingsViewModelProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SafetyConfirmDialog(
        onSafe: () => ref
            .read(walkTimerProvider.notifier)
            .resetInact(settings.inactivityMinutes),
        onTimeout: _sendSafetyAlert,
      ),
    );
  }

  /// 通知先（SMS・Android のみ）と連携相手（プッシュ通知）へ安否通知を送り、
  /// 誰か一人にでも届いたかを返す
  Future<bool> _sendSafetyAlert() async {
    final contacts = ref.read(contactProvider).valueOrNull ?? [];
    final senderName =
        ref.read(authStateProvider).valueOrNull?.displayName ?? '';
    final result = await ref.read(sendSafetyAlertProvider)(
      contacts: contacts,
      senderName: senderName,
    );
    // 届いていないのに「送信しました」と表示しないよう、届いたときだけ通知する
    if (result.isDelivered) {
      await ref.read(notificationServiceProvider).showSmsSentNotification();
    }
    return result.isDelivered;
  }

  void _resetTimer() {
    final settings = ref.read(settingsViewModelProvider);
    ref.read(walkTimerProvider.notifier).resetTurn(settings.timerMinutes);
  }

  void _showTimerFinishedAlert() {
    if (!mounted) return;
    final ts = ref.read(walkTimerProvider);
    if (ts.turnAlertShown) return;
    ref.read(walkTimerProvider.notifier).markTurnAlertShown();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.timerFinishedTitle),
        content: const Text(AppStrings.timerFinishedMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _resetTimer();
            },
            child: const Text(AppStrings.timerReset),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.closeButton),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _gpsTimeoutTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onGpsTimeout() {
    if (!mounted || _currentPosition != null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.gpsTimeoutTitle),
        content: const Text(AppStrings.gpsTimeoutMessage),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              ref.read(notificationServiceProvider).cancelAll();
              ref.read(walkTimerProvider.notifier).reset();
              await ref.read(walkSessionProvider.notifier).resetWalk();
              if (mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            child: const Text(AppStrings.gpsTimeoutRetry),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.gpsTimeoutContinue),
          ),
        ],
      ),
    );
  }

  Future<void> _onTakePhotoPressed(
    BuildContext context,
    AsyncValue<Position> locationState,
  ) async {
    if (!locationState.hasValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.gpsUnavailableError)),
      );
      return;
    }

    final imagePath = await ref.read(cameraServiceProvider).takePhoto();
    if (imagePath == null || !context.mounted) return;

    ref.read(pendingPhotoProvider.notifier).update((l) => [...l, imagePath]);
    // _currentPosition は ref.listen の変化通知で更新されるため、
    // WalkPage 再生成直後など未更新の場合はプロバイダーのキャッシュを使う
    final rawPos = ref.read(locationProvider).valueOrNull;
    final pos = _currentPosition ??
        (rawPos != null ? LatLng(rawPos.latitude, rawPos.longitude) : null);
    if (pos != null) {
      setState(() {
        _photoMarkers.add((point: pos, imagePath: imagePath));
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.photoTaken)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // エラー時は _GpsStatusIndicator（ref.watch 側）がフィードバックを担う
    ref.listen<AsyncValue<Position>>(locationProvider, (_, next) {
      next.whenData((pos) {
        _gpsTimeoutTimer?.cancel();
        _gpsTimeoutTimer = null;
        final point = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentPosition = point;
          // heading < 0 は「取得不可」を示すので最後の有効値を維持する
          if (pos.heading >= 0) _currentHeading = pos.heading;
        });
        // 前回位置から一定距離以上動いた場合のみ不活動タイマーをリセット
        if (ref.read(walkTimerProvider).inactSecondsLeft != null) {
          final prev = _lastMovedPosition;
          final moved = prev == null ||
              const Distance().as(LengthUnit.Meter, prev, point) >=
                  MapConstants.inactivityMinMovementMeters;
          if (moved) {
            _lastMovedPosition = point;
            final settings = ref.read(settingsViewModelProvider);
            ref
                .read(walkTimerProvider.notifier)
                .resetInact(settings.inactivityMinutes);
          }
        }
        // MapController が準備済みの場合のみ move()
        if (_mapControllerAttached) {
          _mapController.move(point, _mapController.camera.zoom);
        }
      });
    });

    final locationState = ref.watch(locationProvider);
    final timerState = ref.watch(walkTimerProvider);
    final turnSeconds = timerState.turnSecondsLeft;
    final inactSeconds = timerState.inactSecondsLeft;
    // widget state がなくても locationProvider の最新値をフォールバックとして使用
    // → WalkPage 再生成時でもマップが即座に表示される
    final streamPos = locationState.valueOrNull;
    final mapCenter = _currentPosition ??
        (streamPos != null
            ? LatLng(streamPos.latitude, streamPos.longitude)
            : null);
    final sizing = AppSizingTheme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClockHeader(
                countdownSeconds: turnSeconds,
                onReset: turnSeconds != null ? _resetTimer : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              _GpsStatusIndicator(locationState: locationState),
              if (inactSeconds != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2l,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _WalkTimerChip(
                        label: AppStrings.timerInactivity,
                        icon: Icons.directions_walk,
                        seconds: inactSeconds,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: mapCenter != null
                        ? FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: mapCenter,
                              initialZoom: MapConstants.defaultZoom,
                              onMapReady: () => _mapControllerAttached = true,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: AppConfig.packageName,
                              ),
                              Builder(builder: (context) {
                                final pts = ref
                                    .watch(walkTrackPointsProvider)
                                    .map((p) => LatLng(p.latitude, p.longitude))
                                    .toList();
                                if (pts.length < 2) return const SizedBox();
                                return PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: pts,
                                      color: AppColors.primary,
                                      strokeWidth:
                                          MapConstants.polylineStrokeWidth,
                                    ),
                                  ],
                                );
                              }),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: mapCenter,
                                    width: AppSize.iconLg,
                                    height: AppSize.iconLg,
                                    child: Transform.rotate(
                                      angle: (_currentHeading ?? 0) *
                                          math.pi /
                                          180,
                                      child: SvgPicture.asset(
                                        'assets/SVG/foot2.svg',
                                        colorFilter: const ColorFilter.mode(
                                          AppColors.primary,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_photoMarkers.isNotEmpty)
                                MarkerLayer(
                                  markers: _photoMarkers
                                      .map(
                                        (m) => Marker(
                                          point: m.point,
                                          width:
                                              MapConstants.photoThumbnailSize,
                                          height:
                                              MapConstants.photoThumbnailSize,
                                          child: Stack(
                                            children: [
                                              ClipOval(
                                                child: Image.file(
                                                  File(m.imagePath),
                                                  width: MapConstants
                                                      .photoThumbnailSize,
                                                  height: MapConstants
                                                      .photoThumbnailSize,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const ColoredBox(
                                                    color:
                                                        AppColors.textDisabled,
                                                    child: Icon(
                                                      Icons.photo,
                                                      color: AppColors
                                                          .textOnPrimary,
                                                      size: AppSize.iconSm,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 0,
                                                right: 0,
                                                child: GestureDetector(
                                                  onTap: () => setState(() {
                                                    _photoMarkers.remove(m);
                                                  }),
                                                  child: Container(
                                                    width: MapConstants
                                                        .photoDeleteBadgeSize,
                                                    height: MapConstants
                                                        .photoDeleteBadgeSize,
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Colors.black54,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.close,
                                                      size: MapConstants
                                                          .photoDeleteIconSize,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  child: FloatingActionButton(
                                    heroTag: 'recenter',
                                    tooltip: AppStrings.recenterMap,
                                    onPressed: () {
                                      _mapController.move(
                                        mapCenter,
                                        MapConstants.defaultZoom,
                                      );
                                    },
                                    backgroundColor: AppColors.surface,
                                    foregroundColor: AppColors.primary,
                                    elevation: 2,
                                    child: const Icon(Icons.my_location),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  color: MapConstants.osmAttributionBg,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal:
                                        MapConstants.osmAttributionPaddingH,
                                    vertical:
                                        MapConstants.osmAttributionPaddingV,
                                  ),
                                  child: const Text(
                                    '© OpenStreetMap contributors',
                                    style: TextStyle(
                                      fontSize:
                                          MapConstants.osmAttributionFontSize,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2l,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _WalkActionButton(
                        label: AppStrings.takePhoto,
                        svgAsset: 'assets/SVG/camera.svg',
                        onPressed: () =>
                            _onTakePhotoPressed(context, locationState),
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _WalkActionButton(
                        label: AppStrings.wantToGo,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WantToGoPage(),
                          ),
                        ),
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2l,
                ),
                child: PrimaryButton(
                  label: AppStrings.endWalk,
                  height: sizing.largeBtnHeight,
                  onPressed: () {
                    ref.read(notificationServiceProvider).cancelAll();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EndWalkPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 0,
          onTap: (index) {
            if (index == 0) {
              // 散歩中はこの画面が「ホーム」なので何もしない
            } else if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SpotListPage()),
              );
            } else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalkRoutePage()),
              );
            } else if (index == 3) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            }
          },
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// GPS 状態インジケーター
// ──────────────────────────────────────────

class _GpsStatusIndicator extends StatelessWidget {
  const _GpsStatusIndicator({required this.locationState});

  final AsyncValue<Position> locationState;

  @override
  Widget build(BuildContext context) {
    return locationState.when(
      data: (_) => const SizedBox.shrink(),
      loading: () => const SizedBox(
        height: AppSize.gpsIndicatorHeight,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: AppSize.gpsSpinnerSize,
                height: AppSize.gpsSpinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: AppSize.gpsSpinnerStroke,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Text(
                AppStrings.gpsAcquiring,
                style: TextStyle(color: AppColors.textDisabled),
              ),
            ],
          ),
        ),
      ),
      error: (_, __) => const SizedBox(
        height: AppSize.gpsIndicatorHeight,
        child: Center(
          child: Text(
            AppStrings.gpsUnavailableError,
            style: TextStyle(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// タイマーチップ
// ──────────────────────────────────────────

class _WalkTimerChip extends StatelessWidget {
  const _WalkTimerChip({
    required this.label,
    required this.icon,
    required this.seconds,
  });

  final String label;
  final IconData icon;
  final int seconds;

  Color _color() {
    if (seconds < 60) return AppColors.error;
    if (seconds < 120) return AppColors.warning;
    return AppColors.primary;
  }

  String _formatted() {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSize.iconXs, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: AppSize.timerChipLabelFontSize,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _formatted(),
            style: TextStyle(
              fontSize: AppSize.timerChipCountFontSize,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// 散歩アクションボタン（ブラウン）
// ──────────────────────────────────────────

class _WalkActionButton extends StatelessWidget {
  const _WalkActionButton({
    required this.label,
    this.svgAsset,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final String? svgAsset;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sizing = AppSizingTheme.of(context);
    final height = compact ? sizing.detailBtnHeight : sizing.actionBtnHeight;
    final fontSize =
        compact ? sizing.detailBtnFontSize : sizing.actionBtnFontSize;
    final iconSize = compact ? AppSize.iconMd : sizing.actionBtnIconSize;
    final radius = compact ? sizing.detailBtnRadius : sizing.actionBtnRadius;

    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: AppColors.textAccent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 4),
            blurRadius: 4,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.textAccent,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: svgAsset != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: SvgPicture.asset(
                      svgAsset!,
                      width: iconSize,
                      height: iconSize,
                      colorFilter: const ColorFilter.mode(
                        AppColors.textOnPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// 安否確認ダイアログ（カウントダウン付き）
// ──────────────────────────────────────────

const _safetyGracePeriodSeconds = 60;

class _SafetyConfirmDialog extends StatefulWidget {
  const _SafetyConfirmDialog({
    required this.onSafe,
    required this.onTimeout,
  });

  final VoidCallback onSafe;

  /// 猶予時間が過ぎたときに安否通知を送り、届いたかどうかを返す
  final Future<bool> Function() onTimeout;

  @override
  State<_SafetyConfirmDialog> createState() => _SafetyConfirmDialogState();
}

class _SafetyConfirmDialogState extends State<_SafetyConfirmDialog> {
  late int _secondsLeft;
  Timer? _timer;
  // 猶予時間が過ぎて送信を終えたら、送信結果（届いたか）を入れる
  bool? _isAlertDelivered;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _safetyGracePeriodSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  Future<void> _onTick(Timer _) async {
    if (!mounted) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) {
      _timer?.cancel();
      final isDelivered = await widget.onTimeout();
      if (!mounted) return;
      setState(() => _isAlertDelivered = isDelivered);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text(AppStrings.safetyConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              switch (_isAlertDelivered) {
                null when _secondsLeft <= 0 =>
                  AppStrings.safetyAlertSendingBody,
                null => AppStrings.safetyConfirmBody,
                true => AppStrings.safetyAlertSentBody,
                false => AppStrings.safetyAlertFailedBody,
              },
            ),
            if (_isAlertDelivered == null && _secondsLeft > 0) ...[
              const SizedBox(height: AppSpacing.x2l),
              Text(
                '$_secondsLeft秒',
                style: const TextStyle(
                  fontSize: AppTextStyle.x3l,
                  fontWeight: AppTextStyle.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.of(context).pop();
                widget.onSafe();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text(AppStrings.safetyOk),
            ),
          ),
        ],
      ),
    );
  }
}
