/// 🔴 C128（玄参 2026-11-22 真机反馈「大招动画期间全场怪都冻结不动」）：
/// 被大招清掉的怪在 sim 里 `dead` + **坐标冻结在被清时刻**（确定性口径不许
/// 动）⇒ C126 的行走态标记只保住了「不提前消失」，位置仍原地定住 —— cast
/// 段一开场清完 walking 怪时，整条车道看起来全部冻结。
///
/// 修复（纯表现层）：field 记录被清时刻，渲染时用 `_ultimateHeldWalkX`（快照
/// 冻结值 + prd 档位速度 + 渲染时钟的纯函数）从冻结坐标**外推继续行走**，钳到
/// 门口 330；未被命中的怪走 sim 本就照常；fx 效果落地帧记账后照常切逃跑淡出。
///
/// 本文件用 widget 级夹具 + 独立期望钉住四件事（期望值全部由 sim 公式
/// `x = speed × (t − spawn)/1000` 手推，与实现无自证循环）：
///  ① cast 期间被清怪继续向前走（不再冻在死亡坐标）；
///  ② 被清怪与「sim 正常行走的未命中怪」在同窗口内前进距离相等
///     （同档位速度 15pt/s ⇒ 渲染外推与 sim 步进同速，逐位口径）;
///  ③ 未命中怪全程照常行走（sim 不断步进，判定不受影响）；
///  ④ fx 效果落地帧后被清怪照常切 800ms 逃跑淡出并摘除（C126 语义不回归）。
///
/// 🔴 全文件有界 `pump`（L4 ticker 常驻 + 帧序列循环动画，绝不 `pumpAndSettle`）。
library guard_ultimate_held_walk_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/guard_battle_sim.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';

const String _dayKey = '2026-11-22';
const String _childId = 'held-walk-kid';

/// 两只 m1（同档位速度 15pt/s，等面积占位同宽 ⇒ 像素可比）：
///  * 怪 0：t=0 出场，普攻极难打死（hitsToKill=99）⇒ 只能被大招清；
///  * 怪 1：t=3500 出场（cast 段期间才出生，**未被大招命中**）⇒ sim 照常走。
GuardBattleScript _script() {
  return const GuardBattleScript(
    windowMs: 30000,
    monsters: <GuardBattleMonsterSpec>[
      GuardBattleMonsterSpec(
        index: 0,
        kind: GuardBattleMonsterKind.m1,
        spawnMs: 0,
        speedPtPerSec: 15,
        dodgeProb: 0.0,
        hitsToKill: 99,
        steal: 1,
        laneYPt: 100,
        wobbleAmpPt: 0,
        wobbleFreqHz: 0,
        wobblePhaseRad: 0,
      ),
      GuardBattleMonsterSpec(
        index: 1,
        kind: GuardBattleMonsterKind.m1,
        spawnMs: 3500,
        speedPtPerSec: 15,
        dodgeProb: 0.0,
        hitsToKill: 99,
        steal: 1,
        laneYPt: 110,
        wobbleAmpPt: 0,
        wobbleFreqHz: 0,
        wobblePhaseRad: 0,
      ),
    ],
  );
}

double _monsterLeft(WidgetTester tester, int index) {
  return tester.widget<Positioned>(
    find.byKey(GuardBattleField.monsterKey(index)),
  ).left!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('C128：被清怪继续行走（外推）+ 未命中怪照常走 + fx 落地帧后照常摘除',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GuardBattleHandle handle = GuardBattleHandle();
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
                    childId: _childId,
                    handle: handle,
                    debugScriptOverride: _script(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // 挂载帧：本帧起 ticker，不给时间。
    await tester.pump(const Duration(milliseconds: 1));

    // ── 推进到 sim t≈1000：怪 0 已入场行走（x = 15×1.0 = 15pt），未开火 ──
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(GuardBattleField.monsterKey(0)), findsOneWidget,
        reason: '怪 0（t=0 出场）已在车道');

    // ── 放大招：下一帧 sim t≈1000+ 消费 ⇒ 怪 0 被清（walking 全清）并进入
    //    「held 行走态」（fx 效果落地帧之前绝不消失 / 冻结）──
    handle.requestUltimate();
    await tester.pump(const Duration(milliseconds: 100));

    // ── 推进到怪 1 出生且入场滑入（400ms）结束之后：sim t≈4200。
    //    此时 cast 段仍在播（我们还没通知 castDone）⇒ 怪 0 处于 held 行走态，
    //    怪 1 由 sim 正常步进。──
    await tester.pump(const Duration(milliseconds: 3100));
    expect(find.byKey(GuardBattleField.monsterKey(1)), findsOneWidget,
        reason: '怪 1（t=3500 出场）已上屏（未被大招命中 ⇒ 照常行走）');

    final double left0a = _monsterLeft(tester, 0);
    final double left1a = _monsterLeft(tester, 1);

    // ── 同一窗口再走 800ms：两只怪都在前进。──
    await tester.pump(const Duration(milliseconds: 800));
    final double left0b = _monsterLeft(tester, 0);
    final double left1b = _monsterLeft(tester, 1);

    expect(left0b, lessThan(left0a),
        reason: '🔴 C128 核心：被清怪（held）在 cast 段必须继续向前走（冻结坐标纯外推）。'
            '🔴 渲染镜像：sim 0 在右、330（门/战士）在左 ⇒ 行走 = left 递减'
            '（mapMonsterX 镜像口径，garden_top_entry 同源）。实测 Δ=${left0b - left0a}px'
            ' —— 修复前恒 0（冻结在死亡坐标）');
    expect(left1b, lessThan(left1a),
        reason: '未命中怪走 sim 本就照常（同镜像方向，防回归基线）');
    expect(
      (left0b - left0a) - (left1b - left1a),
      closeTo(0, 0.75),
      reason: '🔴 外推同速口径：被清怪（15pt/s 档位速度外推）与 sim 行走的怪 1'
          '（15pt/s）在同窗口内前进距离必须相等 —— 外推不是变快/变慢的另一种走法',
    );

    // ── 通知 cast 段播完（真实链路：卡 27 帧 + 音轨收尾后调；测试提前于
    //    4s 预算内调用不影响被测语义：fx 段立即启动）⇒ fx 段上树，播到
    //    效果落地帧后怪 0 记死亡、切 800ms 逃跑淡出、到点摘除。──
    handle.notifyUltimateCastDone();
    // 🔴 分帧推进（fx 4000ms + 效果落地帧 post-frame 回调 + 800ms 逃跑淡出）：
    //    效果落地帧在 post-frame 回调里记账 —— 单个大 pump 会停在「记账那一帧」，
    //    逃跑还没开始就被断言 ⇒ 必须分帧给足 4000 + 800 + 余量。
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byKey(GuardBattleField.monsterKey(0)), findsNothing,
        reason: 'fx 效果落地帧记账 ⇒ 怪 0 从 held 切逃跑淡出，800ms 后摘除（C126 语义不回归）');

    // ── fx 收尾后怪 1 仍在场且继续前进（sim 判定全程未被表现层拖住）。──
    final double left1c = _monsterLeft(tester, 1);
    await tester.pump(const Duration(milliseconds: 500));
    final double left1d = _monsterLeft(tester, 1);
    expect(left1d, lessThan(left1c),
        reason: '整段大招演出期间/结束后，未命中怪一直照常行走（镜像方向 = left 递减）');

    expect(tester.takeException(), isNull);
  });
}
