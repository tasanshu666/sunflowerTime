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

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

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
    _future = _load();
  }

  /// 重新拉取（块体闭包，避免把 Future 返回给 setState）。
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// 并发拉取待确认成长项 + 待处理兑换列表与模板，并构建映射。
  Future<_TodayData> _load() async {
    final List<PendingCheckIn> pendingCheckIns =
        await ref.read(taskCheckInServiceProvider).pendingCheckIns();
    final List<RedemptionRequest> requests =
        await ref.read(redemptionOrchestrationServiceProvider).pendingList();
    final List<RewardTemplate> templates =
        await ref.read(rewardRepositoryProvider).templates();
    final Map<String, RewardTemplate> templateMap =
        <String, RewardTemplate>{for (final RewardTemplate t in templates) t.id: t};
    return _TodayData(
      pendingCheckIns: pendingCheckIns,
      requests: requests,
      templates: templateMap,
    );
  }

  /// 单张待核销奖励卡（模板可能缺失 → 兜底「未知奖励」）。
  Widget _requestCard(_TodayData data, RedemptionRequest req) {
    final RewardTemplate? tpl = data.templates[req.templateId];
    final RewardTemplate template = tpl ??
        RewardTemplate(
          id: req.templateId,
          name: '未知奖励',
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

  @override
  Widget build(BuildContext context) {
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
                Text('加载失败：${snap.error}'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _reload,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        final _TodayData data = snap.data!;
        final bool hasPending = data.pendingCheckIns.isNotEmpty;
        final bool hasRequests = data.requests.isNotEmpty;

        final List<Widget> cards = <Widget>[
          if (hasPending)
            _PendingCheckInsCard(
              items: data.pendingCheckIns,
              onResolved: _reload,
            ),
          if (hasPending && hasRequests) const SizedBox(height: 20),
          for (final RedemptionRequest req in data.requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _requestCard(data, req),
            ),
        ];
        if (!hasPending && !hasRequests) {
          cards.add(const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('暂无待确认奖励 🎉', style: TextStyle(fontSize: 18)),
            ),
          ));
        }
        // 调试期临时开关（仅 debug 构建渲染，release 自动消失）。
        if (kDebugMode) cards.add(const _DebugCapSwitchCard());

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
  }
}

/// 「今日」页加载结果（待确认成长项 + 待处理申请 + 模板映射）。
class _TodayData {
  final List<PendingCheckIn> pendingCheckIns;
  final List<RedemptionRequest> requests;
  final Map<String, RewardTemplate> templates;

  const _TodayData({
    required this.pendingCheckIns,
    required this.requests,
    required this.templates,
  });
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
    try {
      await ref.read(settingsStoreProvider).setDebugCapBypass(v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v ? '已跳过 30 分钟限时（调试）' : '已恢复 30 分钟限时拦截'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bypass = !v); // 写失败回滚。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            title: const Text(
              '🧪 调试：跳过 30 分钟限时',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '调试期间默认开启（不进限时状态）；关闭后恢复防沉迷拦截。仅调试包可见。',
              style: TextStyle(fontSize: 12),
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
                const Expanded(
                  child: Text(
                    '待确认的成长项',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Text('${items.length} 项',
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
    try {
      final TaskCheckInOutcome outcome = await ref
          .read(taskCheckInServiceProvider)
          .verifyCheckIn(widget.item.checkIn.id, DateTime.now());
      if (!mounted) return;
      final String capped = outcome.cappedByDailyCap
          ? '（今日成长奖励已达上限，本次只到账 ${_fmtSun(outcome.granted)} ☀）'
          : '';
      _snack('已确认发放，+${_fmtSun(outcome.granted)} 阳光 🌻$capped');
      // 同步孩子端：自增经济修订号 → 今日卡 / 成长 / 商店 / 花园刷新。
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('确认失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('确认失败：$e');
    }
  }

  /// 驳回：可选理由 → 不发放、状态置 rejected、从待办消失。
  Future<void> _reject() async {
    if (_busy) return;
    String note = '';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('驳回这项成长？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('将不发放「${widget.item.task?.name ?? '（已删除的成长项）'}」的阳光。'),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: '理由（选填）'),
              maxLines: 2,
              onChanged: (String v) => note = v,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认驳回'),
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
      _snack('已驳回 🌞 这项不会发阳光');
      ref.read(economyRevisionProvider.notifier).state++;
      widget.onResolved?.call();
    } on TaskCheckInException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('驳回失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('驳回失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final PendingCheckIn p = widget.item;
    final String name = p.task?.name ?? '（已删除的成长项）';
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
                  '应发 ${_fmtSun(p.checkIn.sunlightGross)} 阳光',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('提交于 $submitted',
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
                  child: const Text('驳回'),
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
                      : const Text('确认发放'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
