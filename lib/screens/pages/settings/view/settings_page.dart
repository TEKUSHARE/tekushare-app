import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_spacing.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/constants/app_text_style.dart';
import 'package:tekushare/domain/entities/contact.dart';
import 'package:tekushare/screens/pages/map/view/walk_route_page.dart';
import 'package:tekushare/screens/pages/settings/view/linked_account_detail_page.dart';
import 'package:tekushare/screens/pages/settings/view/phone_register_page.dart';
import 'package:tekushare/screens/pages/settings/view/reauth_password_dialog.dart';
import 'package:tekushare/screens/providers/account_link_provider.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/auth_provider.dart';
import 'package:tekushare/screens/providers/contact_provider.dart';
import 'package:tekushare/screens/providers/walk_session_provider.dart';
import 'package:tekushare/screens/pages/settings/viewmodel/settings_viewmodel.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';
import 'package:tekushare/screens/widgets/common/app_confirm_dialog.dart';

/// 設定画面
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  void _openPhoneRegisterPage({Contact? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhoneRegisterPage(existing: existing),
      ),
    );
  }

  void _showContactsDialog(List<Contact> contacts) {
    showDialog<void>(
      context: context,
      builder: (_) => _ContactsListDialog(
        contacts: contacts,
        onEdit: (c) {
          Navigator.pop(context);
          _openPhoneRegisterPage(existing: c);
        },
        onAdd: () {
          Navigator.pop(context);
          _openPhoneRegisterPage();
        },
      ),
    );
  }

  void _showLogoutConfirmDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AppConfirmDialog(
        message: AppStrings.settingsLogoutConfirmMessage,
        confirmLabel: AppStrings.settingsLogoutConfirmButton,
        isDestructive: false,
        onConfirm: () {
          ref.read(walkSessionProvider.notifier).resetWalk();
          ref.invalidate(settingsViewModelProvider);
          ref.read(authServiceProvider).signOut();
          Navigator.popUntil(context, (route) => route.isFirst);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  /// アカウントを削除する。最後のログインから時間が経っていて再認証を求められたら、
  /// パスワードを入力してもらって再認証し、もう一度削除する。
  /// 削除できたら true。失敗・キャンセル時はメッセージを出して false。
  Future<bool> _deleteAccountWithReauth() async {
    final auth = ref.read(authServiceProvider);
    try {
      await auth.deleteUser();
      return true;
    } on AuthException catch (e) {
      if (e.code != 'requires-recent-login') {
        _showDeleteError(authErrorMessage(e.code));
        return false;
      }
    } catch (e) {
      debugPrint('アカウントの削除に失敗しました: $e');
      _showDeleteError(AppStrings.settingsDeleteAccountError);
      return false;
    }

    if (!mounted) return false;
    final password = await ReauthPasswordDialog.show(context);
    if (password == null) return false;
    try {
      await auth.reauthenticateWithPassword(password);
      await auth.deleteUser();
      return true;
    } on AuthException catch (e) {
      _showDeleteError(authErrorMessage(e.code));
      return false;
    } catch (e) {
      debugPrint('再認証後のアカウント削除に失敗しました: $e');
      _showDeleteError(AppStrings.settingsDeleteAccountError);
      return false;
    }
  }

  void _showDeleteError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showDeleteAccountConfirmDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AppConfirmDialog(
        message: AppStrings.settingsDeleteAccountConfirmMessage,
        confirmLabel: AppStrings.settingsDeleteAccountConfirmButton,
        isDestructive: true,
        onConfirm: () async {
          // 削除に成功するとログイン状態が変わり画面が破棄されうるため、先に取得しておく
          final uid = ref.read(authStateProvider).valueOrNull?.uid;
          final cleaner = ref.read(localDataCleanerProvider);
          final walkSession = ref.read(walkSessionProvider.notifier);
          final isDeleted = await _deleteAccountWithReauth();
          if (!isDeleted) return;
          // アカウント削除に成功した後で端末内データを消す（失敗時に記録が消えないように）
          await walkSession.resetWalk();
          if (uid != null) await cleaner.deleteUserData(uid);
          if (!mounted) return;
          Navigator.popUntil(context, (route) => route.isFirst);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsViewModelProvider);
    final vm = ref.read(settingsViewModelProvider.notifier);
    final contacts = ref.watch(contactProvider).value ?? [];
    final isSmsSupported = ref.watch(isSmsSupportedProvider);
    final linkedCount =
        ref.watch(linkedAccountsProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(AppStrings.settingsTitle),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.lg),
              _TimerCard(state: state, vm: vm),
              const SizedBox(height: AppSpacing.x2lp),
              _InactivityCard(
                state: state,
                vm: vm,
                contacts: contacts,
                isSmsSupported: isSmsSupported,
                linkedCount: linkedCount,
                onAddContact: () => _openPhoneRegisterPage(),
                onShowContacts: () => _showContactsDialog(contacts),
              ),
              const SizedBox(height: AppSpacing.x2lp),
              _ShareCard(state: state, vm: vm),
              const SizedBox(height: AppSpacing.x2lp),
              _AccountCard(
                onLogout: _showLogoutConfirmDialog,
                onDeleteAccount: _showDeleteAccountConfirmDialog,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () async {
                  final uri = Uri.parse(AppStrings.privacyPolicyUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  AppStrings.settingsPrivacyPolicy,
                  style: TextStyle(
                    fontSize: AppTextStyle.xs,
                    color: AppColors.textDisabled,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTap: (index) {
          if (index == 0) {
            Navigator.popUntil(context, (route) => route.isFirst);
          } else if (index == 1) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const SpotListPage()),
              (route) => route.isFirst,
            );
          } else if (index == 2) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const WalkRoutePage()),
              (route) => route.isFirst,
            );
          }
        },
      ),
    );
  }
}

// ──────────────────────────────────────────
// カード共通コンテナ
// ──────────────────────────────────────────

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: AppSpacing.sm,
            offset: const Offset(0, AppSpacing.xs),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ──────────────────────────────────────────
// 片道/往復 セグメントボタン
// ──────────────────────────────────────────

class _SegmentButtons extends StatelessWidget {
  const _SegmentButtons({required this.roundTrip, required this.onToggle});

  final bool roundTrip;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentBtn(
          label: AppStrings.oneWay,
          isSelected: !roundTrip,
          onTap: () => onToggle(false),
        ),
        _SegmentBtn(
          label: AppStrings.settingsTimerRoundTrip,
          isSelected: roundTrip,
          onTap: () => onToggle(true),
        ),
      ],
    );
  }
}

class _SegmentBtn extends StatelessWidget {
  const _SegmentBtn({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sizing = AppSizingTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: sizing.segmentBtnWidth,
        height: AppSize.segmentBtnH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xxs),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: AppSpacing.xs,
                    offset: const Offset(0, AppSpacing.xs),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyle.md,
            color: isSelected ? AppColors.primary : AppColors.textDisabled,
            fontWeight: isSelected ? AppTextStyle.medium : AppTextStyle.regular,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// 時間ドロップダウン
// ──────────────────────────────────────────

class _MinutePicker extends StatefulWidget {
  const _MinutePicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  State<_MinutePicker> createState() => _MinutePickerState();
}

class _MinutePickerState extends State<_MinutePicker> {
  void _showPicker() {
    final initialIndex = widget.options
        .indexOf(widget.value)
        .clamp(0, widget.options.length - 1);
    final controller = FixedExtentScrollController(initialItem: initialIndex);
    var selected = widget.value;

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: AppSize.pickerSheetH,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    widget.onChanged(selected);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    AppStrings.pickerDone,
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController: controller,
                  itemExtent: AppSize.pickerItemH,
                  onSelectedItemChanged: (index) {
                    selected = widget.options[index];
                  },
                  children: widget.options
                      .map(
                        (m) => Center(
                          child: Text(
                            '$m${AppStrings.minuteSuffix}',
                            style: const TextStyle(fontSize: AppTextStyle.lg),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showPicker,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.value}${AppStrings.minuteSuffix}',
            style: const TextStyle(
              fontSize: AppTextStyle.md2,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: AppSize.pickerGap),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1.0, 1.5, 1.0),
            child: const Icon(
              Icons.arrow_drop_down,
              color: Colors.black,
              size: AppSize.iconXl,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// タイマーカード
// ──────────────────────────────────────────

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.state, required this.vm});

  final SettingsState state;
  final SettingsViewModel vm;

  static final _timerOptions = List.generate(24, (i) => (i + 1) * 5);

  @override
  Widget build(BuildContext context) {
    return _SettingCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSize.timerCardPaddingH,
        vertical: AppSize.timerCardPaddingV,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SvgPicture.asset(
                  'assets/SVG/hourglass.svg',
                  width: AppSize.iconXs,
                  height: AppSize.iconMd,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsTimerTitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.lg2,
                        fontWeight: AppTextStyle.semiBold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      AppStrings.settingsTimerSubtitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.xxs,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              _SegmentButtons(
                roundTrip: state.timerRoundTrip,
                onToggle: vm.setTimerRoundTrip,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _CustomSwitch(
                value: state.timerEnabled,
                onChanged: vm.setTimerEnabled,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                state.timerEnabled ? AppStrings.switchOn : AppStrings.switchOff,
                style: TextStyle(
                  fontSize: AppTextStyle.md2,
                  fontWeight: AppTextStyle.bold,
                  color: state.timerEnabled
                      ? AppColors.primary
                      : AppColors.textDisabled,
                ),
              ),
              const Spacer(),
              _MinutePicker(
                value: state.timerMinutes,
                options: _timerOptions,
                onChanged: vm.setTimerMinutes,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// 安否確認カード
// ──────────────────────────────────────────

class _InactivityCard extends StatelessWidget {
  const _InactivityCard({
    required this.state,
    required this.vm,
    required this.contacts,
    required this.isSmsSupported,
    required this.linkedCount,
    required this.onAddContact,
    required this.onShowContacts,
  });

  final SettingsState state;
  final SettingsViewModel vm;
  final List<Contact> contacts;

  /// SMS の通知先を使えるか（Android のみ）。iOS では連携相手へのプッシュ通知だけで知らせる
  final bool isSmsSupported;

  /// 連携相手の人数（プッシュ通知の届け先）
  final int linkedCount;
  final VoidCallback onAddContact;
  final VoidCallback onShowContacts;

  static final _inactivityOptions = List.generate(8, (i) => (i + 1) * 15);

  @override
  Widget build(BuildContext context) {
    return _SettingCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSize.timerCardPaddingH,
        vertical: AppSize.timerCardPaddingV,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SvgPicture.asset(
                  'assets/SVG/heart.svg',
                  width: AppSize.iconXs,
                  height: AppSize.iconMd,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsInactivityTitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.lg2,
                        fontWeight: AppTextStyle.semiBold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      AppStrings.settingsInactivitySubtitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.xxs,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isSmsSupported)
                GestureDetector(
                  onTap: contacts.isEmpty ? onAddContact : onShowContacts,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: SvgPicture.asset(
                          'assets/SVG/phone.svg',
                          width: AppSize.iconLg,
                          height: AppSize.iconLg,
                        ),
                      ),
                      const SizedBox(width: AppSize.phoneIconGap),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            AppStrings.settingsInactivityContact,
                            style: TextStyle(
                              fontSize: AppTextStyle.xs,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            contacts.isEmpty
                                ? AppStrings.settingsInactivityContactSet
                                : '${contacts.length}件登録中',
                            style: const TextStyle(
                              fontSize: AppTextStyle.sm2,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: AppSpacing.lg),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _CustomSwitch(
                value: state.inactivityEnabled,
                onChanged: (v) async {
                  if (v && isSmsSupported) {
                    final status = await Permission.sms.request();
                    if (status.isPermanentlyDenied) {
                      await openAppSettings();
                    }
                    if (!status.isGranted) return;
                  }
                  vm.setInactivityEnabled(v);
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                state.inactivityEnabled
                    ? AppStrings.switchOn
                    : AppStrings.switchOff,
                style: TextStyle(
                  fontSize: AppTextStyle.md2,
                  fontWeight: AppTextStyle.bold,
                  color: state.inactivityEnabled
                      ? AppColors.primary
                      : AppColors.textDisabled,
                ),
              ),
              const Spacer(),
              _MinutePicker(
                value: state.inactivityMinutes,
                options: _inactivityOptions,
                onChanged: vm.setInactivityMinutes,
              ),
            ],
          ),
          // Android で SMS の通知先を登録済みなら SMS で届くため、未連携でも案内しない
          if (linkedCount > 0 || !isSmsSupported || contacts.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              linkedCount > 0
                  ? AppStrings.settingsInactivityPushNote(linkedCount)
                  : AppStrings.settingsInactivityNoLinkNote,
              style: TextStyle(
                fontSize: AppTextStyle.xxs,
                color:
                    linkedCount > 0 ? AppColors.textDisabled : AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// 連絡先一覧ダイアログ
// ──────────────────────────────────────────

class _ContactsListDialog extends StatelessWidget {
  const _ContactsListDialog({
    required this.contacts,
    required this.onEdit,
    required this.onAdd,
  });

  final List<Contact> contacts;
  final void Function(Contact) onEdit;
  final VoidCallback onAdd;

  static const _maxContacts = 5;

  @override
  Widget build(BuildContext context) {
    final remaining = _maxContacts - contacts.length;
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
            const Text(
              AppStrings.settingsInactivityContact,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.lg2,
                fontWeight: AppTextStyle.semiBold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...contacts.map(
              (c) => InkWell(
                onTap: () => onEdit(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontSize: AppTextStyle.lg2,
                                color: AppColors.textPrimary,
                                fontWeight: AppTextStyle.semiBold,
                              ),
                            ),
                            Text(
                              c.phone,
                              style: const TextStyle(
                                fontSize: AppTextStyle.md,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.primary,
                        size: AppSize.iconMd,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (remaining > 0) ...[
              const Divider(color: AppColors.primary),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'あと$remaining件まで登録できます',
                style: const TextStyle(
                  fontSize: AppTextStyle.xs,
                  color: AppColors.textDisabled,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: AppSize.buttonHeight,
                child: ElevatedButton(
                  onPressed: onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: const Text(
                    AppStrings.settingsPhoneAddButton,
                    style: TextStyle(
                      fontSize: AppTextStyle.lg2,
                      fontWeight: AppTextStyle.medium,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// シェアカード
// ──────────────────────────────────────────

class _ShareCard extends ConsumerWidget {
  const _ShareCard({required this.state, required this.vm});

  final SettingsState state;
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkedAccounts = ref.watch(linkedAccountsProvider).valueOrNull ?? [];

    return _SettingCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSize.timerCardPaddingH,
        vertical: AppSize.timerCardPaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SvgPicture.asset(
                  'assets/SVG/arrow.svg',
                  width: AppSize.iconXs,
                  height: AppSize.iconMd,
                  colorFilter: const ColorFilter.mode(
                    AppColors.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsShareTitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.lg2,
                        fontWeight: AppTextStyle.semiBold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      AppStrings.settingsShareSubtitle,
                      style: TextStyle(
                        fontSize: AppTextStyle.xs,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              if (linkedAccounts.isNotEmpty)
                IconButton(
                  onPressed: vm.toggleEditSharedAccounts,
                  tooltip: state.isEditingSharedAccounts
                      ? AppStrings.accountLinkDoneTooltip
                      : AppStrings.accountLinkEditTooltip,
                  icon: Icon(
                    state.isEditingSharedAccounts
                        ? Icons.check
                        : Icons.edit_outlined,
                    color: AppColors.primary,
                    size: AppSize.iconMd,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final account in linkedAccounts)
            Column(
              children: [
                _ContactRow(
                  name: account.displayName,
                  isEditing: state.isEditingSharedAccounts,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LinkedAccountDetailPage(account: account),
                    ),
                  ),
                  onUnlink: () => showDialog<void>(
                    context: context,
                    builder: (_) => AppConfirmDialog(
                      title: account.displayName,
                      message: AppStrings.settingsShareDeleteConfirmMessage,
                      confirmLabel: AppStrings.settingsShareDeleteConfirmButton,
                      isDestructive: true,
                      onConfirm: () async {
                        try {
                          await vm.unlinkAccount(account.uid);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(AppStrings.accountLinkUnlinkError),
                            ),
                          );
                        }
                      },
                      onCancel: () => Navigator.pop(context),
                    ),
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.primary,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          const SizedBox(height: AppSpacing.x4lp),
          const Text(
            AppStrings.accountLinkInviteDescription,
            style: TextStyle(
              fontSize: AppTextStyle.xs,
              color: AppColors.textDisabled,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.inviteLink != null)
            _ShareLinkArea(link: state.inviteLink!)
          else
            SizedBox(
              width: double.infinity,
              height: AppSize.buttonHeight,
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await vm.generateInviteLink();
                  } catch (e) {
                    debugPrint('generateInviteLink failed: $e');
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.accountLinkGenerateError),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: const Text(
                  AppStrings.accountLinkGenerateButton,
                  style: TextStyle(
                    fontSize: AppTextStyle.lg2,
                    fontWeight: AppTextStyle.medium,
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.x2lm),
          const Center(
            child: Text(
              AppStrings.settingsShareViaApp,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.md,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x2lmm),
          _ShareAppIcons(inviteLink: state.inviteLink),
          const SizedBox(height: AppSpacing.x3lp),
          const Center(
            child: Text(
              AppStrings.settingsShareContent,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.md,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lgp),
          _ShareCheckbox(
            label: AppStrings.settingsShareWantToGo,
            value: state.shareWantToGo,
            onChanged: (v) => vm.setShareWantToGo(v ?? false),
          ),
          _ShareCheckbox(
            label: AppStrings.settingsShareVisited,
            value: state.shareVisited,
            onChanged: (v) => vm.setShareVisited(v ?? false),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSize.buttonHeight,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppStrings.saved)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: const Text(
                AppStrings.settingsShareSaveButton,
                style: TextStyle(
                  fontSize: AppTextStyle.lg2,
                  fontWeight: AppTextStyle.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.name,
    required this.isEditing,
    required this.onTap,
    required this.onUnlink,
  });

  final String name;
  final bool isEditing;
  final VoidCallback onTap;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: AppTextStyle.sm2,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Text(
                      AppStrings.accountLinkViewSpots,
                      style: TextStyle(
                        fontSize: AppTextStyle.xs,
                        color: AppColors.primary,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.primary,
                      size: AppSize.iconMd,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isEditing)
            IconButton(
              onPressed: onUnlink,
              tooltip: AppStrings.accountLinkUnlinkTooltip,
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: AppSize.iconMd,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareLinkArea extends StatelessWidget {
  const _ShareLinkArea({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.shareLinkBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.settingsShareLinkLabel,
                  style: TextStyle(
                    fontSize: AppTextStyle.xs,
                    color: AppColors.shareLinkLabel,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs / 2),
                Text(
                  link,
                  style: const TextStyle(
                    fontSize: AppTextStyle.sm,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.accountLinkCopied)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.shareLinkButton,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
            child: const Text(
              AppStrings.settingsShareLinkCopy,
              style: TextStyle(fontSize: AppTextStyle.sm),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareAppIcons extends StatelessWidget {
  const _ShareAppIcons({this.inviteLink});

  final String? inviteLink;

  bool _checkLink(BuildContext context) {
    if (inviteLink != null) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.shareLinkRequired)),
    );
    return false;
  }

  Future<void> _shareToLine(BuildContext context) async {
    if (!_checkLink(context)) return;
    final text =
        Uri.encodeComponent('${AppStrings.shareInviteText}\n$inviteLink');
    final uri = Uri.parse('https://line.me/R/share?text=$text');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.shareError)),
        );
      }
    }
  }

  Future<void> _shareToX(BuildContext context) async {
    if (!_checkLink(context)) return;
    final text =
        Uri.encodeComponent('${AppStrings.shareInviteText}\n$inviteLink');
    final uri = Uri.parse('https://x.com/intent/tweet?text=$text');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.shareError)),
        );
      }
    }
  }

  Future<void> _shareToInstagram(BuildContext context) async {
    if (!_checkLink(context)) return;
    await Clipboard.setData(ClipboardData(text: inviteLink!));
    try {
      final instagramUri = Uri.parse('instagram://app');
      if (await canLaunchUrl(instagramUri)) {
        await launchUrl(instagramUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Instagram 未インストール時もクリップボードコピー済みなのでスナックバーを表示
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.shareInstagramCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _AppIconItem(
          assetPath: 'assets/SVG/LINE.png',
          isPng: true,
          label: 'LINE',
          onTap: () => _shareToLine(context),
        ),
        _AppIconItem(
          assetPath: 'assets/SVG/Instagram.png',
          isPng: true,
          label: 'Instagram',
          onTap: () => _shareToInstagram(context),
        ),
        _AppIconItem(
          assetPath: 'assets/SVG/X.png',
          isPng: true,
          label: 'X',
          onTap: () => _shareToX(context),
        ),
      ],
    );
  }
}

class _AppIconItem extends StatelessWidget {
  const _AppIconItem({
    required this.assetPath,
    required this.isPng,
    required this.label,
    required this.onTap,
  });

  final String assetPath;
  final bool isPng;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.asset(
              assetPath,
              width: AppSize.iconLgp,
              height: AppSize.iconLgp,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTextStyle.xs,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareCheckbox extends StatelessWidget {
  const _ShareCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: AppTextStyle.md2,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          side: const BorderSide(color: AppColors.textDisabled),
        ),
      ],
    );
  }
}

// アカウントカード
// ──────────────────────────────────────────

class _AccountCard extends ConsumerWidget {
  const _AccountCard({
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authStateProvider).valueOrNull?.displayName;

    return _SettingCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSize.timerCardPaddingH,
        vertical: AppSize.timerCardPaddingV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppStrings.settingsAccountTitle,
            style: TextStyle(
              fontSize: AppTextStyle.lg2,
              fontWeight: AppTextStyle.semiBold,
              color: AppColors.textPrimary,
            ),
          ),
          if (displayName != null && displayName.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: AppTextStyle.md2,
                color: AppColors.primary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSize.buttonHeight,
            child: OutlinedButton(
              onPressed: onLogout,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: const Text(
                AppStrings.settingsLogout,
                style: TextStyle(
                  fontSize: AppTextStyle.lg2,
                  fontWeight: AppTextStyle.medium,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: AppSize.buttonHeight,
            child: ElevatedButton(
              onPressed: onDeleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: const Text(
                AppStrings.settingsDeleteAccount,
                style: TextStyle(
                  fontSize: AppTextStyle.lg2,
                  fontWeight: AppTextStyle.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────
// カスタムスイッチ
// ──────────────────────────────────────────

class _CustomSwitch extends StatelessWidget {
  const _CustomSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: AppSize.switchTrackW,
          height: AppSize.switchTrackH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            color: value ? AppColors.primary : AppColors.textDisabled,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: (AppSize.switchTrackH - AppSize.switchThumb) / 2,
              ),
              child: Container(
                width: AppSize.switchThumb,
                height: AppSize.switchThumb,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
