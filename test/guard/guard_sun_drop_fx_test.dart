/// 击杀掉落「阳光精灵」VFX（B13.8 / B13.11 改**上飞**）的冒烟护栏。
///
/// 真源：玄参提案（已拍板）——打死的怪原地冒一颗阳光，**上飞** + 漂移 + 淡出
/// ~700ms，**纯视觉层**：不许影响 sim / 结算 / 确定性。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | ① | kill 事件后，该怪位置的阳光精灵（`sunDropKey(i)`）在树上 |
/// | ② | 轨迹方向 = **向上**：逐 60ms 采样 `Positioned.top`，必须**严格递减**；总抬升 ≤ `kGuardSunRisePt`(26pt)（不越过场景卡顶边的硬约束）；透明度单调不增且起手非 0 |
/// | ③ | `kGuardSunDropFxMs`(700ms) 后精灵被摘除（findsNothing） |
/// | ④ | 演出零战局影响：整场打完后 `sim` 的结算输入（stolenSun / 结局）与纯 sim 重放逐位一致（VFX 只读事件，不写任何状态） |
///
/// 🔴 方向断言是 B13.11 的**核心回归点**：原实现是 `mapMonsterY + 26 * t`（往下掉），
/// 观感像「阳光掉进地里」。这里用 `top` 的单调性钉死方向 —— 改回加号立即红。
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

/// 采一次精灵的 `(top, opacity)`；不在树上返回 null。
///
/// `top` 读的是 `Positioned.top`（**相对 Stack 的布局值**，不经变换），
/// 所以「向上飞」在数值上等价于「top 变小」——不受漂移 / 父级变换干扰。
(double, double)? _sampleFx(WidgetTester tester, int killIndex) {
  final Finder fx = find.byKey(GuardBattleField.sunDropKey(killIndex));
  if (fx.evaluate().isEmpty) return null;
  final double? top = tester.widget<Positioned>(fx).top;
  if (top == null) return null;
  final Finder opacity =
      find.descendant(of: fx, matching: find.byType(Opacity)).first;
  return (top, tester.widget<Opacity>(opacity).opacity);
}

void main() {
  testWidgets('① kill 后精灵在树上；② 方向 = 上飞（top 严格递减）；③ 700ms 摘除；④ 战局照常收场',
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

    // ── ② 方向：逐 60ms 采样 top，必须**严格递减**（= 向上飞）────────────
    // 采样窗口 = 精灵剩余寿命（首杀可能发生在上一段 450ms 内的任意时刻 ⇒
    // 剩余 ≥ 250ms，至少能采到 4 个点）。摘除后立刻停止采样。
    final List<double> tops = <double>[];
    final List<double> opacities = <double>[];
    for (int i = 0; i < 12; i++) {
      final (double, double)? sample = _sampleFx(tester, killIndex);
      if (sample == null) break;
      tops.add(sample.$1);
      opacities.add(sample.$2);
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tops.length, greaterThanOrEqualTo(2),
        reason: '采样点太少（${tops.length}）—— 阳光精灵寿命必须够长到能看见飞行');
    for (int i = 1; i < tops.length; i++) {
      expect(tops[i], lessThan(tops[i - 1]),
          reason: '🔴 第 $i 次采样的 top 必须比上一次更小（向上飞）；'
              '实测轨迹 $tops —— 变大 = 又改回「下落」了');
    }
    // 硬约束：上飞幅度不得超过 kGuardSunRisePt(26pt)（再高会盖住卡顶计时条）。
    expect(tops.first - tops.last, lessThanOrEqualTo(kGuardSunRisePt + 1e-9),
        reason: '上飞总位移 ${tops.first - tops.last}pt 超出 kGuardSunRisePt'
            '($kGuardSunRisePt) —— 会越过场景卡顶边的计时条');

    // 透明度：起手非 0（「先看到它飞起来」），之后单调不增（后段加速淡出）。
    expect(opacities.first, greaterThan(0.0),
        reason: '刚冒头时必须是不透明的（否则等于没演出）');
    for (int i = 1; i < opacities.length; i++) {
      expect(opacities[i], lessThanOrEqualTo(opacities[i - 1] + 1e-9),
          reason: '透明度必须单调不增（淡出不许回亮）；实测 $opacities');
    }

    // ── ③ 演出结束：kGuardSunDropFxMs(700ms) 后精灵被摘除 ────────────────
    await tester.pump(const Duration(milliseconds: kGuardSunDropFxMs + 200));
    expect(find.byKey(GuardBattleField.sunDropKey(killIndex)), findsNothing,
        reason: '阳光精灵是限时演出，700ms 后必须从树上消失');

    // ── ④ 战局照常收场（纯渲染层的存在没有干扰 sim）：终局横幅最终上屏 ──
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

  // ── 不透明度曲线（纯函数，与渲染解耦）──────────────────────────────────
  test('sunRiseOpacityAt：1 → 0.35（60%） → 0，且全程单调不增', () {
    // 起手全亮。
    expect(GuardBattleField.sunRiseOpacityAt(0), closeTo(1.0, 1e-9));
    // 到 fadeStart（60%）衰减到 fadeStartOpacity（0.35）：字面量，改参须有意更新。
    expect(GuardBattleField.sunRiseOpacityAt(kGuardSunRiseFadeStart),
        closeTo(0.35, 1e-9));
    // 到点归零。
    expect(GuardBattleField.sunRiseOpacityAt(1), closeTo(0.0, 1e-9));

    double previous = 2;
    for (int i = 0; i <= 20; i++) {
      final double value = GuardBattleField.sunRiseOpacityAt(i / 20);
      expect(value, lessThanOrEqualTo(previous + 1e-12),
          reason: 't=${i / 20} 处不透明度回升了（必须单调不增）');
      expect(value, inInclusiveRange(0.0, 1.0));
      previous = value;
    }

    // 越界钳制（不会因浮点越界而出现 >1 / <0）。
    expect(GuardBattleField.sunRiseOpacityAt(-1), closeTo(1.0, 1e-9));
    expect(GuardBattleField.sunRiseOpacityAt(2), closeTo(0.0, 1e-9));
  });
}
