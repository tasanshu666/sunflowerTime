/// QA 独立差分复验 + 受控变异锚点（守卫大招 T01–T05）。
///
/// 本文件**独立于工程师新增的 4 个测试**，由 QA 独立编写，专治「假绿」：
///  · 【头号陷阱】门控真实行为必须在**带 ProviderScope、可控制 entitlementProvider
///    档位**的宿主内验证（裸 MaterialApp 宿主会恒走免费/no-op 分支而假绿）。
///    这里分别注入 free / premium，直接驱动 guardUltimateUnlocked / onGuardUltimateTap，
///    观测「弹买断引导 / 执行 onAllowed / 0 格轻提示」三种真实分支。
///  · D-2 零掉落锚点：castUltimate 只发 ultimateKill/ultimateCast，零 kill/theft/dodge。
///    （受控变异 ultimateKill→kill 时此组必转红。）
///  · 累计能量幂等 / 满 2 格归零 / fillPercent 独立写死期望值锚点。
///
/// 本文件所有期望值独立写死，绝不复用被测函数自证。
library qa_guard_ultimate_differential_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/guard_ultimate_energy_prefs_store.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/domain/services/guard_ultimate_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show ChildConfirmCard;
import 'package:sunflower_time/presentation/shared/premium_gate.dart'
    show guardUltimateUnlocked, onGuardUltimateTap;
import 'package:sunflower_time/presentation/shared/brief_notice.dart'
    show hideBriefNotice;

// ───────────────────────────────────────────────────────────────────────────
// 门控真值宿主：必须挂 ProviderScope，且档位可注入（防假绿）。
// ───────────────────────────────────────────────────────────────────────────

/// 一个位于 ProviderScope / MaterialApp / Navigator 之内的最小宿主。
/// 取它的 Element 作为 BuildContext 交给门控 helper —— 这样
/// `ProviderScope.containerOf(context)` 能拿到真实容器，**不是**裸 widget 宿主。
class _GateHarness extends StatelessWidget {
  const _GateHarness();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<BuildContext> _pumpGateHost(
  WidgetTester tester, {
  required Entitlement entitlement,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        entitlementProvider.overrideWith((Ref ref) => entitlement),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: _GateHarness())),
      ),
    ),
  );
  return tester.element(find.byType(_GateHarness));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // A 组 · 门控真实行为（ProviderScope 宿主，free / premium 双档注入）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-A · 门控真实行为（带 ProviderScope，防裸宿主假绿）', () {
    testWidgets('guardUltimateUnlocked：免费档 = false（真实读容器）',
        (WidgetTester tester) async {
      final BuildContext freeCtx =
          await _pumpGateHost(tester, entitlement: Entitlement.free);
      expect(guardUltimateUnlocked(freeCtx), isFalse,
          reason: '免费档必须锁定（口径 11 / P0-08）');
    });

    testWidgets('guardUltimateUnlocked：买断档 = true（真实读容器）',
        (WidgetTester tester) async {
      final BuildContext premCtx = await _pumpGateHost(
        tester,
        entitlement: Entitlement.lifetime(),
      );
      expect(guardUltimateUnlocked(premCtx), isTrue,
          reason: '买断档必须放行');
    });

    testWidgets('A7 免费档 + 有能量点战士 → 弹买断引导，能量不被消耗（onAllowed 不跑）',
        (WidgetTester tester) async {
      final BuildContext ctx =
          await _pumpGateHost(tester, entitlement: Entitlement.free);

      int allowedCalls = 0;
      onGuardUltimateTap(ctx, hasEnergy: true, onAllowed: () => allowedCalls++);
      await tester.pumpAndSettle();

      expect(allowedCalls, 0, reason: '免费档绝不执行释放回调');
      expect(find.byType(ChildConfirmCard), findsOneWidget,
          reason: '必须弹买断引导卡（不静默、不无响应，口径 12 / P0-09②）');
      expect(
        find.text(AppLocalizationsZh().premium_gate_upsell_dialog_title),
        findsOneWidget,
        reason: '弹的是升级解锁引导',
      );
    });

    testWidgets('A5/P0-04 买断档 + 有能量点战士 → 直接执行 onAllowed（不弹引导）',
        (WidgetTester tester) async {
      final BuildContext ctx = await _pumpGateHost(
        tester,
        entitlement: Entitlement.lifetime(),
      );

      int allowedCalls = 0;
      onGuardUltimateTap(ctx, hasEnergy: true, onAllowed: () => allowedCalls++);
      await tester.pumpAndSettle();

      expect(allowedCalls, 1, reason: '买断且有能量 → 执行一次释放');
      expect(find.byType(ChildConfirmCard), findsNothing,
          reason: '买断档不应弹买断引导');
    });

    testWidgets('B2 买断档 + 0 格 → 1s 淡出轻提示（不释放、不静默）',
        (WidgetTester tester) async {
      final BuildContext ctx = await _pumpGateHost(
        tester,
        entitlement: Entitlement.lifetime(),
      );

      int allowedCalls = 0;
      onGuardUltimateTap(ctx, hasEnergy: false, onAllowed: () => allowedCalls++);
      // showBriefNotice 保持 1s + 淡出 180ms：这里只 pump 短时长，不 pumpAndSettle。
      await tester.pump(const Duration(milliseconds: 250));

      expect(allowedCalls, 0, reason: '0 格不触发释放');
      expect(
        find.text(AppLocalizationsZh().guard_ultimate_empty_hint_light),
        findsOneWidget,
        reason: '0 格给出 i18n 轻提示「请专注去获得能量吧」（玄参 2026-11-20）',
      );
      hideBriefNotice(); // 清理浮层，避免污染后续用例
      await tester.pumpAndSettle();
    });

    testWidgets('A8 买断即兑现：免费期已攒 2 格 → 买断后立即可用，能量原值不动',
        (WidgetTester tester) async {
      final BuildContext ctx =
          await _pumpGateHost(tester, entitlement: Entitlement.free);

      // 能量实体（2 格）与权益物理分离：买断只改档位，能量数值不动。
      final UltimateEnergy energyBefore = credit(UltimateEnergy.empty, 60);
      expect(energyBefore.filledCells, 2);
      expect(guardUltimateUnlocked(ctx), isFalse, reason: '买断前锁定');

      int allowedCalls = 0;
      onGuardUltimateTap(
        ctx,
        hasEnergy: energyBefore.filledCells > 0,
        onAllowed: () => allowedCalls++,
      );
      await tester.pumpAndSettle();
      expect(allowedCalls, 0, reason: '买断前点战士只弹引导');

      // 买断：仅切 entitlementProvider 档位，不写任何能量状态。
      ProviderScope.containerOf(ctx, listen: false)
          .read(entitlementProvider.notifier)
          .state = Entitlement.lifetime();
      await tester.pumpAndSettle();

      expect(guardUltimateUnlocked(ctx), isTrue, reason: '买断后立即解锁');
      onGuardUltimateTap(
        ctx,
        hasEnergy: energyBefore.filledCells > 0,
        onAllowed: () => allowedCalls++,
      );
      await tester.pumpAndSettle();
      expect(allowedCalls, 1, reason: '已攒能量买断后立即可释放，无需重攒');
      expect(energyBefore.filledCells, 2, reason: '门控切换不改能量持久值');
    });

    testWidgets('A9 安全回退：读不到票据的默认档（Entitlement.free）按免费处理',
        (WidgetTester tester) async {
      final BuildContext ctx = await _pumpGateHost(
        tester,
        entitlement: Entitlement.free,
      );
      // 票据读不到 ⇒ Entitlement.free ⇒ 安全回退免费档，不误放行。
      expect(Entitlement.free.tier, EntitlementTier.free);
      expect(guardUltimateUnlocked(ctx), isFalse);

      int allowedCalls = 0;
      onGuardUltimateTap(ctx, hasEnergy: true, onAllowed: () => allowedCalls++);
      await tester.pumpAndSettle();
      expect(allowedCalls, 0, reason: '安全回退：不放行、走引导');
      expect(find.byType(ChildConfirmCard), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B 组 · D-2 零掉落锚点（受控变异 ultimateKill→kill 必转红）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-B · castUltimate 零掉落事件契约', () {
    GuardBattleScript buildScript({required int count, required int dodgeCount}) {
      return GuardBattleScript(
        windowMs: 30000,
        monsters: <GuardBattleMonsterSpec>[
          for (int i = 0; i < count; i++)
            GuardBattleMonsterSpec(
              index: i,
              kind: GuardBattleMonsterKind.m1,
              spawnMs: 0,
              speedPtPerSec: 15,
              dodgeProb: i < dodgeCount ? 1.0 : 0.0,
              hitsToKill: 99,
              steal: 1,
              laneYPt: 100 + i * 4,
              wobbleAmpPt: 0,
              wobbleFreqHz: 0,
              wobblePhaseRad: 0,
            ),
        ],
      );
    }

    test('5 怪含必闪怪：只发 5 ultimateKill + 1 ultimateCast，零 kill 事件', () {
      final GuardBattleSim sim = GuardBattleSim(
        script: buildScript(count: 5, dodgeCount: 2),
        dayKey: '2026-11-20',
        childId: 'qa-ult-kid',
      );
      sim.step(1000, <int>[]);
      final List<GuardBattleEvent> events = <GuardBattleEvent>[];
      sim.castUltimate(1000, events);

      expect(sim.ultimateKillCount, 5);
      expect(
        events
            .where((GuardBattleEvent e) =>
                e.type == GuardBattleEventType.ultimateKill)
            .length,
        5,
      );
      expect(
        events
            .where((GuardBattleEvent e) =>
                e.type == GuardBattleEventType.ultimateCast)
            .length,
        1,
      );
      // 🔴 核心锚点：零 kill ⇒ 表现层 _collectSunDropFx 零触发 ⇒ 阳光/宝箱 +0。
      expect(
        events.any((GuardBattleEvent e) =>
            e.type == GuardBattleEventType.kill),
        isFalse,
        reason: '大招若发 kill 会误触发阳光 VFX（口径 8 / A5）',
      );
      expect(
        events.any((GuardBattleEvent e) =>
            e.type == GuardBattleEventType.dodge),
        isFalse,
        reason: '无视闪避：不走子弹/闪避路径',
      );
      expect(
        sim.snapshot().monsters
            .where((GuardBattleMonsterSnapshot m) => m.phaseId == 'dead')
            .length,
        5,
        reason: '5 只全置 dead（死亡演出仍消费 ultimateKill）',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C 组 · 累计能量状态机锚点（幂等 / 溢出归零 / fillPercent 独立写死）
  // ══════════════════════════════════════════════════════════════════════
  group('QA-C · 状态机与幂等锚点', () {
    test('同一 sessionId 重复 credit 只计一次（幂等；变异去重要转红）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final GuardUltimateService service = GuardUltimateService(
        store: GuardUltimateEnergyPrefsStore(sp),
        childId: () => 'qa-kid',
      );
      expect(
        await service.creditFocus(
            sessionId: 'dup', childId: 'qa-kid', actualFocusMin: 29),
        isTrue,
      );
      expect(
        await service.creditFocus(
            sessionId: 'dup', childId: 'qa-kid', actualFocusMin: 29),
        isFalse,
        reason: '重复 sessionId 必须被去重挡下',
      );
      final UltimateEnergy e = await service.read();
      expect(e.fractionMin, 29, reason: '零头没被重复累加');
      expect(e.totalFocusMin, 29.0);
    });

    test('满 2 格那一刻 fractionMin 强制归 0（变异保留溢出要转红）', () {
      const UltimateEnergy base =
          UltimateEnergy(filledCells: 1, fractionMin: 29);
      final UltimateEnergy e = credit(base, 31);
      expect(e.filledCells, 2);
      expect(e.fractionMin, 0, reason: '满 2 格丢弃溢出、零头归零（B1）');
    });

    test('fillPercent 期望值独立写死（变异公式要转红）', () {
      expect(fillPercent(credit(UltimateEnergy.empty, 29), 0), 96.7);
      expect(fillPercent(credit(UltimateEnergy.empty, 15), 0), 50.0);
      expect(fillPercent(credit(UltimateEnergy.empty, 1), 0), 3.3);
      expect(fillPercent(UltimateEnergy.empty, 0), 0.0);
      expect(fillPercent(credit(UltimateEnergy.empty, 30), 0), 100.0);
    });
  });
}
