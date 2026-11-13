/// 受击「闪动」+ 子弹「拖尾」演出护栏（B13.20b，玄参 2026-11-13）。
///
/// 真源：玄参真机验收反馈 ——「阳光战士发射的子弹打到小怪物后，现在只有
/// 一个音效，可不可以给小怪物也做一个闪动的效果呢？发射的子弹也做一个
/// 拖尾的效果。」两者皆为**纯渲染层**演出：不许影响 sim / 结算 / 确定性。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | ① | hit / kill 事件后，该怪本体闪动层（`hitFlashKey(i)`）透明度变深（< 0.9）、期间回亮（≥ 0.9），`kGuardHitFlashMs`(180ms) 后**回到恒 1.0** |
/// | ② | 拖尾：子弹在飞时 `bulletTrailKey(idx, 0..2)` 三颗圆点在树；尺寸**逐颗变小**、不透明度逐颗变淡；整体位于子弹**运动反方向**一侧 |
/// | ③ | 子弹出膛（命中 / 闪避 / 落空）后，本体与全部拖尾圆点一起从树上消失 |
/// | ④ | 演出零战局影响：战斗照常打到终局横幅（VFX 只读事件，不写任何状态） |
/// | ⑤ | 纯函数 `hitFlashAlphaAt`：起手 = 1 − depth(0.25)、t=1 回到 1.0、全程 ∈ [0.25, 1]、中段明暗往返的字面锚点 |
/// | ⑥ | 拖尾常量表与点数等长（改点数漏改表 ⇒ 立即红） |
/// | ⑦ | 🔴 **B13.20c 回归**：闪动层**恒挂树**（开火前就在、opacity = 1.0）——旧实现「有 hit 才包 Opacity」翻转树结构 ⇒ `_GuardSequence` State 被销毁重建 ⇒ FutureBuilder waiting 帧画出兜底**绿色方块**（玄参实机「方块闪烁不是怪物闪烁」）；恒挂树 = 结构永不翻转 |
/// | ⑧ | 🔴 **B13.20d 受击击退**（玄参：「音效、闪烁、被击退一小段距离」）：纯函数 `knockbackOffsetAt` 锚点（0→0 / 0.5→1 / 1→0、越界钳位、前后半镜像）；hit 后怪 slot `left` 出现**正增长步**（逆行走方向 = 向右弹开，行走时 left 本应单调减小），`kGuardKnockbackMs`(180ms) 后回位（不再正增长）；**击灭怪不击退**（转入逃跑演出） |
///
/// 🔴 全文件定长 `pump`（战斗 ticker 常驻，绝不 `pumpAndSettle`）；结束前把
/// 终局横幅的 `Future.delayed` 泵过（不留 pending timer，与 sun_drop 同款）。
library guard_hit_flash_and_trail_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

const String _dayKey = '2026-01-01';

/// 直挂一个 L4 战斗层（288×140 卡内槽位），返回开火手柄。
Future<GuardBattleHandle> _pumpField(WidgetTester tester) async {
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
                  childId: 'hf-trail-0',
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

/// 终局收尾：泵到横幅上屏 + 横幅停留回调播完（不留 pending timer）。
Future<void> _pumpToBattleEnd(WidgetTester tester) async {
  for (int t = 0; t <= kGuardBattleWindowMs + 500; t += 450) {
    await tester.pump(const Duration(milliseconds: 450));
    if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pump(
      const Duration(milliseconds: kGuardEndBannerDwellMs + kGuardDeathFleeMs));
}

void main() {
  /// 第 [i] 只怪闪动层的当前透明度（B13.20c 恒挂树 ⇒ key 永在；层不在 = 1.0）。
  double flashOpacityOf(WidgetTester tester, int i) {
    final Finder f = find.byKey(GuardBattleField.hitFlashKey(i));
    if (f.evaluate().isEmpty) return 1.0;
    return tester.widget<Opacity>(f).opacity;
  }

  testWidgets('① hit/kill 后怪本体闪动：起手深 → 回亮 → 180ms 回稳恒 1.0；④ 战局照常收场',
      (WidgetTester tester) async {
    final GuardBattleHandle handle = await _pumpField(tester);

    // 🔴 B13.20c：闪动层恒挂树 —— 开火前就必须在，且透明度恒 1.0。
    expect(find.byKey(GuardBattleField.hitFlashKey(0)), findsOneWidget,
        reason: '闪动层恒挂树（结构永不翻转）——这是「方块闪烁」bug 的结构回归护栏');
    expect(flashOpacityOf(tester, 0), 1.0, reason: '开火前不该闪');

    // 每 450ms 开火一次；弹达窗口（≤ ~250ms）内 45ms 步进探测「变暗」。
    bool seen = false;
    int flashMonster = -1;
    outer:
    for (int shot = 0; shot < 40 && !seen; shot++) {
      await tester.pump(const Duration(milliseconds: 450));
      handle.fire();
      for (int k = 0; k < 10; k++) {
        await tester.pump(const Duration(milliseconds: 45));
        if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
          break outer;
        }
        for (int i = 0; i < 5; i++) {
          if (flashOpacityOf(tester, i) < 1.0) {
            seen = true;
            flashMonster = i;
            break outer;
          }
        }
      }
    }
    expect(seen, isTrue,
        reason: '开火连射必中（自瞄 + 闪避是小概率）⇒ hit/kill 后闪动必须变暗');

    // 曲线：检测时刻 age ≤ 45ms ⇒ 起手段必然深（< 0.9）；随后的明暗往返里
    // 必须回亮到 ≥ 0.9（= 「闪动」而不是「变暗定格」）。
    final List<double> alphas = <double>[];
    for (int k = 0; k < 16; k++) {
      alphas.add(flashOpacityOf(tester, flashMonster));
      await tester.pump(const Duration(milliseconds: 15));
    }
    expect(alphas, isNotEmpty);
    expect(alphas.reduce(minOf), lessThan(0.9),
        reason: '闪动必须有「变暗」的深谷（起手段 1 − 0.75 = 0.25 附近）；实测 $alphas');
    expect(alphas.reduce(maxOf), greaterThanOrEqualTo(0.9),
        reason: '闪动必须回亮（往复明暗），不能一路暗下去；实测 $alphas');

    // kGuardHitFlashMs(180ms) 后回稳：透明度**恒 1.0**（层仍在树、结构不翻转），
    // 怪本体仍在（行走或逃跑中）。
    await tester.pump(const Duration(milliseconds: kGuardHitFlashMs + 120));
    expect(flashOpacityOf(tester, flashMonster), 1.0,
        reason: '闪动是限时演出，180ms 后必须回稳到恒 1.0（B13.20c：层恒挂树）');
    expect(find.byKey(GuardBattleField.monsterKey(flashMonster)), findsOneWidget,
        reason: '闪层只是怪本体上的一层 Opacity —— 怪不许跟着消失');

    // ── ④ 演出零战局影响：战斗照常打到终局横幅 ──────────────────────────
    await _pumpToBattleEnd(tester);
    expect(find.byKey(GuardBattleField.bannerKey), findsOneWidget,
        reason: '闪动/拖尾只是视觉层 —— 战局必须照常打到终局横幅');
    expect(tester.takeException(), isNull);
  });

  testWidgets('②③ 子弹拖尾：三颗渐小渐淡圆点在运动反方向一侧；子弹离场拖尾同摘',
      (WidgetTester tester) async {
    final GuardBattleHandle handle = await _pumpField(tester);

    await tester.pump(const Duration(milliseconds: 450));
    handle.fire();
    // 30ms 步进直到首颗子弹（index = 0）上树。
    for (int k = 0; k < 12; k++) {
      if (find.byKey(GuardBattleField.bulletKey(0)).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(GuardBattleField.bulletKey(0)), findsOneWidget,
        reason: '开火被受理后子弹必须上屏');

    // 方向采样：再泵 30ms 取子弹 left 差分（>0 = 向右飞）。
    final double left1 =
        tester.widget<Positioned>(find.byKey(GuardBattleField.bulletKey(0)))
            .left!;
    await tester.pump(const Duration(milliseconds: 30));
    final Finder bulletNow = find.byKey(GuardBattleField.bulletKey(0));
    expect(bulletNow, findsOneWidget,
        reason: '弹速 300pt/s、行程 ≥56pt ⇒ 30ms 后必然还在飞（flaky 防线）');
    final double left2 = tester.widget<Positioned>(bulletNow).left!;
    final bool movingRight = left2 > left1;

    // 三颗拖尾圆点：在树、尺寸逐颗变小、透明度逐颗变淡、整体在运动反方向一侧。
    double prevSize = double.infinity;
    double prevOpacity = double.infinity;
    final double bulletLeft = left2;
    for (int dot = 0; dot < kGuardBulletTrailDots; dot++) {
      final Finder dotFinder =
          find.byKey(GuardBattleField.bulletTrailKey(0, dot));
      expect(dotFinder, findsOneWidget, reason: '拖尾第 $dot 颗圆点必须在树');
      final Positioned p = tester.widget<Positioned>(dotFinder);
      expect(p.width!, lessThan(prevSize),
          reason: '拖尾必须越远越小；实测第 $dot 颗 ${p.width}（前一颗 $prevSize）');
      final double opacity = tester
          .widget<Opacity>(
              find.descendant(of: dotFinder, matching: find.byType(Opacity)).first)
          .opacity;
      expect(opacity, kGuardBulletTrailDotOpacities[dot],
          reason: '第 $dot 颗透明度必须取常量表（字面量钉死）');
      expect(opacity, lessThan(prevOpacity),
          reason: '拖尾必须越远越淡；实测第 $dot 颗 $opacity（前一颗 $prevOpacity）');
      if (movingRight) {
        expect(p.left! + p.width!, lessThan(bulletLeft),
            reason: '子弹向右飞 ⇒ 拖尾整体在其**左侧**（尾巴 = 运动反方向）');
      } else {
        expect(p.left!, greaterThan(bulletLeft + 0.0),
            reason: '子弹向左飞 ⇒ 拖尾整体在其**右侧**');
      }
      prevSize = p.width!;
      prevOpacity = opacity;
    }

    // ── ③ 子弹出膛（命中 / 闪避 / 落空）后：本体 + 全部拖尾一起消失 ────────
    for (int k = 0; k < 30; k++) {
      if (find.byKey(GuardBattleField.bulletKey(0)).evaluate().isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(GuardBattleField.bulletKey(0)), findsNothing,
        reason: '子弹必然在 ~600ms 内出膛（弹速 300pt/s）');
    for (int dot = 0; dot < kGuardBulletTrailDots; dot++) {
      expect(find.byKey(GuardBattleField.bulletTrailKey(0, dot)), findsNothing,
          reason: '拖尾随子弹同生命周期 —— 本体消失后第 $dot 颗不许残留');
    }
    expect(tester.takeException(), isNull);
  });

  // ── ⑤ 不透明度曲线（纯函数，与渲染解耦）────────────────────────────────
  test('hitFlashAlphaAt：起手 0.25 → 往复明暗 → t=1 恰好回 1.0，全程 ∈ [0.25, 1]', () {
    // 起手最深（被打中的一瞬立刻变暗）：1 − 0.75 = 0.25（字面量，改参须有意更新）。
    expect(GuardBattleField.hitFlashAlphaAt(0), closeTo(0.25, 1e-9));
    // 包络保证结束时恰好回亮（无收尾跳变）。
    expect(GuardBattleField.hitFlashAlphaAt(1), closeTo(1.0, 1e-9));
    // 中段字面锚点：t = 1/6 / 1/2 / 5/6 是三个「全亮」谷点（cos = −1）。
    expect(GuardBattleField.hitFlashAlphaAt(1 / 6), closeTo(1.0, 1e-9));
    expect(GuardBattleField.hitFlashAlphaAt(1 / 2), closeTo(1.0, 1e-9));
    expect(GuardBattleField.hitFlashAlphaAt(5 / 6), closeTo(1.0, 1e-9));
    // t = 1/3 / 2/3 是后两个「最深」峰点：1 − 0.75 × (1 − t)。
    expect(GuardBattleField.hitFlashAlphaAt(1 / 3), closeTo(1 - 0.75 * 2 / 3, 1e-9));
    expect(GuardBattleField.hitFlashAlphaAt(2 / 3), closeTo(1 - 0.75 * 1 / 3, 1e-9));

    // 全程值域 + 越界钳制。
    for (int i = 0; i <= 60; i++) {
      final double value = GuardBattleField.hitFlashAlphaAt(i / 60);
      expect(value, inInclusiveRange(0.25, 1.0), reason: 't=${i / 60}');
    }
    expect(GuardBattleField.hitFlashAlphaAt(-1), closeTo(0.25, 1e-9));
    expect(GuardBattleField.hitFlashAlphaAt(2), closeTo(1.0, 1e-9));
  });

  // ── ⑥ 拖尾常量表自检 ────────────────────────────────────────────────────
  test('拖尾常量表与点数等长且单调（改点数漏改表 ⇒ 立即红）', () {

    expect(kGuardBulletTrailDotScales.length, kGuardBulletTrailDots);
    expect(kGuardBulletTrailDotOpacities.length, kGuardBulletTrailDots);
    for (int i = 1; i < kGuardBulletTrailDots; i++) {
      expect(kGuardBulletTrailDotScales[i], lessThan(kGuardBulletTrailDotScales[i - 1]),
          reason: '越远越小');
      expect(
          kGuardBulletTrailDotOpacities[i],
          lessThan(kGuardBulletTrailDotOpacities[i - 1]),
          reason: '越远越淡');
    }
  });

  // ── ⑧a 击退纯函数锚点（B13.20d）────────────────────────────────────────
  test('knockbackOffsetAt：t=0→0、t=0.5→1.0、t=1→0，全程 ∈ [0,1]，前后半镜像对称', () {
    expect(GuardBattleField.knockbackOffsetAt(0), closeTo(0, 1e-9),
        reason: '起手不跳变');
    expect(GuardBattleField.knockbackOffsetAt(0.5), closeTo(1.0, 1e-9),
        reason: '峰值恰在半程（冲出到最远）');
    expect(GuardBattleField.knockbackOffsetAt(1), closeTo(0, 1e-9),
        reason: '结束回位不跳变（到点后与未受击逐位相同）');
    expect(GuardBattleField.knockbackOffsetAt(-0.3), closeTo(0, 1e-9),
        reason: '越界钳位');
    expect(GuardBattleField.knockbackOffsetAt(1.7), closeTo(0, 1e-9),
        reason: '越界钳位');
    for (int i = 0; i <= 100; i++) {
      expect(GuardBattleField.knockbackOffsetAt(i / 100), inInclusiveRange(0, 1),
          reason: 't=${i / 100}');
    }
    expect(
      GuardBattleField.knockbackOffsetAt(0.25),
      closeTo(GuardBattleField.knockbackOffsetAt(0.75), 1e-9),
      reason: 'sin(π·t) 关于 0.5 对称（冲出 = 回位镜像）',
    );
  });

  // ── ⑧b 受击击退 widget 级 ──────────────────────────────────────────────
  testWidgets('⑧ 受击击退：hit 后怪 left 短时向右增大（逆行走方向），击退窗后回位',
      (WidgetTester tester) async {
    final GuardBattleHandle handle = await _pumpField(tester);

    // 找一次「非击灭」的受击：闪动变暗 + 怪没转入死亡演出（kill 不击退）。
    int target = -1;
    outer:
    for (int shot = 0; shot < 40 && target < 0; shot++) {
      await tester.pump(const Duration(milliseconds: 450));
      handle.fire();
      for (int k = 0; k < 12; k++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byKey(GuardBattleField.bannerKey).evaluate().isNotEmpty) {
          break outer;
        }
        for (int i = 0; i < 5; i++) {
          final bool flashing = flashOpacityOf(tester, i) < 1.0;
          final bool dying = find.descendant(
            of: find.byKey(GuardBattleField.monsterKey(i)),
            matching: find.byKey(GuardBattleField.deathFadeKey(i)),
          ).evaluate().isNotEmpty;
          if (flashing && !dying) {
            target = i;
            break outer;
          }
        }
      }
    }
    expect(target, greaterThanOrEqualTo(0), reason: '必须找到一次非击灭的受击');

    // 受击窗口内 20ms 步进采样怪 slot 的 left：正常行走怪向左走（left 单调
    // 减小），击退 = 出现明显的**正增长**步（20ms 内 ≥ +2pt；sin 起步段斜率
    // ≈ π·10pt/180ms ⇒ 20ms 差最大 ~3.4pt）。
    double prev = _monsterLeft(tester, target);
    bool knocked = false;
    for (int k = 0; k < 10 && !knocked; k++) {
      await tester.pump(const Duration(milliseconds: 20));
      final double cur = _monsterLeft(tester, target);
      if (cur - prev >= 2.0) knocked = true;
      prev = cur;
    }
    expect(knocked, isTrue,
        reason: '受击后必须出现「向右弹开」的位移步（逆行走方向 = 击退）');

    // 击退窗（180ms）后回位：left 恢复单调减小（不再出现正增长步）。
    await tester.pump(const Duration(milliseconds: kGuardKnockbackMs));
    prev = _monsterLeft(tester, target);
    bool stillKnocking = false;
    for (int k = 0; k < 4; k++) {
      await tester.pump(const Duration(milliseconds: 60));
      final double cur = _monsterLeft(tester, target);
      if (cur - prev > 1.0) stillKnocking = true;
      prev = cur;
    }
    expect(stillKnocking, isFalse,
        reason: '击退是限时演出，180ms 后必须回位（left 恢复行走单调减小）');
    expect(tester.takeException(), isNull);
  });
}

/// 第 [i] 只怪 slot（`monsterKey(i)`）的当前 left（击退测试用）。
double _monsterLeft(WidgetTester tester, int i) =>
    tester.widget<Positioned>(find.byKey(GuardBattleField.monsterKey(i)))
        .left!;

/// 取列表最小 / 最大值的小工具（避免为两处 reduce 引整个 dart:math）。
double minOf(double a, double b) => a < b ? a : b;
double maxOf(double a, double b) => a > b ? a : b;
