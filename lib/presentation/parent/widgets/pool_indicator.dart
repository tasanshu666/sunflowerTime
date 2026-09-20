/// 月度池用量指示（§5 T-F）：展示当月阳光池消耗进度与当前档免确认上限。
///
/// 数据来源：`MonthlyPoolService.pool(monthKey(DateTime.now()))` + 设置中的 ageTier；
/// 免确认上限经 `MonthlyPoolService.autoApproveCap(pool, tier)` 计算（§3.2 capFor）。
library pool_indicator;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/monthly_pool.dart';
import 'package:sunflower_time/domain/entities/settings.dart';

/// 年龄档中文标签（单点展示用）。
String tierLabel(AgeTier tier) {
  switch (tier) {
    case AgeTier.low:
      return '低年级';
    case AgeTier.mid:
      return '中年级';
    case AgeTier.high:
      return '高年级';
  }
}

/// 月度池用量指示卡。
class PoolIndicator extends ConsumerStatefulWidget {
  const PoolIndicator({super.key});

  @override
  ConsumerState<PoolIndicator> createState() => _PoolIndicatorState();
}

class _PoolIndicatorState extends ConsumerState<PoolIndicator> {
  late Future<_PoolData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PoolData> _load() async {
    final MonthlyPool pool = await ref
        .read(monthlyPoolServiceProvider)
        .pool(monthKey(DateTime.now()));
    final AppSettings settings =
        await ref.read(settingsRepositoryProvider).getSettings();
    final int cap = ref
        .read(monthlyPoolServiceProvider)
        .autoApproveCap(pool, settings.ageTier);
    return _PoolData(pool: pool, cap: cap, tier: settings.ageTier);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PoolData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_PoolData> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('月度池加载失败：${snap.error}'),
          );
        }

        final _PoolData data = snap.data!;
        final MonthlyPool pool = data.pool;
        final int usedTotal = pool.used + pool.autoReleased;
        final int budget = pool.budget;
        final double ratio =
            budget > 0 ? (usedTotal / budget).clamp(0.0, 1.0) : 0.0;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '月度阳光池（${pool.monthKey}）',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 8),
                Text(
                  '已用 $usedTotal / 池 $budget 阳光',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前档（${tierLabel(data.tier)}）免确认上限：${data.cap} 阳光',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 月度池指示所需数据（池 + 免确认上限 + 档位）。
class _PoolData {
  final MonthlyPool pool;
  final int cap;
  final AgeTier tier;

  const _PoolData({required this.pool, required this.cap, required this.tier});
}
