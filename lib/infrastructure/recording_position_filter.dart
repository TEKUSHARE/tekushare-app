import 'package:geolocator/geolocator.dart';

/// ルートの記録・見守り・スポットの保存に使ってよい精度の位置かを判定する。
///
/// 誤差の大きい位置をルートに入れると線が乱れるため、誤差 [maxAccuracyMeters] 以内だけを採用する。
/// ただし一定時間良い位置が来ないときは、誤差 [fallbackAccuracyMeters] 以内まで緩める。
/// 画面の現在地表示には、この判定を通さない位置も使ってよい。
class RecordingPositionFilter {
  RecordingPositionFilter({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// 通常の精度のしきい値
  static const maxAccuracyMeters = 30.0;

  /// 良い位置が来ないときに緩めるしきい値
  static const fallbackAccuracyMeters = 50.0;

  /// しきい値を緩めるまでの時間
  static const fallbackTimeout = Duration(seconds: 10);

  final DateTime Function() _now;
  DateTime? _lastAcceptedAt;

  /// [pos] を記録に使ってよければ true
  bool accept(Position pos) {
    final now = _now();
    final last = _lastAcceptedAt;
    final sinceLastAccept =
        last == null ? fallbackTimeout : now.difference(last);
    final isAccepted = pos.accuracy <= maxAccuracyMeters ||
        sinceLastAccept >= fallbackTimeout &&
            pos.accuracy <= fallbackAccuracyMeters;
    if (isAccepted) _lastAcceptedAt = now;
    return isAccepted;
  }
}
