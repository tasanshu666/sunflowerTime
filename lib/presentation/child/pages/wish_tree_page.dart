/// 孩子端「许愿树」页（A-T04）——三段结构 + 历史今日回顾 + 花园入口的落点页。
///
/// ## 三段（页内分段，不是 tab；判据见 A19.6）
/// 树上（`treeSlot` 升序）/ 愿望收藏箱（`createdAt` 倒序）/ 达成所愿池（`fulfilledAt` 倒序）。
/// 数据全部经 [WishOrchestrationService] 读；本页**不实现**任何状态机 / 进度 / 额度判据。
///
/// ## 页级 provider（🔴 不改 A-T03 接线层）
/// A-T03 的 `wish_state.dart` 只提供 `wishTreeProvider` / `wishBadgeProvider` 等，
/// **不含** boxed / pool / tasks / anniversary / 盖章数 / 软门槛植物数。按派单铁律
/// 「provider 不足只给最小补充方案、不自行大改接线层」，本页以页级只读 provider
/// 组合既有服务读方法（`boxedWishes` / `poolWishes` / `tasksOf` /
/// `stampedAchievedCount` / `plantRepository.plants`）解决，最小补充方案见回报。
///
/// ## 幂等（A25 A-T04 断言 ⑦ / A35）
/// 里程碑演出用页级 [wishLastMilestoneProvider]（进程内 StateProvider）记住上次值；
/// 同一 stage 连续两次只播一次（纯函数 [shouldCelebrateMilestone] 便于测试）。
library wish_tree_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/wish_state.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_anniversary_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card_detail.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_collection_box.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_compose_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';

// ── 页级只读 provider（组合既有服务方法，不改接线层） ────────────────────────

/// 收藏箱愿望（`boxedWishes()`；仓储已按 `createdAt` 倒序）。
final wishBoxedProvider = FutureProvider.autoDispose<List<Wish>>((ref) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    return await ref.read(wishOrchestrationServiceProvider).boxedWishes();
  } catch (_) {
    return <Wish>[];
  }
});

/// 达成池愿望（`poolWishes()`；仓储已按 `fulfilledAt` 倒序）。
final wishPoolProvider = FutureProvider.autoDispose<List<Wish>>((ref) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    return await ref.read(wishOrchestrationServiceProvider).poolWishes();
  } catch (_) {
    return <Wish>[];
  }
});

/// 盖章计数（`stampedAchievedCount()`；里程碑 = floor(count / step)）。
final wishStampedCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    return await ref
        .read(wishOrchestrationServiceProvider)
        .stampedAchievedCount();
  } catch (_) {
    return 0;
  }
});

/// 已种植物数（软门槛：≥ [kWishSoftGateMinPlants] 才能许愿）。
final wishPlantCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    return (await ref.read(plantRepositoryProvider).plants()).length;
  } catch (_) {
    return 0;
  }
});

/// 单条愿望的归属任务（只读，按 `wishId` family）。
final wishTasksFamilyProvider =
    FutureProvider.autoDispose.family<List<Task>, String>((ref, wishId) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    return await ref.read(wishOrchestrationServiceProvider).tasksOf(
          wishId: wishId,
          now: DateTime.now(),
        );
  } catch (_) {
    return <Task>[];
  }
});

/// 里程碑演出的「上次展示值」（进程内；重启归零 ⇒ 宁可漏播一次）。
final wishLastMilestoneProvider = StateProvider<int>((ref) => -1);

/// 里程碑是否需要演出（幂等纯函数：`current > last` 才播，相等/更小不播）。
bool shouldCelebrateMilestone(int current, int last) => current > last;

/// 历史今日命中判据（A26.10.2 ②：同月同日 + 年早于今年；今天刚许的不算）。
bool isAnniversaryMatch(Wish wish, DateTime now) =>
    wish.createdAt.year < now.year &&
    wish.createdAt.month == now.month &&
    wish.createdAt.day == now.day;

/// 历史今日结果：主卡（命中中 `createdAt` 最大）+ 折叠列表（`createdAt` 倒序）。
class AnniversaryResult {
  const AnniversaryResult({
    this.wish,
    this.extras = const <Wish>[],
  });

  final Wish? wish;
  final List<Wish> extras;

  bool get isEmpty => wish == null;

  /// 折叠计数 = 命中总数 − 1（A26.10.3 ②）。
  int get extraCount => extras.length;
}

/// 历史今日只读组合：三段并集 → 内存过滤 → 排序（不新增仓储/服务方法）。
final wishAnniversaryProvider =
    FutureProvider.autoDispose<AnniversaryResult>((ref) async {
  ref.watch(childProfileRevisionProvider);
  final DateTime now = DateTime.now();
  try {
    final service = ref.read(wishOrchestrationServiceProvider);
    final List<Wish> all = <Wish>[
      ...await service.mountedWishes(),
      ...await service.boxedWishes(),
      ...await service.poolWishes(),
    ];
    final List<Wish> hits =
        all.where((Wish w) => isAnniversaryMatch(w, now)).toList()
          ..sort((Wish a, Wish b) => b.createdAt.compareTo(a.createdAt));
    if (hits.isEmpty) return const AnniversaryResult();
    return AnniversaryResult(
      wish: hits.first,
      extras: hits.sublist(1),
    );
  } catch (_) {
    return const AnniversaryResult();
  }
});

/// 页内分段枚举（不是 tab）。
enum _WishSection { tree, box, pool }

/// 许愿树页。
class WishTreePage extends ConsumerStatefulWidget {
  const WishTreePage({super.key});

  @override
  ConsumerState<WishTreePage> createState() => _WishTreePageState();
}

class _WishTreePageState extends ConsumerState<WishTreePage> {
  _WishSection _section = _WishSection.tree;

  /// 历史今日：是否展示（受频次控制）+ 是否已判定完成。
  bool _showAnniversary = false;
  bool _anniversaryResolved = false;

  /// 高亮目标愿望 id（A36.3「看看它」）。
  String? _highlightWishId;

  late final DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // 历史今日频次：展示那一刻即写今日日期（A26.10.4 ⑥）。
    _resolveAnniversary();
  }

  Future<void> _resolveAnniversary() async {
    try {
      final String childId = ref.read(accountServiceProvider).childId;
      final String? shown = await ref
          .read(settingsStoreProvider)
          .wishAnniversaryShownOn(childId: childId);
      final String today = dayKey(_now);
      final AnniversaryResult result = await ref.read(wishAnniversaryProvider.future);
      if (!mounted) return;
      final bool shouldShow = !result.isEmpty && shown != today;
      if (shouldShow) {
        await ref
            .read(settingsStoreProvider)
            .setWishAnniversaryShownOn(childId: childId, yyyyMmDd: today);
      }
      if (!mounted) return;
      setState(() {
        _showAnniversary = shouldShow;
        _anniversaryResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _anniversaryResolved = true);
    }
  }

  /// 收起回顾卡（写今日日期已在展示时完成，收起仅隐藏本卡）。
  void _dismissAnniversary() {
    setState(() => _showAnniversary = false);
  }

  /// 「看看它」：切到目标所在段 + 高亮 + 收起回顾卡（A36.3）。
  void _lookAt(Wish wish) {
    final _WishSection section;
    if (wish.isAchieved) {
      section = _WishSection.pool;
    } else if (wish.isReleased) {
      section = _WishSection.box;
    } else {
      section = _WishSection.tree;
    }
    setState(() {
      _section = section;
      _highlightWishId = wish.id;
      _showAnniversary = false;
    });
  }

  Future<void> _startWish(AppLocalizations t) async {
    final int plantCount = await ref.read(wishPlantCountProvider.future);
    final WishBadge badge = await ref.read(wishBadgeProvider.future);
    if (!mounted) return;

    // A-T04 断言 ③④：软门槛未达成 / 挂载位满 ⇒ 按钮仍可点，弹流程引导（无购买入口）。
    final String? hint;
    if (!WishOrchestrationService.softGateSatisfied(plantCount)) {
      hint = t.wishTreeSoftGateHint;
    } else if (badge.mounted >= badge.quota) {
      hint = t.wishTreeSlotFullHint;
    } else {
      hint = null;
    }
    if (hint != null) {
      await showChildConfirmCard(
        context: context,
        title: t.wishTreeGuideTitle,
        message: hint,
        confirmLabel: t.wishTreeGuideOk,
        cancelLabel: t.shared_cancel,
      );
      return;
    }

    final WishComposeResult? result = await showWishComposeDialog(
      context: context,
      l10n: t,
    );
    if (result == null || !mounted) return;
    final int idx = result.categoryIndex.clamp(0, WishCategory.values.length - 1);
    try {
      await ref.read(wishOrchestrationServiceProvider).createWish(
            text: result.text,
            category: WishCategory.values[idx],
            now: DateTime.now(),
          );
    } catch (_) {
      if (!mounted) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.wishComposeSaveFailed)),
        );
      }
    }
  }

  Future<void> _collect(Wish wish) async {
    await ref
        .read(wishOrchestrationServiceProvider)
        .collectToBox(id: wish.id, now: DateTime.now());
  }

  Future<void> _change(Wish wish, AppLocalizations t) async {
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: t.wishTreeTitle,
      message: t.wishTreeChangeWish,
      confirmLabel: t.wishTreeChangeWish,
      cancelLabel: t.shared_cancel,
    );
    if (ok != true || !mounted) return;
    await ref
        .read(wishOrchestrationServiceProvider)
        .abandon(id: wish.id, now: DateTime.now());
  }

  Future<void> _selfFulfill(Wish wish) async {
    await ref
        .read(wishOrchestrationServiceProvider)
        .selfFulfill(id: wish.id, now: DateTime.now());
  }

  Future<void> _restore(Wish wish, AppLocalizations t) async {
    try {
      await ref
          .read(wishOrchestrationServiceProvider)
          .restoreFromBox(id: wish.id, now: DateTime.now());
    } catch (_) {
      // C69：额度被拒不删数据 ⇒ 弹引导（无购买入口）。
      if (!mounted || !context.mounted) return;
      await showChildConfirmCard(
        context: context,
        title: t.wishTreeGuideTitle,
        message: t.wishBoxFullHint,
        confirmLabel: t.wishTreeGuideOk,
        cancelLabel: t.shared_cancel,
      );
    }
  }

  void _openDetail(Wish wish, AppLocalizations t) {
    // A36.3 消失时机③：点别处（进详情）⇒ 清高亮。
    if (_highlightWishId != null) {
      setState(() => _highlightWishId = null);
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFFBF0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _DetailBody(
              wish: wish,
              t: t,
              now: _now,
              onCollect: () => _collect(wish),
              onChange: () => _change(wish, t),
              onSelfFulfill: () => _selfFulfill(wish),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    return L10nScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.wishTreeTitle),
          leading: IconButton(
            key: const Key('wish_tree_back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              // 历史今日回顾卡（页内顶部，不打断）。
              if (_anniversaryResolved && _showAnniversary)
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, Widget? _) {
                    final AnniversaryResult result =
                        ref.watch(wishAnniversaryProvider).value ??
                            const AnniversaryResult();
                    final Wish? main = result.wish;
                    if (main == null) return const SizedBox.shrink();
                    final int years = _now.year - main.createdAt.year;
                    return WishAnniversaryCard(
                      wish: main,
                      years: years,
                      t: t,
                      extraWishes: result.extras,
                      extraCount: result.extraCount,
                      onLook: () => _lookAt(main),
                      onDismiss: _dismissAnniversary,
                    );
                  },
                ),
              _buildSectionSwitch(t),
              _buildHangingRow(t),
              Expanded(child: _buildSection(t)),
            ],
          ),
        ),
      ),
    );
  }

  /// 页内分段切换（树上 / 收藏箱 / 达成池）。
  Widget _buildSectionSwitch(AppLocalizations t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(child: _segChip(_WishSection.tree, t)),
            const SizedBox(width: 8),
            Expanded(child: _segChip(_WishSection.box, t)),
            const SizedBox(width: 8),
            Expanded(child: _segChip(_WishSection.pool, t)),
          ],
        ),
      );

  Widget _segChip(_WishSection section, AppLocalizations t) {
    // 三段标签与实时角标（角标由页级 provider 给出，切段不改数据源）。
    final String label = switch (section) {
      _WishSection.tree => t.wishTreeTabTree,
      _WishSection.box => t.wishTreeTabBox(_boxedCount()),
      _WishSection.pool => t.wishTreeTabPool(_poolCount()),
    };
    final bool selected = _section == section;
    return ChoiceChip(
      key: Key('wish_section_${section.name}'),
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        _section = section;
        _highlightWishId = null;
      }),
    );
  }

  int _boxedCount() => ref.watch(wishBoxedProvider).value?.length ?? 0;
  int _poolCount() => ref.watch(wishPoolProvider).value?.length ?? 0;

  /// 「已挂 N / 额度 M」+「开始许愿」按钮（M 随等级变化）。
  Widget _buildHangingRow(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final WishBadge badge = ref.watch(wishBadgeProvider).value ??
              const WishBadge();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Text(
                  t.wishTreeHanging(badge.mounted, badge.quota),
                  key: const Key('wish_tree_hanging'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  t.wishTreeLevel(badge.focusLevel),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A66)),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('wish_tree_start'),
                  onPressed: () => _startWish(t),
                  icon: const Icon(Icons.add),
                  label: Text(t.wishTreeStart),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildSection(AppLocalizations t) => switch (_section) {
        _WishSection.tree => _buildTree(t),
        _WishSection.box => _buildBox(t),
        _WishSection.pool => _buildPool(t),
      };

  Widget _buildTree(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishTreeProvider).value ?? <Wish>[];
          // 树上树按 treeSlot 升序（记忆锚点，不由时间冲掉）。
          final List<Wish> sorted = <Wish>[...wishes]
            ..sort((Wish a, Wish b) =>
                (a.treeSlot ?? 0).compareTo(b.treeSlot ?? 0));
          if (sorted.isEmpty) {
            return Center(
              key: const Key('wish_tree_empty_tree'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.wishTreeEmptyTree,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF8A7A66)),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('wish_tree_list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: sorted.length,
            itemBuilder: (BuildContext context, int index) {
              final Wish wish = sorted[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WishCard(
                  wish: wish,
                  t: t,
                  highlight: _highlightWishId == wish.id,
                  taskCount: ref.watch(wishTasksFamilyProvider(wish.id)).value?.length ?? 0,
                  waitDays: WishOrchestrationService.waitingDays(
                    wish.createdAt,
                    _now,
                  ),
                  onTap: () => _openDetail(wish, t),
                ),
              );
            },
          );
        },
      );

  Widget _buildBox(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishBoxedProvider).value ?? <Wish>[];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: WishCollectionBox(
              wishes: wishes,
              t: t,
              highlightWishId: _highlightWishId,
              onRestore: (Wish wish) => _restore(wish, t),
            ),
          );
        },
      );

  Widget _buildPool(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishPoolProvider).value ?? <Wish>[];
          final int stamped = ref.watch(wishStampedCountProvider).value ?? 0;
          final int milestone =
              WishOrchestrationService.poolMilestoneCount(stamped);
          // 里程碑演出幂等：current > last 才播，且立即写回 last。
          final int last = ref.watch(wishLastMilestoneProvider);
          if (milestone > last) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.read(wishLastMilestoneProvider.notifier).state = milestone;
              }
            });
          }
          if (wishes.isEmpty) {
            return Center(
              key: const Key('wish_tree_empty_pool'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.wishTreeEmptyPool,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF8A7A66)),
                ),
              ),
            );
          }
          return ListView.builder(
            key: const Key('wish_tree_pool_list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: wishes.length,
            itemBuilder: (BuildContext context, int index) {
              final Wish wish = wishes[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WishPoolTile(
                  wish: wish,
                  t: t,
                  milestoneCount: milestone,
                  highlight: _highlightWishId == wish.id,
                ),
              );
            },
          );
        },
      );
}

/// 详情页主体（在浮层 scope 内构建，文案由页面取好经 [t] 传入）。
class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.wish,
    required this.t,
    required this.now,
    required this.onCollect,
    required this.onChange,
    required this.onSelfFulfill,
  });

  final Wish wish;
  final AppLocalizations t;
  final DateTime now;
  final VoidCallback onCollect;
  final VoidCallback onChange;
  final VoidCallback onSelfFulfill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Task> tasks =
        ref.watch(wishTasksFamilyProvider(wish.id)).value ?? <Task>[];
    final bool canSelfFulfill = hasGoalTarget(wish.targetValue) &&
        wish.releasedAt == null &&
        !wish.isTerminal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WishCardDetail(
          wish: wish,
          t: t,
          waitDays: WishOrchestrationService.waitingDays(wish.createdAt, now),
          taskCount: tasks.length,
          canSelfFulfill: canSelfFulfill,
          confirmTitle: t.wishTreeSelfFulfillConfirm,
          confirmMessage: t.wishSelfFulfillConfirm,
          confirmLabel: t.wishSelfFulfill,
          cancelLabel: t.shared_cancel,
          onCollectToBox: onCollect,
          onChangeWish: onChange,
          onSelfFulfill: onSelfFulfill,
        ),
        if (tasks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t.wishTreeTaskBadge(tasks.length),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          for (final Task task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WishTaskCard(
                task: task,
                wishTitle: wish.text,
                focusActionLabel: t.wishTaskGoFocus,
                didItLabel: t.wishTaskDidIt,
                confirmTitle: t.wishTaskGoFocus,
                confirmMessage: t.wishTaskGoFocus,
                startFocusLabel: t.wishTaskGoFocus,
                cancelLabel: t.shared_cancel,
                doneLabel: t.wishTaskDone,
                pendingLabel: t.wishTaskPending,
              ),
            ),
        ],
      ],
    );
  }
}
