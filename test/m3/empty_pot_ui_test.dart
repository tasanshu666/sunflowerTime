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
///  ⑥ 真实花园页：浮标 → 点空盆种下 → 该盆浮标消失、且**不入账**（不返还）。
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

      // 浮标淡出后从数据层消失（该盆记录被清空，其余盆仍在）。
      final bool gone = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length < before,
      );
      expect(gone, isTrue, reason: '清除后该盆浮标必须消失');
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

    testWidgets('重叠清除（300ms 淡出窗口内连清两盆）不泄漏刷新票据：两盆都真的消失',
        (WidgetTester tester) async {
      // 🔴 QA 缺陷回归守卫（F155-B 引入）：单例 `_clearSeqTimer` 时，第二次清除会
      // cancel 掉第一次的定时器 → 第一张票据永久留在 `_suppressTickets` →
      // 本页此后**所有**刷新一律 early-return：草地不刷新、空盆 tick 不跑，
      // 已清掉的浮标淡出后**复活**并常驻。本用例在 300ms 窗口内连点两盆来触发它。
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
      await tester.pump(const Duration(milliseconds: 80)); // < kPestFadeOutMs
      await tester.tap(_weedChip().at(1)); // 盆 1（盆 0 的浮标仍在淡出中）
      await tester.pump(const Duration(milliseconds: 80));
      expect(_weedChip().evaluate().length, 4,
          reason: '两次清除都在淡出窗口内：数据已清但草地尚未刷新（浮标仍在树上）');

      // 等两条定时器都收尾（300ms / 380ms）+ 刷新落地。
      final bool cleared = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 2,
      );
      expect(cleared, isTrue,
          reason: '两盆都清掉后必须只剩 2 支浮标（票据泄漏时会停在 4 支）');

      // 稳定性：再等一会，确认已被清掉的浮标不会「复活」。
      await tester.pump(const Duration(milliseconds: 400));
      expect(_weedChip().evaluate().length, 2,
          reason: '刷新未被永久挡住时，清掉的浮标不得复活');
      expect(ledger.ofType(kGardenWeedRefType).length, 2,
          reason: '两盆各入账一次（+1 ☀ × 2）');
      expect(pots.store[0]?.hasWeed ?? false, isFalse);
      expect(pots.store[1]?.hasWeed ?? false, isFalse);

      // 🔴 「页面仍在刷新」的可观测证据（不能只断言浮标数量）：票据若泄漏，
      // [_suppressReload] 恒 true → **之后再怎么清都不会刷新**，第三盆的浮标
      // 会永远留在草地上。故重叠清除之后再清一盆，它必须真的消失。
      final int balanceBefore = ledger.entries.length;
      await tester.tap(_weedChip().first); // 现在是盆 2
      final bool thirdGone = await _pumpUntil(
        tester,
        () => _weedChip().evaluate().length == 1,
      );
      expect(thirdGone, isTrue,
          reason: '重叠清除之后页面仍必须能刷新（票据泄漏时第三盆浮标永不消失）');
      expect(ledger.entries.length, balanceBefore + 1,
          reason: '第三次清除仍照常入账 → 经济链路未被挡住');
      expect(pots.store[2]?.hasWeed ?? false, isFalse);
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
