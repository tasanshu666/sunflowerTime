/// 独立 QA 复核 · 「花园守卫 · 宝箱与结算演出」批次 **演出层** 探针。
///
/// 覆盖：
///  · QA-3  8s 自动开箱的 Timer 生命周期（卸载取消 / 开箱后取消 / 兜底真能开）；
///  · QA-4  结算卡卡面数字 == 到账额（阳光 / 碎片 / 种子）+ 入场 scale-in。
///
/// 🔴 纪律：本文件**绝不** `pumpAndSettle()`
/// （idle 期有无限呼吸 `AnimationController` + 8s `Timer`，会一路推进到超时）。
/// 帧率相关断言一律用 `Duration(microseconds: 166700)` 的整数倍。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/enum_l10n.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/platform/audio_service.dart' show AudioCue;
import 'package:sunflower_time/presentation/child/state/guard_today_state.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_chest_stage.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_result_card.dart';

final AppLocalizations _zh = AppLocalizationsZh();

/// 音效调用记录（[GuardChestStage.playSfx] 的测试接缝）。
class _SfxLog {
  final List<double> volumes = <double>[];
  final List<AudioCue> cues = <AudioCue>[];

  void play(AudioCue cue, {double volume = 1.0}) {
    cues.add(cue);
    volumes.add(volume);
  }
}

/// 把宝箱演出层挂在普通 `Scaffold` 里（无路由可 pop）。
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

/// 推进到「落定静止」（600ms + 一帧余量，不写 650 这种魔数）。
Future<void> _settleDrop(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: kGuardChestDropMs));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 卸载整棵树（模拟「孩子在 idle 期离开今日页 / 强杀」）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

/// 造一张结算卡要用的 view。
GuardTodayView _view({
  required GuardChestTier tier,
  int winSun = 4,
  int fragments = 0,
  GuardSeedKind seedKind = GuardSeedKind.none,
  String? speciesId,
  GuardDropKind drop = GuardDropKind.waterVoucher,
  GuardDropKind bonusDrop = GuardDropKind.none,
}) {
  return GuardTodayView(
    mode: GuardPillMode.fighting,
    state: GuardDayState(
      dayKey: '2026-11-09',
      status: GuardDayStatus.fighting,
      thiefKind: GuardThiefKind.sunRat,
      winSun: winSun,
      dropKind: drop,
      chestTier: tier,
      chestBonusDropKind: bonusDrop,
      chestFragmentQty: fragments,
      chestSeedKind: seedKind,
      chestSeedSpeciesId: speciesId,
    ),
    energyAvailable: 1,
    balance: 10,
  );
}

/// 把结算卡直接挂起来（自带 320ms 入场动画，一次性控制器）。
Future<void> _pumpCard(WidgetTester tester, GuardTodayView view) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GuardResultCard(
          view: view,
          l10n: _zh,
          onCollect: () async => throw UnimplementedError(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // QA-3 🔴 8s 自动开的 Timer 不泄漏
  // ══════════════════════════════════════════════════════════════════════
  group('QA-3 8s Timer 生命周期', () {
    testWidgets('QA-3a idle 期直接卸载 ⇒ 不得留 pending Timer（框架会判红）',
        (WidgetTester tester) async {
      // ⚠️ 这条用例的**断言就是「测试结束时没有 pending timer」**：
      //    flutter_test 在结束时会检查 fake async 队列，若 `dispose()` 漏了
      //    `_autoOpenTimer?.cancel()`，本用例会以
      //    「A Timer is still pending even after the widget tree was disposed」
      //    直接失败 —— 无需额外断言语句。
      final _SfxLog log = await _pumpStage(tester);
      await _settleDrop(tester);
      expect(find.byKey(GuardChestStage.chestKey), findsOneWidget,
          reason: '前置：已进入 idle（8s Timer 正在计时）');
      expect(log.cues, <AudioCue>[AudioCue.guardChestLand],
          reason: '前置：只播过落地音效（drop→idle，2026-11-12 新增），还没开箱');

      await _unmount(tester);
      expect(find.byKey(GuardChestStage.stageKey), findsNothing);

      // 再推 12s：若 Timer 泄漏，这里会触发 _open 并可能再起动画。
      await tester.pump(const Duration(milliseconds: 12000));
      expect(log.cues, <AudioCue>[AudioCue.guardChestLand],
          reason: '卸载后不得再播开箱音效（唯一 1 条仍是落地音）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('QA-3b 点开之后 8s 不得再触发第二次开箱（音效只 1 次 / 回调只 1 次）',
        (WidgetTester tester) async {
      int opened = 0;
      final _SfxLog log = await _pumpStage(tester, onOpened: () => opened++);
      await _settleDrop(tester);

      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(log.cues, <AudioCue>[AudioCue.guardChestLand, AudioCue.guardChestOpen],
          reason: '落地音效（drop→idle）+ 点击立刻起播的开箱音效');

      // 5s 播完（166.7ms × 30 帧）。
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(microseconds: 166700));
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1, reason: '5s 到点必须回调一次');

      // 越过 8s 自动开的时间点（挂载起算），再推一大段。
      await tester.pump(const Duration(milliseconds: kGuardChestAutoOpenMs));
      expect(log.cues, hasLength(2),
          reason: '🔴 开箱后 8s Timer 必须已取消；否则会再播第 3 次音效');
      expect(opened, 1, reason: 'onOpened 只许一次（重复回调会让页面弹两张卡）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('QA-3c 不点：8s 兜底路径真的存在且真的能开（结算卡前提成立）',
        (WidgetTester tester) async {
      int opened = 0;
      final _SfxLog log = await _pumpStage(tester, onOpened: () => opened++);
      await _settleDrop(tester);
      expect(log.cues, <AudioCue>[AudioCue.guardChestLand],
          reason: '此刻只有落地音效（fall 段结束 240ms 播）');

      // 从挂载起算 8s（这里已过 650ms ⇒ 再推 7.35s + 一帧余量）。
      await tester.pump(const Duration(milliseconds: kGuardChestAutoOpenMs));
      expect(log.cues, <AudioCue>[AudioCue.guardChestLand, AudioCue.guardChestOpen],
          reason: '🔴 8s 无操作必须自动开箱（第 2 条是开箱音效）');
      expect(log.volumes, <double>[0.5, 0.5],
          reason: '落地 0.5（B13.13 裁定）；自动开也走 0.5 同一个音量口径');
      expect(find.byKey(GuardChestStage.chestKey), findsNothing,
          reason: '自动开后宝箱态必须结束');
      expect(find.byKey(GuardChestStage.openPlayerKey), findsOneWidget,
          reason: '自动开后必须挂上 30 帧播放器');

      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(microseconds: 166700));
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1, reason: '兜底路径也必须能走到 onOpened（否则页面永远弹不出结算卡）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('QA-3d 30 帧 / 5s ⇒ 每 166.7ms 恰好推进一帧（6fps，不是 30fps）',
        (WidgetTester tester) async {
      // 用播放器的「当前帧下标」间接断言帧率：5s 播 30 帧。
      // ⚠️ 只读公开 widget：FrameSequencePlayer 暴露的 Image 的 key 不含帧号，
      //    故这里用「5s 整点完成 / 4.4s 未完成」两个抽样点钉住时长（±1 帧）。
      int opened = 0;
      await _pumpStage(tester, onOpened: () => opened++);
      await _settleDrop(tester);
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      await tester.pump(); // 让 FrameSequencePlayer 挂上并起播

      // 26 帧 = 4.334s ⇒ 还没播完
      for (int i = 0; i < 26; i++) {
        await tester.pump(const Duration(microseconds: 166700));
      }
      expect(opened, 0, reason: '4.334s（26 帧）时不得完成');

      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(microseconds: 166700));
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1, reason: '30 帧 = 5.001s ⇒ 完成');
      expect(kGuardChestOpenMs, 5000);
      expect(kGuardChestFrameCount, 30);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // QA-4 🔴 卡面 == 到账额
  // ══════════════════════════════════════════════════════════════════════
  group('QA-4 结算卡卡面', () {
    testWidgets('高级宝箱：卡面阳光 = 基础 × 2（+8，不是 +4）', (WidgetTester tester) async {
      await _pumpCard(tester, _view(tier: GuardChestTier.premium, winSun: 4));
      expect(find.text('+8'), findsOneWidget,
          reason: '🔴 卡面 N 必须恒等于账本 guard_win 行（领域层用例已对账）');
      expect(find.text('+4'), findsNothing, reason: '普通档的数字不得出现在高级档');
    });

    testWidgets('普通宝箱：卡面阳光 = 基础值（+4，不翻倍）', (WidgetTester tester) async {
      await _pumpCard(tester, _view(tier: GuardChestTier.normal, winSun: 4));
      expect(find.text('+4'), findsOneWidget);
      expect(find.text('+8'), findsNothing, reason: '🔴 免费/普通档不得白送翻倍');
    });

    testWidgets('碎片卡 +1 / +2 与片数一致；普通档不渲染碎片卡', (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(tier: GuardChestTier.premium, fragments: 1),
      );
      expect(find.byKey(GuardResultCard.fragmentRewardKey), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);

      await _pumpCard(
        tester,
        _view(tier: GuardChestTier.premium, fragments: 2),
      );
      expect(find.text('+2'), findsOneWidget);

      await _pumpCard(tester, _view(tier: GuardChestTier.normal, fragments: 0));
      expect(find.byKey(GuardResultCard.fragmentRewardKey), findsNothing,
          reason: '普通档不得出现碎片卡（也不许出现 +0 占位）');
      expect(find.byKey(GuardResultCard.seedRewardKey), findsNothing);
      expect(find.byKey(GuardResultCard.bonusVoucherRewardKey), findsNothing);
    });

    testWidgets('种子卡：×1 + 物种名（SpeciesId 映射走 ARB，不显示原始 id）',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(
          tier: GuardChestTier.premium,
          seedKind: GuardSeedKind.common,
          speciesId: 'species_tomato',
        ),
      );
      expect(find.byKey(GuardResultCard.seedRewardKey), findsOneWidget);
      expect(find.textContaining('species_tomato'), findsNothing,
          reason: '卡面不得漏出内部 speciesId（孩子看不懂的机器名）');
      expect(find.text('×1'), findsOneWidget);
    });

    testWidgets('双券：主券 + 第二张券各一张卡，且两张不同种（不画两张一样的）',
        (WidgetTester tester) async {
      await _pumpCard(
        tester,
        _view(
          tier: GuardChestTier.premium,
          drop: GuardDropKind.waterVoucher,
          bonusDrop: GuardDropKind.freeWater,
        ),
      );
      expect(find.byKey(GuardResultCard.voucherRewardKey), findsOneWidget);
      expect(find.byKey(GuardResultCard.bonusVoucherRewardKey), findsOneWidget);

      // 两张卡上的券名必须不同（同种 = 画了两张一样的）。
      final String watering = guardDropName(GuardDropKind.waterVoucher, _zh);
      final String freeWater = guardDropName(GuardDropKind.freeWater, _zh);
      expect(watering, isNot(freeWater), reason: '前置：ARB 里两档文案不同');
      expect(find.text(watering), findsOneWidget);
      expect(find.text(freeWater), findsOneWidget);
    });

    testWidgets('🔴 同种券（构造层硬造 bonusDrop == drop）⇒ 只画一张券卡，不画两张一样的',
        (WidgetTester tester) async {
      // 背景：这个分支**依赖派生层不变量**（`_pickOtherVoucher` 保证
      // `bonusDropKind != dropKind`）所以生产路径走不到；但表现层在收尾时补了
      // `bonusDropKind != dropKind` 的去重条件（`guard_result_card.dart`），
      // 本用例把「去重条件」本身钉住：上游哪天放宽了不变量，这里也不能画出
      // 两张一模一样的券卡。
      //
      // 🔴 这不是「硬造不可能的状态」：`GuardTodayView` 的 `bonusDropKind` getter
      // 只做「优先 chestBonusDropKind，否则退回旧 bonusDropKind」的取舍，
      // **没有**任何「强制与 dropKind 不同」的归一化 ⇒ 同种是构造得出来的。
      await _pumpCard(
        tester,
        _view(
          tier: GuardChestTier.premium,
          drop: GuardDropKind.waterVoucher,
          bonusDrop: GuardDropKind.waterVoucher,
        ),
      );

      // 前置：确认构造出来的两个档位**真的是同一种**（否则本用例什么也没测）。
      final Finder card = find.byType(GuardResultCard);
      final GuardResultCard widget = tester.widget<GuardResultCard>(card);
      expect(widget.view.dropKind, GuardDropKind.waterVoucher);
      expect(widget.view.bonusDropKind, GuardDropKind.waterVoucher,
          reason: '前置：view 层不做「强制不同」归一化，同种必须能构造出来');

      expect(find.byKey(GuardResultCard.voucherRewardKey), findsOneWidget,
          reason: '第一张券（主券）照常画');
      expect(find.byKey(GuardResultCard.bonusVoucherRewardKey), findsNothing,
          reason: '🔴 第二张券与第一张同种 ⇒ 必须去重不画（否则孩子看到两张一样的券）');

      // 券名文案也只能出现一次（「两张卡不同 key 但同文案」同样算画了两次）。
      final String watering = guardDropName(GuardDropKind.waterVoucher, _zh);
      expect(find.text(watering), findsOneWidget,
          reason: '券名文案只允许出现一次（去重后没有第二张同名卡）');
    });

    testWidgets('入场：scale 从 0.86 弹到 1.0（320ms，一次性，不停留 ticker）',
        (WidgetTester tester) async {
      await _pumpCard(tester, _view(tier: GuardChestTier.normal));
      double scaleNow() => tester
          .widget<ScaleTransition>(find.byKey(GuardResultCard.scaleKey))
          .scale
          .value;

      // 首帧（t=0）读的是 begin 端。
      expect(scaleNow(), closeTo(0.86, 0.02),
          reason: '🔴 「从小到大弹出」必须真的从 0.86 起');

      await tester.pump(
          const Duration(milliseconds: GuardResultCard.entryScaleMs));
      await tester.pump();
      expect(scaleNow(), closeTo(1.0, 0.02), reason: '320ms 后必须到 1.0');

      // 一次性控制器：再推 2s 不得继续变化（也不得留下 ticker）。
      await tester.pump(const Duration(seconds: 2));
      expect(scaleNow(), closeTo(1.0, 0.02));
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 阶段机：战斗结束后的下一阶段（纯函数）
  // ══════════════════════════════════════════════════════════════════════
  group('阶段机 guardStageAfterBattle', () {
    GuardTodayView viewOf(GuardDayStatus status, GuardChestTier tier) =>
        GuardTodayView(
          mode: GuardPillMode.fighting,
          state: GuardDayState(
            dayKey: '2026-11-09',
            status: status,
            thiefKind: GuardThiefKind.sunRat,
            winSun: 4,
            chestTier: tier,
          ),
          energyAvailable: 1,
          balance: 10,
        );

    test('未领取 ⇒ 必演宝箱（chestDrop），普通 / 高级都一样', () {
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.pending, GuardChestTier.normal)),
          GuardShowStage.chestDrop);
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.fighting, GuardChestTier.premium)),
          GuardShowStage.chestDrop);
    });

    test('已领取 ⇒ 不演宝箱，直接结算卡', () {
      expect(guardStageAfterBattle(viewOf(GuardDayStatus.claimed, GuardChestTier.premium)),
          GuardShowStage.settled,
          reason: '🔴 已领 ⇒ 东西早进账，再演一遍等于承诺第二份奖励');
    });
  });
}
