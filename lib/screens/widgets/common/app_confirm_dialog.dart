import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_spacing.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/constants/app_text_style.dart';

/// キャンセル＋確認ボタンを持つ汎用ダイアログ。
///
/// - [title] を渡すと本文上部に primary 色の見出しを表示する。
/// - [isDestructive] が true のとき確認ボタンを赤色にする。
/// - [confirmColor] を渡すと [isDestructive] より優先してその色を使う。
/// - [onConfirm] は同期・非同期どちらでも可。非同期の場合は完了まで
///   確認ボタンを無効化する。
class AppConfirmDialog extends StatefulWidget {
  const AppConfirmDialog({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.title,
    this.isDestructive = false,
    this.confirmColor,
  });

  final String? title;
  final String message;
  final String confirmLabel;
  final bool isDestructive;
  final Color? confirmColor;
  final FutureOr<void> Function() onConfirm;
  final VoidCallback onCancel;

  @override
  State<AppConfirmDialog> createState() => _AppConfirmDialogState();
}

class _AppConfirmDialogState extends State<AppConfirmDialog> {
  bool _processing = false;

  Color get _confirmColor {
    if (widget.confirmColor != null) return widget.confirmColor!;
    return widget.isDestructive ? Colors.red.shade400 : AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4l,
        vertical: AppSpacing.x2l,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2l,
          AppSpacing.x3l,
          AppSpacing.x2l,
          AppSpacing.x2l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null) ...[
              Text(
                widget.title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: AppTextStyle.lg2,
                  fontWeight: AppTextStyle.semiBold,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: AppTextStyle.md),
            ),
            const SizedBox(height: AppSpacing.x2l),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.x5l,
                    child: OutlinedButton(
                      onPressed: _processing ? null : widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        side: const BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: const Text(AppStrings.cancelButton),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.x5l,
                    child: ElevatedButton(
                      onPressed: _processing
                          ? null
                          : () async {
                              setState(() => _processing = true);
                              try {
                                await widget.onConfirm();
                              } catch (e) {
                                // エラー表示は呼び出し側の責務。ここでは操作不能にならないことだけを保証する
                                debugPrint('確認ダイアログの処理で例外が発生しました: $e');
                              } finally {
                                // 失敗しても処理中のまま操作できなくならないよう、必ず戻す
                                if (mounted) {
                                  setState(() => _processing = false);
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        backgroundColor: _confirmColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: Text(widget.confirmLabel),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
