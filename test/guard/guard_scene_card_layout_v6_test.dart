/// 守卫战 v2 · **布局护栏 v6（B10 新增）** —— 真机尺寸夹具上的「不裁剪 + 六值 dump」。
///
/// ## 为什么要有 v6（v5 守不住的那条线）
/// B9 用 `Transform.translate(0, −16)` 把场景卡整体上移，**验收全绿**，
/// 但玄参第五轮真机截图里「房子被削顶」了 —— 因为 `Transform` **不消耗布局空间**：
/// 卡的布局矩形还在原位，绘制矩形上移 16pt ⇒ 越过 `ListView` 视口的 `ClipRect`
/// 上边界 ⇒ 屋顶被裁掉。
///
/// 🔴 所以 v6 的第一条是**硬断言**，且它在旧实现（有 Transform 的那一版）下必红：
/// ```
/// tester.getRect(cardKey).top >= tester.getRect(ListView).top
/// ```
/// （B9 实现里卡顶 = 视口顶 − 16 ⇒ `top < viewportTop` ⇒ 这条立刻失败。）
///
/// ## 本文件测什么
/// | # | 断言 |
/// |---|---|
/// | ① | **卡不被视口裁剪**：卡顶 ≥ 视口顶边；卡顶到屋顶 == `kGuardCardPadTop`(14)；房子四边全在卡内 |
/// | ② | 六值 dump（真机尺寸夹具）：`MediaQuery.width` / `cardWidth` / `scale` / `houseRect` / `energyDotRect` / `soldierRect` |
/// | ③ | C1 战士 68：正方形、底边踩房子基线、与房子间隙 2、绘制框 113.33 |
/// | ④ | C2 能量点 14 / 6：两点组合以花园中轴居中；锚点常量默认 0（十点差异的说明见下） |
/// | ⑤ | 三个 y：卡顶 / 屋顶 / 统计卡 —— 供交付报告直接抄 |
///
/// ## B11（玄参第六轮）改动
/// * 卡整体再上移 10（`kGuardCardLift` 16 → **26**）⇒ 视口顶 / 卡顶绝对值再小 10，
///   统计卡累计上移 **22**（相对 B9 基线）。**所有断言都是相对量**，故只有
///   dump 打印出来的绝对值会变，判据不变；
/// * 能量点锚点 **0 → 20**（两点圆心中点 **98.08**）；
/// * 战士 68 / 卡顶→屋顶 14 / 房子尺寸 **全部锁定不动**。
///
/// ## 🔴 C2 那「十点差异」的结论（B10 复核 → B11 拍板）
/// B10 派单要求「若对不上先停下报」。当时的复核结论：**几何是对的**。
/// · 真机尺寸夹具实测：`houseRect = (0,14,156.17,102)` ⇒ `center.dx = 78.083`；
///   两个 14pt 圆点组合宽 `2×14 + 6 = 34` ⇒ 左端 61.08、右端 95.08，
///   **组合中点 = 78.08**（两个圆心的中点也是 78.08）。
/// · 素材 `house.webp`（1984×1118）经 alpha>128 的包围盒 = (33,17,1961,1105)，
///   换算视觉中心 = 78.48 ⇒ 与几何中心只差 **0.39pt**（截图侧的透明边差异量级）。
/// · 因此 66~68 应是「把某一个点的圆心 / 某侧半边当成整体中点」的读法。
///
/// 🔴 **B11（玄参第六轮）拍板：仍要往右让 20pt** —— 这不是几何修正，是
/// **美学位移**，由玄参看图定，故改旋钮 `kGuardEnergyDotAnchorDx`：0 → **20**
/// ⇒ 两点圆心中点 = `houseRect.center.dx + 20` = **98.08**。
/// （本轮同时锁定：直径 14 / gap 6 / 顶边 14 一律不动。）
///
/// ## 夹具
/// 与 `guard_today_flow_test` 同款「真仓储 + 内存库 + 真今日页」——因为「被不被
/// `ListView` 裁剪」只有在**真的 ListView 视口**里才测得出来（裸 SizedBox 没有
/// 视口裁剪，测了也白测）。
///
/// 🔴 绝不 `pumpAndSettle`（今日页阳光气泡是 12s 无限循环动画）。
library guard_scene_card_layout_v6_test;

// ignore_for_file: avoid_print

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具（真仓储 + 内存库 + 真今日页）
// ═══════════════════════════════════════════════════════════════════════

class _Env {
  _Env({required this.sp, required this.database, required this.account});

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;

  String get childId => account.childId;

  GuardStatePrefsStore get guardStore => GuardStatePrefsStore(sp);

  Future<GuardDayState> guardState() => guardStore.read(childId);
}

Future<_Env> _makeEnv() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  return _Env(sp: sp, database: database, account: account);
}

/// 种一株存活苗（`resolve()` 只有在有存活株时才生成小偷 ⇒ 才渲染场景卡）。
Future<void> _seedPlant(_Env env, {String id = 'plant_1'}) async {
  final DateTime now = DateTime.now();
  await PlantLocalRepository(env.database, account: env.account).savePlant(
    Plant(
      id: id,
      speciesId: 'sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: now,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: now,
    ),
  );
}

/// 挂载「今日页」并推进到守卫链路完成（不点卡，故不会弹教学浮层）。
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  _Env env, {
  Size screen = const Size(390, 844),
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(env.sp),
      appDatabaseProvider.overrideWithValue(env.database),
      accountServiceProvider.overrideWithValue(env.account),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ChildTodayPage()),
    ),
  );
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

/// 反复 pump 直到 [finder] 出现（绝不用 `pumpAndSettle`）。
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 220,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget, reason: '等待超时：目标 widget 一直没出现');
}

/// 一次性把请求的六个几何真值打到测试输出（交付报告直接抄）。
///
/// `top/bottom` 一律**同时**给绝对值与「相对卡顶」的值：绝对值取决于今日页
/// 滚动位置（本夹具卡顶 y = 355.12），相对值才是卡内几何（14 / 102 …）。
void _dumpSix({
  required double mediaWidth,
  required double cardWidth,
  required double scale,
  required double cardTop,
  required Rect house,
  required Rect dot0,
  required Rect dot1,
  required Rect soldier,
}) {
  String f(double v) => v.toStringAsFixed(2);
  String r(Rect x) =>
      '(${f(x.left)}, ${f(x.top)}, ${f(x.right)}, ${f(x.bottom)})';
  print('── B11 真机尺寸夹具六值 ─────────────────────────────');
  print('MediaQuery.width = ${f(mediaWidth)}');
  print('cardWidth        = ${f(cardWidth)}');
  print('scale            = ${f(scale)}');
  print('card.top (绝对值) = ${f(cardTop)}');
  print('houseRect        = ${r(house)}  (w=${f(house.width)}, h=${f(house.height)}, '
      'top−卡顶=${f(house.top - cardTop)}, bottom−卡顶=${f(house.bottom - cardTop)})');
  print('energyDotRect(0) = ${r(dot0)}  center.dx=${f(dot0.center.dx)}, '
      'top−卡顶=${f(dot0.top - cardTop)}');
  print('energyDotRect(1) = ${r(dot1)}  center.dx=${f(dot1.center.dx)}');
  print('dot 组合中点      = ${f((dot0.left + dot1.right) / 2)}  '
      '(= house.center.dx + kGuardEnergyDotAnchorDx)');
  print('soldierRect      = ${r(soldier)}  (w=${f(soldier.width)}, '
      'h=${f(soldier.height)}, top−卡顶=${f(soldier.top - cardTop)})');
  print('──────────────────────────────────────────────────');
}

void main() {
  // ── ① 卡不被视口裁剪（v6 的核心硬断言）────────────────────────────────
  group('① 卡不被 ListView 视口裁剪（B10/B1 的硬断言）', () {
    testWidgets('卡顶 ≥ 视口顶边；卡顶到屋顶 == padTop(14)；房子四边全在卡内',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);
      await _pumpUntil(tester, find.byKey(GuardSceneCard.cardKey));

      final Rect viewport = tester.getRect(find.byType(ListView));
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      // 统计卡（第一张卡「今日获取阳光」的标签）—— B10 连带上移 12pt 的观测点。
      final Rect stat = tester.getRect(find.text('今日获取阳光'));

      print('── B11 三个 y ───────────────────────────────────');
      print('viewport.top = ${viewport.top.toStringAsFixed(2)}');
      print('card.top     = ${card.top.toStringAsFixed(2)}');
      print('house.top    = ${house.top.toStringAsFixed(2)}');
      print('statCard.top = ${stat.top.toStringAsFixed(2)}  '
          '(相对卡顶 ${(stat.top - card.top).toStringAsFixed(2)} = '
          '卡 112 + 间距 10 + 卡内标签内边距 14)');
      print('屋顶 − 卡顶  = ${(house.top - card.top).toStringAsFixed(2)}');
      print('────────────────────────────────────────────────');

      // 统计卡：卡(112) + 卡后间距(10) + 标签内边距(14) ⇒ 相对卡顶 136。
      // 🔴 「累计上移 22pt」的算法（相对 B9 基线，不依赖旧代码即可复核）：
      //   B9 ：视口顶 371.12 + 卡 108 + 间距 10 + 14 = 503.12
      //   B10：视口顶 355.12 + 卡 112 + 间距 10 + 14 = 491.12 ⇒ −12.00
      //   B11：视口顶 345.12 + 卡 112 + 间距 10 + 14 = 481.12 ⇒ **−22.00**
      //   （视口顶累计上移 16 + 10 = 26 = kGuardCardLift，卡高多了 4 = padTop 10 → 14）
      expect(stat.top - card.top, closeTo(136, 1.5),
          reason: '🔴 B10 连带：统计卡相对卡顶上移（卡高 112+10+14）');

      // 🔴 硬断言（旧实现 Transform 版必红：卡顶 = 视口顶 − 16）。
      expect(card.top, greaterThanOrEqualTo(viewport.top - 0.01),
          reason: '🔴 卡顶不许高于视口顶边 —— 否则屋顶被 ClipRect 削掉（B9 的真机 bug）');
      expect(card.top, closeTo(viewport.top, 0.5),
          reason: '🔴 上移量改由「缩上方 sceneGap」实现 ⇒ 卡顶 == 视口顶边');
      expect(card.height, closeTo(kGuardSceneCardHeight, 0.5),
          reason: '卡高恒 112（padTop 14 + 房子 88 + padBottom 10）');

      // 屋顶到卡顶 = padTop（玄参验收：视觉留白 14pt）。
      expect(house.top - card.top, closeTo(14, 0.5),
          reason: '🔴 卡顶到屋顶 == kGuardCardPadTop = 14');
      expect(house.top, greaterThanOrEqualTo(card.top - 0.01),
          reason: '房子不许越过卡顶（越过就等于被裁）');
      expect(house.bottom, lessThanOrEqualTo(card.bottom + 0.01),
          reason: '房子底边不许越过卡底');
      expect(house.left, greaterThanOrEqualTo(card.left - 0.01),
          reason: '房子左边在卡内');
      expect(house.right, lessThanOrEqualTo(card.right + 0.01),
          reason: '房子右边在卡内');
    });
  });

  // ── ② 六值 dump ──────────────────────────────────────────────────────
  group('② 真机尺寸夹具六值（390 屏 / 卡宽 390）', () {
    testWidgets('MediaQuery / cardWidth / scale / houseRect / energyDotRect / soldierRect',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);
      await _pumpUntil(tester, find.byKey(GuardSceneCard.cardKey));

      final double mediaWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final GuardCardLayout layout = GuardCardLayout(card.width);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect dot0 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(0)));
      final Rect dot1 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(1)));
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));

      _dumpSix(
        mediaWidth: mediaWidth,
        cardWidth: card.width,
        scale: layout.scale,
        cardTop: card.top,
        house: house,
        dot0: dot0,
        dot1: dot1,
        soldier: soldier,
      );

      // 写死真值（±0.5）—— 任何一项漂移都必须红。
      // 横向是**卡内绝对量**（卡满宽贴边 ⇒ 与屏幕坐标相同）；纵向用「相对卡顶」。
      expect(mediaWidth, closeTo(390, 0.01), reason: '真机尺寸 = 390 逻辑宽');
      expect(card.width, closeTo(390, 0.5), reason: '卡宽 = 屏宽（满宽贴边）');
      expect(layout.scale, 1.0, reason: '390 > 380 ⇒ scale 必须 1.0（不许误判成 0.85）');
      expect(house.left, closeTo(0, 0.5), reason: '房子左边贴屏幕左缘');
      expect(house.top - card.top, closeTo(14, 0.5), reason: '房子顶 − 卡顶 = padTop 14');
      expect(house.right, closeTo(156.16, 0.5), reason: '房子宽 156.16');
      expect(house.bottom - card.top, closeTo(102, 0.5), reason: '房子高 88（14 → 102）');
      expect(house.center.dx, closeTo(78.08, 0.5),
          reason: '🔴 花园中轴 78.08（C2 锚点基准）');
      expect(dot0.left, closeTo(81.08, 0.5),
          reason: '点组合左端 = 78.08 + 20 − 17（B11 锚点 +20）');
      expect(dot0.top - card.top, closeTo(14, 0.5), reason: '点顶边钉房顶线 = padTop 14');
      expect(dot1.right, closeTo(115.08, 0.5),
          reason: '点组合右端 = 78.08 + 20 + 17');
      expect(soldier.left, closeTo(158.16, 0.5),
          reason: '战士左 = 房子右 + 2');
      expect(soldier.right, closeTo(226.16, 0.5));
      expect(soldier.top - card.top, closeTo(34, 0.5), reason: '战士顶 = 102 − 68');
      expect(soldier.bottom - card.top, closeTo(102, 0.5),
          reason: '战士底 == 房子基线');
    });
  });

  // ── ③ C1 战士 68 ─────────────────────────────────────────────────────
  group('③ C1 战士 68（真机尺寸夹具）', () {
    testWidgets('正方形 68×68、底边踩房子基线、间隙 2、绘制框 113.33',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);
      await _pumpUntil(tester, find.byKey(GuardSceneCard.cardKey));

      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));

      expect(soldier.width, closeTo(68, 0.5), reason: '🔴 战士边长 68');
      expect(soldier.height, closeTo(68, 0.5), reason: '🔴 正方形（攻击帧不拖累跑道）');
      expect(soldier.bottom, closeTo(house.bottom, 0.5),
          reason: '脚底踩同一条基线');
      expect(soldier.left - house.right, closeTo(2, 0.5),
          reason: '🔴 soldierHouseGap = 2');

      final Size draw = tester.getSize(find.descendant(
        of: find.byKey(GuardSceneCard.soldierKey),
        matching: find.byType(FrameSequencePlayer),
      ));
      expect(draw.width, closeTo(113.33, 0.5),
          reason: '🔴 绘制框 = 68 × 5/3（横向溢出放行，攻击帧不被裁）');
      expect(draw.height, closeTo(68, 0.5), reason: '绘制高度 = 战士 68');
    });
  });

  // ── ④ C2 能量点 ──────────────────────────────────────────────────────
  group('④ C2 能量点 14 / gap 6（组合锚花园中轴）', () {
    testWidgets('直径 14、间距 6、组合中点 == house.center.dx + 锚点常量',
        (WidgetTester tester) async {
      final _Env env = await _makeEnv();
      await _seedPlant(env);
      await _pumpToday(tester, env);
      await _pumpUntil(tester, find.byKey(GuardSceneCard.cardKey));

      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect dot0 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(0)));
      final Rect dot1 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(1)));

      expect(dot0.width, closeTo(14, 0.5), reason: '🔴 直径 18 → 14');
      expect(dot0.height, closeTo(14, 0.5));
      expect(dot1.left - dot0.right, closeTo(6, 0.5), reason: '🔴 gap 8 → 6');
      expect((dot0.left + dot1.right) / 2,
          closeTo(house.center.dx + kGuardEnergyDotAnchorDx, 0.5),
          reason: '🔴 锚点 = house.center.dx + kGuardEnergyDotAnchorDx');
      expect((dot0.center.dx + dot1.center.dx) / 2,
          closeTo(house.center.dx + kGuardEnergyDotAnchorDx, 0.5),
          reason: '🔴 两个**圆心**的中点同样锚在花园中轴（玄参按截图量的就是这个量）');

      // 常量本身：B11 玄参拍板 +20（美学位移，不是几何修正 —— 见文件头）。
      expect(kGuardEnergyDotAnchorDx, 20,
          reason: '🔴 玄参第六轮：整组点再往右让 20pt（唯一旋钮）');
      expect(house.center.dx + kGuardEnergyDotAnchorDx, closeTo(98.08, 0.5),
          reason: '🔴 生效锚点 98.08（两点圆心中点）');
    });

    test('纯值类：两点组合宽 34、左端 = 中心 − 17（390 / 320 两档）', () {
      const GuardCardLayout wide = GuardCardLayout(390);
      final Rect w0 = wide.energyDotRect(0);
      final Rect w1 = wide.energyDotRect(1);
      expect(w1.right - w0.left, closeTo(34, 0.001));
      expect(w0.left,
          closeTo(wide.houseRect.center.dx + kGuardEnergyDotAnchorDx - 17, 0.001),
          reason: '🔴 B11 锚点 +20 ⇒ 左端 = 中轴 + 20 − 17 = 81.08');

      const GuardCardLayout narrow = GuardCardLayout(320);
      final Rect n0 = narrow.energyDotRect(0);
      final Rect n1 = narrow.energyDotRect(1);
      expect(n1.right - n0.left, closeTo(34 * 0.85, 0.001),
          reason: '窄卡等比缩：34 × 0.85 = 28.9');
      expect(n0.left,
          closeTo(
              narrow.houseRect.center.dx +
                  kGuardEnergyDotAnchorDx * 0.85 -
                  17 * 0.85,
              0.001),
          reason: '窄卡：锚点偏移也按 0.85 缩');
    });
  });
}
