/// 家长端「奖励」页（§5 T-F）：每周阳光池用量指示（含预算设定）+ 可编辑奖励模板列表。
///
/// M2 经济：家长可新增/编辑/删除奖励模板；改动后自增 [economyRevisionProvider]，
/// 使孩子端阳光商店实时刷新（§3.2 家长-孩子同步）。核销集中在「今日」tab。
///
/// 整页可滚动：根节点为 [ListView]，避免键盘弹出时 [Column] 固定高度子项溢出
/// （真机「BOTTOM OVERFLOWED BY 47 PIXELS」）。模板列表用 shrinkWrap 内嵌。
library parent_reward_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/presentation/parent/widgets/pool_indicator.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';

/// 「奖励」页：每周阳光池指示（含预算设定）+ 可编辑模板列表。
class ParentRewardPage extends ConsumerStatefulWidget {
  const ParentRewardPage({super.key});

  @override
  ConsumerState<ParentRewardPage> createState() => _ParentRewardPageState();
}

class _ParentRewardPageState extends ConsumerState<ParentRewardPage> {
  List<RewardTemplate> _templates = <RewardTemplate>[];
  Map<String, int> _weeklyUsed = <String, int>{}; // templateId -> 本周已领次数（cooldownCount），供算剩余
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 监听经济修订号：孩子端兑换 / 家长核销 / 拒绝都会自增 → 本页重算「剩余次数」。
    // 注意：initState 中必须用 listenManual（ref.listen 只允许在 build 内调用，
    // 否则真机会抛 "ref.listen can only be used within the build method" 断言崩溃）。
    ref.listenManual(economyRevisionProvider, (_, __) {
      if (mounted) _load();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final RewardRepository repo = ref.read(rewardRepositoryProvider);
    final List<RewardTemplate> list = await repo.templates();
    // 逐模板取本周已领次数（cooldownCount），与卡片「剩余次数」口径一致。
    final Map<String, int> used = <String, int>{};
    for (final RewardTemplate t in list) {
      used[t.id] = await repo.cooldownCount(t.id, CooldownPeriod.weekly);
    }
    if (mounted) {
      setState(() {
        _templates = list;
        _weeklyUsed = used;
        _loading = false;
      });
    }
  }

  /// 改动后刷新孩子端商店：自增经济修订号（§3.2 家长-孩子同步）。
  void _bumpEconomy() => ref.read(economyRevisionProvider.notifier).state++;

  Future<void> _addTemplate() async {
    final RewardTemplate? tpl = await showDialog<RewardTemplate>(
      context: context,
      builder: (_) => const _RewardEditorDialog(),
    );
    if (tpl == null) return;
    await ref.read(rewardRepositoryProvider).saveTemplate(tpl);
    _bumpEconomy();
    await _load();
  }

  Future<void> _editTemplate(RewardTemplate t) async {
    final RewardTemplate? tpl = await showDialog<RewardTemplate>(
      context: context,
      builder: (_) => _RewardEditorDialog(initial: t),
    );
    if (tpl == null) return;
    await ref.read(rewardRepositoryProvider).saveTemplate(tpl);
    _bumpEconomy();
    await _load();
  }

  Future<void> _deleteTemplate(RewardTemplate t) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除奖励'),
        content: Text('确定删除「${t.name}」？孩子端阳光商店将不再展示该奖励。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(rewardRepositoryProvider).deleteTemplate(t.id);
    _bumpEconomy();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        const WeeklyPoolCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '每周阳光池：本周孩子可「免确认自动放行」的阳光上限（进度条）。'
            '超出该上限的兑换需你在「今日」Tab 手动核销。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: <Widget>[
              const Text(
                '奖励模板',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addTemplate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增奖励'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '点按某条可编辑名称/价格/分类；右侧垃圾桶可删除。改动会同步到孩子端阳光商店。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_templates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('暂无奖励模板，点「新增奖励」创建')),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: _templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int i) {
              final RewardTemplate t = _templates[i];
              // 家长端展示「剩余可兑换次数」= 配置限领 − 本周已领（cooldownCount），
              // 核销 1 次即从 N 变为 N-1，与孩子端口径一致，避免时间长忘了设了几条。
              final String? freqLabel =
                  weeklyRedeemLabel(t.frequencyLimitPerWeek, _weeklyUsed[t.id] ?? 0);
              return ListTile(
                leading: const Icon(Icons.card_giftcard),
                title: Text(t.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(categoryLabel(t.category)),
                    if (freqLabel != null)
                      Text(
                        freqLabel,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.blueGrey.shade600),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${t.baseCost} 阳光',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: '删除',
                      onPressed: () => _deleteTemplate(t),
                    ),
                  ],
                ),
                onTap: () => _editTemplate(t),
              );
            },
          ),
      ],
    );
  }
}

/// 奖励模板编辑弹窗（新增/编辑共用）。
///
/// [initial] 为 null 表示新增（id 由 `Uuid` 生成）；非 null 表示编辑（沿用原 id）。
class _RewardEditorDialog extends StatefulWidget {
  final RewardTemplate? initial;

  const _RewardEditorDialog({this.initial});

  @override
  State<_RewardEditorDialog> createState() => _RewardEditorDialogState();
}

class _RewardEditorDialogState extends State<_RewardEditorDialog> {
  late final TextEditingController _nameCtrl;
  late RewardCategory _category;
  late int _baseCost;
  late int _freq;
  late CooldownRule _cooldown;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final RewardTemplate? t = widget.initial;
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _category = t?.category ?? RewardCategory.parentHandled;
    _baseCost = t?.baseCost ?? 20;
    _freq = t?.frequencyLimitPerWeek ?? 1;
    _cooldown = t?.cooldownRule ?? CooldownRule.weekly;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增奖励' : '编辑奖励'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '奖励名称'),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RewardCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: '分类'),
                items: const <DropdownMenuItem<RewardCategory>>[
                  DropdownMenuItem(
                    value: RewardCategory.parentHandled,
                    child: Text('家长经手'),
                  ),
                  DropdownMenuItem(
                    value: RewardCategory.selfService,
                    child: Text('自服务（看电视/玩平板）'),
                  ),
                ],
                onChanged: (RewardCategory? v) =>
                    setState(() => _category = v!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _baseCost.toString(),
                decoration: const InputDecoration(labelText: '阳光价格'),
                keyboardType: TextInputType.number,
                validator: (String? v) {
                  final int? n = int.tryParse(v ?? '');
                  return (n == null || n <= 0) ? '请输入正整数' : null;
                },
                onSaved: (String? v) => _baseCost = int.parse(v!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _freq.toString(),
                decoration: const InputDecoration(labelText: '每周限领次数'),
                keyboardType: TextInputType.number,
                validator: (String? v) {
                  final int? n = int.tryParse(v ?? '');
                  return (n == null || n < 0) ? '请输入非负整数' : null;
                },
                onSaved: (String? v) => _freq = int.parse(v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CooldownRule>(
                initialValue: _cooldown,
                decoration: const InputDecoration(labelText: '冷却规则'),
                items: const <DropdownMenuItem<CooldownRule>>[
                  DropdownMenuItem(value: CooldownRule.none, child: Text('无冷却')),
                  DropdownMenuItem(
                    value: CooldownRule.weekly,
                    child: Text('每周限领'),
                  ),
                  DropdownMenuItem(
                    value: CooldownRule.monthly,
                    child: Text('每月限领'),
                  ),
                ],
                onChanged: (CooldownRule? v) => setState(() => _cooldown = v!),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              final RewardTemplate tpl = RewardTemplate(
                id: widget.initial?.id ?? const Uuid().v4(),
                name: _nameCtrl.text.trim(),
                category: _category,
                baseCost: _baseCost,
                frequencyLimitPerWeek: _freq,
                cooldownRule: _cooldown,
              );
              Navigator.of(context).pop(tpl);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
