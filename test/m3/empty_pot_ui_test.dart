/// 空花盆干扰物 **UI 接线**回归测试（F155-B，玄参 2026-10-27 拍板）。
///
/// 口径：空花盆每天也独立 roll 杂草 / 害虫，清理奖励与植物完全一致、**不阻挡种植**；
/// 种下后该盆干扰物立即消失（不返还、不再显示）。
///
/// 本文件只钉**接线**（域语义另有 `empty_pot_disturbance_test.dart`）：
///  ① [EmptyPot] 收到 `hasWeed` / `hasPest` 就画浮标（复用 [GardenPot] 那支浮标）；
///  ② 点浮标 → 触发 `onClearWeed` / `onClearPest`，且**不**触发整格 `onTap`
///     （否则「点掉草 + 弹种植选择」双反馈）；
///  ③ `weedFading` / `pestFading` 让浮标透明度归零（与有植物盆同一套淡出动画）；
///  ④ 浮标是 `Positioned` 叠加 → 空盆图片框的**尺寸**与「没浮标时」逐像素一致
///     （「空盆与有植物盆等大、同底」布局契约不被新玩法破坏）；
///  ⑤ 真实花园页：浮标 → 点击 → 浮标消失 + 阳光账本 +1 ☀（refType / refId 正确）；
///  ⑥ 真实花园页：浮标 → 点空盆种下 → 该盆浮标消失、且**不入账**（不返还）；
///  ⑦ **F156-A（玄参 2026-10-27）**：空盆拔草 / 除虫必须**完整播 4.1s 演出**（与有植物盆
///    同一条路径），演出期间 `_busy` 锁页 → 第二次点击被挡；收尾后才刷新草地 + 飘字；
///  ⑧ 淡出 300ms 窗口内的**重叠清除**：两张票据同时在飞也各自释放 → 本页仍能刷新
///    （票据泄漏守卫；F156-A 之前就存在的真实现象）。
library empty_pot_ui_test;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/plant_seed.dart';
import 'package:sunflower_time/data/local/repositories/in_memory_bloom_reward_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/care_effect_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';

// ── Fake：空盆干扰物仓储（内存）───────────────────────────────────────────────

class _MemPotDisturbanceRepo implements PotDisturbanceRepository {
  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      store.values.toList()..sort((PotDisturbance a, PotDisturbance b) =>
          a.potIndex.compareTo(b.potIndex));

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];

  @override
  Future<void> save(PotDisturbance disturbance) async {
    store[disturbance.potIndex] = disturbance;
  }

  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);

  @override
  Future<void> deleteAll() async => store.clear();
}

// ── Fake：随机源（固定序列，测试可确定性「必中 / 必不中」）────────────────────

/// 固定返回序列的 [Random]：只实现 [nextDouble]（干扰物 roll 唯一用到的方法）。
///
/// 命中判据是 `nextDouble() < rate`：喂 `0.0` = 必中、`0.99` = 必不中。
class _SeqRandom implements Random {
  _SeqRandom(this.values);

  final List<double> values;
  int calls = 0;

  @override
  double nextDouble() => values[calls++ % values.length];

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// 账本 Fake：只记录 append 条目 + 维护余额（其余对账口返回 0 / null）。
class _MemLedger implements SunlightRepository {
  double balanceValue = 1000;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> ofType(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    balanceValue += entry.net;
    return balanceValue;
  }

  @override
  Future<double> balance() async => balanceValue;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    final List<SunlightEntry> hits = ofType(refType);
    return hits.isEmpty ? null : hits.last;
  }

  @override
  Future<double> dayNet(String key) async => 0;
  @override
  Future<double> earnGrossOnDay(String key) async => 0;
  @override
  Future<double> earnNetOnDay(String key) async => 0;
  @override
  Future<double> verifiedRedeemTotal() async => 0;
  @override
  Future<double> netByRefTypeOnDay(String refType, String key) async => 0;
  @override
  Future<double> netByRefTypeInMonth(String refType, String key) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String key,
  ) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && e.dayKey == key)
          .length;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits =
        entries.where((SunlightEntry e) => e.refType == refType).toList();
    return hits.isEmpty ? null : hits.last.ts;
  }
}

class _FakeSettingsRepo implements SettingsRepository {
  /// 4 盆（与 `kGardenPotCapacityDefault` 一致，弹窗 / 一屏都放得下）。
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
        gardenPotCapacity: 4,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _NoFocusRepo implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String key) async =>
      const <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _MemPlantRepo implements PlantRepository {
  final List<Plant> store = <Plant>[];

  @override
  Future<List<Plant>> plants() async => List<Plant>.of(store);

  @override
  Future<Plant?> plant(String id) async {
    for (final Plant p in store) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> savePlant(Plant plant) async {
    store.removeWhere((Plant p) => p.id == plant.id);
    store.add(plant);
  }

  @override
  Future<void> deletePlant(String id) async =>
      store.removeWhere((Plant p) => p.id == id);

  @override
  Future<List<PlantSpecies>> species() async => kSeedPlantSpecies;
}

// ── 宿主与工具 ──────────────────────────────────────────────────────────────

/// 单挂一支 [EmptyPot]（走裸 `MaterialApp`：`l10nOf` 回退中文，与既有用例同构）。
Widget _hostPot(Widget pot) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 120, height: 240, child: pot),
        ),
      ),
    );

/// 命中「杂草浮标」的判据：`Image.asset(kGardenWeedAsset)`。
///
/// 用图片资源名匹配（而不是私有类型 / emoji 文本）：素材加载失败时组件回退 emoji，
/// 但 `Image` 节点仍在 → 无论加载成败都能定位到浮标。
Finder _weedChip() => find.byWidgetPredicate((Widget w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == kGardenWeedAsset);

Finder _pestChip() => find.byWidgetPredicate((Widget w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == kGardenPestAsset);

/// 有界帧推进（花园页木牌是无限呼吸动画 → 禁用 `pumpAndSettle`）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 120,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 一次「完整清除演出 + 淡出 + 刷新落地」的帧预算（F156-A）。
///
/// 空盆拔草 / 除虫现在与有植物盆**同一条时序**：4.1s 效果帧（[kCareWeedDurationMs]）
/// + 300ms 浮标淡出（[kPestFadeOutMs]）+ 一次 `_reload` 落地 ≈ 4.4s。
/// 按 16ms/帧 计需要 ≈ 275 帧，故给 420 帧（≈6.7s）余量；**仍然有界**（不是
/// `pumpAndSettle`：页面内有无限呼吸 / 飘浮动画，settle 会超时）。
const int _clearSettleFrames = 420;

/// 真实花园页宿主：只覆盖与花园相关的仓储 + 空盆服务（roll 随机源固定）。
///
/// `firstSightImmune: false`：首帧就掷骰，测试无需「隔天」即可拿到确定状态
/// （生产默认 true，见 `EmptyPotService` 文件头「首日免疫」段）。
///
/// [perk]：覆盖 `currentPlantPerkProvider`（门控单点）。传非 none 值即可验证
/// 页面确实把**称号属性**传进了空盆清除路径（否则称号「除草 +1」对空盆静默失效）。
Widget _hostGardenPage({
  required _MemPotDisturbanceRepo pots,
  required _MemLedger ledger,
  required _MemPlantRepo plants,
  PlantPerk perk = PlantPerk.none,
}) {
  final EmptyPotService svc = EmptyPotService(
    disturbances: pots,
    ledger: ledger,
    // 杂草必中（0.0 < 0.20）、害虫必不中（0.99 ≥ 0.15）。
    weedRandom: _SeqRandom(<double>[0.0]),
    pestRandom: _SeqRandom(<double>[0.99]),
    firstSightImmune: false,
  );
  return ProviderScope(
    overrides: <Override>[
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
      sunlightRepositoryProvider.overrideWithValue(ledger),
      focusRepositoryProvider.overrideWithValue(_NoFocusRepo()),
      plantRepositoryProvider.overrideWithValue(plants),
      bloomRewardRepositoryProvider
          .overrideWithValue(InMemoryBloomRewardRepository()),
      potDisturbanceRepositoryProvider.overrideWithValue(pots),
      emptyPotServiceProvider.overrideWithValue(svc),
      currentPlantPerkProvider.overrideWith((Ref ref) async => perk),
    ],
    child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
  );
}

void main() {
  // ── ①③④ 组件级：[EmptyPot] 的浮标渲染 / 点击分流 / 淡出 / 不改尺寸 ─────────
  group('①③④ EmptyPot 浮标（渲染 / 点击分流 / 淡出 / 尺寸契约）', () {
    testWidgets('hasWeed / hasPest → 两支浮标都渲染；无状态时不渲染', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_hostPot(EmptyPot(
        potIndex: 0,
        onTap: () {},
        hasWeed: true,
        hasPest: true,
      )));
      await tester.pump();
      expect(_weedChip(), findsOneWidget, reason: 'hasWeed → 必须画杂草浮标');
      expect(_pestChip(), findsOneWidget, reason: 'hasPest → 必须画害虫浮标');

      await tester.pumpWidget(_hostPot(EmptyPot(potIndex: 0, onTap: () {})));
      await tester.pump();
      expect(_weedChip(), findsNothing, reason: '默认无状态 → 不画浮标（既有调用点零改动）');
      expect(_pestChip(), findsNothing);
    });

    testWidgets('点浮标 → 只触发清除回调，不吃成「点整格」（不弹种植选择）', (
      WidgetTester tester,
    ) async {
      int clearWeed = 0;
      int clearPest = 0;
      int potTap = 0;
      await tester.pumpWidget(_hostPot(EmptyPot(
        potIndex: 0,
        onTap: () => potTap++,
        hasWeed: true,
        hasPest: true,
        onClearWeed: () => clearWeed++,
        onClearPest: () => clearPest++,
      )));
      await tester.pump();

      await tester.tap(_weedChip());
      await tester.pump();
      expect(clearWeed, 1, reason: '点杂草浮标 → 拔草回调');
      expect(potTap, 0, reason: '浮标 opaque 命中区必须吃掉点击，否则双反馈');

      await tester.tap(_pestChip());
      await tester.pump();
      expect(clearPest, 1, reason: '点害虫浮标 → 除虫回调');
      expect(potTap, 0);
    });

    testWidgets('weedFading / pestFading → 浮标透明度归零（同一套 kPestFadeOutMs 淡出）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_hostPot(EmptyPot(
        potIndex: 0,
        onTap: () {},
        hasWeed: true,
        hasPest: true,
        weedFading: true,
        pestFading: true,
      )));
      await tester.pump();

      double opacityOf(Finder chip) => tester
          .widget<AnimatedOpacity>(find
              .ancestor(of: chip, matching: find.byType(AnimatedOpacity))
              .first)
          .opacity;

      expect(opacityOf(_weedChip()), 0.0, reason: 'weedFading → 淡出到 0');
      expect(opacityOf(_pestChip()), 0.0, reason: 'pestFading → 淡出到 0');
      expect(
        tester
            .widget<AnimatedOpacity>(find
                .ancestor(of: _weedChip(), matching: find.byType(AnimatedOpacity))
                .first)
            .duration,
        const Duration(milliseconds: kPestFadeOutMs),
        reason: '与有植物盆同一套淡出时长（不新立一套动画）',
      );
    });

    testWidgets('④ 浮标不占布局高度：有 / 无浮标时空盆尺寸逐像素一致', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
          _hostPot(EmptyPot(potIndex: 0, onTap: () {})));
      await tester.pump();
      final Size plain = tester.getSize(find.byType(EmptyPot));
      // 图片框（`Align > SizedBox(artW×artH)`）的矩形：三类格子「等大、同底」的锚点。
      final Rect plainArt = tester.getRect(find.byType(Align).first);

      await tester.pumpWidget(_hostPot(EmptyPot(
        potIndex: 0,
        onTap: () {},
        hasWeed: true,
        hasPest: true,
      )));
      await tester.pump();
      expect(tester.getSize(find.byType(EmptyPot)), plain,
          reason: '叠浮标后整格尺寸不得变化（草地网格高度被矮屏测试钉死）');
      expect(tester.getRect(find.byType(Align).first), plainArt,
          reason: '图片框（artW×artH）尺寸与底边不得变化');
      // 底部等高空位仍在（空盆与有植物盆「同底」契约）。
      expect(find.byKey(const Key('empty_pot_footer')), findsOneWidget);
    });
  });

  // ── ⑤⑥ 真实花园页：浮标 → 清除入账 / 种下即消失 ──────────────────────────
  group('⑤⑥ 真实花园页接线', () {
    testWidgets('空盆长出杂草浮标 → 点击后消失，且阳光 +1 ☀（refType / refId 正确）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(
          _hostGardenPage(pots: pots, ledger: ledger, plants: plants));

      // 空盆先建出来（tick 是 _reload 内的异步动作）。
      final bool potsReady = await _pumpUntil(
        tester,
        () => find.byType(EmptyPot).evaluate().isNotEmpty,
      );
      expect(potsReady, isTrue, reason: '花园页必须渲染出空花盆');

      // 每个空盆都命中杂草（weedRandom 恒 0.0）→ 浮标出现。
      final bool chipsShown = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().isNotEmpty,
      );
      expect(chipsShown, isTrue, reason: '空盆 roll 命中 → 必须显示杂草浮标');
      expect(pots.store.isNotEmpty, isTrue, reason: '状态必须落进空盆仓储');
      final int before = _weedChip().evaluate().length;
      expect(ledger.entries, isEmpty, reason: 'roll 出浮标不入账（只有清除才给阳光）');

      // 点掉第一支浮标。
      await tester.tap(_weedChip().first);
      final bool earned = await _pumpUntil(
        tester,
        () => ledger.ofType(kGardenWeedRefType).isNotEmpty,
      );
      expect(earned, isTrue, reason: '拔草必须入账（奖励与植物一致）');

      final SunlightEntry entry = ledger.ofType(kGardenWeedRefType).single;
      expect(entry.gross, kGardenWeedReward,
          reason: '基础奖励与植物同源（kGardenWeedReward）');
      expect(entry.refType, kGardenWeedRefType);
      expect(entry.refId, EmptyPotService.refIdOf(0),
          reason: '空盆账本 refId = pot:<potIndex>');

      // 🔴 F156-A（玄参 2026-10-27）：入账是**立刻**的，但草地刷新必须等 4.1s 演出播完
      // —— 空盆现在也走 [CareEffectOverlay]（效果帧），不再「只播音效 + 立刻淡出」。
      // 入账发生在 `_run` 内部（早于 `_playCareEffect`），故这里用有界推进等叠加层上屏
      // （而不是直接断言：那样会偶发地卡在「已入账、动画还没开播」的中间帧）。
      expect(
        await _pumpUntil(
          tester,
          () => find.byType(CareEffectOverlay).evaluate().isNotEmpty,
        ),
        isTrue,
        reason: '空盆拔草必须挂出效果帧叠加层 [CareEffectOverlay]'
            '（空盆格没挂 _potKey / 恢复早退分支时这里恒为 0）',
      );
      await tester.pump(const Duration(milliseconds: kCareWeedDurationMs ~/ 2));
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '演出未到时长（4.1s）前不得提前收场');
      expect(_weedChip().evaluate().length, before,
          reason: '演出期间草地不得刷新（本盆浮标仍在）');

      // 浮标淡出后从数据层消失（该盆记录被清空，其余盆仍在）。
      final bool gone = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length < before,
        maxFrames: _clearSettleFrames,
      );
      expect(gone, isTrue, reason: '清除后该盆浮标必须消失');
      expect(find.byType(CareEffectOverlay), findsNothing,
          reason: '演出结束必须移除叠加层（不会留在树上）');
      expect(pots.store[0]?.hasWeed ?? false, isFalse,
          reason: '拨掉的盆当日不得再有杂草（rollDay 幂等锚保留）');
    });

    testWidgets('空盆有杂草 → 点空盆种下 → 该盆浮标消失且不返还（不入账）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(
          _hostGardenPage(pots: pots, ledger: ledger, plants: plants));

      expect(
        await _pumpUntil(tester, () => _weedChip().evaluate().isNotEmpty),
        isTrue,
        reason: '前置：空盆必须有杂草浮标',
      );
      expect(pots.store.containsKey(0), isTrue);

      // 「不阻挡种植」：点空盆底部（避开浮标）照常弹种植选择。
      // warnIfMissed: false —— 底部是纯占位 `SizedBox`（无子节点 → 自身不吃命中），
      // 点击由外层 InkWell 兜住，flutter_test 会误报「没命中该 SizedBox」。
      await tester.tap(
        find.byKey(const Key('empty_pot_footer')).first,
        warnIfMissed: false,
      );
      final bool sheetShown = await _pumpUntil(
        tester,
        () => find.text('选择要种的植物').evaluate().isNotEmpty,
      );
      expect(sheetShown, isTrue, reason: '空盆有杂草时也必须能种（不阻挡种植）');
      await tester.pump(const Duration(milliseconds: 400));

      // 向日葵首株免费 → 点「免费」→ 确认卡 → 确定种植。
      await tester.tap(find.text('免费').first);
      final bool confirmShown = await _pumpUntil(
        tester,
        () => find.text('确定种植').evaluate().isNotEmpty,
      );
      expect(confirmShown, isTrue, reason: '选种后必须弹二次确认卡');
      await tester.tap(find.text('确定种植'));

      final bool planted = await _pumpUntil(
        tester,
        () => plants.store.isNotEmpty,
      );
      expect(planted, isTrue, reason: '确认后必须真的种下');

      // 种下即清：该盆记录被删除（不返还、不再显示）。
      final bool cleared = await _pumpUntil(
        tester,
        () => !pots.store.containsKey(0),
      );
      expect(cleared, isTrue, reason: '种下后该盆空盆干扰物必须立即清掉');
      expect(ledger.ofType(kGardenWeedRefType), isEmpty,
          reason: '种下即清不返还任何阳光（不入账）');
      expect(ledger.ofType(kGardenPestRefType), isEmpty);
      // 该格变成有植物盆 → 不再有「浮标属于盆 0」的记录。
      expect(find.byType(EmptyPot).evaluate().length, lessThan(4),
          reason: '种下一株后空盆数减少');
    });

    testWidgets('清除演出期间第二次点击被挡，且演出结束后本页仍能刷新（不泄漏刷新票据）',
        (WidgetTester tester) async {
      // 🔴 QA 缺陷回归守卫（F155-B 引入，F156-A 语义更新，**不得删除**）：
      //  · 单例 `_clearSeqTimer` 时代：第二次清除会 cancel 掉第一次的定时器 →
      //    第一张票据永久留在 `_suppressTickets` → 本页此后**所有**刷新一律 early-return
      //    （草地不刷新、空盆 tick 不跑，已清掉的浮标淡出后**复活**并常驻）；
      //  · F156-A 起空盆也播完整 4.1s 演出、`_busy` 全程锁住 → **演出期间**的第二次
      //    点击必然被挡。本用例因此改成守护**两条仍然成立的不变量**：
      //     ① 演出期间第二次点击必须被挡住（不产生第二张票据、不写第二条账本）；
      //     ② 一次清除收尾之后票据必须被**释放** → 本页仍能正常刷新（清第二盆真的消失）。
      //    若把 `_busy` 闸门或票据释放改坏，②会以「第二盆浮标永不消失」变红。
      //
      // ⚠️ 覆盖不到的地方：`_onClearAnimated` 先把 `_busy` 置 false、再等 300ms 淡出，
      // **那个淡出窗口内仍可构造「两张票据同时在飞」**（本用例点的是演出期，走 `_busy`
      // 分支，到不了多票据路径）→ 那段由下一条用例「淡出窗口内重叠清除」专门覆盖。
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(
          _hostGardenPage(pots: pots, ledger: ledger, plants: plants));

      expect(
        await _pumpUntil(tester, () => _weedChip().evaluate().length == 4),
        isTrue,
        reason: '前置：4 个空盆全部长草',
      );

      await tester.tap(_weedChip().first); // 盆 0：开始 4.1s 演出
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '前置：第一次清除必须已在播演出');

      // ① 演出期间再点第二盆 → 必须被 [_busy] 挡住（不写第二条账本、不清第二盆）。
      await tester.tap(_weedChip().at(1)); // 盆 1
      await tester.pump(const Duration(milliseconds: 80));
      expect(ledger.ofType(kGardenWeedRefType).length, 1,
          reason: '演出期间第二次点击必须被挡：账本只应有 1 条');
      expect(pots.store[1]?.hasWeed ?? false, isTrue,
          reason: '被挡住的第二次点击不得清掉盆 1 的杂草（否则票据/账本双写）');
      expect(_weedChip().evaluate().length, 4,
          reason: '演出期间草地尚未刷新（浮标仍在）');

      // 演出 + 淡出 + 刷新走完 → 只剩 3 支浮标，账本恰好 1 条。
      final bool firstCleared = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 3,
        maxFrames: _clearSettleFrames,
      );
      expect(firstCleared, isTrue,
          reason: '演出结束后盆 0 的浮标必须消失（票据泄漏时永不消失）');
      expect(ledger.ofType(kGardenWeedRefType).length, 1,
          reason: '只有第一次清除入账（第二次被挡）');
      expect(pots.store[0]?.hasWeed ?? false, isFalse);

      // 稳定性：再等一会，确认已被清掉的浮标不会「复活」。
      await tester.pump(const Duration(milliseconds: 400));
      expect(_weedChip().evaluate().length, 3,
          reason: '刷新未被永久挡住时，清掉的浮标不得复活');

      // ② 「页面仍在刷新」的可观测证据（不能只断言浮标数量）：
      // 票据若泄漏，[_suppressReload] 恒 true → **之后再怎么清都不会刷新**，
      // 第二盆的浮标会永远留在草地上。故这里再清一盆，它必须真的消失并入账。
      await tester.tap(_weedChip().first); // 现在是盆 1
      await tester.pump(const Duration(milliseconds: 80));
      final bool secondGone = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 2,
        maxFrames: _clearSettleFrames,
      );
      expect(secondGone, isTrue,
          reason: '第一次清除收尾之后页面仍必须能刷新（票据泄漏时第二盆浮标永不消失）');
      expect(ledger.ofType(kGardenWeedRefType).length, 2,
          reason: '第二次清除照常入账 → 经济链路未被挡住');
      expect(pots.store[1]?.hasWeed ?? false, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_weedChip().evaluate().length, 2,
          reason: '第二次清除后也不得复活');
    });

    testWidgets('淡出窗口内重叠清除：两张票据同时在飞也各自收尾（票据不释放必红）',
        (WidgetTester tester) async {
      // 🔴 **守的是「每张票据最终都被释放」**（[_suppressTickets] 不能泄漏）。
      //
      // 构造路径必须是「**淡出 300ms 窗口**内的重叠」，不是演出期：
      //  · 演出期（4.1s）由 `_busy` 锁住 → 第二次点击被 `_run` 挡掉（见上一条用例）；
      //  · 但 `_onClearAnimated` 是**先 `_busy = false`、再等 kPestFadeOutMs 淡出**，
      //    这 300ms 内上一张票据**还活着**、页面**已可操作** → 点另一盆即构成重叠
      //    （两张票据同时在飞，这是 F156-A 之前就存在的真实现象）。
      //
      // 🔴 变异自证（本地已做）：把 `_onClearAnimated` 里的 `_suppressTickets.remove(ticket)`
      // 注释掉（票据永不释放）→ 第一张票据永久留在 `_suppressTickets` → 本页此后永不刷新
      // → **本用例红在最核心那条**「两张票据必须各自收尾：两盆浮标都消失」（停在 4 支），
      // 另带 3 条旧用例一同变红。
      //
      // ⚠️ 覆盖不到的地方：把 `_clearTimers` 回退成「新票据进来 cancel 全部」**不会**让本
      // 用例变红 —— 被取消的那条 300ms 定时器总是先触发完毕，第二张票据的 `_onClearAnimated`
      // 至少晚 4.1s 才到，故该实现细节**当前不可观测**（详见 garden_page `_clearTimers`）。
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(
          _hostGardenPage(pots: pots, ledger: ledger, plants: plants));

      expect(
        await _pumpUntil(tester, () => _weedChip().evaluate().length == 4),
        isTrue,
        reason: '前置：4 个空盆全部长草',
      );

      await tester.tap(_weedChip().first); // 盆 0
      await tester.pump(); // 挂载叠加层（动画从第 0 帧开始）
      await tester.pump(
          const Duration(milliseconds: kCareWeedDurationMs + 100));
      expect(find.byType(CareEffectOverlay), findsNothing,
          reason: '前置：盆 0 的 4.1s 演出必须已播完（票据进入淡出窗口）');
      expect(_weedChip().evaluate().length, 4,
          reason: '前置：淡出窗口内草地尚未刷新（盆 0 的浮标还在淡出中）');

      // 🔴 淡出窗口内点第二盆 → 第二张票据进场，**此时盆 0 的票据尚未释放**。
      await tester.tap(_weedChip().at(1)); // 盆 1
      await tester.pump(const Duration(milliseconds: 16));
      expect(ledger.ofType(kGardenWeedRefType).length, 2,
          reason: '淡出窗口内第二次清除必须照常执行（两张票据同时在飞）');
      expect(pots.store[0]?.hasWeed ?? true, isFalse);
      expect(pots.store[1]?.hasWeed ?? true, isFalse);
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '盆 1 的演出已开始（盆 0 的已结束）→ 两张票据真的同时在飞');

      // 🔴 核心断言：两张票据各自释放 → 两盆浮标**都**真的消失（4 → 2）。
      // 票据泄漏（如 `_suppressTickets.remove(ticket)` 被删）时刷新永久被挡住 → 停在 4 支。
      final bool bothGone = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 2,
        maxFrames: _clearSettleFrames,
      );
      expect(bothGone, isTrue,
          reason: '两张票据必须各自收尾：两盆浮标都消失'
              '（票据不释放 → 本页永久不刷新 → 会停在 4 支）');
      expect(pots.store[0]?.hasWeed ?? true, isFalse);
      expect(pots.store[1]?.hasWeed ?? true, isFalse);
      expect(ledger.ofType(kGardenWeedRefType).length, 2,
          reason: '两盆各入账 1 条，不重复入账');
      // 稳定性：不得复活。
      await tester.pump(const Duration(milliseconds: 400));
      expect(_weedChip().evaluate().length, 2,
          reason: '两张票据都释放后，已清掉的浮标不得复活');
    });

    testWidgets('F156-A 空盆清除必须完整播放 4.1s 演出（去掉空盆 key / 恢复早退分支即变红）',
        (WidgetTester tester) async {
      // 🔴 F156-A 主守卫（玄参 2026-10-27 原话：「空盆首日免疫可以，清理的时候为什么不
      // 播放动画呢？……我觉得是需要完整的播放动画的」）。
      //
      // 变异验证（本地已做，见交付说明）：
      //  · 去掉 `_buildCells()` 里 `EmptyPot(key: _potKey(i))` → `_playCareEffect` 取不到
      //    落点 context（早退分支①：无动画无音效）→ **本用例第一条断言即变红**；
      //  · 恢复 F155-B 的 `pid == null` 早退分支（只 playSfx + 立刻淡出）→ 同样变红。
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(
          _hostGardenPage(pots: pots, ledger: ledger, plants: plants));

      expect(
        await _pumpUntil(tester, () => _weedChip().evaluate().length == 4),
        isTrue,
        reason: '前置：4 个空盆全部长草',
      );

      await tester.tap(_weedChip().first); // 盆 0
      await tester.pump(const Duration(milliseconds: 16));

      // ① 演出**开始**：叠加层在树上（没有 key 时 `_playCareEffect` 走早退分支 → 0）。
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '空盆拔草必须挂出 [CareEffectOverlay]（效果帧），不能只播音效');

      // ② 4.1s 时长**内**：演出仍在、草地**未**刷新（本盆浮标仍在 = 干扰物未提前消失）。
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '3.0s 处演出必须仍在（总时长 4101ms）');
      expect(_weedChip().evaluate().length, 4,
          reason: '演出期间草地不得刷新');

      await tester.pump(const Duration(milliseconds: 1000)); // 累计 ≈4.02s < 4.101s
      expect(find.byType(CareEffectOverlay), findsOneWidget,
          reason: '4.02s（仍短于 kCareWeedDurationMs=4101ms）时演出不得提前结束');
      expect(_weedChip().evaluate().length, 4,
          reason: '4.1s 内浮标必须还在（旧「立刻淡出」实现会在这里掉到 3）');
      expect(ledger.ofType(kGardenWeedRefType).length, 1,
          reason: '账本在点击时即写入，且只写 1 行');

      // ③ 演出 + 淡出 + 刷新落地：浮标消失、叠加层移除、飘字出现、账本恰好 1 行。
      final bool settled = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 3,
        maxFrames: _clearSettleFrames,
      );
      expect(settled, isTrue, reason: '演出结束后该盆浮标必须消失');
      expect(find.byType(CareEffectOverlay), findsNothing,
          reason: '演出结束必须移除叠加层');
      expect(find.text('除草成功'), findsOneWidget,
          reason: '收尾必须弹「除草成功，阳光+N」飘字（与有植物盆同一条收尾时序）');
      expect(ledger.ofType(kGardenWeedRefType).length, 1,
          reason: '恰好 1 条杂草账本（不重复入账）');
      expect(pots.store[0]?.hasWeed ?? false, isFalse,
          reason: '拨掉的盆当日不得再有杂草');
    });

    testWidgets('称号属性生效：空盆拔草也必须传门控 perk（除草 +1 → 实得 2 ☀）',
        (WidgetTester tester) async {
      // 🔴 QA 建议的质量守卫：把 `_clearPest` 空盆分支的 `perk: _perk` 删掉后，
      // 若不钉这条断言，全部用例仍会绿（只拿到基础 1 ☀）→ 称号「除草 +1」
      // 对空花盆会静默失效且无人发现。奖励数字由 `weedRewardOf(perk)` 单点派生，
      // 本断言只钉「页面确实把 perk 传下去了」。
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final _MemPotDisturbanceRepo pots = _MemPotDisturbanceRepo();
      final _MemLedger ledger = _MemLedger();
      final _MemPlantRepo plants = _MemPlantRepo();
      await tester.pumpWidget(_hostGardenPage(
        pots: pots,
        ledger: ledger,
        plants: plants,
        perk: const PlantPerk(weedBonus: 1),
      ));

      expect(
        await _pumpUntil(tester, () => _weedChip().evaluate().isNotEmpty),
        isTrue,
        reason: '前置：空盆必须长出杂草浮标',
      );

      await tester.tap(_weedChip().first);
      final bool earned = await _pumpUntil(
        tester,
        () => ledger.ofType(kGardenWeedRefType).isNotEmpty,
      );
      expect(earned, isTrue, reason: '拔草必须入账');

      final SunlightEntry entry = ledger.ofType(kGardenWeedRefType).single;
      expect(entry.net, kGardenWeedReward + 1,
          reason: '称号 weedBonus=1 → 实得 2 ☀（页面没传 perk 时这里会是 1.0）');
      expect(entry.net, 2.0, reason: '基础 1 ☀ + 称号加成 1 ☀');
    });
  });
}
