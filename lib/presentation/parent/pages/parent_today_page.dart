/// 家长端「今日」页（§4.3 / §5 T-F）：列出待家长核销/排队的兑换申请，逐条渲染为核销卡。
///
/// 数据来源：
///  · `RedemptionOrchestrationService.pendingList()` —— pending + queued，按 requestedAt 升序；
///  · `RewardRepository.templates()` —— 建立 templateId → RewardTemplate 映射用于展示。
///
/// 核销成功后由 [VerificationCard.onVerified] 触发本页重新拉取，使卡消失。
///
/// 注：刷新统一用**块体**闭包 `setState(() { _future = _load(); })`。
/// 若写成箭头体 `setState(() => _future = _load())`，闭包会把赋值结果（Future）
/// 作为返回值交给 setState，触发 debug 断言
/// 「setState() callback argument returned a Future」，且 markNeedsBuild 不会执行
/// → 界面不刷新、异常被上层 catch 成「核销失败」（真机 BUG 复现）。
library parent_today_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';

/// 「今日」页：待核销列表。
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

  /// 并发拉取待处理列表与模板，并构建映射。
  Future<_TodayData> _load() async {
    final List<RedemptionRequest> requests = await ref
        .read(redemptionOrchestrationServiceProvider)
        .pendingList();
    final List<RewardTemplate> templates =
        await ref.read(rewardRepositoryProvider).templates();
    final Map<String, RewardTemplate> templateMap =
        <String, RewardTemplate>{for (final RewardTemplate t in templates) t.id: t};
    return _TodayData(requests: requests, templates: templateMap);
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
        if (data.requests.isEmpty) {
          return const Center(
            child: Text('暂无待确认奖励 🎉', style: TextStyle(fontSize: 18)),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            _reload();
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int i) {
              final RedemptionRequest req = data.requests[i];
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
            },
          ),
        );
      },
    );
  }
}

/// 「今日」页加载结果（待处理申请 + 模板映射）。
class _TodayData {
  final List<RedemptionRequest> requests;
  final Map<String, RewardTemplate> templates;

  const _TodayData({required this.requests, required this.templates});
}
