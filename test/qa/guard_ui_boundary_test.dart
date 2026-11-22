/// 花园守卫独立验收 · **V5 UI 边界**
///
/// 覆盖：
///  ① 今日页场景卡 `absent` 零占位（第一张卡位移差**恰好** 118pt = 108 + 10；
///     B8 布局 v4 把卡高从 160 降到 108 ⇒ 位移差 170 → 118，判据不变）；
///     v1 胶囊时代是 54pt，见 git 历史）；
///  ② 320×568 + en + 1.3 倍字号：场景卡 / 券 chip / 结算卡三处无 RenderFlex overflow；
///  ③ buff chip 文案不含 `×`（已在 V3-5 钉过，这里补一条渲染后的整棵树断言）；
///  ④ 平板（1032 宽 = iPad 13″ ⇒ uiScale 1.6）：场景卡 / chip 按比例放大后不溢出；
///  ⑤ 卡 5 状态可点性：只有 `pendingFree` / `pendingPaid` 可点。
///
/// 🔴 B3 迁移注：②④⑤ 的夹具原直 pump `GuardPill`（胶囊本体已随战斗浮层一起
///    退役），现改 pump `GuardSceneCard`（dayKey/childId 用字面量）—— 断言对象
///    换了、判据等价（溢出 / 宽度 / 可点性），覆盖不降。
/// 🔴 不用 `pumpAndSettle`（今日页阳光气泡是 12 秒无限循环动画）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_buff_chip.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_scene_card.dart';
import 'package:sunflower_time/shared/responsive.dart';

import 'guard_probe_support.dart';

GuardTodayView _view(
  GuardPillMode mode, {
  GuardThiefKind thief = GuardThiefKind.sneakThief,
  GuardDropKind drop = GuardDropKind.waterVoucher,
  int winSun = 2,
  int energy = 0,
  double balance = 0,
}) {
  final GuardDayStatus status = switch (mode) {
    GuardPillMode.claimed => GuardDayStatus.claimed,
    GuardPillMode.fighting => GuardDayStatus.fighting,
    GuardPillMode.freeRide => GuardDayStatus.short,
    GuardPillMode.absent => GuardDayStatus.none,
    _ => GuardDayStatus.pending,
  };
  return GuardTodayView(
    mode: mode,
    state: GuardDayState(
      dayKey: '2026-11-09',
      status: status,
      thiefKind: mode == GuardPillMode.absent ? null : thief,
      winSun: winSun,
      dropKind: drop,
    ),
    energyAvailable: energy,
    balance: balance,
  );
}

/// 统一挂载壳：可指定 locale / textScale / 屏尺寸。
Widget _shell(
  Widget child, {
  Size screen = const Size(390, 844),
  double textScale = 1.0,
  bool english = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: screen,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Localizations(
      locale: english ? const Locale('en') : const Locale('zh'),
      delegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
}

/// 把 [GuardSceneCard] 单独挂在槽位里（B3 迁移：原夹具为 GuardPill）。
Future<void> _pumpCard(
  WidgetTester tester,
  GuardTodayView view, {
  double width = 288,
  double textScale = 1.0,
  bool english = false,
  VoidCallback? onStart,
}) async {
  await tester.pumpWidget(
    _shell(
      Center(
        child: SizedBox(
          width: width,
          child: GuardSceneCard(
            view: view,
            dayKey: '2026-01-01',
            childId: 'seed-0',
            onStart: onStart,
          ),
        ),
      ),
      textScale: textScale,
      english: english,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// 今日页外壳（真 DB + 真 prefs + 真守卫链路）。
Future<ProviderContainer> _pumpToday(
  WidgetTester tester,
  GuardProbeEnv env, {
  Size screen = const Size(320, 568),
  int frames = 24,
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
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

double _firstCardOffset(WidgetTester tester) {
  final Rect list = tester.getRect(find.byType(ListView));
  final Rect label = tester.getRect(find.text('今日获取阳光'));
  return label.top - list.top;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // V5-1 absent 零占位
  // ══════════════════════════════════════════════════════════════════════
  group('V5-1 absent 零占位（B2 场景卡）', () {
    testWidgets('无贼 ⇒ 不渲染场景卡；有贼后第一张卡**恰好**下移 122pt',
        (WidgetTester tester) async {
      final GuardProbeEnv env = await GuardProbeEnv.create();
      addTearDown(env.close);

      final ProviderContainer container = await _pumpToday(tester, env);
      expect(find.byKey(GuardSceneCard.cardKey), findsNothing);
      final double before = _firstCardOffset(tester);

      // 种一株 + 触发一次刷新（页面监听 economyRevisionProvider）。
      await env.seedPlant('plant_1', now: DateTime.now());
      container.read(economyRevisionProvider.notifier).state++;
      for (int i = 0; i < 40; i++) {
        if (find.byKey(GuardSceneCard.cardKey).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(GuardSceneCard.cardKey), findsOneWidget);

      final double after = _firstCardOffset(tester);
      expect(after - before, closeTo(122.0, 0.01),
          reason: '🔴 差 1pt 都算布局回归：kGuardSceneCardHeight(112，B10 布局 v6 '
              '= padTop 14 + 房子 88 + padBottom 10) + kGuardPillGap(10)');
      expect(container.read(guardTodayProvider).isVisible, isTrue);
    });

    test('场景卡布局常量字面量：112 / 20 / 28 / 64；胶囊占位仍是 44 / 10', () {
      // 字面量防悄悄漂移（B10 布局 v6：卡高 = padTop 14 + 房子 88 + 底衬 10
      // = **112**；能量点 28 常量仍在 prd_params 里（v1 素材位约定不变），卡内
      // 实际用的是 `GuardCardLayout.energyDotSize` = 14）。
      expect(kGuardSceneCardHeight, 112.0);
      expect(kGuardSceneCardRadius, 20.0);
      expect(kGuardSceneEnergyDotSize, 28.0);
      expect(kGuardSceneFireButtonSize, 64.0);
      expect(kGuardSceneCardHeight + kGuardPillGap, 122.0);
      // v1 胶囊常量不动（B3 退役前夹具仍依赖）。
      expect(kGuardPillHeight, 44.0);
      expect(kGuardPillGap, 10.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V5-2 320×568 + en + 1.3 倍字号
  // ══════════════════════════════════════════════════════════════════════
  group('V5-2 最坏组合：320×568 + en + 1.3×', () {
    testWidgets('场景卡（5 态）不 overflow', (WidgetTester tester) async {
      for (final GuardPillMode mode in <GuardPillMode>[
        GuardPillMode.pendingFree,
        GuardPillMode.pendingPaid,
        GuardPillMode.freeRide,
        GuardPillMode.fighting,
        GuardPillMode.claimed,
      ]) {
        await _pumpCard(
          tester,
          _view(mode, energy: 2, balance: 100),
          width: 288,
          textScale: 1.3,
          english: true,
        );
        // fighting 态多推一帧：L4 战斗层 ticker 跑起来（怪在车道上）后再查。
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$mode 在 en+1.3 下溢出');
      }
    });

    testWidgets('结算卡（带券比较行）在 288 宽槽位不 overflow',
        (WidgetTester tester) async {
      final AppLocalizations en = await AppLocalizations.delegate.load(
        const Locale('en'),
      );
      for (final GuardDropKind drop in <GuardDropKind>[
        GuardDropKind.waterVoucher,
        GuardDropKind.laborVoucher,
        GuardDropKind.freeFertilize,
        GuardDropKind.none,
      ]) {
        await tester.pumpWidget(
          _shell(
            Center(
              child: SizedBox(
                width: 288,
                child: GuardResultCard(
                  view: _view(
                    GuardPillMode.pendingPaid,
                    drop: drop,
                    balance: 100,
                  ),
                  l10n: en,
                  onCollect: () async => throw UnimplementedError(),
                ),
              ),
            ),
            textScale: 1.3,
            english: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: '${drop.id} 结算卡溢出');
      }
    });

    testWidgets('buff chip 在 160pt 窄槽位不 overflow 且不含 `×`',
        (WidgetTester tester) async {
      for (final GuardDropKind kind in <GuardDropKind>[
        GuardDropKind.waterVoucher,
        GuardDropKind.laborVoucher,
        GuardDropKind.fertilizeVoucher,
        GuardDropKind.freeWater,
        GuardDropKind.freeFertilize,
      ]) {
        await tester.pumpWidget(
          _shell(
            Center(
              child: SizedBox(
                width: 160,
                child: GuardBuffChip(
                  buff: GuardBuffState(kind: kind, quota: 6, used: 2),
                ),
              ),
            ),
            textScale: 1.3,
            english: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: '${kind.id} chip 溢出');
        expect(find.textContaining('×'), findsNothing);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V5-4 平板（1032 宽 ⇒ uiScale 1.6）
  // ══════════════════════════════════════════════════════════════════════
  group('V5-4 平板 1032 宽', () {
    test('tabletUiScaleFor(1032) == 1.6，手机 == 1.0', () {
      expect(tabletUiScaleFor(1032), 1.6);
      expect(tabletUiScaleFor(390), 1.0);
    });

    testWidgets('场景卡在平板宽度 + en + 1.6 倍字号下不溢出',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(GuardPillMode.pendingPaid, balance: 100),
        width: 1032 - 32,
        textScale: 1.6,
        english: true,
        onStart: () {},
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('chip 在平板宽度 + en + 1.6 倍字号下不溢出、宽度不超过屏宽 − 24',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _shell(
          const Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: GuardBuffChip(
                buff: GuardBuffState(
                  kind: GuardDropKind.waterVoucher,
                  quota: 6,
                  used: 0,
                ),
              ),
            ),
          ),
          screen: const Size(1032, 1366),
          textScale: 1.6,
          english: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(GuardBuffChip.chipKey)).width,
        lessThanOrEqualTo(1032 - 24),
        reason: 'chips 行 Positioned(left:12,right:12) ⇒ 可用宽 1008',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V5-5 五态可点性（B3 迁移：可点 = 「开始守卫」钮在树且回调触发）
  // ══════════════════════════════════════════════════════════════════════
  group('V5-5 卡可点性', () {
    testWidgets('未 claimed 三态（pendingFree / pendingPaid / freeRide）可点；claimed/fighting 不可点',
        (WidgetTester tester) async {
      final Map<GuardPillMode, bool> expected = <GuardPillMode, bool>{
        GuardPillMode.pendingFree: true,
        GuardPillMode.pendingPaid: true,
        GuardPillMode.freeRide: true,
        GuardPillMode.fighting: false,
        GuardPillMode.claimed: false,
      };
      for (final MapEntry<GuardPillMode, bool> e in expected.entries) {
        int taps = 0;
        await _pumpCard(
          tester,
          _view(e.key, energy: 2, balance: 100),
          onStart: () => taps++,
        );
        if (e.value) {
          expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
              reason: '${e.key} 必须渲染「开始守卫」钮');
          await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
          await tester.pump(const Duration(milliseconds: 50));
        } else {
          expect(find.byKey(GuardSceneCard.startButtonKey), findsNothing,
              reason: '${e.key} 不得渲染「开始守卫」钮');
          await tester.tap(find.byKey(GuardSceneCard.cardKey),
              warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(taps, e.value ? 1 : 0, reason: '${e.key} 可点性错误');
        expect(_view(e.key, energy: 2, balance: 100).isActionable, e.value);
      }
    });

    testWidgets('没玩过（freeRide + 0能量0余额）也可点：画钮、不画旗',
        (WidgetTester tester) async {
      int taps = 0;
      await _pumpCard(
        tester,
        _view(GuardPillMode.freeRide, energy: 0, balance: 0),
        onStart: () => taps++,
      );
      expect(find.byKey(GuardSceneCard.startButtonKey), findsOneWidget,
          reason: '玄参裁定：没玩过也必须画「开始守卫」钮');
      expect(find.byKey(GuardSceneCard.claimedBadgeKey), findsNothing,
          reason: '0 资源画胜利旗是假胜利');
      await tester.tap(find.byKey(GuardSceneCard.startButtonKey));
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1, reason: '按钮必须有真实回调，不能是空按钮');
    });

    test('纯函数 guardPillModeOf 的 5 态映射', () {
      GuardDayState st(GuardDayStatus s) => GuardDayState(
            dayKey: '2026-11-09',
            status: s,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 2,
          );
      expect(
        guardPillModeOf(st(GuardDayStatus.pending), 2, 0),
        GuardPillMode.pendingFree,
      );
      expect(
        guardPillModeOf(st(GuardDayStatus.pending), 0, 100),
        GuardPillMode.pendingPaid,
      );
      expect(
        guardPillModeOf(st(GuardDayStatus.pending), 0, 4),
        GuardPillMode.freeRide,
      );
      expect(
        guardPillModeOf(st(GuardDayStatus.short), 0, 100),
        GuardPillMode.freeRide,
      );
      expect(
        guardPillModeOf(st(GuardDayStatus.fighting), 2, 100),
        GuardPillMode.fighting,
      );
      expect(
        guardPillModeOf(st(GuardDayStatus.claimed), 2, 100),
        GuardPillMode.claimed,
      );
      expect(
        guardPillModeOf(const GuardDayState(dayKey: '2026-11-09', status: GuardDayStatus.none), 2, 100),
        GuardPillMode.absent,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // V13-27 结算卡阳光卡数字 + 失败态标题（B13.27 增量 C120-13 玄参口径钉死）
  // ══════════════════════════════════════════════════════════════════════
  group('V13-27 结算卡阳光卡：未参战恒 −N（页面恒传 3）+ 失败标题、参战 +N（C128：开火或大招清怪）', () {
    Future<void> pump(
      WidgetTester tester,
      GuardTodayView view, {
      int stolenSun = 0,
      bool didAttack = true,
    }) async {
      final AppLocalizations zh = await AppLocalizations.delegate.load(
        const Locale('zh'),
      );
      await tester.pumpWidget(
        _shell(
          Center(
            child: GuardResultCard(
              view: view,
              l10n: zh,
              onCollect: () async => throw UnimplementedError(),
              stolenSun: stolenSun,
              didAttack: didAttack,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder sunText() => find.descendant(
          of: find.byKey(GuardResultCard.sunRewardKey),
          matching: find.byType(Text),
        );

    String sunNumber(WidgetTester tester) {
      final Iterable<String> texts = sunText().evaluate().map(
            (Element e) => (e.widget as Text).data ?? '',
          );
      return texts.firstWhere(
        (String s) => s.startsWith('+') ||
            s.startsWith('−') ||
            (s.length <= 2 && int.tryParse(s) != null),
      );
    }

    Color sunColor(WidgetTester tester) {
      final Iterable<Text> texts = sunText().evaluate().map(
            (Element e) => e.widget as Text,
          );
      return texts
          .firstWhere((Text t) => (t.data ?? '').startsWith('+') ||
              (t.data ?? '').startsWith('−') ||
              (t.data ?? '').length <= 2 && int.tryParse(t.data ?? '') != null)
          .style!
          .color!;
    }

    testWidgets('未参战 + 惩罚 3（页面真实入参）⇒ 显示「−3」红色 + 失败标题 + 被偷行恒渲染',
        (WidgetTester tester) async {
      await pump(
        tester,
        _view(GuardPillMode.pendingFree, winSun: 4),
        stolenSun: 3,
        didAttack: false,
      );
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '🔴 C120-13：未参战场标题 = 失败文案，绝不用「守卫成功」误导（C128 后大招参战场不会进此分支）');
      expect(sunNumber(tester), '−3',
          reason: '🔴 C120-13：未参战场阳光卡恒 −3（惩罚必达），绝不允许 0/+N');
      expect(sunColor(tester), const Color(0xFFB3261E),
          reason: '红色 = 「被偷走」的损失语义');
      // 馋光鼠被偷行恒渲染（文案数字 = 惩罚额 3；用精确匹配防标题「偷走」撞车）。
      expect(find.text('被偷菜贼偷走了 3 阳光'), findsOneWidget);
    });

    testWidgets('未参战 + N=1（组件级任意 N 支持）⇒ 显示「−1」', (WidgetTester tester) async {
      await pump(
        tester,
        _view(GuardPillMode.pendingFree, winSun: 4),
        stolenSun: 1,
        didAttack: false,
      );
      expect(sunNumber(tester), '−1');
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '失败标题只跟 didAttack 走，与 N 无关');
    });

    testWidgets('未参战 + 脏入参 N=0（防御）⇒ 显示「0」而不是「−0」', (WidgetTester tester) async {
      await pump(
        tester,
        _view(GuardPillMode.pendingFree, winSun: 4),
        stolenSun: 0,
        didAttack: false,
      );
      expect(sunNumber(tester), '0',
          reason: '「−0」是脏数字 —— 实扣 0 = 分毫未损，负号在撒谎（页面恒传 3，此为防御分支）');
    });

    testWidgets('参战场显示现状「+winSunToGrant」+ 成功标题不回归', (WidgetTester tester) async {
      await pump(
        tester,
        _view(GuardPillMode.pendingFree, winSun: 4),
        stolenSun: 0,
        didAttack: true,
      );
      expect(sunNumber(tester), '+4',
          reason: '参战场逐位不变（winSun=4 → guardGrantWinSunOf = +4）');
      expect(sunColor(tester), const Color(0xFFB37400));
      expect(find.text('花园守卫成功，赶走了贪吃的小动物'), findsOneWidget,
          reason: '🔴 参战场标题不变（成功文案）');
    });

    testWidgets('参战 + 被偷 3（真机反馈 4）⇒ 标题走失败文案，不再自相矛盾',
        (WidgetTester tester) async {
      await pump(
        tester,
        _view(GuardPillMode.pendingFree, winSun: 4),
        stolenSun: 3,
        didAttack: true,
      );
      expect(find.text('守卫失败，怪物偷走了阳光！'), findsOneWidget,
          reason: '🔴 真机反馈 4：开过火但被偷也算没守住，标题必须与下方被偷行一致');
      expect(find.textContaining('守卫成功，赶走了贪吃的小动物'), findsNothing,
          reason: '🔴 不能再出现「守卫成功」与被偷行并存的矛盾文案');
      expect(find.text('被偷菜贼偷走了 3 阳光'), findsOneWidget,
          reason: '被偷行照常渲染，账本不受影响');
    });
  });
}
