/// 花园守卫 · 今日券服务（`GuardVoucherService`）单测。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §3.7（掉落 6 档）/ §3.8（收口表）。
///
/// ## 本文件钉死的 5 条红线
///  · **A10 免费券绝不整批**：批量（`plantId == null`）拿到的 perk **不含**免费减免
///    ⇒ 一键 5 盆扣 20 ☀（1 盆免 + 4 盆付），绝不是 0 ☀；
///  · **A11（B13.4 改版）浇水券当日不限次**：12 盆 × 3 次 = 36 次浇水，总节省
///    = **36**（玄参 2026-11-11 拍板废除 6 ☀ 封顶；劳动券同理、4 ☀ 封顶废除）；
///  · 券的减免只经本服务产出 `PlantPerk`（价格一律走 `waterCostOf` / `fertilizeCostOf`）；
///  · 与称号减免**相加**（5 − 1 − 1 = 3；免费券直接归零 5 − 1 − 5 → 钳到 0）；
///  · 额度记账走 `GuardDayState.buff`（不新建存储），用完即不再减免。
///
/// 🔴 期望值全部写死常量（5 / 10 / 6 / 4 / 2 / 3），**不从实现里引用同一常量反推** ——
/// 否则实现改错时测试会跟着一起错。
library guard_voucher_test;

import 'package:test/test.dart';

import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/repositories/guard_state_store.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';

/// 内存版守卫状态存储（只实现 3 个方法，行为与 prefs 实现同口径）。
class _FakeStore implements GuardStateStore {
  final Map<String, GuardDayState> byChild = <String, GuardDayState>{};

  /// 「从来没有写过」时 `read` 兜底的 dayKey。
  String fallbackDayKey = '2026-11-09';

  /// 写次数（用于「不写库」类断言）。
  int writeCount = 0;

  @override
  Future<GuardDayState> read(String childId) async =>
      byChild[childId] ?? GuardDayState.empty(fallbackDayKey);

  @override
  Future<void> write(String childId, GuardDayState state) async {
    byChild[childId] = state;
    writeCount++;
  }

  @override
  Future<void> clear(String childId) async {
    byChild.remove(childId);
  }
}

const String _childId = 'c1';
const String _today = '2026-11-09';

DateTime _clock() => DateTime(2026, 11, 9, 10, 30);

/// 造一个「今天已领取、buff 已发放」的存档。
_FakeStore _storeWithBuff(GuardDropKind kind) {
  final _FakeStore store = _FakeStore();
  store.byChild[_childId] = GuardDayState(
    dayKey: _today,
    status: GuardDayStatus.claimed,
    thiefKind: GuardThiefKind.sunRat,
    winSun: 2,
    dropKind: kind,
    buff: guardBuffFor(kind),
  );
  return store;
}

GuardVoucherService _service(_FakeStore store) => GuardVoucherService(
      store: store,
      childId: () => _childId,
      clock: _clock,
    );

void main() {
  group('券 → PlantPerk 映射（价格一律走 perk-aware 取值函数）', () {
    test('浇水券：每盆 −1（5 → 4）', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.waterVoucher));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.water,
        plantId: null,
      );
      expect(perk.waterDiscount, 1);
      expect(waterCostOf(perk), 4);
    });

    test('施肥券：今日每次 −2 ☀（10 → 8）', () async {
      final GuardVoucherService svc =
          _service(_storeWithBuff(GuardDropKind.fertilizeVoucher));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.fertilize,
        plantId: 'p1',
      );
      expect(perk.fertilizeDiscount, 2);
      expect(fertilizeCostOf(perk), 8);
    });

    test('劳动券：每次清理除草 +1、除虫 +1（1 → 2 / 2 → 3）', () async {
      final GuardVoucherService svc =
          _service(_storeWithBuff(GuardDropKind.laborVoucher));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.labor,
        plantId: 'p1',
      );
      expect(weedRewardOf(perk), 2.0);
      expect(pestRewardOf(perk), 3.0);
    });

    test('免费浇水券（单株）：5 → 0（钳制，绝不出现负价）', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.freeWater));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
      );
      expect(perk.waterDiscount, 5);
      expect(waterCostOf(perk), 0);
    });

    test('免费施肥券（单株）：10 → 0', () async {
      final GuardVoucherService svc =
          _service(_storeWithBuff(GuardDropKind.freeFertilize));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeFertilize,
        plantId: 'p1',
      );
      expect(perk.fertilizeDiscount, 10);
      expect(fertilizeCostOf(perk), 0);
    });

    test('无道具档：没有 buff ⇒ perk 与称号逐位相同', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.none));
      const PlantPerk lv5 = PlantPerk(waterDiscount: 1);
      final PlantPerk perk = await svc.overlay(
        lv5,
        kind: GuardVoucherKind.water,
        plantId: 'p1',
      );
      expect(perk, lv5);
      expect(await svc.currentBuff(), isNull);
    });
  });

  // ───────────────────────── 🔴 A10：免费券绝不整批 ─────────────────────────
  group('🔴 A10 免费券只能用于单株（批量一律不减免）', () {
    test('批量（plantId == null）：返回的 perk **不含**免费减免', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.freeWater));
      final PlantPerk batch = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: null,
      );
      expect(batch.waterDiscount, 0, reason: '批量动作拿不到免费额度');
      expect(batch, PlantPerk.none, reason: '与称号 perk 逐位相同');
      expect(waterCostOf(batch), 5, reason: '批量里每一盆仍是原价 5 ☀');
    });

    test('单株（plantId == "p1"）：才含免费减免', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.freeWater));
      final PlantPerk single = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
      );
      expect(single.waterDiscount, 5);
      expect(waterCostOf(single), 0);
    });

    test('🔴 一键浇水 5 盆 + 免费券 = 扣 20 ☀（不是 0，也不是 25）', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.freeWater);
      final GuardVoucherService svc = _service(store);

      // 批量调用（page 一键 5 盆）：拿到的是「无免费减免」的 perk。
      final PlantPerk batch = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: null,
      );
      // 唯一被指定的那一盆（孩子挑的第 1 盆）：拿到免费。
      final PlantPerk freeOne = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
      );

      // 4 盆按原价 + 1 盆免费 = 20 ☀。
      final int total = waterCostOf(batch) * 4 + waterCostOf(freeOne);
      expect(total, 20, reason: 'A10：一键 5 盆 + 免费券 ⇒ 20 ☀');
      expect(total, isNot(0), reason: '🔴 绝不整批免费（否则 = 省 25 ☀ = 5 天浇水预算）');
      expect(waterCostOf(batch) * 5, 25, reason: '若误把批量 perk 用到全部 5 盆，就是原价 25');
    });

    test('🔴 批量调用会把免费券的额度「留在账上」（recordConsumed 也拒绝核销）', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.freeWater);
      final GuardVoucherService svc = _service(store);
      await svc.overlay(PlantPerk.none, kind: GuardVoucherKind.freeWater, plantId: null);
      await svc.recordConsumed(kind: GuardVoucherKind.freeWater, plantId: null);
      expect(store.byChild[_childId]!.buff!.used, 0, reason: '批量动作不消耗单株免费额度');
      expect(await svc.remainingOf(GuardVoucherKind.freeWater), 1);
      expect(store.writeCount, 0, reason: '拒绝核销时一个字都不写库');
    });

    test('单株用完一次后，第二盆不再免费', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.freeWater);
      final GuardVoucherService svc = _service(store);
      final PlantPerk first = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
      );
      expect(waterCostOf(first), 0);
      await svc.recordConsumed(kind: GuardVoucherKind.freeWater, plantId: 'p1');

      final PlantPerk second = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p2',
      );
      expect(second.waterDiscount, 0, reason: '免费券只有 1 次/天');
      expect(waterCostOf(second), 5);
    });
  });

  // ─────────────── 🔴 A11（B13.4 改版）：浇水 / 劳动券当日不限次 ───────────────
  group('🔴 A11（B13.4）浇水 / 劳动券当日不限次', () {
    test('12 盆 × 3 次 = 36 次浇水：次次减免，总节省 = 36', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.waterVoucher);
      final GuardVoucherService svc = _service(store);

      int savedTotal = 0;
      int discountedApplications = 0;
      for (int round = 0; round < 3; round++) {
        for (int pot = 0; pot < 12; pot++) {
          final PlantPerk perk = await svc.overlay(
            PlantPerk.none,
            kind: GuardVoucherKind.water,
            plantId: 'p$pot',
          );
          final int price = waterCostOf(perk); // 恒 4
          savedTotal += 5 - price;
          if (price == 4) discountedApplications++;
          await svc.recordConsumed(
            kind: GuardVoucherKind.water,
            plantId: 'p$pot',
          );
        }
      }

      expect(discountedApplications, 36, reason: 'B13.4：36 次全部拿到减免');
      expect(savedTotal, 36, reason: 'A11（B13.4）：总节省 = 36 ☀，封顶已废除');
    });

    test('存量存档 used == quota ⇒ 减免仍生效（B13.4 不看额度字段）', () async {
      // 🔴 B13.4：recordConsumed 对不限次券是空操作（没有额度可记），故直接
      // 构造一份「旧封顶时代用完」的存量存档（used 6 / quota 6）。
      final _FakeStore store = _FakeStore();
      store.byChild[_childId] = const GuardDayState(
        dayKey: _today,
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        dropKind: GuardDropKind.waterVoucher,
        buff: GuardBuffState(
          kind: GuardDropKind.waterVoucher,
          quota: 6,
          used: 6,
        ),
      );
      final GuardVoucherService svc = _service(store);
      final GuardBuffState buff = (await svc.currentBuff())!;
      expect(buff.used, 6);
      expect(buff.isExhausted, isTrue);

      // 🔴 B13.4：即便额度字段用尽，浇水券减免仍全天生效。
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.water,
        plantId: 'p1',
      );
      expect(perk.waterDiscount, 1);
      expect(waterCostOf(perk), 4);
    });

    test('劳动券当日不限次：10 次清理次次 +1（共 +10）', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.laborVoucher);
      final GuardVoucherService svc = _service(store);
      double bonusTotal = 0;
      for (int i = 0; i < 10; i++) {
        final PlantPerk perk = await svc.overlay(
          PlantPerk.none,
          kind: GuardVoucherKind.labor,
          plantId: 'p1',
        );
        bonusTotal += perk.weedBonus;
        await svc.recordConsumed(kind: GuardVoucherKind.labor, plantId: 'p1');
      }
      expect(bonusTotal, 10.0, reason: 'A12（B13.4）：劳动券当日不限次，封顶 4 已废除');
    });

    test('施肥券今日每次 −2 ☀：第 1 / 2 / 3 次施肥都是 8 ☀', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.fertilizeVoucher);
      final GuardVoucherService svc = _service(store);
      // 额度 12 次（最大盆位数，每盆每天限施 1 次）⇒ 连施 3 次都足额减 2。
      for (int i = 1; i <= 3; i++) {
        final PlantPerk perk = await svc.overlay(
          PlantPerk.none,
          kind: GuardVoucherKind.fertilize,
          plantId: 'p$i',
        );
        expect(fertilizeCostOf(perk), 8,
            reason: '第 $i 次施肥仍是 8 ☀（不是回原价 10）');
        await svc.recordConsumed(
            kind: GuardVoucherKind.fertilize, plantId: 'p$i');
      }
      expect(await svc.remainingOf(GuardVoucherKind.fertilize), 9,
          reason: '12 次额度用掉 3 次还剩 9 次');
    });
  });

  group('与称号减免叠加（相加 / 归零）', () {
    test('浇水券 + Lv.5 称号：5 − 1 − 1 = 3', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.waterVoucher));
      final PlantPerk perk = await svc.overlay(
        const PlantPerk(waterDiscount: 1),
        kind: GuardVoucherKind.water,
        plantId: 'p1',
      );
      expect(waterCostOf(perk), 3);
    });

    test('施肥券 + Lv.10 称号：10 − 1 − 2 = 7', () async {
      final GuardVoucherService svc =
          _service(_storeWithBuff(GuardDropKind.fertilizeVoucher));
      final PlantPerk perk = await svc.overlay(
        const PlantPerk(fertilizeDiscount: 1),
        kind: GuardVoucherKind.fertilize,
        plantId: 'p1',
      );
      expect(fertilizeCostOf(perk), 7);
    });

    test('免费券 + 称号：仍归零（钳制到 0，绝不 −1）', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.freeWater));
      final PlantPerk perk = await svc.overlay(
        const PlantPerk(waterDiscount: 1),
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
      );
      expect(waterCostOf(perk), 0);
    });

    test('劳动券 + 称号：加在称号之后（草 1+1+1 = 3 / 虫 2+1+1 = 4）', () async {
      final GuardVoucherService svc =
          _service(_storeWithBuff(GuardDropKind.laborVoucher));
      final PlantPerk perk = await svc.overlay(
        const PlantPerk(weedBonus: 1, pestBonus: 1),
        kind: GuardVoucherKind.labor,
        plantId: 'p1',
      );
      expect(weedRewardOf(perk), 3.0);
      expect(pestRewardOf(perk), 4.0);
    });
  });

  group('过期 / 种类不符：一律不减免', () {
    test('跨天：存档是昨天的 ⇒ currentBuff 为 null、perk 与称号相同', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.freeWater);
      final GuardVoucherService svc = _service(store);
      final DateTime tomorrow = DateTime(2026, 11, 10, 8);
      expect(await svc.currentBuff(now: tomorrow), isNull);

      const PlantPerk lv5 = PlantPerk(waterDiscount: 1);
      final PlantPerk perk = await svc.overlay(
        lv5,
        kind: GuardVoucherKind.freeWater,
        plantId: 'p1',
        now: tomorrow,
      );
      expect(perk, lv5);
      expect(waterCostOf(perk), 4);
      expect(await svc.remainingOf(GuardVoucherKind.water, now: tomorrow), 0);
    });

    test('种类不符：拿浇水券去免施肥费 → 不减免', () async {
      final GuardVoucherService svc = _service(_storeWithBuff(GuardDropKind.waterVoucher));
      final PlantPerk perk = await svc.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.fertilize,
        plantId: 'p1',
      );
      expect(perk.fertilizeDiscount, 0);
      expect(fertilizeCostOf(perk), 10);
    });

    test('种类不符：recordConsumed 也不核销（不会烧掉别的券的额度）', () async {
      final _FakeStore store = _storeWithBuff(GuardDropKind.waterVoucher);
      final GuardVoucherService svc = _service(store);
      await svc.recordConsumed(kind: GuardVoucherKind.fertilize, plantId: 'p1');
      expect(store.byChild[_childId]!.buff!.used, 0);
      expect(store.writeCount, 0);
    });
  });

  group('额度表（quota / unit / buffFor 单点派生）', () {
    test('当日额度：浇水 6 / 劳动 4 / 施肥 12 / 免费浇水 1 / 免费施肥 1 / 无道具 0', () {
      expect(guardVoucherQuotaOf(GuardDropKind.waterVoucher), 6);
      expect(guardVoucherQuotaOf(GuardDropKind.laborVoucher), 4);
      expect(guardVoucherQuotaOf(GuardDropKind.fertilizeVoucher), 12);
      expect(guardVoucherQuotaOf(GuardDropKind.freeWater), 1);
      expect(guardVoucherQuotaOf(GuardDropKind.freeFertilize), 1);
      expect(guardVoucherQuotaOf(GuardDropKind.none), 0);
    });

    test('单次核销单位 = 1（浇水 / 劳动券都按 1 ☀ 累计）', () {
      for (final GuardVoucherKind kind in GuardVoucherKind.values) {
        expect(voucherUnitOf(kind), 1, reason: '${kind.name} 的单位应为 1');
      }
    });

    test('guardBuffFor：无道具档没有 buff，其余档 quota 与上表一致', () {
      expect(guardBuffFor(GuardDropKind.none), isNull);
      final GuardBuffState water = guardBuffFor(GuardDropKind.waterVoucher)!;
      expect(water.kind, GuardDropKind.waterVoucher);
      expect(water.quota, 6);
      expect(water.used, 0);
    });

    test('GuardVoucherKind.of：无道具档返回 null，其余一一对应', () {
      expect(GuardVoucherKind.of(GuardDropKind.none), isNull);
      expect(
        GuardVoucherKind.of(GuardDropKind.freeFertilize),
        GuardVoucherKind.freeFertilize,
      );
      expect(GuardVoucherKind.freeWater.isSinglePlantOnly, isTrue);
      expect(GuardVoucherKind.water.isSinglePlantOnly, isFalse);
    });
  });

  group('overlaySequenceFor：批量逐盆减免序列（B13.4 不限次券全程足额）', () {
    // 🔴 期望值全部写字面量（4/5/2/1），不用 `waterCostOf(perk)` 反推 ——
    //    否则实现把基础价改错时，测试会跟着一起错。

    test('浇水券（不限次）+ 12 盆 ⇒ 水价 4×12', () {
      final GuardVoucherService svc = _service(_FakeStore());
      final List<PlantPerk> seq = svc.overlaySequenceFor(
        const GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6),
        null,
        kind: GuardVoucherKind.water,
        count: 12,
      );
      expect(seq, hasLength(12));
      expect(
        <int>[for (final PlantPerk p in seq) waterCostOf(p)],
        <int>[4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
        reason: 'B13.4：当日不限次，12 盆全部 −1（旧封顶「第 7 盆回 5」废除）',
      );
    });

    test('存量存档只剩 1 ☀ 额度 + 3 盆 ⇒ 仍是 4/4/4（额度字段不挡减免）', () {
      final GuardVoucherService svc = _service(_FakeStore());
      final List<PlantPerk> seq = svc.overlaySequenceFor(
        const GuardBuffState(
          kind: GuardDropKind.waterVoucher,
          quota: 6,
          used: 5,
        ),
        null,
        kind: GuardVoucherKind.water,
        count: 3,
      );
      expect(
        <int>[for (final PlantPerk p in seq) waterCostOf(p)],
        <int>[4, 4, 4],
        reason: 'B13.4：浇水券当日不限次，used/quota 仅记账',
      );
    });

    test('劳动券（不限次）+ 10 处 ⇒ 除草奖励 2×10', () {
      final GuardVoucherService svc = _service(_FakeStore());
      final List<PlantPerk> seq = svc.overlaySequenceFor(
        const GuardBuffState(kind: GuardDropKind.laborVoucher, quota: 4),
        null,
        kind: GuardVoucherKind.labor,
        count: 10,
      );
      expect(
        <double>[for (final PlantPerk p in seq) weedRewardOf(p)],
        <double>[2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
        reason: 'B13.4：当日不限次，10 处全部 +1',
      );
    });

    test('免费浇水券 + 5 盆 ⇒ 5 项全是原价 5（免费券在批量里不生效）', () {
      final GuardVoucherService svc = _service(_FakeStore());
      final List<PlantPerk> seq = svc.overlaySequenceFor(
        const GuardBuffState(kind: GuardDropKind.freeWater, quota: 1),
        null,
        kind: GuardVoucherKind.freeWater,
        count: 5,
      );
      expect(
        <int>[for (final PlantPerk p in seq) waterCostOf(p)],
        <int>[5, 5, 5, 5, 5],
      );
    });
  });

  group('guardVoucherKindForAction（动作 → 券种类 单点）', () {
    // 🔴 期望值写**字面量**，不引用实现里的常量做同义反复：将来加券种类
    //    （例如 freeLabor）时，这条断言会强迫你回来看这张表。
    test('三个动作逐位映射；免费券按「同动作换名」', () {
      expect(
        guardVoucherKindForAction(GuardActionKind.water),
        GuardVoucherKind.water,
      );
      expect(
        guardVoucherKindForAction(GuardActionKind.fertilize),
        GuardVoucherKind.fertilize,
      );
      expect(
        guardVoucherKindForAction(GuardActionKind.labor),
        GuardVoucherKind.labor,
      );

      // 今天掉落的是免费券时，同一个动作要问「免费券的名字」，否则
      // overlayFor / recordConsumed 的种类闸门会拒绝（展示 5 而实际应 0）。
      expect(
        guardVoucherKindForAction(
          GuardActionKind.water,
          activeDrop: GuardDropKind.freeWater,
        ),
        GuardVoucherKind.freeWater,
      );
      expect(
        guardVoucherKindForAction(
          GuardActionKind.fertilize,
          activeDrop: GuardDropKind.freeFertilize,
        ),
        GuardVoucherKind.freeFertilize,
      );
      // 券与动作不匹配时不许「蹭」减免：换名只发生在同一种动作上。
      expect(
        guardVoucherKindForAction(
          GuardActionKind.fertilize,
          activeDrop: GuardDropKind.freeWater,
        ),
        GuardVoucherKind.fertilize,
      );
      expect(
        guardVoucherKindForAction(
          GuardActionKind.labor,
          activeDrop: GuardDropKind.freeWater,
        ),
        GuardVoucherKind.labor,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 🔴 B13.5 双券：主券 + 第二张（10% 双券掉落）。
  //    两张种类恒不同（rollBonus 排除首张）；减免/核销按券种各走各的槽位。
  // ════════════════════════════════════════════════════════════════════════
  group('B13.5 双券：currentBuffs / recordConsumed 按券种路由', () {
    _FakeStore buildDualStore() {
      final _FakeStore store = _FakeStore();
      store.byChild[_childId] = GuardDayState(
        dayKey: _today,
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        dropKind: GuardDropKind.waterVoucher,
        buff: guardBuffFor(GuardDropKind.waterVoucher),
        bonusDropKind: GuardDropKind.fertilizeVoucher,
        bonusBuff: guardBuffFor(GuardDropKind.fertilizeVoucher),
      );
      return store;
    }

    test('currentBuffs 返回 0/1/2 张（主券 + 第二张，顺序 = 主 → 副）', () async {
      final _FakeStore empty = _FakeStore();
      expect(await _service(empty).currentBuffs(), isEmpty,
          reason: '今天没券 → 空表');

      expect((await _service(_storeWithBuff(GuardDropKind.waterVoucher)).currentBuffs())
          .length, 1, reason: '只有主券');

      final List<GuardBuffState> two =
          await _service(buildDualStore()).currentBuffs();
      expect(two.length, 2);
      expect(two[0].kind, GuardDropKind.waterVoucher, reason: '主券在前');
      expect(two[1].kind, GuardDropKind.fertilizeVoucher, reason: '第二张在后');
    });

    test('浇水动作核销写主券槽位（buff.used +1，bonusBuff 不动）', () async {
      // 🔴 槽位路由用**记账型券种**验证：B13.4 起浇水 / 劳动券核销是
      //    无操作（当日不限次不记账），永远推不动 used ⇒ 改用
      //    「施肥券主 + 免费浇水副」（两者核销都真实写 used）。
      final _FakeStore store = _FakeStore();
      store.byChild[_childId] = GuardDayState(
        dayKey: _today,
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        dropKind: GuardDropKind.fertilizeVoucher,
        buff: guardBuffFor(GuardDropKind.fertilizeVoucher),
        bonusDropKind: GuardDropKind.freeWater,
        bonusBuff: guardBuffFor(GuardDropKind.freeWater),
      );
      await _service(store).recordConsumed(
        kind: GuardVoucherKind.fertilize,
        plantId: 'p0',
      );
      final GuardDayState after = store.byChild[_childId]!;
      expect(after.buff!.used, 1, reason: '施肥核销打在主券槽位');
      expect(after.bonusBuff!.used, 0, reason: '第二张（免费浇水）不被误核销');
    });

    test('免费浇水动作核销写第二张槽位（bonusBuff.used +1，主券不动）', () async {
      final _FakeStore store = _FakeStore();
      store.byChild[_childId] = GuardDayState(
        dayKey: _today,
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        dropKind: GuardDropKind.fertilizeVoucher,
        buff: guardBuffFor(GuardDropKind.fertilizeVoucher),
        bonusDropKind: GuardDropKind.freeWater,
        bonusBuff: guardBuffFor(GuardDropKind.freeWater),
      );
      await _service(store).recordConsumed(
        kind: GuardVoucherKind.freeWater,
        plantId: 'p0',
      );
      final GuardDayState after = store.byChild[_childId]!;
      expect(after.bonusBuff!.used, 1, reason: '免费浇水核销打在第二张槽位');
      expect(after.buff!.used, 0, reason: '主券（施肥券）不被误核销');
    });

    test('双券叠加：浇水 −1 与施肥 −2 互不干扰（同日两种动作各自生效）', () async {
      final GuardVoucherService service = _service(buildDualStore());
      final PlantPerk waterPerk = await service.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.water,
        plantId: 'p0',
      );
      expect(waterPerk.waterDiscount, 1, reason: '浇水券 −1（每盆）');
      final PlantPerk fertPerk = await service.overlay(
        PlantPerk.none,
        kind: GuardVoucherKind.fertilize,
        plantId: 'p0',
      );
      expect(fertPerk.fertilizeDiscount, 2, reason: '施肥券 −2（足额，不缩额）');
    });
  });
}
