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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/wish_state.dart';
import 'package:sunflower_time/presentation/child/state/wish_tree_scene_state.dart';
// C136 需求 2：复用花园「玩法说明」弹窗的宽度上限常量
// `kGardenHelpDialogMaxWidth`（600），禁止在许愿树侧另写一个孪生数字。
import 'package:sunflower_time/presentation/child/pages/garden_page.dart'
    show kGardenHelpDialogMaxWidth;
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_anniversary_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card_detail.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_collection_box.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_compose_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_pool_tile.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_scene.dart';
import 'package:sunflower_time/shared/responsive.dart';

// ── 页级只读 provider（组合既有服务方法，不改接线层） ────────────────────────

/// 愿望详情弹层可见卡片 Key（几何测试载体：Dialog 自身铺满，卡片才是矩形）。
const Key kWishDetailDialogKey = Key('wish_detail_dialog');

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

/// 单条愿望任务打卡流水（只读，按 `wishId` family）。
///
/// 详情页据此派生「等家长确认」胶囊与「已完成」态；纯函数判据仍唯一落在
/// [wishTaskStageOf]。打卡落库后页面自增 economyRevision ⇒ 本 provider 重算。
final wishTaskCheckInsFamilyProvider =
    FutureProvider.autoDispose.family<List<CheckIn>, String>((ref, wishId) async {
  ref.watch(childProfileRevisionProvider);
  ref.watch(economyRevisionProvider);
  try {
    final List<Task> tasks = await ref.read(wishTasksFamilyProvider(wishId).future);
    if (tasks.isEmpty) return <CheckIn>[];
    return await ref.read(wishTaskRepositoryProvider).checkInsOfTaskIds(
          taskIds: tasks.map((Task task) => task.id).toList(),
        );
  } catch (_) {
    return <CheckIn>[];
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

/// 收藏箱 / 愿望池弹窗的**实际宽度**（纯函数，便于单测；C136 需求 2）。
///
/// ## 为什么需要它（玄参 2026-11-25 真机反馈原文）
/// 「许愿树里面愿望池和收藏箱，点击后弹出来的卡片，卡片宽度没有对 ipad 进行适配，
/// 现在显示的有点窄啊」。旧实现把 `maxWidth: 420` 写死在
/// `Container.constraints` 里 —— iPad 13″（逻辑宽 1032）上弹窗依旧只有 420 宽，
/// 两侧大片留白，显得窄长。
///
/// ## 为什么必须是 tight（`SizedBox(width:)`）而不是 `maxWidth`
/// 与花园「玩法说明」弹窗同一个坑（见 `garden_page.dart` 的
/// `kGardenHelpDialogMaxWidth` 注释）：本弹窗内容是
/// `SingleChildScrollView + Column(mainAxisSize.min)`，只给**松**的 `maxWidth`
/// 时 Column 会收缩到内容固有宽 —— 把 420 改成 600 也是假修，依旧窄长。
/// 故本函数返回的数值必须喂给 `SizedBox(width:)` 做 tight 约束。
///
/// ## 数值口径
/// 复用花园弹窗**同一个**上限常量 [kGardenHelpDialogMaxWidth]（600；禁止再写一个
/// 孪生 600）。减去 48 = 本弹窗 `insetPadding` 的 horizontal 之和（左右各 24）：
///  · iPhone 390 → 342（旧实现 390 − 48 = 342 且 < 420，**逐点与现状一致**）；
///  · iPad 11″ 834 / 13″ 1032 → 封顶 600，明显变宽；
///  · 极端窄视口钳到 0，绝不把负宽传给 `SizedBox`。
double wishListDialogWidth(double viewportWidth) =>
    (viewportWidth - 48).clamp(0.0, kGardenHelpDialogMaxWidth).toDouble();

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

  /// 场景闸门的 notifier 引用（initState 捕获，dispose 复用）。
  ///
  /// 🔴 不可在 `initState` / `dispose` 里 `ref.read(...notifier)` 后**立即**赋值：
  /// Riverpod 2.6.1 的 `StateController.state` setter 会 `markNeedsBuild()`，而在
  /// build / initState / dispose 阶段触发会抛
  /// `FlutterError: Tried to modify a provider while the widget tree was building`
  /// （WISH-V02-BUG-01：initState 抛 ⇒ dispose 不执行 ⇒ 闸门永久卡 true ⇒
  /// 返回花园环境音不恢复）。照仓库既有 `ChildShellPage` 先例：
  /// 先抓 controller 引用，上台延后到**帧后**、下台延后**一微任务**再写。
  late final StateController<bool> _sceneGateCtrl;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // v0.2.0（R-P0-04）：树页占据台前 ⇒ 花园页 build 折入闸门后停播环境音。
    // 🔴 本页**零 AudioService 代码**，只翻纯状态闸门；音频 API 冻结。
    // 先只抓引用（读 provider 不触发 markNeedsBuild），写入延后到本帧结束。
    _sceneGateCtrl = ref.read(wishTreeSceneActiveProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 帧前就被 pop 掉的极端情况：树页已不在树上，不得占台前。
      if (!mounted) return;
      _sceneGateCtrl.state = true;
    });
    // 历史今日频次：展示那一刻即写今日日期（A26.10.4 ⑥）。
    _resolveAnniversary();
  }

  @override
  void dispose() {
    // 返回花园 ⇒ 解除闸门，花园既有 `_syncAmbientTimer()` 成对恢复播放。
    //
    // 🔴 两条硬约束（照 `child_shell_page.dart::_publishOnStage` 先例）：
    //  1. `dispose` 阶段 `ref` 已不可靠（`ConsumerStatefulElement.unmount()` 先把
    //     自己标 disposed 再调 `state.dispose()`）⇒ 必须用 initState 捕获的 controller；
    //  2. **不能同步写**：`dispose` 发生在 `BuildOwner.finalizeTree()` 内，Riverpod 的
    //     `_debugCanModifyProviders` 守卫在这里同样判为「build 期改 provider」并抛
    //     `FlutterError`（WISH-V02-BUG-01 实测：同步写会让 dispose 炸掉 ⇒ 闸门卡 true）。
    //     故延后一微任务发布：仍在下一帧之前完成，花园页下一帧 build 就能读到 false 并复播。
    scheduleMicrotask(() {
      try {
        _sceneGateCtrl.state = false;
      } catch (_) {
        // ProviderScope / provider 已随页面一起销毁（退出 App / 测试收尾）：
        // 无需也无法发布，静默即可（抛出去只会把 dispose 弄脏）。
      }
    });
    super.dispose();
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

    // v0.3.0（R3-P0-04 / S2）：字数上限的**唯一取数点**。同一变量既给弹层
    // counter/本地校验，也给域层 createWish 校验 ⇒ 显示上限 == 提交上限。
    final int maxLen =
        wishMaxTextLength(Localizations.localeOf(context).languageCode);
    final WishComposeResult? result = await showWishComposeDialog(
      context: context,
      l10n: t,
      maxTextLength: maxLen,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(wishOrchestrationServiceProvider).createWish(
            text: result.text,
            // v0.3.0（R3-P0-03）：分类输入已下线 ⇒ 一律 other（category=0），
            // 列保留供历史数据读取。
            category: WishCategory.other,
            now: DateTime.now(),
            maxTextLength: maxLen,
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

  /// R7-P0-01：孩子显式「放进愿望池」——复用领域薄入口 putIntoPool。
  ///
  /// 手动任务型愿望 targetValue==0 被 registerCheckIn 的 hasGoalTarget 闸门拦住，
  /// 家长确认后不自动进池，改由本入口经 _tryComplete → _complete 收口。
  Future<void> _putIntoPool(Wish wish) async {
    await ref
        .read(wishOrchestrationServiceProvider)
        .putIntoPool(id: wish.id, now: DateTime.now());
  }

  /// 有任务愿望的任务卡「我做到了」（R6-P0-02③）。
  ///
  /// 不再走 `selfFulfill` 即时进池：复用成长任务打卡链落 pending，
  /// 由家长核销后经 `registerCheckIn` 的门控决定是否成真。
  /// 经济隔离（0 阳光 / 不进完美日）由 [TaskCheckInService] 的唯一 helper 保证。
  Future<void> _didIt(Task task) async {
    try {
      await ref
          .read(taskCheckInServiceProvider)
          .checkIn(task: task, now: DateTime.now());
      // 精准失效本愿望的打卡 provider，任务卡切到「等家长确认」胶囊。
      // 不触碰 economyRevisionProvider 总线（A-T03 接线层只读订阅契约）。
      ref.invalidate(wishTaskCheckInsFamilyProvider(task.wishId ?? ''));
    } on TaskCheckInException catch (_) {
      // 已提交 / 重复提交：静默降级，卡片只读态由下一次刷新呈现。
    }
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
    // 玄参 v0.3 真机反馈 4：详情从贴底 BottomSheet 改为**居中 Dialog**，
    // 几何口径照抄 wish_compose_dialog.dart 的已验证版本（24/40 inset、
    // maxWidth 420 / maxHeight 85% 屏高、24 圆角、内部滚动）。
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final Size screen = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            key: kWishDetailDialogKey,
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: screen.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF0),
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: WishDetailBody(
                  wish: wish,
                  t: t,
                  now: _now,
                  // C136 需求 4（玄参真机反馈）：放进收藏箱后**自动关闭**详情卡。
                  // 原实现只落库不 pop，卡片留在原地，孩子还能继续点「换个愿望」
                  // /「实现了」—— 已经收进收藏箱的愿望不该再出现这些入口（箱内
                  // 只能「取回」，由 `wish_collection_box.dart` 的取回按钮承载）。
                  // 照抄下方 `onRealized` 的范式：落库**成功后**才关，失败保持不动
                  // （避免网络/库异常时误关，孩子看不到失败提示）。
                  onCollect: () async {
                    try {
                      await _collect(wish);
                    } catch (_) {
                      return; // 落库失败：详情卡不关，孩子可重试。
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  onChange: () => _change(wish, t),
                  onSelfFulfill: () => _selfFulfill(wish),
                  onDidIt: _didIt,
                  // R7-P0-01：显式进池走领域薄入口（source=Progress，不经目标闸门）。
                  onPutInPool: () => _putIntoPool(wish),
                  // 达成落库后关掉详情，孩子直接看到愿望已从树上移进愿望池。
                  onRealized: () {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 收藏箱 / 愿望池居中卡片弹窗（玄参 iPad 13 反馈 3）。
  ///
  /// 几何照抄 [_openDetail]：Dialog transparent + insetPadding(24,40) +
  /// maxHeight 85% 屏高 + 圆角24 + SingleChildScrollView。
  /// [content] 是已组装好的只读 body（[_boxContent] / [_poolContent]），
  /// 与整页分段共用同一份实现，避免重复渲染逻辑。
  ///
  /// 🔴 C136 需求 2：宽度不再写死 420，改由 [wishListDialogWidth] 按视口算并交给
  /// `SizedBox(width: ...)` 做 **tight** 约束（只当 maxWidth 用会收缩到内容固有宽）。
  /// ⚠️ 树上愿望的详情卡（[_openDetail]）玄参没提，保持 420 不动。
  void _openListDialog({
    required Key key,
    required String title,
    required Widget content,
  }) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final Size screen = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: SizedBox(
            width: wishListDialogWidth(screen.width),
            child: Container(
              key: key,
              constraints: BoxConstraints(
                maxHeight: screen.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF0),
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5A4321),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('wish_list_dialog_close'),
                            icon: const Icon(Icons.close),
                            tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      content,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    return L10nScope(
      child: Scaffold(
        appBar: AppBar(
          // 玄参 2026-11-19 美术接入：页面标题改「美好愿望」；wishTreeTitle
          // 保留供花园入口等其它复用点使用（key 本身不删，测试守卫仍绿）。
          title: Text(t.wishPageTitle),
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
              // 🔴 玄参 2026-11-19 美术接入：树上段改沉浸场景（背景/大树/三态蛋/
              // 三按钮），场景自带导航，故隐藏三段 chip 与悬浮许愿行；但两个
              // 方法保留（box/pool 段仍用 chip，_buildHangingRow 守源码断言）。
              if (_section != _WishSection.tree) _buildSectionSwitch(t),
              if (_section != _WishSection.tree) _buildHangingRow(t),
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

  /// 树上愿望 → 场景蛋（三态唯一判据仍走领域 [wishTreeFaceOf]）。
  ///
  /// 🔴 玄参 2026-11-20 布局返工：tree 段**只有一个占满 body 的全屏沉浸场景**。
  /// 背景 BoxFit.cover 铺满、大树真实树根像素压背景土坡、一愿望一蛋挂树冠下方；
  /// 原 WishCard 列表已删除（box/pool 段不受影响）。
  /// 三态选图：S1/S2 → 许愿蛋；S3 hasWays → 正在实现蛋；
  /// 达成蛋 egg_done 仍只用于愿望池段，不动。
  /// 🔴 iPad 13 反馈：蛋下不挂「小办法 N 个」青色角标；S3 办法证据下沉到
  /// 详情浮层的办法列表（见 [WishDetailBody]），树上蛋只呈现蛋图。
  Widget _buildTree(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishTreeProvider).value ?? <Wish>[];
          // 树上树按 treeSlot 升序（记忆锚点，不由时间冲掉）。
          final List<Wish> sorted = <Wish>[...wishes]
            ..sort((Wish a, Wish b) =>
                (a.treeSlot ?? 0).compareTo(b.treeSlot ?? 0));

          final List<WishEgg> eggs = <WishEgg>[];
          for (final Wish wish in sorted) {
            final List<Task> tasks =
                ref.watch(wishTasksFamilyProvider(wish.id)).value ??
                    <Task>[];
            final int wayCount = tasks.length;
            // R7-P0-02：蛋联动与 face 正交，复用唯一门控纯函数 wishTasksAllDone。
            final List<CheckIn> checkIns =
                ref.watch(wishTaskCheckInsFamilyProvider(wish.id)).value ??
                    <CheckIn>[];
            final bool tasksAllDone = wishTasksAllDone(
              tasks: tasks,
              checkIns: checkIns,
              now: _now,
            );
            final WishTreeFace face =
                wishTreeFaceOf(wish: wish, wayCount: wayCount);
            final WishTreeEgg egg =
                wishTreeEggOf(face: face, tasksAllDone: tasksAllDone);
            eggs.add(WishEgg(
              asset: wishTreeEggAssetOf(egg),
              label: wish.text,
              onTap: () => _openDetail(wish, t),
              // 接过真实页面测试的点击标识（原卡片载体 → 现在的蛋）。
              key: Key('wish_card_${wish.id}'),
            ));
          }

          return Stack(
            children: <Widget>[
              // 场景占满 Expanded 给到的全部空间（不再 0.56 切分）。
              WishTreeScene(
                key: const Key('wish_tree_scene'),
                eggs: eggs,
                // R7-P0-03 图3：底部三圆形按钮按手机系数缩，iPad 恒 1.0。
                actionScale: compactScaleOf(context),
                onStartWish: () => _startWish(t),
                // 🔴 iPad 13 反馈 3：收藏箱 / 愿望池改居中 Dialog 弹窗，
                // 不再 setState 切走 tree 段 —— tree 段永远是全屏场景。
                onOpenBox: () => _openListDialog(
                  key: const Key('wish_box_dialog'),
                  title: t.wishSceneBoxLabel,
                  content: _boxContent(t),
                ),
                onOpenPool: () => _openListDialog(
                  key: const Key('wish_pool_dialog'),
                  title: t.wishScenePoolLabel,
                  content: _poolContent(t),
                ),
                boxLabel: t.wishSceneBoxLabel,
                poolLabel: t.wishScenePoolLabel,
                startLabel: t.wishTreeStart,
                boxCount: _boxedCount(),
                poolCount: _poolCount(),
              ),
              // 空树提示浮在场景中部（不再依赖卡片列表位置）。
              if (sorted.isEmpty)
                Positioned.fill(
                  child: Center(
                    key: const Key('wish_tree_empty_tree'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCCFFFBF0),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        t.wishTreeEmptyTree,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8A7A66),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  /// 整页分段用的收藏箱 body（外层给滚动容器）。
  Widget _buildBox(AppLocalizations t) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: _boxContent(t),
      );

  /// 收藏箱只读内容：整页分段与居中弹窗共用同一份实现。
  Widget _boxContent(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishBoxedProvider).value ?? <Wish>[];
          return WishCollectionBox(
            wishes: wishes,
            t: t,
            highlightWishId: _highlightWishId,
            onRestore: (Wish wish) => _restore(wish, t),
          );
        },
      );

  /// 整页分段用的愿望池 body（外层给滚动容器）。
  Widget _buildPool(AppLocalizations t) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: _poolContent(t),
      );

  /// 愿望池只读内容：整页分段与居中弹窗共用同一份实现。
  ///
  /// 用 Column（有限高）而非 ListView，才能同时嵌进整页 SingleChildScrollView
  /// 与弹窗的 SingleChildScrollView，避免无界高度溢出。
  Widget _poolContent(AppLocalizations t) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          final List<Wish> wishes = ref.watch(wishPoolProvider).value ?? <Wish>[];
          final int stamped = ref.watch(wishStampedCountProvider).value ?? 0;
          final int milestone =
              WishOrchestrationService.poolMilestoneCount(stamped);
          // 里程碑演出幂等：current > last 才播，且立即写回 last。
          // 🔴 写回在 postFrame 完成，引用 mounted 守卫；弹窗与整页共用本 body
          // 时 provider 是同一实例，第二次构建读到新的 last 即不再触发。
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
          return Column(
            key: const Key('wish_tree_pool_list'),
            children: <Widget>[
              for (final Wish wish in wishes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: WishPoolTile(
                    wish: wish,
                    t: t,
                    milestoneCount: milestone,
                    highlight: _highlightWishId == wish.id,
                  ),
                ),
            ],
          );
        },
      );
}

/// 详情里「实现了」的唯一入口归属。
enum WishRealizeEntry {
  /// 非树上愿望（收藏箱 / 已终态）：不渲染任何达成入口。
  none,

  /// 愿望级主按钮（无手动办法，或办法卡都不承载达成入口）。
  wishCard,

  /// 第一条手动办法卡上的方盒（玄参截图右下角那枚）。
  firstManualTask,
}

/// 单一入口判据（纯函数，便于测试直接钉死）。
///
/// 玄参 iPad13 拍板：有手动办法时用办法卡那枚，没办法时用愿望主按钮；
/// 两条路径都不再看 `targetValue`。收藏箱 / 终态愿望一律不给入口。
///
/// 🔴 R6-P0-02⑤（成长任务闭环）：只要愿望挂了成长任务，就不再给愿望级
/// 「直接进池」主按钮（`wishCard`）——手动任务走「我做到了」提交链，
/// 纯专注任务由专注结算闭环。无任务愿望保持 v0.5 自助实现（Q2 逐字节不变）。
WishRealizeEntry wishRealizeEntryOf({
  required bool onTree,
  required List<Task> tasks,
}) {
  if (!onTree) return WishRealizeEntry.none;
  for (final Task task in tasks) {
    if (!task.requiresFocus) return WishRealizeEntry.firstManualTask;
  }
  if (tasks.isNotEmpty) return WishRealizeEntry.none;
  return WishRealizeEntry.wishCard;
}

// ── R7-P0-01 / R7-P0-02 单一派生纯函数（玄参真机反馈，v0.2） ────────────────

/// 详情卡「放进愿望池」按钮形态（R7-P0-01，单一判据）。
///
/// - [onTree]==false（收藏箱 / 终态）⇒ none（无进池入口，原样）；
/// - [hasManualTask] && [tasksAllDone] ⇒ putInPool（单个「放进愿望池」，隐藏两次级按钮）；
/// - 其余（含纯专注型 hasManualTask==false、无任务、有未完成任务）⇒ changeAndCollect（现状两按钮）。
///
/// [tasksAllDone] 由唯一纯函数 [wishTasksAllDone] 派生，本函数不再散写任务判据。
enum WishPoolButton { none, changeAndCollect, putInPool }

WishPoolButton wishPoolButtonOf({
  required bool onTree,
  required bool hasManualTask,
  required bool tasksAllDone,
}) {
  if (!onTree) return WishPoolButton.none;
  if (hasManualTask && tasksAllDone) return WishPoolButton.putInPool;
  return WishPoolButton.changeAndCollect;
}

/// 树上蛋形态（R7-P0-02，单一派生判据，face × 任务完成正交）。
///
/// - face != hasWays（hanging / parentResponded：无任务 / 家长未布置办法）⇒ wish（逐字节不变）；
/// - face == hasWays && !tasksAllDone ⇒ growing（现状）；
/// - face == hasWays && tasksAllDone ⇒ done（新增 eggDone）。
enum WishTreeEgg { wish, growing, done }

WishTreeEgg wishTreeEggOf({
  required WishTreeFace face,
  required bool tasksAllDone,
}) {
  if (face == WishTreeFace.hasWays && tasksAllDone) return WishTreeEgg.done;
  if (face == WishTreeFace.hasWays) return WishTreeEgg.growing;
  return WishTreeEgg.wish;
}

/// 蛋 → asset 映射留在展示层（复用 L7 `WishTreeArt`，不加图片资源）。
String wishTreeEggAssetOf(WishTreeEgg egg) => switch (egg) {
      WishTreeEgg.wish => WishTreeArt.eggWish,
      WishTreeEgg.growing => WishTreeArt.eggGrowing,
      WishTreeEgg.done => WishTreeArt.eggDone,
    };

/// 详情页主体（在浮层 scope 内构建，文案由页面取好经 [t] 传入）。
///
/// 🔴 唯一达成入口：由 [wishRealizeEntryOf] 决定渲染办法卡方盒**或**愿望主按钮，
/// 二者永不并存。确认后先落库（[onSelfFulfill]）再关详情（[onRealized]）。
class WishDetailBody extends ConsumerWidget {
  const WishDetailBody({
    super.key,
    required this.wish,
    required this.t,
    required this.now,
    required this.onCollect,
    required this.onChange,
    required this.onSelfFulfill,
    required this.onDidIt,
    required this.onRealized,
    this.onPutInPool,
  });

  final Wish wish;
  final AppLocalizations t;
  final DateTime now;
  final VoidCallback onCollect;
  final VoidCallback onChange;

  /// 领域层自助达成（页面级 service 调用；只有二次确认通过才会触发）。
  final Future<void> Function() onSelfFulfill;

  /// R7-P0-01：显式「放进愿望池」领域薄入口（页面级 service 调用；
  /// 由 WishCardDetail 的二次确认把住，取消不触发）。可空：非 putInPool 态不传。
  final Future<void> Function()? onPutInPool;

  /// R6-P0-02③：手动愿望任务「我做到了」→ `checkIn` 落 pending。
  ///
  /// 与 [onSelfFulfill] 是两条不同行为路径，不得互换。
  final Future<void> Function(Task task) onDidIt;

  /// 落库成功后关闭详情浮层，让孩子看到愿望已移入愿望池。
  final VoidCallback onRealized;

  Future<void> _realizeAndClose() async {
    await onSelfFulfill();
    onRealized();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // R6-P0-04：收藏箱里的愿望，其关联任务在详情也一并隐藏（派生，零写入）。
    final List<Task> tasks =
        (ref.watch(wishTasksFamilyProvider(wish.id)).value ?? <Task>[])
            .where(
              (Task task) => isWishTaskVisible(
                task: task,
                wishById: <String, Wish>{wish.id: wish},
              ),
            )
            .toList();
    final List<CheckIn> checkIns =
        ref.watch(wishTaskCheckInsFamilyProvider(wish.id)).value ?? <CheckIn>[];
    // v0.3.0：三态唯一判据（与树上卡片同源，禁止本处另写条件）。
    final WishTreeFace face =
        wishTreeFaceOf(wish: wish, wayCount: tasks.length);
    // R7-P0-01：onTree 判据一处算出，wishRealizeEntryOf 与 wishPoolButtonOf 共用。
    final bool onTree = wish.releasedAt == null && !wish.isTerminal;
    final WishRealizeEntry entry = wishRealizeEntryOf(
      onTree: onTree,
      tasks: tasks,
    );
    final bool useManualTask = entry == WishRealizeEntry.firstManualTask;
    // R7-P0-01①：任务全完成判据复用唯一纯函数，手动任务型才显进池按钮。
    final bool tasksAllDone = wishTasksAllDone(
      tasks: tasks,
      checkIns: checkIns,
      now: now,
    );
    final bool hasManualTask = tasks.any((Task task) => !task.requiresFocus);
    final WishPoolButton poolButton = wishPoolButtonOf(
      onTree: onTree,
      hasManualTask: hasManualTask,
      tasksAllDone: tasksAllDone,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WishCardDetail(
          wish: wish,
          t: t,
          waitDays: WishOrchestrationService.waitingDays(wish.createdAt, now),
          taskCount: tasks.length,
          face: face,
          canSelfFulfill: entry == WishRealizeEntry.wishCard,
          // R7-P0-01①：putInPool 态下发单按钮开关 + 文案 + 落库回调。
          canPutInPool: poolButton == WishPoolButton.putInPool,
          putInPoolLabel: t.wishDetailPutInPool,
          onPutInPool: poolButton == WishPoolButton.putInPool
              ? () async {
                  await onPutInPool?.call();
                  onRealized();
                }
              : null,
          confirmTitle: t.wishRealizedCongrats,
          confirmLabel: t.wishDetailRealized,
          cancelLabel: t.shared_cancel,
          onCollectToBox: onCollect,
          onChangeWish: onChange,
          onSelfFulfill: entry == WishRealizeEntry.wishCard
              ? () => _realizeAndClose()
              : null,
        ),
        if (tasks.isNotEmpty) ...<Widget>[
          // 🔴 玄参 iPad13 反馈：「小办法 N 个」列表标题已删除，
          // 办法证据直接由下面的 WishTaskCard 承载。
          const SizedBox(height: 8),
          for (final Task task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WishTaskCard(
                task: task,
                wishTitle: wish.text,
                focusActionLabel: t.wishTaskGoFocus,
                // R6-P0-02①：有任务愿望的按钮文案 = 「我做到了」，复用既有 key。
                didItLabel: t.wishTaskDidIt,
                // R6-P0-02②/③：确认卡改为「提交后等家长确认…」，
                // 不再预告「愿望实现」（那时还没经家长核销）。
                confirmTitle: task.requiresFocus
                    ? t.wishRealizedCongrats
                    : t.wishTaskSubmitConfirm,
                startFocusLabel: t.wishTaskGoFocus,
                cancelLabel: t.shared_cancel,
                doneLabel: t.wishTaskDone,
                pendingLabel: t.wishTaskPending,
                // 每条手动任务都有提交入口（门控要求全部任务 verified）；
                // 「唯一入口」由 wishRealizeEntryOf 在愿望级把住，不再有
                // 任何「直接进池」按钮与这些提交按钮并存。
                showDidIt: useManualTask && !task.requiresFocus,
                // R6-P0-02④：pending / done 由打卡流水派生，卡片显示只读胶囊。
                done: wishTaskStageOf(
                        task: task, checkIns: checkIns, now: now) ==
                    WishTaskStage.done,
                pending: wishTaskStageOf(
                        task: task, checkIns: checkIns, now: now) ==
                    WishTaskStage.awaitingVerify,
                onDidIt: useManualTask && !task.requiresFocus
                    ? () => onDidIt(task)
                    : null,
              ),
            ),
        ],
      ],
    );
  }
}
