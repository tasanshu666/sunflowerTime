/// `GuardDayState` 实体的验收测试：`copyWith` 三态 / buff 封顶 / JSON 往返 / 容错。
///
/// ## 为什么实体也要单测
/// 第二批的 `GuardStateStore` 会把本实体直接 `jsonEncode` 进 `SharedPreferences`，
/// 而「清空可空字段清不掉」是本项目**已经踩过**的坑（`Plant.kClear` 的注释里写着）。
/// 序列化 / 反序列化一旦有 bug，第一批看不出来，第二批会在真机上表现成「券用不掉」
/// 或「昨天的贼今天还在」—— 那时已经很难定位。
library guard_day_state_test;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/domain/entities/guard_chest.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';

void main() {
  group('GuardDayState.empty / 派生 getter', () {
    test('空白起点：status = none、无贼、无 buff、各项归零', () {
      final GuardDayState state = GuardDayState.empty('2026-11-08');
      expect(state.dayKey, '2026-11-08');
      expect(state.status, GuardDayStatus.none);
      expect(state.thiefKind, isNull);
      expect(state.hasThief, isFalse);
      expect(state.isClaimed, isFalse);
      expect(state.isFreeRide, isFalse);
      expect(state.energyUsed, 0);
      expect(state.paidSun, 0);
      expect(state.winSun, 0);
      expect(state.dropKind, GuardDropKind.none);
      expect(state.sunStolen, 0);
      expect(state.growthStolen, isEmpty);
      expect(state.buff, isNull);
    });
  });

  group('copyWith：可空字段必须能清空（防 Plant 踩过的坑）', () {
    const GuardDayState base = GuardDayState(
      dayKey: '2026-11-08',
      status: GuardDayStatus.claimed,
      thiefKind: GuardThiefKind.sneakThief,
      energyUsed: 1,
      paidSun: 0,
      winSun: 2,
      dropKind: GuardDropKind.waterVoucher,
      sunStolen: 0,
      growthStolen: <String, double>{'plant-1': 0.03},
      buff: GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6),
    );

    test('不传 → 保持原值', () {
      final GuardDayState same = base.copyWith();
      expect(same, base);
      expect(same.buff, isNotNull);
      expect(same.thiefKind, GuardThiefKind.sneakThief);
    });

    test('clearBuff: true → buff 变 null', () {
      expect(base.copyWith(clearBuff: true).buff, isNull);
    });

    test('clearThief: true → thiefKind 变 null', () {
      expect(base.copyWith(clearThief: true).thiefKind, isNull);
    });

    test('显式传 buff / thiefKind → 覆盖', () {
      final GuardDayState changed = base.copyWith(
        thiefKind: GuardThiefKind.sunRat,
        buff: const GuardBuffState(
          kind: GuardDropKind.freeFertilize,
          quota: 1,
        ),
      );
      expect(changed.thiefKind, GuardThiefKind.sunRat);
      expect(changed.buff!.kind, GuardDropKind.freeFertilize);
    });

    test('改 dayKey 不会顺手丢掉其它字段', () {
      final GuardDayState next = base.copyWith(dayKey: '2026-11-09');
      expect(next.dayKey, '2026-11-09');
      expect(next.thiefKind, GuardThiefKind.sneakThief);
      expect(next.buff, base.buff);
    });
  });

  group('GuardBuffState：额度与已用（当日累计封顶的实现形态）', () {
    test('remaining = quota - used，且永不为负', () {
      const GuardBuffState buff =
          GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 2);
      expect(buff.remaining, 4);
      expect(buff.isExhausted, isFalse);
      expect(buff.hasRemaining, isTrue);

      const GuardBuffState over =
          GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 9);
      expect(over.remaining, 0);
      expect(over.isExhausted, isTrue);
    });

    test('consume 累加', () {
      const GuardBuffState buff =
          GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6);
      expect(buff.consume(4).used, 4);
      expect(buff.consume(4).remaining, 2);
    });

    test('consume 钳到剩余额度（重复核销不会顶过 quota）', () {
      const GuardBuffState buff =
          GuardBuffState(kind: GuardDropKind.waterVoucher, quota: 6, used: 5);
      expect(buff.consume(100).used, 6);
      expect(buff.consume(100).remaining, 0);
      // 再核销一次是空操作，不会越界。
      expect(buff.consume(100).consume(1).used, 6);
    });

    test('consume(0) / consume(负数) → 原样返回（不产生新对象）', () {
      const GuardBuffState buff =
          GuardBuffState(kind: GuardDropKind.laborVoucher, quota: 4, used: 1);
      expect(identical(buff.consume(0), buff), isTrue);
      expect(identical(buff.consume(-2), buff), isTrue);
    });

    test('已用尽的券 consume 仍是空操作', () {
      const GuardBuffState exhausted =
          GuardBuffState(kind: GuardDropKind.freeWater, quota: 1, used: 1);
      expect(identical(exhausted.consume(1), exhausted), isTrue);
    });
  });

  group('JSON 往返', () {
    test('完整状态 jsonEncode / jsonDecode 后逐字段相等', () {
      const GuardDayState state = GuardDayState(
        dayKey: '2026-11-08',
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.leafBug,
        energyUsed: 1,
        paidSun: 0,
        winSun: 2,
        dropKind: GuardDropKind.laborVoucher,
        sunStolen: 0,
        growthStolen: <String, double>{'plant-1': 0.028, 'plant-2': 0.01},
        buff: GuardBuffState(
          kind: GuardDropKind.laborVoucher,
          quota: 4,
          used: 1,
        ),
      );

      final String encoded = jsonEncode(state.toJson());
      final GuardDayState decoded = GuardDayState.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
        fallbackDayKey: '2026-01-01',
      );

      expect(decoded, state);
      expect(decoded.hashCode, state.hashCode);
      expect(decoded.buff, state.buff);
      expect(decoded.growthStolen, state.growthStolen);
    });

    test('线名是冻结的 ASCII（改线名 = 老存档读不出来）', () {
      final Map<String, Object?> json =
          GuardDayState.empty('2026-11-08').toJson();
      expect(json['status'], 'none');
      expect(json['thiefKind'], isNull);
      expect(json['dropKind'], 'none');
      expect(GuardDayStatus.claimed.id, 'claimed');
      expect(GuardThiefKind.sunRat.id, 'sun_rat');
      expect(GuardThiefKind.leafBug.id, 'leaf_bug');
      expect(GuardThiefKind.sneakThief.id, 'sneak_thief');
      expect(GuardDropKind.waterVoucher.id, 'water_voucher');
      expect(GuardDropKind.laborVoucher.id, 'labor_voucher');
      expect(GuardDropKind.fertilizeVoucher.id, 'fertilize_voucher');
      expect(GuardDropKind.freeWater.id, 'free_water');
      expect(GuardDropKind.freeFertilize.id, 'free_fertilize');
      expect(GuardDropKind.none.id, 'none');
    });

    test('坏 JSON 不抛异常：缺字段 / 未知线名都兜底', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'status': 'landed_on_mars',
          'thiefKind': 'purple_hamster',
          'dropKind': 'golden_egg',
          'energyUsed': '3',
          'winSun': 2.0,
          'growthStolen': <String, Object?>{'plant-1': 'oops', 'plant-2': 0.02},
          'buff': <String, Object?>{'kind': 'unknown', 'quota': null},
        },
        fallbackDayKey: '2026-11-08',
      );
      expect(decoded.dayKey, '2026-11-08', reason: '缺 dayKey 用 fallback');
      expect(decoded.status, GuardDayStatus.none);
      expect(decoded.thiefKind, isNull);
      expect(decoded.dropKind, GuardDropKind.none);
      expect(decoded.energyUsed, 3, reason: 'String 数字要能解析');
      expect(decoded.winSun, 2, reason: 'num 要能取整');
      expect(decoded.growthStolen, <String, double>{'plant-2': 0.02});
      expect(decoded.buff!.kind, GuardDropKind.none);
      expect(decoded.buff!.quota, 0);
      expect(decoded.buff!.remaining, 0);
    });

    test('buff 不是 Map（脏数据）→ null，不抛异常', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{'dayKey': '2026-11-08', 'buff': 'broken'},
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.buff, isNull);
    });

    test('growthStolen 非 Map → 空表，不抛异常', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{'dayKey': '2026-11-08', 'growthStolen': 42},
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.growthStolen, isEmpty);
    });

    test('🔴 B13.5 双券字段：bonusDropKind / bonusBuff 往返逐位相等', () {
      const GuardDayState state = GuardDayState(
        dayKey: '2026-11-11',
        status: GuardDayStatus.claimed,
        thiefKind: GuardThiefKind.sunRat,
        winSun: 2,
        dropKind: GuardDropKind.waterVoucher,
        bonusDropKind: GuardDropKind.fertilizeVoucher,
        buff: GuardBuffState(
          kind: GuardDropKind.waterVoucher,
          quota: 6,
          used: 1,
        ),
        bonusBuff: GuardBuffState(
          kind: GuardDropKind.fertilizeVoucher,
          quota: 12,
          used: 0,
        ),
      );

      final String encoded = jsonEncode(state.toJson());
      final GuardDayState decoded = GuardDayState.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
        fallbackDayKey: '2026-01-01',
      );

      expect(decoded, state);
      expect(decoded.bonusDropKind, GuardDropKind.fertilizeVoucher);
      expect(decoded.bonusBuff, state.bonusBuff);
      // copyWith 两个方向：覆盖 + 显式清空第二张。
      final GuardDayState cleared =
          state.copyWith(clearBonusBuff: true, bonusDropKind: GuardDropKind.none);
      expect(cleared.bonusBuff, isNull);
      expect(cleared.bonusDropKind, GuardDropKind.none);
      expect(cleared.buff, state.buff, reason: '主券不受 clearBonusBuff 影响');
    });

    test('🔴 B13.5 旧存档兼容：缺 bonus 字段 → none / null（不抛异常）', () {
      // 模拟 B13.5 之前的存档：完全没有 bonusDropKind / bonusBuff 线。
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-08',
          'status': 'claimed',
          'dropKind': 'water_voucher',
          'buff': <String, Object?>{'kind': 'water_voucher', 'quota': 6},
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.bonusDropKind, GuardDropKind.none);
      expect(decoded.bonusBuff, isNull);
    });
  });

  group('B1 tutorialSeen（守卫战 v2 · 教学浮层只播一次的持久化标记）', () {
    test('缺省 false：空状态 / 构造不传 / copyWith 不传都保持 false', () {
      expect(GuardDayState.empty('2026-11-08').tutorialSeen, isFalse);
      const GuardDayState state = GuardDayState(
        dayKey: '2026-11-08',
        status: GuardDayStatus.pending,
      );
      expect(state.tutorialSeen, isFalse);
      expect(state.copyWith().tutorialSeen, isFalse);
    });

    test('copyWith(true) 置位；再 copyWith 不传保持 true', () {
      const GuardDayState base = GuardDayState(
        dayKey: '2026-11-08',
        status: GuardDayStatus.pending,
      );
      expect(base.copyWith(tutorialSeen: true).tutorialSeen, isTrue);
      expect(
        base.copyWith(tutorialSeen: true).copyWith().tutorialSeen,
        isTrue,
        reason: '已看过的标记不会被无关 copyWith 冲掉',
      );
    });

    test('JSON 往返：true 编码后再解码仍 true；参与 == 与 hashCode', () {
      const GuardDayState seen = GuardDayState(
        dayKey: '2026-11-08',
        status: GuardDayStatus.pending,
        tutorialSeen: true,
      );
      final GuardDayState decoded = GuardDayState.fromJson(
        jsonDecode(jsonEncode(seen.toJson())) as Map<String, Object?>,
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.tutorialSeen, isTrue);
      expect(decoded, seen);
      expect(decoded.hashCode, seen.hashCode);
      expect(seen, isNot(seen.copyWith(tutorialSeen: false)));
    });

    test('向后兼容：老存档 JSON 无 tutorialSeen 键 → 兜底 false，不抛异常', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-08',
          'status': 'pending',
          'thiefKind': 'sun_rat',
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.tutorialSeen, isFalse);
      // 脏值（非 bool）也兜底 false，绝不为 true。
      final GuardDayState dirty = GuardDayState.fromJson(
        <String, Object?>{'dayKey': '2026-11-08', 'tutorialSeen': 'yes'},
        fallbackDayKey: '2026-01-01',
      );
      expect(dirty.tutorialSeen, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Guard-B13.11：高级宝箱六字段（纯加性 ⇒ 老存档必须零迁移可读）
  // ════════════════════════════════════════════════════════════════════════
  group('Guard-B13.11 宝箱六字段：缺省 / 往返 / copyWith / 旧存档兼容', () {
    const GuardDayState full = GuardDayState(
      dayKey: '2026-11-11',
      status: GuardDayStatus.pending,
      thiefKind: GuardThiefKind.sunRat,
      winSun: 4,
      dropKind: GuardDropKind.waterVoucher,
      chestTier: GuardChestTier.premium,
      chestBonusDropKind: GuardDropKind.laborVoucher,
      chestFragmentQty: 2,
      chestSeedKind: GuardSeedKind.premium,
      chestSeedSpeciesId: 'species_lotus',
      chestExtrasGranted: true,
    );

    test('缺省值：chestTier = normal、其余全空、未发放', () {
      const GuardDayState state = GuardDayState(
        dayKey: '2026-11-11',
        status: GuardDayStatus.pending,
      );
      // 🔴 缺省是 **normal**（不是「没有宝箱」）：普通宝箱 = 改造前的全部内容，
      //    所以老存档读成 normal 一分钱都不会多发。
      expect(state.chestTier, GuardChestTier.normal);
      expect(state.chestBonusDropKind, GuardDropKind.none);
      expect(state.chestFragmentQty, 0);
      expect(state.chestSeedKind, GuardSeedKind.none);
      expect(state.chestSeedSpeciesId, isNull);
      expect(state.chestExtrasGranted, isFalse);
      expect(GuardDayState.empty('2026-11-11').chestTier, GuardChestTier.normal);
    });

    test('JSON 往返：六个字段逐位相等（含 == / hashCode）', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        jsonDecode(jsonEncode(full.toJson())) as Map<String, Object?>,
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded, full);
      expect(decoded.hashCode, full.hashCode);
      expect(decoded.chestTier, GuardChestTier.premium);
      expect(decoded.chestBonusDropKind, GuardDropKind.laborVoucher);
      expect(decoded.chestFragmentQty, 2);
      expect(decoded.chestSeedKind, GuardSeedKind.premium);
      expect(decoded.chestSeedSpeciesId, 'species_lotus');
      expect(decoded.chestExtrasGranted, isTrue);
      // 编码出来的键名（线名冻结，改动等于让老存档读不出来）。
      final Map<String, Object?> json = full.toJson();
      expect(json['chestTier'], 'premium');
      expect(json['chestBonusDropKind'], 'labor_voucher');
      expect(json['chestFragmentQty'], 2);
      expect(json['chestSeedKind'], 'premium');
      expect(json['chestSeedSpeciesId'], 'species_lotus');
      expect(json['chestExtrasGranted'], isTrue);
    });

    test('copyWith 覆盖 + 显式清空物种（clearChestSeedSpeciesId）', () {
      expect(full.copyWith().chestSeedSpeciesId, 'species_lotus');
      expect(full.copyWith(chestFragmentQty: 1).chestFragmentQty, 1);
      expect(full.copyWith(chestTier: GuardChestTier.normal).chestTier,
          GuardChestTier.normal);
      expect(full.copyWith(chestExtrasGranted: false).chestExtrasGranted, isFalse);
      final GuardDayState cleared = full.copyWith(
        clearChestSeedSpeciesId: true,
        chestSeedKind: GuardSeedKind.none,
      );
      expect(cleared.chestSeedSpeciesId, isNull,
          reason: '可空字段必须能清（防 Plant 踩过的坑）');
      expect(cleared.chestSeedKind, GuardSeedKind.none);
      expect(cleared.chestFragmentQty, 2, reason: '清物种不影响碎片');
    });

    test('== / hashCode 覆盖六个新字段（缺一个就会出现假绿）', () {
      final List<GuardDayState> variants = <GuardDayState>[
        full.copyWith(chestTier: GuardChestTier.normal),
        full.copyWith(chestBonusDropKind: GuardDropKind.none),
        full.copyWith(chestFragmentQty: 1),
        full.copyWith(chestSeedKind: GuardSeedKind.common),
        full.copyWith(chestSeedSpeciesId: 'species_rose'),
        full.copyWith(chestExtrasGranted: false),
      ];
      for (final GuardDayState v in variants) {
        expect(v, isNot(full), reason: '变体必须与基准不等：$v');
      }
    });

    test('🔴 旧存档兼容：完全没有 chest* 键 → 全兜底，不抛异常', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-08',
          'status': 'claimed',
          'dropKind': 'water_voucher',
          'winSun': 4,
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.chestTier, GuardChestTier.normal);
      expect(decoded.chestBonusDropKind, GuardDropKind.none);
      expect(decoded.chestFragmentQty, 0);
      expect(decoded.chestSeedKind, GuardSeedKind.none);
      expect(decoded.chestSeedSpeciesId, isNull);
      expect(decoded.chestExtrasGranted, isFalse);
      // 老字段一个不改（经济口径零变化）。
      expect(decoded.winSun, 4);
      expect(decoded.dropKind, GuardDropKind.waterVoucher);
    });

    test('脏数据兜底：未知线名 / 负片数 / 非 bool 标记', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-11',
          'chestTier': 'ultra', // 未知档位 → normal
          'chestBonusDropKind': 42, // 非字符串 → none
          'chestFragmentQty': -3, // 负数 → 0
          'chestSeedKind': 'common',
          'chestSeedSpeciesId': 123, // 非字符串 → null
          'chestExtrasGranted': 'yes', // 非 bool → false
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.chestTier, GuardChestTier.normal);
      expect(decoded.chestBonusDropKind, GuardDropKind.none);
      expect(decoded.chestFragmentQty, 0);
      expect(decoded.chestSeedKind, GuardSeedKind.common);
      expect(decoded.chestSeedSpeciesId, isNull);
      expect(decoded.chestExtrasGranted, isFalse);
    });

    test('不变量：种子档位为 none ⇒ 物种强制 null（即使存档里写了）', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-11',
          'chestSeedKind': 'none',
          'chestSeedSpeciesId': 'species_lotus',
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.chestSeedSpeciesId, isNull,
          reason: '脏存档不该让发放层相信「没有档位却有物种」');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // P2-③ 旧（非 chest*）字段的脏类型容错
  //
  // 背景：本批给 chest* 四键引入了 `_stringOf` 兜底，但 `status` / `thiefKind` /
  // `dropKind` / `bonusDropKind` 仍是 `json['x'] as String?` —— 一条 `{"status": 42}`
  // 就抛 `TypeError`，与文件头「绝不抛异常 —— 一份坏掉的 prefs 不该让孩子打不开
  // 今日页」直接相悖（生产侧 `GuardStatePrefsStore.read` 的 `catch(_)` 只是把
  // 白屏挡住了，契约仍然不一致）。
  //
  // 🔴 收尾：`dayKey` 原来是 `(json['dayKey'] as String?) ?? fallbackDayKey` ——
  // **同一类残留**（`{"dayKey": 42}` 一样抛 `TypeError`），留着等于本批只修一半。
  // 现在与那四个字段同口径（`_stringOf(...) ?? fallbackDayKey`）。
  //
  // 逐字段钉死：**不抛异常** + **回落到缺省值**。
  // ══════════════════════════════════════════════════════════════════════
  group('P2-③ 旧字段脏类型：不抛 TypeError，回落缺省值', () {
    test('{"status": 42} ⇒ status = none（不是抛 TypeError）', () {
      late GuardDayState decoded;
      expect(
        () => decoded = GuardDayState.fromJson(
          <String, Object?>{'dayKey': '2026-11-11', 'status': 42},
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
        reason: '一个坏 prefs 不该让孩子打不开今日页',
      );
      expect(decoded.status, GuardDayStatus.none);
    });

    test('{"thiefKind": 42} ⇒ thiefKind = null（不是抛 TypeError）', () {
      late GuardDayState decoded;
      expect(
        () => decoded = GuardDayState.fromJson(
          <String, Object?>{'dayKey': '2026-11-11', 'thiefKind': 42},
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
      );
      expect(decoded.thiefKind, isNull);
      expect(decoded.hasThief, isFalse);
    });

    test('{"dropKind": []} ⇒ dropKind = none（不是抛 TypeError）', () {
      late GuardDayState decoded;
      expect(
        () => decoded = GuardDayState.fromJson(
          <String, Object?>{'dayKey': '2026-11-11', 'dropKind': <Object?>[]},
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
      );
      expect(decoded.dropKind, GuardDropKind.none);
    });

    test('{"bonusDropKind": {}} ⇒ bonusDropKind = none（不是抛 TypeError）', () {
      late GuardDayState decoded;
      expect(
        () => decoded = GuardDayState.fromJson(
          <String, Object?>{
            'dayKey': '2026-11-11',
            'bonusDropKind': <String, Object?>{'k': 'v'},
          },
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
      );
      expect(decoded.bonusDropKind, GuardDropKind.none);
    });

    test('🔴 {"dayKey": 42} ⇒ 回落 fallbackDayKey（不是抛 TypeError）；空串同口径', () {
      // `dayKey` 原来是 `(json['dayKey'] as String?) ?? fallbackDayKey` ——
      // 与上面四个字段**同一类残留**：脏类型一样抛 `TypeError`。
      // 换成 `_stringOf` 之后：
      //  · 非 String（42）→ null → 回落 fallbackDayKey；
      //  · 空串（''）→ 也回落 fallbackDayKey（空串**不是**合法 dayKey：它会让
      //    「同一天 ⇒ 空操作」永不成立，等于天天重结算）。
      late GuardDayState decoded;
      expect(
        () => decoded = GuardDayState.fromJson(
          <String, Object?>{'dayKey': 42},
          fallbackDayKey: '2026-01-01',
        ),
        returnsNormally,
        reason: '一个坏 prefs 不该让孩子打不开今日页',
      );
      expect(decoded.dayKey, '2026-01-01');

      final GuardDayState emptyKey = GuardDayState.fromJson(
        <String, Object?>{'dayKey': ''},
        fallbackDayKey: '2026-01-01',
      );
      expect(emptyKey.dayKey, '2026-01-01',
          reason: '空串不是合法 dayKey，必须回落（保持既有语义）');

      // 合法的值照旧原样保留。
      final GuardDayState good = GuardDayState.fromJson(
        <String, Object?>{'dayKey': '2026-11-11'},
        fallbackDayKey: '2026-01-01',
      );
      expect(good.dayKey, '2026-11-11');
    });

    test('四个旧字段同时脏 ⇒ 一次性全部兜底，且不影响相邻字段', () {
      final GuardDayState decoded = GuardDayState.fromJson(
        <String, Object?>{
          'dayKey': '2026-11-11',
          'status': 42,
          'thiefKind': <String, Object?>{},
          'energyUsed': 1,
          'winSun': 4,
          'dropKind': 3.5,
          'bonusDropKind': true,
        },
        fallbackDayKey: '2026-01-01',
      );
      expect(decoded.dayKey, '2026-11-11');
      expect(decoded.status, GuardDayStatus.none);
      expect(decoded.thiefKind, isNull);
      expect(decoded.dropKind, GuardDropKind.none);
      expect(decoded.bonusDropKind, GuardDropKind.none);
      // 相邻的数值字段照旧解析（兜底不能变成「整份退回缺省」）。
      expect(decoded.energyUsed, 1);
      expect(decoded.winSun, 4);
    });
  });
}
