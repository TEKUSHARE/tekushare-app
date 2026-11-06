import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekushare/domain/entities/lat_lng.dart' as domain;
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/location_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';

/// 散歩中に蓄積した GPS トラックポイントを保持するプロバイダー。
/// 散歩中でない場合は空リストを返し、散歩終了や別ページへの遷移があっても
/// ウォーキング中はデータが消えない。
///
/// アプリが終了されても記録途中のルートが失われないよう、端末内
/// （SharedPreferences）に途中保存し、同じ散歩が復元されたときに読み戻す。
class WalkTrackPointsNotifier extends Notifier<List<domain.LatLng>> {
  /// 途中保存のキー。`{"walkId": "...", "points": [[lat, lng], ...]}` の形で保存する
  @visibleForTesting
  static const storageKey = 'walk_track_points';

  // GPS は数メートルごとに届くため、毎回ルート全体を書き込まないよう間隔を空ける
  static const _saveInterval = Duration(seconds: 10);

  String? _walkId;
  DateTime? _lastSavedAt;
  Timer? _saveTimer;
  AppLifecycleListener? _lifecycleListener;

  SharedPreferences? get _prefs => ref.read(sharedPrefsProvider).valueOrNull;

  @override
  List<domain.LatLng> build() {
    final session = ref.watch(
      walkSessionProvider.select((s) => (status: s.status, id: s.id)),
    );
    _saveTimer?.cancel();
    _lastSavedAt = null;
    if (session.status != WalkStatus.walking) {
      _walkId = null;
      // 散歩が終わったら途中保存は不要
      unawaited(_prefs?.remove(storageKey));
      return [];
    }
    _walkId = session.id;

    // バックグラウンドに回るとき（iOS はそのまま終了されることがある）に保存する
    _lifecycleListener = AppLifecycleListener(
      onInactive: flush,
      onHide: flush,
      onPause: flush,
      onDetach: flush,
    );
    ref.onDispose(() {
      _saveTimer?.cancel();
      _lifecycleListener?.dispose();
      _lifecycleListener = null;
    });

    final restored = _restore(session.id);

    // プロバイダー初期化時点で locationProvider がすでに GPS 位置を持っている場合
    // （FlutterMap が表示されてから本プロバイダーが初めてアクセスされるケース）は
    // キャッシュ値を初期点として取り込む。
    final cached = ref.read(locationProvider).valueOrNull;
    final initial = [...restored];
    if (cached != null) {
      final p = domain.LatLng(cached.latitude, cached.longitude);
      if (initial.isEmpty || initial.last != p) initial.add(p);
    }

    ref.listen<AsyncValue<Position>>(locationProvider, (_, next) {
      next.whenData((pos) {
        final p = domain.LatLng(pos.latitude, pos.longitude);
        // 直前の点と重複する場合は追加しない
        if (state.isNotEmpty && state.last == p) return;
        state = [...state, p];
        _scheduleSave();
      });
    });

    return initial;
  }

  /// 途中保存をすぐに書き込む
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final walkId = _walkId;
    final prefs = _prefs;
    if (walkId == null || prefs == null) return;
    _lastSavedAt = DateTime.now();
    final json = jsonEncode({
      'walkId': walkId,
      'points': [
        for (final p in state) [p.latitude, p.longitude],
      ],
    });
    unawaited(prefs.setString(storageKey, json));
  }

  void _scheduleSave() {
    final last = _lastSavedAt;
    final now = DateTime.now();
    if (last == null || now.difference(last) >= _saveInterval) {
      flush();
      return;
    }
    if (_saveTimer != null) return;
    _saveTimer = Timer(_saveInterval - now.difference(last), flush);
  }

  List<domain.LatLng> _restore(String walkId) {
    final raw = _prefs?.getString(storageKey);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // 別の散歩の記録は読み戻さない
      if (data['walkId'] != walkId) return [];
      final points = data['points'] as List<dynamic>;
      return [
        for (final p in points)
          domain.LatLng(
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ),
      ];
    } catch (e) {
      debugPrint('途中保存したルートを読み込めませんでした: $e');
      return [];
    }
  }
}

final walkTrackPointsProvider =
    NotifierProvider<WalkTrackPointsNotifier, List<domain.LatLng>>(
  WalkTrackPointsNotifier.new,
);
