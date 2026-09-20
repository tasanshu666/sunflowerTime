/// 孩子端首页（M0 占位，竖屏）。M1 将替换为「今日状态卡 + 底部导航」（§5）。
///
/// M2 追加：进入孩子端时检查「家长已核销」通知 —— 家长核销后孩子端需有弹窗提醒
/// （家长-孩子同步）。已读申请 id 记在 shared_preferences，避免重复弹窗。
library child_home_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/utils/datetime_ext.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';

class ChildHomePage extends ConsumerStatefulWidget {
  const ChildHomePage({super.key});

  @override
  ConsumerState<ChildHomePage> createState() => _ChildHomePageState();
}

class _ChildHomePageState extends ConsumerState<ChildHomePage> {
  @override
  void initState() {
    super.initState();
    // 首帧后再弹窗，避免在 build 期间触发路由/覆盖层变更。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVerifiedNotices());
  }

  /// 进入孩子端即检查「家长已核销」通知：有未读则弹窗告知，并标记已读。
  ///
  /// 判定口径：`verifiedRequests()` 中 id 不在 shared_preferences 已读列表里的申请。
  /// 任何异常都不阻塞首页（通知属增强能力）。
  Future<void> _checkVerifiedNotices() async {
    try {
      final RewardRepository repo = ref.read(rewardRepositoryProvider);
      final SettingsStore store = ref.read(settingsStoreProvider);

      final List<RedemptionRequest> verified = await repo.verifiedRequests();
      if (verified.isEmpty) return;

      final List<String> acked = await store.acknowledgedVerifyIds();
      final Set<String> ackedSet = acked.toSet();
      final List<RedemptionRequest> news =
          verified.where((RedemptionRequest r) => !ackedSet.contains(r.id)).toList();
      if (news.isEmpty) return;

      final List<RewardTemplate> tpls = await repo.templates();
      final Map<String, String> names = <String, String>{
        for (final RewardTemplate t in tpls) t.id: t.name,
      };
      if (!mounted) return;

      final int total =
          news.fold(0, (int s, RedemptionRequest r) => s + r.cost);
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('🎉 家长已确认你的兑换'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final RedemptionRequest r in news)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '· ${names[r.templateId] ?? '奖励'}  -${r.cost} 阳光',
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                '共扣除 $total 阳光',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道啦'),
            ),
          ],
        ),
      );

      // 标记已读（去重合并），下次进入不再重复弹窗。
      await store.setAcknowledgedVerifyIds(
        <String>{...acked, ...news.map((RedemptionRequest r) => r.id)}.toList(),
      );
    } catch (_) {
      // 通知检查失败不阻塞孩子端首页。
    }
  }

  /// DEBUG ONLY — 测试用临时入口，提交前删除。
  /// 追加一条 +1000 阳光账本（net 为正、balanceAfter 累加），便于真机验收兑换链路。
  Future<void> _grantDebugSunlight() async {
    final double balance = await ref.read(sunlightRepositoryProvider).balance();
    final DateTime now = DateTime.now();
    await ref.read(sunlightRepositoryProvider).append(SunlightEntry(
      id: const Uuid().v4(),
      ts: now,
      type: SunlightType.earn,
      gross: 1000,
      net: 1000,
      balanceAfter: balance + 1000,
      refType: 'debug_grant',
      refId: null,
      dayKey: dayKey(now),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DEBUG：已加 1000 阳光，去阳光商店看看'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('向日葵专注')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('孩子端首页', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            const Text('M0 骨架占位 · M1 接入今日状态卡与底部导航'),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => context.go('/entry'),
              child: const Text('开始专注'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/s1-demo'),
              child: const Text('四档反馈预览（S1）'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/parent'),
              child: const Text('家长天地 →'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push('/store'),
              child: const Text('阳光商店'),
            ),
            const SizedBox(height: 12),
            // DEBUG ONLY — 测试用，提交前删除
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              onPressed: _grantDebugSunlight,
              child: const Text('DEBUG 加1000阳光'),
            ),
          ],
        ),
      ),
    );
  }
}
