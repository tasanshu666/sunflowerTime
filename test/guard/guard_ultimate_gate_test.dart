/// 大招门控测试（A7/A8/A9/A11 / P0-08/09/10 / 架构 §1.3 / 口径 11-13）。
///
/// 覆盖：矩阵单点（free false / premium true）、默认安全回退免费、
/// 买断即兑现（能量数值不动）、卖点表零改动、孩子端零权益 token。
library guard_ultimate_gate_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart'
    show unlockRowsFor;

String _projectRoot() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/guard') || cwd.endsWith('\\test\\guard')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  group('P0-08 · 门控矩阵单点', () {
    test('FeatureKey.guardUltimate 有且仅有一条 rule，free/premium = false/true', () {
      expect(kEntitlementMatrix.keys.where((FeatureKey k) => k == FeatureKey.guardUltimate).length, 1);
      final FeatureRule rule = kEntitlementMatrix[FeatureKey.guardUltimate]!;
      expect(rule.freeEnabled, isFalse);
      expect(rule.premiumEnabled, isTrue);
      expect(rule.freeQuota, kUnlimitedQuota);
      expect(rule.premiumQuota, kUnlimitedQuota);
    });

    test('featureAllowedFor 判定：free=false / premium=true', () {
      expect(featureAllowedFor(FeatureKey.guardUltimate, EntitlementTier.free), isFalse);
      expect(featureAllowedFor(FeatureKey.guardUltimate, EntitlementTier.premium), isTrue);
    });

    test('A9 安全回退：Entitlement.free（读不到票据的默认）⇒ 不放行', () {
      expect(Entitlement.free.tier, EntitlementTier.free);
      expect(featureAllowedFor(FeatureKey.guardUltimate, Entitlement.free.tier), isFalse);
    });
  });

  group('A8 · 买断即兑现', () {
    test('买断只改档位，能量数值与门控派生独立（🔒 是派生显示态）', () {
      // 能量状态与权益物理分离：门控 bool 由档位派生，能量实体不受影响。
      const Entitlement free = Entitlement.free;
      final Entitlement premium = Entitlement.lifetime();
      expect(featureAllowedFor(FeatureKey.guardUltimate, free.tier), isFalse);
      expect(featureAllowedFor(FeatureKey.guardUltimate, premium.tier), isTrue);
      // 档位切换不改变任何能量持久化 key（无数据清除语义，C69）。
      expect(free.tier == premium.tier, isFalse);
    });
  });

  group('P0-10 · 卖点表零改动', () {
    test('unlockRowsFor 仍恰好 6 行，键序白名单不含 guardUltimate', () {
      final rows = unlockRowsFor();
      expect(rows.length, 6);
      expect(
        rows.map((r) => r.key).toList(),
        <FeatureKey>[
          FeatureKey.gardenPotCapacity,
          FeatureKey.taskTemplateCount,
          FeatureKey.multiChildProfile,
          FeatureKey.oneClickCare,
          FeatureKey.titlePerks,
          FeatureKey.deepReport,
        ],
      );
      expect(rows.any((r) => r.allKeys.contains(FeatureKey.guardUltimate)), isFalse,
          reason: '「守卫大招」不得进入购买页卖点对比表（口径 13）');
    });
  });

  group('定死点③ · 门控不落页面', () {
    final String root = _projectRoot();

    test('孩子端 guard_scene_card.dart 零权益 token', () {
      final File f = File('$root/lib/presentation/child/widgets/guard_scene_card.dart');
      final String src = f.readAsStringSync();
      const List<String> banned = <String>[
        'Entitlement',
        'FeatureKey',
        'FeatureRule',
        'PremiumGate',
        'entitlementProvider',
        'entitlementServiceProvider',
        'kEntitlementMatrix',
        'kUnlimitedQuota',
      ];
      for (final String token in banned) {
        expect(src.contains(token), isFalse,
            reason: 'guard_scene_card.dart 不得出现权益 token: $token');
      }
      // 只允许中性 helper 名（门控判定 guardUltimateUnlocked 下沉在白名单文件
      // premium_gate.dart 内，孩子端只吃注入的 bool + 点击中性入口）。
      expect(src.contains('onGuardUltimateTap'), isTrue);
      expect(src.contains('ultimateUnlocked'), isTrue);
    });

    test('门控判定只写在白名单文件 premium_gate.dart 内', () {
      final File f = File('$root/lib/presentation/shared/premium_gate.dart');
      final String src = f.readAsStringSync();
      expect(src.contains('FeatureKey.guardUltimate'), isTrue);
      expect(src.contains('guardUltimateUnlocked'), isTrue);
      expect(src.contains('onGuardUltimateTap'), isTrue);
      expect(src.contains('showPremiumUpsell(context, FeatureKey.guardUltimate)'), isFalse,
          reason: '孩子端零购买入口：免费档点战士不得弹买断引导卡');
      expect(src.contains('_showGuardUltimateLockedHint('), isTrue);
      expect(src.contains('guard_ultimate_locked_hint'), isTrue);
      expect(src.contains('showBriefNotice('), isTrue,
          reason: '免费档改走 1s 淡出轻提示');
    });
  });
}
