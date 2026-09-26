/// 周阳光池用量指示（§5 T-F）：展示当周阳光池消耗进度与当前档免确认上限，
/// 并允许家长直接在卡内设定每周预算。
///
/// 合并卡 [WeeklyPoolCard]：原「每周阳光池预算」Card 与 `PoolIndicator` 两张卡合二为一，
/// 自上而下为：标题（含 weekKey）→ 预算输入 + 保存 → 进度条 → 已用/池 → 当前档免确认上限。
///
/// 数据来源：`WeeklyPoolService.pool(weekKey(DateTime.now()))` + 设置中的 ageTier；
/// 免确认上限经 `WeeklyPoolService.autoApproveCap(pool, tier)` 计算（§3.2 capFor）。
/// 保存预算：写 settings.poolBudget + 当周池 budget，重载展示并自增 economyRevisionProvider。
library pool_indicator;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';

/// 周阳光池合并卡：预算输入 + 进度 + 免确认上限（§5 T-F）。
///
/// 家长可直接在卡内改周预算并保存；保存同步 [AppSettings.poolBudget] 与当周池 budget，
/// 重载展示后进度条与「已用/池」立即反映新预算，并自增 [economyRevisionProvider]
/// 令其它页面重算（§3.2 家长-孩子同步）。
///
/// 校验：预算须为整数且落在 50–1200（[WeeklyPool] 文档区间），越界提示且不保存。
class WeeklyPoolCard extends ConsumerStatefulWidget {
  const WeeklyPoolCard({super.key});

  @override
  ConsumerState<WeeklyPoolCard> createState() => _WeeklyPoolCardState();
}

class _WeeklyPoolCardState extends ConsumerState<WeeklyPoolCard> {
  late final TextEditingController _budgetCtrl;
  late Future<_PoolData> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _budgetCtrl = TextEditingController();
    _future = _load();
  }

  Future<_PoolData> _load() async {
    final WeeklyPool pool = await ref
        .read(weeklyPoolServiceProvider)
        .pool(weekKey(DateTime.now()));
    final AppSettings settings =
        await ref.read(settingsRepositoryProvider).getSettings();
    final int cap = ref
        .read(weeklyPoolServiceProvider)
        .autoApproveCap(pool, settings.ageTier);
    return _PoolData(pool: pool, cap: cap, tier: settings.ageTier);
  }

  Future<void> _saveBudget() async {
    final int? parsed = int.tryParse(_budgetCtrl.text.trim());
    // 校验：必须是整数且落在可调区间（玄参 2026-09-22 拍板收到 50–500）。
    // 区间来源 [kWeeklyPoolBudgetMin] / [kWeeklyPoolBudgetMax]（单点常量），
    // 不再在 UI 里写裸字面量——此前 50/1200 只存在于本文件，常量体系里没有出处。
    if (parsed == null ||
        parsed < kWeeklyPoolBudgetMin ||
        parsed > kWeeklyPoolBudgetMax) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '请输入 $kWeeklyPoolBudgetMin–$kWeeklyPoolBudgetMax 之间的整数预算值',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final AppSettings current =
          await ref.read(settingsRepositoryProvider).getSettings();
      // 1) 写设置（家长设定价 source of truth）。
      await ref
          .read(settingsRepositoryProvider)
          .saveSettings(current.copyWith(poolBudget: parsed));
      // 2) 同步改写当周池 budget（保留 used / autoReleased / resetAt）。
      await ref
          .read(weeklyPoolServiceProvider)
          .updateBudget(DateTime.now(), parsed);
      if (mounted) {
        // 3) 重载展示：进度条与「已用/池」立即反映新预算。
        setState(() => _future = _load());
        // 4) 自增经济修订号，令其它页面重算（§3.2 家长-孩子同步）。
        ref.read(economyRevisionProvider.notifier).state++;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存每周阳光池预算')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PoolData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_PoolData> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('周阳光池加载失败：${snap.error}'),
            ),
          );
        }

        final _PoolData data = snap.data!;
        final WeeklyPool pool = data.pool;
        final int usedTotal = pool.used + pool.autoReleased;
        final int budget = pool.budget;
        final double ratio =
            budget > 0 ? (usedTotal / budget).clamp(0.0, 1.0) : 0.0;

        // 预算输入框初值跟随当周池 budget；保存重载后亦随之刷新。
        if (_budgetCtrl.text != budget.toString()) {
          _budgetCtrl.text = budget.toString();
        }

        return Container(
          decoration: creamCardDecoration(),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '本周阳光预算',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              // 大号预算数字，一眼可见（家长最关心的「这周孩子能自己花多少」）。
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '$budget',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8D6E00),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('阳光',
                      style: TextStyle(fontSize: 18, color: Colors.brown)),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 12,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 6),
              Text(
                '已用 $usedTotal / 共 $budget 阳光',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                '孩子本周最多自己花 $budget 阳光；其中约 ${data.cap} 阳光能自动放行，'
                '超出的兑换会等你点一下确认。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _budgetCtrl,
                      decoration: const InputDecoration(
                        labelText: '调整预算（50–1200）',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _saveBudget,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 周阳光池指示所需数据（池 + 免确认上限 + 档位）。
class _PoolData {
  final WeeklyPool pool;
  final int cap;
  final AgeTier tier;

  const _PoolData({required this.pool, required this.cap, required this.tier});
}
