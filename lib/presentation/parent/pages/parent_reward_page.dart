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
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/repositories/reward_repository.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/parent/widgets/pool_indicator.dart';
import 'package:sunflower_time/presentation/parent/widgets/verification_card.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';
// F130：平板 UI 倍率（文字之外的定尺寸元素一律乘 `uiScaleOf(context)`）。
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/domain_text_l10n.dart';
import 'package:sunflower_time/core/i18n/enum_l10n.dart';
import 'package:sunflower_time/core/i18n/seed_l10n.dart';

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
    // i18n B2 🔴 弹窗纪律：文案在页级 scope 内取好，经参数槽位传入弹窗。
    final AppLocalizations l10n = l10nOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.parent_reward_delete_title),
        content: Text(l10n.parent_reward_delete_body(
            rewardDisplayName(t.id, t.name, l10n))),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.shared_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.shared_delete),
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
    // F130（2026-10-19 玄参 iPad Pro 13″ 实测截图）：平板 UI 放大倍率
    //（手机 1.0 / iPad 11″ 1.3 / iPad 13″ 1.6）。
    //
    // 为什么在 build 顶部取一次：`responsive.dart` 铁律——文字走 textScaler 自动
    // 放大，**文字之外的定尺寸元素（图标 / 方块 / 圆角 / 间距）必须自己乘
    // `uiScaleOf`**。此前本页价格胶囊里的阳光图标写死 16pt，1.6 倍下数字放大到
    // 22.4pt 而图标仍是 16pt → 真机截图「图标明显偏小」。
    final double s = uiScaleOf(context);
    // 阶段 4 门控：新增奖励受 `rewardTemplateCount` 配额约束（免费 5 条）。
    // 🔴 C69：只拦「新增」，编辑 / 删除照常（存量超额可编辑 / 可删、不能新增）。
    final EntitlementTier tier = ref.watch(entitlementProvider).tier;
    final bool canAdd = PremiumQuotaGate.allows(
      tier,
      FeatureKey.rewardTemplateCount,
      _templates.length,
    );
    // 🔴 页级 L10nScope（i18n B2）：全页文案经 AppLocalizations 解析。
    return L10nScope(
      child: Builder(builder: (BuildContext context) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        const WeeklyPoolCard(),
        // C91（玄参平板真机反馈）：原「每周阳光池：本周孩子可「免确认自动放行」的
        // 阳光上限……」说明小字**整行删除** —— 自动放行功能已随 C90-C 废除，
        // 该文案对家长只剩误导；周池语义以 WeeklyPoolCard 卡内说明为准。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // i18n B2：英文标题比中文长（`Reward templates` vs `奖励模板`）→
                  // 标题吃 `Expanded` 换行，按钮保持自然宽度，避免窄屏溢出。
                  Expanded(
                    child: Text(
                      l10n.parent_reward_templates_title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => PremiumQuotaGate.onTap(
                      context: context,
                      feature: FeatureKey.rewardTemplateCount,
                      currentCount: _templates.length,
                      onAllowed: _addTemplate,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    // 达上限 → 置灰（视觉）；仍可点 → 走分因提示（C62）。
                    style: canAdd
                        ? null
                        : OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey,
                          ),
                    label: Text(l10n.parent_reward_btn_add),
                  ),
                ],
              ),
              if (!canAdd)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.parent_reward_quota_hint(PremiumQuotaGate.inlineReason(
                      tier,
                      FeatureKey.rewardTemplateCount,
                      _templates.length,
                      l10n: l10n,
                    )),
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l10n.parent_reward_edit_hint,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_templates.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text(l10n.parent_reward_empty)),
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
              final String? freqLabel = weeklyRedeemLabelL10n(
                  t.frequencyLimitPerWeek, _weeklyUsed[t.id] ?? 0, l10n);
              return Container(
                decoration: creamCardDecoration(),
                // F130：卡片内边距 / 图标块 / 间距一律乘 `s` —— 1.6 倍下文字已放大，
                // 图标块若仍 56pt 就成了「字大图标小」；手机 s=1.0 逐位不变（零回归）。
                padding: EdgeInsets.all(14 * s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // C48（玄参 2026-10-10）：图标与孩子端商店同款 UI 素材
                    // （按奖励名关键词映射，见 growth_icons），失败回退马卡龙色块 + emoji。
                    Container(
                      width: 56 * s,
                      height: 56 * s,
                      decoration: BoxDecoration(
                        color: macaronColorById(t.id).bg,
                        borderRadius: BorderRadius.circular(14 * s),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14 * s),
                        child: Image.asset(
                          rewardIconAssetFor(t),
                          fit: BoxFit.cover,
                          // F130：emoji 回退只跟随 textScaler（字号不动），不乘 s。
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(t.contentCategory.icon,
                                style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12 * s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            rewardDisplayName(t.id, t.name, l10n),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 6 * s),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: <Widget>[
                              pillLabel(
                                text: rewardContentCategoryLabel(t.contentCategory, l10n),
                                bg: macaronColorById(t.id).bg,
                                fg: macaronColorById(t.id).fg,
                              ),
                              pillLabel(
                                text: categoryLabel(t.category, l10n),
                                bg: Colors.grey.shade100,
                                fg: Colors.grey.shade700,
                              ),
                              if (freqLabel != null)
                                pillLabel(
                                  text: freqLabel,
                                  bg: Colors.blue.shade50,
                                  fg: Colors.blue.shade700,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        // F130（玄参 iPad 13″ 实测截图）：价格胶囊里的阳光图标
                        // **明显偏小** —— 数字经 textScaler 放大到 22.4pt，图标却仍
                        // 写死 16pt。此处把「内边距 / 圆角 / 间距 / 图标」全部乘 `s`，
                        // 与文字同源等比（手机 s=1.0 逐位不变）。
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12 * s, vertical: 6 * s),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1C2),
                            borderRadius: BorderRadius.circular(20 * s),
                          ),
                          // C48：「N 阳光」→ 数字 + 阳光 UI 图标（与孩子端同款）。
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // 字号不动（走 textScaler，大字号是无障碍需求）。
                              Text(
                                '${t.baseCost}',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8D6E00),
                                ),
                              ),
                              SizedBox(width: 4 * s),
                              Image.asset(
                                'assets/rewards/sunlight.png',
                                width: 16 * s,
                                height: 16 * s,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.wb_sunny,
                                    color: const Color(0xFFE8A600),
                                    size: 16 * s),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8 * s),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Colors.blueGrey),
                              tooltip: l10n.shared_edit,
                              onPressed: () => _editTemplate(t),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: l10n.shared_delete,
                              onPressed: () => _deleteTemplate(t),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
        );
      }),
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
  late RewardContentCategory _contentCategory; // 奖励内容分类（零食/游玩/娱乐/其他）
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
    _contentCategory = t?.contentCategory ?? RewardContentCategory.other;
    _baseCost = t?.baseCost ?? 20;
    _freq = t?.frequencyLimitPerWeek ?? 1;
    _cooldown = t?.cooldownRule ?? CooldownRule.weekly;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// 内容分类下拉项（C52 / 玄参 2026-10-10）：换「UI 图标 + 文字」渲染，
  /// 并纳入新增「玩具 / 阅读」分类；图标加载失败回退 emoji（美术永不阻塞）。
  DropdownMenuItem<RewardContentCategory> _contentCategoryDropdownItem(
      RewardContentCategory c, AppLocalizations l10n) {
    return DropdownMenuItem<RewardContentCategory>(
      value: c,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              rewardCategoryIconAsset(c),
              width: 22,
              height: 22,
              errorBuilder: (_, Object __, StackTrace? ___) =>
                  Text(c.icon, style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          Text(rewardContentCategoryLabel(c, l10n)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗 builder 在页级 scope 之外 → 本弹窗**内部自带** [L10nScope]
    // （B1 先例：PlantConfirmDialog / TaskEditorDialog），文案经内部上下文取。
    return L10nScope(
      child: Builder(builder: (BuildContext context) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        return AlertDialog(
      title: Text(widget.initial == null
          ? l10n.parent_reward_edit_title_new
          : l10n.parent_reward_edit_title_edit),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_name_label,
                ),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? l10n.parent_reward_err_required
                    : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RewardCategory>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_category_label,
                ),
                items: <DropdownMenuItem<RewardCategory>>[
                  DropdownMenuItem(
                    value: RewardCategory.parentHandled,
                    child: Text(l10n.parent_verify_cat_parent_handled),
                  ),
                  DropdownMenuItem(
                    value: RewardCategory.selfService,
                    child: Text(l10n.parent_reward_cat_self_full),
                  ),
                ],
                onChanged: (RewardCategory? v) =>
                    setState(() => _category = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RewardContentCategory>(
                initialValue: _contentCategory,
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_content_label,
                ),
                items: RewardContentCategory.values
                    .map((RewardContentCategory c) =>
                        _contentCategoryDropdownItem(c, l10n))
                    .toList(),
                onChanged: (RewardContentCategory? v) =>
                    setState(() => _contentCategory = v!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _baseCost.toString(),
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_cost_label,
                ),
                keyboardType: TextInputType.number,
                validator: (String? v) {
                  final int? n = int.tryParse(v ?? '');
                  return (n == null || n <= 0)
                      ? l10n.parent_reward_err_positive
                      : null;
                },
                onSaved: (String? v) => _baseCost = int.parse(v!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _freq.toString(),
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_freq_label,
                ),
                keyboardType: TextInputType.number,
                validator: (String? v) {
                  final int? n = int.tryParse(v ?? '');
                  return (n == null || n < 0)
                      ? l10n.parent_reward_err_nonneg
                      : null;
                },
                onSaved: (String? v) => _freq = int.parse(v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<CooldownRule>(
                initialValue: _cooldown,
                decoration: InputDecoration(
                  labelText: l10n.parent_reward_cooldown_label,
                ),
                items: <DropdownMenuItem<CooldownRule>>[
                  DropdownMenuItem(
                    value: CooldownRule.none,
                    child: Text(l10n.parent_reward_cooldown_none),
                  ),
                  DropdownMenuItem(
                    value: CooldownRule.weekly,
                    child: Text(l10n.parent_reward_cooldown_weekly),
                  ),
                  DropdownMenuItem(
                    value: CooldownRule.monthly,
                    child: Text(l10n.parent_reward_cooldown_monthly),
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
          child: Text(l10n.shared_cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _formKey.currentState!.save();
              final RewardTemplate tpl = RewardTemplate(
                id: widget.initial?.id ?? const Uuid().v4(),
                name: _nameCtrl.text.trim(),
                category: _category,
                contentCategory: _contentCategory,
                baseCost: _baseCost,
                frequencyLimitPerWeek: _freq,
                cooldownRule: _cooldown,
              );
              Navigator.of(context).pop(tpl);
            }
          },
          child: Text(l10n.parent_task_edit_btn_save),
        ),
      ],
        );
      }),
    );
  }
}
