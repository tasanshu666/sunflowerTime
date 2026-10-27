/// 空花盆干扰物（杂草 / 害虫）玩法回归测试 —— F155-B（玄参 2026-10-27 拍板）。
///
/// 拍板口径（逐条钉死，判据都是**可观测产物**）：
///  ① **每日 roll + 同日幂等**：同一天重复 tick 不重 roll（否则「每天一次」退化成
///     「每次刷新都掷骰」）；以 `rollDay`（当天零点）为幂等锚；
///  ② **概率 = 植物的一半**：草 [kEmptyPotWeedRate] 0.20 / 虫 [kEmptyPotPestRate] 0.15
///     （植物 0.40 / 0.30），两者独立、**可同时出现**；
///  ③ **当天有效、次日失效**：非当天零点 → 记录里的 weed/pest 必须被清掉；
///  ④ **首日免疫**：某个盆第一次被观测到时只写幂等锚、不掷骰（与植物侧
///     `plant()` 的「新种下单日免疫」同口径），次日才参与 roll；
///  ⑤ **清除即入账**：拔草 +[kGardenWeedReward]、除虫 +[kGardenPestReward]（含称号加成），
///     账本 `refType` 复用植物的 `plant_weed` / `plant_pest`，`refId = 'pot:<potIndex>'`；
///     清除后**保留** rollDay（否则同日又长出来）；
///  ⑥ **分因**：无草拔草 / 无记录 均抛 [PlantOperationException]（与植物侧同风格）；
///  ⑦ **种下即清**：`clearForPlanting` 删该盆记录（不返还）；tick 对「已不是空盆」的
///     脏行做防御性清理。
///
/// 纯 Dart：仓储以内存 Fake 实现，随机源喂**固定序列**（`_SeqRandom`）保证确定性。
library empty_pot_disturbance_test;

import 'dart:math';

import 'package:test/test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/pot_disturbance_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart'
    show PlantOperationError, PlantOperationException;
import 'package:sunflower_time/domain/services/plant_perk.dart';

// ── 测试替身 ────────────────────────────────────────────────────────────────

/// 内存版空盆干扰物仓储（按 potIndex 单键，与实现同语义）。
class _MemPotRepo implements PotDisturbanceRepository {
  final Map<int, PotDisturbance> store = <int, PotDisturbance>{};

  @override
  Future<List<PotDisturbance>> disturbances() async =>
      List<PotDisturbance>.of(store.values);

  @override
  Future<PotDisturbance?> disturbanceOf(int potIndex) async => store[potIndex];

  @override
  Future<void> save(PotDisturbance disturbance) async =>
      store[disturbance.potIndex] = disturbance;

  @override
  Future<void> deletePot(int potIndex) async => store.remove(potIndex);

  @override
  Future<void> deleteAll() async => store.clear();
}

/// 内存账本：记录全部 append 行，余额按 net 累加。
class _MemLedger implements SunlightRepository {
  static const double initialBalance = 100.0;
  final List<SunlightEntry> entries = <SunlightEntry>[];

  List<SunlightEntry> entriesOf(String refType) =>
      entries.where((SunlightEntry e) => e.refType == refType).toList();

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    return balance();
  }

  @override
  Future<double> balance() async => initialBalance +
      entries.fold<double>(0.0, (double a, SunlightEntry e) => a + e.net);

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async {
    final List<SunlightEntry> list = entriesOf(refType).toList()
      ..sort((SunlightEntry a, SunlightEntry b) => b.ts.compareTo(a.ts));
    return list.isEmpty ? null : list.first;
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
  Future<int> countByRefType(String refType) async => 0;

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
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    final List<SunlightEntry> hits = entries
        .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
        .toList()
      ..sort((SunlightEntry a, SunlightEntry b) => a.ts.compareTo(b.ts));
    return hits.isEmpty ? null : hits.last.ts;
  }
}

/// 固定序列随机源（循环取值），并记录被调用次数（验证「幂等日不掷骰」）。
class _SeqRandom implements Random {
  _SeqRandom(this._values);
  final List<double> _values;
  int calls = 0;

  @override
  double nextDouble() {
    final double v = _values[calls % _values.length];
    calls++;
    return v;
  }

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

// ── 夹具 ────────────────────────────────────────────────────────────────────

final DateTime _today = DateTime(2026, 10, 27);
final DateTime _todayStart = DateTime(2026, 10, 27);
final DateTime _yesterdayStart = DateTime(2026, 10, 26);

class _Ctx {
  _Ctx(this.svc, this.pots, this.ledger);
  final EmptyPotService svc;
  final _MemPotRepo pots;
  final _MemLedger ledger;
}

_Ctx _make({
  _SeqRandom? weedRandom,
  _SeqRandom? pestRandom,
  bool firstSightImmune = true,
}) {
  final _MemPotRepo pots = _MemPotRepo();
  final _MemLedger ledger = _MemLedger();
  final EmptyPotService svc = EmptyPotService(
    disturbances: pots,
    ledger: ledger,
    weedRandom: weedRandom ?? _SeqRandom(<double>[0.99]),
    pestRandom: pestRandom ?? _SeqRandom(<double>[0.99]),
    firstSightImmune: firstSightImmune,
  );
  return _Ctx(svc, pots, ledger);
}

void main() {
  group('⓪ 常量口径（空盆频率 = 植物一半；奖励同植物）', () {
    test('杂草 0.20 = 植物 0.40 的一半；害虫 0.15 = 植物 0.30 的一半', () {
      expect(kEmptyPotWeedRate, 0.20);
      expect(kEmptyPotPestRate, 0.15);
      expect(kEmptyPotWeedRate, kGardenWeedRate / 2);
      expect(kEmptyPotPestRate, kGardenPestRate / 2);
    });

    test('奖励常量复用植物的 1 ☀ / 2 ☀（不另立一套）', () {
      expect(kGardenWeedReward, 1);
      expect(kGardenPestReward, 2);
      expect(weedRewardOf(PlantPerk.none), 1);
      expect(pestRewardOf(PlantPerk.none), 2);
    });
  });

  group('① 首日免疫 + 同日幂等', () {
    test('首次观测：只写幂等锚，不掷骰（杂草 / 害虫都不出现）', () async {
      final _SeqRandom weed = _SeqRandom(<double>[0.0]); // 若掷骰必命中
      final _SeqRandom pest = _SeqRandom(<double>[0.0]);
      final _Ctx ctx = _make(weedRandom: weed, pestRandom: pest);

      final List<PotDisturbance> states =
          await ctx.svc.tick(<int>[0, 1], _today);

      expect(states, hasLength(2));
      for (final PotDisturbance d in states) {
        expect(d.hasWeed, isFalse, reason: '首日免疫：不得当天长草');
        expect(d.hasPest, isFalse, reason: '首日免疫：不得当天长虫');
        expect(d.rollDay, _todayStart, reason: '必须落下「今日已 roll」幂等锚');
      }
      expect(weed.calls, 0, reason: '首日免疫分支不得掷骰');
      expect(pest.calls, 0);
      expect(ctx.pots.store.keys.toSet(), <int>{0, 1},
          reason: '每个空盆各落一行（复合主键 childId + potIndex）');
    });

    test('同日二次 tick：结果与首次逐字段一致，且不再掷骰', () async {
      final _SeqRandom weed = _SeqRandom(<double>[0.0]);
      final _SeqRandom pest = _SeqRandom(<double>[0.0]);
      final _Ctx ctx = _make(weedRandom: weed, pestRandom: pest);

      await ctx.svc.tick(<int>[0], _today);
      final List<PotDisturbance> second =
          await ctx.svc.tick(<int>[0], _today.add(const Duration(hours: 9)));

      expect(second.single.rollDay, _todayStart);
      expect(second.single.hasWeed, isFalse);
      expect(second.single.hasPest, isFalse);
      expect(weed.calls, 0, reason: '同日幂等：第二次 tick 不得重 roll');
      expect(pest.calls, 0);
    });

    test('firstSightImmune=false：首次观测当场掷骰（可关的开关，口径留档）', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.0]),
        pestRandom: _SeqRandom(<double>[0.99]),
        firstSightImmune: false,
      );
      final List<PotDisturbance> states =
          await ctx.svc.tick(<int>[0], _today);
      expect(states.single.hasWeed, isTrue);
      expect(states.single.hasPest, isFalse);
      expect(states.single.weedAt, _todayStart);
    });
  });

  group('②③ 概率边界 + 次日失效', () {
    test('杂草命中（0.19 < 0.20）/ 害虫未命中（0.99 ≥ 0.15）→ 只有草', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.19]),
        pestRandom: _SeqRandom(<double>[0.99]),
      );
      // 预置「昨天已 roll」的行 → 今天必须重新掷骰。
      await ctx.pots.save(PotDisturbance(
        potIndex: 0,
        rollDay: _yesterdayStart,
        weedAt: _yesterdayStart, // 昨天的草，今天必须失效
      ));

      final PotDisturbance d = (await ctx.svc.tick(<int>[0], _today)).single;

      expect(d.hasWeed, isTrue);
      expect(d.weedAt, _todayStart, reason: '存「出现当天零点」，非时刻');
      expect(d.hasPest, isFalse);
      expect(d.rollDay, _todayStart);
    });

    test('害虫命中（0.14 < 0.15）/ 杂草未命中（0.20 ≥ 0.20，边界不得命中）', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.20]),
        pestRandom: _SeqRandom(<double>[0.14]),
      );
      await ctx.pots.save(PotDisturbance(
        potIndex: 2,
        rollDay: _yesterdayStart,
      ));

      final PotDisturbance d = (await ctx.svc.tick(<int>[2], _today)).single;

      expect(d.hasPest, isTrue);
      expect(d.pestAt, _todayStart);
      expect(d.hasWeed, isFalse, reason: 'nextDouble()==rate 时不算命中（严格小于）');
    });

    test('都命中 → 同一天可草虫并存', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.0]),
        pestRandom: _SeqRandom(<double>[0.0]),
      );
      await ctx.pots.save(
          PotDisturbance(potIndex: 1, rollDay: _yesterdayStart));
      final PotDisturbance d = (await ctx.svc.tick(<int>[1], _today)).single;
      expect(d.hasWeed, isTrue);
      expect(d.hasPest, isTrue);
    });

    test('非当天自动失效：昨天有草有虫 → 今天未命中则清空', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.99]),
        pestRandom: _SeqRandom(<double>[0.99]),
      );
      await ctx.pots.save(PotDisturbance(
        potIndex: 3,
        rollDay: _yesterdayStart,
        weedAt: _yesterdayStart,
        pestAt: _yesterdayStart,
      ));

      final PotDisturbance d = (await ctx.svc.tick(<int>[3], _today)).single;

      expect(d.hasWeed, isFalse, reason: '跨天必须自动过期（不会永久卡着）');
      expect(d.hasPest, isFalse);
      expect(d.rollDay, _todayStart);
    });

    test('每盆独立 roll：一盆中草、另一盆不中', () async {
      final _Ctx ctx = _make(
        weedRandom: _SeqRandom(<double>[0.10, 0.90]), // 盆 0 命中 → 盆 1 未命中
        pestRandom: _SeqRandom(<double>[0.99]),
      );
      await ctx.pots.save(
          PotDisturbance(potIndex: 0, rollDay: _yesterdayStart));
      await ctx.pots.save(
          PotDisturbance(potIndex: 1, rollDay: _yesterdayStart));

      final List<PotDisturbance> states =
          await ctx.svc.tick(<int>[0, 1], _today);

      expect(states[0].hasWeed, isTrue);
      expect(states[1].hasWeed, isFalse);
    });
  });

  group('⑤ 清除即入账（奖励与植物一致）', () {
    test('拔草 +1 ☀：账本 refType=plant_weed、refId=pot:<i>、字段清空、rollDay 保留', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(PotDisturbance(
        potIndex: 3,
        rollDay: _todayStart,
        weedAt: _todayStart,
      ));

      await ctx.svc.clearWeed(3, _today);

      final List<SunlightEntry> rows = ctx.ledger.entriesOf(kGardenWeedRefType);
      expect(rows, hasLength(1));
      expect(rows.single.net, 1.0);
      expect(rows.single.gross, 1.0);
      expect(rows.single.refId, 'pot:3');
      expect(rows.single.type.index, 0, reason: '入账行（SunlightType.earn）');

      final PotDisturbance after = ctx.pots.store[3]!;
      expect(after.hasWeed, isFalse, reason: '清除后字段必须清空');
      expect(after.rollDay, _todayStart,
          reason: '必须保留幂等锚，否则同日再 tick 又长出来');
    });

    test('除虫 +2 ☀：账本 refType=plant_pest、refId=pot:<i>', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(PotDisturbance(
        potIndex: 5,
        rollDay: _todayStart,
        pestAt: _todayStart,
      ));

      await ctx.svc.clearPest(5, _today);

      final List<SunlightEntry> rows = ctx.ledger.entriesOf(kGardenPestRefType);
      expect(rows, hasLength(1));
      expect(rows.single.net, 2.0);
      expect(rows.single.refId, 'pot:5');
      expect(ctx.pots.store[5]!.hasPest, isFalse);
    });

    test('称号加成生效：除草 +1 / 除虫 +2（与植物侧同一批取值函数）', () async {
      final _Ctx ctx = _make();
      const PlantPerk perk = PlantPerk(weedBonus: 1, pestBonus: 2);
      await ctx.pots.save(PotDisturbance(
        potIndex: 0,
        rollDay: _todayStart,
        weedAt: _todayStart,
        pestAt: _todayStart,
      ));

      await ctx.svc.clearWeed(0, _today, perk: perk);
      await ctx.svc.clearPest(0, _today, perk: perk);

      expect(ctx.ledger.entriesOf(kGardenWeedRefType).single.net,
          weedRewardOf(perk));
      expect(ctx.ledger.entriesOf(kGardenWeedRefType).single.net, 2.0);
      expect(ctx.ledger.entriesOf(kGardenPestRefType).single.net,
          pestRewardOf(perk));
      expect(ctx.ledger.entriesOf(kGardenPestRefType).single.net, 4.0);
    });

    test('清完再 tick（同日）：不会又长出来（幂等锚保留 + 不重掷骰）', () async {
      final _SeqRandom weed = _SeqRandom(<double>[0.0]); // 若重掷必命中
      final _Ctx ctx = _make(weedRandom: weed, pestRandom: _SeqRandom(<double>[0.99]));
      await ctx.pots.save(PotDisturbance(
        potIndex: 0,
        rollDay: _todayStart,
        weedAt: _todayStart,
      ));

      await ctx.svc.clearWeed(0, _today);
      final PotDisturbance after = (await ctx.svc.tick(<int>[0], _today)).single;

      expect(after.hasWeed, isFalse);
      expect(weed.calls, 0);
    });
  });

  group('⑥ 分因（与植物侧同风格）', () {
    test('无草拔草 → noWeed；无虫除虫 → noPest；无记录 → plantNotFound', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(
          PotDisturbance(potIndex: 0, rollDay: _todayStart));

      await expectLater(
        ctx.svc.clearWeed(0, _today),
        throwsA(isA<PlantOperationException>().having(
            (PlantOperationException e) => e.code, 'code', PlantOperationError.noWeed)),
      );
      await expectLater(
        ctx.svc.clearPest(0, _today),
        throwsA(isA<PlantOperationException>().having(
            (PlantOperationException e) => e.code, 'code', PlantOperationError.noPest)),
      );
      await expectLater(
        ctx.svc.clearWeed(9, _today),
        throwsA(isA<PlantOperationException>().having((PlantOperationException e) =>
            e.code, 'code', PlantOperationError.plantNotFound)),
      );
      expect(ctx.ledger.entries, isEmpty, reason: '失败路径绝不许写账本');
    });
  });

  group('⑦ 种下即清 / 脏行防御性清理', () {
    test('clearForPlanting：删该盆记录，且不写任何账本（不返还）', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(PotDisturbance(
        potIndex: 4,
        rollDay: _todayStart,
        weedAt: _todayStart,
        pestAt: _todayStart,
      ));

      await ctx.svc.clearForPlanting(4);

      expect(ctx.pots.store.containsKey(4), isFalse);
      expect(ctx.ledger.entries, isEmpty, reason: '种下即清 = 不返还任何奖励');
      // 幂等：再调一次不报错。
      await ctx.svc.clearForPlanting(4);
    });

    test('tick 只保留「本轮真正的空盆」：已种下的盆记录被清掉', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(
          PotDisturbance(potIndex: 0, rollDay: _todayStart));
      await ctx.pots.save(
          PotDisturbance(potIndex: 7, rollDay: _todayStart));

      // 本轮只有盆 0 是空盆（盆 7 已种下）。
      final List<PotDisturbance> states =
          await ctx.svc.tick(<int>[0], _today);

      expect(states.map((PotDisturbance d) => d.potIndex), <int>[0]);
      expect(ctx.pots.store.containsKey(7), isFalse,
          reason: '非空盆的脏行必须清掉（防止种下后浮标残留）');
      expect(ctx.pots.store.containsKey(0), isTrue);
    });

    test('空盆列表为空：不报错、清空全部记录', () async {
      final _Ctx ctx = _make();
      await ctx.pots.save(
          PotDisturbance(potIndex: 0, rollDay: _todayStart));

      final List<PotDisturbance> states =
          await ctx.svc.tick(const <int>[], _today);

      expect(states, isEmpty);
      expect(ctx.pots.store, isEmpty);
    });
  });

  group('⑧ 实体语义（与 Plant 的哨兵三态同款）', () {
    test('copyWith：不传 → 保持；kClear → 清空；传值 → 赋值', () {
      final PotDisturbance d = PotDisturbance(
        potIndex: 1,
        weedAt: _todayStart,
        pestAt: _todayStart,
        rollDay: _todayStart,
      );
      expect(d.copyWith().weedAt, _todayStart);
      expect(d.copyWith(weedAt: PotDisturbance.kClear).weedAt, isNull);
      expect(d.copyWith(weedAt: PotDisturbance.kClear).pestAt, _todayStart,
          reason: '只清指定字段，不影响其它字段');
      expect(d.copyWith(rollDay: PotDisturbance.kClear).rollDay, isNull);
      expect(d.copyWith(pestAt: _yesterdayStart).pestAt, _yesterdayStart);
      expect(d.hasWeed, isTrue);
      expect(d.hasPest, isTrue);
      expect(d.hasPestOrWeed, isTrue);
      expect(d.copyWith(weedAt: PotDisturbance.kClear).hasWeed, isFalse);
    });
  });
}
