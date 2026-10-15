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
