/// 购买页改版 · 对比表 + 源码守卫（付费墙 · 阶段 5 · 线 B）。
///
/// 覆盖设计文档 `docs/购买页改版_v1_系统设计.md` §10 的测试点 T1–T12（T8/T12 另有既有
/// 测试兜底，此处亦补轻量守卫）：
///  · T1 更名守卫（源码）：旧名 0 命中、6 处 UI 文案为「解锁全部功能」；
///  · T2 对比表渲染结构（widget）：两栏胶囊 / 三个分组带 / 7 行 3 组（F146）；
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
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_settings_page.dart';
import 'package:sunflower_time/presentation/parent/widgets/premium_unlock_table.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

/// 商店返回的本地化价格（与既有 `premium_page_test` 同款，刻意区别于硬编码金额）。
const String _storePrice = r'HK$88.00';

/// 🔴 红线词：**绝不**出现在购买页 / 对比表的对外文案里（Apple 3.1.1 / 2.3.1）。
/// F146：「深度报告」「多孩子档案」已真实接线并入对比表（合法），从红线词集移除；
/// 保留仍未实现的 3 项。
const List<String> _kRedLineWords = <String>[
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

/// 家长设置页的最小夹具（i18n B2：T1 守卫改「真实入口」渲染后需要泵整页）。
///
/// 只覆盖 [ParentSettingsPage] **build 期**真正读到的依赖：
/// `settingsRepositoryProvider`（`initState` 拉一次设置）与 `entitlementProvider`
/// （`PremiumStatusText` / `DebugUnlockSwitch`）。PIN 重设（`secureStoreProvider`）
/// 与阳光赠予（`sunlightRepositoryProvider`）只在点按时读，本守卫不点，故不装配。
class _FakeSettingsRepo implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 6,
      );

  @override
  Future<void> saveSettings(AppSettings s) async {}
}

/// 泵家长设置页（视口调高使 `ListView` 一次性布局，避免懒加载漏建控件）。
Future<void> _pumpSettingsPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ParentSettingsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  final String root = _projectRoot();

  // ───────────────────────────── T1 更名守卫 ─────────────────────────────
  group('阶段5 · T1 更名守卫（源码 + 真实入口渲染）', () {
    test('lib/** 不再出现旧名「会员与购买」/「了解会员」', () {
      final List<String> hits =
          _scanLib(root, <String>['会员与购买', '了解会员']);
      expect(hits, isEmpty, reason: '更名未彻底：\n${hits.join('\n')}');
    });

    test('lib/** 不再出现「升级解锁全部功能」（Q2 去掉「升级」）', () {
      final List<String> hits = _scanLib(root, <String>['升级解锁全部功能']);
      expect(hits, isEmpty, reason: 'Q2 标题统一未落地：\n${hits.join('\n')}');
    });

    // ── i18n B2：文案已全部迁入 ARB，源码里**不再有中文字面量**可钉 ──
    //
    // 守卫改为**两段式**（原文「逐字钉死 6 处中文」已随迁移失效）：
    //  ③-1 ARB 模板（zh）的文案槽位必须逐字为「解锁全部功能」——防译文回归 / 被改写；
    //  ③-2 从**真实入口**（购买页 / 设置页 / 门控 API）渲染出来的文案必须是该值
    //       ——防「ARB 对了但接线断了」。组件层自己传参不算验证（`confirmLabel:`
    //       是 `showPremiumUpsell` 从 ARB 取好再传进卡壳的，属实现细节），故一律
    //       走真入口泵页面 / 触发真 API 后断言屏幕上出现了什么。
    test('③-1 ARB 模板：文案槽位逐字为「解锁全部功能」', () {
      final AppLocalizations zh = AppLocalizationsZh();
      expect(zh.parent_premium_title, '解锁全部功能',
          reason: '购买页 AppBar 标题 + 主卡标题（2 处，Q2 标题统一）');
      expect(zh.premium_gate_unlock_all, '解锁全部功能',
          reason: '设置页分区标题 + 设置入口卡标题 + 配额轻提示动作 + 升级弹窗按钮'
              '（4 处，4 处更名）');
    });

    testWidgets('③-2 真实入口①购买页：AppBar 标题与主卡标题均为「解锁全部功能」',
        (WidgetTester tester) async {
      final _Env env = _buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      // 有界 pump 至商品加载完成（价格串来自商店，加载完才渲染主按钮）。
      await _pumpUntil(
        tester,
        () => find.textContaining('立即解锁').evaluate().isNotEmpty,
        maxFrames: 200,
      );

      expect(find.widgetWithText(AppBar, '解锁全部功能'), findsOneWidget,
          reason: '购买页 AppBar 标题应渲染「解锁全部功能」');
      expect(find.text('解锁全部功能'), findsNWidgets(2),
          reason: '购买页恰好 2 处：AppBar 标题 + 主卡标题（不得回归旧名）');
    });

    testWidgets('③-2 真实入口②设置页：分区标题与入口卡标题均为「解锁全部功能」',
        (WidgetTester tester) async {
      await _pumpSettingsPage(tester);

      expect(find.text('解锁全部功能'), findsNWidgets(2),
          reason: '设置页恰好 2 处：分区标题 + 金令牌入口卡标题（不得回归旧名）');
    });

    testWidgets('③-2 真实入口③门控 API：升级弹窗 4 处文案为迁移后取值',
        (WidgetTester tester) async {
      // 走 `PremiumGate.onTap`（生产页面调用的**唯一**回调型门控入口）：
      // `oneClickCare` 在免费档由矩阵**关闭**（布尔能力），应弹升级引导。
      // （注意不能选 `gardenPotCapacity` —— 它是**计数**能力，免费档仍放行，
      //  达上限才由 `PremiumQuotaGate` 拦，见下一用例。）
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(
            overrides: <Override>[
              entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
            ],
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => Center(
                  child: ElevatedButton(
                    onPressed: () => PremiumGate.onTap(
                      context,
                      FeatureKey.oneClickCare,
                      () {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('升级解锁'), findsOneWidget, reason: '弹窗标题');
      expect(find.text('「花园一键操作」需要一次性买断解锁。'), findsOneWidget,
          reason: '能力点名 + 一次性买断说明（带参 key，防占位符顺序漂移）');
      expect(find.text('稍后'), findsOneWidget, reason: '取消按钮');
      expect(find.text('解锁全部功能'), findsOneWidget, reason: '确认按钮');
    });
  });

  testWidgets('③-2 真实入口④配额门控：达上限轻提示动作文案已迁移',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
          ],
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  // 生产调用点：`parent_task_config_page` 的「新增」按钮。
                  onPressed: () => PremiumQuotaGate.onTap(
                    context: context,
                    feature: FeatureKey.taskTemplateCount,
                    currentCount: 5,
                    onAllowed: () {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text('免费版最多 5（当前 5），删除多余内容后即可新增'), findsOneWidget,
        reason: '轻提示正文（带参 key，limit / count 顺序不得漂移）');
    expect(find.text('解锁全部功能'), findsOneWidget,
        reason: '轻提示动作应渲染「解锁全部功能」');
  });

  group('阶段5 · T1 保留文案未被误改（描述句 / 升级动作）', () {
    test('ARB 模板：引导卡描述句与弹窗标题逐字保留', () {
      final AppLocalizations zh = AppLocalizationsZh();
      expect(zh.premium_gate_upsell_subtitle, '一次买断，永久解锁全部功能',
          reason: '引导卡描述句应保留原样');
      expect(zh.premium_gate_upsell_dialog_title, '升级解锁',
          reason: '弹窗标题「升级解锁」应保留原样');
    });

    testWidgets('真实入口：引导卡渲染出的描述句为原文（不得被误改）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PremiumUpsellCard(feature: FeatureKey.oneClickCare)),
        ),
      );
      await tester.pump();

      expect(find.text('解锁「花园一键操作」'), findsOneWidget,
          reason: '标题带能力点名（带参 key）');
      expect(find.text('一次买断，永久解锁全部功能'), findsOneWidget,
          reason: '描述句应保留原样');
    });
  });

  // ─────────────────────── T3 对比表数据派生（unit）───────────────────────
  group('阶段5 · T3 对比表数据派生（unit）', () {
    test('F146 后恰好 6 行，键序白名单（表行 2–7）', () {
      final List<PremiumUnlockRow> rows = unlockRowsFor();
      expect(rows.length, 6);
      expect(
        rows.map((PremiumUnlockRow r) => r.key).toList(),
        <FeatureKey>[
          FeatureKey.gardenPotCapacity,
          FeatureKey.taskTemplateCount,
          FeatureKey.multiChildProfile,
          FeatureKey.oneClickCare,
          FeatureKey.titlePerks,
          FeatureKey.deepReport,
        ],
        reason: '🔴 必须显式枚举这 6 个键（行序 = 新表行 2–7），禁止遍历 FeatureKey.values',
      );
      // 合并行（行 3）：主键 task + 次键 reward，守卫走 allKeys。
      expect(rows[1].secondaryKey, FeatureKey.rewardTemplateCount,
          reason: '模板合并行应挂 secondaryKey = rewardTemplateCount');
      expect(rows[1].allKeys,
          <FeatureKey>[FeatureKey.taskTemplateCount, FeatureKey.rewardTemplateCount],
          reason: '合并行 allKeys 恰为 task+reward 双键');
      expect(rows[1].allKeys.length, 2);
    });

    test('7 行 3 组结构守卫：容量组切分点 = kUnlockCapacityRowCount（防组件切分漂移）', () {
      final List<PremiumUnlockRow> rows = unlockRowsFor();
      expect(kUnlockCapacityRowCount, 3,
          reason: '数据层导出常量 = 3（组件消费切分，禁魔法数）');
      expect(
        rows.sublist(0, kUnlockCapacityRowCount).map((PremiumUnlockRow r) => r.key).toSet(),
        <FeatureKey>{
          FeatureKey.gardenPotCapacity,
          FeatureKey.taskTemplateCount,
          FeatureKey.multiChildProfile,
        },
        reason: 'rows[0..2]（容量组）键集 = {pots, 模板合并, profiles}',
      );
      expect(
        rows.sublist(kUnlockCapacityRowCount).map((PremiumUnlockRow r) => r.key).toSet(),
        <FeatureKey>{
          FeatureKey.oneClickCare,
          FeatureKey.titlePerks,
          FeatureKey.deepReport,
        },
        reason: 'rows[3..5]（进阶组）键集 = {oneClick, perks, report}',
      );
    });

    test('徽标退役守卫：badgeRowsFor 已删（批次 2 Ⓑ 场景卡取代）+ unlockRowsFor 恰 6 行', () {
      // 批次 2 Ⓑ（玄参 2026-10-23 拍板）：购买页权益速览改 3 场景卡（静态文案 +
      // 常量数字），badgeRowsFor 全链退役 —— 源码守卫防「删了又偷偷接回来」。
      expect(unlockRowsFor().length, 6, reason: '对比表派生 6 行（F146 改版）');
      final String gate = _read(
          root, 'lib/presentation/shared/premium_gate.dart');
      expect(gate.contains('badgeRowsFor'), isFalse,
          reason: 'badgeRowsFor 必须保持退役（场景卡后无消费方，复活即红）');
      final String page = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      for (final String key in <String>[
        'parent_premium_scene_garden_title',
        'parent_premium_scene_routine_title',
        'parent_premium_scene_perk_title',
      ]) {
        expect(page.contains(key), isTrue, reason: '场景卡应取词 $key');
      }
      expect(page.contains('badgeRowsFor'), isFalse,
          reason: '购买页不得再挂 badgeRowsFor');
    });

    test('取值来自矩阵（默认矩阵 → 期望文案，数字派生不写死）', () {
      final AppLocalizations zh = AppLocalizationsZh();
      final Map<FeatureKey, PremiumUnlockRow> byKey =
          <FeatureKey, PremiumUnlockRow>{
        for (final PremiumUnlockRow r in unlockRowsFor()) r.key: r,
      };
      expect(byKey[FeatureKey.oneClickCare]!.freeOk, isFalse,
          reason: '一键操作免费档已关闭 → freeOk=false');
      expect(byKey[FeatureKey.oneClickCare]!.premiumText, '✓ 不限');
      expect(byKey[FeatureKey.gardenPotCapacity]!.freeText, '$kFreeGardenPotQuota 个');
      expect(byKey[FeatureKey.gardenPotCapacity]!.premiumText, '最多 $kPremiumGardenPotQuota');
      // 模板合并行：free 列「各 5 条」（改版后 free_items 模板），premium 列「✓ 不限」。
      expect(byKey[FeatureKey.taskTemplateCount]!.freeText, '各 $kFreeTaskQuota 条',
          reason: '两模板配额相等（现网均 5）→ 合并行显示「各 5 条」');
      expect(byKey[FeatureKey.taskTemplateCount]!.premiumText, '✓ 不限');
      // C70：花盆行必须带注
      expect(byKey[FeatureKey.gardenPotCapacity]!.note, '扩容仍需花阳光');
      // 档案行（行 4）：数字派生自档案配额常量（不写死 1 / 3）。
      expect(byKey[FeatureKey.multiChildProfile]!.freeText,
          zh.premium_table_free_pots(kFreeChildProfileCount),
          reason: '档案行 freeText = free_pots(kFreeChildProfileCount)（1 派生）');
      expect(byKey[FeatureKey.multiChildProfile]!.premiumText,
          '最多 $kPremiumChildProfileCount',
          reason: '档案行 premiumText = max(kPremiumChildProfileCount)（3 派生）');
      // 报告行（行 7）：free 列「近 7 天」如实展示（freeOk 恒 true），premium 列与
      // 报告页引导横条口径对齐。
      expect(byKey[FeatureKey.deepReport]!.freeText, zh.premium_table_report_days);
      expect(byKey[FeatureKey.deepReport]!.freeOk, isTrue,
          reason: '日 / 周报告免费真实可用（C69 细化）');
      expect(byKey[FeatureKey.deepReport]!.premiumText, contains('月'));
      expect(byKey[FeatureKey.deepReport]!.premiumText, contains('热力图'));
      expect(byKey[FeatureKey.deepReport]!.premiumOk,
          featureAllowedFor(FeatureKey.deepReport, EntitlementTier.premium),
          reason: '报告行 premiumOk 派生自矩阵 premium 档');
      // C80：称号属性（free ✗ / premium ✓ 9 条，9 由 kFocusLevelTitleLevels 派生）。
      expect(byKey[FeatureKey.titlePerks]!.freeOk, isFalse,
          reason: '称号属性免费关闭（C80 门控）');
      expect(byKey[FeatureKey.titlePerks]!.freeText, '✗');
      expect(byKey[FeatureKey.titlePerks]!.premiumOk, isTrue);
      expect(byKey[FeatureKey.titlePerks]!.premiumText,
          '✓ ${kFocusLevelTitleLevels.length} 条',
          reason: 'premiumText 由 kFocusLevelTitleLevels.length 派生（9 派生，防漂移）');
      expect(byKey[FeatureKey.titlePerks]!.label, '称号属性');
    });

    test('注入自定义矩阵 → 输出随之变化（证明非硬编码；合并行回退形态）', () {
      final Map<FeatureKey, FeatureRule> custom =
          Map<FeatureKey, FeatureRule>.of(kEntitlementMatrix);
      // 注 task freeQuota=3（≠ reward 5）→ 合并行 free 列走「3 条 / 5 条」回退形态。
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
      expect(byKey[FeatureKey.taskTemplateCount]!.freeText, '3 条 / 5 条',
          reason: '两配额不等（3≠5）→ 合并行回退「N 条 / M 条」（free_items_single ×2）');
      expect(byKey[FeatureKey.taskTemplateCount]!.premiumText, '最多 2 / ✓ 不限',
          reason: 'premium 两配额不等 → 逐侧格式化后以「 / 」连接');
      // 未动的行不受影响
      expect(byKey[FeatureKey.gardenPotCapacity]!.freeText, '$kFreeGardenPotQuota 个');
    });

    test('数字不写死守卫：注入档案配额 → 档案行随之变化（行 4 派生自矩阵）', () {
      final Map<FeatureKey, FeatureRule> custom =
          Map<FeatureKey, FeatureRule>.of(kEntitlementMatrix);
      custom[FeatureKey.multiChildProfile] = const FeatureRule(
        key: FeatureKey.multiChildProfile,
        freeEnabled: true,
        freeQuota: 2,
        premiumQuota: kPremiumChildProfileCount,
      );
      final Map<FeatureKey, PremiumUnlockRow> byKey =
          <FeatureKey, PremiumUnlockRow>{
        for (final PremiumUnlockRow r in unlockRowsFor(matrix: custom)) r.key: r,
      };
      expect(byKey[FeatureKey.multiChildProfile]!.freeText, '2 个',
          reason: '档案行 freeText 派生自矩阵配额（而非写死「1 个」）');
      expect(byKey[FeatureKey.multiChildProfile]!.premiumText,
          '最多 $kPremiumChildProfileCount');
    });

    test('zh 模板逐字钉：新增 ARB key 文案不漂移（对齐两段式守卫惯例）', () {
      final AppLocalizations zh = AppLocalizationsZh();
      expect(zh.premium_table_row_core, '核心体验全免费');
      expect(zh.premium_table_band_capacity, '买断解锁 · 更大容量');
      expect(zh.premium_table_band_advanced, '买断解锁 · 进阶能力');
      expect(zh.premium_table_row_templates, '成长项 / 奖励模板');
      expect(zh.premium_table_row_profiles, '孩子档案');
      expect(zh.premium_table_report_premium, '加月 / 年报告 · 热力图');
      expect(zh.premium_table_footnote_core,
          '专注番茄钟 · 防沉迷作息 · 护眼休息 · 花园养成 · 阳光账本 · 商店兑换 · 40 级专注称号');
      expect(zh.premium_table_free_items(5), '各 5 条',
          reason: 'free_items 改版后为「各 N 条」（合并行共用）');
      expect(zh.premium_table_free_items_single(3), '3 条',
          reason: '回退形态单数条目文案（两配额不等时）');
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
      // F146：样例换仍未实现项（深度报告已真实接线入表，不再算违规）。
      // 样例须**字面含**红线词「数据导出」，否则守卫命中不了（形同虚设）。
      expect(_hitsRedLine('买断即可解锁「数据导出」功能'), isTrue,
          reason: '红线词集必须能命中违规样例，否则守卫形同虚设');
      expect(_hitsRedLine('买断即可导出数据'), isFalse,
          reason: '反例：字面不含红线词（说明守卫按词匹配而非语义）');
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

    test('运行期：unlockRowsFor 输出键集（含合并行 allKeys）不含任何未实现键', () {
      // F146：禁键集缩为 3（deepReport / multiChildProfile 已真实接线入表，合法）。
      // 取键走 [allKeys]（覆盖模板合并行双键，禁止绕过）。
      final Set<FeatureKey> keys = unlockRowsFor()
          .expand((PremiumUnlockRow r) => r.allKeys)
          .toSet();
      for (final FeatureKey k in <FeatureKey>[
        FeatureKey.exportShare,
        FeatureKey.memoirExport,
        FeatureKey.familySharing,
      ]) {
        expect(keys.contains(k), isFalse,
            reason: '未实现键 $k 出现在了对比表里（若新增一行即由本测试兜底变红）');
      }
    });

    test('批次 2 Ⓑ：权益速览 3 场景卡（emoji/取词/数字派生/无红线词）', () {
      final AppLocalizations zh = AppLocalizationsZh();
      // 源码：3 枚 emoji 与 3 组标题取词在位；旧 5 枚 emoji 表不得回潮。
      final String page = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      for (final String e in <String>['🌻', '📚', '👑']) {
        expect(page.contains(e), isTrue, reason: '场景卡 emoji $e 应在位');
      }
      expect(page.contains("'⚡', '🪴', '📋', '🎁', '🏅'"), isFalse,
          reason: '旧 5 枚 emoji 表已随批次 2 退役，不得回潮');
      // 数字派生纪律（C108-4 同源）：potMax/perkCount/profileMax 必须读常量。
      expect(page.contains('kPremiumGardenPotQuota'), isTrue,
          reason: '场景卡花盆上限应读矩阵买断档常量');
      expect(page.contains('kFocusLevelTitleLevels'), isFalse,
          reason: '守卫⑤：家长端文件禁 FocusLevel 子串，称号条数应走 kPremiumTitlePerkCount 别名');
      expect(page.contains('kPremiumTitlePerkCount'), isTrue,
          reason: '称号条数应派生自 kPremiumTitlePerkCount（premium_gate 收口别名）');
      expect(page.contains('kPremiumChildProfileCount'), isTrue,
          reason: '档案上限应读 kPremiumChildProfileCount');
      // 场景文案无红线词（未实现能力不进卖点）。
      for (final String s in <String>[
        zh.parent_premium_scene_garden_title,
        zh.parent_premium_scene_garden_detail(kPremiumGardenPotQuota),
        zh.parent_premium_scene_routine_title,
        zh.parent_premium_scene_routine_detail,
        zh.parent_premium_scene_perk_title,
        zh.parent_premium_scene_perk_detail(
            kFocusLevelTitleLevels.length, kPremiumChildProfileCount),
      ]) {
        expect(_hitsRedLine(s), isFalse, reason: '场景文案含红线词：$s');
      }
    });

    testWidgets('批次 2 Ⓑ：真实入口①购买页渲染 3 场景卡（标题 + 数字）', (WidgetTester tester) async {
      final _Env env = _buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);
      await _pumpPage(tester, env);
      await _pumpUntil(
        tester,
        () => find.textContaining('立即解锁').evaluate().isNotEmpty,
        maxFrames: 200,
      );
      expect(find.text('花园更宽敞'), findsOneWidget);
      expect(find.textContaining('花盆最多 12 盆'), findsOneWidget);
      expect(find.text('习惯随心配'), findsOneWidget);
      expect(find.textContaining('不限量'), findsOneWidget);
      expect(find.text('专属成长加成'), findsOneWidget);
      expect(find.textContaining('9 条称号属性'), findsOneWidget);
      expect(find.textContaining('最多 3 个孩子档案'), findsOneWidget);
      // 段落顺序（Ⓑ）：速览卡在对比表之前、知悉卡沉底 —— 用几何关系判定。
      final Finder scene = find.text('花园更宽敞');
      final Finder band = find.text('免费就能用');
      expect(tester.getTopLeft(scene).dy, lessThan(tester.getTopLeft(band).dy),
          reason: '场景速览卡应渲染在对比表之前');
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
    testWidgets('两栏胶囊 + 三个分组带 + 7 行 3 组项目名齐全（F146 改版）',
        (WidgetTester tester) async {
      await _pumpTable(tester);

      // 两栏胶囊
      expect(find.text('免费版'), findsOneWidget, reason: '免费列顶应有「免费版」胶囊');
      expect(find.textContaining('解锁全部功能'), findsOneWidget,
          reason: '买断列顶应有「解锁全部功能 ★」胶囊');
      // 三个分组带（F146：band_free + band_capacity + band_advanced）
      expect(find.text('免费就能用'), findsOneWidget);
      expect(find.text('买断解锁 · 更大容量'), findsOneWidget);
      expect(find.text('买断解锁 · 进阶能力'), findsOneWidget);
      // 行 1（静态核心行）+ 行 2–7（派生行）项目名
      for (final String label in <String>[
        '核心体验全免费',
        '花盆上限',
        '成长项 / 奖励模板',
        '孩子档案',
        '花园「一键操作」',
        '称号属性',
        '家长专注报告',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '7 行缺行：$label');
      }
      // 脚注（F146：核心脚注 + 花盆 note；「更多报告能力开发中」已随失实删除）
      expect(find.textContaining('专注番茄钟 ·'), findsOneWidget,
          reason: '行 1 核心脚注列举');
      expect(find.textContaining('扩容仍需花阳光'), findsOneWidget);
      // 报告行：free 列「近 7 天」1 处（premium 列改为 report_premium 口径）
      expect(find.text('近 7 天'), findsNWidgets(1));
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
    test('源码守卫：恢复购买入口 + 诚实说明卡 4 条仍在（i18n B2：钉 ARB key 接线）', () {
      final String src = _read(
          root, 'lib/presentation/parent/pages/parent_premium_page.dart');
      expect(src.contains('kPremiumRestoreButtonKey'), isTrue,
          reason: '「恢复购买」按钮 Key 不得删除');
      // i18n B2：文案已迁入 ARB，源码里钉的是**接线**（页内必须消费这些 key），
      // 文案本体由下面的 ARB 模板断言兜底 —— 两段合起来才等价于原来的「文案不得
      // 删除」，且不会因为「迁到 ARB」而误判为回归。
      expect(src.contains('t.parent_premium_restore'), isTrue,
          reason: '「恢复购买」文案必须来自 ARB');
      expect(src.contains('t.parent_premium_note_1'), isTrue,
          reason: '第 1 条：非订阅');
      expect(src.contains('t.parent_premium_note_3'), isTrue,
          reason: '第 3 条：跨平台不互通');
      expect(src.contains('t.parent_premium_note_4'), isTrue,
          reason: '第 4 条：支付由 Apple 处理');

      final AppLocalizations zh = AppLocalizationsZh();
      expect(zh.parent_premium_restore, '恢复购买',
          reason: 'Apple 对可恢复内购（非消耗型）硬性要求「恢复购买」入口');
      expect(zh.parent_premium_note_1.contains('不是订阅'), isTrue,
          reason: '第 1 条：非订阅');
      expect(zh.parent_premium_note_3.contains('Android'), isTrue,
          reason: '第 3 条：跨平台不互通');
      expect(zh.parent_premium_note_4.contains('支付信息'), isTrue,
          reason: '第 4 条：支付由 Apple 处理');
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
