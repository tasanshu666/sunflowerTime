/// 花园守卫 · 当日状态存储（`GuardStatePrefsStore`）单测。
///
/// 真源：`docs/花园守卫_向日葵守卫者_增量PRD_v2.md` §7.2（存储方案）。
///
/// ## 本文件钉死的 5 件事
///  1. 🔴 **键名必须带 childId 后缀**（`guard_day_state_v2_<childId>`）：
///     prefs 是**设备级**，不带后缀会让「A 的小偷出现在 B 的今日页、A 的浇水券被 B 用掉」；
///  2. JSON 往返逐字段一致（`dayKey` / 状态 / 掉落档 / buff / growthStolen）；
///  3. 🔴 **跨天后 read 返回那条旧存档**（不自动重置、不删键）—— 这是
///     `GuardService.expire()` 能结算昨天损失的前提，口径见
///     `domain/repositories/guard_state_store.dart` 文件头；
///  4. 坏 JSON / 非 Map 存档 → 空白当日状态，**绝不抛异常**（别让孩子打不开今日页）；
///  5. `clear` 只删自己的键，不动 prefs 里其他任何东西。
library guard_state_store_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/guard_state_prefs_store.dart';
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/entities/guard_thief.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';

DateTime _today() => DateTime(2026, 11, 9, 10, 0);
DateTime _tomorrow() => DateTime(2026, 11, 10, 10, 0);

GuardDayState _stateOf(String dayKey) => GuardDayState(
      dayKey: dayKey,
      status: GuardDayStatus.claimed,
      thiefKind: GuardThiefKind.sneakThief,
      energyUsed: 1,
      paidSun: 0,
      winSun: 3,
      dropKind: GuardDropKind.waterVoucher,
      sunStolen: 2,
      growthStolen: const <String, double>{'p1': 0.03, 'p2': 0.01},
      buff: guardBuffFor(GuardDropKind.waterVoucher),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  test('🔴 键名 = 前缀 + childId（两个孩子互相看不见对方的状态）', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    await store.write('kid-a', _stateOf('2026-11-09'));

    // 前缀写字面量（不从常量反推）：改掉它会让所有老存档读不出来。
    expect(prefs.getString('guard_day_state_v2_kid-a'), isNotNull);
    expect(prefs.getString('guard_day_state_v2_kid-b'), isNull);

    final GuardDayState a = await store.read('kid-a');
    expect(a.thiefKind, GuardThiefKind.sneakThief);

    final GuardDayState b = await store.read('kid-b');
    expect(b.hasThief, isFalse, reason: '🔴 B 不该看到 A 的小偷');
    expect(b.buff, isNull, reason: '🔴 B 不该看到 A 的浇水券');
    expect(b.dayKey, '2026-11-09', reason: '没有存档 ⇒ 用今天兜底');
  });

  test('JSON 往返：dayKey / 状态 / 掉落 / buff / growthStolen 逐字段一致', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    final GuardDayState original = _stateOf('2026-11-09');
    await store.write('kid-a', original);
    expect(await store.read('kid-a'), original);
  });

  test('一天只有一条存档：重复 write 覆盖，不会累积', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    await store.write('kid-a', GuardDayState.empty('2026-11-09'));
    await store.write('kid-a', _stateOf('2026-11-09'));

    // 前缀只有一条键（不是按天追加），且读到的是最后一次写入的内容。
    final Iterable<String> guardKeys = prefs
        .getKeys()
        .where((String k) => k.startsWith('guard_day_state_v2_'));
    expect(guardKeys.length, 1);
    expect((await store.read('kid-a')).hasThief, isTrue);
  });

  test('跨天读到的仍是「昨天那条」（expire 靠它结算损失）', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    await store.write('kid-a', _stateOf('2026-11-09'));

    // 换一个时钟（第二天）再读：仍是旧存档，没有被偷偷重置成"今天空白"。
    final GuardStatePrefsStore nextDay =
        GuardStatePrefsStore(prefs, clock: _tomorrow);
    final GuardDayState stale = await nextDay.read('kid-a');
    expect(stale.dayKey, '2026-11-09');
    expect(stale.hasThief, isTrue);
    expect(stale.sunStolen, 2);
    expect(stale.growthStolen, <String, double>{'p1': 0.03, 'p2': 0.01});
    expect(prefs.containsKey('guard_day_state_v2_kid-a'), isTrue,
        reason: '🔴 read 绝不删键（结算与清理都是 expire() 的责任）');
  });

  test('坏存档（非 JSON / 非 Map）→ 空白当日状态，不抛异常', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    prefs.setString('guard_day_state_v2_broken', 'not-a-json{');
    final GuardDayState broken = await store.read('broken');
    expect(broken.dayKey, '2026-11-09');
    expect(broken.hasThief, isFalse);

    prefs.setString('guard_day_state_v2_list', '[1,2,3]');
    final GuardDayState list = await store.read('list');
    expect(list.dayKey, '2026-11-09');
    expect(list.hasThief, isFalse);
  });

  test('缺 dayKey 的存档：用今天兜底（不抛）', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    prefs.setString('guard_day_state_v2_partial', '{"status":"pending"}');
    final GuardDayState partial = await store.read('partial');
    expect(partial.dayKey, '2026-11-09');
    expect(partial.status, GuardDayStatus.pending);
  });

  test('clear 只删自己的键（其他孩子的存档原样保留）', () async {
    final GuardStatePrefsStore store =
        GuardStatePrefsStore(prefs, clock: _today);
    await store.write('kid-a', _stateOf('2026-11-09'));
    await store.write('kid-b', _stateOf('2026-11-09'));

    await store.clear('kid-a');

    expect(prefs.containsKey('guard_day_state_v2_kid-a'), isFalse);
    expect(prefs.containsKey('guard_day_state_v2_kid-b'), isTrue);
    expect((await store.read('kid-b')).hasThief, isTrue);
  });
}
