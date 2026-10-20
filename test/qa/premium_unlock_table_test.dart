/// 购买页改版 · 对比表 + 源码守卫（付费墙 · 阶段 5 · 线 B）。
///
/// 覆盖设计文档 `docs/购买页改版_v1_系统设计.md` §10 的测试点 T1–T12（T8/T12 另有既有
/// 测试兜底，此处亦补轻量守卫）：
///  · T1 更名守卫（源码）：旧名 0 命中、6 处 UI 文案为「解锁全部功能」；
///  · T2 对比表渲染结构（widget）：两栏胶囊 / 两个分组带 / B 组 4 行；
///  · T3 数值**来自矩阵**（unit）：注入自定义矩阵 → 输出随之变化；
///  · T4 数据来源守卫（源码）：对比表组件不含任何权益标识符；
///  · T5 🔴 红线守卫（源码 + 运行期）：未实现能力**不进**对比表/预览徽标；**并做变异
///    自检**（守卫自身能命中违规样例）；
///  · T6 免费列中性米白 / 暖金只给买断列（源码，轻量）；
///  · T7 主按钮仍是可测的 `ButtonStyleButton`；T9 Apple 硬性要求存活；T10 已解锁态文案；
///  · T11 平板 ×1.3 + 窄屏 320 不溢出；T12 孩子端无购买入口（源码）。
library premium_unlock_table_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/premium_unlock_table.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

/// 商店返回的本地化价格（与既有 `premium_page_test` 同款，刻意区别于硬编码金额）。
const String _storePrice = r'HK$88.00';

/// 🔴 红线词：**绝不**出现在购买页 / 对比表的对外文案里（Apple 3.1.1 / 2.3.1）。
const List<String> _kRedLineWords = <String>[
  '深度报告',
  '多孩子档案',
  '数据导出',
  '纪念册',
  '家庭共享',
];

/// 工程根（与其它守卫测试同款防御）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

String _read(String root, String rel) =>
    File('$root/$rel').readAsStringSync();

/// 扫描 `lib/**.dart`，返回含任一 [words] 的 `rel:line` 命中清单。
List<String> _scanLib(String root, List<String> words) {
  final List<String> hits = <String>[];
  final Directory lib = Directory('$root/lib');
  for (final File f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final String rel = f.path.substring(root.length + 1).replaceAll('\\', '/');
    final List<String> lines = f.readAsStringSync().split('\n');
    for (int i = 0; i < lines.length; i++) {
      for (final String w in words) {
        if (lines[i].contains(w)) {
          hits.add('$rel:${i + 1}  «$w»  →  ${lines[i].trim()}');
        }
      }
    }
  }
  return hits;
}

bool _hitsRedLine(String src) =>
    _kRedLineWords.any((String w) => src.contains(w));

// ── 页面测试装配（假 IAP 适配器 + 真 IapService + 内存假票据仓储）──

class _FakeIapAdapter implements IapAdapter {
  _FakeIapAdapter({this.available = true});

  bool available;

  /// 商店返回的本地化价格（本文件测试恒用 [_storePrice]）。
  String price = _storePrice;

  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    if (!available) return const <IapProduct>[];
    return <IapProduct>[
      IapProduct(
        id: kIapProductIdLifetime,
        title: 'Lifetime',
        description: 'unlock all',
        price: price,
      ),
    ];
  }

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}

  Future<void> dispose() => _controller.close();
}

class _FakeRepo implements EntitlementRepository {
  _FakeRepo({Entitlement? initial}) : _stored = initial ?? Entitlement.free;

  Entitlement _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      _stored = entitlement;

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

class _Env {
  _Env({required this.container, required this.adapter});

  final ProviderContainer container;
  final _FakeIapAdapter adapter;
}

_Env _buildEnv({bool available = true, Entitlement? initial}) {
  final _FakeIapAdapter adapter = _FakeIapAdapter(available: available);
  final IapService svc = IapService(
    adapter: adapter,
    restoreGrace: const Duration(milliseconds: 40),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      iapServiceProvider.overrideWithValue(svc),
      entitlementServiceProvider.overrideWithValue(
        MatrixEntitlementService(repository: _FakeRepo(initial: initial), iap: svc),
      ),
      if (initial != null && initial.isPremium)
        entitlementProvider.overrideWith((Ref ref) => initial),
    ],
  );
  return _Env(container: container, adapter: adapter);
}

Future<void> _pumpPage(WidgetTester tester, _Env env) async {
  // 阶段 5：购买页新增「对比表」后内容显著变高，把测试视口调高使整页一次性布局
  // （仅避免 `ListView` 懒加载导致控件未构建，**不改任何断言**）。
  tester.view.physicalSize = const Size(400, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
      child: const MaterialApp(home: ParentPremiumPage()),
    ),
  );
}

/// 有界 pump（避免 pumpAndSettle 被无限动画 / SnackBar 计时器拖满）。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 120,
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return;
    await tester.pump(step);
  }
}

/// pump 对比表（可选注入文字缩放，模拟平板 ×1.3）。
Future<void> _pumpTable(
  WidgetTester tester, {
  bool isUnlocked = false,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[PremiumUnlockTable(isUnlocked: isUnlocked)],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final String root = _projectRoot();

  // ───────────────────────────── T1 更名守卫 ─────────────────────────────
  group('阶段5 · T1 更名守卫（源码）', () {
    test('lib/** 不再出现旧名「会员与购买」/「了解会员」', () {
      final List<String> hits =
          _scanLib(root, <String>['会员与购买', '了解会员']);
      expect(hits, isEmpty, reason: '更名未彻底：\n${hits.join('\n')}');
    });

    test('lib/** 不再出现「升级解锁全部功能」（Q2 去掉「升级」）', () {
      final List<String> hits = _scanLib(root, <String>['升级解锁全部功能']);
      expect(hits, isEmpty, reason: 'Q2 标题统一未落地：\n${hits.join('\n')}');
    });

    test('6 处 UI 文案均为「解锁全部功能」', () {
      final String premium = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      final String settings =
          _read(root, 'lib/presentation/parent/pages/parent_settings_page.dart');
      final String gate = _read(root, 'lib/presentation/shared/premium_gate.dart');

      // 4 处更名
      expect(premium.contains("AppBar(title: const Text('解锁全部功能'))"), isTrue,
          reason: '购买页 AppBar 标题应为「解锁全部功能」');
      expect(settings.contains("_SectionTitle('解锁全部功能')"), isTrue,
          reason: '设置页分区标题应为「解锁全部功能」');
      expect(gate.contains("label: '解锁全部功能',"), isTrue,
          reason: '配额轻提示动作应为「解锁全部功能」');
      // F141 ⑥：升级引导弹窗改走孩子端统一卡壳 `showChildConfirmCard`（文案逐字
      // 未变，仅写法从 `const Text('解锁全部功能'),` 变成卡壳的 `confirmLabel:`）。
      // 本守卫的意图是「文案不得回归」，故匹配**当前**调用形态的同一字面量。
      expect(gate.contains("confirmLabel: '解锁全部功能',"), isTrue,
          reason: '升级引导弹窗按钮应为「解锁全部功能」');
      // 2 处标题统一（Q2）
      expect(premium.contains("'解锁全部功能',"), isTrue,
          reason: '主卡标题应为「解锁全部功能」');
      expect(settings.contains("title: '解锁全部功能',"), isTrue,
          reason: '设置入口卡标题应为「解锁全部功能」');
    });

    test('保留文案未被误改（描述句 / 升级动作）', () {
      final String gate = _read(root, 'lib/presentation/shared/premium_gate.dart');
      expect(gate.contains('一次买断，永久解锁全部功能'), isTrue,
          reason: '引导卡描述句应保留原样');
      // F141 ⑥：同上，标题从 `const Text('升级解锁')` 变为卡壳的 `title:` 入参，
      // 文案字面量本身一字未改。
      expect(gate.contains("title: '升级解锁',"), isTrue,
          reason: '弹窗标题「升级解锁」应保留原样');
    });
  });

  // ─────────────────────── T3 对比表数据派生（unit）───────────────────────
  group('阶段5 · T3 对比表数据派生（unit）', () {
    test('C80 后恰好 5 行，键为 5 个真实生效项（白名单）', () {
      final List<PremiumUnlockRow> rows = unlockRowsFor();
      expect(rows.length, 5);
      expect(
        rows.map((PremiumUnlockRow r) => r.key).toList(),
        <FeatureKey>[
          FeatureKey.oneClickCare,
          FeatureKey.gardenPotCapacity,
          FeatureKey.taskTemplateCount,
          FeatureKey.rewardTemplateCount,
          FeatureKey.titlePerks,
        ],
        reason: '🔴 必须显式枚举这 5 个键（C80 加 titlePerks），禁止遍历 FeatureKey.values',
      );
    });

    test('取值来自矩阵（默认矩阵 → 期望文案）', () {
      final Map<FeatureKey, PremiumUnlockRow> byKey =
          <FeatureKey, PremiumUnlockRow>{
        for (final PremiumUnlockRow r in unlockRowsFor()) r.key: r,
      };
      expect(byKey[FeatureKey.oneClickCare]!.freeOk, isFalse,
          reason: '一键操作免费档已关闭 → freeOk=false');
      expect(byKey[FeatureKey.oneClickCare]!.premiumText, '✓ 不限');
      expect(byKey[FeatureKey.gardenPotCapacity]!.freeText, '$kFreeGardenPotQuota 个');
      expect(byKey[FeatureKey.gardenPotCapacity]!.premiumText, '最多 $kPremiumGardenPotQuota');
      expect(byKey[FeatureKey.taskTemplateCount]!.freeText, '$kFreeTaskQuota 条');
      expect(byKey[FeatureKey.rewardTemplateCount]!.freeText, '$kFreeRewardQuota 条');
      // kUnlimitedQuota → '不限'
      expect(byKey[FeatureKey.taskTemplateCount]!.premiumText, contains('不限'));
      expect(byKey[FeatureKey.rewardTemplateCount]!.premiumText, contains('不限'));
      // C70：花盆行必须带注
      expect(byKey[FeatureKey.gardenPotCapacity]!.note, '扩容仍需花阳光');
      // C80 第 5 行：称号属性（free ✗ / premium ✓ 9 条，9 由 kFocusLevelTitleLevels 派生）。
      expect(byKey[FeatureKey.titlePerks]!.freeOk, isFalse,
          reason: '称号属性免费关闭（C80 门控）');
      expect(byKey[FeatureKey.titlePerks]!.freeText, '✗');
      expect(byKey[FeatureKey.titlePerks]!.premiumOk, isTrue);
      expect(byKey[FeatureKey.titlePerks]!.premiumText,
          '✓ ${kFocusLevelTitleLevels.length} 条',
          reason: 'premiumText 由 kFocusLevelTitleLevels.length 派生（9 派生，防漂移）');
      expect(byKey[FeatureKey.titlePerks]!.label, '称号属性');
    });

    test('注入自定义矩阵 → 输出随之变化（证明非硬编码）', () {
      final Map<FeatureKey, FeatureRule> custom =
          Map<FeatureKey, FeatureRule>.of(kEntitlementMatrix);
      custom[FeatureKey.taskTemplateCount] = const FeatureRule(
        key: FeatureKey.taskTemplateCount,
        freeEnabled: true,
        freeQuota: 3,
        premiumQuota: 2,
      );
      final Map<FeatureKey, PremiumUnlockRow> byKey =
          <FeatureKey, PremiumUnlockRow>{
        for (final PremiumUnlockRow r in unlockRowsFor(matrix: custom)) r.key: r,
      };
      expect(byKey[FeatureKey.taskTemplateCount]!.freeText, '3 条',
          reason: '免费额度改为 3 → 对比表应显示「3 条」');
      expect(byKey[FeatureKey.taskTemplateCount]!.premiumText, '最多 2',
          reason: '买断额度改为 2 → 对比表应显示「最多 2」');
      // 未动的行不受影响
      expect(byKey[FeatureKey.rewardTemplateCount]!.freeText, '$kFreeRewardQuota 条');
    });
  });

  // ─────────────────── T4 / T5 / T6 源码与运行期守卫 ───────────────────
  group('阶段5 · T4 数据来源守卫（源码）', () {
    test('对比表组件不含任何权益标识符（守卫干净）', () {
      final String src = _read(
          root, 'lib/presentation/parent/widgets/premium_unlock_table.dart');
      for (final String token in <String>[
        'FeatureKey',
        'kEntitlementMatrix',
        'featureQuotaFor',
        'featureAllowedFor',
        'Entitlement',
        'PremiumGate',
        'FeatureRule',
        'kUnlimitedQuota',
      ]) {
        expect(src.contains(token), isFalse,
            reason: '对比表组件不得出现权益标识符「$token」（应全部在 premium_gate.dart 派生）');
      }
    });
  });

  group('阶段5 · T5 🔴 红线守卫（源码 + 运行期）', () {
    test('守卫自身非空：红线词集能命中一段典型违规样例（变异自检）', () {
      expect(_hitsRedLine('买断即可看深度报告'), isTrue,
          reason: '红线词集必须能命中违规样例，否则守卫形同虚设');
      expect(_hitsRedLine('专注番茄钟 · 花园养成'), isFalse);
    });

    test('购买页 / 对比表源码不含未实现能力字样', () {
      for (final String rel in <String>[
        'lib/presentation/parent/pages/parent_premium_page.dart',
        'lib/presentation/parent/widgets/premium_unlock_table.dart',
      ]) {
        expect(_hitsRedLine(_read(root, rel)), isFalse,
            reason: '$rel 出现未实现能力字样（Apple 3.1.1 拒审风险）');
      }
    });

    test('unlockRowsFor 不遍历 FeatureKey.values', () {
      final String src = _read(root, 'lib/presentation/shared/premium_gate.dart');
      expect(src.contains('FeatureKey.values'), isFalse,
          reason: '🔴 禁止遍历 FeatureKey.values（会把未实现键带进卖点）');
    });

    test('运行期：unlockRowsFor 输出键集不含任何未实现键', () {
      final Set<FeatureKey> keys =
          unlockRowsFor().map((PremiumUnlockRow r) => r.key).toSet();
      for (final FeatureKey k in <FeatureKey>[
        FeatureKey.deepReport,
        FeatureKey.multiChildProfile,
        FeatureKey.exportShare,
        FeatureKey.memoirExport,
        FeatureKey.familySharing,
      ]) {
        expect(keys.contains(k), isFalse,
            reason: '未实现键 $k 出现在了对比表里（若新增一行即由本测试兜底变红）');
      }
    });

    test('运行期：预览徽标数据源只含 5 项且标签无红线词（C80 第 5 枚 🏅）', () {
      final List<PremiumUnlockRow> rows = unlockRowsFor();
      expect(rows.length, 5, reason: '预览徽标 5 枚真实生效项（C80：+ 称号属性）');
      for (final PremiumUnlockRow r in rows) {
        expect(_hitsRedLine(r.label), isFalse);
      }
      // 预览徽标 emoji 表扩第 5 枚（源码断言，与 rows.length 同长防漏）。
      final String page =
          _read(root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      expect(page.contains("'⚡', '🪴', '📋', '🎁', '🏅'"), isTrue,
          reason: '预览徽标 emojis 常量应扩到 5 枚（V3-Q3 裁定加 🏅）');
    });
  });

  group('阶段5 · T6 免费列中性 / 暖金只给买断列（源码）', () {
    test('免费列底色为中性米白，买断列使用金色令牌', () {
      final String src = _read(
          root, 'lib/presentation/parent/widgets/premium_unlock_table.dart');
      expect(src.contains('0xFFF5F1E8'), isTrue, reason: '免费列底应为中性米白');
      expect(src.contains('0xFFE8C56A'), isTrue, reason: '买断列应有金描边');
      expect(src.contains('0xFFE8A600'), isTrue, reason: '买断列 ✓ 应为金色');
    });
  });

  // ───────────────────── T2 对比表渲染结构（widget）─────────────────────
  group('阶段5 · T2 对比表渲染结构（widget）', () {
    testWidgets('两栏胶囊 + 两个分组带 + B 组 5 行项目名齐全（C80：+ 称号属性）',
        (WidgetTester tester) async {
      await _pumpTable(tester);

      // 两栏胶囊
      expect(find.text('免费版'), findsOneWidget, reason: '免费列顶应有「免费版」胶囊');
      expect(find.textContaining('解锁全部功能'), findsOneWidget,
          reason: '买断列顶应有「解锁全部功能 ★」胶囊');
      // 两个分组带
      expect(find.text('免费就能用'), findsOneWidget);
      expect(find.text('买断后解锁'), findsOneWidget);
      // B 组 5 行项目名
      for (final String label in <String>[
        '花园「一键操作」',
        '花盆上限',
        '成长项模板',
        '奖励模板',
        '称号属性',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'B 组缺行：$label');
      }
      // A 组 8 行（含「商店兑换」与「家长专注报告」两行都保留）
      for (final String label in <String>[
        '专注番茄钟',
        '防沉迷与作息',
        '少儿护眼休息',
        '花园养成',
        '阳光经济与账本',
        '商店兑换',
        '专注等级 + 9 称号',
        '家长专注报告',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'A 组缺行：$label');
      }
      // 脚注（C70 + 报告能力如实标注）
      expect(find.textContaining('扩容仍需花阳光'), findsOneWidget);
      expect(find.textContaining('更多报告能力开发中'), findsOneWidget);
      // 报告行两栏同值
      expect(find.text('近 7 天'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('已解锁 → 买断列顶追加「已拥有」小徽标', (WidgetTester tester) async {
      await _pumpTable(tester, isUnlocked: true);
      expect(find.text('已拥有'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────────── T11 空间硬约束（widget）─────────────────────
  group('阶段5 · T11 平板 ×1.3 + 窄屏不溢出', () {
    testWidgets('窄屏 320×640 不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTable(tester);
      expect(tester.takeException(), isNull,
          reason: '320dp 窄屏下三列不得水平溢出');
    });

    testWidgets('平板 800×1200 + textScaler 1.3 叠加不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTable(tester, textScale: 1.3);
      expect(tester.takeException(), isNull,
          reason: '平板 ×1.3 叠加 320 窄屏不得溢出');
    });

    testWidgets('窄屏 320 + textScaler 1.3 叠加不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTable(tester, textScale: 1.3);
      expect(tester.takeException(), isNull,
          reason: '320 窄屏 + textScaler 1.3 叠加不得溢出（S4）');
    });
  });

  // ─────────────── T7 / T9 / T10 购买页主按钮与 Apple 要求 ───────────────
  group('阶段5 · T7 主按钮仍是 ButtonStyleButton（widget）', () {
    testWidgets('商店不可用 → 主按钮为 ButtonStyleButton 且 onPressed==null', (WidgetTester tester) async {
      final _Env env = _buildEnv(available: false);
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('暂不可购买').evaluate().isNotEmpty);

      final ButtonStyleButton btn =
          tester.widget<ButtonStyleButton>(find.byKey(kPremiumMainButtonKey));
      expect(btn.onPressed, isNull, reason: '商店不可用时主按钮必须禁用');
    });

    testWidgets('已解锁 → 主按钮仍为 ButtonStyleButton 且不可点', (WidgetTester tester) async {
      final _Env env = _buildEnv(initial: Entitlement.lifetime());
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(tester, () => find.text('已解锁').evaluate().isNotEmpty,
          maxFrames: 200);

      final ButtonStyleButton btn =
          tester.widget<ButtonStyleButton>(find.byKey(kPremiumMainButtonKey));
      expect(btn.onPressed, isNull, reason: '已解锁态主按钮应为不可点');
    });
  });

  group('阶段5 · T9 Apple 硬性要求存活（源码 + widget）', () {
    test('源码守卫：恢复购买入口 + 诚实说明卡 4 条仍在', () {
      final String src = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      expect(src.contains('kPremiumRestoreButtonKey'), isTrue,
          reason: '「恢复购买」按钮 Key 不得删除');
      expect(src.contains('恢复购买'), isTrue);
      expect(src.contains('不是订阅'), isTrue, reason: '第 1 条：非订阅');
      expect(src.contains('Android'), isTrue, reason: '第 3 条：跨平台不互通');
      expect(src.contains('支付信息'), isTrue, reason: '第 4 条：支付由 Apple 处理');
    });

    testWidgets('渲染守卫：恢复购买入口存在', (WidgetTester tester) async {
      final _Env env = _buildEnv(available: false);
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('暂不可购买').evaluate().isNotEmpty);
      expect(find.text('恢复购买'), findsOneWidget,
          reason: '即便商店不可用，恢复购买入口仍须保留');
    });

    test('价格只来自商店：购买页源码无硬编码金额', () {
      final String src = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      expect(RegExp(r'\$\s*\d').hasMatch(src), isFalse);
      expect(RegExp(r'[¥€£]\s*\d').hasMatch(src), isFalse);
    });
  });

  group('阶段5 · T10 已解锁态文案未回归（widget）', () {
    testWidgets('主卡胶囊仍保留精确「已解锁」文案', (WidgetTester tester) async {
      final _Env env = _buildEnv(initial: Entitlement.lifetime());
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(tester, () => find.text('已解锁').evaluate().isNotEmpty,
          maxFrames: 200);
      expect(find.text('已解锁'), findsWidgets,
          reason: '主卡胶囊的「已解锁」精确文案不得回归');
    });
  });

  // ───────────────────── T12 孩子端无购买入口（源码）─────────────────────
  group('阶段5 · T12 孩子端无购买入口（源码）', () {
    test('孩子端页面一律不含 /parent/premium（C81 ①：锁标只弹提示卡，不再跳转）', () {
      // 🔴 C81 修订（玄参拍板）：详情卡锁标点按改「只弹提示卡、不跳转」⇒ 孩子端
      // **零**购买入口（原 C80 的 `focus_level_badge` 白名单随之撤销）。
      final List<String> hits = <String>[];
      final Directory child = Directory('$root/lib/presentation/child');
      for (final File f in child.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final String rel =
            f.path.substring(root.length + 1).replaceAll('\\', '/');
        if (f.readAsStringSync().contains('/parent/premium')) {
          hits.add(rel);
        }
      }
      expect(hits, isEmpty,
          reason: '孩子端不得出现购买入口（C81 ①：锁标只弹提示卡）：'
              '${hits.join(', ')}');
    });
  });
}
