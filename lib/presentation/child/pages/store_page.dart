/// 孩子端阳光商店页（M2 T-E，§4.1）。
///
/// 行为：
///  1. 读 settingsProvider 拿当前 AgeTier；
///  2. 取全部奖励模板，按家长设定价（baseCost，不再叠加分龄系数 K）展示与扣费；
///  3. 逐模板查本周冷却（cooldownCount >= 该模板 frequencyLimitPerWeek 进入禁用态；
///     frequencyLimitPerWeek <= 0 视为不限次数）；
///  4. 点兑换 → **弹窗二次确认** → 调 submit()，按 SubmitOutcome 反馈；成功后刷新。
///
/// 展示口径（真机反馈收敛）：
///  · 待核销阳光只在 AppBar 右上角展示（实际 + 灰色待核销），
///    不再重复渲染顶部汇总条与底部「待家长核销」列表；
///  · 逐模板的待核销笔数由卡片内联提示「待家长核销 / 代家长核销 +N」承载。
library store_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/domain/services/redemption_orchestration_service.dart';
import 'package:sunflower_time/presentation/child/widgets/reward_card.dart';

/// 商店数据载荷：当前档位 + 模板列表 + 逐模板冷却态 + 各模板待核销笔数。
class _StoreLoad {
  final AgeTier tier;
  final List<RewardTemplate> templates;
  final Map<String, bool> onCooldown;
  final List<RedemptionRequest> pending; // pending + queued（待家长处理）
  final Map<String, bool> hasActive; // templateId -> 存在未核销申请
  final Map<String, int> pendingCount; // templateId -> 待核销笔数
  final Map<String, bool> hasQueued; // templateId -> 存在排队中申请（次月释放）
  final Map<String, String> queuedId; // templateId -> 排队申请 id（供撤销）

  const _StoreLoad({
    required this.tier,
    required this.templates,
    required this.onCooldown,
    required this.pending,
    required this.hasActive,
    required this.pendingCount,
    this.hasQueued = const <String, bool>{},
    this.queuedId = const <String, String>{},
  });
}

/// 商店数据：档位 + 全部模板 + 逐模板冷却态 + 待核销申请（随 [economyRevisionProvider] 重算）。
final _storeLoadProvider = FutureProvider<_StoreLoad>((ref) async {
  // 依赖经济修订号：家长端「核销/拒绝」或孩子端兑换后自增 → 本 provider 重算，
  // 避免家长端处理完返回孩子端时仍显示旧缓存（待核销总额/卡片禁用态不同步）。
  ref.watch(economyRevisionProvider);
  final AppSettings settings = await ref.watch(settingsProvider.future);
  final RewardRepository rewardRepo = ref.watch(rewardRepositoryProvider);
  final List<RewardTemplate> templates = await rewardRepo.templates();
  final Map<String, bool> cooldown = <String, bool>{};
  final List<RedemptionRequest> pending = await rewardRepo.pendingAndQueued();
  final Map<String, bool> hasActive = <String, bool>{};
  final Map<String, int> pendingCount = <String, int>{};
  final Map<String, bool> hasQueued = <String, bool>{};
  final Map<String, String> queuedId = <String, String>{};
  for (final RedemptionRequest r in pending) {
    pendingCount[r.templateId] = (pendingCount[r.templateId] ?? 0) + 1;
    if (r.status == RequestStatus.queued) {
      hasQueued[r.templateId] = true; // 排队中 → 次月释放
      queuedId[r.templateId] = r.id;
    } else {
      hasActive[r.templateId] = true; // 待核销（pending）→ 该模板卡显示待核销提示
    }
  }
    for (final RewardTemplate t in templates) {
      final int count =
          await rewardRepo.cooldownCount(t.id, CooldownPeriod.weekly);
      // 按模板各自的每周限领次数放行（frequencyLimitPerWeek<=0 视为不限）。
      cooldown[t.id] = t.frequencyLimitPerWeek > 0 && count >= t.frequencyLimitPerWeek;
    }
  return _StoreLoad(
    tier: settings.ageTier,
    templates: templates,
    onCooldown: cooldown,
    pending: pending,
    hasActive: hasActive,
    pendingCount: pendingCount,
    hasQueued: hasQueued,
    queuedId: queuedId,
  );
});

/// 当前阳光余额（实际可用，未扣待核销）；随 [economyRevisionProvider] 重算。
final _balanceProvider = FutureProvider<double>((ref) {
  ref.watch(economyRevisionProvider); // 家长端核销后会扣账本，余额需重算
  return ref.watch(sunlightRepositoryProvider).balance();
});

/// 正在提交兑换的模板 id（防止并发点击）。
final _submittingProvider = StateProvider<String?>((ref) => null);

class StorePage extends ConsumerStatefulWidget {
  const StorePage({super.key});

  @override
  ConsumerState<StorePage> createState() => _StorePageState();
}

class _StorePageState extends ConsumerState<StorePage> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<double> balanceAsync = ref.watch(_balanceProvider);
    final AsyncValue<_StoreLoad> loadAsync = ref.watch(_storeLoadProvider);
    // 待核销阳光总额（pending + queued，均未扣账本），用于右上角灰色小字。
    final int pendingTotal = loadAsync.maybeWhen(
      data: (load) =>
          load.pending.fold(0, (int s, RedemptionRequest r) => s + r.cost),
      orElse: () => 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('阳光商店'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: balanceAsync.when(
                data: (double b) {
                  // 金色 = 可用余额（账本余额 − 已兑换未扣的阳光）。
                  // 注意：pending / queued 按 §7.4 不变式 **不扣账本/不扣池**，
                  // 此处仅在展示口径上做减法，绝不真去扣账本或扣池（否则违反项目不变式）。
                  final int available = (b - pendingTotal).round();
                  final int golden = available < 0 ? 0 : available;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '☀ $golden',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.brown.shade700,
                        ),
                      ),
                      if (pendingTotal > 0) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          '待核销 $pendingTotal',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      body: loadAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('加载失败：$e')),
        data: (load) => _buildBody(load),
      ),
    );
  }

  Widget _buildBody(_StoreLoad load) {
    final String? submittingId = ref.watch(_submittingProvider);

    // 空态：模板列表为空时给一个友好提示，避免「纯黑空白页」这种无声故障。
    if (load.templates.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                '商店还没上架奖励，请让家长先添加奖励模板',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final List<Widget> children = <Widget>[];
    for (final RewardTemplate tpl in load.templates) {
      final int cost = tpl.baseCost;
      final bool onCd = load.onCooldown[tpl.id] ?? false;
      final bool active = load.hasActive[tpl.id] ?? false;
      final bool queued = load.hasQueued[tpl.id] ?? false;
      final bool submitting = submittingId == tpl.id;
      children.add(RewardCard(
        template: tpl,
        costForTier: cost,
        onCooldown: onCd,
        hasActiveRequest: active,
        pendingCount: load.pendingCount[tpl.id] ?? 0,
        weeklyLimit: tpl.frequencyLimitPerWeek,
        submitting: submitting,
        hasQueuedRequest: queued,
        onCancelQueue: queued
            ? () => _onCancelQueue(tpl, load.queuedId[tpl.id])
            : null,
        onRedeem: (onCd || active || queued || submitting)
            ? null
            : () => _onRedeem(tpl, cost, load.tier),
      ));
      children.add(const SizedBox(height: 12));
    }

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  /// 发起一笔兑换：先弹窗二次确认（防误点）→ 写 submitting 态 → submit → 反馈 → 刷新。
  Future<void> _onRedeem(RewardTemplate tpl, int cost, AgeTier tier) async {
    if (ref.read(_submittingProvider) != null) return; // 防并发
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认兑换？'),
        content: Text(
          '确定要用 $cost 阳光兑换「${tpl.name}」吗？\n'
          '提交后需家长核销，核销通过才会扣除阳光。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    ref.read(_submittingProvider.notifier).state = tpl.id;
    try {
      final SubmitResult result = await ref
          .read(redemptionOrchestrationServiceProvider)
          .submit(tpl.id, tier, DateTime.now(), forcePending: true);
      if (!mounted) return;
      await _handleResult(result);
    } finally {
      if (mounted) ref.read(_submittingProvider.notifier).state = null;
    }
  }

  /// 孩子撤销一笔排队中的兑换（A3）：二次确认 → reject（不扣账本）→ 自增修订号 → 刷新。
  Future<void> _onCancelQueue(RewardTemplate tpl, String? requestId) async {
    if (requestId == null || !mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('撤销排队？'),
        content: Text(
          '确定要撤销「${tpl.name}」的排队吗？\n'
          '撤销后该奖励将不再次月自动释放，可重新兑换。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('撤销排队'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(redemptionOrchestrationServiceProvider)
          .reject(requestId, DateTime.now(), note: '孩子撤销排队');
      if (!mounted) return;
      _toast('已撤销排队');
      // 经济已变更 → 递增修订号，令本页 provider 重算（排队提示消失、兑换恢复可用）。
      ref.read(economyRevisionProvider.notifier).state++;
    } catch (e) {
      if (!mounted) return;
      _toast('撤销失败：$e');
    }
  }

  /// 按 SubmitOutcome 给出反馈文案，并刷新商店数据。
  Future<void> _handleResult(SubmitResult result) async {
    final String message;
    switch (result.outcome) {
      case SubmitOutcome.verified:
        message = '兑换成功！阳光已扣除';
      case SubmitOutcome.pending:
        message = await _pendingFeedback(result.requestId);
      case SubmitOutcome.queued:
        final int rank = result.queueRank ?? 0;
        message = '排队中：第 $rank 位，下月1日释放';
      case SubmitOutcome.rejectedCooldown:
        message = '本周已领过啦';
      case SubmitOutcome.rejectedBalance:
        message = result.cost != null
            ? '阳光不够啦，再去专注赚一些吧（需要 ${result.cost} 阳光）'
            : '阳光不够啦，再去专注赚一些吧';
    }
    if (!mounted) return;
    if (result.outcome == SubmitOutcome.verified) {
      await _showCelebration(context);
    } else {
      _toast(message);
    }
    // 经济已变更 → 递增修订号，令本页 provider 重算（与家长端「核销/拒绝」共用同一机制）。
    ref.read(economyRevisionProvider.notifier).state++;
  }

  /// 待核销反馈：若 requestedAt 距今 > kPendingReminderHours 展示兜底文案。
  Future<String> _pendingFeedback(String? requestId) async {
    if (requestId == null) return '已提交，等家长确认哦～';
    final List<RedemptionRequest> list =
        await ref.read(rewardRepositoryProvider).pendingAndQueued();
    for (final RedemptionRequest r in list) {
      if (r.id == requestId) {
        if (DateTime.now().difference(r.requestedAt) >
            const Duration(hours: kPendingReminderHours)) {
          return kPendingReminderText;
        }
        break;
      }
    }
    return '已提交，等家长确认哦～';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 兑换成功（verified）时的庆祝动画：弹出透明 Dialog 强化正反馈，替代纯 toast。
  ///
  /// 返回 [showDialog] 的 Future 以便 [_handleResult] 中 await，确保动画展示期间
  /// 不提前 invalidate/关闭页面。
  Future<void> _showCelebration(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VerifiedCelebration(),
    );
  }
}

/// 庆祝弹窗装饰星星的位置与文案描述（供 [_VerifiedCelebration] 错峰淡入使用）。
class _StarSpec {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final String emoji;
  final double begin;

  const _StarSpec({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.emoji,
    required this.begin,
  });
}

/// 兑换成功庆祝动画弹窗。
///
/// 通过 [AnimationController] + elasticOut 弹性缩放 + easeOut 淡入，居中展示大号太阳 emoji
/// 与「兑换成功！阳光已扣除」圆角卡片，并在四周用若干小星星错峰淡入点缀；2 秒后自动关闭。
class _VerifiedCelebration extends StatefulWidget {
  const _VerifiedCelebration();

  @override
  State<_VerifiedCelebration> createState() => _VerifiedCelebrationState();
}

class _VerifiedCelebrationState extends State<_VerifiedCelebration>
    with SingleTickerProviderStateMixin {
  /// 装饰星星：围绕卡片四周错峰淡入。
  static const List<_StarSpec> _stars = <_StarSpec>[
    _StarSpec(top: -8, left: 12, emoji: '⭐', begin: 0.2),
    _StarSpec(top: 18, right: -4, emoji: '✨', begin: 0.45),
    _StarSpec(bottom: 56, left: -6, emoji: '🌟', begin: 0.3),
    _StarSpec(bottom: 20, right: 14, emoji: '⭐', begin: 0.6),
  ];

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    // 2 秒后自动关闭庆祝弹窗。
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: <Widget>[
              ..._stars.map(_buildStar),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('☀️', style: TextStyle(fontSize: 72)),
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Text(
                      '兑换成功！\n阳光已扣除',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单颗错峰淡入的装饰星星。
  Widget _buildStar(_StarSpec spec) {
    return Positioned(
      top: spec.top,
      bottom: spec.bottom,
      left: spec.left,
      right: spec.right,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (BuildContext _, Widget? __) {
          final double t = CurvedAnimation(
            parent: _ctrl,
            curve: Interval(spec.begin, 1.0, curve: Curves.easeOut),
          ).value;
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.6 + 0.4 * t,
              child: Text(spec.emoji, style: const TextStyle(fontSize: 28)),
            ),
          );
        },
      ),
    );
  }
}
