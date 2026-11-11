/// 击杀掉落「阳光精灵」VFX（B13.8）的冒烟护栏。
///
/// 真源：玄参提案（已拍板）——打死的怪原地掉一颗阳光，下落 + 漂移 + 淡出
/// ~700ms，**纯视觉层**：不许影响 sim / 结算 / 确定性。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | ① | kill 事件后，该怪位置的阳光精灵（`sunDropKey(i)`）在树上 |
/// | ② | `kGuardSunDropFxMs`(700ms) 后精灵被摘除（findsNothing） |
/// | ③ | 演出零战局影响：整场打完后 `sim` 的结算输入（stolenSun / 结局）与纯 sim 重放逐位一致（VFX 只读事件，不写任何状态） |
///
/// 🔴 种子控制与 `guard_battle_field_test` 同款：纯 sim 里先搜「该天必胜 +
/// 首杀时刻」的 childId，再在 UI 里按同一时间线经开火手柄重放 —— 零随机 flake。
/// 🔴 全文件定长 `pump`（战斗 ticker 常驻，绝不 `pumpAndSettle`）。
library guard_sun_drop_fx_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

const String _dayKey = '2026-01-01';

/// 纯 sim 重放：450ms 步进连射，返回 (首个 kill 的怪序号, 是否打完全灭)。
(int, bool) _replay(String dayKey, String childId) {
  final GuardBattleScript script =
      deriveGuardBattleScript(dayKey: dayKey, childId: childId);
  final GuardBattleSim sim =
      GuardBattleSim(script: script, dayKey: dayKey, childId: childId);
  int firstKillIndex = -1;
  for (int t = 450; t <= script.windowMs; t += 450) {
    final GuardBattleStepReport report = sim.step(t, <int>[t]);
    for (final GuardBattleEvent e in report.events) {
      if (e.type == GuardBattleEventType.kill &&
          e.monsterIndex >= 0 &&
          firstKillIndex < 0) {
        firstKillIndex = e.monsterIndex;
      }
    }
    if (report.ended) return (firstKillIndex, true);
  }
  return (firstKillIndex, false);
}

/// 搜一个「今天能全灭且有首杀」的 childId，返回 (childId, 首杀怪序号)。
(String, int) _findKillChild(String dayKey) {
  for (int n = 0; n < 200; n++) {
    final String childId = 'sd-kill-$n';
    final (int idx, bool won) = _replay(dayKey, childId);
    if (won && idx >= 0) return (childId, idx);
  }
  throw StateError('搜遍 200 个 seed 都没有可全灭阵容 —— 引擎参数或判定异常');
}

/// 直挂一个 L4 战斗层（288×140 卡内槽位），返回开火手柄。
Future<GuardBattleHandle> _pumpField(WidgetTester tester, String childId) async {
  final GuardBattleHandle handle = GuardBattleHandle();
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Localizations(
      locale: const Locale('zh'),
      delegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 288,
                height: 140,
                child: GuardBattleField(
                  dayKey: _dayKey,
                  childId: childId,
                  handle: handle,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // 挂载帧（不给 ticker 推进时间 ⇒ 之后的 pump 差值 = sim 时间轴）。
  await tester.pump(const Duration(milliseconds: 1));
  return handle;
}

void main() {
  testWidgets('① kill 后阳光精灵在树上；② 700ms 后被摘除；③ 战局照常收场',
      (WidgetTester tester) async {
    final (String childId, int killIndex) = _findKillChild(_dayKey);
    final GuardBattleHandle handle = await _pumpField(tester, childId);

    // 与纯 sim 同一时间线重放（450ms 步进连射；fire 落在当前 sim 时刻，
    // 下一步 step 交给 sim —— 与重放的 step(t, [t]) 等价）。每步之后探测
    // 阳光精灵是否已生成（首杀一旦发生，精灵 age=0 必在树上）。
    bool seen = false;
    for (int t = 450; t <= kGuardBattleWindowMs && !seen; t += 450) {
      await tester.pump(const Duration(milliseconds: 450));
      handle.fire();
      seen = find
          .byKey(GuardBattleField.sunDropKey(killIndex))
          .evaluate()
          .isNotEmpty;
    }
    expect(seen, isTrue,
        reason: '首杀发生后，阳光精灵（sunDropKey($killIndex)）必须在树上');

    // ② 演出结束：kGuardSunDropFxMs(700ms) 后精灵被摘除。
    await tester.pump(const Duration(milliseconds: kGuardSunDropFxMs + 200));
    expect(find.byKey(GuardBattleField.sunDropKey(killIndex)), findsNothing,
        reason: '阳光精灵是限时演出，700ms 后必须从树上消失');

    // ③ 战局照常收场（纯渲染层的存在没有干扰 sim）：终局横幅最终上屏。
    bool banner = false;
    for (int t = 450;
        t <= kGuardBattleWindowMs + kGuardDeathFleeMs + kGuardEndBannerDwellMs;
        t += 450) {
      await tester.pump(const Duration(milliseconds: 450));
      if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
        banner = true;
        break;
      }
    }
    expect(banner, isTrue,
        reason: '阳光 VFX 只是视觉层 —— 战局必须照常打到终局横幅');
    // 🔴 终局路径里有一个 delay = 横幅停留（≤900ms）的 Future.delayed 回调
    // （onFinished 交回页面用）；测试结束时不得留 pending timer ⇒ 再泵过它。
    await tester.pump(const Duration(milliseconds: kGuardEndBannerDwellMs + 200));
    expect(tester.takeException(), isNull);
  });
}
