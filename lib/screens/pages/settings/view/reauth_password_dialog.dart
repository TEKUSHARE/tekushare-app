import 'package:flutter/material.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_strings.dart';

/// アカウント消去の前に、再認証のためパスワードを入力してもらうダイアログ。
/// 入力されたパスワードを返す。キャンセル時は null。
class ReauthPasswordDialog extends StatefulWidget {
  const ReauthPasswordDialog({super.key});

  /// ダイアログを表示し、入力されたパスワードを返す
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ReauthPasswordDialog(),
    );
  }

  @override
  State<ReauthPasswordDialog> createState() => _ReauthPasswordDialogState();
}

class _ReauthPasswordDialogState extends State<ReauthPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.settingsReauthTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(AppStrings.settingsReauthMessage),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: AppStrings.settingsReauthPasswordLabel,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancelButton),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text(AppStrings.settingsReauthConfirmButton),
        ),
      ],
    );
  }
}
