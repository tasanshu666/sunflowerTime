/// 守卫战 v2 · **布局不变量护栏**（B6 裁定 v2 立、B7 裁定 v3 后**仍然成立**的那些）。
///
/// 真源：`guard_card_layout.dart`（几何单一来源）+ `guard_scene_card.dart`
/// （草地板 / contain 房子 / 常驻战士 / 图标钮）+ `guard_battle_field.dart`
/// （镜像映射）+ `guard_tutorial_sheet.dart`（居中弹层）。
///
/// ## B7 之后本文件保留什么（逐条）
/// | # | 断言 | 状态 |
/// |---|---|---|
/// | ① | 元素**尺寸跨屏宽逐位相等**，只有通道宽度差 = 卡宽差 | 保留（B7 放大后仍须成立） |
/// | ② | 房子完整可见：矩形在卡内 + 宽高比 ≈ 1.7746 + `BoxFit.contain` | 保留 |
/// | ③ | **镜像**：怪 x 随时间减小；子弹 x 随时间增大且 > 战士右缘 | 保留（开火改经手柄） |
/// | ④ | 草地板宽 = 卡宽（横向可拉伸） | 保留 |
/// | ⑤ | ❌ **已删**：状态文案底衬 + WCAG 对比度 | B7「卡内减法」把状态文案整个搬进 `Semantics.label`，卡面**零文本** ⇒ 底衬与对比度失去对象（护栏对象消失，不是放宽阈值） |
/// | ⑥ | en 下开始按钮 ≤ 120pt 且按钮内无 `Text` | 保留 |
/// | ⑦ | 教学浮层**屏幕居中** | 保留 |
/// | ⑧ | 320×568 + en + 1.3：待机 / 战斗两态零 overflow | 保留 |
///
/// ## 🔴 为什么尺寸断言要用 **358 / 992** 两档
/// 卡宽 ≤ 380 会进「窄卡等比缩」（×0.85；B7 新增，B8.1 阈值 340→380）—— 那一档的元素尺寸**本来就
/// 该不同**，它的护栏在 `guard_scene_card_layout_v3_test.dart` 的 ⑦。
///
/// 🔴 全文件有界 `pump`（战斗层 ticker + 帧序列动画常驻，绝不 `pumpAndSettle`）。
library guard_scene_card_layout_v2_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_battle_field.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show deriveGuardBattleScript;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_tutorial_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
// ═══════════════════════════════════════════════════════════════════════

/// 构造一份守卫快照（widget 级用例不碰服务）。
GuardTodayView _view(GuardPillMode mode, {int energy = 2, double balance = 0}) {
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
      thiefKind: mode == GuardPillMode.absent ? null : GuardThiefKind.sunRat,
      winSun: 2,
    ),
    energyAvailable: energy,
    balance: balance,
  );
}

/// 把场景卡挂在 [cardWidth] 宽的槽位里。
///
/// 🔴 必须同时把 **view 尺寸**放到 [screenWidth]：`SizedBox(width: 992)` 在只有
/// 800pt 宽的测试视口里会被父约束夹到 800（B6 踩过这个坑 —— 宽卡实际只拿到
/// 798pt，通道差值恒差 192pt）。
///
/// [handle] 非空时注入给卡（B7：卡内已无开火钮，widget 级用例经手柄开火）。
Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  GuardPillMode mode = GuardPillMode.pendingFree,
  double textScale = 1.0,
  bool english = false,
  double screenWidth = 320,
  VoidCallback? onStart,
  GuardBattleHandle? handle,
}) async {
  tester.view.physicalSize = Size(screenWidth, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: english ? const Locale('en') : const Locale('zh'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: cardWidth,
            child: GuardSceneCard(
              view: _view(mode),
              dayKey: '2026-11-10',
              childId: 'seed-0',
              onStart: onStart ?? () {},
              battleHandle: handle,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 卡内某 Key 的矩形（相对屏幕；卡本身也在屏幕里 ⇒ 差值口径一致）。
Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

/// 通道宽度（实测口径）：用**渲染出来的**卡内宽喂给几何，再减去实测战士右缘。
///
/// 战斗态右簇格是**空的**（B7 删了卡内开火钮），所以不能再像 v2 那样靠
/// 「右簇左缘 − 战士右缘」量 —— 改成「几何算出的通道右端 − 实测战士右缘」，
/// 同时钉住「战士右缘 == 几何的 channelLeft」（见用例 ①）。
double _channelWidth(WidgetTester tester) {
  final Rect card = _rect(tester, GuardSceneCard.cardKey);
  // B8/A4：卡根已无描边 ⇒ 卡内可用宽 == 卡宽（不再减 2）。
  final GuardCardLayout layout = GuardCardLayout(card.width);
  // 🔴 B9/C3：通道左端已改成「战士右缘 − 半个怪」（怪半个身子压住战士才停），
  // 不再等于战士右缘 ⇒ 「几何单一来源」改为**整个战士矩形**逐一比对。
  final Rect soldier = _rect(tester, GuardSceneCard.soldierKey);
  expect(soldier.left, closeTo(card.left + layout.soldierRect.left, 0.6),
      reason: '实测战士左缘必须等于几何的 soldierRect.left（几何单一来源）');
  expect(soldier.right, closeTo(card.left + layout.soldierRect.right, 0.6),
      reason: '实测战士右缘必须等于几何的 soldierRect.right（几何单一来源）');
  return layout.channelWidth;
}

// ═══════════════════════════════════════════════════════════════════════

void main() {
  // ── ① 元素固定 / 通道弹性 ────────────────────────────────────────────
  group('① 元素固定 / 通道弹性', () {
    testWidgets('房子 + 开始钮：390 卡 vs 1024 卡 尺寸逐位相等', (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390, screenWidth: 390);
      final Size houseSmall = tester.getSize(find.byKey(GuardSceneCard.houseKey));
      final Size buttonSmall =
          tester.getSize(find.byKey(GuardSceneCard.startButtonKey));

      await _pumpCard(tester, cardWidth: 1024, screenWidth: 1024);
      final Size houseWide = tester.getSize(find.byKey(GuardSceneCard.houseKey));
      final Size buttonWide =
          tester.getSize(find.byKey(GuardSceneCard.startButtonKey));

      expect(houseWide, houseSmall,
          reason: '🔴 房子尺寸必须跨屏宽逐位相等（iPad 只拉长通道）');
      expect(buttonWide, buttonSmall,
          reason: '🔴 开始钮尺寸必须跨屏宽逐位相等');
      // 字面量核对（防止「两个都错成同一值」）。
      expect(houseSmall.height, closeTo(GuardCardLayout.houseHeight, 0.01));
      expect(buttonSmall.width, closeTo(GuardCardLayout.rightClusterSize, 0.01));
    });

    testWidgets('战士 + 小怪：390 卡 vs 1024 卡 尺寸逐位相等', (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 390, screenWidth: 390, mode: GuardPillMode.fighting);
      final Size soldierSmall =
          tester.getSize(find.byKey(GuardSceneCard.soldierKey));
      final Size monsterSmall = tester
          .getSize(find.byKey(GuardBattleField.monsterKey(0)));

      await _pumpCard(tester,
          cardWidth: 1024, screenWidth: 1024, mode: GuardPillMode.fighting);
      final Size soldierWide =
          tester.getSize(find.byKey(GuardSceneCard.soldierKey));
      final Size monsterWide =
          tester.getSize(find.byKey(GuardBattleField.monsterKey(0)));

      expect(soldierWide, soldierSmall, reason: '🔴 战士尺寸必须跨屏宽逐位相等');
      expect(monsterWide, monsterSmall, reason: '🔴 小怪尺寸必须跨屏宽逐位相等');
      expect(soldierSmall.width, closeTo(GuardCardLayout.soldierSize, 0.01));
      // 🔴 B13：战斗怪的种类**跟当日小偷走**（_kindOfThief）——
      // dayKey '2026-11-10' / 'seed-0' 的战局种类由脚本派生，宽度按该种反解。
      final String kindId = deriveGuardBattleScript(
              dayKey: '2026-11-10', childId: 'seed-0')
          .monsters
          .first
          .kind
          .id;
      expect(monsterSmall.width,
          closeTo(const GuardCardLayout(390).monsterWidthOf(kindId), 0.01));
    });

    testWidgets('通道宽度差 = 卡宽差（±2）', (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 390, screenWidth: 390, mode: GuardPillMode.fighting);
      final double small = _channelWidth(tester);

      await _pumpCard(tester,
          cardWidth: 1024, screenWidth: 1024, mode: GuardPillMode.fighting);
      final double wide = _channelWidth(tester);

      expect(wide - small, closeTo(1024 - 390, 2.0),
          reason: '🔴 唯一随屏宽变化的是通道（宽卡只拉长战斗区）');
      // 🔴 B13.2：通道左端 = 战士右缘 − 半个怪（战士 60）⇒ 390 屏实测 117.84pt。
      expect(small, closeTo(117.84, 0.6), reason: '🔴 实测 390 卡通道');
    });
  });

  // ── ② 房子完整可见（contain 不裁切）──────────────────────────────────
  group('② 房子完整可见', () {
    testWidgets('房子矩形在卡内 + 宽高比 ≈ 1.7746（±2%）+ BoxFit.contain',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 288);
      final Rect card = _rect(tester, GuardSceneCard.cardKey);
      final Rect house = _rect(tester, GuardSceneCard.houseKey);

      expect(card.contains(house.topLeft) &&
          card.contains(house.bottomRight - const Offset(0.01, 0.01)), isTrue,
          reason: '🔴 房子必须完整落在卡内（不得被卡裁切）');
      expect(house.width / house.height,
          closeTo(kGuardHouseAspectRatio, 0.02 * kGuardHouseAspectRatio),
          reason: '🔴 contain 未裁切 ⇒ 渲染宽高比必须 ≈ 素材 1.7746');

      final Image img = tester.widget<Image>(
        find.descendant(
          of: find.byKey(GuardSceneCard.houseKey),
          matching: find.byType(Image),
        ),
      );
      expect(img.fit, BoxFit.contain,
          reason: '🔴 房子必须 contain（cover 在 iPad 上会裁掉 75%）');
    });
  });

  // ── ③ 镜像：怪自右向左、子弹向右 ─────────────────────────────────────
  group('③ 镜像方向（渲染层，sim 零改动）', () {
    testWidgets('怪 x 随时间减小；子弹 x 随时间增大且 > 战士右缘',
        (WidgetTester tester) async {
      final GuardBattleHandle handle = GuardBattleHandle();
      await _pumpCard(tester,
          cardWidth: 900,
          screenWidth: 1000,
          mode: GuardPillMode.fighting,
          handle: handle);

      // t=2s：第 0 只怪（spawn 0s，m1 = 13pt/s ⇒ sim x≈26）
      await tester.pump(const Duration(seconds: 2));
      final Rect m2 = _rect(tester, GuardBattleField.monsterKey(0));

      // t=4s：sim x≈52 ⇒ 镜像后屏幕 x 更小（向左移动）
      await tester.pump(const Duration(seconds: 2));
      final Rect m4 = _rect(tester, GuardBattleField.monsterKey(0));
      expect(m4.left, lessThan(m2.left),
          reason: '🔴 小怪必须自右向左进攻（旧实现是从左往右）');

      // 开火：弹着点在怪身上（怪在右侧）⇒ 屏幕上子弹向**右**飞
      final Rect soldier = _rect(tester, GuardSceneCard.soldierKey);
      handle.fire();
      await tester.pump(const Duration(milliseconds: 16));
      final Rect b1 = _rect(tester, GuardBattleField.bulletKey(0));
      expect(b1.left, greaterThan(soldier.right - 1),
          reason: '🔴 子弹必须从战士右侧（枪口）出发');

      await tester.pump(const Duration(milliseconds: 100));
      final Rect b2 = _rect(tester, GuardBattleField.bulletKey(0));
      expect(b2.left, greaterThan(b1.left),
          reason: '🔴 子弹必须向右飞（镜像方向与旧实现相反）');
    });
  });

  // ── ④ 草地板横向可拉伸 ────────────────────────────────────────────────
  group('④ 草地板拉伸', () {
    testWidgets('底衬宽 = 卡宽（320 / 1024 两宿主），差值 = 卡宽差',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 320, screenWidth: 320);
      final double backdropSmall =
          tester.getSize(find.byKey(GuardSceneCard.backdropKey)).width;
      final double cardSmall =
          tester.getSize(find.byKey(GuardSceneCard.cardKey)).width;

      await _pumpCard(tester, cardWidth: 1024, screenWidth: 1024);
      final double backdropWide =
          tester.getSize(find.byKey(GuardSceneCard.backdropKey)).width;

      // B8/A4：无描边 ⇒ 草地板宽 == 卡宽（逐位相等）。
      expect(backdropSmall, closeTo(cardSmall, 0.01),
          reason: '🔴 草地板必须铺满整张卡（无边到边留白）');
      expect(backdropWide - backdropSmall, closeTo(1024 - 320, 1.0),
          reason: '🔴 草地板随卡宽拉伸（程序化，不会像位图那样被裁）');
    });
  });

  // ── ⑥ 英文按钮预算 ────────────────────────────────────────────────────
  group('⑥ en 开始按钮 ≤ 120pt 且无文案截断', () {
    testWidgets('图标钮 64pt；按钮内无 Text（不存在截断风险）', (WidgetTester tester) async {
      await _pumpCard(tester,
          cardWidth: 288, english: true, textScale: 1.3);

      final Size button =
          tester.getSize(find.byKey(GuardSceneCard.startButtonKey));
      expect(button.width, lessThanOrEqualTo(120),
          reason: '🔴 en 下开始钮宽必须 ≤ 120pt（旧实现 188.8pt 吃掉 53% 卡宽）');
      expect(
        find.descendant(
          of: find.byKey(GuardSceneCard.startButtonKey),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: '🔴 图标钮：文案不参与布局 ⇒ 任何语言都不会截断（a11y 名称走 Semantics）',
      );
      // 语义名仍在（读屏可读），且与 ARB 同源。
      expect(
        tester.getSemantics(find.byKey(GuardSceneCard.startButtonKey)).label,
        isNotEmpty,
        reason: '图标钮必须保留无障碍名称（guard_scene_start）',
      );
    });
  });

  // ── ⑦ 弹层居中 ────────────────────────────────────────────────────────
  group('⑦ 教学浮层屏幕居中', () {
    testWidgets('点开始 → 教学卡中心 ≈ 屏幕中心（≤ 8pt），不是底部抽屉',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('openTutorial'),
                  onPressed: () => showGuardTutorialSheet(
                    context: ctx,
                    l10n: AppLocalizations.of(ctx),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('openTutorial')));
      // 200ms 转场：有界推进（不 pumpAndSettle）。
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byKey(kGuardTutorialSheetKey), findsOneWidget);
      final Rect card = tester.getRect(find.byKey(kGuardTutorialCardKey));
      const Offset screenCenter = Offset(390 / 2, 844 / 2);
      expect((card.center - screenCenter).distance, lessThanOrEqualTo(8),
          reason: '🔴 教学卡必须屏幕居中（底部抽屉的卡心会偏下 200pt 以上）');
      // 反证：不是底部抽屉（卡底明显高于屏幕底）。
      expect(card.bottom, lessThan(844 - 100),
          reason: '🔴 底部抽屉形态的卡会贴屏幕底（本断言直接排除）');
    });
  });

  // ── ⑧ 最坏组合不溢出 ──────────────────────────────────────────────────
  group('⑧ 320×568 + en + 1.3：两态零 overflow', () {
    for (final GuardPillMode mode in <GuardPillMode>[
      GuardPillMode.pendingFree,
      GuardPillMode.fighting,
    ]) {
      testWidgets('$mode', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _pumpCard(tester,
            cardWidth: 288, mode: mode, english: true, textScale: 1.3);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull,
            reason: '🔴 320×568 + en + 1.3 下 $mode 不得溢出');
        expect(tester.getRect(find.byKey(GuardSceneCard.cardKey)).height,
            closeTo(kGuardSceneCardHeight, 0.5),
            reason: '卡高恒 112（B10 布局 v6；不随字号 / 窄卡缩放）');
      });
    }
  });

  // ── 布局纯函数（几何单一来源的自检）───────────────────────────────────
  group('⑨ GuardCardLayout 纯函数', () {
    test('360 卡：通道宽 = 卡宽 − 固定簇；sim 映射双向单调', () {
      const GuardCardLayout l = GuardCardLayout(360);
      // 🔴 B9/C3：360 卡落在窄卡档（阈值 380）⇒ 元素 ×0.85。
      // 右侧固定 = (8 + 64 + 4) × 0.85 = 64.6 ⇒ channelRight = 295.4；
      // 左侧 = 房子右缘 132.74 + 间隙 1.7 + 战士 51.0 − 半个怪 18.7 = 166.74
      // ⇒ 跑道 **128.66**（B13.2：战士 64 → 60，跑道再 +3.4）。
      expect(l.channelWidth, closeTo(128.66, 0.05));
      expect(l.scale, 0.85, reason: '🔴 360 ≤ 380 ⇒ 走窄卡等比缩');
      // 镜像：sim x 增大 ⇒ 屏幕 x 减小
      expect(l.mapMonsterX(0), closeTo(l.channelRight, 0.01));
      expect(l.mapMonsterX(330), closeTo(l.channelLeft, 0.01));
      expect(l.mapMonsterX(165), greaterThan(l.mapMonsterX(330)));
      // 🔴 B7：怪的纵向区间是**围绕战士中心**的一条窄带（2D 同平面）。
      // B8.1 起 360 是窄卡（s = 0.85）⇒ 带宽半高 8 × 0.85 = **6.8**。
      // 🔴 B13.2：带**底部**有渲染安全钳（最低点 + 半个怪不压倒计时细线），
      // 顶部照旧；判据写成护栏式（不抄实现数值）。
      expect(l.mapMonsterY(10), closeTo(l.soldierCenterY - 6.8, 0.01),
          reason: '🔴 带顶部照旧（钳只向下）');
      final double monsterBottom =
          l.mapMonsterY(80) + l.monsterExtent / 2;
      expect(monsterBottom, lessThanOrEqualTo(l.countdownRect.top - 1),
          reason: '🔴 B13.2 渲染安全钳：怪的最低点必须让开卡底倒计时细线');
      expect(monsterBottom, lessThanOrEqualTo(l.cardHeight),
          reason: '怪必须完整落在卡内');
    });

    test('通道宽度在极窄卡上钳到 0（不出现负数矩形）', () {
      const GuardCardLayout l = GuardCardLayout(200);
      expect(l.channelWidth, 0);
      expect(l.mapMonsterX(0), l.channelLeft);
    });
  });
}
