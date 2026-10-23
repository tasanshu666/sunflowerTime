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
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
// ⚠️ **跨层引用说明（F141 ⑥）**：`shared/` 引用 `child/widgets/` 属跨层。
// 允许的理由：付费引导弹窗是**家长端与孩子端共用**的二次确认卡，而「确认卡壳」
// 目前只在孩子端落地（`ChildConfirmCard`，F135）。为了不让同一 App 出现两套
// 弹窗样式，此处直接复用孩子端卡壳 —— Dart 层**无循环依赖**
// （`child_confirm_card.dart` 只依赖 `gold_notice_dialog.dart` 与
// `shared/responsive.dart`，不反向依赖本文件），且 `flutter analyze` 无告警。
// 后续若要在 `shared/` 长期使用，可把卡壳迁到 `shared/`（需同步改所有调用方）。
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show showChildConfirmCard;

/// 能力点的展示名（付费引导文案用，i18n B2 经 ARB 取）。
String _featureLabel(AppLocalizations t, FeatureKey f) {
  switch (f) {
    case FeatureKey.oneClickCare:
      return t.premium_gate_feature_one_click_care;
    case FeatureKey.gardenPotCapacity:
      return t.premium_gate_feature_pot_capacity;
    case FeatureKey.parentReport:
      return t.premium_gate_feature_parent_report;
    case FeatureKey.taskTemplateCount:
      return t.premium_gate_feature_task_templates;
    case FeatureKey.rewardTemplateCount:
      return t.premium_gate_feature_reward_templates;
    case FeatureKey.multiChildProfile:
      return t.premium_gate_feature_multi_child;
    case FeatureKey.deepReport:
      return t.premium_gate_feature_deep_report;
    case FeatureKey.exportShare:
      return t.premium_gate_feature_export_share;
    case FeatureKey.memoirExport:
      return t.premium_gate_feature_memoir_export;
    case FeatureKey.familySharing:
      return t.premium_gate_feature_family_sharing;
    case FeatureKey.titlePerks:
      return t.premium_gate_feature_title_perks;
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
    // i18n B2：文案在**调用方上下文**（页级 scope 内）取好再进 SnackBar/弹窗 ——
    // SnackBar 的 content 在 overlay 里重建，不得直调 `AppLocalizations.of`。
    final AppLocalizations t = l10nOf(context);
    final String limit =
        quota == kUnlimitedQuota ? t.shared_unlimited : '$quota';
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.premium_quota_snack(limit, currentCount)),
        duration: const Duration(milliseconds: 1000),
        action: allowUpsell
            ? SnackBarAction(
                label: t.premium_gate_unlock_all,
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
    int currentCount, {
    AppLocalizations? l10n,
  }) {
    final AppLocalizations t = l10n ?? AppLocalizationsZh();
    final int quota = featureQuotaFor(feature, tier);
    final String limit =
        quota == kUnlimitedQuota ? t.shared_unlimited : '$quota';
    return t.premium_quota_inline_reason(limit, currentCount);
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
    // i18n B2：文案经 [l10nOf]（页级 scope 内取；裸宿主回退 zh）。
    final AppLocalizations t = l10nOf(context);
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
                t.premium_gate_upsell_title(_featureLabel(t, feature)),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B6252),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.premium_gate_upsell_subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF9C917E)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => showPremiumUpsell(context, feature),
                child: Text(t.premium_gate_upsell_btn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹出付费引导对话框（家长端可跳 `/parent/premium` 购买页）。
///
/// F141 ⑥：改走孩子端**统一确认卡壳** `ChildConfirmCard`（文案逐字不变：
/// 「升级解锁」/「「X」需要一次性买断解锁。」/「稍后」/「解锁全部功能」）。
/// 返回语义不变：只有点「解锁全部功能」才 `push('/parent/premium')`。
///
/// i18n B2 🔴 **弹窗纪律**：卡壳 builder 在页级 scope 之外 → 文案在此处（调用方
/// 上下文）解析好，经**参数槽位**传入卡壳。
Future<void> showPremiumUpsell(BuildContext context, FeatureKey feature) async {
  final AppLocalizations t = l10nOf(context);
  final bool? ok = await showChildConfirmCard(
    context: context,
    title: t.premium_gate_upsell_dialog_title,
    message: t.premium_gate_upsell_dialog_message(_featureLabel(t, feature)),
    cancelLabel: t.premium_gate_later,
    confirmLabel: t.premium_gate_unlock_all,
  );
  if (ok != true) return;
  // 卡壳已 pop 后再跳：`await` 之后 context 可能已失效（页面被销毁），故先查 mounted。
  if (!context.mounted) return;
  context.push('/parent/premium');
}

// ───────────────────────────────────────────────────────────────────────────
// 购买页对比表 · 数据层（付费墙 · 阶段 5 · 购买页改版 v1 §3.2 / §4.1）
//
// 为什么 presenter 放这里：本文件**已在** `entitlement_gate_guard_test` 的权益标识符
// 白名单内 —— 派生逻辑（读矩阵）留在此处，UI 组件（`PremiumUnlockTable`）就能保持
// **守卫干净**（不含任何权益标识符），无需改白名单。
// ───────────────────────────────────────────────────────────────────────────

/// 对比表派生行（纯数据，供 UI 渲染；F146 后含模板合并行双键形态）。
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

  /// 主能力键（合并行挂「主键」，现网 = `taskTemplateCount`）。
  ///
  /// 溯源用（便于守卫断言键序白名单 / 未实现键检查）。
  final FeatureKey key;

  /// 次能力键（**仅合并行**使用；单键行恒 `null`）。
  ///
  /// 取舍：不改 `keys: List<FeatureKey>` —— 全仓仅 1 个双键场景（模板合并行），
  /// [secondaryKey] 让既有单键构造与取法零破坏；守卫断言一律经 [allKeys] 取全集。
  final FeatureKey? secondaryKey;

  /// 该行涉及的全部能力键（守卫断言统一入口；未实现键检查用）。
  List<FeatureKey> get allKeys =>
      <FeatureKey>[key, if (secondaryKey != null) secondaryKey!];

  /// 可选补充注（小字，渲染在该行下方）；仅花盆行用（C70：扩容仍需花阳光）。
  final String? note;

  const PremiumUnlockRow({
    required this.label,
    required this.freeText,
    required this.premiumText,
    required this.freeOk,
    required this.premiumOk,
    required this.key,
    this.secondaryKey,
    this.note,
  });
}

/// 对比表「买断解锁 · 更大容量」组的**固定切分点**：[unlockRowsFor] 的前
/// [kUnlockCapacityRowCount] 行（花盆 / 模板合并 / 档案）归容量组，其余
/// （一键 / 称号 / 报告）归进阶组。
///
/// 由组件消费切分（**禁止在组件里写魔法数 3**），行序守卫兜底
/// （`test/qa/premium_unlock_table_test.dart` T3 结构守卫）。
const int kUnlockCapacityRowCount = 3;

/// 买断档「称号专属属性」条数（= [kFocusLevelTitleLevels].length 的收口别名）。
///
/// 为什么收口在此：`focus_level_guard_test` ⑤ 禁止 `/presentation/parent/` 下任何
/// 文件出现 `FocusLevel` 子串（家长端不引用等级组件），而购买页场景卡需要展示
/// 「9 条称号属性」—— 故派生别名放本文件（shared 层），家长端只引本 getter。
// ignore: constant_identifier_names
int get kPremiumTitlePerkCount => kFocusLevelTitleLevels.length;

/// 对比表派生行（**6 行**，顺序 = 新表行 2–7；行 1「核心体验全免费」为纯描述
/// 静态行，留在组件侧 —— 无 FeatureKey 语义，不入派生层）。
///
/// 行序白名单：花盆 → 模板（合并）→ 档案 → 一键 → 称号 → 报告。
///
/// 🔴 为什么必须显式枚举：能力枚举里除这 6 个真实生效键外，还有 3 个**未实现**键
/// （`exportShare` / `memoirExport` / `familySharing`）。一旦遍历 `values`，未实现
/// 能力会被写进对外卖点 → 描述不符（Apple 3.1.1 / 2.3.1 拒审）。故此处**逐行写死
/// 键名**，并由源码守卫兜底（见 `test/qa/premium_unlock_table_test.dart`）。
///
/// 数值来源（数字派生纪律：**全链路不写死权益数字**）：
///  · 布尔：`featureAllowedFor(oneClickCare|deepReport, tier)`；
///  · 配额：`featureQuotaFor(gardenPotCapacity|taskTemplateCount|rewardTemplateCount|
///    multiChildProfile, tier)`（[kUnlimitedQuota] → `'不限'`）；
///  · 称号数：`kFocusLevelTitleLevels.length`（9 派生，防漂移）。
///
/// [matrix] 仅供测试注入自定义矩阵（生产恒用 [kEntitlementMatrix]）。
///
/// i18n B2：[l10n] 缺省回退中文（[AppLocalizationsZh]）—— 纯数据层（单测 / 守卫）
/// 不依赖 BuildContext 也能拿到与现网逐字节一致的中文展示串。
List<PremiumUnlockRow> unlockRowsFor({
  Map<FeatureKey, FeatureRule> matrix = kEntitlementMatrix,
  AppLocalizations? l10n,
}) {
  final AppLocalizations t = l10n ?? AppLocalizationsZh();
  return <PremiumUnlockRow>[
    _potsRow(t, matrix), // 行 2 gardenPotCapacity，note = pots_note（C70）
    _templatesRow(t, matrix), // 行 3 合并行 task+reward（见 _templatesRow 注释）
    _profilesRow(t, matrix), // 行 4 multiChildProfile（读档案配额常量）
    _oneClickRow(t, matrix), // 行 5 oneClickCare
    _perksRow(t, matrix), // 行 6 titlePerks（9 = kFocusLevelTitleLevels.length）
    _reportRow(t, matrix), // 行 7 deepReport（freeOk 恒 true：日/周免费真实可用）
  ];
}

// ── 行构造 helpers（unlockRowsFor 专用）──

/// 行 2「花盆上限」：配额行，note = pots_note（C70：扩容仍需花阳光）。
PremiumUnlockRow _potsRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  final int freePot = featureQuotaFor(
      FeatureKey.gardenPotCapacity, EntitlementTier.free, matrix: matrix);
  final int premiumPot = featureQuotaFor(
      FeatureKey.gardenPotCapacity, EntitlementTier.premium, matrix: matrix);
  return PremiumUnlockRow(
    key: FeatureKey.gardenPotCapacity,
    label: t.premium_table_row_pots,
    freeText: _quotaPots(t, freePot),
    freeOk: true,
    premiumText: _quotaOrUnlimited(t, premiumPot),
    premiumOk: true,
    // C70：买断只解锁「扩容资格」，扩容仍需花阳光 —— 必须如实标注。
    note: t.premium_table_pots_note,
  );
}

/// 行 3「成长项 / 奖励模板」**合并行**（`key` = taskTemplateCount 主键 +
/// `secondaryKey` = rewardTemplateCount 次键）。
///
/// free 列派生规则（F146 §3.4）：两键 freeQuota 相等（现网均 5）→「各 N 条」；
/// 不等 →「N 条 / M 条」回退（`premium_table_free_items_single` ×2）。
/// premium 列：均不限 →「✓ 不限」；否则逐侧格式化后以「 / 」连接
/// （回退分支现网不可达：`kFreeTaskQuota` == `kFreeRewardQuota`，用注入测试钉住）。
PremiumUnlockRow _templatesRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  final int freeTask = featureQuotaFor(
      FeatureKey.taskTemplateCount, EntitlementTier.free, matrix: matrix);
  final int freeReward = featureQuotaFor(
      FeatureKey.rewardTemplateCount, EntitlementTier.free, matrix: matrix);
  final int premTask = featureQuotaFor(
      FeatureKey.taskTemplateCount, EntitlementTier.premium, matrix: matrix);
  final int premReward = featureQuotaFor(
      FeatureKey.rewardTemplateCount, EntitlementTier.premium, matrix: matrix);
  final String freeText = freeTask == freeReward
      ? t.premium_table_free_items(freeTask)
      : '${t.premium_table_free_items_single(freeTask)} / '
          '${t.premium_table_free_items_single(freeReward)}';
  final String premiumText =
      (premTask == kUnlimitedQuota && premReward == kUnlimitedQuota)
          ? t.premium_table_unlimited
          : '${_quotaOrUnlimited(t, premTask)} / ${_quotaOrUnlimited(t, premReward)}';
  return PremiumUnlockRow(
    key: FeatureKey.taskTemplateCount,
    secondaryKey: FeatureKey.rewardTemplateCount,
    label: t.premium_table_row_templates,
    freeText: freeText,
    premiumText: premiumText,
    // 配额行：可用（只拦新增，C69，「只拦新增」语义不入对外文案）。
    freeOk: true,
    premiumOk: true,
  );
}

/// 行 4「孩子档案」：配额行，读 `kFreeChildProfileCount` / `kPremiumChildProfileCount`
///（经矩阵派生，不写死 1 / 3）。
PremiumUnlockRow _profilesRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  final int freeProfile = featureQuotaFor(
      FeatureKey.multiChildProfile, EntitlementTier.free, matrix: matrix);
  final int premiumProfile = featureQuotaFor(
      FeatureKey.multiChildProfile, EntitlementTier.premium, matrix: matrix);
  return PremiumUnlockRow(
    key: FeatureKey.multiChildProfile,
    label: t.premium_table_row_profiles,
    freeText: _quotaPots(t, freeProfile),
    freeOk: true,
    premiumText: _quotaOrUnlimited(t, premiumProfile),
    premiumOk: true,
  );
}

/// 行 5「花园一键操作」：布尔行（free 档由矩阵关闭 → ✗）。
PremiumUnlockRow _oneClickRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  final bool freeOneClick = featureAllowedFor(
      FeatureKey.oneClickCare, EntitlementTier.free, matrix: matrix);
  final bool premiumOneClick = featureAllowedFor(
      FeatureKey.oneClickCare, EntitlementTier.premium, matrix: matrix);
  return PremiumUnlockRow(
    key: FeatureKey.oneClickCare,
    label: t.premium_table_row_one_click,
    freeText: freeOneClick ? '✓' : '✗',
    freeOk: freeOneClick,
    premiumText: premiumOneClick ? t.premium_table_unlimited : '✗',
    premiumOk: premiumOneClick,
  );
}

/// 行 6「称号属性」：布尔行（C80）；premiumText 由 [kFocusLevelTitleLevels.length]
/// 派生（9 派生，防漂移）。
PremiumUnlockRow _perksRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  final bool freePerks = featureAllowedFor(
      FeatureKey.titlePerks, EntitlementTier.free, matrix: matrix);
  return PremiumUnlockRow(
    key: FeatureKey.titlePerks,
    label: t.premium_table_row_perks,
    freeText: freePerks ? '✓' : '✗',
    freeOk: freePerks,
    premiumText: t.premium_table_perks_count(kFocusLevelTitleLevels.length),
    premiumOk: featureAllowedFor(
        FeatureKey.titlePerks, EntitlementTier.premium, matrix: matrix),
  );
}

/// 行 7「家长专注报告」：deepReport 行。free 列「近 7 天」如实展示（C69 细化：
/// 日 / 周报告免费真实可用，freeOk 恒 true）；premium 列与报告页引导横条口径对齐
///（「解锁深度专注报告」→ 加月 / 年报告 · 热力图）。
PremiumUnlockRow _reportRow(
  AppLocalizations t,
  Map<FeatureKey, FeatureRule> matrix,
) {
  return PremiumUnlockRow(
    key: FeatureKey.deepReport,
    label: t.premium_table_row_report,
    freeText: t.premium_table_report_days,
    freeOk: true,
    premiumText: t.premium_table_report_premium,
    premiumOk: featureAllowedFor(
        FeatureKey.deepReport, EntitlementTier.premium, matrix: matrix),
  );
}

/// 配额展示串（花盆 / 档案类）：`kUnlimitedQuota` → 不限，否则 `'$quota 个'`。
String _quotaPots(AppLocalizations t, int quota) =>
    quota == kUnlimitedQuota
        ? t.shared_unlimited
        : t.premium_table_free_pots(quota);

/// 配额展示串（买断列通用）：`kUnlimitedQuota` → 「✓ 不限」，否则「最多 N」。
String _quotaOrUnlimited(AppLocalizations t, int quota) =>
    quota == kUnlimitedQuota ? t.premium_table_unlimited : t.premium_table_max(quota);
