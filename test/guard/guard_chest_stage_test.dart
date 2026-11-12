/// 花园守卫 · **宝箱演出阶段机**（Guard-B13.11 / T03）的行为护栏。
///
/// 真源：`docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §2.2（状态机）/
/// §7.3-§7.5（演出）/ §8.2（T03 判据）/ §9.3（测试纪律）。
///
/// ## 覆盖
/// | # | 断言 | 用例 |
/// |---|---|---|
/// | ① | 挂载即 `drop`（宝箱在、开箱播放器不在）；600ms 后进 `idle`（提示亮起）；**落地音效播在 fall 段结束 240ms**（B13.13 音画对齐） | A |
/// | ② | 点**卡内任意处**即可开（**卡外不生效**）：宝箱消失、播放器上屏；音效序列 = 落地 0.5（240ms）+ 开箱 0.5 | B |
/// | ③ | 5s 播完 → `onOpened` **恰好一次** | B |
/// | ④ | 不点：8s 后自动开（宝箱态消失） | C |
/// | ⑤ | 高级宝箱有「高级」角标 + 主题色光晕；普通宝箱没有 | D |
/// | ⑥ | 宝箱态**没有「跳过」**，且系统返回**不关卡**（`PopScope`） | E |
/// | ⑦ | 已领取态**不演宝箱**（`guardStageAfterBattle` 纯函数） | F |
/// | ⑧ | 几何纯函数：落下单调、回弹小于落差、落定归零、挤压收敛 | G |
/// | ⑨ | **只占场景卡那一块**（B13.12）：舞台矩形 = 卡宽 × 112、宝箱在小怪车道上、卡外点击不生效 | H |
///
/// ## 🔴 绝不 `pumpAndSettle()`
/// `idle` 期有**无限**呼吸动画 + 8s `Timer` —— `pumpAndSettle` 会一路推进到
/// 开箱播完（甚至超时），断言全部作废。全文件统一定长 `pump(Duration)`。
library guard_chest_stage_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/audio_service.dart' show AudioCue;
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_card_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';

/// 一次音效调用的记录（[GuardChestStage.playSfx] 的测试接缝）。
class _SfxLog {
  final List<AudioCueCall> calls = <AudioCueCall>[];

  /// 转发给 [GuardChestStage.playSfx] 的播放器（记录 cue 与 volume）。
  void play(AudioCue cue, {double volume = 1.0}) {
    calls.add(AudioCueCall(cue: cue, volume: volume));
  }
}

/// 一条音效调用。
class AudioCueCall {
  AudioCueCall({required this.cue, required this.volume});

  final AudioCue cue;
  final double volume;
}

final AppLocalizations _zh = AppLocalizationsZh();

/// 把宝箱演出层单独挂在一屏里（普通 `Scaffold`，没有可 pop 的路由）。
///
/// 🔴 B13.12 尺寸契约：本层自身 = **一张场景卡**（宽 = 父约束的卡宽、高恒
/// `kGuardSceneCardHeight`、在父约束里顶部对齐）⇒ 挂进 `Scaffold.body` 后它
/// 正好占 `y ∈ [0, 112)`。故「卡内」= y < 112，「卡外」= y ≥ 112。
Future<_SfxLog> _pumpStage(
  WidgetTester tester, {
  GuardChestTier tier = GuardChestTier.normal,
  bool autoOpen = true,
  VoidCallback? onOpened,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final _SfxLog log = _SfxLog();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuardChestStage(
          tier: tier,
          l10n: _zh,
          autoOpen: autoOpen,
          playSfx: log.play,
          onOpened: onOpened ?? () {},
        ),
      ),
    ),
  );
  // 挂载帧 + 让「帧列表解析」这条 async 走完（不推进动画时间）。
  await tester.pump();
  await tester.pump();
  return log;
}

/// 「卡内」的一个点（离宝箱本体很远，但在卡矩形里）。
const Offset _insideCard = Offset(10, 10);

/// 「卡外」的一个点（卡高 112 之下 ⇒ 宝箱层不该吃这一次点击）。
const Offset _outsideCard = Offset(10, 400);

/// 反复 `pump` 直到 [finder] 命中（**不用** `pumpAndSettle`）。
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  expect(finder, findsWidgets, reason: '等待超时：目标 widget 一直没出现');
}

/// 推进到「落定静止」这一帧。
///
/// ⚠️ 为什么是 600ms + 50ms 而不是恰好 600ms：`AnimationController` 的
/// `completed` 状态与监听回调落在**到点后的下一次 tick**（实测：恰好 pump(600)
/// 时画面已落定，但 `_onDropStatus` 还没被派发）。多给 50ms 是刻意的「一帧余量」，
/// 断言仍然只写死 600（落下时长）这一个字面量。
Future<void> _settleDrop(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: kGuardChestDropMs));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 推进到「开箱 5s 播完」之后（同样多给一帧余量让 completed 回调派发）。
Future<void> _finishOpening(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: kGuardChestOpenMs));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① drop → idle ────────────────────────────────────────────────────
  group('① 落下 600ms ⇒ 静止（提示 0.9s 淡入）', () {
    testWidgets('挂载即 drop（宝箱在、播放器不在）；600ms 后进 idle、提示不透明度 = 1',
        (WidgetTester tester) async {
      await _pumpStage(tester);

      expect(find.byKey(GuardChestStage.stageKey), findsOneWidget,
          reason: '宝箱演出层必须上屏');
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget,
          reason: 'drop 期渲染静态首帧（frame001）');
      expect(find.byKey(GuardChestStage.openPlayerKey), findsNothing,
          reason: 'drop 期还没开箱');
      expect(
          tester
              .widget<AnimatedOpacity>(find.byKey(GuardChestStage.tapHintKey))
              .opacity,
          0.0,
          reason: '提示在 idle 之前不可见（不是一上来就催孩子点）');

      // 走到 idle（drop 恰好 600ms）。
      await _settleDrop(tester);
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget);
      expect(
          tester
              .widget<AnimatedOpacity>(find.byKey(GuardChestStage.tapHintKey))
              .opacity,
          1.0,
          reason: 'idle 期提示必须亮起（0.9s 淡入的终点）');

      // 收尾：让 8s 自动开 + 5s 播完走完，避免「Timer still pending」。
      await tester.pump(const Duration(milliseconds: kGuardChestAutoOpenMs));
      await tester.pump();
      await _finishOpening(tester);
    });

    testWidgets('🔴 落地音效播在 fall 段结束（240ms），不是 600ms（B13.13 音画对齐）',
        (WidgetTester tester) async {
      final _SfxLog log = await _pumpStage(tester, autoOpen: false);
      // fall 段 = kGuardChestDropFallRatio(0.40) × 600ms = 240ms —— 画面砸地。
      await tester.pump(const Duration(milliseconds: 200));
      expect(log.calls, isEmpty,
          reason: '200ms（还在加速下落）不得出声 —— 旧实现播在 600ms，'
              '声音比画面晚 360ms（玄参真机实测「落地声音慢了一些」的根因）');
      await tester.pump(const Duration(milliseconds: 60)); // 累计 260ms
      expect(log.calls.length, 1,
          reason: '260ms ≥ 240ms：画面砸地的那一帧后必须已经出声（误差 ≤ 1 帧）');
      expect(log.calls.single.cue, AudioCue.guardChestLand);
      expect(log.calls.single.volume, 0.5,
          reason: '落地音效音量 0.5（B13.13 裁定，与开箱音统一）');
      // 收尾：走到 idle 后停掉（autoOpen=false 无 Timer；unmount 即 dispose）。
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  // ── ②③ 点击卡内开箱 + 5s 播完回调 ────────────────────────────────────
  group('② 点卡内任意处开箱（卡外不生效）；③ 5s 播完回调恰好一次', () {
    testWidgets('点卡内 (10,10) 也能开：宝箱消失、播放器上屏、音效 0.5、5s 后 onOpened=1',
        (WidgetTester tester) async {
      int opened = 0;
      final _SfxLog log =
          await _pumpStage(tester, onOpened: () => opened++);
      await _settleDrop(tester);

      // 🔴 热区（B13.12）：**卡内**离宝箱最远的那一角也必须能开。
      await tester.tapAt(_insideCard);
      await tester.pump();

      expect(find.byKey(GuardChestStage.chestKey), findsNothing,
          reason: '开箱起播后静止宝箱必须让位（宝箱态结束的判据）');
      await _pumpUntil(tester, find.byKey(GuardChestStage.openPlayerKey));
      expect(find.byKey(GuardChestStage.openPlayerKey), findsOneWidget);

      // 音效：落地（fall 段结束已播）+ 开箱（点击）两条按序；字面量断言，不引常量反推。
      expect(log.calls.length, 2, reason: '落地音效 1 条（2026-11-12 新增）+ 点击开箱音效 1 条');
      expect(log.calls[0].cue, AudioCue.guardChestLand,
          reason: '落地音效在 fall 段结束（240ms）已播（_settleDrop 已推进过 600ms）');
      expect(log.calls[0].volume, 0.5,
          reason: '🔴 落地音效音量必须是 0.5（玄参 2026-11-12 B13.13 裁定，与开箱统一）');
      expect(log.calls[1].cue, AudioCue.guardChestOpen);
      expect(log.calls[1].volume, 0.5,
          reason: '🔴 开箱音效音量必须是 0.5（玄参 Q-04 裁定）');

      // 5s 播完（帧率断言见 guard_chest_overlay_test）。
      expect(opened, 0, reason: '5s 未到不得回调');
      await tester.pump(const Duration(milliseconds: 2500));
      expect(opened, 0, reason: '2.5s 时仍在播');
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1, reason: '🔴 5000ms 到点必须回调 onOpened 一次');

      // 幂等：再推一段不会再回调（`_finished` 闸门）。
      await tester.pump(const Duration(milliseconds: 1000));
      expect(opened, 1, reason: 'onOpened 只许一次（重复回调会让页面弹两张卡）');
    });

    testWidgets('重复点击卡内只起播一次（`_opening` 闸门）', (WidgetTester tester) async {
      final _SfxLog log = await _pumpStage(tester);
      await _settleDrop(tester);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.tapAt(const Offset(30, 30));
      await tester.pump();
      expect(log.calls.length, 2,
          reason: '落地音效 1 条（drop→idle）+ 开箱音效 1 条 —— 连点收敛到同一个 `_open()`（§7.4 幂等）');
      expect(log.calls[1].cue, AudioCue.guardChestOpen);
      expect(log.calls[1].volume, 0.5);
      await _finishOpening(tester);
    });

    // 🔴 新增（B13.12）：热区从「全屏」收到「卡矩形」—— 卡外那一次点击既不许
    //    开箱（宝箱还在、零音效），也不许把卡外当成热区「顺手」吃掉。
    testWidgets('卡外（y = 400，卡高只有 112）点击不生效：宝箱还在、零音效',
        (WidgetTester tester) async {
      final _SfxLog log = await _pumpStage(tester, autoOpen: false);
      await _settleDrop(tester);

      await tester.tapAt(_outsideCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(log.calls.length, 1,
          reason: '此刻只有落地音效（fall 段结束必播）；卡外点击不许开箱（热区只在场景卡内）');
      expect(log.calls.single.cue, AudioCue.guardChestLand,
          reason: '那 1 条必须是落地音效，不是开箱');
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget,
          reason: '卡外点击后宝箱态必须还在（没被起点开）');
      expect(find.byKey(GuardChestStage.openPlayerKey), findsNothing);

      // 收尾：卡内点一次走完开箱（不留 pending 动画）。
      await tester.tapAt(_insideCard);
      await tester.pump();
      await _finishOpening(tester);
      expect(log.calls.length, 2, reason: '卡外点击未新增音效；真正开箱的只有卡内那一次');
      expect(log.calls[1].cue, AudioCue.guardChestOpen);
      expect(log.calls[1].volume, 0.5,
          reason: '开箱音效音量 0.5（Q-04）');
    });
  });

  // ── ④ 8s 自动开 ──────────────────────────────────────────────────────
  group('④ 不点：8s 无操作自动开', () {
    testWidgets('pump(8000ms) 后自动进入开箱（宝箱态消失、音效已播）',
        (WidgetTester tester) async {
      final _SfxLog log = await _pumpStage(tester);
      // 600ms 落地（落地音效在 240ms 已播）+ 7.4s 等待 = 8s 到点。
      // 🔴 必须像真实帧节奏一样先推进 600ms：单个 pump(8000) 会让 8s Timer
      //    先触发 `_open()`（phase 切 opening），随后 drop 的 completed 回调
      //    被 `_phase != drop` 闸门拦掉 ⇒ 落地音效被吞 —— 那是测试泵帧伪影，
      //    不是生产行为（真实运行每帧都在走，600ms 落地音必播）。
      await _settleDrop(tester);
      expect(log.calls.length, 1, reason: '落地音效先播（fall 段结束 240ms 必播）');
      await tester.pump(
          const Duration(milliseconds: kGuardChestAutoOpenMs - kGuardChestDropMs));
      expect(log.calls.length, 2,
          reason: '落地音效 1 条（600ms）+ 8s 自动开箱音效 1 条');
      expect(log.calls[1].cue, AudioCue.guardChestOpen,
          reason: '第 2 条才是自动开箱的音效');
      expect(log.calls[1].volume, 0.5);
      expect(find.byKey(GuardChestStage.chestKey), findsNothing,
          reason: '自动开箱后宝箱态必须结束');
      await _pumpUntil(tester, find.byKey(GuardChestStage.openPlayerKey));
      await _finishOpening(tester);
    });

    testWidgets('autoOpen=false ⇒ 15s 也不自己开（测试接缝本身可信）',
        (WidgetTester tester) async {
      final _SfxLog log = await _pumpStage(tester, autoOpen: false);
      await tester.pump(
          const Duration(milliseconds: kGuardChestAutoOpenMs + 7000));
      expect(log.calls.length, 1,
          reason: '关掉接缝后没有自动开箱音效；唯一 1 条是 fall 段结束的落地音效（必播）');
      expect(log.calls.single.cue, AudioCue.guardChestLand);
      expect(log.calls.single.volume, 0.5,
          reason: '落地音效音量 0.5（B13.13 裁定）');
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget);
    });
  });

  // ── ⑤ 高级宝箱的视觉区分 ──────────────────────────────────────────────
  group('⑤ 高级宝箱：角标 + 光晕；普通宝箱没有', () {
    testWidgets('premium ⇒ 「高级宝箱」角标在树；normal ⇒ 找不到',
        (WidgetTester tester) async {
      await _pumpStage(tester, tier: GuardChestTier.premium, autoOpen: false);
      await _settleDrop(tester);
      expect(find.byKey(GuardChestStage.premiumBadgeKey), findsOneWidget,
          reason: '🔴 高级宝箱必须能一眼看出来（玄参：「要看效果」）');
      expect(find.text(_zh.guard_chest_name_premium), findsWidgets,
          reason: '角标文案走 ARB（zh/en 双语）');

      await _pumpStage(tester, tier: GuardChestTier.normal, autoOpen: false);
      await _settleDrop(tester);
      expect(find.byKey(GuardChestStage.premiumBadgeKey), findsNothing,
          reason: '普通宝箱不得有「高级」角标（否则档位无从分辨）');
    });
  });

  // ── ⑥ 不可跳过 ───────────────────────────────────────────────────────
  group('⑥ 宝箱阶段不可跳过', () {
    testWidgets('找不到任何「跳过」；系统返回手势不关卡（PopScope）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final _SfxLog log = _SfxLog();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: TextButton(
                  onPressed: () => showGuardChestOverlay(
                    context,
                    tier: GuardChestTier.normal,
                    l10n: _zh,
                    playSfx: log.play,
                  ),
                  child: const Text('pop'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pop'));
      // overlay 入场过渡（200ms）+ 落地（600ms）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _settleDrop(tester);
      expect(find.byKey(GuardChestStage.stageKey), findsOneWidget);

      // 🔴 没有任何「跳过」入口。
      expect(find.text('跳过'), findsNothing, reason: '🔴 宝箱阶段不许有跳过按钮');
      expect(find.textContaining('跳过'), findsNothing);

      // 🔴 系统返回（Android 返回键 / iOS 返回手势）不得关卡。
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(GuardChestStage.stageKey), findsOneWidget,
          reason: '🔴 PopScope(canPop:false) 必须挡住系统返回');

      // 8s 自动开 + 5s 播完 ⇒ overlay 自己关掉（页面据此弹结算卡）。
      await tester.pump(const Duration(milliseconds: kGuardChestAutoOpenMs));
      // 自动开在 Timer 回调里 setState ⇒ 再泵一帧把播放器挂上（它的 5s 从此刻起算）。
      await tester.pump();
      expect(find.byKey(GuardChestStage.openPlayerKey), findsOneWidget,
          reason: '自动开后必须挂上开箱播放器');
      await _finishOpening(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(GuardChestStage.stageKey), findsNothing,
          reason: '30 帧播完 ⇒ 宝箱 overlay 必须收场');
    });
  });

  // ── ⑦ 已领取态不演宝箱 ───────────────────────────────────────────────
  group('⑦ guardStageAfterBattle：已领取态不演宝箱', () {
    GuardTodayView viewOf(GuardDayStatus status) => GuardTodayView(
          mode: status == GuardDayStatus.claimed
              ? GuardPillMode.claimed
              : GuardPillMode.fighting,
          state: GuardDayState(
            dayKey: '2026-11-11',
            status: status,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 4,
            chestTier: GuardChestTier.premium,
          ),
          energyAvailable: 1,
          balance: 10,
        );

    test('claimed ⇒ 直接进结算卡（不演宝箱）', () {
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.claimed)),
          GuardShowStage.settled,
          reason: '🔴 已领取 = 东西早进账，再演一遍等于承诺第二份奖励');
    });

    test('fighting ⇒ chestDrop（普通 / 高级都演）', () {
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.fighting)),
          GuardShowStage.chestDrop);
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.pending)),
          GuardShowStage.chestDrop,
          reason: '旧存档 / 未领取都照常演宝箱');
    });
  });

  // ── ⑧ 几何纯函数 ─────────────────────────────────────────────────────
  group('⑧ 落下几何：单调下落、回弹幅度、落定归零', () {
    test('起点 = -78pt（卡顶之外一点），末尾（t=1）= 0', () {
      expect(GuardChestStage.dropOffsetDy(0), -78,
          reason: '起点 = −(边长 66 + 顶部余量 12)，'
              '起手瞬间箱子底边正好压在卡顶线上（整只在卡外）');
      expect(GuardChestStage.dropOffsetDy(1), 0, reason: '落定必须归零');
    });

    test('下落段（0→0.4）单调递增，且 t=0.4 恰好为 0', () {
      double prev = GuardChestStage.dropOffsetDy(0);
      for (double t = 0.02; t <= kGuardChestDropFallRatio + 1e-9; t += 0.02) {
        final double cur = GuardChestStage.dropOffsetDy(t);
        expect(cur, greaterThanOrEqualTo(prev), reason: 't=$t 时纵向位置回跳了');
        prev = cur;
      }
      expect(GuardChestStage.dropOffsetDy(kGuardChestDropFallRatio),
          closeTo(0, 1e-9));
    });

    test('回弹段抬升 ≤ 8pt（「轻微」；远小于 78pt 的实测落差）', () {
      double peak = 0;
      for (double t = kGuardChestDropFallRatio;
          t <= kGuardChestDropBounceEndRatio;
          t += 0.005) {
        final double dy = GuardChestStage.dropOffsetDy(t);
        expect(dy, lessThanOrEqualTo(0), reason: '回弹只能向上（负值），不许钻到落点之下');
        if (-dy > peak) peak = -dy;
      }
      // 字面量 8 = kGuardChestDropBouncePt；峰值必须贴近它（正弦半波顶点）。
      expect(peak, closeTo(8, 0.2));
    });

    test('挤压：下落段恒 1.0，回弹段峰值 ≈1.06，落定回到 1.0', () {
      expect(GuardChestStage.squashScale(0), 1.0);
      expect(GuardChestStage.squashScale(kGuardChestDropFallRatio), 1.0);
      expect(GuardChestStage.squashScale(1), 1.0);
      double peak = 1.0;
      for (double t = kGuardChestDropFallRatio;
          t <= kGuardChestDropBounceEndRatio;
          t += 0.005) {
        final double s = GuardChestStage.squashScale(t);
        if (s > peak) peak = s;
      }
      expect(peak, closeTo(1.06, 0.01));
    });

    test('卡内尺寸：边长 66（B13.15 缩小；窄卡 ×0.85）、底边 96 贴地、整只不出卡', () {
      // 390 卡（scale 1.0）：边长 = kGuardChestCardBoxSide = 66（玄参「有点大」：76→66）。
      expect(GuardChestStage.boxSideOf(390), closeTo(66, 1e-9));
      // 320 卡（窄卡，scale 0.85）：66 × 0.85 = 56.1（与卡内其他元素同口径）。
      expect(GuardChestStage.boxSideOf(320), closeTo(56.1, 1e-9));
      // 底边 = 112 − 16 = 96（B13.15「好像没落地」：24 → 16，下移 8pt 贴地）。
      expect(GuardChestStage.boxBottomOf(), closeTo(96, 1e-9));
      expect(GuardChestStage.boxBottomOf(),
          lessThan(const GuardCardLayout(390).countdownRect.top),
          reason: '箱子底边必须在卡底倒计时细线（y = 102）之上，不许压计时条');
    });
  });

  // ── ⑨ 只占场景卡那一块（B13.12 玄参第六轮）─────────────────────────────
  group('⑨ 只占场景卡那一块：舞台 = 卡宽 × 112、宝箱在小怪车道上', () {
    testWidgets('舞台矩形 = 390 × 112（不是全屏），宝箱整只落在卡内',
        (WidgetTester tester) async {
      await _pumpStage(tester, autoOpen: false);
      await _settleDrop(tester);

      final Rect stage =
          tester.getRect(find.byKey(GuardChestStage.stageKey));
      expect(stage.size, const Size(390, kGuardSceneCardHeight),
          reason: '🔴 宝箱层自身就是一张场景卡（宽 = 卡宽、高 = 112），'
              '不再是全屏 overlay');
      expect(stage.top, 0, reason: '在父约束里顶部对齐（弹层那边由卡矩形定位）');

      final Rect box = tester.getRect(find.byKey(GuardChestStage.chestKey));
      expect(box.top, greaterThanOrEqualTo(stage.top),
          reason: '宝箱不许出卡顶（呼吸 + 回弹也在卡内）');
      expect(box.bottom, lessThanOrEqualTo(stage.bottom),
          reason: '宝箱不许出卡底');
      expect(box.right, lessThanOrEqualTo(stage.right),
          reason: '宝箱不许出卡右缘');
      expect(box.height, closeTo(kGuardChestCardBoxSide, 2),
          reason: '边长 = 卡内口径 76（±2 是 1.02 倍高级光晕圈的取整余量）');
    });

    test('宝箱落点 = 旗心左移 15pt（「插旗的位置」再偏左，不是随手居中）', () {
      // 390 卡（scale 1.0）：rightClusterRect = [318, 382]，中心 350 ⇒
      // 宝箱中心 = 350 − 15（B13.15 玄参「太靠右，往左挪 15pt」）= 335，
      // left = 335 − 33 = 302，占 [302, 368]。
      // （沿革：B13.12 218.17 → B13.13 276 → B13.14 312 → B13.15 302。）
      const GuardCardLayout layout = GuardCardLayout(390);
      final Rect chest = GuardChestStage.chestRectOf(390);
      expect(chest.center.dx,
          closeTo(layout.rightClusterRect.center.dx - 15, 1e-9),
          reason: '宝箱中心 = 旗心左移 15pt（kGuardChestCardCenterShiftPt）');
      expect(chest.left, closeTo(302, 1e-9),
          reason: '390 卡字面量（K26~K28：期望值独立于实现）');
      // 纵向：底边 96 贴地（B13.15「好像没落地」），仍在小怪水平带之下不远。
      expect(chest.bottom, closeTo(96, 1e-9));
      // 不许出卡右缘（钳制线 = cardWidth − side；演出期槽位为空）。
      expect(chest.right, lessThanOrEqualTo(390 + 1e-9));

      // 窄卡 320（scale 0.85）：仍整只落在卡内（中心对齐后钳制不出卡）。
      final Rect narrow = GuardChestStage.chestRectOf(320);
      expect(narrow.left, greaterThanOrEqualTo(0));
      expect(narrow.right, lessThanOrEqualTo(320));
      expect(narrow.width, closeTo(56.1, 1e-9));
    });

    test('顶部余量够：静止顶边 − (回弹 8 + 呼吸 2) 仍在卡内', () {
      final Rect chest = GuardChestStage.chestRectOf(390);
      expect(chest.top - kGuardChestDropBouncePt - 2, greaterThanOrEqualTo(0),
          reason: '静止顶边 30 − 10 = 20 ≥ 0（边长 66 + 底边 96 ⇒ 顶边 112−96−66=30）');
    });
  });

  // ── 装配断言：guardServiceProvider 必须接上碎片 / 种子发放端口 ──────────
  group('⑩ 装配：guardServiceProvider 的 bloomRewards 端口已注入', () {
    test('真实装配（内存 prefs + 内存库）后 hasBloomRewardPort == true', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(guardServiceProvider).hasBloomRewardPort, isTrue,
          reason: '🔴 漏注入 ⇒ 高级宝箱的碎片 / 种子会静默丢失（T01 把它做成可选参数）');
    });
  });
}
