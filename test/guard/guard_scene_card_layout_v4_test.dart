/// 守卫战 v2 · **B8 布局 v4 裁定护栏**（玄参 2026-11-10 第三轮真机复验）。
///
/// 真源：`guard_card_layout.dart`（v4 几何单一来源）+ `guard_scene_card.dart`
/// （108 卡高 / 能量点回归 / 去外框 / 战士栅栏外）+ `guard_art.dart`
/// （idle 帧色彩归一后的素材）。
///
/// ## 覆盖（逐条对应 B8 的 A1~A5）
/// | # | 断言 |
/// |---|---|
/// | ① | 卡高 **112** 字面量（B10：padTop 14）；房子顶 14 / 基线 102 / 倒计时细线在卡内 |
/// | ② | 战士**在栅栏外**：`soldier.left − house.right == 2`（B9 裁边后才是真 2pt）且底边同高 |
/// | ③ | 能量点 ×2：**14pt（B10）**、**顶边与房顶线齐平（dot.top == 14 ≥ house.top）**；亮/灭两态 |
/// | ④ | **无外框**：卡根不是 Container、卡内无 ClipRRect、无带 border 的 Container |
/// | ⑤ | 素材亮度归一：idle frame001 与 attack 的平均亮度差 ≤ **5%**（字面量阈值） |
/// | ⑥ | 通道宽度（B13.2：战士 60）：320/360/375/390/1024 = 88.66/128.66/143.66/117.84/751.84 |
///
/// 🔴 全文件有界 `pump`（常驻战士帧序列 / 战斗 ticker 都在跑，绝不 `pumpAndSettle`）。
library guard_scene_card_layout_v4_test;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具
// ═══════════════════════════════════════════════════════════════════════

GuardTodayView _view(GuardPillMode mode, {int energy = 2, bool isPremium = false}) {
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
    isPremium: isPremium,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required double cardWidth,
  double screenWidth = 390,
  GuardPillMode mode = GuardPillMode.pendingFree,
  int energy = 2,
  // 🔴 B13.8 能量档位制：缺省 false（免费档，第 2 颗恒锁标）。
  bool isPremium = false,
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
              view: _view(mode, energy: energy, isPremium: isPremium),
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

/// 读一张素材的「平均亮度」（alpha ≥ 16 的像素，Rec.709 权重）。
///
/// 直接在测试里解码真实素材 —— 这样「待机帧偏暗」这件事由**产物本身**说话，
/// 不靠管线自报的数字（防「管线说改好了、资产其实没换」）。
///
/// 🔴 `ImageByteFormat.rawRgba` 是**预乘 alpha** 的：半透明边缘像素会被
/// alpha 压暗。待机帧带一圈柔光/阴影（半透明像素多），若不还原就会量出
/// 「待机 121 vs 攻击 156」这种假差距（实测差 22%）。故这里逐像素**反预乘**
/// （`c' = c × 255 / a`）再求均值，与管线（PIL，直通 alpha）同口径。
Future<double> _meanLuma(String asset) async {
  final ByteData data = await rootBundle.load(asset);
  final ui.Codec codec =
      await ui.instantiateImageCodec(data.buffer.asUint8List());
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ByteData? raw =
      await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: '素材解码失败：$asset');
  final Uint8List px = raw!.buffer.asUint8List();
  double rs = 0;
  double gs = 0;
  double bs = 0;
  int n = 0;
  for (int i = 0; i + 3 < px.length; i += 4) {
    final int a = px[i + 3];
    if (a < 16) continue;
    // 反预乘（a == 255 时是恒等变换）。
    final double k = 255.0 / a;
    rs += (px[i] * k).clamp(0.0, 255.0);
    gs += (px[i + 1] * k).clamp(0.0, 255.0);
    bs += (px[i + 2] * k).clamp(0.0, 255.0);
    n++;
  }
  frame.image.dispose();
  codec.dispose();
  expect(n, greaterThan(0), reason: '素材全透明：$asset');
  return 0.2126 * (rs / n) + 0.7152 * (gs / n) + 0.0722 * (bs / n);
}

void main() {
  // ── ① 卡高 108 ────────────────────────────────────────────────────────
  group('① 卡高 112（B10：padTop 14，房子 88 + 底衬 10）', () {
    testWidgets('卡高恒 112；房子顶 14、基线 102、倒计时细线在卡内',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      expect(card.height, closeTo(112, 0.01), reason: '🔴 B10 字面量 112');

      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      // 卡内坐标（相对卡左上角）。
      expect(house.top - card.top, closeTo(14, 0.5),
          reason: '🔴 房子顶 = 112 − padBottom 10 − 房子 88 = 14');
      expect(house.bottom - card.top, closeTo(102, 0.5),
          reason: '🔴 基线 = 112 − 10 = 102');
    });

    test('纯值类口径：390 / 320 / 1024 卡高都是 112（不随屏宽缩）', () {
      for (final double w in <double>[390, 320, 1024]) {
        expect(const GuardCardLayout(390).cardHeight, 112);
        expect(GuardCardLayout(w).cardHeight, 112);
      }
      // 倒计时细线：高 4、距卡底 6 ⇒ 落在 [102, 106]，不越出卡。
      const GuardCardLayout l = GuardCardLayout(390);
      expect(l.countdownRect.top, closeTo(102, 0.01));
      expect(l.countdownRect.bottom, closeTo(106, 0.01));
      expect(l.countdownRect.bottom, lessThanOrEqualTo(l.cardHeight));
    });

    test('🔴 卡高是**派生值**：padTop 14 + 房子 88 + padBottom 10 = 112', () {
      // 字面量：三个来源常量各写一个数（不是互相反算）。
      expect(kGuardCardPadTop, 14);
      expect(kGuardCardHouseHeight, 88);
      expect(kGuardCardPadBottom, 10);
      // 求和等于卡高 —— 这条就是「禁止两套账」的护栏：
      // 谁改了房子高度 / 留白却忘了卡高，本行立刻红。
      expect(kGuardCardPadTop + kGuardCardHouseHeight + kGuardCardPadBottom, 112);
      expect(kGuardSceneCardHeight, 112);
      // 布局类的三个来源常量与 prd_params 同源（引用而不是复制）。
      expect(GuardCardLayout.padTop, 14);
      expect(GuardCardLayout.houseHeight, 88);
      expect(GuardCardLayout.padBottom, 10);
      // 屋顶 = 卡高 − 底衬 − 房子：宽卡上逐位等于 padTop。
      expect(const GuardCardLayout(390).houseTopY, closeTo(14, 0.001));
      expect(const GuardCardLayout(1024).houseTopY, closeTo(14, 0.001));
      // 窄卡：只缩元素不缩卡高 ⇒ 屋顶下移到 24.7（多出的空留在卡顶）。
      expect(const GuardCardLayout(320).houseTopY, closeTo(28.7, 0.01));
      expect(const GuardCardLayout(320).cardHeight, 112,
          reason: '🔴 窄卡绝不改卡高（今日页滚动预算才稳）');
    });
  });

  // ── ② 战士在栅栏外 ────────────────────────────────────────────────────
  group('② 战士挪到房子右侧栅栏外', () {
    testWidgets('soldier.left ≥ house.right + 2，且与房子同一条基线',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect soldier =
          tester.getRect(find.byKey(GuardSceneCard.soldierKey));

      expect(soldier.left, greaterThan(house.right),
          reason: '🔴 战士必须站在栅栏**外**（v3 是压进房子 6pt）');
      expect(soldier.left - house.right, closeTo(2, 0.51),
          reason: '🔴 栅栏间隙 = 2pt（B9：裁边后 2 才是肉眼 2，旧 6pt 肉眼是 23pt）');
      expect(soldier.bottom, closeTo(house.bottom, 0.01),
          reason: '🔴 脚底踩同一条基线（站在草地上，不是浮空）');
    });

    test('纯值类口径：窄卡 0.85 下栅栏间隙同比缩', () {
      const GuardCardLayout wide = GuardCardLayout(390);
      const GuardCardLayout narrow = GuardCardLayout(320);
      expect(wide.soldierRect.left - wide.houseRect.right, closeTo(2, 0.01));
      expect(narrow.soldierRect.left - narrow.houseRect.right,
          closeTo(2 * 0.85, 0.01));
      expect(narrow.soldierRect.bottom, closeTo(narrow.houseRect.bottom, 0.01));
    });
  });

  // ── ③ 能量点回归 ──────────────────────────────────────────────────────
  group('③ 能量点（房子右侧 / 栅栏上方）', () {
    testWidgets('🔴 B8.1 点顶边与房顶线齐平：dot.top == 10 且 ≥ house.top',
        (WidgetTester tester) async {
      // 玄参原话：「能量点显示在家园花园的上方，**不好超出房子的高度**」。
      // ⇒ 圆点整体必须落在房子图**之内或之下**：顶边 ≥ 房顶线（不许飘在图上）。
      // 写死数字（10 / 房顶 10），不引用常量 —— 常量被改错时本断言必须红。
      await _pumpCard(tester, cardWidth: 390);
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      expect(house.top - card.top, closeTo(14, 0.01), reason: '房顶线在卡内 y=14');

      for (int i = 0; i < 2; i++) {
        final Rect dot =
            tester.getRect(find.byKey(GuardSceneCard.energyDotKey(i)));
        expect(dot.top - card.top, closeTo(14, 0.01),
            reason: '🔴 点顶边必须与房顶线齐平（= 14，不许探出房顶）');
        expect(dot.top, greaterThanOrEqualTo(house.top - 0.01),
            reason: '🔴 零像素出界：dot.top ≥ house.top');
        expect(dot.bottom - card.top, closeTo(28, 0.01),
            reason: '点底边 = 14 + 14 = 28（仍在房顶线以下一个直径内）');
      }
    });

    testWidgets('两个 14pt 圆点都在卡内，且不高于房顶线',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final Rect house = tester.getRect(find.byKey(GuardSceneCard.houseKey));

      for (int i = 0; i < 2; i++) {
        final Rect dot =
            tester.getRect(find.byKey(GuardSceneCard.energyDotKey(i)));
        expect(dot.width, closeTo(14, 0.01), reason: '🔴 能量点直径 14（B10）');
        expect(dot.height, closeTo(14, 0.01));
        expect(dot.top, greaterThanOrEqualTo(card.top - 0.01),
            reason: '🔴 不许被卡顶裁掉（dot.top ≥ 0）');
        // 🔴 B8.1 判据更新：玄参要「不超出房子的高度」⇒ 顶边不得高于房顶线。
        // （旧判据「不越出房顶一个直径」是把 `house.top + 直径` 当上界，自造口径。）
        expect(dot.top, greaterThanOrEqualTo(house.top - 0.01),
            reason: '🔴 零像素飘到房子图上方（dot.top ≥ house.top）');
        expect(dot.bottom, lessThanOrEqualTo(house.top + 14 + 0.01),
            reason: '点底边不超过房顶线 + 一个直径（不压房子主体）');
        expect(dot.left, greaterThanOrEqualTo(card.left - 0.01),
            reason: '🔴 不越出卡左缘');
        expect(dot.right, lessThanOrEqualTo(card.right),
            reason: '🔴 不越出卡右缘');
      }
      // 两点水平不重叠。
      final Rect d0 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(0)));
      final Rect d1 = tester.getRect(find.byKey(GuardSceneCard.energyDotKey(1)));
      expect(d0.right, lessThanOrEqualTo(d1.left));
      // 🔴 B9/C4：两点整体**以房子中轴居中**（玄参：「应该在花园的上方显示，
      // 不是向日葵战士的头顶上」）—— 中点 x 与房子中心 x 逐位相等。
      // 🔴 B11/C2：锚点常量为 20（玄参「整组点再往右让一点」）⇒ 中点 = 中轴 + 20。
      expect((d0.left + d1.right) / 2,
          closeTo(house.center.dx + kGuardEnergyDotAnchorDx, 0.01),
          reason: '🔴 能量点锚点是**房子中轴**，不是战士头顶');
    });

    testWidgets('亮/灭两态（会员档）：energyAvailable 2 ⇒ 两个实心；0 ⇒ 两个空心',
        (WidgetTester tester) async {
      Color dotColor(WidgetTester t, int i) {
        final DecoratedBox box = t.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(GuardSceneCard.energyDotKey(i)),
            matching: find.byType(DecoratedBox),
          ),
        );
        return (box.decoration as BoxDecoration).color!;
      }

      // 🔴 B13.8：两颗都可点亮是**会员档**口径（免费档第 2 颗恒锁标，
      // 见 guard_scene_card_test 的 B13.8 专项组）。
      await _pumpCard(tester, cardWidth: 390, energy: 2, isPremium: true);
      expect(dotColor(tester, 0), const Color(0xFFFFC93C), reason: '🔴 点亮 = 金色');
      expect(dotColor(tester, 1), const Color(0xFFFFC93C));

      await _pumpCard(tester, cardWidth: 390, energy: 1, isPremium: true);
      expect(dotColor(tester, 0), const Color(0xFFFFC93C), reason: '只有点 0 亮');
      expect(dotColor(tester, 1), const Color(0x00000000), reason: '点 1 灭了');

      await _pumpCard(tester, cardWidth: 390, energy: 0, isPremium: true);
      expect(dotColor(tester, 0), const Color(0x00000000));
      expect(dotColor(tester, 1), const Color(0x00000000));
    });
  });

  // ── ④ 去外框 ──────────────────────────────────────────────────────────
  group('④ 去掉卡片外框（无描边 / 无圆角 / 草地满宽）', () {
    testWidgets('卡根不是 Container；卡内无 ClipRRect、无带 border 的 Container',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Finder card = find.byKey(GuardSceneCard.cardKey);
      expect(tester.widget(card), isA<SizedBox>(),
          reason: '🔴 A4：卡根已从 Container 换成 SizedBox（容器 key 即移除）');
      expect(
        find.descendant(of: card, matching: find.byType(ClipRRect)),
        findsNothing,
        reason: '🔴 圆角容器已删（v3 的 ClipRRect 不许回来）',
      );
      // 卡内任何 Container 都不许带描边。
      for (final Element e in find
          .descendant(of: card, matching: find.byType(Container))
          .evaluate()) {
        final Container c = e.widget as Container;
        expect(c.decoration is BoxDecoration ? (c.decoration! as BoxDecoration).border : null,
            isNull,
            reason: '🔴 卡内不许出现描边（玄参：不要下面的框）');
      }
    });

    testWidgets('草地铺满整张卡（宽 == 卡宽，x 与卡逐位对齐）',
        (WidgetTester tester) async {
      await _pumpCard(tester, cardWidth: 390);
      final Rect card = tester.getRect(find.byKey(GuardSceneCard.cardKey));
      final Rect grass = tester.getRect(find.byKey(GuardSceneCard.backdropKey));
      expect(grass.width, closeTo(card.width, 0.01));
      expect(grass.left, closeTo(card.left, 0.01));
      expect(grass.height, closeTo(card.height, 0.01));
    });
  });

  // ── ⑤ 素材亮度归一 ────────────────────────────────────────────────────
  group('⑤ 待机帧色彩归一（玄参：待机图偏暗）', () {
    test('idle frame001 与 attack 的平均亮度差 ≤ 5%', () async {
      final double idle = await _meanLuma('assets/guard/soldier_idle/frame001.webp');
      final double attack = await _meanLuma('assets/guard/soldier_attack.webp');
      final double diff = (idle - attack).abs() / attack;
      expect(diff, lessThanOrEqualTo(0.05),
          reason: '🔴 量化阈值 5%：idle=$idle / attack=$attack ⇒ 差 ${(diff * 100).toStringAsFixed(2)}%');
    });

    test('19 帧待机全部落在攻击帧 ±5% 内（不是只有第一帧修好了）', () async {
      final double attack = await _meanLuma('assets/guard/soldier_attack.webp');
      for (int i = 1; i <= 19; i++) {
        final String name =
            'assets/guard/soldier_idle/frame${i.toString().padLeft(3, '0')}.webp';
        final double luma = await _meanLuma(name);
        expect((luma - attack).abs() / attack, lessThanOrEqualTo(0.05),
            reason: '🔴 $name 亮度 $luma vs attack $attack');
      }
    });
  });

  // ── ⑥ 通道宽度 vs 窄卡阈值（B8.1：修「屏越大通道越窄」的倒挂）────────
  group('⑥ 通道宽度（窄卡阈值 380）', () {
    test('320 / 360 / 375 / 390 / 1024 的通道实测值（写死，±0.6）', () {
      // 🔴 玄参 / 主理人给定的验收口径：屏越大，通道不许反而变窄。
      // 阈值 380 之前：360 屏 49.84 < 320 屏 56.36（倒挂）。
      // 阈值 380 之后（s = 0.85 覆盖到 380）：360 ⇒ 128.66、375 ⇒ 143.66；
      // 390 屏仍是全尺寸元素（玄参要的 88/72 大图不变）⇒ 117.84（B13.2 战士 60）。
      const double eps = 0.6;
      expect(const GuardCardLayout(320).channelWidth, closeTo(88.66, eps));
      expect(const GuardCardLayout(360).channelWidth, closeTo(128.66, eps),
          reason: '🔴 360 屏必须 ≥ 320 屏（旧阈值 340 下只有 49.84，倒挂）');
      expect(const GuardCardLayout(375).channelWidth, closeTo(143.66, eps));
      expect(const GuardCardLayout(390).channelWidth, closeTo(117.84, eps),
          reason: '🔴 B13.2 验收：390 屏 314 − (218.16 − 22) = 117.84');
      expect(const GuardCardLayout(1024).channelWidth, closeTo(751.84, eps));

      // 倒挂本身钉死：360 屏的通道必须**宽于** 320 屏。
      expect(const GuardCardLayout(360).channelWidth,
          greaterThan(const GuardCardLayout(320).channelWidth));
      // 320 / 360 / 375 走窄卡；390 起走全尺寸（390 的 s 必须是 1.0）。
      expect(const GuardCardLayout(320).scale, 0.85);
      expect(const GuardCardLayout(360).scale, 0.85);
      expect(const GuardCardLayout(375).scale, 0.85);
      expect(const GuardCardLayout(390).scale, 1.0);
    });

    test('窄卡只缩元素不缩卡高：320 / 360 / 375 / 390 卡高都是 112', () {
      for (final double w in <double>[320, 360, 375, 390, 1024]) {
        expect(GuardCardLayout(w).cardHeight, 112);
      }
      // 窄卡上房子随元素缩，屋顶线下移 ⇒ 能量点顶边跟着下移（不出房顶）。
      expect(const GuardCardLayout(320).houseTopY, closeTo(28.7, 0.01));
      expect(const GuardCardLayout(320).energyDotTopY, closeTo(28.7, 0.01));
      expect(const GuardCardLayout(390).energyDotTopY, closeTo(14, 0.01));
    });
  });
}
