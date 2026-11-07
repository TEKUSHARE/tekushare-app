import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:tekushare/core/constants/app_strings.dart';

class LocationService {
  static const _distanceFilterMeters = 3;

  /// iOS の一時的な正確な位置情報の要求で使う理由のキー
  /// （Info.plist の NSLocationTemporaryUsageDescriptionDictionary と一致させる）
  static const temporaryFullAccuracyPurposeKey = 'WalkRoute';

  /// パーミッション確認・リクエストを行い、現在地の Stream を返す。
  /// 精度を問わず届いた位置をすべて流す（記録に使うかは [RecordingPositionFilter] で判定する）。
  /// パーミッションが拒否された場合は例外をスローする。
  Stream<Position> rawPositionStream() async* {
    await _ensurePermission();
    await _requestFullAccuracyIfReduced();

    // 散歩2回目以降は distanceFilter により getPositionStream が初回位置を配信しない
    // ため、キャッシュ済みの最終位置を先に配信してマップ・GPS インジケーターを即時更新する。
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) yield last;
    } catch (_) {}

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: _distanceFilterMeters,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: AppStrings.walkForegroundNotificationTitle,
              notificationText: AppStrings.walkForegroundNotificationBody,
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: _distanceFilterMeters,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );

    yield* Geolocator.getPositionStream(locationSettings: settings);
  }

  /// 「正確な位置情報」がオンか（iOS 14 以降・Android 12 以降で、大まかな位置だけを許可されていると false）
  Future<bool> isPreciseLocationEnabled() async {
    try {
      final status = await Geolocator.getLocationAccuracy();
      return status != LocationAccuracyStatus.reduced;
    } catch (_) {
      // 判定できない端末では、正確な位置情報が使える前提で扱う
      return true;
    }
  }

  /// 端末の設定画面（このアプリの位置情報の設定）を開く
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// iOS で「正確な位置情報」がオフなら、散歩中だけ正確な位置を使えるよう一時的に求める。
  /// オフのままだと誤差が数km の位置しか届かず、ルートを記録できないため。
  Future<void> _requestFullAccuracyIfReduced() async {
    if (!Platform.isIOS) return;
    try {
      if (await isPreciseLocationEnabled()) return;
      await Geolocator.requestTemporaryFullAccuracy(
        purposeKey: temporaryFullAccuracyPurposeKey,
      );
    } catch (_) {
      // 求められなくても大まかな位置で表示は続ける（案内は画面側で出す）
    }
  }

  /// 現在地を一度だけ取得する。
  Future<Position> getCurrentPosition() async {
    await _ensurePermission();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
  }

  Future<void> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw PermissionDeniedException(permission.toString());
    }
  }
}
