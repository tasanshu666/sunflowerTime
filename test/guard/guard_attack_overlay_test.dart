/// 守卫战 v2 · **B10/B2 攻击叠层护栏**（玄参 2026-11-10 第五轮）。
///
/// ## 玄参原话
/// 「战士攻击的时候，**原地还站着一个待机的小人**」—— 两个人物同屏。
///
/// ## 病理（渲染层，不是 sim）
/// `_GuardSequence` 的结构是 `Stack[ 帧序列 , 攻击静态 ]`：帧序列**常驻挂载**
/// （这是对的 —— 换掉整棵子树会让每枪重建 FutureBuilder、闪一帧占位色），
/// 但攻击帧只是**盖在上面**，下面那层没有隐藏。攻击帧按 `fitHeight` 画
/// 512×349（宽 1.467h），比待机帧（宽 0.973h）宽得多 ⇒ 盖不住两侧的待机小人
/// ⇒ 玄参看到「两个人物」。
///
/// ## 修法与本文的断言
/// 帧序列层套一层 `Opacity(key: GuardArt.idleLayerKey)`：
/// * 攻击时 `opacity = 0`（`RenderOpacity` 在 0 时**跳过整棵子树的绘制**，
///   肉眼只剩攻击帧）；
/// * 子树**仍然挂载**（`FrameSequencePlayer` 还在树上，缓存 / 播放位置不丢）
///   ⇒ `_flashAttack` 结束同帧待机立刻回来，**不许有一帧空白**。
///
/// 🔴 全文件有界 `pump`（战局 ticker + 帧序列常驻，绝不 `pumpAndSettle`）。
library guard_attack_overlay_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

/// 战斗态快照（`mode == fighting` ⇒ 卡内挂 L4 战斗层，开火手柄才接得上）。
GuardTodayView _fightingView() {
  return const GuardTodayView(
    mode: GuardPillMode.fighting,
    state: GuardDayState(
      dayKey: '2026-11-10',
      status: GuardDayStatus.fighting,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: 2,
    balance: 100,
  );
}

/// 战士子树里**实际可见**（累计 opacity > 0）的 `Image` 张数。
///
/// 为什么不用 `find.byType(Image)` 直接数：待机层在攻击时 `opacity = 0`，
/// 但它**仍在树上**（这正是 B10 的修法），必须按「累计不透明度」筛。
int _visibleSoldierImages(WidgetTester tester) {
  int count = 0;
  for (final Element e in find
      .descendant(
        of: find.byKey(GuardSceneCard.soldierKey),
        matching: find.byType(Image),
      )
      .evaluate()) {
    double opacity = 1;
    e.visitAncestorElements((Element anc) {
      final Widget w = anc.widget;
      if (w is Opacity) opacity *= w.opacity;
      // 走到战士槽位就停（外面的层与本断言无关）。
      return anc.widget.key != GuardSceneCard.soldierKey;
    });
    if (opacity > 0) count++;
  }
  return count;
}

void main() {
  testWidgets('① fighting 态 idle 层全程隐藏；开火只切叠层素材（B12）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final GuardBattleHandle handle = GuardBattleHandle();
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
              width: 390,
              child: GuardSceneCard(
                view: _fightingView(),
                dayKey: '2026-11-10',
                childId: 'overlay-0',
                battleHandle: handle,
                onStart: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // 帧序列要先落位（AssetManifest 异步解析）。
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));

    // ── 战斗进行中（未开火）：B12 站立静态盖在 idle 层之上 ────────────────
    // 🔴 B12 语义更新：战斗站立 = soldier_stand.webp（stillAsset），
    // idle 帧序列层从进战斗那一刻起就 opacity = 0（隐藏但仍挂载）。
    expect(find.byKey(GuardArt.attackOverlayKey), findsOneWidget,
        reason: 'B12：战斗站立静态走同一个 still 叠层');
    String overlayAssetOf(WidgetTester t) {
      final Image img = t.widget<Image>(
        find.descendant(
          of: find.byKey(GuardArt.attackOverlayKey),
          matching: find.byType(Image),
        ),
      );
      return (img.image as AssetImage).assetName;
    }

    expect(overlayAssetOf(tester), 'assets/guard/soldier_stand.webp',
        reason: 'B12：未开火时叠层 = 专用站立静态');
    final Opacity idleBefore =
        tester.widget<Opacity>(find.byKey(GuardArt.idleLayerKey));
    expect(idleBefore.opacity, 0.0,
        reason: '🔴 B12：fighting 态 idle 帧序列层必须隐藏（stand 也算 still）');
    expect(_visibleSoldierImages(tester), 1,
        reason: '战斗中始终只有一个可见人物');
    final Element idleElementBefore =
        find.byKey(GuardArt.idleLayerKey).evaluate().single;

    // ── 开火：命中 300ms 攻击窗口 ──────────────────────────────────────
    expect(find.byKey(GuardBattleField.fieldKey), findsOneWidget,
        reason: 'fighting 态必须挂 L4（手柄才接得上）');
    handle.fire();
    await tester.pump(const Duration(milliseconds: 16));

    expect(overlayAssetOf(tester), 'assets/guard/soldier_attack.webp',
        reason: '🔴 开火后叠层素材必须切攻击帧');
    final Opacity idleDuring =
        tester.widget<Opacity>(find.byKey(GuardArt.idleLayerKey));
    expect(idleDuring.opacity, 0.0,
        reason: '🔴 B10/B2：攻击时帧序列层必须隐藏（否则两个人物同屏）');
    expect(_visibleSoldierImages(tester), 1,
        reason: '🔴 攻击期间树里只能有一个 opacity > 0 的战士素材');
    // 🔴 关键：隐藏 ≠ 摘树。子树必须还在（缓存 / 播放位置不丢，切回来不闪）。
    expect(find.byKey(GuardArt.idleLayerKey), findsOneWidget,
        reason: '🔴 帧序列层不许从树上摘掉（只是不绘制）');
    expect(
        find.descendant(
          of: find.byKey(GuardArt.idleLayerKey),
          matching: find.byType(Image),
        ),
        findsWidgets,
        reason: '🔴 待机帧的 Image 必须仍在树上（挂载保活，不是 Visibility 摘除）');
    expect(
        find.byKey(GuardArt.idleLayerKey).evaluate().single,
        same(idleElementBefore),
        reason: '🔴 同一个 Element（没重建 ⇒ FutureBuilder 不会重解析、不闪占位色）');

    // ── 300ms 到点：回站立静态（B12），仍只有一个可见人物 ────────────────
    await tester.pump(const Duration(milliseconds: kGuardSoldierAttackFlashMs));
    expect(overlayAssetOf(tester), 'assets/guard/soldier_stand.webp',
        reason: '🔴 收枪同帧必须回到 B12 站立静态（不是 idle 循环帧）');
    expect(_visibleSoldierImages(tester), 1,
        reason: '🔴 收枪同帧必须有一个可见的战士（不许空白）');
    expect(
        tester.widget<Opacity>(find.byKey(GuardArt.idleLayerKey)).opacity, 0.0,
        reason: '🔴 仍在战斗中：idle 层保持隐藏');

    // ── 再开一枪：仍然只有一个可见人物（可重复）───────────────────────
    await tester.pump(const Duration(milliseconds: 400)); // 过冷却闸门
    handle.fire();
    await tester.pump(const Duration(milliseconds: 16));
    expect(overlayAssetOf(tester), 'assets/guard/soldier_attack.webp',
        reason: '🔴 第二枪同样切攻击帧');
    expect(_visibleSoldierImages(tester), 1,
        reason: '🔴 第二枪同样是「一个可见人物」');
    await tester.pump(const Duration(milliseconds: kGuardSoldierAttackFlashMs));
    expect(overlayAssetOf(tester), 'assets/guard/soldier_stand.webp',
        reason: '🔴 第二枪收枪后回站立静态');
    expect(_visibleSoldierImages(tester), 1,
        reason: '🔴 收枪后仍是一个可见人物');
  });

  test('② 常量：攻击帧时长 300ms 与 kGuardCardLift 26 互不干扰', () {
    expect(kGuardSoldierAttackFlashMs, 300);
    // 🔴 B11：卡整体再上移 10（16 → 26），与开火攻击帧时长无关。
    expect(kGuardCardLift, 36);
  });
}
