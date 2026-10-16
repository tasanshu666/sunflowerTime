/// C74 · 升级（解锁新称号）演出 widget 测试。
///
/// 钉住五件事：
///  ① **包络有限时长**：弹入 360 → 停留 1600 → 淡出 300，能被 `pumpAndSettle` 结束，
///     [onComplete] **恰好回吐一次**；
///  ② **文案**：`Lv.N · 称号` + `+N` +（多称号）`连升 N 个称号！`；
///  ③ **走根 Overlay**：`levelUpFxOverlayEntry` 插入后卡片**屏幕居中**（C32 实证：
///     页面根 Stack 居中在真机会贴底）；
///  ④ **全程 IgnorePointer**：不拦截点击/返回键（Q-G）；
///  ⑤ `FxCardShell` 抽取后成长演出**零视觉变化**（既有 `growth_fx_overlay_test.dart`
///     之外再加一道：同一张共享卡体仍渲染出渐变底 + 胶囊标题）。
library level_up_fx_overlay_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/fx_card_shell.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';

/// 一个称号节点（Lv.5 专注小苗苗，+5）。
FocusLevelSettleResult _single() => const FocusLevelSettleResult(
      currentLevel: 5,
      settledLevel: 5,
      settledBefore: 4,
      granted: <LevelGrant>[LevelGrant(level: 5, amount: 5)],
      totalSunlight: 5,
      firstUseSilent: false,
    );

/// 一次解锁 3 个称号节点（跨多级结算：1/5/10 → 合计 15）。
FocusLevelSettleResult _multi() => const FocusLevelSettleResult(
      currentLevel: 10,
      settledLevel: 10,
      settledBefore: 0,
      granted: <LevelGrant>[
        LevelGrant(level: 1, amount: 3),
        LevelGrant(level: 5, amount: 5),
        LevelGrant(level: 10, amount: 7),
      ],
      totalSunlight: 15,
      firstUseSilent: false,
    );

/// **普通升级**（Lv.4，非称号节点）：零阳光、零账本行，但**仍要播演出**
/// （C74 §6 修订二，玄参 2026-10-14 拍板）。
FocusLevelSettleResult _ordinary() => const FocusLevelSettleResult(
      currentLevel: 4,
      settledLevel: 4,
      settledBefore: 3,
      granted: <LevelGrant>[],
      totalSunlight: 0,
      firstUseSilent: false,
    );

/// 空帧列表（素材缺失的兜底路径）。
const List<String> kNoFrames = <String>[];

/// 根 Overlay 浮层的测试宿主（在首帧回调里插入，避免 build 阶段 insert 报错）。
class _FxHost extends StatefulWidget {
  const _FxHost({required this.onReady});

  /// 把 State 回传给测试（供断言与 tearDown 移除浮层）。
  final void Function(_FxHostState) onReady;

  @override
  State<_FxHost> createState() => _FxHostState();
}

class _FxHostState extends State<_FxHost> {
  OverlayEntry? _entry;
  bool inserted = false;

  @override
  void initState() {
    super.initState();
    widget.onReady(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entry = levelUpFxOverlayEntry(
        result: _single(),
        frames: kNoFrames,
        onComplete: () {},
      );
      Overlay.of(context, rootOverlay: true).insert(_entry!);
      inserted = true;
    });
  }

  void remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

Future<void> _pump(
  WidgetTester tester, {
  required FocusLevelSettleResult result,
  required VoidCallback onComplete,
  List<String> frames = kNoFrames,
}) async {
  // C80：_LevelUpContent 为 ConsumerWidget（watch entitlementProvider 判锁标），
  // 夹具包 ProviderScope（默认 free 档，不影响本文件断言口径）。
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: LevelUpFxOverlay(
            result: result,
            frames: frames,
            onComplete: onComplete,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('C74 §6 修订二 · 演出种类判定（纯函数）', () {
    test('称号节点 → titleNode；普通升级 → ordinary；未升级 / 首用 → null', () {
      expect(levelUpFxKindOf(_single()), LevelUpFxKind.titleNode);
      expect(levelUpFxKindOf(_multi()), LevelUpFxKind.titleNode);
      // 🔑 本次修订的核心：普通升级**也播**（granted 为空但 leveledUp）。
      expect(levelUpFxKindOf(_ordinary()), LevelUpFxKind.ordinary);

      // 没升级（快路径）：settledBefore == current ⇒ null。
      expect(
        levelUpFxKindOf(const FocusLevelSettleResult(
          currentLevel: 7,
          settledLevel: 7,
          settledBefore: 7,
          granted: <LevelGrant>[],
          totalSunlight: 0,
          firstUseSilent: false,
        )),
        isNull,
      );
      // 老用户首用静默：即使等级很高也**不播**。
      expect(
        levelUpFxKindOf(const FocusLevelSettleResult(
          currentLevel: 23,
          settledLevel: 23,
          settledBefore: 23,
          granted: <LevelGrant>[],
          totalSunlight: 0,
          firstUseSilent: true,
        )),
        isNull,
        reason: 'C74 §7 追加拍板 ②：老用户首用静默',
      );
    });

    test('素材规格：目录 / 时长 / 音效 / 帧速（fps = 帧数 ÷ 音频时长）', () {
      final LevelUpFxSpec title = levelUpFxSpecOf(LevelUpFxKind.titleNode);
      expect(title.dir, 'assets/fx/levelUp/5leveUp',
          reason: '⚠️ 目录名按玄参交付原样（少一个 l）');
      expect(title.durationMs, 4180);
      expect(title.fallbackFrameCount, 41);
      expect(title.cue, AudioCue.levelUpFive);
      expect(title.fps, closeTo(41 / 4.180, 0.01), reason: '≈ 9.81 fps');

      final LevelUpFxSpec ordinary =
          levelUpFxSpecOf(LevelUpFxKind.ordinary);
      expect(ordinary.dir, 'assets/fx/levelUp/defaultLevelUp');
      expect(ordinary.durationMs, 3579);
      expect(ordinary.fallbackFrameCount, 36);
      expect(ordinary.cue, AudioCue.levelUpDefault);
      expect(ordinary.fps, closeTo(36 / 3.579, 0.01), reason: '≈ 10.06 fps');
    });

    test('音效文件真实存在且过 ≥3s 红线（C35 入库先例）', () {
      for (final AudioCue cue in <AudioCue>[
        AudioCue.levelUpDefault,
        AudioCue.levelUpFive,
      ]) {
        expect(cue.assetPath.endsWith('.mp3'), isTrue);
      }
      expect(AudioCue.levelUpDefault.assetPath,
          'assets/audio/sfx/default_level_up.mp3');
      expect(AudioCue.levelUpFive.assetPath,
          'assets/audio/sfx/5_level_up.mp3');
    });
  });

  testWidgets('①b 普通升级：播 default 素材的演出，但**零阳光行**',
      (WidgetTester tester) async {
    await _pump(tester, result: _ordinary(), onComplete: () {});
    await tester.pump();

    // 标题是「升级啦！」而不是「解锁新称号！」
    expect(find.text(kLevelUpFxLevelTitle), findsOneWidget);
    expect(find.text(kLevelUpFxTitle), findsNothing,
        reason: '普通升级不得冒充「解锁新称号」');
    expect(find.text('Lv.4 · 专注小萌芽'), findsOneWidget,
        reason: 'Lv.4 的称号仍是 Lv.1 节点那个（等级与称号解耦）');
    // 🔴 零阳光：不能出现任何「+N」。
    expect(find.text('+0'), findsNothing);
    expect(find.text('+3'), findsNothing);
    expect(find.byType(Image), findsNothing,
        reason: '普通升级不显示阳光图标（经济层未动）');
  });

  testWidgets('① 包络有限时长：pumpAndSettle 能结束，onComplete 恰好一次',
      (WidgetTester tester) async {
    int calls = 0;
    await _pump(tester, result: _single(), onComplete: () => calls++);
    // ⚠️ 包络的「停留」由 Timer 驱动（与花园页汇总提示同款）→ 必须显式 pump 时长。
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 0, reason: '停留未结束前不得提前回吐');
    // 🔑 停留时长 = **素材播放时长**（称号节点 4180ms），不再是固定 1600。
    final int total = levelUpFxSpecOf(LevelUpFxKind.titleNode).totalMs;
    await tester.pump(Duration(milliseconds: total + 400));
    await tester.pumpAndSettle(); // 淡出是 Ticker 驱动，需要帧
    expect(calls, 1, reason: '停留 + 淡出结束后应恰好回吐一次');
    expect(total, kGrowFxEnterMs + kLevelUpTitleFxDurationMs + kFxDisplayFadeOutMs);
  });

  testWidgets('② 单称号节点文案：Lv.5 · 专注小苗苗 + +5（无「连升」副标题）',
      (WidgetTester tester) async {
    await _pump(tester, result: _single(), onComplete: () {});
    await tester.pump();

    expect(find.text(kLevelUpFxTitle), findsOneWidget);
    expect(find.text('Lv.5 · 专注小苗苗'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(
      find.text(kLevelUpFxMultiTemplate.replaceAll('{n}', '3')),
      findsNothing,
      reason: '只解锁 1 个称号时不显示「连升 N 个称号」',
    );
  });

  testWidgets('②b 跨多级：只播一场卡，显示**最高**称号 + 本轮合计 + 连升副标题',
      (WidgetTester tester) async {
    await _pump(tester, result: _multi(), onComplete: () {});
    await tester.pump();

    expect(
      find.byKey(kLevelUpFxCardKey),
      findsOneWidget,
      reason: '跨多级结算**只播 1 场**演出',
    );
    expect(find.text('Lv.10 · 静心小书童'), findsOneWidget,
        reason: '显示本轮解锁到的最高称号节点');
    expect(find.text('+15'), findsOneWidget, reason: '显示本轮合计（3+5+7）');
    expect(find.text('连升 3 个称号！'), findsOneWidget);
  });

  testWidgets('③ 走根 Overlay：浮层卡片屏幕居中（C32 实证：根 Stack 会贴底）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late _FxHostState host;
    await tester.pumpWidget(
      // C80：演出卡内容为 ConsumerWidget，夹具包 ProviderScope（默认 free 档）。
      ProviderScope(
        child: MaterialApp(home: _FxHost(onReady: (_FxHostState s) => host = s)),
      ),
    );
    await tester.pump(); // 首帧 → 回调里插入根 Overlay 浮层
    await tester.pump(const Duration(milliseconds: 16));
    addTearDown(() => host.remove());

    expect(host.inserted, isTrue, reason: '根 Overlay 应被插入一次');

    final Offset cardCenter =
        tester.getCenter(find.byKey(kLevelUpFxCardKey));
    expect((cardCenter.dx - 402 / 2).abs(), lessThan(1.0),
        reason: '卡片必须水平居中于屏幕');
    expect((cardCenter.dy - 874 / 2).abs(), lessThan(1.0),
        reason: '卡片必须垂直居中于屏幕（真机「贴底」回归）');
  });

  testWidgets('④ 浮层自带 IgnorePointer：不拦截点击 / 返回键（Q-G）',
      (WidgetTester tester) async {
    // 走真实插入路径（`levelUpFxOverlayEntry`），浮层外层才有 IgnorePointer。
    late _FxHostState host;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: _FxHost(onReady: (_FxHostState s) => host = s)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    addTearDown(() => host.remove());

    expect(
      find
          .ancestor(
            of: find.byKey(kLevelUpFxCardKey),
            matching: find.byWidgetPredicate(
              (Widget w) => w is IgnorePointer && w.ignoring,
            ),
          )
          .evaluate(),
      isNotEmpty,
      reason: '演出外层必须有真正生效的 IgnorePointer（不接收任何命中事件）',
    );
  });

  testWidgets('⑤ FxCardShell 抽取零视觉变化：成长演出仍是渐变奶油底 + 胶囊标题',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrowthFxOverlay(
            frames: <String>[
              'assets/fx/grow/sunflower/seed_to_sprout/frame001.webp',
            ],
            durationMs: 200,
            title: '长大啦！🌿',
          ),
        ),
      ),
    );
    await tester.pump();

    final Iterable<BoxDecoration> decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((DecoratedBox b) => b.decoration)
        .whereType<BoxDecoration>();

    expect(
      decorations.where((BoxDecoration d) => d.gradient is LinearGradient),
      isNotEmpty,
      reason: '共享卡体必须仍是渐变奶油底（抽出后不得退化成纯白）',
    );
    expect(
      decorations.where((BoxDecoration d) => d.gradient is RadialGradient),
      isNotEmpty,
      reason: '卡内播放区的金色径向柔光不得丢失',
    );
    expect(find.text('长大啦！🌿'), findsOneWidget, reason: '胶囊标题仍在');
    // 色值单点：共享壳与成长演出引用同一常量。
    expect(kGrowFxCardRadius, 24);
    expect(kGrowFxEnterMs, 360);
    expect(kFxDisplayFadeOutMs, 300);
  });
}
