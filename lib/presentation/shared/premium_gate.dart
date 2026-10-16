/// 付费门控组件（付费墙 · 阶段 1）——**门控单点收口**的 UI 侧入口。
///
/// 两种用法：
///  · 包内容：[`PremiumGate`]（`ConsumerWidget`）包裹需要门控的子树。**未开通时
///    显示付费引导卡片（而不是静默隐藏）**——静默隐藏会让用户莫名其妙、投诉「功能没了」。
///  · 回调型：[`PremiumGate.onTap`] 在**入口处一次判断**——允许则直接跑原回调，
///    不允许则弹付费引导。业务代码零改动（无需把逻辑拆进 Widget 树）。
///
/// 阶段 4 追加：**计数型**门控 [`PremiumQuotaGate`]（吃「当前数量」，委托
/// `quotaAllowsAdd`）——家长端「新增」入口达上限时给 1s 轻提示 + 「解锁全部功能」。
/// 对齐 C62：**「不可点」≠ `onTap: null`**（不静默失败）。
///
/// ⚠️ **阶段 4 已落地**：门控矩阵（`kEntitlementMatrix`）现已收紧 5 项 ——
/// `oneClickCare` / `deepReport` 在 free 档**关闭**；`gardenPotCapacity` free=4 /
/// `taskTemplateCount` free=5 / `rewardTemplateCount` free=5（premium 更宽）。
/// 其余能力（`parentReport` + 4 个未实现键）**仍免费放开**。
/// 故本组件对「已收紧」能力在 free 档**真正拦截**、premium 档放行；对「未收紧」能力
/// 一如既往**原样放行 [child]**（不显示付费引导）。
library premium_gate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';

/// 能力点的展示名（付费引导文案用）。
String _featureLabel(FeatureKey f) {
  switch (f) {
    case FeatureKey.oneClickCare:
      return '花园一键操作';
    case FeatureKey.gardenPotCapacity:
      return '更多花盆';
    case FeatureKey.parentReport:
      return '家长专注报告';
    case FeatureKey.taskTemplateCount:
      return '更多成长项模板';
    case FeatureKey.rewardTemplateCount:
      return '更多奖励模板';
    case FeatureKey.multiChildProfile:
      return '多孩子档案';
    case FeatureKey.deepReport:
      return '深度专注报告';
    case FeatureKey.exportShare:
      return '数据导出与分享';
    case FeatureKey.memoirExport:
      return '纪念册导出';
    case FeatureKey.familySharing:
      return '家庭共享';
    case FeatureKey.titlePerks:
      return '称号专属属性';
  }
}

/// 内容型门控：未开通时**显示付费引导**，已开通时原样放行 [child]。
class PremiumGate extends ConsumerWidget {
  const PremiumGate({
    required this.feature,
    required this.child,
    super.key,
  });

  /// 被门控的能力点（其 free / premium 行为由门控矩阵声明）。
  final FeatureKey feature;

  /// 允许时展示的内容。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Entitlement entitlement = ref.watch(entitlementProvider);
    if (_allows(entitlement, feature)) {
      return child;
    }
    return PremiumUpsellCard(feature: feature);
  }

  /// 回调型门控：**在入口处一次判断**。
  ///
  /// 允许 → 直接执行 [onAllowed]；不允许 → 弹出付费引导（不执行 [onAllowed]）。
  /// 业务代码无需改动（把原 `onTap: () {...}` 换成
  /// `onTap: () => PremiumGate.onTap(context, feature, () {...})` 即可）。
  static void onTap(
    BuildContext context,
    FeatureKey feature,
    VoidCallback onAllowed,
  ) {
    final ProviderContainer container =
        ProviderScope.containerOf(context, listen: false);
    final Entitlement entitlement = container.read(entitlementProvider);
    if (_allows(entitlement, feature)) {
      onAllowed();
      return;
    }
    showPremiumUpsell(context, feature);
  }

  /// 判定是否放行：委托门控矩阵（**唯一判定入口**，杜绝判定孪生）。
  static bool _allows(Entitlement entitlement, FeatureKey feature) =>
      featureAllowedFor(feature, entitlement.tier);
}

/// 配额型门控（付费墙 · 阶段 4）——**计数能力**的单点入口（吃「当前数量」）。
///
/// 与 [`PremiumGate`] 的关系：`PremiumGate` 管**布尔**能力（`featureAllowedFor`）；
/// `PremiumQuotaGate` 管**计数**能力（`quotaAllowsAdd`）——二者共用门控矩阵单点。
///
/// 纪律（C62）：**「不可点」≠ `onTap: null`** —— 达上限时**不**置空回调，而是落到
/// 分因提示；调用方据 [allows] 自行把按钮**置灰**（视觉），点击时经 [onTap] 给
/// **1s 轻提示 + 「解锁全部功能」**（不静默失败）。
///
/// 🔴 红线 C69：判定**只读**计数，**绝不**删除 / 裁剪任何已存数据。
class PremiumQuotaGate {
  const PremiumQuotaGate._();

  /// 该档位 + 当前数量下，「新增」是否放行（委托矩阵单点）。
  static bool allows(
    EntitlementTier tier,
    FeatureKey feature,
    int currentCount,
  ) =>
      quotaAllowsAdd(feature, tier, currentCount);

  /// 「新增」入口回调：放行 → 跑 [onAllowed]；达上限 → 1s 轻提示（家长端带
  /// 「解锁全部功能」→ `/parent/premium`，孩子端 [allowUpsell] = false 时不出购买入口）。
  static void onTap({
    required BuildContext context,
    required FeatureKey feature,
    required int currentCount,
    required VoidCallback onAllowed,
    bool allowUpsell = true,
  }) {
    final ProviderContainer container =
        ProviderScope.containerOf(context, listen: false);
    final Entitlement entitlement = container.read(entitlementProvider);
    if (quotaAllowsAdd(feature, entitlement.tier, currentCount)) {
      onAllowed();
      return;
    }
    final int quota = featureQuotaFor(feature, entitlement.tier);
    final String limit = quota == kUnlimitedQuota ? '不限' : '$quota';
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('免费版最多 $limit（当前 $currentCount），删除多余内容后即可新增'),
        duration: const Duration(milliseconds: 1000),
        action: allowUpsell
            ? SnackBarAction(
                label: '解锁全部功能',
                onPressed: () => context.push('/parent/premium'),
              )
            : null,
      ),
    );
  }

  /// 内联原因文案（父端按钮旁展示；对齐 C62「置灰 + 内联一行原因」）。
  static String inlineReason(
    EntitlementTier tier,
    FeatureKey feature,
    int currentCount,
  ) {
    final int quota = featureQuotaFor(feature, tier);
    final String limit = quota == kUnlimitedQuota ? '不限' : '$quota';
    return '免费上限 $limit（当前 $currentCount）';
  }
}

/// 付费引导卡片（未开通时由 [`PremiumGate`] 展示）。
///
/// 暖色儿童风：白底大圆角 + 主色按钮（配色与 [`cream_card`] 同调）。
class PremiumUpsellCard extends StatelessWidget {
  const PremiumUpsellCard({required this.feature, super.key});

  /// 触发引导的能力点（用于文案）。
  final FeatureKey feature;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('🌻', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                '解锁「${_featureLabel(feature)}」',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B6252),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '一次买断，永久解锁全部功能',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF9C917E)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => showPremiumUpsell(context, feature),
                child: const Text('查看详情'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出付费引导对话框（家长端可跳 `/parent/premium` 购买页）。
Future<void> showPremiumUpsell(BuildContext context, FeatureKey feature) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('升级解锁'),
      content: Text('「${_featureLabel(feature)}」需要一次性买断解锁。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.push('/parent/premium');
          },
          child: const Text('解锁全部功能'),
        ),
      ],
    ),
  );
}

// ───────────────────────────────────────────────────────────────────────────
// 购买页对比表 · 数据层（付费墙 · 阶段 5 · 购买页改版 v1 §3.2 / §4.1）
//
// 为什么 presenter 放这里：本文件**已在** `entitlement_gate_guard_test` 的权益标识符
// 白名单内 —— 派生逻辑（读矩阵）留在此处，UI 组件（`PremiumUnlockTable`）就能保持
// **守卫干净**（不含任何权益标识符），无需改白名单。
// ───────────────────────────────────────────────────────────────────────────

/// 对比表「买断后解锁」一行（纯数据，供 UI 渲染）。
///
/// 取值全部来自**单点矩阵**（[kEntitlementMatrix]）经 [featureAllowedFor] /
/// [featureQuotaFor] 派生，故改矩阵即改对比表，杜绝「宣传数字与实现漂移」。
class PremiumUnlockRow {
  /// 项目名（对比表左列）。
  final String label;

  /// 免费档显示串（如 `'4 个'` / `'5 条'` / `'✗'`）。
  final String freeText;

  /// 买断档显示串（如 `'最多 12'` / `'✓ 不限'`）。
  final String premiumText;

  /// 免费档是否为「可用 / 正向」（驱动 ✓ / ✗ 与配色）。
  final bool freeOk;

  /// 买断档是否为「可用 / 正向」（恒 true）。
  final bool premiumOk;

  /// 溯源用（便于守卫断言「恰好这 4 个键」）。
  final FeatureKey key;

  /// 可选补充注（小字，渲染在该行下方）；仅花盆行用（C70：扩容仍需花阳光）。
  final String? note;

  const PremiumUnlockRow({
    required this.label,
    required this.freeText,
    required this.premiumText,
    required this.freeOk,
    required this.premiumOk,
    required this.key,
    this.note,
  });
}

/// B 组 5 行（**显式白名单，禁止遍历能力枚举的 `values`**）。
///
/// 🔴 为什么必须显式枚举：能力枚举里除这 5 个真实生效键外，还有 `deepReport` +
/// 4 个**未实现**键。一旦遍历 `values`，未实现能力会被写进对外卖点 → 描述不符
/// （Apple 3.1.1 / 2.3.1 拒审）。故此处**逐行写死键名**，并由源码守卫兜底
/// （见 `test/qa/premium_unlock_table_test.dart` 的变异测试）。
/// C80：`titlePerks`（称号专属属性）为真实生效的第 5 键（free ✗ / premium ✓ 9 条）。
///
/// 数值来源：
///  · 布尔：`featureAllowedFor(oneClickCare, tier)`；
///  · 配额：`featureQuotaFor(gardenPotCapacity|taskTemplateCount|rewardTemplateCount, tier)`
///    （[kUnlimitedQuota] → `'不限'`）。
///
/// [matrix] 仅供测试注入自定义矩阵（生产恒用 [kEntitlementMatrix]）。
List<PremiumUnlockRow> unlockRowsFor({
  Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
}) {
  final int freePot =
      featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.free, matrix: matrix);
  final int premiumPot =
      featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.premium, matrix: matrix);
  final int freeTask =
      featureQuotaFor(FeatureKey.taskTemplateCount, EntitlementTier.free, matrix: matrix);
  final int premiumTask =
      featureQuotaFor(FeatureKey.taskTemplateCount, EntitlementTier.premium, matrix: matrix);
  final int freeReward =
      featureQuotaFor(FeatureKey.rewardTemplateCount, EntitlementTier.free, matrix: matrix);
  final int premiumReward =
      featureQuotaFor(FeatureKey.rewardTemplateCount, EntitlementTier.premium, matrix: matrix);
  final bool freeOneClick =
      featureAllowedFor(FeatureKey.oneClickCare, EntitlementTier.free, matrix: matrix);
  final bool premiumOneClick =
      featureAllowedFor(FeatureKey.oneClickCare, EntitlementTier.premium, matrix: matrix);

  return <PremiumUnlockRow>[
    PremiumUnlockRow(
      key: FeatureKey.oneClickCare,
      label: '花园「一键操作」',
      freeText: freeOneClick ? '✓' : '✗',
      freeOk: freeOneClick,
      premiumText: premiumOneClick ? '✓ 不限' : '✗',
      premiumOk: premiumOneClick,
    ),
    PremiumUnlockRow(
      key: FeatureKey.gardenPotCapacity,
      label: '花盆上限',
      freeText: _quotaText(freePot, unit: '个'),
      freeOk: true,
      premiumText: premiumPot == kUnlimitedQuota ? '✓ 不限' : '最多 $premiumPot',
      premiumOk: true,
      // C70：买断只解锁「扩容资格」，扩容仍需花阳光 —— 必须如实标注。
      note: '扩容仍需花阳光',
    ),
    PremiumUnlockRow(
      key: FeatureKey.taskTemplateCount,
      label: '成长项模板',
      freeText: _quotaText(freeTask, unit: '条'),
      freeOk: true,
      premiumText: premiumTask == kUnlimitedQuota ? '✓ 不限' : '最多 $premiumTask',
      premiumOk: true,
    ),
    PremiumUnlockRow(
      key: FeatureKey.rewardTemplateCount,
      label: '奖励模板',
      freeText: _quotaText(freeReward, unit: '条'),
      freeOk: true,
      premiumText: premiumReward == kUnlimitedQuota ? '✓ 不限' : '最多 $premiumReward',
      premiumOk: true,
    ),
    // C80 第 5 行：称号专属属性。freeOk 派生自矩阵（与其余布尔行同款），
    // premiumText 由 [kFocusLevelTitleLevels.length] 派生（9 派生，防漂移）。
    PremiumUnlockRow(
      key: FeatureKey.titlePerks,
      label: '称号属性',
      freeText: featureAllowedFor(
              FeatureKey.titlePerks, EntitlementTier.free,
              matrix: matrix)
          ? '✓'
          : '✗',
      freeOk: featureAllowedFor(
          FeatureKey.titlePerks, EntitlementTier.free, matrix: matrix),
      premiumText: '✓ ${kFocusLevelTitleLevels.length} 条',
      premiumOk: featureAllowedFor(
          FeatureKey.titlePerks, EntitlementTier.premium, matrix: matrix),
    ),
  ];
}

/// 配额展示串：`kUnlimitedQuota` → `'不限'`，否则 `'$quota $unit'`（如 `'4 个'`）。
String _quotaText(int quota, {required String unit}) =>
    quota == kUnlimitedQuota ? '不限' : '$quota $unit';
