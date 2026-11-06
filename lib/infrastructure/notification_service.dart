import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tekushare/core/constants/app_strings.dart';

class NotificationService {
  NotificationService._(this._plugin);

  static final NotificationService instance =
      NotificationService._(FlutterLocalNotificationsPlugin());

  @visibleForTesting
  factory NotificationService.forTest(
    FlutterLocalNotificationsPlugin plugin,
  ) =>
      NotificationService._(plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'tekushare_walk';
  static const _channelName = '散歩通知';

  static const _idInactivity = 1;
  static const _idTurnaround = 2;
  static const _idRoundTrip = 3;
  static const _idSmsSent = 4;
  static const _idWalkReminder = 5;
  static const _idWalkAutoEnd = 6;
  static const _idRemoteMessage = 7;
  // geolocator が startForeground で使う ID と同じにしてスロットを共有させる
  static const _idWalkOngoing = 75415;

  static const _walkOngoingChannelId = 'tekushare_walk_ongoing';
  static const _walkOngoingChannelName = '散歩記録中';

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  /// 長時間散歩中のリマインド通知を表示する
  Future<void> showWalkReminderNotification(int hours) async {
    await _plugin.show(
      id: _idWalkReminder,
      title: AppStrings.walkReminderNotificationTitle,
      body: AppStrings.walkReminderNotificationBody(hours),
      notificationDetails: _notificationDetails(),
    );
  }

  /// 自動終了30分前の警告通知を表示する
  Future<void> showWalkAutoEndWarningNotification() async {
    await _plugin.show(
      id: _idWalkAutoEnd,
      title: AppStrings.walkAutoEndWarningTitle,
      body: AppStrings.walkAutoEndWarningBody,
      notificationDetails: _notificationDetails(),
    );
  }

  /// 散歩が自動終了したことを通知する
  Future<void> showWalkAutoEndNotification() async {
    await _plugin.show(
      id: _idWalkAutoEnd,
      title: AppStrings.walkAutoEndNotificationTitle,
      body: AppStrings.walkAutoEndNotificationBody,
      notificationDetails: _notificationDetails(),
    );
  }

  /// SMS 送信後の通知を表示する（バックグラウンド時でも気づけるよう）
  Future<void> showSmsSentNotification() async {
    await _plugin.show(
      id: _idSmsSent,
      title: AppStrings.smsSentNotificationTitle,
      body: AppStrings.smsSentNotificationBody,
      notificationDetails: _notificationDetails(),
    );
  }

  /// アプリを開いている間に届いたプッシュ通知（連携相手の安否通知など）を表示する。
  /// Android は前面にいるとき FCM の通知を自動で表示しないため、ここで代わりに出す
  Future<void> showRemoteNotification({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: _idRemoteMessage,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(),
    );
  }

  /// 無動作時の安否確認通知を表示する
  Future<void> showInactivityNotification() async {
    await _plugin.show(
      id: _idInactivity,
      title: '大丈夫ですか？',
      body: '動きがありません。散歩を続けていますか？',
      notificationDetails: _notificationDetails(),
    );
  }

  /// 往復タイマーの折り返し通知を表示する
  Future<void> showRoundTripNotification() async {
    await _plugin.show(
      id: _idRoundTrip,
      title: AppStrings.timerRoundTripNotificationTitle,
      body: AppStrings.timerRoundTripNotificationBody,
      notificationDetails: _notificationDetails(),
    );
  }

  /// タイマー終了通知を表示する
  Future<void> showTurnaroundNotification() async {
    await _plugin.show(
      id: _idTurnaround,
      title: AppStrings.timerFinishedTitle,
      body: AppStrings.timerFinishedMessage,
      notificationDetails: _notificationDetails(),
    );
  }

  /// 散歩中の ongoing 通知を表示する。
  /// 通常通知（フォアグラウンドサービスとは別）のため Android 14 でも消せない。
  Future<void> showWalkOngoingNotification() async {
    await _plugin.show(
      id: _idWalkOngoing,
      title: AppStrings.walkForegroundNotificationTitle,
      body: AppStrings.walkForegroundNotificationBody,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _walkOngoingChannelId,
          _walkOngoingChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  /// 散歩中の ongoing 通知をキャンセルする
  Future<void> cancelWalkOngoingNotification() async {
    await _plugin.cancel(id: _idWalkOngoing);
  }

  /// 表示中の通知をすべてキャンセルする
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }
}
