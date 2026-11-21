/// C131 玄参复验几何护栏：**「向日葵释放大招时还是变小了，跟待机大小不一样」**。
///
/// 沿革：C130（「你不要给我切割」+「放大招战士变小了」）把补偿基准定为
/// **实体并集最大张态**（frame009，255px）—— 但统一素材是「蓄力→爆发→收尾」
/// 动作，战士实体每帧变化极大（frame001 148px → frame009 255px → 光效帧铺满），
/// 并集基准下蓄力帧 001..008 只有 35~59pt ⇒ 玄参按下大招立即看到「小战士」。
///
/// 🔴 C131 口径（主理人拍板，像素诊断定性「补偿基准选错」）：
///  * **补偿基准 = 蓄力主体帧 frame006（238px）**：绘制高 =
///    `soldierRect.height × 720 / 238 × kGuardCastVisualScale`；
///  * **锚点 = 基准帧底边踩地面**：frame006 实体底边（454/720，实测复测值，
///    bbox = (216,216,464,454)）对齐 soldierRect 底边（基线）—— 战士站地面，
///    不漂浮不下沉；x 仍按基准帧实体中心（340/720）对齐槽位中心 x；
///  * 🔴 C132（玄参拍板放弃精确计算，走视觉调优旋钮）：乘
///    `kGuardCastVisualScale = 1.5`（目测初值 1.8 → 玄参真机复验回调，「再大点/小点」只改
///    那一个常量；锚点恒等式对系数**代数不变**（dy/dx 公式里的绘制高项自动
///    跟随，本文件期望值按 ×1.5 手算重写）；
///  * **防二次切割**：卡根 Stack `clipBehavior: Clip.none`（widget 测试读真
///    widget，不扫源码）。
library guard_cast_size_alignment_test;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardCastAnchorFrameBottomPx,
        kGuardCastAnchorFrameCenterXPx,
        kGuardCastAnchorFrameHeightPx,
        kGuardCastFramePx,
        kGuardCastVisualScale;
import 'package:sunflower_time/core/di/providers.dart'
    show entitlementProvider, guardUltimateServiceProvider;
import 'package:sunflower_time/data/local/guard_ultimate_energy_prefs_store.dart'
    show GuardUltimateEnergyPrefsStore;
import 'package:sunflower_time/domain/entities/entitlement.dart' show Entitlement;
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart'
    show UltimateEnergy;
import 'package:sunflower_time/domain/services/guard_ultimate_service.dart'
    show GuardUltimateService;
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart'
    show GuardArt;
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart'
    show GuardCardLayout;
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart'
    show GuardSceneCard;

// ── 手算期望值（🔴 字面量，独立于实现公式；🔴 C132 全部 × kGuardCastVisualScale 1.5）──

/// 常量契约本身（管线实测值）：全画布 720、锚点帧（frame006）实体高 238、
/// 底边 454、实体中心 x 340、视觉调优旋钮 1.5。
const double kFramePx = 720;
const double kAnchorHeightPx = 238;
const double kAnchorBottomPx = 454;
const double kAnchorCenterXPx = 340;
const double kVisualScale = 1.5;

/// 实体占比补偿倍数 × 视觉旋钮 = 720 / 238 × 1.5 = 4.537815126050420。
const double kCompensateRatio = 720 / 238 * 1.5;

/// 390 宽卡（scale 1.0）cast 绘制高
/// = 60 × 720/238 × 1.5 = 272.2689075630252。
const double kPaintHeight390 = 60 * 720 / 238 * 1.5;

/// x 配准位移 = (0.5 − 340/720) × 绘制高 + 视觉修正 kVisualOffsetX
/// = 60 × 20/238 × 1.5 − 13 = 7.563025210084034 − 13 = −5.436974789915966
/// （340 = 锚点帧实体中心 x；20 = 360 − 340；−13 = C132-b 位置旋钮定稿）。
const double kVisualOffsetX = -13.0;
/// y 视觉修正：+6pt 下移（C132-e，玄参初调 +4 → 复验 +6）。
const double kVisualOffsetY = 6.0;
const double kAlignDx390 = 60 * (360 - 340) / 238 * 1.5 + kVisualOffsetX;

/// y 配准位移（画布上移让锚点帧底边仍踩基线）
/// = 布局框半高 − (454/720 − 0.5) × 绘制高 = 30 − 60 × 94/238 × 1.5
/// = 30 − 60×94/238×1.5 + 4（C132-e 下移）= −5.546218487394959 + 4
/// = −1.546218487394959（94 = 454 − 360；几何项 C132 起翻负=画布上移，
/// 视觉修正 +4 后净上移 −1.55）。
const double kAlignDy390 =
    30 - 60 * (454 - 360) / 238 * 1.5 + kVisualOffsetY;

/// 锚点帧底边到画布中心的距离 = (454/720 − 0.5) × 绘制高 = 60 × 94/238 × 1.5
/// = 42.65546218487395 —— 与 y 位移之和恰 = 30 = 半个布局框（手算恒等）。
const double kAnchorBottomFromCanvasCenter = 60 * (454 - 360) / 238 * 1.5;

/// 窄卡 320（scale 0.85）：布局框高 51，绘制高 = 51 × 720/238 × 1.5 = 231.428571…。
const double kPaintHeight320 = 51 * 720 / 238 * 1.5;

/// iPad（uiScale 1.3）：布局框高 78，绘制高 = 78 × 720/238 × 1.5 = 353.949579…。
const double kPaintHeightIpad13 = 78 * 720 / 238 * 1.5;

void main() {
  group('C132 · 常量契约（管线实测值的字面量钉死）', () {
    test('kGuardCastFramePx=720 / 锚点帧高=238 / 底边=454 / 中心x=340 / 旋钮=1.5', () {
      expect(kGuardCastFramePx, kFramePx);
      expect(kGuardCastAnchorFrameHeightPx, kAnchorHeightPx);
      expect(kGuardCastAnchorFrameBottomPx, kAnchorBottomPx);
      expect(kGuardCastAnchorFrameCenterXPx, kAnchorCenterXPx);
      expect(kGuardCastVisualScale, kVisualScale);
    });
  });

  group('C132 · 绘制高 = 基准 × 720/238 × 旋钮1.5（手算独立期望）', () {
    test('390 宽卡：绘制高 272.2689 = 181.5126 × 1.5', () {
      const GuardCardLayout layout = GuardCardLayout(390);
      // 🔴 C132 恒等式：绘制高 = soldierRect.height × 720/238 × 1.5。
      expect(layout.ultimateCastPaintHeight, closeTo(kPaintHeight390, 1e-9));
      expect(
          layout.ultimateCastPaintHeight, closeTo(272.2689075630252, 1e-6));
      // C131 基准（×1.5 前）逐位保留：绘制高 / 1.5 = 181.5126。
      expect(layout.ultimateCastPaintHeight / kGuardCastVisualScale,
          closeTo(181.51260504201682, 1e-6),
          reason: 'C131 几何基准仍是基础，旋钮只是乘在它上面');
      // 锚点帧渲染高 = 绘制高 × 238/720 = 待机 × 1.5 = 90（玄参视觉调优起点）。
      final double anchorEntityHeight =
          layout.ultimateCastPaintHeight * kAnchorHeightPx / kFramePx;
      expect(anchorEntityHeight, closeTo(layout.soldierRect.height * 1.5, 1e-9));
      expect(anchorEntityHeight, closeTo(90, 1e-6));
      // 补偿倍数本体（4.5378…）也钉死，防止常量漂移。
      expect(kFramePx / kAnchorHeightPx * 1.5, closeTo(kCompensateRatio, 1e-12));
    });

    test('窄卡 320（scale 0.85）：绘制高 231.4286 = 154.2857 × 1.5', () {
      const GuardCardLayout layout = GuardCardLayout(320);
      expect(layout.soldierRect.height, closeTo(51, 1e-9),
          reason: '窄卡 ×0.85：60 → 51（既有窄卡缩放口径，零改动）');
      expect(layout.ultimateCastPaintHeight, closeTo(kPaintHeight320, 1e-9));
      expect(
        layout.ultimateCastPaintHeight * kAnchorHeightPx / kFramePx,
        closeTo(layout.soldierRect.height * 1.5, 1e-9),
        reason: '窄卡上旋钮不变式同样成立',
      );
    });

    test('iPad uiScale 1.3：绘制高 353.9496 = 235.9664 × 1.5', () {
      const GuardCardLayout layout = GuardCardLayout(1024, 1.3);
      expect(layout.soldierRect.height, closeTo(78, 1e-9),
          reason: '平板 ×1.3：60 → 78（既有平板口径，零改动）');
      expect(layout.ultimateCastPaintHeight, closeTo(kPaintHeightIpad13, 1e-9));
      expect(
        layout.ultimateCastPaintHeight * kAnchorHeightPx / kFramePx,
        closeTo(layout.soldierRect.height * 1.5, 1e-9),
      );
    });

    test('逐帧观感表（C132 ×1.5 起点）：锚点帧 90pt，峰值 96.43，起手 55.97', () {
      // 逐帧实体高（管线实测，720² 全画布像素）× 渲染倍率 60×1.5/238：
      const double scale390 = 60 * 1.5 / 238;
      expect(238 * scale390, closeTo(90, 1e-9),
          reason: '锚点帧 frame006 = 待机 × 1.5（玄参视觉调优起点，'
              '「再大点/小点」只改 kGuardCastVisualScale）');
      expect(230 * scale390, closeTo(86.97, 0.01),
          reason: '按下段 frame005 = 86.97pt（≈ 待机的 1.45 倍）');
      expect(248 * scale390, closeTo(93.78, 0.01));
      expect(255 * scale390, closeTo(96.43, 0.01),
          reason: '峰值 frame009 = 96.43pt（待机 × 1.61）');
      expect(148 * scale390, closeTo(55.97, 0.01),
          reason: '起手 frame001 = 55.97pt（略小于待机实体，蓄力下蹲动作）');
    });
  });

  group('C132 · 锚点复验：底边恒等式在 ×1.5 下仍逐位成立 + 中心 x 对齐', () {
    test('390 宽卡：dx = −5.437（含 −13 修正）；dy = +0.454（−5.546 几何 + 6 下移）', () {
      const GuardCardLayout layout = GuardCardLayout(390);
      final Offset offset = layout.ultimateCastAlignOffset;
      expect(offset.dx, closeTo(kAlignDx390, 1e-9));
      expect(offset.dx, closeTo(-5.436974789915966, 1e-6));
      expect(offset.dx, lessThan(0),
          reason: '理论配准 +7.56 − 视觉修正 11 转负 ⇒ 画布净左移（玄参「偏右」修正）；'
              'dy 同为负但语义不同（上移），dx≠dy 防混淆');
      expect(offset.dy, closeTo(kAlignDy390, 1e-9));
      expect(offset.dy, closeTo(0.453781512605041, 1e-6));
      expect(offset.dy, greaterThan(0),
          reason: '几何 dy −5.55（画布上移踩基线）+ C132-e 下移 +6 后净下移 '
              '+0.45（画布略下移，玄参视觉拍板）');
      expect(offset.dy, isNot(closeTo(offset.dx, 0.5)),
          reason: 'x/y 锚点语义分离（x=中心、y=底边），仍不相等');
    });

    test('底边锚点恒等式 ×1.5：dy + (454/720−0.5)×绘制高 = 30 = 半个布局框', () {
      // 手算推导：底边−画布中心 = 60×94/238×1.5 = 35.5462；dy = 30 − 35.5462
      // = −5.5462 ⇒ 锚点帧底边 = soldierRect 底边 = 基线，对任意绘制高
      // 代数不变（旋钮只改绝对值，不改恒等式）。
      const GuardCardLayout layout = GuardCardLayout(390);
      final double bottomFromCanvasCenter =
          (kAnchorBottomPx / kFramePx - 0.5) * layout.ultimateCastPaintHeight;
      expect(
          bottomFromCanvasCenter, closeTo(kAnchorBottomFromCanvasCenter, 1e-9));
      expect(bottomFromCanvasCenter, closeTo(35.546218487394958, 1e-6));
      final Offset offset = layout.ultimateCastAlignOffset;
      expect(offset.dy + bottomFromCanvasCenter,
          closeTo(layout.soldierRect.height / 2 + kVisualOffsetY, 1e-9),
          reason: '🔴 底边锚点恒等式 + C132-e 下移 +6：锚点帧底边落在基线下方 '
              '4pt（玄参视觉拍板的观感下沉，有意偏离几何恒等式）');
    });

    test('窄卡 / iPad：底边锚点恒等式 ×1.5 同样成立（位移随 e × 旋钮缩放）', () {
      const GuardCardLayout narrow = GuardCardLayout(320);
      final Offset n = narrow.ultimateCastAlignOffset;
      expect(n.dx, closeTo(51 * 20 / 238 * 1.5 + kVisualOffsetX, 1e-9));
      expect(n.dy, closeTo(25.5 - 51 * 94 / 238 * 1.5 + kVisualOffsetY, 1e-9));
      expect(
        n.dy +
            (kAnchorBottomPx / kFramePx - 0.5) *
                narrow.ultimateCastPaintHeight,
        closeTo(narrow.soldierRect.height / 2 + kVisualOffsetY, 1e-9),
      );
      const GuardCardLayout pad = GuardCardLayout(1024, 1.3);
      final Offset p = pad.ultimateCastAlignOffset;
      expect(p.dx, closeTo(78 * 20 / 238 * 1.5 + kVisualOffsetX, 1e-9));
      expect(p.dy, closeTo(39 - 78 * 94 / 238 * 1.5 + kVisualOffsetY, 1e-9));
      expect(
        p.dy +
            (kAnchorBottomPx / kFramePx - 0.5) * pad.ultimateCastPaintHeight,
        closeTo(pad.soldierRect.height / 2 + kVisualOffsetY, 1e-9),
      );
    });
  });

  group('C132 · widget 护栏：绘制框 ×1.5 + 底边锚点 + 越界放行（真 widget 读取）', () {
    /// 构造 fighting 态 view（premium + 有 1 格能量 ⇒ 点战士直接放行 cast）。
    GuardTodayView fightingView() {
      return const GuardTodayView(
        mode: GuardPillMode.fighting,
        state: GuardDayState(
          dayKey: '2026-01-01',
          status: GuardDayStatus.fighting,
          thiefKind: GuardThiefKind.sunRat,
          winSun: 2,
          tutorialSeen: true,
        ),
        energyAvailable: 1,
        balance: 10,
        isPremium: true,
      );
    }

    Future<void> pumpFightingCard(WidgetTester tester) async {
      // 固定测试视口为 390×844（默认 800×600 会让 Center 把卡居中到屏中，
      // 全局坐标断言不可预期）。devicePixelRatio 1.0 ⇒ 逻辑坐标 = 全局坐标。
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final GuardUltimateEnergyPrefsStore store = GuardUltimateEnergyPrefsStore(
          await SharedPreferences.getInstance());
      final GuardUltimateService service = GuardUltimateService(
        store: store,
        childId: () => 'cast-size-kid',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            entitlementProvider.overrideWith((Ref ref) => Entitlement.lifetime()),
            guardUltimateServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 390,
                  child: Localizations(
                    locale: const Locale('zh'),
                    delegates: const <LocalizationsDelegate<dynamic>>[
                      AppLocalizations.delegate,
                      GlobalMaterialLocalizations.delegate,
                      GlobalWidgetsLocalizations.delegate,
                      GlobalCupertinoLocalizations.delegate,
                    ],
                    child: GuardSceneCard(
                      view: fightingView(),
                      dayKey: '2026-01-01',
                      childId: 'cast-size-kid',
                      onStart: () {},
                      // 🔴 必须显式注入能量快照：默认 UltimateEnergy.empty
                      // （filledCells = 0）⇒ 门控走「无能量轻提示」，cast 永不上树。
                      ultimateEnergy: const UltimateEnergy(
                        filledCells: 1,
                        fractionMin: 0,
                        totalFocusMin: 30,
                      ),
                      ultimateUnlocked: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // 待机帧循环 + sim ticker ⇒ 只做有界 pump，绝不 pumpAndSettle。
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('cast 段：OverflowBox 放大到 272.27²，锚点帧底边踩基线、中心 x 对齐',
        (WidgetTester tester) async {
      await pumpFightingCard(tester);

      // 点战士 → 门控放行 → _castUltimate（async spendCell → setState casting）。
      await tester.tap(find.byKey(GuardSceneCard.soldierKey),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(GuardArt.ultimateCastKey), findsOneWidget,
          reason: 'cast 段已上树（战士本体原位 27 帧）');

      // ① 绘制框：OverflowBox 在 cast 段给出 272.27² 紧约束（手算字面量，×1.5）。
      final OverflowBox overflow = tester.widget<OverflowBox>(
        find.ancestor(
          of: find.byKey(GuardArt.ultimateCastKey),
          matching: find.byType(OverflowBox),
        ).first,
      );
      expect(overflow.minWidth, closeTo(kPaintHeight390, 1e-6),
          reason: 'cast 绘制宽 = 60 × 720/238 × 1.5 = 272.2689');
      expect(overflow.maxWidth, closeTo(kPaintHeight390, 1e-6));
      expect(overflow.minHeight, closeTo(kPaintHeight390, 1e-6),
          reason: 'cast 绘制高 = 60 × 720/238 × 1.5 = 272.2689（正方形画布）');
      expect(overflow.maxHeight, closeTo(kPaintHeight390, 1e-6));

      // ② 🔴 C132 直读断言：soldierUltimateCast 渲染框 == 绘制高（防「getter
      //    改了但接线忘了跟」的 M1 变异假绿）。
      final Rect slot = tester.getRect(find.byKey(GuardSceneCard.soldierKey));
      expect(slot.width, closeTo(60, 1e-6), reason: '战士槽位 = 布局框 60²');
      expect(slot.height, closeTo(60, 1e-6));
      final Rect castRect = tester.getRect(find.byKey(GuardArt.ultimateCastKey));
      expect(castRect.width, closeTo(kPaintHeight390, 1e-3),
          reason: '🔴 渲染框宽必须逐位 = ultimateCastPaintHeight（直读）');
      expect(castRect.height, closeTo(kPaintHeight390, 1e-3),
          reason: '🔴 渲染框高必须逐位 = ultimateCastPaintHeight（直读）');

      // ③ 锚点配准（×1.5 后公式自动跟随，恒等式不变）：锚点帧（frame006）底边
      //    踩槽位底边（基线）、实体中心 x 对齐槽位中心 x。
      expect(castRect.top + kAnchorBottomPx / kFramePx * kPaintHeight390,
          closeTo(slot.bottom + kVisualOffsetY, 0.01),
          reason: '🔴 C131 锚点（底边踩基线）+ C132-e 下移 +6：frame006 实体底边 '
              '（454/720）落在 soldierRect 底边下方 4pt（玄参视觉拍板）');
      expect(castRect.left + kAnchorCenterXPx / kFramePx * kPaintHeight390,
          closeTo(slot.center.dx + kVisualOffsetX, 0.01),
          reason: '🔴 frame006 实体中心 x（340/720）对齐槽位中心 x 后，再叠加 '
              'C132-b 位置旋钮 kVisualOffsetX = −13（玄参三轮左移修正）');
      // 越界绘制证据：画布上下都超出槽位（根 Stack Clip.none 放行后可见）。
      expect(castRect.top, lessThan(slot.top),
          reason: '画布顶超出槽位顶（272.27 > 60，光效必须能越界画）');
      expect(castRect.bottom, greaterThan(slot.bottom));

      // ④ 防二次切割：卡根 Stack 必须 Clip.none（真 widget，不扫源码）。
      final Stack rootStack = tester.widget<Stack>(
        find.ancestor(
          of: find.byKey(GuardSceneCard.soldierKey),
          matching: find.byType(Stack),
        ).first,
      );
      expect(rootStack.clipBehavior, Clip.none,
          reason: '🔴 玄参「你不要给我切割」：光效帧铺满 720² 画布，'
              '卡根 hardEdge 会把越界光效切出硬边');

      // 收尾：把 cast（4s）+ fx 段（4s）推完，避免挂起 Timer 污染用例收尾。
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    });

    testWidgets('非 cast 姿态：OverflowBox 维持原口径（宽 100 / 高 60，零回归）',
        (WidgetTester tester) async {
      await pumpFightingCard(tester);
      // 不点战士：常态站立帧。OverflowBox 取 soldierDrawWidth × soldierRect.height。
      // 🔴 OverflowBox 是 soldierKey（SizedBox）的**子**，不是祖先 ⇒ 用 descendant。
      final OverflowBox overflow = tester.widget<OverflowBox>(
        find.descendant(
          of: find.byKey(GuardSceneCard.soldierKey),
          matching: find.byType(OverflowBox),
        ).first,
      );
      expect(overflow.minWidth, closeTo(60 * 5 / 3, 1e-9),
          reason: '常态绘制宽 = soldierOverflowWidth = 100（B13 定稿口径零改动）');
      expect(overflow.maxWidth, closeTo(60 * 5 / 3, 1e-9));
      expect(overflow.minHeight, closeTo(60, 1e-9));
      expect(overflow.maxHeight, closeTo(60, 1e-9));
    });
  });
}
