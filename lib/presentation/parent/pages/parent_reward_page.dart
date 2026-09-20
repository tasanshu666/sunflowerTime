/// 家长端「奖励」页（§5 T-F）：顶部月度池用量指示 + 只读奖励模板列表。
///
/// M2 不编辑模板（只读）；核销集中在「今日」tab，本页仅呈现模板与月度池状态。
library parent_reward_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/presentation/parent/widgets/pool_indicator.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';

/// 「奖励」页：月度池指示 + 只读模板列表。
class ParentRewardPage extends ConsumerStatefulWidget {
  const ParentRewardPage({super.key});

  @override
  ConsumerState<ParentRewardPage> createState() => _ParentRewardPageState();
}

class _ParentRewardPageState extends ConsumerState<ParentRewardPage> {
  late Future<List<RewardTemplate>> _templatesFuture;

  @override
  void initState() {
    super.initState();
    _templatesFuture = ref.read(rewardRepositoryProvider).templates();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PoolIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '月度阳光池：本月孩子可「免确认自动放行」的阳光上限（进度条）。'
            '超出该上限的兑换需你在「今日」Tab 手动核销。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '奖励模板（只读）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '当前奖励由系统预设，家长暂不可编辑（模板编辑/自定义上架功能后续开放）。'
            '孩子端「阳光商店」展示的就是这些奖励；孩子的每次兑换会进入「今日」Tab，由你核销确认。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<RewardTemplate>>(
            future: _templatesFuture,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<RewardTemplate>> snap,
            ) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('模板加载失败：${snap.error}'));
              }
              final List<RewardTemplate> templates = snap.data ?? <RewardTemplate>[];
              if (templates.isEmpty) {
                return const Center(child: Text('暂无奖励模板'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int i) {
                  final RewardTemplate t = templates[i];
                  return ListTile(
                    leading: const Icon(Icons.card_giftcard),
                    title: Text(t.name),
                    subtitle: Text(categoryLabel(t.category)),
                    trailing: Text(
                      '${t.baseCost} 阳光',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
