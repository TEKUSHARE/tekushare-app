import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:tekushare/screens/widgets/common/app_confirm_dialog.dart';
import 'package:tekushare/core/config/flavor.dart';
import 'package:tekushare/core/constants/app_colors.dart';
import 'package:tekushare/core/constants/app_spacing.dart';
import 'package:tekushare/core/constants/app_strings.dart';
import 'package:tekushare/core/constants/app_text_style.dart';
import 'package:tekushare/core/constants/map_constants.dart';
import 'package:tekushare/core/theme/app_sizing_theme.dart';
import 'package:tekushare/core/utils/distance_calculator.dart';
import 'package:tekushare/domain/entities/saved_route.dart';
import 'package:tekushare/domain/entities/spot.dart';
import 'package:tekushare/domain/entities/walk_route.dart';
import 'package:tekushare/domain/entities/walk_session.dart';
import 'package:tekushare/screens/pages/map/viewmodel/walk_route_viewmodel.dart';
import 'package:tekushare/screens/pages/settings/view/settings_page.dart';
import 'package:tekushare/screens/pages/spot/view/spot_list_page.dart';
import 'package:tekushare/screens/providers/app_providers.dart';
import 'package:tekushare/screens/providers/saved_routes_provider.dart';
import 'package:tekushare/screens/providers/spot_provider.dart';
import 'package:tekushare/screens/providers/walk_history_provider.dart';
import 'package:tekushare/screens/providers/walk_routes_provider.dart';
import 'package:tekushare/screens/widgets/common/app_bottom_nav.dart';

const _weekdayNames = ['日', '月', '火', '水', '木', '金', '土'];

Map<String, int> _buildSpotCountMap(
  List<WalkSession> sessions,
  List<Spot> spots,
) {
  final result = <String, int>{};
  for (final s in sessions) {
    if (s.status != WalkStatus.finished || s.startedAt == null) continue;
    final end = s.finishedAt ?? DateTime.now();
    result[s.id] = spots
        .where(
          (sp) =>
              !sp.createdAt.isBefore(s.startedAt!) &&
              !sp.createdAt.isAfter(end),
        )
        .length;
  }
  return result;
}

List<WalkLog> _buildSessionLogs(
  List<WalkSession> sessions,
  Map<String, double> distanceBySessionId,
  Map<String, int> spotCountBySessionId,
) {
  final finished = sessions
      .where((s) => s.status == WalkStatus.finished && s.startedAt != null)
      .toList()
    ..sort((a, b) => a.startedAt!.compareTo(b.startedAt!));

  final last7 =
      finished.length > 7 ? finished.sublist(finished.length - 7) : finished;

  return List.generate(7, (i) {
    if (i >= last7.length) {
      return (
        sessionId: '',
        date: '-',
        startEndTime: '-',
        duration: '-',
        distance: '-',
        spotCount: 0,
        dayLabel: '-',
      );
    }

    final session = last7[i];
    final start = session.startedAt!;
    final end = session.finishedAt;
    final dayLabel = _weekdayNames[start.weekday % 7];
    final h = session.elapsedSeconds ~/ 3600;
    final m = (session.elapsedSeconds % 3600) ~/ 60;
    final s = session.elapsedSeconds % 60;

    return (
      sessionId: session.id,
      date: '${start.year}年${start.month.toString().padLeft(2, '0')}月'
          '${start.day.toString().padLeft(2, '0')}日($dayLabel)',
      startEndTime: end != null
          ? '${start.hour}:${start.minute.toString().padLeft(2, '0')}'
              '~${end.hour}:${end.minute.toString().padLeft(2, '0')}'
          : '${start.hour}:${start.minute.toString().padLeft(2, '0')}',
      duration: h > 0
          ? '${h.toString().padLeft(2, '0')}:'
              '${m.toString().padLeft(2, '0')}:'
              '${s.toString().padLeft(2, '0')}'
          : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      distance: formatDistanceKm(
        distanceBySessionId[session.id] ?? 0,
      ),
      spotCount: spotCountBySessionId[session.id] ?? 0,
      dayLabel: dayLabel,
    );
  });
}

Map<String, double> _buildDistanceMap(List<WalkRoute> routes) => {
      for (final r in routes) r.walkSessionId: calcDistanceKm(r.points),
    };

/// 散歩ルートページ
class WalkRoutePage extends ConsumerStatefulWidget {
  const WalkRoutePage({super.key, this.showSaveDialogOnLoad = false});

  final bool showSaveDialogOnLoad;

  @override
  ConsumerState<WalkRoutePage> createState() => _WalkRoutePageState();
}

class _WalkRoutePageState extends ConsumerState<WalkRoutePage> {
  final _nameController = TextEditingController();
  int _cardSlideDirection = 1;
  Map<String, double> _distanceBySessionId = {};
  Map<String, int> _spotCountBySessionId = {};
  bool _isSaveDialogShowing = false;

  void _selectDay(int day) {
    final current = ref.read(walkRouteViewModelProvider).selectedDay;
    setState(() => _cardSlideDirection = day > current ? 1 : -1);
    ref.read(walkRouteViewModelProvider.notifier).selectDay(day);
  }

  void _applyHistory(List<WalkSession> sessions) {
    if (!mounted) return;
    final finished =
        sessions.where((s) => s.status == WalkStatus.finished).toList();
    final vm = ref.read(walkRouteViewModelProvider.notifier);
    vm.setLogs(
      _buildSessionLogs(sessions, _distanceBySessionId, _spotCountBySessionId),
    );
    if (finished.isEmpty) return;
    vm.selectDay(finished.length.clamp(1, 7));
  }

  void _applyWalkRoutes(List<WalkRoute> routes) {
    if (!mounted) return;
    _distanceBySessionId = _buildDistanceMap(routes);
    final sessions = ref.read(walkHistoryProvider).valueOrNull;
    if (sessions != null) _applyHistory(sessions);
  }

  void _applySpots(List<Spot> spots) {
    if (!mounted) return;
    final sessions = ref.read(walkHistoryProvider).valueOrNull;
    if (sessions == null) return;
    _spotCountBySessionId = _buildSpotCountMap(sessions, spots);
    _applyHistory(sessions);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final results = await Future.wait([
          ref.read(walkHistoryProvider.future),
          ref.read(savedRoutesProvider.future),
          ref.read(walkRoutesProvider.future),
        ]);
        if (!mounted) return;
        final sessions = results[0] as List<WalkSession>;
        final spots = ref.read(spotProvider);
        _spotCountBySessionId = _buildSpotCountMap(sessions, spots);
        _applyWalkRoutes(results[2] as List<WalkRoute>);
        _applyHistory(sessions);
        _applySavedRoutes(results[1] as List<SavedRoute>);
      } on Object catch (e) {
        debugPrint('データの読み込みに失敗しました: $e');
      }
      if (!mounted) return;
      if (widget.showSaveDialogOnLoad) _showSaveConfirmDialog();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSaveConfirmDialog() {
    if (_isSaveDialogShowing) return;
    _isSaveDialogShowing = true;
    final state = ref.read(walkRouteViewModelProvider);
    showDialog<void>(
      context: context,
      builder: (_) => _SaveConfirmDialog(
        nameController: _nameController,
        log: state.selectedLog,
        onSave: () {
          final log = state.selectedLog;
          final name = _nameController.text.isEmpty
              ? state.defaultRouteName
              : _nameController.text;
          final sessionId = log.sessionId.isEmpty ? null : log.sessionId;
          final savedRoute = SavedRoute(
            id: 0,
            name: name,
            date: log.date,
            distance: log.distance,
            time: log.duration,
            createdAt: DateTime.now(),
            walkSessionId: sessionId,
          );
          ref.read(savedRouteRepositoryProvider).save(savedRoute).then((_) {
            ref.invalidate(savedRoutesProvider);
          });
          _nameController.clear();
          Navigator.pop(context);
          if (!mounted) return;
          _showSavedDialog();
        },
        onCancel: () => Navigator.pop(context),
      ),
    ).whenComplete(() => _isSaveDialogShowing = false);
  }

  void _showSavedDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _SavedDialog(
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  void _applySavedRoutes(List<SavedRoute> routes) {
    if (!mounted) return;
    final items = routes
        .map((r) => (
              id: r.id,
              date: r.date,
              name: r.name,
              distance: r.distance,
              time: r.time,
              walkSessionId: r.walkSessionId,
            ))
        .toList();
    ref.read(walkRouteViewModelProvider.notifier).setRoutes(items);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(walkHistoryProvider, (_, next) {
      next.whenData(_applyHistory);
    });
    ref.listen(savedRoutesProvider, (_, next) {
      next.whenData(_applySavedRoutes);
    });
    ref.listen(walkRoutesProvider, (_, next) {
      next.whenData(_applyWalkRoutes);
    });
    ref.listen(spotProvider, (_, spots) => _applySpots(spots));

    final state = ref.watch(walkRouteViewModelProvider);
    final vm = ref.read(walkRouteViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(AppStrings.walkRoutePageTitle),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  if (state.selectedRoute != null)
                    _SelectedRouteCard(route: state.selectedRoute!),
                  const SizedBox(height: AppSpacing.lg),
                  _RouteListCard(
                    routes: state.routes,
                    selectedIndex: state.selectedRouteIndex,
                    onSelect: vm.selectRoute,
                    onDelete: (int globalIndex) {
                      final route = state.routes[globalIndex];
                      vm.removeRoute(globalIndex);
                      if (route.id != 0) {
                        ref
                            .read(savedRouteRepositoryProvider)
                            .delete(route.id)
                            .then((_) => ref.invalidate(savedRoutesProvider))
                            .catchError(
                              (_) => ref.invalidate(savedRoutesProvider),
                            );
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _CalendarRow(
                    selectedDay: state.selectedDay,
                    onSelect: _selectDay,
                    dayLabels: state.logs.map((l) => l.dayLabel).toList(),
                  ),
                  GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity;
                      if (v == null) return;
                      if (v < -200) {
                        _selectDay(
                          state.selectedDay < 7 ? state.selectedDay + 1 : 1,
                        );
                      } else if (v > 200) {
                        _selectDay(
                          state.selectedDay > 1 ? state.selectedDay - 1 : 7,
                        );
                      }
                    },
                    child: ClipRect(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                          alignment: Alignment.topLeft,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        ),
                        transitionBuilder: (child, animation) {
                          final isEntering =
                              child.key == ValueKey(state.selectedDay);
                          final begin = Offset(
                            isEntering
                                ? _cardSlideDirection.toDouble()
                                : -_cardSlideDirection.toDouble(),
                            0,
                          );
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: begin,
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              )),
                              child: child,
                            ),
                          );
                        },
                        child: _WalkInfoCard(
                          key: ValueKey(state.selectedDay),
                          log: state.selectedLog,
                          onSave: _showSaveConfirmDialog,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withValues(alpha: 0),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: (index) {
          if (index == 0) {
            Navigator.popUntil(context, (route) => route.isFirst);
          } else if (index == 1) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const SpotListPage()),
              (route) => route.isFirst,
            );
          } else if (index == 3) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
              (route) => route.isFirst,
            );
          }
        },
      ),
    );
  }
}

// ──────────────────────────────────────────
// 保存済みルートリストカード
// ──────────────────────────────────────────

class _RouteListCard extends StatefulWidget {
  const _RouteListCard({
    required this.routes,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDelete,
  });

  final List<SavedRouteItem> routes;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onDelete;

  @override
  State<_RouteListCard> createState() => _RouteListCardState();
}

class _RouteListCardState extends State<_RouteListCard> {
  static const _pageSize = 3;
  int _currentPage = 0;
  int _slideDirection = 1;

  int get _pageCount =>
      widget.routes.isEmpty ? 1 : (widget.routes.length / _pageSize).ceil();

  void _goToPage(int page) {
    _slideDirection = page > _currentPage ? 1 : -1;
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final offset = _currentPage * _pageSize;
    final end = (offset + _pageSize).clamp(0, widget.routes.length);
    final pageRoutes = widget.routes.sublist(offset, end);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200 && _currentPage < _pageCount - 1) {
          _goToPage(_currentPage + 1);
        } else if (details.primaryVelocity! > 200 && _currentPage > 0) {
          _goToPage(_currentPage - 1);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.primary),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: AppSpacing.sm,
              offset: const Offset(0, AppSpacing.xs),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) => Text(
                AppStrings.savedRoutes,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: AppSizingTheme.of(context).routeListHeadingFontSize,
                  fontWeight: AppTextStyle.semiBold,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  final isEntering = child.key == ValueKey(_currentPage);
                  final begin = isEntering
                      ? Offset(_slideDirection.toDouble(), 0)
                      : Offset(-_slideDirection.toDouble(), 0);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      )),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey(_currentPage),
                  children: List.generate(_pageSize, (i) {
                    final hasItem = i < pageRoutes.length;
                    final globalIndex = offset + i;
                    const dummyItem = (
                      id: 0,
                      date: '',
                      name: '',
                      distance: '',
                      time: '',
                      walkSessionId: null,
                    );
                    final itemContent = Column(
                      children: [
                        _RouteItem(
                          route: hasItem ? pageRoutes[i] : dummyItem,
                          isSelected:
                              hasItem && globalIndex == widget.selectedIndex,
                          onTap: hasItem
                              ? () => widget.onSelect(globalIndex)
                              : null,
                          onDelete: hasItem
                              ? () {
                                  widget.onDelete(globalIndex);
                                  final newCount = widget.routes.length - 1;
                                  final maxPage = newCount == 0
                                      ? 0
                                      : ((newCount / _pageSize).ceil() - 1);
                                  if (_currentPage > maxPage) {
                                    setState(() => _currentPage = maxPage);
                                  }
                                }
                              : null,
                        ),
                        if (i < _pageSize - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    );
                    if (!hasItem) {
                      return Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: itemContent,
                      );
                    }
                    return itemContent;
                  }),
                ),
              ),
            ),
            if (_pageCount > 1) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 0
                        ? () => _goToPage(_currentPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    color: AppColors.primary,
                    disabledColor: AppColors.textDisabled,
                  ),
                  Text(
                    '${_currentPage + 1}',
                    style: const TextStyle(
                      fontSize: AppTextStyle.md,
                      fontWeight: AppTextStyle.semiBold,
                      color: AppColors.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: _currentPage < _pageCount - 1
                        ? () => _goToPage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    color: AppColors.primary,
                    disabledColor: AppColors.textDisabled,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteItem extends StatelessWidget {
  const _RouteItem({
    required this.route,
    required this.isSelected,
    this.onTap,
    this.onDelete,
  });

  final SavedRouteItem route;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.chipUnselected,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) => Text(
                      route.name,
                      style: TextStyle(
                        fontSize:
                            AppSizingTheme.of(context).routeItemNameFontSize,
                        fontWeight: AppTextStyle.medium,
                        color: isSelected ? AppColors.primary : Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Builder(
                    builder: (context) => Text(
                      '距離 ${route.distance} / ${route.time}',
                      style: TextStyle(
                        fontSize:
                            AppSizingTheme.of(context).routeItemSubFontSize,
                        color: isSelected ? AppColors.primary : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: const Offset(2, -8),
                    child: Transform.rotate(
                      angle: -0.9,
                      child: SvgPicture.asset(
                        'assets/SVG/foot.svg',
                        width: AppSize.iconMd,
                        height: AppSize.iconMd,
                        colorFilter: ColorFilter.mode(
                          isSelected
                              ? AppColors.primary
                              : AppColors.chipUnselected,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(-14, 8),
                    child: Transform.rotate(
                      angle: 0.9,
                      child: Transform.scale(
                        scaleX: -1,
                        child: SvgPicture.asset(
                          'assets/SVG/foot.svg',
                          width: AppSize.iconMd,
                          height: AppSize.iconMd,
                          colorFilter: ColorFilter.mode(
                            isSelected
                                ? AppColors.primary
                                : AppColors.chipUnselected,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => AppConfirmDialog(
                      title: route.name,
                      message: AppStrings.routeDeleteConfirmMessage,
                      confirmLabel: AppStrings.routeDeleteButton,
                      isDestructive: true,
                      onConfirm: () {
                        Navigator.pop(ctx);
                        onDelete!();
                      },
                      onCancel: () => Navigator.pop(ctx),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(
                      Icons.delete_outline,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// 選択中ルートカード
// ──────────────────────────────────────────

class _SelectedRouteCard extends ConsumerStatefulWidget {
  const _SelectedRouteCard({required this.route});

  final SavedRouteItem route;

  @override
  ConsumerState<_SelectedRouteCard> createState() => _SelectedRouteCardState();
}

class _SelectedRouteCardState extends ConsumerState<_SelectedRouteCard> {
  double _strokeWidth = MapConstants.savedRoutePolylineStrokeWidth;

  @override
  Widget build(BuildContext context) {
    final walkRoutes = ref.watch(walkRoutesProvider).valueOrNull ?? [];
    final walkRoute = widget.route.walkSessionId == null
        ? null
        : walkRoutes
            .where((r) => r.walkSessionId == widget.route.walkSessionId)
            .firstOrNull;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.primary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: AppSpacing.sm,
            offset: const Offset(0, AppSpacing.xs),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              AppStrings.selectedRoute,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.lg2,
                fontWeight: AppTextStyle.semiBold,
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final height = AppSizingTheme.of(context).mapPlaceholderHeight;
              if (walkRoute == null || walkRoute.points.isEmpty) {
                return Container(
                  width: double.infinity,
                  height: height,
                  color: AppColors.chipUnselected,
                  child: const Center(
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.map_outlined,
                        size: 48,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  ),
                );
              }
              final points = walkRoute.points
                  .map((p) => latlong2.LatLng(p.latitude, p.longitude))
                  .toList();
              const interactionOptions = InteractionOptions(
                flags: MapConstants.savedRouteMapFlags,
              );
              final mapOptions = points.length >= 2
                  ? MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(AppSpacing.x2l),
                      ),
                      interactionOptions: interactionOptions,
                      onMapEvent: (event) {
                        if (event is MapEventMove) {
                          final w = MapConstants.savedRouteStrokeWidthAtZoom(
                            event.camera.zoom,
                          );
                          if ((w - _strokeWidth).abs() > 0.1) {
                            setState(() => _strokeWidth = w);
                          }
                        }
                      },
                    )
                  : MapOptions(
                      initialCenter: points.first,
                      initialZoom: MapConstants.defaultZoom,
                      interactionOptions: interactionOptions,
                      onMapEvent: (event) {
                        if (event is MapEventMove) {
                          final w = MapConstants.savedRouteStrokeWidthAtZoom(
                            event.camera.zoom,
                          );
                          if ((w - _strokeWidth).abs() > 0.1) {
                            setState(() => _strokeWidth = w);
                          }
                        }
                      },
                    );
              return Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: height,
                    child: FlutterMap(
                      options: mapOptions,
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: AppConfig.packageName,
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              strokeWidth: _strokeWidth,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: AppStrings.fullscreenMapTooltip,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _FullScreenRouteMapPage(
                            points: points,
                            name: widget.route.name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.fullscreen, size: 20),
                      color: AppColors.primary,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.85),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.start,
              children: [
                _RouteTag(label: widget.route.name),
                _RouteTag(label: widget.route.distance),
                _RouteTag(label: widget.route.time),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteTag extends StatelessWidget {
  const _RouteTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.primary),
      ),
      child: Builder(
        builder: (context) => Text(
          label,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: AppSizingTheme.of(context).routeTagFontSize,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// カレンダー行
// ──────────────────────────────────────────

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.selectedDay,
    required this.onSelect,
    required this.dayLabels,
  });

  final int selectedDay;
  final ValueChanged<int> onSelect;
  final List<String> dayLabels;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        final day = i + 1;
        final isSelected = day == selectedDay;
        return GestureDetector(
          onTap: () => onSelect(day),
          child: Column(
            children: [
              Text(
                i < dayLabels.length ? dayLabels[i] : '-',
                style: const TextStyle(
                  fontSize: AppTextStyle.xs,
                  color: AppColors.textDisabled,
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$day',
                      style: TextStyle(
                        fontSize:
                            isSelected ? AppTextStyle.xl : AppTextStyle.md2,
                        fontWeight: isSelected
                            ? AppTextStyle.semiBold
                            : AppTextStyle.regular,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '回',
                      style: TextStyle(
                        fontSize:
                            isSelected ? AppTextStyle.xs : AppTextStyle.xs,
                        fontWeight: AppTextStyle.regular,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Builder(
                builder: (context) => Container(
                  height: 3,
                  width: AppSizingTheme.of(context).calendarUnderlineWidth,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────
// 散歩情報カード
// ──────────────────────────────────────────

class _WalkInfoCard extends StatelessWidget {
  const _WalkInfoCard({super.key, required this.log, required this.onSave});

  final WalkLog log;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.x3l,
        horizontal: 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.primary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: AppSpacing.sm,
            offset: const Offset(0, AppSpacing.xs),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.date,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: AppTextStyle.x2l,
              fontWeight: AppTextStyle.semiBold,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoRow(
            label: AppStrings.walkStartEndTime,
            value: log.startEndTime,
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            label: AppStrings.walkDuration,
            value: log.duration,
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            label: AppStrings.walkDistanceLabel,
            value: log.distance,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${AppStrings.walkSpotCount}：${log.spotCount}件',
            style: const TextStyle(
              fontSize: AppTextStyle.md,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: AppSize.buttonHeightLg,
            child: ElevatedButton(
              onPressed: log.sessionId.isEmpty ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: const Text(
                AppStrings.saveRouteButton,
                style: TextStyle(
                  fontSize: AppTextStyle.xl,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label：',
          style: const TextStyle(
            fontSize: AppTextStyle.md,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: AppTextStyle.md,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────
// 保存確認ダイアログ
// ──────────────────────────────────────────

class _SaveConfirmDialog extends StatelessWidget {
  const _SaveConfirmDialog({
    required this.nameController,
    required this.log,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController nameController;
  final WalkLog log;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  String get _shortDate {
    final match = RegExp(r'\d+年0?(\d+)月0?(\d+)日\((.+)\)').firstMatch(log.date);
    if (match == null) return log.date;
    return '${match.group(1)}月${match.group(2)}日（${match.group(3)}）';
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
          AppSpacing.lg,
          AppSpacing.x3l,
          AppSpacing.lg,
          AppSpacing.x2l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _shortDate,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.x2l,
                fontWeight: AppTextStyle.semiBold,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '散歩時間${log.duration} / 距離${log.distance}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: AppTextStyle.sm,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 名前入力
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: AppStrings.routeNameHint,
                hintStyle: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: AppTextStyle.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.chipUnselected),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.chipUnselected),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              AppStrings.saveRouteConfirmMessage,
              style: TextStyle(fontSize: AppTextStyle.md),
            ),
            const SizedBox(height: AppSpacing.x2l),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.x5l,
                    child: ElevatedButton(
                      onPressed: onSave,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: const Text(AppStrings.saveButton),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.x5l,
                    child: OutlinedButton(
                      onPressed: onCancel,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// 保存完了ダイアログ
// ──────────────────────────────────────────

class _SavedDialog extends StatelessWidget {
  const _SavedDialog({required this.onClose});

  final VoidCallback onClose;

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
            const Text(
              AppStrings.saved,
              style: TextStyle(
                fontSize: AppTextStyle.lg2,
                fontWeight: AppTextStyle.medium,
              ),
            ),
            const SizedBox(height: AppSpacing.x2l),
            SizedBox(
              width: double.infinity,
              height: AppSize.buttonHeight,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text(AppStrings.closeButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// 全画面ルートマップページ
// ──────────────────────────────────────────

class _FullScreenRouteMapPage extends StatefulWidget {
  const _FullScreenRouteMapPage({
    required this.points,
    required this.name,
  });

  final List<latlong2.LatLng> points;
  final String name;

  @override
  State<_FullScreenRouteMapPage> createState() =>
      _FullScreenRouteMapPageState();
}

class _FullScreenRouteMapPageState extends State<_FullScreenRouteMapPage> {
  double _strokeWidth = MapConstants.savedRoutePolylineStrokeWidth;

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMove) {
      final w = MapConstants.savedRouteStrokeWidthAtZoom(event.camera.zoom);
      if ((w - _strokeWidth).abs() > 0.1) {
        setState(() => _strokeWidth = w);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapOptions = widget.points.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: widget.points,
              padding: const EdgeInsets.all(AppSpacing.x2l),
            ),
            onMapEvent: _onMapEvent,
          )
        : MapOptions(
            initialCenter: widget.points.first,
            initialZoom: MapConstants.defaultZoom,
            onMapEvent: _onMapEvent,
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.name),
        centerTitle: true,
        elevation: 0,
      ),
      body: FlutterMap(
        options: mapOptions,
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: AppConfig.packageName,
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.points,
                strokeWidth: _strokeWidth,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
