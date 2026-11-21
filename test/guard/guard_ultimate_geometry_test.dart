/// 玄参 2026-11-20 真机验收 · 大招**几何 + 两段串行判据**独立护栏。
///
/// 🔴 期望值独立写死（188.18 / 37 / 42 / 30min 等均为字面量或从常量独立推导），
/// 绝不调用被测的 `ultimateBarRect` / `ultimateFxAnchor` 自证（防假绿 / 受控变异）。
library guard_ultimate_geometry_test;

import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardEnergyDotAnchorDx,
        kUltimateBarAboveGap,
        kUltimateFxFallbackDx,
        kMaxUltimateCells,
        kMinPerUltimateCell;
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleMonsterSnapshot, kGuardBattleFieldTravelPt;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart'
    show GuardCardLayout;
import 'package:sunflower_time/presentation/child/widgets/guard_ultimate_fx.dart'
    show canStartFxStage;

void main() {
  group('bug1 · 大招能量格 = 战士头顶正上方，且与旧能量球错开', () {
    test('390 屏：能量格中轴 ≈ 战士中轴 188.18，而非能量点中轴 98.09', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Rect soldier = l.soldierRect;
      final Rect bar0 = l.ultimateBarRect(0);
      final Rect bar1 = l.ultimateBarRect(1);
      final Rect dot0 = l.energyDotRect(0);

      // 独立期望：房子宽 = 88 × (1984/1118) ≈ 156.17；战士左 = 房子右 + 2；
      // 战士中轴 = 156.17 + 2 + 30 = 188.17（不是 78.09 + 20 = 98.09）。
      const double expectedSoldierCenterX = 188.17;
      expect(soldier.center.dx, closeTo(expectedSoldierCenterX, 0.1));
      expect(bar0.center.dx + 11.5, closeTo(expectedSoldierCenterX, 0.1),
          reason: '格0中心 + 半组宽(11.5) = 两格组中轴 = 战士中轴');
      expect(bar0.overlaps(dot0), isFalse,
          reason: '能量格不得压在旧能量球（入场券能量点）上');
      expect(
        (bar0.center.dx - dot0.center.dx).abs(),
        greaterThan(60),
        reason: 'X 维明显分离：390 屏两锚点相距 ≈90pt',
      );
      // 满 2 格总宽独立写死 = 2×20 + 3 = 43pt。
      expect(
        bar1.right - bar0.left,
        closeTo(43.0, 0.01),
        reason: '两格总宽 = 2×cellW + gap',
      );
    });

    test('390 屏：能量格底 = 战士顶 − 5（头顶之上、不压脸），且能量球在其上方', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Rect soldier = l.soldierRect;
      final Rect bar0 = l.ultimateBarRect(0);
      final Rect dot0 = l.energyDotRect(0);

      // 独立期望：基线 112−10 = 102；战士顶 = 102−60 = 42；
      // 能量格底 = 42−5 = 37（顶 31，高 6）。
      expect(soldier.top, closeTo(42.0, 0.01));
      expect(bar0.bottom, closeTo(37.0, 0.01));
      expect(soldier.top - bar0.bottom, closeTo(kUltimateBarAboveGap, 0.01));
      expect(bar0.bottom, lessThan(soldier.top));
      // 能量点顶 14 / 底 28（房顶线），能量格在其**下方** 3pt 但 X 已错开 90pt。
      expect(dot0.top, closeTo(14.0, 0.01));
      expect(dot0.bottom, closeTo(28.0, 0.01));
    });

    test('320 窄卡 + 平板两档：仍贴战士头顶、总宽不越卡、随 e 缩放', () {
      for (final (double width, double uiScale, double e)
          in <(double, double, double)>[
        (320, 1.0, 0.85),
        (390, 1.0, 1.0),
        (834, 1.6, 1.6),
      ]) {
        final GuardCardLayout l = GuardCardLayout(width, uiScale);
        final Rect soldier = l.soldierRect;
        final Rect bar0 = l.ultimateBarRect(0);
        final Rect bar1 = l.ultimateBarRect(1);
        expect(soldier.top - bar0.bottom, closeTo(kUltimateBarAboveGap * e, 0.01),
            reason: 'gap 随 e 缩放（w=$width, s=$uiScale）');
        expect(bar1.right - bar0.left, closeTo(43.0 * e, 0.01),
            reason: '总宽随 e 缩放');
        expect(bar0.left, greaterThanOrEqualTo(0),
            reason: '不越卡左边界（w=$width）');
        expect(bar1.right, lessThan(width), reason: '不越卡右边界（w=$width）');
      }
    });

    test('能量格 X 锚点不再使用旧能量点旋钮 kGuardEnergyDotAnchorDx', () {
      // 旋钮仍服务旧能量点（B11 美学位移 20），但大招能量格不得再复用它。
      expect(kGuardEnergyDotAnchorDx, 20);
      const GuardCardLayout l = GuardCardLayout(390);
      // 能量格组中轴 = 战士中轴（独立期望 188.17），不是 78.09 + 20 = 98.09。
      expect(
        (l.ultimateBarRect(0).center.dx + l.ultimateBarRect(1).center.dx) / 2,
        closeTo(188.17, 0.1),
      );
      expect(kMaxUltimateCells, 2);
    });
  });

  group('bug5 · cast 在战士本体 / fx 在怪物区 / 两段串行', () {
    test('ultimateCastRect == soldierRect（本体原位），不等于 fx 锚点', () {
      const GuardCardLayout l = GuardCardLayout(390);
      expect(l.ultimateCastRect, l.soldierRect,
          reason: '释放动作帧画在战士本体矩形，绝不另起形象');

      // 一只走到了通道中点的怪：fx 锚点经 mapMonsterX 落在通道，离战士中轴很远。
      const GuardBattleMonsterSnapshot mid = GuardBattleMonsterSnapshot(
        index: 0,
        kindId: 'm2',
        phaseId: 'walking',
        x: kGuardBattleFieldTravelPt / 2,
        y: 100,
        spawnMs: 0,
        hitsTaken: 0,
        stolen: 0,
      );
      final Offset fx = l.ultimateFxAnchor(<GuardBattleMonsterSnapshot>[mid]);
      expect((fx.dx - l.soldierRect.center.dx).abs(), greaterThan(30),
          reason: 'fx 锚点不在 soldierRect 中心（口径 9）');
    });

    test('无 walking 怪时 fx 回退锚点也不落战士脚下', () {
      const GuardCardLayout l = GuardCardLayout(390);
      final Offset fx =
          l.ultimateFxAnchor(<GuardBattleMonsterSnapshot>[]);
      // 独立期望：房子宽 88×1984/1118 ≈ 156.16 ⇒ 战士右 = 156.16+2+60 = 218.16；
      // channelLeft = 218.16 − 22 = 196.16；回退 = 196.16 + 24 = 220.16
      // （离战士中轴 188.16 有 32pt，不在战士脚下）。
      expect(fx.dx, closeTo(220.16, 0.2));
      expect((fx.dx - l.soldierRect.center.dx).abs(), greaterThan(30));
      expect(kUltimateFxFallbackDx, 24.0);
    });

    test('两段串行判据：cast 帧与 cast 音轨都完成才允许启动 fx', () {
      expect(canStartFxStage(castFramesDone: false, castAudioDone: false), isFalse);
      expect(canStartFxStage(castFramesDone: true, castAudioDone: false), isFalse,
          reason: '音轨没播完不得抢跑 fx');
      expect(canStartFxStage(castFramesDone: false, castAudioDone: true), isFalse,
          reason: '动作没播完不得抢跑 fx');
      expect(canStartFxStage(castFramesDone: true, castAudioDone: true), isTrue);
      // 30min 1 格 / 2 格封顶（bug4 口径不变，本轮零改动）。
      expect(kMinPerUltimateCell, 30);
    });
  });
}
