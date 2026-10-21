/// 独立复验（QA）· 家长端「一次性买断」购买页（付费墙 · 阶段 3 第二批）。
///
/// 用**假 IapAdapter + 真 IapService（注入假适配器）+ 内存假票据仓储**驱动，
/// **零平台依赖**（绝不触碰真实 `in_app_purchase` / StoreKit）。覆盖：
///  · 加载中 → 商品返回 → 主按钮显示**商店返回的本地化价格**（断言用的是商店价格）；
///  · 购买成功 → `entitlementProvider` 变 premium → 主按钮出现「已解锁」；
///  · 用户取消 → 状态不变、无异常、有提示；
///  · 商店不可用 / `loadProducts` 抛错 → 降级文案 + 主按钮禁用、**不崩**；
///  · 恢复购买三态（restored / nothingToRestore / failed）各有正确 UI 反馈；
///  · 页面**存在「恢复购买」入口**（源码 + 组件双层守卫，防日后删除而拒审）。
library premium_page_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_premium_page.dart';

/// 商店返回的**本地化价格**（测试值）。刻意选一个与「常见硬编码 `$9.99`」不同的串，
/// 以证明主按钮用的是商店价格、而非页内写死的金额。
const String _storePrice = r'HK$88.00';

/// 记录型假适配器：可配置「可用性 / 抛错 / 发出的消息 / 商品价格」，离线驱动全部状态。
class _FakeIapAdapter implements IapAdapter {
  _FakeIapAdapter({this.available = true, this.price = _storePrice});

  bool available;
  String price;
  bool throwOnQuery = false;
  bool throwOnBuy = false;
  bool throwOnRestore = false;
  IapMessage? buyMessage;
  IapMessage? restoreMessage;

  final StreamController<IapMessage> _controller =
      StreamController<IapMessage>.broadcast();

  @override
  Stream<IapMessage> get messages => _controller.stream;

  @override
  Future<bool> isStoreAvailable() async => available;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async {
    if (throwOnQuery) throw StateError('query boom');
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
  Future<void> startLifetimePurchase(String productId) async {
    if (throwOnBuy) throw StateError('buy boom');
    final IapMessage? m = buyMessage;
    if (m != null) _controller.add(m);
  }

  @override
  Future<void> startRestore() async {
    if (throwOnRestore) throw StateError('restore boom');
    final IapMessage? m = restoreMessage;
    if (m != null) _controller.add(m);
  }

  Future<void> dispose() => _controller.close();
}

/// 内存假票据仓储（零平台依赖）。
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

/// 测试装配：假适配器 + 真 [IapService]（注入假适配器）+ 域服务（注入假仓储）。
class _Env {
  _Env({required this.container, required this.adapter});

  final ProviderContainer container;
  final _FakeIapAdapter adapter;
}

_Env _buildEnv({
  bool available = true,
  String price = _storePrice,
  bool throwOnQuery = false,
  bool throwOnBuy = false,
  bool throwOnRestore = false,
  IapMessage? buyMessage,
  IapMessage? restoreMessage,
  Entitlement? initial,
}) {
  final _FakeIapAdapter adapter = _FakeIapAdapter(available: available, price: price)
    ..throwOnQuery = throwOnQuery
    ..throwOnBuy = throwOnBuy
    ..throwOnRestore = throwOnRestore
    ..buyMessage = buyMessage
    ..restoreMessage = restoreMessage;
  final _FakeRepo repo = _FakeRepo(initial: initial);
  // 短宽限窗口：无购买历史时尽快判 `nothingToRestore`，避免测试久等。
  final IapService svc = IapService(
    adapter: adapter,
    restoreGrace: const Duration(milliseconds: 40),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      iapServiceProvider.overrideWithValue(svc),
      entitlementServiceProvider.overrideWithValue(
        MatrixEntitlementService(repository: repo, iap: svc),
      ),
    ],
  );
  return _Env(container: container, adapter: adapter);
}

Future<void> _pumpPage(WidgetTester tester, _Env env) async {
  // 阶段 5：购买页新增「对比表」后内容显著变高（主按钮落到首屏之下），把测试视口
  // 调高使整页一次性布局 —— 仅避免 `ListView` 懒加载导致控件未构建，**不改任何断言**。
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

/// 有界 pump（避免 pumpAndSettle 被 SnackBar 计时器拖满）。
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

/// 排空 SnackBar 的自动消失计时器，避免测试结束时有 pending timer。
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump();
}

/// 工程根（与其它守卫测试同款防御：无论从工程根还是 `test/qa` 运行都能定位）。
String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  final String root = _projectRoot();
  group('购买页 · 加载与价格', () {
    testWidgets('加载中 → 商品返回 → 主按钮显示商店本地化价格', (WidgetTester tester) async {
      final _Env env = _buildEnv();
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      // 首帧：商品未返回，处于加载中。
      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: '商品拉取完成前应显示加载中');

      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      expect(find.text('立即解锁 · $_storePrice'), findsOneWidget,
          reason: '主按钮必须用商店返回的本地化价格（$_storePrice），而非硬编码金额');
      expect(find.text('恢复购买'), findsOneWidget,
          reason: 'Apple 硬性要求：可恢复内购必须有「恢复购买」入口');
      expect(find.text('暂时连不上商店'), findsNothing,
          reason: '商店可用时不应出现降级文案');
    });
  });

  group('购买页 · 购买三态', () {
    testWidgets('购买成功 → entitlementProvider=premium → 主按钮出现「已解锁」',
        (WidgetTester tester) async {
      final _Env env = _buildEnv(
        buyMessage: const IapMessage(
          state: IapMessageState.purchased,
          productId: kIapProductIdLifetime,
          jws: 'JWS-buy',
        ),
      );
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      await tester.tap(find.text('立即解锁 · $_storePrice'));
      await _pumpUntil(
        tester,
        () => env.container.read(entitlementProvider).isPremium,
        maxFrames: 200,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isTrue,
          reason: '购买成功后权益必须刷新为 premium');
      expect(find.text('已解锁'), findsWidgets,
          reason: '已解锁后主按钮应变为「已解锁」态');
      // 已解锁态：主按钮不可点。
      final ButtonStyleButton unlockedBtn =
          tester.widget<ButtonStyleButton>(find.byKey(kPremiumMainButtonKey));
      expect(unlockedBtn.onPressed, isNull,
          reason: '已解锁后主按钮应为不可点的「已解锁」态');
      await _drainSnack(tester);
    });

    testWidgets('用户取消 → 状态不变、无异常、有提示', (WidgetTester tester) async {
      final _Env env = _buildEnv(
        buyMessage: const IapMessage(
          state: IapMessageState.canceled,
          productId: kIapProductIdLifetime,
        ),
      );
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      await tester.tap(find.text('立即解锁 · $_storePrice'));
      await _pumpUntil(
        tester,
        () => find.textContaining('购买未完成').evaluate().isNotEmpty,
        maxFrames: 200,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isFalse,
          reason: '取消后权益不得变为 premium');
      expect(find.textContaining('购买未完成'), findsOneWidget,
          reason: '取消后必须给用户明确提示');
      expect(find.text('立即解锁 · $_storePrice'), findsOneWidget,
          reason: '取消后主按钮仍在（可再次购买）');
      expect(tester.takeException(), isNull, reason: '取消不得抛异常');
      await _drainSnack(tester);
    });
  });

  group('购买页 · 商店不可用降级', () {
    testWidgets('商店不可用 → 降级文案 + 主按钮禁用、不崩', (WidgetTester tester) async {
      final _Env env = _buildEnv(available: false);
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('暂时连不上商店').evaluate().isNotEmpty);

      expect(find.text('暂时连不上商店'), findsOneWidget,
          reason: '商店不可用必须给出离线降级文案');
      expect(find.text('暂不可购买'), findsOneWidget,
          reason: '商店不可用时主按钮文案应回到「暂不可购买」');
      final ButtonStyleButton mainBtn =
          tester.widget<ButtonStyleButton>(find.byKey(kPremiumMainButtonKey));
      expect(mainBtn.onPressed, isNull, reason: '商店不可用时主按钮必须禁用');
      expect(find.text('恢复购买'), findsOneWidget,
          reason: '即便商店不可用，「恢复购买」入口仍须保留');
      expect(tester.takeException(), isNull, reason: '商店不可用不得崩');
    });

    testWidgets('loadProducts 抛错 → 同样降级、不崩', (WidgetTester tester) async {
      final _Env env = _buildEnv(throwOnQuery: true);
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('暂时连不上商店').evaluate().isNotEmpty);

      expect(find.text('暂不可购买'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '商品查询抛错不得崩');
      expect(env.container.read(entitlementProvider).isPremium, isFalse);
    });
  });

  group('购买页 · 恢复购买三态', () {
    testWidgets('restored → 已解锁 + 「已恢复」提示', (WidgetTester tester) async {
      final _Env env = _buildEnv(
        restoreMessage: const IapMessage(
          state: IapMessageState.restored,
          productId: kIapProductIdLifetime,
          jws: 'JWS-restore',
        ),
      );
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      await tester.tap(find.text('恢复购买'));
      await _pumpUntil(
        tester,
        () => env.container.read(entitlementProvider).isPremium,
        maxFrames: 200,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isTrue,
          reason: 'restored 后权益应变 premium');
      expect(find.textContaining('已恢复购买'), findsOneWidget,
          reason: 'restored 应有成功提示');
      await _drainSnack(tester);
    });

    testWidgets('nothingToRestore → 状态不变 + 「没有找到」提示', (WidgetTester tester) async {
      final _Env env = _buildEnv(); // 不发任何消息 → 宽限窗口内无 → nothingToRestore
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      await tester.tap(find.text('恢复购买'));
      await _pumpUntil(
        tester,
        () => find.textContaining('没有找到可恢复').evaluate().isNotEmpty,
        maxFrames: 300,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isFalse,
          reason: '无购买历史不得误判为已解锁');
      expect(find.textContaining('没有找到可恢复'), findsOneWidget,
          reason: 'nothingToRestore 应如实告知「没找到记录」');
      await _drainSnack(tester);
    });

    testWidgets('failed → 状态不变 + 「恢复失败」提示', (WidgetTester tester) async {
      final _Env env = _buildEnv(throwOnRestore: true);
      addTearDown(env.container.dispose);
      addTearDown(env.adapter.dispose);

      await _pumpPage(tester, env);
      await _pumpUntil(
          tester, () => find.text('立即解锁 · $_storePrice').evaluate().isNotEmpty);

      await tester.tap(find.text('恢复购买'));
      await _pumpUntil(
        tester,
        () => find.textContaining('恢复失败').evaluate().isNotEmpty,
        maxFrames: 300,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(env.container.read(entitlementProvider).isPremium, isFalse);
      expect(find.textContaining('恢复失败'), findsOneWidget,
          reason: 'failed 应提示「稍后重试」而非谎报未购');
      expect(tester.takeException(), isNull);
      await _drainSnack(tester);
    });
  });

  group('购买页 · 「恢复购买」入口守卫（防拒审）', () {
    test('源码守卫：购买页必须接线「恢复购买」ARB 文案（i18n B2 后不再有字面量）',
        () {
      final String src = File(
        '$root/lib/presentation/parent/pages/parent_premium_page.dart',
      ).readAsStringSync();
      // i18n B2：文案已迁入 ARB，源码里钉**接线**（页内消费该 key），文案本体由
      // ARB 模板断言兜底；二者合起来等价于原来的字面量守卫。
      expect(src.contains('t.parent_premium_restore'), isTrue,
          reason: 'Apple 对可恢复内购（非消耗型）硬性要求「恢复购买」入口，缺了必被拒审');
      expect(AppLocalizationsZh().parent_premium_restore, '恢复购买',
          reason: 'ARB 模板必须逐字为「恢复购买」');
    });

    test('源码守卫：购买页不得硬编码货币金额（价格只来自商店）', () {
      final String src = File(
        '$root/lib/presentation/parent/pages/parent_premium_page.dart',
      ).readAsStringSync();
      // 页内不应出现「$ + 数字」形态的写死金额（形如 $9.99 / ¥12）。
      expect(RegExp(r'\$\s*\d').hasMatch(src), isFalse,
          reason: '价格必须来自 IapProduct.price，不得硬编码金额');
      expect(RegExp(r'[¥€£]\s*\d').hasMatch(src), isFalse,
          reason: '价格必须来自 IapProduct.price，不得硬编码货币符号金额');
    });
  });
}
