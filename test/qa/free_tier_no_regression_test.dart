/// 免费零回归守卫测试（付费墙 · 阶段 1 收口 → 阶段 4 收紧后更新）。
///
/// 阶段 1 门控全放开，本测试钉「free == premium」。阶段 4 **刻意收紧 5 项**，
/// C80 再收紧 `titlePerks`（共 6 项），故守卫随之改写为两层：
///  1. **未收紧的能力**：free 与 premium 判定 / 额度仍必须等价且放行（免费功能不退化）；
///  2. **已收紧的能力**：其免费边界与买断边界必须**明确声明**（防手滑放回全开）。
///
/// 另加源码守卫：报告页门控本批**缓做**，报告页仍不得被权益判定缠上；孩子端花园页
/// 不得出现任何购买入口 / 价格。
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

/// 阶段 4 / C90 期 1 **已收紧**的能力点（其余免费能力必须与 premium 等价）。
/// C80：`titlePerks`（称号专属属性）加入收紧集 —— 本仓**第一个真实生效的布尔收紧键**。
/// C90 期 1：`multiChildProfile` 加入收紧集 —— free 1 / premium 3，只拦新增（C69）。
const Set<FeatureKey> _tightenedInPhase4 = <FeatureKey>{
  FeatureKey.oneClickCare,
  FeatureKey.gardenPotCapacity,
  FeatureKey.taskTemplateCount,
  FeatureKey.rewardTemplateCount,
  FeatureKey.deepReport,
  FeatureKey.titlePerks,
  FeatureKey.multiChildProfile,
};

void main() {
  final String root = _projectRoot();

  group('矩阵不变量：未收紧能力 free == premium 且全放开', () {
    test('每个「未收紧」能力点 free 与 premium 完全等价', () {
      final List<FeatureKey> open = FeatureKey.values
          .where((FeatureKey f) => !_tightenedInPhase4.contains(f))
          .toList();
      expect(open, isNotEmpty, reason: '应存在未收紧的免费能力点');
      for (final FeatureKey f in open) {
        expect(featureAllowedFor(f, EntitlementTier.free), isTrue,
            reason: '$f 未被阶段 4 收紧，免费必须放行（否则免费功能退化）');
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

    test('「已收紧」能力点的免费边界 = 声明值（防放回全开）', () {
      // 一键操作 / 深度报告 / C80 称号属性：free 关闭。
      expect(featureAllowedFor(FeatureKey.oneClickCare, EntitlementTier.free),
          isFalse);
      expect(featureAllowedFor(FeatureKey.deepReport, EntitlementTier.free),
          isFalse);
      expect(featureAllowedFor(FeatureKey.titlePerks, EntitlementTier.free),
          isFalse, reason: 'C80：free 不享 9 条称号专属属性（currentPerk → none）');
      // 花盆 / 任务 / 奖励：free 有额度上限，premium 更宽。
      expect(featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.free),
          kFreeGardenPotQuota);
      expect(featureQuotaFor(FeatureKey.taskTemplateCount, EntitlementTier.free),
          kFreeTaskQuota);
      expect(featureQuotaFor(FeatureKey.rewardTemplateCount, EntitlementTier.free),
          kFreeRewardQuota);
      // C90 期 1：孩子档案 free 1 / premium 3（只拦新增）。
      expect(featureQuotaFor(FeatureKey.multiChildProfile, EntitlementTier.free),
          kFreeChildProfileCount);
      expect(
          featureQuotaFor(FeatureKey.multiChildProfile, EntitlementTier.premium),
          kPremiumChildProfileCount);
      // 买断后一律更宽 / 放开。
      expect(
        featureQuotaFor(FeatureKey.gardenPotCapacity, EntitlementTier.premium),
        kPremiumGardenPotQuota,
      );
      expect(
        featureAllowedFor(FeatureKey.oneClickCare, EntitlementTier.premium),
        isTrue,
      );
    });
  });

  group('未开通态：PremiumGate 对「未收紧」能力原样放行', () {
    testWidgets('free 档 + 未收紧能力 → 展示 child 且不出现付费引导卡',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.free),
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
      expect(find.text('CHILD'), findsOneWidget,
          reason: '未收紧能力下 PremiumGate 必须放行');
      expect(find.byType(PremiumUpsellCard), findsNothing,
          reason: '未收紧能力不应出现付费引导');
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

    testWidgets('free 档 + 已收紧能力 → 显示付费引导（真正拦得住）',
        (WidgetTester tester) async {
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
      expect(find.text('CHILD'), findsNothing);
      expect(find.byType(PremiumUpsellCard), findsOneWidget);
    });
  });

  group('源码守卫：关键入口未被错误缠绕', () {
    test('报告段门控只经 focus_report_section 单点（旧独立页已删除）', () {
      // C87（2026-10-17）：孤儿页 `parent_report_page.dart` 已按玄参拍板删除。
      // 本用例原意是「本批缓做、报告页别被权益判定缠上」，该口径早被 C76 取代
      // （月/年/稳定性/热力图归 deepReport），故改写为两条**更硬**的反向断言：
      // ① 孤儿页不得复活；② 门控只能出现在报告段单点，且判定走矩阵。
      expect(
        File('$root/lib/presentation/parent/pages/parent_report_page.dart')
            .existsSync(),
        isFalse,
        reason: 'C87：孤儿页已删除，不得复活',
      );

      final String src = File(
        '$root/lib/presentation/parent/widgets/focus_report_section.dart',
      ).readAsStringSync();
      expect(src.contains('featureAllowedFor'), isTrue,
          reason: '报告段门控必须走矩阵单点 featureAllowedFor');
      // 报告段核心内容仍在：专注报告服务 + 有效专注日口径。
      expect(src.contains('focusReportServiceProvider'), isTrue,
          reason: '报告段应仍走 focusReportServiceProvider（本地聚合）');
    });

    test('孩子端花园页不出现购买入口 / 价格（门控只在家长端）', () {
      final String src = File(
        '$root/lib/presentation/child/pages/garden_page.dart',
      ).readAsStringSync();
      expect(src.contains('_oneClickUnlocked'), isTrue,
          reason: '一键 FAB 出现条件应叠加档位门控');
      expect(src.contains('kOneClickMinPlants'), isTrue,
          reason: '一键操作仍由 kOneClickMinPlants 阈值驱动（存活株数）');
      expect(src.contains('/parent/premium'), isFalse,
          reason: '孩子端不得出现购买页入口');
      expect(src.contains('buyLifetime'), isFalse,
          reason: '孩子端不得触发购买');
    });
  });
}
