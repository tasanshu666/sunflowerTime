/// 权益标识符源码守卫测试（付费墙 · 阶段 1）。
///
/// 为什么存在：付费墙最危险的失败模式是「门控点四散」——某处随手写
/// `if (entitlement.isPremium)` 绕过门控矩阵，阶段 4 收紧能力时漏改、留后门。
/// 本测试直读 `lib/**.dart` 源码，把权益标识符钉死在**白名单文件**内：
/// 其它任何文件出现即红，逼所有门控走 [`PremiumGate`] / 门控矩阵单点收口。
///
/// 范式参照 `test/m3/fx_frame_assets_guard_test.dart`（读源码 + 正则/包含断言）。
///
/// 注：**刻意不把裸 `isPremium` 列入禁用词**——项目内 `PlantSpecies.isPremium`
/// （植物稀有度）已广泛使用，会误伤。守卫只钉**权益命名空间**的标识符。
library entitlement_gate_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

/// 允许出现权益标识符的白名单（相对工程根，使用 `/` 分隔）。
final Set<String> _whitelist = <String>{
  'lib/domain/entities/entitlement.dart',
  'lib/domain/services/entitlement_service.dart',
  'lib/domain/repositories/entitlement_repository.dart',
  'lib/core/constants/entitlement_matrix.dart',
  'lib/core/constants/iap_product_ids.dart',
  'lib/data/local/secure_entitlement_store.dart',
  'lib/data/local/repositories/entitlement_local_repository.dart',
  'lib/core/di/providers.dart', // DI 装配：登记 entitlement* Provider
  'lib/presentation/shared/premium_gate.dart',
  'lib/platform/iap_service.dart', // 阶段 2 平台层（此刻可能尚未创建）
  // 阶段 3 第二批：一次性买断购买页（读取/刷新 entitlementProvider 是**合法**用途，
  // 非门控点；门控仍只经 PremiumGate / 门控矩阵）。设置页复用本页导出的
  // PremiumStatusText 副标题组件，故设置页自身不出现权益标识符（守卫仍紧）。
  'lib/presentation/parent/pages/parent_premium_page.dart',
  // 阶段 4 付费门控接线：
  //  · main.dart：冷启动 P1 修复（读取 entitlementService/Provider 加载票据）——合法用途；
  //  · 4 个门控接线页/服务：孩子端花园页（一键 FAB / 花盆容量判定）、家长端任务配置页、
  //    家长端奖励页（新增配额判定）、域层植物养成服务（expandPot 上限域层防线）。
  //    这些文件均**只读矩阵单点**（featureAllowedFor / featureQuotaFor / quotaAllowsAdd），
  //    不散落 `isPremium` 判定，故纳入白名单。
  'lib/main.dart',
  'lib/presentation/child/pages/garden_page.dart',
  'lib/presentation/parent/pages/parent_task_config_page.dart',
  'lib/presentation/parent/pages/parent_reward_page.dart',
  'lib/domain/services/plant_growth_service.dart',
  // C80 第二批（称号属性付费解锁 · 详情卡改版）：
  //  · focus_level_badge.dart：详情卡改 ConsumerWidget，读 entitlementProvider +
  //    featureAllowedFor(titlePerks) 给每行属性徽章下发**锁标态**（合法展示用途，
  //    非门控散落——门控仍只经矩阵单点）；
  //  · level_up_fx_overlay.dart：升级演出卡同理（免费档属性行置灰 + 🔒付费解锁尾缀）。
  //    两者均只读矩阵单点，且**仅** FeatureKey.titlePerks 一处，绝不含 isPremium 判定。
  'lib/presentation/child/widgets/focus_level_badge.dart',
  'lib/presentation/child/widgets/level_up_fx_overlay.dart',
  // C76 第三批（专注报告 v2 · 报告段门控接线 T03）：
  //  · focus_report_section.dart：报告段的**判定单点**（读 entitlementProvider +
  //    featureAllowedFor(deepReport) 决定要不要取热力图 / 稳定性数据、要不要拦月/年）。
  //    这是全仓唯一新增的门控点：色板 / 周期条 / 热力图 / 稳定性卡 / 护眼卡
  //    **一律只吃 `bool unlocked`**，故其余 5 个新文件都不在白名单里（守卫仍紧）。
  'lib/presentation/parent/widgets/focus_report_section.dart',
  // C86 第四批（任务与奖励段加「年」粒度 + 免费档锁月/年）：
  //  · history_activity_section.dart：记录页「任务与奖励」段的**判定单点**（读
  //    entitlementProvider + featureAllowedFor(deepReport) 决定月/年是否置锁 /
  //    点击是否拦下弹「升级解锁」）。与报告段**同一 key**（不新增 FeatureKey），
  //    且周期算术 / 聚合 / 条导航**一律只吃 `bool unlocked` 与 `Set<_Period>`**。
  'lib/presentation/parent/widgets/history_activity_section.dart',
};

/// 权益命名空间标识符（词边界、大小写敏感）。
final List<RegExp> _tokens = <RegExp>[
  RegExp(r'\bEntitlement'), // Entitlement / EntitlementTier / EntitlementService / ...
  RegExp(r'\bFeatureKey\b'),
  RegExp(r'\bFeatureRule\b'),
  RegExp(r'\bRestoreResult\b'),
  RegExp(r'\bPremiumGate\b'),
  RegExp(r'\bkEntitlementMatrix\b'),
  RegExp(r'\bkUnlimitedQuota\b'),
  RegExp(r'\bentitlementProvider\b'),
  RegExp(r'\bentitlementServiceProvider\b'),
  RegExp(r'\bentitlementRepositoryProvider\b'),
];

/// 把绝对路径转成相对工程根的、以 `/` 分隔的路径。
String _rel(String root, String absPath) =>
    absPath.substring(root.length + 1).replaceAll('\\', '/');

void main() {
  final String root = _projectRoot();

  test('守卫自身非空：token 集能命中一段典型的违规代码', () {
    const String sample =
        'final Entitlement e = Entitlement.free; if (e.isPremium) {}';
    expect(_tokens.any((RegExp r) => r.hasMatch(sample)), isTrue,
        reason: '禁用词集必须能命中权益标识符，否则守卫形同虚设');
  });

  test('白名单文件真实存在（防拼写漂移使守卫失效）', () {
    for (final String rel in <String>[
      'lib/domain/entities/entitlement.dart',
      'lib/domain/services/entitlement_service.dart',
      'lib/domain/repositories/entitlement_repository.dart',
      'lib/core/constants/entitlement_matrix.dart',
      'lib/core/constants/iap_product_ids.dart',
      'lib/data/local/secure_entitlement_store.dart',
      'lib/data/local/repositories/entitlement_local_repository.dart',
      'lib/core/di/providers.dart',
      'lib/presentation/shared/premium_gate.dart',
      'lib/presentation/parent/pages/parent_premium_page.dart',
      'lib/platform/iap_service.dart',
      'lib/main.dart',
      'lib/presentation/child/pages/garden_page.dart',
      'lib/presentation/parent/pages/parent_task_config_page.dart',
      'lib/presentation/parent/pages/parent_reward_page.dart',
      'lib/domain/services/plant_growth_service.dart',
      'lib/presentation/child/widgets/focus_level_badge.dart',
      'lib/presentation/child/widgets/level_up_fx_overlay.dart',
      'lib/presentation/parent/widgets/focus_report_section.dart',
      'lib/presentation/parent/widgets/history_activity_section.dart',
    ]) {
      expect(File('$root/$rel').existsSync(), isTrue,
          reason: '白名单文件不应缺失（缺失说明重构后守卫白名单失效）：$rel');
    }
  });

  test('权益标识符只允许出现在白名单文件内（lib/**.dart）', () {
    final Directory lib = Directory('$root/lib');
    expect(lib.existsSync(), isTrue, reason: '缺 lib 目录');

    final List<String> violations = <String>[];
    final List<File> dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    for (final File f in dartFiles) {
      final String rel = _rel(root, f.path);
      if (_whitelist.contains(rel)) continue;
      final List<String> lines = f.readAsStringSync().split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // 🔴 判据精度（2026-10-15，team-lead 拍板）：**整行注释**不计入违例 ——
        //    本守卫拦的是「代码引用权益标识符」（门控点四散），文档/注释里**提到**
        //    该词（如 C77 设计说明「判定不读权益来源」）不是门控点，不算违宪。
        //    ⚠️ 行内**尾**注释不做豁免（该行本身是代码，仍会命中）→ 守卫强度不降。
        if (line.trimLeft().startsWith('//')) continue;
        for (final RegExp token in _tokens) {
          if (token.hasMatch(line)) {
            violations.add('$rel:${i + 1} 出现「${token.pattern}」→ $line');
            break; // 同一行只报一次
          }
        }
      }
    }

    expect(violations, isEmpty,
        reason: '付费墙门控点四散：以下文件出现权益标识符却不在白名单内。\n'
            '请改为走 PremiumGate / 门控矩阵单点收口，或（若是合法的权益相关新文件）'
            '加入本测试白名单：\n${violations.join('\n')}');
  });
}
