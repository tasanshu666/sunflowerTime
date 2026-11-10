/// 守卫战 v2 · **布局护栏 v5（B9 引入，B10 数字已更新）**。
///
/// 真源：`guard_card_layout.dart`（几何单一来源）+ `guard_scene_card.dart`
/// （战士 / 溢出放行 / 能量点锚花园中轴）+ `guard_art.dart`（裁边后的素材）。
///
/// ## 🔴 本文件的数字属于**哪一版**
/// B9（玄参第四轮）建立了本文件，B10（第五轮）改了其中四个数并**同步更新了断言**：
/// | 项 | B9 | **B10** |
/// |---|---|---|
/// | 战士边长 | 78 | **68** |
/// | 战士绘制框 | 130 | **113.33**（= 68 × 5/3，派生） |
/// | 能量点直径 / 间隙 | 18 / 8 | **14 / 6** |
/// | 卡顶留白 padTop | 10 | **14**（卡高 108 → 112） |
/// | 390 屏跑道 | 99.83 | **109.83** |
/// | 三怪口径 | 高度齐平 44 | **等面积**（B10 1936pt²；B11 起 m1 × 0.80） |
///
/// B10 的**新增**验收（卡不被 ListView 裁剪 / 能量点锚点六值 dump / 三怪等面积）
/// 在 `guard_scene_card_layout_v6_test.dart`；本文件继续守「几何来源一致 +
/// 跨屏宽不打架」这条线。
///
/// ## 覆盖
/// | # | 断言 |
/// |---|---|
/// | ① | 战士 **68** 正方形、底边踩基线；窄卡 57.8 |
/// | ② | 三态 `BoxFit.fitHeight` + 绘制框 113.33 宽（横向溢出**不裁**、不缩） |
/// | ③ | 栅栏间隙 2（窄卡 1.7） |
/// | ④ | `channelLeft = soldierRect.right − monsterExtent/2`；390 屏跑道 **109.83** |
/// | ⑤ | 能量点两点整体锚**花园中轴**；直径 14、gap 6、顶边 14 |
/// | ⑥ | `kGuardCardLift == 16`、卡高 **112**、卡后间距仍是 10 |
/// | ⑦ | 三怪**等面积**（B11 系数：m1 0.80 ⇒ 44.19×35.04 / m2 44×44 / m3 60.93×31.77） |
///
/// 🔴 全文件有界 `pump`（待机战士帧序列 / 战斗 ticker 都在跑，绝不 `pumpAndSettle`）。
library guard_scene_card_layout_v5_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show
        GuardBattleMonsterKind,
        GuardBattleMonsterSpec,
        GuardBattleScript,
        kGuardBattleFieldTravelPt,
        kGuardBattleLaneBottomPt,
        kGuardBattleLaneTopPt;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
// ═══════════════════════════════════════════════════════════════════════

GuardTodayView _view(GuardPillMode mode, {int energy = 2}) {
  final GuardDayStatus status = switch (mode) {
    GuardPillMode.claimed => GuardDayStatus.claimed,
    GuardPillMode.fighting => GuardDayStatus.fighting,
    GuardPillMode.freeRide => GuardDayStatus.short,
    _ => GuardDayStatus.pending,
  };
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-11-10',
      status: status,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: energy,
    balance: 0,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  double screenWidth = 390,
  GuardPillMode mode = GuardPillMode.pendingFree,
  int energy = 2,
}) async {
  tester.view.physicalSize = Size(screenWidth, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cardWidth,
            child: GuardSceneCard(
              view: _view(mode, energy: energy),
              dayKey: '2026-11-10',
              childId: 'seed-0',
              onStart: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 三只怪（m1 / m2 / m3）同时在场的最小战斗层夹具（量宽高用）。
///
/// 三只都在 t=0 出场、速度极慢（4pt/s ⇒ 330pt 要 82s ≫ 30s 窗口）⇒ 不会到门、
/// 不会互相顶掉、战局不会提前结束。`hitsToKill` 给大值 ⇒ 一枪打不死，画面稳定。
Future<void> _pumpThreeMonsterField(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  GuardBattleMonsterSpec spec(int index, GuardBattleMonsterKind kind) {
    return GuardBattleMonsterSpec(
      index: index,
      kind: kind,
      spawnMs: 0,
      speedPtPerSec: 4,
      dodgeProb: 0,
      hitsToKill: 99,
      steal: 1,
      laneYPt: (kGuardBattleLaneTopPt + kGuardBattleLaneBottomPt) / 2,
      wobbleAmpPt: 0,
      wobbleFreqHz: 0,
      wobblePhaseRad: 0,
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 390,
            height: kGuardSceneCardHeight,
            child: GuardBattleField(
              dayKey: '2026-11-10',
              childId: 'three-0',
              handle: GuardBattleHandle(),
              debugScriptOverride: GuardBattleScript(
                windowMs: kGuardBattleWindowMs,
                monsters: <GuardBattleMonsterSpec>[
                  spec(0, GuardBattleMonsterKind.m1),
                  spec(1, GuardBattleMonsterKind.m2),
                  spec(2, GuardBattleMonsterKind.m3),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // 帧序列靠 FutureBuilder 解析 AssetManifest ⇒ 多 pump 几帧等它落位。
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  // ── ① 战士 68 正方形 ──────────────────────────────────────────────────
  group('① 战士 68（裁边后标称 = 视觉；B10/C1）', () {
    testWidgets('390 卡：soldierRect 正方形 68×68，底边踩房子基线',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));

      // 字面量 68（不引用常量 —— 常量被改本断言必须红）。
      expect(soldier.width, closeTo(68, 0.01),
          reason: '🔴 B10/C1：战士边长 78 → 68（玄参第五轮「还是太大」）');
      expect(soldier.height, closeTo(68, 0.01),
          reason: '🔴 正方形：跑道按它算，不许被攻击帧的长兵器拖累');
      expect(soldier.bottom, closeTo(house.bottom, 0.01),
          reason: '🔴 脚底踩同一条基线（站在草地上，不是浮空）');
      // 顶部不越出卡：68 高 + padBottom 10 ≤ 卡高 112。
      expect(soldier.height,
          lessThanOrEqualTo(kGuardSceneCardHeight - kGuardCardPadBottom));
    });

    testWidgets('320 卡（≤380）：68 × 0.85 = 57.8（卡高仍 112）',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 320, screenWidth: 320);
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));
      expect(soldier.width, closeTo(57.8, 0.05),
          reason: '🔴 窄卡等比缩：68 × 0.85');
      expect(soldier.height, closeTo(57.8, 0.05));
      expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
          closeTo(112, 0.5),
          reason: '🔴 窄卡只缩元素不缩卡高');
    });

    test('纯值类口径：soldierHeight 68 / soldierHouseGap 2 / 绘制框 113.33', () {
      expect(GuardCardLayout.soldierHeight, 68);
      expect(GuardCardLayout.soldierSize, 68, reason: '正方形（旧名合并）');
      expect(GuardCardLayout.soldierHouseGap, 2,
          reason: '🔴 裁边后 2pt 才是肉眼 2pt（旧 6pt 肉眼是 23pt）');
      // 绘制框 = 68 × 5/3 = 113.33 > 攻击帧需要的 99.76（512×349 按高 68 缩放）。
      expect(GuardCardLayout.soldierOverflowWidth, closeTo(113.33, 0.01));
      expect(const GuardCardLayout(390).soldierDrawWidth,
          closeTo(113.33, 0.01));
      expect(const GuardCardLayout(320).soldierDrawWidth, closeTo(96.33, 0.01));
      const double attackWidth = 68 * 512 / 349;
      expect(attackWidth, lessThan(GuardCardLayout.soldierOverflowWidth),
          reason: '🔴 攻击帧宽 ${attackWidth.toStringAsFixed(2)} 必须落在绘制框内');
    });
  });

  // ── ② fitHeight + 横向溢出放行 ────────────────────────────────────────
  group('② 三态 fitHeight（禁止 contain）', () {
    testWidgets('待机帧按 fitHeight 绘制，绘制框 113.33×68（宽比 68 大 ⇒ 溢出放行）',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);

      final Size draw = tester.getSize(find.descendant(
        of: find.byKey(GuardSceneCard.soldierKey),
        matching: find.byType(FrameSequencePlayer),
      ));
      expect(draw.width, closeTo(113.33, 0.5),
          reason: '🔴 绘制框 113.33 宽（比布局框 68 宽 ⇒ 攻击帧长兵器不被裁）');
      expect(draw.height, closeTo(68, 0.5),
          reason: '🔴 高度恒定 68（三态都一样高，绝不会一开火就变小）');

      final Iterable<Image> images = tester.widgetList<Image>(find.descendant(
        of: find.byKey(GuardSceneCard.soldierKey),
        matching: find.byType(Image),
      ));
      expect(images, isNotEmpty, reason: '待机帧序列必须真的在画素材');
      for (final Image img in images) {
        expect(img.fit, BoxFit.fitHeight,
            reason: '🔴 三态一律 BoxFit.fitHeight（禁止 contain）');
      }
    });

    testWidgets('布局框仍是 68（溢出不放宽跑道）', (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      const GuardCardLayout l = GuardCardLayout(390);
      expect(l.soldierRect.width, closeTo(68, 0.001),
          reason: '🔴 溢出只影响绘制，soldierRect 仍是正方形 68');
      expect(tester.getSize(find.byKey(GuardSceneCard.soldierKey)).width,
          closeTo(68, 0.01));
    });
  });

  // ── ③ 栅栏间隙 2 ──────────────────────────────────────────────────────
  group('③ 栅栏间隙 2pt', () {
    testWidgets('390 卡：soldier.left − house.right == 2',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));
      expect(soldier.left - house.right, closeTo(2, 0.51),
          reason: '🔴 裁边后 2pt 就是肉眼 2pt');
    });

    test('窄卡同比缩：2 × 0.85 = 1.7', () {
      const GuardCardLayout wide = GuardCardLayout(390);
      const GuardCardLayout narrow = GuardCardLayout(320);
      expect(wide.soldierRect.left - wide.houseRect.right, closeTo(2, 0.01));
      expect(narrow.soldierRect.left - narrow.houseRect.right,
          closeTo(1.7, 0.01));
    });
  });

  // ── ④ 通道左端 = 战士右缘 − 半个怪 ────────────────────────────────────
  group('④ 跑道（怪半个身子压住战士才停）', () {
    test('390 卡：channelRight 314 / 战士右缘 226.17 / 跑道 109.83', () {
      const GuardCardLayout l = GuardCardLayout(390);
      // 玄参验收口径（字面量，不引用常量反算）：
      //   channelRight = 390 − 8 − 64 − 4 = 314
      //   soldierRect.right = 156.17 + 2 + 68 = 226.17
      //   跑道 = 314 − (226.17 − 22) = 109.83
      expect(l.houseRect.right, closeTo(156.17, 0.05));
      expect(l.soldierRect.right, closeTo(226.17, 0.05));
      expect(l.rightClusterRect.left, closeTo(318, 0.01));
      expect(l.channelRight, closeTo(314, 0.01));
      expect(l.channelLeft, closeTo(204.17, 0.05));
      expect(l.channelWidth, closeTo(109.83, 0.05),
          reason: '🔴 B10/C1 验收线（±1）：实测 ${l.channelWidth}');
      // 语义：停下时怪压住战士半个身位（= monsterExtent / 2 = 22）。
      expect(l.soldierRect.right - l.channelLeft, closeTo(22, 0.001),
          reason: '🔴 C 方案：怪走到门口时半个身子压在战士身上');
    });

    test('sim 行程映射口径不变：0 ⇒ channelRight，330 ⇒ channelLeft', () {
      const GuardCardLayout l = GuardCardLayout(390);
      expect(l.mapMonsterX(0), closeTo(l.channelRight, 0.01));
      expect(l.mapMonsterX(kGuardBattleFieldTravelPt), closeTo(l.channelLeft, 0.01),
          reason: '🔴 sim 的行程刻度一个字节没动，只换渲染落点');
      expect(l.mapBulletX(0), closeTo(l.channelRight, 0.01));
    });

    test('通道随屏宽单调、窄卡留够一只怪', () {
      expect(const GuardCardLayout(320).channelWidth, closeTo(81.86, 0.6));
      expect(const GuardCardLayout(360).channelWidth, closeTo(121.86, 0.6));
      expect(const GuardCardLayout(375).channelWidth, closeTo(136.86, 0.6));
      expect(const GuardCardLayout(1024).channelWidth, closeTo(743.84, 0.6));
      for (final double w in <double>[320, 360, 375, 390, 1024]) {
        expect(GuardCardLayout(w).channelWidth,
            greaterThanOrEqualTo(GuardCardLayout(w).monsterExtent),
            reason: '$w 卡的跑道必须容得下一只怪（$w）');
      }
    });
  });

  // ── ⑤ 能量点锚花园中轴 ────────────────────────────────────────────────
  group('⑤ 能量点在花园上方（不是战士头顶）', () {
    testWidgets('两点整体以花园中轴居中；gap 6、直径 14、顶边 14',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final Rect d0 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(0)));
      final Rect d1 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(1)));

      expect((d0.left + d1.right) / 2,
          closeTo(house.center.dx + kGuardEnergyDotAnchorDx, 0.01),
          reason: '🔴 锚点 = houseRect.center.dx + kGuardEnergyDotAnchorDx');
      expect(d0.width, closeTo(14, 0.01));
      expect(d0.height, closeTo(14, 0.01));
      expect(d1.left - d0.right, closeTo(6, 0.01), reason: '两点 gap = 6');
      expect(d0.top - card.top, closeTo(14, 0.01),
          reason: '🔴 顶边钉房顶线（= padTop 14）');
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));
      expect((d0.left + d1.right) / 2,
          isNot(closeTo(soldier.center.dx, 1.0)),
          reason: '🔴 不许再锚在战士头顶');
    });

    test('纯值类口径：点组合宽度 = 2×14 + 6 = 34，左端 = 花园中心 − 17', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Rect d0 = l.energyDotRect(0);
      final Rect d1 = l.energyDotRect(1);
      expect(d1.right - d0.left, closeTo(34, 0.001));
      expect(d0.left,
          closeTo(l.houseRect.center.dx + kGuardEnergyDotAnchorDx - 17, 0.001),
          reason: '🔴 B11：锚点 +20 ⇒ 左端 = 中轴 + 20 − 17');
      expect(d0.top, l.energyDotTopY);
    });
  });

  // ── ⑥ 整体上移常量 ────────────────────────────────────────────────────
  group('⑥ 卡片上移 26pt（B10 改缩滚动区留白；B11 再 +10）', () {
    test('常量：kGuardCardLift = 26，卡高 112 / 间距 10', () {
      // B9 = 16（Transform 实现，已因削顶废弃）→ B10 = 16（缩 sceneGap）→
      // **B11 = 26**（玄参第六轮「再往上一点」）。机制仍是缩滚动区留白。
      expect(kGuardCardLift, 26, reason: '🔴 B11：卡顶与半圆弧之间的空隙再 +10');
      expect(kGuardSceneCardHeight, 112,
          reason: '🔴 B10：padTop 10 → 14 ⇒ 卡高 112');
      expect(kGuardCardPadTop, 14);
      expect(kGuardPillGap, 10,
          reason: '🔴 卡后间距保持 10（上移量落在上方 sceneGap 里）');
    });

    testWidgets('卡自身高度 112（上移由页面缩 sceneGap 完成，卡内不受影响）',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
          closeTo(kGuardSceneCardHeight, 0.5));
      // 页面层的「卡顶不越视口 / 统计卡累计上移 22」在 v6 ① 与
      // guard_today_flow_test ① 里测量（那里有真实 ListView）。
    });
  });

  // ── ⑦ 三怪等面积（B10/C3 + B11/C5 面积系数）────────────────────────────
  group('⑦ 三怪等面积（B11：m1 系数 0.80 ⇒ 1548.8pt²；m2/m3 仍 1936pt²）', () {
    test('纯值类：m1 44.19×35.04 / m2 44×44 / m3 60.93×31.77（窄卡 ×0.85）', () {
      const GuardCardLayout l = GuardCardLayout(390);
      // 字面量（不引用常量反算）。
      // 🔴 B11/C5：m1 面积 × 0.80 = 1548.8 ⇒ h = √(1548.8/1.261) = 35.04、w = 44.19。
      expect(l.monsterWidthOf('m1'), closeTo(44.19, 0.1),
          reason: '🔴 m1 馋光鼠（系数 0.80）：44.19 宽');
      expect(l.monsterHeightOf('m1'), closeTo(35.04, 0.1),
          reason: '🔴 m1 高 35.04（B10 是 39.18）');
      expect(l.monsterWidthOf('m2'), closeTo(44.00, 0.1));
      expect(l.monsterHeightOf('m2'), closeTo(44.00, 0.1));
      expect(l.monsterWidthOf('m3'), closeTo(60.93, 0.1),
          reason: '🔴 m3 贪婪鼬 512×267 ⇒ h = √(1936/1.918) = 31.77、w = 60.93');
      expect(l.monsterHeightOf('m3'), closeTo(31.77, 0.1));
      // 未知种类兜底 = 正方形（占位色块）。
      expect(l.monsterWidthOf('mX'), closeTo(44.00, 0.01));
      expect(l.monsterHeightOf('mX'), closeTo(44.00, 0.01));
      // 窄卡等比缩。
      const GuardCardLayout narrow = GuardCardLayout(320);
      expect(narrow.monsterHeightOf('m1'), closeTo(29.79, 0.1),
          reason: '35.04 × 0.85 = 29.79');
      expect(narrow.monsterWidthOf('m3'), closeTo(51.79, 0.1));
    });

    testWidgets('390 屏实测：三怪同屏，宽高 ≡ 等面积（±0.6）',
        (WidgetTester tester) async {
      await _pumpThreeMonsterField(tester);

      final Map<int, Size> rendered = <int, Size>{};
      for (int i = 0; i < 3; i++) {
        expect(find.byKey(GuardBattleField.monsterKey(i)), findsOneWidget,
            reason: '三只怪都要在场（否则量不到宽高）');
        rendered[i] = tester.getSize(find.descendant(
          of: find.byKey(GuardBattleField.monsterKey(i)),
          matching: find.byType(FrameSequencePlayer),
        ));
      }

      expect(rendered[0]!.width, closeTo(44.19, 0.6),
          reason: 'm1 44.19 宽（B11 系数 0.80）');
      expect(rendered[0]!.height, closeTo(35.04, 0.6), reason: 'm1 35.04 高');
      expect(rendered[1]!.width, closeTo(44.00, 0.6), reason: 'm2 正方形');
      expect(rendered[1]!.height, closeTo(44.00, 0.6));
      expect(rendered[2]!.width, closeTo(60.93, 0.6), reason: 'm3 60.93 宽');
      expect(rendered[2]!.height, closeTo(31.77, 0.6), reason: 'm3 31.77 高');

      // 🔴 核心断言：面积 == 1936 × **本档系数**（±1%）—— 玄参「体量要一样」
      // 的判据（B11 起 m1 单独乘 0.80，「馋光鼠还有点大」）。
      const double base = 44 * 44;
      const Map<String, double> factor = <String, double>{
        'm1': 0.80,
        'm2': 1.0,
        'm3': 1.0,
      };
      const List<String> kinds = <String>['m1', 'm2', 'm3'];
      for (int i = 0; i < 3; i++) {
        final double area = rendered[i]!.width * rendered[i]!.height;
        final double target = base * factor[kinds[i]]!;
        expect(area, closeTo(target, target * 0.01),
            reason: '🔴 ${kinds[i]} 面积 ${area.toStringAsFixed(1)} 必须 ≈ '
                '${target.toStringAsFixed(1)}（1936 × ${factor[kinds[i]]}）');
      }
      // 与 B10 逐位对照：m2/m3 本轮**一个字节没动**。
      expect(rendered[1]!.width, closeTo(44.00, 0.1),
          reason: '🔴 m2 与 B10 逐位相同');
      expect(rendered[2]!.height, closeTo(31.77, 0.6),
          reason: '🔴 m3 与 B10 逐位相同');

      // 素材一律 fitHeight（与战士同一套口径，禁止 contain）。
      final Iterable<Image> images = tester.widgetList<Image>(find.descendant(
        of: find.byKey(GuardBattleField.fieldKey),
        matching: find.byType(Image),
      ));
      expect(images, isNotEmpty);
      for (final Image img in images) {
        expect(img.fit, BoxFit.fitHeight,
            reason: '🔴 三怪一律 BoxFit.fitHeight（contain 会让 m3 只剩 22.9pt）');
      }
    });
  });
}
