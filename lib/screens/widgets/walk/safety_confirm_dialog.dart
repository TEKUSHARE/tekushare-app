import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_spacing.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/constants/app_text_style.dart';

// ──────────────────────────────────────────
// 安否確認ダイアログ（カウントダウン付き）
// ──────────────────────────────────────────

/// 安否確認で、応答がないときに通知を送るまでの猶予（秒）
const safetyGracePeriodSeconds = 60;

/// 動きがないときに表示する安否確認ダイアログ。
/// 猶予時間内に「元気です」が押されなければ [onTimeout] で安否通知を送る。
class SafetyConfirmDialog extends StatefulWidget {
  const SafetyConfirmDialog({
    super.key,
    required this.onSafe,
    required this.onTimeout,
  });

  /// 「元気です」が押されたとき
  final VoidCallback onSafe;

  /// 猶予時間が過ぎたときに安否通知を送り、届いたかどうかを返す
  final Future<bool> Function() onTimeout;

  @override
  State<SafetyConfirmDialog> createState() => _SafetyConfirmDialogState();
}

class _SafetyConfirmDialogState extends State<SafetyConfirmDialog> {
  late int _secondsLeft;
  Timer? _timer;
  // 猶予時間が過ぎて送信を終えたら、送信結果（届いたか）を入れる
  bool? _isAlertDelivered;

  @override
  void initState() {
    super.initState();
    _secondsLeft = safetyGracePeriodSeconds;
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
