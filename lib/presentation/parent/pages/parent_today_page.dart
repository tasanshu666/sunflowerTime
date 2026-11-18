/// 家长端「今日」页（§4.3 / §5 T-F）：家长监管「今天该处理的事」。
///
/// 两块内容（自上而下）：
///  · **待确认的成长项**（M4 家长监管）：孩子对**非联动成长项**点「我做到了」后落 pending
///    （当期不发阳光），在此由家长「确认发放」或「驳回」。数据来源
///    `TaskCheckInService.pendingCheckIns()`（**不限今日**，按提交时间升序）。列表为空时
///    **整张卡（含标题）都不渲染**。
///  · **待核销奖励**：`RedemptionOrchestrationService.pendingList()` 的兑换申请核销卡。
///
/// 注：刷新统一用**块体**闭包 `setState(() { _future = _load(); })`。
/// 若写成箭头体 `setState(() => _future = _load())`，闭包会把赋值结果（Future）
/// 作为返回值交给 setState，触发 debug 断言
/// 「setState() callback argument returned a Future」，且 markNeedsBuild 不会执行
/// → 界面不刷新、异常被上层 catch 成「核销失败」（真机 BUG 复现）。
library parent_today_page;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/parent/widgets/parent_wish_action_sheet.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';
import 'package:sunflower_time/presentation/parent/widgets/wish_task_editor.dart';
import 'package:sunflower_time/presentation/parent/widgets/wish_tree_section.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/core/i18n/error_l10n.dart';
import 'package:sunflower_time/core/i18n/seed_l10n.dart';

/// 「今日」页：待确认的成长项 + 待核销奖励。
class ParentTodayPage extends ConsumerStatefulWidget {
  const ParentTodayPage({super.key});

  @override
  ConsumerState<ParentTodayPage> createState() => _ParentTodayPageState();
}

class _ParentTodayPageState extends ConsumerState<ParentTodayPage> {
  late Future<_TodayData> _future;

  @override
  void initState() {
    super.initState();
    // 🔴 A21.2：家长端今日页原本零订阅 —— 必须 listenManual 订阅经济修订号，
    //    否则孩子许愿 / 家长写操作后本页不刷新。
    // ⚠️ 必须 listenManual：ref.listen 在 initState 会抛断言。
    ref.listenManual(economyRevisionProvider, (_, __) {
      if (mounted) _reload();
    });
    // 切孩子快照失效：仅本场景使用档案修订号，跨端刷新仍走 economyRevision。
    ref.listenManual(childProfileRevisionProvider, (_, __) {
      if (mounted) _reload();
    });
    _future = _load();
  }

  /// 重新拉取（块体闭包，避免把 Future 返回给 setState）。
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 并发拉取待确认成长项 + 待处理兑换列表与模板 + 许愿树数据，并构建映射。
  Future<_TodayData> _load() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      ref.read(taskCheckInServiceProvider).pendingCheckIns(),
      ref.read(redemptionOrchestrationServiceProvider).pendingList(),
      ref.read(rewardRepositoryProvider).templates(),
      _loadWishDesk(),
    ]);
    final List<PendingCheckIn> pendingCheckIns =
        results[0] as List<PendingCheckIn>;
    final List<RedemptionRequest> requests =
        results[1] as List<RedemptionRequest>;
    final List<RewardTemplate> templates = results[2] as List<RewardTemplate>;
    final _WishDeskData wishDesk = results[3] as _WishDeskData;
    final Map<String, RewardTemplate> templateMap =
        <String, RewardTemplate>{for (final RewardTemplate t in templates) t.id: t};
    return _TodayData(
      pendingCheckIns: pendingCheckIns,
      requests: requests,
      templates: templateMap,
      wishEntries: wishDesk.entries,
      selfFulfilled: wishDesk.selfFulfilled,
      wishService: wishDesk.service,
      allPendingCheckIns: pendingCheckIns,
    );
  }

  /// 许愿树只读装配：树上愿望 + 每条的任务 / 待核销打卡 + 孩子自助达成列表。
  ///
  /// 待核销打卡从 [taskCheckInServiceProvider] 再取一次（同一份流水），按任务
  /// 归属拆给各愿望；异常降级为空，今日页核心卡不受愿望数据影响。
  Future<_WishDeskData> _loadWishDesk() async {
    // 读服务本身也纳入降级：家长首页在部分测试桩里以简化的 task 仓储挂载，
    // 愿望数据不可用时今日页核心卡（待核销 / 兑换）仍照常工作。
    final WishOrchestrationService? service;
    try {
      service = ref.read(wishOrchestrationServiceProvider);
    } catch (_) {
      return const _WishDeskData(entries: <WishDeskEntry>[]);
    }
    try {
      final WishOrchestrationService svc = service!;
      final DateTime now = DateTime.now();
      final List<Wish> wishes = await svc.parentDeskList(now);
      final List<PendingCheckIn> pendingCheckIns =
          await ref.read(taskCheckInServiceProvider).pendingCheckIns();
      final List<WishDeskEntry> entries = <WishDeskEntry>[];
      for (final Wish wish in wishes) {
        final List<Task> tasks = await svc.tasksOf(wishId: wish.id, now: now);
        final Set<String> taskIds =
            tasks.map((Task task) => task.id).toSet();
        final List<PendingCheckIn> pending = <PendingCheckIn>[
          for (final PendingCheckIn p in pendingCheckIns)
            if (p.task != null && taskIds.contains(p.task!.id)) p,
        ];
        final List<CheckIn> checkIns = <CheckIn>[
          for (final PendingCheckIn p in pending) p.checkIn,
        ];
        entries.add(WishDeskEntry(
          wish: wish,
          tasks: tasks,
          checkIns: checkIns,
          pending: pending,
        ));
      }
      // 「孩子说做到了」= 达成池里 fulfill_source = child 的愿望。
      final List<Wish> pool = await svc.poolWishes();
      final List<Wish> selfFulfilled = <Wish>[
        for (final Wish w in pool)
          if (w.fulfillSource == kWishFulfillSourceChild) w,
      ];
      return _WishDeskData(
        entries: entries,
        selfFulfilled: selfFulfilled,
        service: service,
      );
    } catch (_) {
      return _WishDeskData(entries: const <WishDeskEntry>[], service: service);
    }
  }

  /// 单张待核销奖励卡（模板可能缺失 → 兜底「未知奖励」）。
  Widget _requestCard(_TodayData data, RedemptionRequest req) {
    final AppLocalizations t = l10nOf(context);
    final RewardTemplate? tpl = data.templates[req.templateId];
    final RewardTemplate template = tpl ??
        RewardTemplate(
          id: req.templateId,
          name: t.parent_today_unknown_reward,
          category: RewardCategory.parentHandled,
          baseCost: req.cost,
          frequencyLimitPerWeek: 1,
        );
    return VerificationCard(
      request: req,
      template: template,
      onResolved: _reload,
    );
  }

  // ── 许愿树三动作 / 核销 / 撤销回调 ──────────────────────────────────────

  void _snackWish(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 动作①：设定目标 + 布置任务（WishTaskEditor 两页签弹层）。
  Future<void> _openSetup(WishDeskEntry entry) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => WishTaskEditor(
        wish: entry.wish,
        initialTasks: entry.tasks,
        onSaved: () {
          ref.read(economyRevisionProvider.notifier).state++;
        },
      ),
    );
    if (saved == true && mounted) _reload();
  }

  /// 动作③：贴标签 + 温柔回复（ParentWishActionSheet → tagWithReply）。
  Future<void> _openTag(WishDeskEntry entry) async {
    // 已有标签回填到表单（枚举 name → 枚举）。
    WishTag? initialTag;
    if (entry.wish.tagKey != null) {
      for (final WishTag tag in WishTag.values) {
        if (tag.name == entry.wish.tagKey) {
          initialTag = tag;
          break;
        }
      }
    }
    final WishTagReplyResult? result = await showDialog<WishTagReplyResult>(
      context: context,
      builder: (BuildContext ctx) => ParentWishActionSheet(
        wish: entry.wish,
        initialTag: initialTag,
        initialReply: entry.wish.parentReply,
        onSetup: () {
          Navigator.of(ctx).pop(null);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openSetup(entry);
          });
        },
        onFulfill: () {
          Navigator.of(ctx).pop(null);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _confirmFulfill(entry.wish);
          });
        },
        onTagReply: (WishTagReplyResult r) => Navigator.of(ctx).pop(r),
      ),
    );
    if (result == null || !mounted) return;
    // 未选标签、未填回信 ⇒ 无操作（表单允许全空跳过）。
    if (result.tag == null && (result.reply == null || result.reply!.isEmpty)) {
      return;
    }
    try {
      final WishTag tag = result.tag ?? WishTag.needMoreTime;
      await ref.read(wishOrchestrationServiceProvider).tagWithReply(
            id: entry.wish.id,
            tag: tag,
            reply: result.reply,
            now: DateTime.now(),
          );
      if (!mounted) return;
      ref.read(economyRevisionProvider.notifier).state++;
      _reload();
    } catch (e) {
      if (!mounted) return;
      _snackWish('$e');
    }
  }

  /// 动作②：直接实现（二次确认 → fulfill，写 fulfill_source=parentAction）。
  Future<void> _confirmFulfill(Wish wish) async {
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_wish_action_fulfill),
        content: Text(t.parent_wish_fulfill_confirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_wish_action_fulfill),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(wishOrchestrationServiceProvider).fulfill(
            id: wish.id,
            now: DateTime.now(),
          );
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      _snackWish('$e');
    }
  }

  /// 撤销：「孩子说做到了」→ 退回树上（二次确认 → undoFulfill，唯一反向边）。
  Future<void> _confirmUndo(Wish wish) async {
    final AppLocalizations t = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_wish_undo),
        content: Text(t.parent_wish_undo_confirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_wish_undo),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(wishOrchestrationServiceProvider).undoFulfill(
            id: wish.id,
            now: DateTime.now(),
          );
      if (!mounted) return;
      ref.read(economyRevisionProvider.notifier).state++;
      _reload();
    } catch (e) {
      if (!mounted) return;
      _snackWish('$e');
    }
  }

  /// 行为型愿望任务核销（走既有 check_ins 流水 → CAS + 推进进度）。
  Future<void> _verifyWishTask(PendingCheckIn item) async {
    final AppLocalizations t = l10nOf(context);
    try {
      final TaskCheckInOutcome outcome = await ref
          .read(taskCheckInServiceProvider)
          .verifyCheckIn(item.checkIn.id, DateTime.now());
      if (!mounted) return;
      final String granted = outcome.granted == outcome.granted.roundToDouble()
          ? outcome.granted.toStringAsFixed(0)
          : outcome.granted.toStringAsFixed(1);
      _snackWish(t.parent_today_confirm_ok_snack(granted, ''));
      ref.read(economyRevisionProvider.notifier).state++;
      _reload();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      _snackWish(t.parent_today_confirm_fail_snack(taskCheckInErrorMessage(e, t)));
    } catch (e) {
      if (!mounted) return;
      _snackWish(t.parent_today_confirm_fail_snack(e));
    }
  }

  /// 行为型愿望任务驳回（原因必填 → rejectCheckIn）。
  Future<void> _rejectWishTask(PendingCheckIn item) async {
    final AppLocalizations t = l10nOf(context);
    String reason = '';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_today_reject_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              decoration: InputDecoration(labelText: t.parent_today_reject_reason),
              maxLines: 2,
              onChanged: (String v) => reason = v,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            onPressed: () {
              if (reason.trim().isEmpty) return; // 原因必填。
              Navigator.of(ctx).pop(true);
            },
            child: Text(t.parent_today_reject_ok),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(taskCheckInServiceProvider).rejectCheckIn(
            item.checkIn.id,
            note: reason.trim(),
            now: DateTime.now(),
          );
      if (!mounted) return;
      _snackWish(t.parent_today_rejected_snack);
      ref.read(economyRevisionProvider.notifier).state++;
      _reload();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      _snackWish(t.parent_today_reject_fail_snack(taskCheckInErrorMessage(e, t)));
    } catch (e) {
      if (!mounted) return;
      _snackWish(t.parent_today_reject_fail_snack(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析；Builder 的
    // context 位于 scope 之下。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return FutureBuilder<_TodayData>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<_TodayData> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                // §7.5：DAO 异常向上抛，UI 降级提示 + 重试。
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(l10n.shared_load_failed('${snap.error}')),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _reload,
                        child: Text(l10n.shared_retry),
                      ),
                    ],
                  ),
                );
              }

              final _TodayData data = snap.data!;
              final bool hasPending = data.pendingCheckIns.isNotEmpty;
              final bool hasRequests = data.requests.isNotEmpty;
              final bool hasWishes =
                  data.wishEntries.isNotEmpty || data.selfFulfilled.isNotEmpty;

              final List<Widget> cards = <Widget>[
                if (hasPending)
                  _PendingCheckInsCard(
                    items: data.pendingCheckIns,
                    onResolved: _reload,
                  ),
                // A21.1：许愿树区块 —— _PendingCheckInsCard 之后、兑换请求之前。
                if (hasWishes) const SizedBox(height: 20),
                if (hasWishes)
                  WishTreeSection(
                    entries: data.wishEntries,
                    service: data.wishService!,
                    selfFulfilled: data.selfFulfilled,
                    onSetup: (WishDeskEntry entry) => _openSetup(entry),
                    onFulfill: (WishDeskEntry entry) =>
                        _confirmFulfill(entry.wish),
                    onTag: (WishDeskEntry entry) => _openTag(entry),
                    onVerify: _verifyWishTask,
                    onReject: _rejectWishTask,
                    onUndo: _confirmUndo,
                  ),
                if ((hasPending || hasWishes) && hasRequests)
                  const SizedBox(height: 20),
                for (final RedemptionRequest req in data.requests)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _requestCard(data, req),
                  ),
              ];
              if (!hasPending && !hasRequests && !hasWishes) {
                cards.add(Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(l10n.parent_today_empty,
                        style: const TextStyle(fontSize: 18)),
                  ),
                ));
              }
              // 调试期临时开关（仅 debug 构建渲染，release 自动消失）。
              // 🔴 2026-10-19（玄参）：截商店图时这张卡会入镜 → 构建期开关 [kHideDebugUi]
              // （`--dart-define=HIDE_DEBUG_UI=true`）可显式关闭；默认仍显示。
              if (shouldShowDebugUi(
                debugMode: kDebugMode,
                hideForScreenshots: kHideDebugUi,
              )) {
                cards.add(const _DebugCapSwitchCard());
              }

              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: cards,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 「今日」页加载结果（待确认成长项 + 待处理申请 + 模板映射 + 许愿树数据）。
class _TodayData {
  final List<PendingCheckIn> pendingCheckIns;
  final List<RedemptionRequest> requests;
  final Map<String, RewardTemplate> templates;
  final List<WishDeskEntry> wishEntries;
  final List<Wish> selfFulfilled;
  final WishOrchestrationService? wishService;
  final List<PendingCheckIn> allPendingCheckIns;

  const _TodayData({
    required this.pendingCheckIns,
    required this.requests,
    required this.templates,
    this.wishEntries = const <WishDeskEntry>[],
    this.selfFulfilled = const <Wish>[],
    this.wishService,
    this.allPendingCheckIns = const <PendingCheckIn>[],
  });
}

/// 许愿树装配中间结果。
class _WishDeskData {
  const _WishDeskData({
    required this.entries,
    this.selfFulfilled = const <Wish>[],
    this.service,
  });

  final List<WishDeskEntry> entries;
  final List<Wish> selfFulfilled;
  final WishOrchestrationService? service;
}

/// 调试期临时开关卡（**仅 kDebugMode 渲染**，release 自动消失）。
///
/// 玄参 2026-09-29：调试期间默认**打开** = 跳过 30 分钟防沉迷限时；
/// 关掉后恢复拦截。状态存 shared_preferences（`kPrefDebugCapBypass`），
/// 孩子端外壳（ChildShellPage）进入时读取。
class _DebugCapSwitchCard extends ConsumerStatefulWidget {
  const _DebugCapSwitchCard();

  @override
  ConsumerState<_DebugCapSwitchCard> createState() =>
      _DebugCapSwitchCardState();
}

class _DebugCapSwitchCardState extends ConsumerState<_DebugCapSwitchCard> {
  bool _bypass = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bool v = await ref.read(settingsStoreProvider).debugCapBypass();
      if (!mounted) return;
      setState(() => _bypass = v);
    } catch (_) {
      // 读失败 → 保持默认 true（调试期绕过）。
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _bypass = v);
    final AppLocalizations t = l10nOf(context);
    try {
      await ref.read(settingsStoreProvider).setDebugCapBypass(v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v
            ? t.parent_today_debug_cap_on_snack
            : t.parent_today_debug_cap_off_snack),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bypass = !v); // 写失败回滚。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.parent_today_debug_save_fail_snack)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        decoration: creamCardDecoration(),
        // C54（玄参 2026-10-10 测试暴露）：`SwitchListTile` 内含 `ListTile`，而
        // `ListTile` 要求**最近的 Material 祖先**承载其背景/水波纹；此处外层是
        // `creamCardDecoration()` 的带色 `DecoratedBox`，Flutter 会断言
        // 「ListTile background color or ink splashes may be invisible」。
        // 垫一层透明 Material 即可让水波正确落在卡片内（视觉零变化）。
        child: Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: _bypass,
            onChanged: _toggle,
            activeThumbColor: const Color(0xFF64B5F6),
            title: Text(
              t.parent_today_debug_cap_title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              t.parent_today_debug_cap_subtitle,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「待确认的成长项」卡片（M4 家长监管）。列表为空时调用方整体不渲染。
class _PendingCheckInsCard extends StatelessWidget {
  final List<PendingCheckIn> items;

  /// 处理完一条后的回调（父列表刷新，使该条消失）。
  final VoidCallback? onResolved;

  const _PendingCheckInsCard({required this.items, this.onResolved});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    return Container(
      decoration: creamCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.hourglass_top, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.parent_today_pending_title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(t.parent_today_count(items.length),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            for (final PendingCheckIn p in items)
              _PendingCheckInTile(item: p, onResolved: onResolved),
          ],
        ),
      ),
    );
  }
}

/// 单条待确认成长项：名称 / 提交时间 / 应发阳光 + 「确认发放」「驳回」。
///
/// 金额取 `checkIn.sunlightGross`（**应发**；pending 阶段 `sunlightGranted` 恒为 0，
/// 不能拿它当「待核销」判据）。确认发放后由服务按当日软顶差额入账。
class _PendingCheckInTile extends ConsumerStatefulWidget {
  final PendingCheckIn item;
  final VoidCallback? onResolved;

  const _PendingCheckInTile({required this.item, this.onResolved});

  @override
  ConsumerState<_PendingCheckInTile> createState() => _PendingCheckInTileState();
}

class _PendingCheckInTileState extends ConsumerState<_PendingCheckInTile> {
  bool _busy = false;

  /// 阳光数值展示：整数不带小数，否则保留 1 位。
  String _fmtSun(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// 确认发放：家长核销通过 → 入账 → 刷新（该条消失）。
  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final AppLocalizations t = l10nOf(context);
    try {
      final TaskCheckInOutcome outcome = await ref
          .read(taskCheckInServiceProvider)
          .verifyCheckIn(widget.item.checkIn.id, DateTime.now());
      if (!mounted) return;
      final String capped = outcome.cappedByDailyCap
          ? t.parent_today_capped_note(_fmtSun(outcome.granted))
          : '';
      _snack(t.parent_today_confirm_ok_snack(
        _fmtSun(outcome.granted),
        capped,
      ));
      // 同步孩子端：自增经济修订号 → 今日卡 / 成长 / 商店 / 花园刷新。
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // i18n B3（T03）：领域层只回语义码，文案经单点映射装配。
      _snack(t.parent_today_confirm_fail_snack(taskCheckInErrorMessage(e, t)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(t.parent_today_confirm_fail_snack(e));
    }
  }

  /// 驳回：可选理由 → 不发放、状态置 rejected、从待办消失。
  Future<void> _reject() async {
    if (_busy) return;
    final AppLocalizations t = l10nOf(context);
    String note = '';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.parent_today_reject_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.parent_today_reject_body(
              // F154：预制任务显示名跟随当前语言。
              widget.item.task != null
                  ? taskDisplayName(
                      widget.item.task!.id, widget.item.task!.name, t)
                  : t.parent_today_deleted_task,
            )),
            const SizedBox(height: 8),
            TextField(
              decoration:
                  InputDecoration(labelText: t.parent_today_reject_reason),
              maxLines: 2,
              onChanged: (String v) => note = v,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.shared_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.parent_today_reject_ok),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(taskCheckInServiceProvider).rejectCheckIn(
            widget.item.checkIn.id,
            note: note.trim().isEmpty ? null : note.trim(),
            now: DateTime.now(),
          );
      if (!mounted) return;
      _snack(t.parent_today_rejected_snack);
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(t.parent_today_reject_fail_snack(taskCheckInErrorMessage(e, t)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(t.parent_today_reject_fail_snack(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final PendingCheckIn p = widget.item;
    // F154：预制任务显示名跟随当前语言（自定义/改过名原样）。
    final String name = p.task != null
        ? taskDisplayName(p.task!.id, p.task!.name, t)
        : t.parent_today_deleted_task;
    final String submitted =
        DateFormat('yyyy-MM-dd HH:mm').format(p.checkIn.completedAt);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t.parent_today_should_grant(_fmtSun(p.checkIn.sunlightGross)),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(t.parent_today_submitted_at(submitted),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: !_busy ? _reject : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(t.parent_today_btn_reject),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: !_busy ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t.parent_today_btn_confirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
