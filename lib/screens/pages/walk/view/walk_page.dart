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
import 'package:tekushare/core/constants/map_constants.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/screens/pages/map/view/walk_route_page.dart';
import 'package:tekushare/screens/pages/settings/view/settings_page.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/pages/spot/view/want_to_go_page.dart';
import 'package:tekushare/screens/pages/walk/view/end_walk_page.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
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
  double? _currentHeading;
  bool _mapControllerAttached = false;

  // タイマー・見守り（不活動の検知）・長時間散歩の監視は、画面を移っても止まらないよう
  // WalkMonitor（walkMonitorProvider）が行う
  Timer? _gpsTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _gpsTimeoutTimer = Timer(
      const Duration(seconds: _gpsTimeoutSeconds),
      _onGpsTimeout,
    );
  }

  void _resetTimer() {
    final settings = ref.read(settingsViewModelProvider);
    ref.read(walkTimerProvider.notifier).resetTurn(settings.timerMinutes);
  }

  @override
  void dispose() {
    _gpsTimeoutTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _onGpsTimeout() async {
    // 記録に使える精度の位置がすでに届いていれば何もしない
    if (!mounted || ref.read(locationProvider).hasValue) return;
    final hint = await _gpsTimeoutHint();
    if (!mounted || ref.read(locationProvider).hasValue) return;
    final isPreciseOff = hint == AppStrings.gpsTimeoutPreciseOffHint;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.gpsTimeoutTitle),
        content: Text(
          hint == null
              ? AppStrings.gpsTimeoutMessage
              : '${AppStrings.gpsTimeoutMessage}\n\n$hint',
        ),
        actions: [
          if (isPreciseOff)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                ref.read(locationServiceProvider).openAppSettings();
              },
              child: const Text(AppStrings.gpsOpenSettings),
            ),
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

  /// 位置を取得できない原因の案内。分からなければ null
  Future<String?> _gpsTimeoutHint() async {
    final isPrecise =
        await ref.read(locationServiceProvider).isPreciseLocationEnabled();
    if (!isPrecise) return AppStrings.gpsTimeoutPreciseOffHint;
    // 位置は届いているが精度が足りない（屋内など）
    if (ref.read(rawLocationProvider).hasValue) {
      return AppStrings.gpsTimeoutIndoorHint;
    }
    return null;
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
    // 記録に使える精度の位置が届いたら、GPS タイムアウトの案内は不要
    ref.listen<AsyncValue<Position>>(locationProvider, (_, next) {
      if (!next.hasValue) return;
      _gpsTimeoutTimer?.cancel();
      _gpsTimeoutTimer = null;
    });
    // 現在地の表示には、精度の低い位置も使う（屋内などでも地図を出すため）
    ref.listen<AsyncValue<Position>>(rawLocationProvider, (_, next) {
      next.whenData((pos) {
        final point = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _currentPosition = point;
          // heading < 0 は「取得不可」を示すので最後の有効値を維持する
          if (pos.heading >= 0) _currentHeading = pos.heading;
        });
        // MapController が準備済みの場合のみ move()
        if (_mapControllerAttached) {
          _mapController.move(point, _mapController.camera.zoom);
        }
      });
    });

    final locationState = ref.watch(locationProvider);
    final rawLocationState = ref.watch(rawLocationProvider);
    final timerState = ref.watch(walkTimerProvider);
    final turnSeconds = timerState.turnSecondsLeft;
    final inactSeconds = timerState.inactSecondsLeft;
    // widget state がなくても locationProvider の最新値をフォールバックとして使用
    // → WalkPage 再生成時でもマップが即座に表示される
    final streamPos = rawLocationState.valueOrNull ?? locationState.valueOrNull;
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
              _GpsStatusIndicator(
                locationState: locationState,
                rawLocationState: rawLocationState,
              ),
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
  const _GpsStatusIndicator({
    required this.locationState,
    required this.rawLocationState,
  });

  /// ルートの記録に使える精度の位置
  final AsyncValue<Position> locationState;

  /// 精度を問わない位置（記録には使えない誤差の大きい位置も含む）
  final AsyncValue<Position> rawLocationState;

  @override
  Widget build(BuildContext context) {
    if (locationState.hasValue) return const SizedBox.shrink();
    final rawError = rawLocationState.error ?? locationState.error;
    if (rawError != null) {
      return const SizedBox(
        height: AppSize.gpsIndicatorHeight,
        child: Center(
          child: Text(
            AppStrings.gpsUnavailableError,
            style: TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    final rawPos = rawLocationState.valueOrNull;
    return SizedBox(
      height: AppSize.gpsIndicatorHeight,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: AppSize.gpsSpinnerSize,
              height: AppSize.gpsSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: AppSize.gpsSpinnerStroke,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                rawPos == null
                    ? AppStrings.gpsAcquiring
                    : AppStrings.gpsLowAccuracy(rawPos.accuracy.round()),
                style: const TextStyle(color: AppColors.textDisabled),
                textAlign: TextAlign.center,
              ),
            ),
          ],
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
