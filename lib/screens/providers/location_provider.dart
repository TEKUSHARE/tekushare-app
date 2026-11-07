import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/infrastructure/location_service.dart';
import 'package:tekushare/infrastructure/recording_position_filter.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// 散歩中に届いた位置を、精度を問わずすべて流す（画面の現在地表示用）。
/// 非歩行中（idle / finished）は Stream.empty() を返す。
///
/// 屋内や「正確な位置情報」がオフのときは誤差の大きい位置しか届かないが、
/// それも表示に使うことで「GPS取得中」のまま止まって見えないようにする。
final rawLocationProvider = StreamProvider.autoDispose<Position>((ref) {
  final status = ref.watch(walkSessionProvider.select((s) => s.status));
  if (status != WalkStatus.walking) {
    return const Stream.empty();
  }
  // 散歩中は他タブに移動しても GPS ストリームを継続する。
  // 散歩終了（status 変化）でプロバイダーが再評価される際に keepAlive は自動解除される。
  ref.keepAlive();
  return ref.watch(locationServiceProvider).rawPositionStream();
});

/// 散歩中の位置のうち、ルートの記録・見守り・スポットの保存に使える精度のものだけを流す
/// （[RecordingPositionFilter] で判定）。
/// 散歩中は WalkPage が非表示でも Stream を維持するため keepAlive を使用する。
final locationProvider = StreamProvider.autoDispose<Position>((ref) {
  final status = ref.watch(walkSessionProvider.select((s) => s.status));
  if (status != WalkStatus.walking) {
    return const Stream.empty();
  }
  ref.keepAlive();

  // GPS の購読は rawLocationProvider の1本だけにし、ここでは精度で絞り込む
  final controller = StreamController<Position>();
  final filter = RecordingPositionFilter();
  ref.listen<AsyncValue<Position>>(
    rawLocationProvider,
    (_, next) {
      if (controller.isClosed) return;
      next.when(
        data: (pos) {
          if (filter.accept(pos)) controller.add(pos);
        },
        error: controller.addError,
        loading: () {},
      );
    },
    fireImmediately: true,
  );
  ref.onDispose(controller.close);
  return controller.stream;
});
