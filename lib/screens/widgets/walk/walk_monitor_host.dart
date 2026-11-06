import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/providers/contact_provider.dart';
import 'package:tekushare/screens/providers/walk_monitor_provider.dart';
import 'package:tekushare/screens/providers/walk_timer_provider.dart';
import 'package:tekushare/screens/widgets/walk/safety_confirm_dialog.dart';

/// 散歩中の監視（[walkMonitorProvider]）をアプリ全体で動かし続け、
/// タイマー終了・安否確認のダイアログを、どの画面を開いていても表示する。
///
/// MaterialApp.builder で Navigator の外側に置くため、ダイアログは
/// [navigatorKey] の Navigator に対して表示する。
class WalkMonitorHost extends ConsumerStatefulWidget {
  const WalkMonitorHost({
    super.key,
    required this.navigatorKey,
    required this.isEnabled,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  /// 端末内 DB の初期化とログインが済んでいるか。済むまでは監視を始めない
  /// （散歩の記録は DB を使うため）。
  /// ウィジェットを付け外しすると配下の Navigator が作り直されるため、
  /// 常に置いたままこのフラグで切り替える。
  final bool isEnabled;
  final Widget child;

  @override
  ConsumerState<WalkMonitorHost> createState() => _WalkMonitorHostState();
}

class _WalkMonitorHostState extends ConsumerState<WalkMonitorHost> {
  StreamSubscription<WalkMonitorEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    if (widget.isEnabled) _subscribe();
  }

  @override
  void didUpdateWidget(WalkMonitorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled && _eventSub == null) _subscribe();
    if (!widget.isEnabled) _unsubscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    _eventSub = ref.read(walkMonitorProvider).events.listen(_onEvent);
  }

  void _unsubscribe() {
    _eventSub?.cancel();
    _eventSub = null;
  }

  BuildContext? get _navigatorContext => widget.navigatorKey.currentContext;

  void _onEvent(WalkMonitorEvent event) {
    switch (event) {
      case WalkMonitorEvent.timerFinished:
        _showTimerFinishedAlert();
      case WalkMonitorEvent.inactivityDetected:
        _showSafetyConfirmDialog();
    }
  }

  void _resetTimer() {
    final settings = ref.read(settingsViewModelProvider);
    ref.read(walkTimerProvider.notifier).resetTurn(settings.timerMinutes);
  }

  void _showTimerFinishedAlert() {
    final navContext = _navigatorContext;
    if (navContext == null) return;
    final ts = ref.read(walkTimerProvider);
    if (ts.turnAlertShown) return;
    ref.read(walkTimerProvider.notifier).markTurnAlertShown();
    showDialog<void>(
      context: navContext,
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

  void _showSafetyConfirmDialog() {
    final navContext = _navigatorContext;
    if (navContext == null) return;
    final settings = ref.read(settingsViewModelProvider);
    showDialog<void>(
      context: navContext,
      barrierDismissible: false,
      builder: (_) => SafetyConfirmDialog(
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

  @override
  Widget build(BuildContext context) {
    // 監視を常に生かしておく（散歩中ステータスに連動して自動で開始・停止する）
    if (widget.isEnabled) ref.watch(walkMonitorProvider);
    return widget.child;
  }
}
