/// 免费零回归守卫测试（付费墙 · 阶段 1 收口）。
///
/// 目的：把「未开通（free）」态的行为**钉死为与今天一致**——阶段 1 不接线任何门控点，
/// 门控矩阵全放开，故免费用户的一切能力、一切页面行为都不应改变。
///
/// 覆盖三层：
///  1. 矩阵不变量：每个能力点 free 与 premium 判定 / 额度完全等价（全放开）；
///  2. 组件行为：free 态下 [`PremiumGate`] 原样放行 child（不显示付费引导）；
///  3. 源码守卫：关键免费入口（花园一键操作、家长报告页）未被权益判定缠上。
library free_tier_no_regression_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/qa') || cwd.endsWith('\\test\\qa')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  final String root = _projectRoot();

  group('矩阵不变量：阶段 1 免费行为 = 现状', () {
    test('每个能力点 free 与 premium 完全等价', () {
      for (final FeatureKey f in FeatureKey.values) {
        expect(featureAllowedFor(f, EntitlementTier.free), isTrue,
            reason: '$f 阶段 1 免费必须放行（否则免费功能退化）');
        expect(
          featureAllowedFor(f, EntitlementTier.free),
          featureAllowedFor(f, EntitlementTier.premium),
          reason: '$f free/premium 判定必须等价',
        );
        expect(
          featureQuotaFor(f, EntitlementTier.free),
          featureQuotaFor(f, EntitlementTier.premium),
          reason: '$f free/premium 额度必须等价',
        );
      }
    });
  });

  group('未开通态：PremiumGate 原样放行（不拦任何人）', () {
    testWidgets('free 档 + 矩阵放开 → 展示 child 且不出现付费引导卡', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PremiumGate(
                feature: FeatureKey.oneClickCare,
                child: Text('CHILD'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('CHILD'), findsOneWidget,
          reason: '未开通态下 PremiumGate 必须放行（阶段 1 全放开）');
      expect(find.byType(PremiumUpsellCard), findsNothing,
          reason: '未开通态不应出现付费引导（会与今天不一致）');
    });

    testWidgets('premium 档亦放行（购买后行为不变）', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider
                .overrideWith((Ref ref) => Entitlement.lifetime()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PremiumGate(
                feature: FeatureKey.parentReport,
                child: Text('CHILD'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('CHILD'), findsOneWidget);
      expect(find.byType(PremiumUpsellCard), findsNothing);
    });
  });

  group('源码守卫：关键免费入口未被门控缠上', () {
    test('花园页「一键操作」出现条件仍只看存活株数（无权益判定）', () {
      final String src = File(
        '$root/lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      expect(src.contains('_showOneClickFab'), isTrue,
          reason: '花园页一键操作出现条件（_showOneClickFab）应仍存在');
      expect(src.contains('kOneClickMinPlants'), isTrue,
          reason: '一键操作出现条件应仍由 kOneClickMinPlants 阈值驱动（存活株数）');
      expect(src.contains('PremiumGate'), isFalse,
          reason: '阶段 1 不接线门控点：花园页不应引用 PremiumGate');
      expect(src.contains('Entitlement'), isFalse,
          reason: '阶段 1 不接线门控点：花园页不应出现权益标识符');
    });

    test('家长报告页内容未被权益判定缠上', () {
      final String src = File(
        '$root/lib/presentation/parent/pages/parent_report_page.dart',
      ).readAsStringSync();
      expect(src.contains('PremiumGate'), isFalse,
          reason: '阶段 1 不接线门控点：报告页不应引用 PremiumGate');
      expect(src.contains('Entitlement'), isFalse,
          reason: '阶段 1 不接线门控点：报告页不应出现权益标识符');
      // 报告页核心内容仍在：专注报告服务 + 有效专注日口径。
      expect(src.contains('focusReportServiceProvider'), isTrue,
          reason: '报告页应仍走 focusReportServiceProvider（本地聚合）');
    });
  });
}
