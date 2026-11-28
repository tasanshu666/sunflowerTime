/// iOS 对照组：Android 支付接入后，iOS 付费页**逐字节保持基线**。
///
/// 双保险：① widget 级断言 iOS 主按钮 / 恢复购买 / 吸底 / 四条 note；
///         ② 源码级断言 iOS 分支的关键字面量一字未改（防「顺手重构」）。
library premium_alipay_ios_control_test;

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

const String _storePrice = r'HK$88.00';

class _FakeIapAdapter implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<List<IapProduct>> queryProducts(Set<String> productIds) async =>
      <IapProduct>[
        const IapProduct(
          id: kIapProductIdLifetime,
          title: 'Lifetime',
          description: 'unlock all',
          price: _storePrice,
        ),
      ];

  @override
  Future<void> startLifetimePurchase(String productId) async {}

  @override
  Future<void> startRestore() async {}
}

class _FakeRepo implements EntitlementRepository {
  Entitlement stored = Entitlement.free;

  @override
  Future<Entitlement> read() async => stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async =>
      stored = entitlement;

  @override
  Future<void> clear() async => stored = Entitlement.free;
}

void main() {
  final AppLocalizationsZh t = AppLocalizationsZh();

  setUp(() {
    redeemCodeEntryEnabledResolver = () => false;
    alipayEntryEnabledResolver = () => false;
  });
  tearDown(() {
    redeemCodeEntryEnabledResolver = defaultRedeemCodeEntryEnabled;
    alipayEntryEnabledResolver = defaultAlipayEntryEnabled;
  });

  testWidgets('iOS：主按钮仍为商店本地化价格，恢复购买常驻，支付宝入口零渲染',
      (WidgetTester tester) async {
    final _FakeRepo repo = _FakeRepo();
    final IapService iap = IapService(adapter: _FakeIapAdapter());
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      iapServiceProvider.overrideWithValue(iap),
      entitlementRepositoryProvider.overrideWithValue(repo),
      entitlementServiceProvider.overrideWithValue(
        MatrixEntitlementService(repository: repo, iap: iap),
      ),
    ]);
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ParentPremiumPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.parent_premium_btn_unlock_now(_storePrice)),
        findsOneWidget);
    expect(find.byKey(kPremiumRestoreButtonKey), findsOneWidget);
    expect(find.text(t.parent_premium_restore), findsOneWidget);
    // 吸底结构：主按钮 + 恢复按钮仍在同一个 Scaffold.bottomNavigationBar 槽位。
    expect(find.byKey(kPremiumMainButtonKey), findsOneWidget);
    // Android 专属入口一律不渲染。
    expect(find.byKey(kPremiumAlipayCodeEntryKey), findsNothing);
    expect(find.byKey(kPremiumAlipayReclaimKey), findsNothing);
    expect(find.byKey(kPremiumAlipayPhaseKey), findsNothing);
    expect(find.text(t.parent_premium_alipay_btn_buy), findsNothing);
    expect(find.text(t.parent_premium_alipay_note_refund), findsNothing);
    // Apple 合规 note 四条一字未动。
    for (final String note in <String>[
      t.parent_premium_note_1,
      t.parent_premium_note_2,
      t.parent_premium_note_3,
      t.parent_premium_note_4,
    ]) {
      expect(find.text(note), findsOneWidget);
    }
  });

  test('源码级：iOS 分支关键字面量与吸底结构逐字节不变', () {
    final File file = File(
      'lib/presentation/parent/pages/parent_premium_page.dart',
    );
    final String source = file.readAsStringSync();

    // iOS 主按钮的完整判定块（改动前后逐字节一致）。
    expect(
      source,
      contains(
        'final bool enabled =\n'
        '        !_storeUnavailable && !_buying && !_restoring && price.isNotEmpty;',
      ),
    );
    expect(
      source,
      contains('final String label = _buying\n'
          '        ? t.parent_premium_btn_buying\n'
          '        : _storeUnavailable || price.isEmpty\n'
          '            ? t.parent_premium_btn_unavailable\n'
          '            : t.parent_premium_btn_unlock_now(price);'),
    );
    // Apple 硬性要求的恢复购买入口：if (!_usesRedeemCode) 块逐字节不变。
    expect(
      source,
      contains(
        'if (!_usesRedeemCode) ...<Widget>[\n'
        '              const SizedBox(height: 6),\n'
        '              _buildRestoreButton(t),\n'
        '            ],',
      ),
    );
    // iOS 四条 note 的选择分支逐字节不变。
    expect(
      source,
      contains(
        ': <String>[\n'
        '            t.parent_premium_note_1,\n'
        '            t.parent_premium_note_2,\n'
        '            t.parent_premium_note_3,\n'
        '            t.parent_premium_note_4,\n'
        '          ];',
      ),
    );
    // isAndroidRuntime 判定本体不动（仍用 dart:io，不采信 defaultTargetPlatform）。
    expect(
      source,
      contains(
        'bool get isAndroidRuntime {\n'
        '  if (kIsWeb) return false;\n'
        '  try {\n'
        '    return Platform.isAndroid;\n'
        '  } catch (_) {\n'
        '    return false;\n'
        '  }\n'
        '}',
      ),
    );
  });
}
