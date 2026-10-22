/// C74 · 专注等级（40 级 + 9 称号）**领域层单测**：纯函数 + 结算编排。
///
/// 覆盖（设计 §5.24.11 测试点 + 2026-10-14 修订新增边界）：
///  · TC-01 门槛边界（含 **Lv.1 = 60 分钟** 与 `level = 0` 未解锁态）；
///  · TC-02 **C78：称号节点零阳光、零账本行**（原 102☀ 阶梯已废止）；
///  · TC-03 称号映射与**等级↔称号解耦**（Lv.7 → 仍是 Lv.5 的称号）；
///  · TC-04/05 `pendingLevelsOf` / `titleLevelsOf` / `nextSettledLevelOf`（含失败停在上一级）；
///  · TC-06 快路径零账本查询；
///  · TC-07/08 老用户首用静默（不补发）/ 新用户 0 分钟；
///  · TC-09~14 单节点 / 重复进页 / 跨多级 / 账本幂等 / SP 丢失恢复 / 写失败不重试。
///
/// 🟢 夹具纪律：时间戳**一律相对 `DateTime.now()`**（S12），无绝对时间字面量。
library focus_level_service_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/core/i18n/domain_text_l10n.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

// ───────────────────────────────────────────────────────────────────────────
// 夹具
// ───────────────────────────────────────────────────────────────────────────

/// 内存账本假实现（append 真的累计余额；**可注入抛错**用于「写失败不重试」用例）。
class _FakeLedger implements SunlightRepository {
  _FakeLedger({double initialBalance = 0, this.throwOnAmount})
      : _balance = initialBalance;

  final List<SunlightEntry> entries = <SunlightEntry>[];
  double _balance;
  int queryCount = 0;

  /// 命中该金额时 `append` 抛异常（模拟写入失败）；置 null 即恢复。
  double? throwOnAmount;

  @override
  Future<double> append(SunlightEntry entry) async {
    if (throwOnAmount != null && entry.net == throwOnAmount) {
      throw StateError('账本写入失败（测试注入）');
    }
    entries.add(entry);
    _balance += entry.net;
    return _balance;
  }

  @override
  Future<double> balance() async => _balance;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async {
    queryCount++;
    return entries
        .where((SunlightEntry e) =>
            e.refType == refType &&
            e.refId == refId &&
            e.dayKey == dayKey)
        .length;
  }

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async {
    queryCount++;
    return entries
        .where((SunlightEntry e) =>
            e.refType == refType &&
            e.refId == refId &&
            !e.ts.isBefore(since))
        .length;
  }

  @override
  Future<int> countByRefType(String refType) async {
    queryCount++;
    return entries.where((SunlightEntry e) => e.refType == refType).length;
  }

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType == refType && e.refId == refId && (last == null || e.ts.isAfter(last))) {
        last = e.ts;
      }
    }
    return last;
  }

  /// 预置一条「历史已发」的称号阳光（用于幂等 / SP 丢失恢复场景）。
  void seedGranted(int level, int amount) {    entries.add(
      SunlightEntry(
        id: 'seed-lv$level',
        ts: DateTime.now().subtract(const Duration(days: 1)),
        type: SunlightType.earn,
        gross: amount.toDouble(),
        net: amount.toDouble(),
        balanceAfter: amount.toDouble(),
        refType: kFocusLevelUpRefType,
        refId: levelRefIdOf(level),
        dayKey: 'seed',
      ),
    );
  }

  /// 某 refId 在账本里的行数（幂等断言用）。
  int balanceOfRefId(String refId) =>
      entries.where((SunlightEntry e) => e.refId == refId).length;
}

/// 内存 SP 假实现。
class _FakeStore implements FocusLevelSettledStore {
  int? value;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int settledLevel) async {
    value = value == null ? settledLevel : (value! > settledLevel ? value : settledLevel);
  }

  @override
  Future<void> clear() async => value = null;
}

FocusLevelService _service(
  _FakeLedger ledger,
  _FakeStore store, {
  DateTime Function()? clock,
}) =>
    FocusLevelService(
      ledger: ledger,
      store: store,
      idFactory: () => 'id-${DateTime.now().microsecondsSinceEpoch}',
      clock: clock,
    );

void main() {
  // ── TC-01 · 门槛边界 ────────────────────────────────────────────────────
  group('TC-01 门槛判定（40 级，Lv.1 = 60 分钟）', () {
    test('未解锁：0 / 30 / 59.9 分钟 → level = 0（尚未达到 Lv.1）', () {
      expect(levelOfMinutes(0), 0);
      expect(levelOfMinutes(30), 0);
      expect(levelOfMinutes(59.9), 0);
    });

    test('Lv.1 边界：59.9 → 0，60 → 1，119.9 → 1，120 → 2', () {
      expect(levelOfMinutes(59.9), 0);
      expect(levelOfMinutes(60), 1);
      expect(levelOfMinutes(119.9), 1);
      expect(levelOfMinutes(120), 2);
    });

    test('40 档门槛逐条可及且严格递增（内部按分钟存储）', () {
      expect(kFocusLevelThresholdMinutes.length, kFocusLevelMaxLevel);
      for (int i = 0; i < kFocusLevelThresholdMinutes.length; i++) {
        final int lv = i + 1;
        final int minutes = kFocusLevelThresholdMinutes[i];
        expect(levelOfMinutes(minutes.toDouble()), lv,
            reason: 'Lv.$lv 门槛 $minutes 分钟应刚好达到 Lv.$lv');
        if (i > 0) {
          expect(minutes, greaterThan(kFocusLevelThresholdMinutes[i - 1]),
              reason: '门槛必须严格递增');
          expect(levelOfMinutes(minutes - 0.1), lv - 1,
              reason: '门槛前一分钟应停在 Lv.${lv - 1}');
        }
      }
    });

    test('满级：21900 分钟 → Lv.40；再多也不超过 40', () {
      expect(levelOfMinutes(21900), kFocusLevelMaxLevel);
      expect(levelOfMinutes(999999), kFocusLevelMaxLevel);
    });

    test('负数 / NaN 安全落到 0', () {
      expect(levelOfMinutes(-10), 0);
      expect(levelOfMinutes(double.nan), 0);
    });
  });

  // ── TC-02 · 阳光阶梯 ────────────────────────────────────────────────────
  group('TC-02 C78：称号节点零阳光、零账本行（原 102☀ 阶梯废止）', () {
    test('9 个称号节点仍被 titleLevelsOf 挑出；31 次普通升级不挑', () {
      expect(titleLevelsOf(List<int>.of(kFocusLevelTitleLevels)).length, 9);
      final int ordinary = <int>[
        for (int lv = 1; lv <= kFocusLevelMaxLevel; lv++)
          if (!isTitleLevelOf(lv)) lv,
      ].length;
      expect(ordinary, 31, reason: '40 级减去 9 个称号节点 = 31 次普通升级');
    });

    test('全等级扫描结算：账本零新增、totalSunlight 恒 0、amount 恒 0', () async {
      for (final int minutes in <int>[0, 60, 360, 480, 1980, 7620, 21900]) {
        final _FakeLedger ledger = _FakeLedger();
        final _FakeStore store = _FakeStore()..value = 0;
        final FocusLevelSettleResult r =
            await _service(ledger, store).settle(minutes.toDouble());
        expect(ledger.entries, isEmpty,
            reason: '$minutes 分钟结算后账本不得新增任何行（C78）');
        expect(r.totalSunlight, 0, reason: '$minutes 分钟结算 totalSunlight 恒 0');
        for (final LevelGrant g in r.granted) {
          expect(g.amount, 0, reason: 'Lv.${g.level} 的 LevelGrant.amount 恒 0');
        }
      }
    });
  });

  // ── TC-03 · 称号映射与解耦 ──────────────────────────────────────────────
  group('TC-03 称号（9 个，每 5 级一个）与等级解耦', () {
    test('9 个称号节点文案逐条相等', () {
      expect(kFocusLevelTitles.length, 9);
      expect(titleOfLevel(1), '专注小萌芽');
      expect(titleOfLevel(5), '专注小苗苗');
      expect(titleOfLevel(10), '静心小书童');
      expect(titleOfLevel(15), '时光小卫士');
      expect(titleOfLevel(20), '专心小骑士');
      expect(titleOfLevel(25), '守时小星使');
      expect(titleOfLevel(30), '专注小法师');
      expect(titleOfLevel(35), '星辰守护者');
      expect(titleOfLevel(40), '时光大贤者');
    });

    test('🔑 当前称号 = 已解锁的最高称号节点（Lv.7 仍是「专注小苗苗」）', () {
      expect(titleOfLevel(2), '专注小萌芽');
      expect(titleOfLevel(4), '专注小萌芽');
      expect(titleOfLevel(7), '专注小苗苗');
      expect(titleOfLevel(9), '专注小苗苗');
      expect(titleOfLevel(14), '静心小书童');
      expect(titleOfLevel(23), '专心小骑士');
      expect(titleOfLevel(39), '星辰守护者');
    });

    test('未解锁与越界：level<1 → 空串；level>40 → 上钳到最高称号', () {
      expect(titleOfLevel(0), '');
      expect(titleOfLevel(-5), '');
      expect(titleOfLevel(99), '时光大贤者');
    });

    test('latestTitleNodeOfLevel 返回已解锁的最高称号节点', () {
      expect(latestTitleNodeOfLevel(0), 0);
      expect(latestTitleNodeOfLevel(1), 1);
      expect(latestTitleNodeOfLevel(7), 5);
      expect(latestTitleNodeOfLevel(23), 20);
      expect(latestTitleNodeOfLevel(40), 40);
    });
  });

  // ── TC-04/05 · 待领清单与推进 ───────────────────────────────────────────
  group('TC-04/05 pendingLevelsOf / titleLevelsOf / nextSettledLevelOf', () {
    test('pendingLevelsOf：settled=3, current=6 → [4,5,6]；无待领 → []', () {
      expect(
        pendingLevelsOf(currentLevel: 6, settledLevel: 3),
        <int>[4, 5, 6],
      );
      expect(pendingLevelsOf(currentLevel: 3, settledLevel: 3), <int>[]);
      expect(pendingLevelsOf(currentLevel: 2, settledLevel: 8), <int>[]);
    });

    test('titleLevelsOf 只留称号节点', () {
      expect(
        titleLevelsOf(pendingLevelsOf(currentLevel: 12, settledLevel: 0)),
        <int>[1, 5, 10],
      );
      expect(titleLevelsOf(<int>[21, 22, 23]), <int>[]);
    });

    test('nextSettledLevelOf：全部成功 → 推进到 current', () {
      expect(
        nextSettledLevelOf(
          settledLevel: 3,
          currentLevel: 6,
          isGranted: (_) => true,
        ),
        6,
      );
    });

    test('I3 · 中间称号节点（Lv.5）失败 → 停在 4，下轮重试该条而不重复发 Lv.4', () {
      final int next = nextSettledLevelOf(
        settledLevel: 3,
        currentLevel: 6,
        isGranted: (int lv) => lv != 5,
      );
      expect(next, 4, reason: 'Lv.5 未入账 ⇒ settled 停在 4');
      // 下轮从 4 起：pending = [5,6]，仍会再试 Lv.5。
      expect(pendingLevelsOf(currentLevel: 6, settledLevel: 4), <int>[5, 6]);
    });
  });

  group('progressOf / formatDurationL10n（B3：文案迁至 core/i18n）', () {
    test('未解锁：level 0、无称号、进度指向 Lv.1', () {
      final FocusLevelProgress p = progressOf(30);
      expect(p.level, 0);
      expect(p.isLocked, isTrue);
      expect(p.title, '');
      expect(p.nextLevel, 1);
      expect(p.minutesToNext, 30);
      expect(p.progress, closeTo(0.5, 0.001));
      expect(p.isMax, isFalse);
    });

    test('已解锁：进度指向下一级（不是下一个称号）', () {
      final FocusLevelProgress p = progressOf(480); // Lv.5
      expect(p.level, 5);
      expect(p.title, '专注小苗苗');
      expect(p.nextLevel, 6, reason: '下一级是 Lv.6，不是下一个称号节点 Lv.10');
      expect(p.minutesToNext, 180); // Lv.6 = 660 分钟
      expect(p.progress, 0.0);
    });

    test('满级：Lv.40 isMax、无下一级、称号 = 时光大贤者', () {
      final FocusLevelProgress p = progressOf(21900);
      expect(p.level, kFocusLevelMaxLevel);
      expect(p.isMax, isTrue);
      expect(p.title, '时光大贤者');
      expect(p.minutesToNext, 0);
      expect(p.nextLevel, isNull);
      expect(p.progress, 1.0);
    });

    // i18n B3（T02）：`formatDurationMinutes` 已从 domain 删除 —— 迁到
    // `formatDurationL10n(minutes, l10n)`。断言文案逐字节不变（zh 为模板语言）。
    test('时长格式化（儿童友好，不出现大数字分钟）', () {
      expect(formatDurationL10n(0, AppLocalizationsZh()), '0 分钟');
      expect(formatDurationL10n(30, AppLocalizationsZh()), '30 分钟');
      expect(formatDurationL10n(60, AppLocalizationsZh()), '1 小时');
      expect(formatDurationL10n(90, AppLocalizationsZh()), '1 小时 30 分钟');
      expect(formatDurationL10n(21900, AppLocalizationsZh()), '365 小时');
    });
  });

  // ── TC-15/16 · 详情卡（v2「摘要 + 点按详情」新增的两个纯函数）─────────────
  //
  // 二者都是**纯函数**（flutter-free）：UI 层禁止再写一遍「门槛 − 累计」与
  // 「当前节点」的判定（S14 逻辑单点）。
  group('TC-15 titleRowsOfLevel（9 个称号全列 + 当前节点高亮）', () {
    test('恒 9 行，节点与文案一一对应', () {
      final List<FocusLevelTitleRow> rows = titleRowsOfLevel(7);
      expect(rows.length, 9);
      for (int i = 0; i < kFocusLevelTitleLevels.length; i++) {
        expect(rows[i].level, kFocusLevelTitleLevels[i]);
        expect(rows[i].title, kFocusLevelTitles[i]);
      }
    });

    test('Lv.7：解锁 1/5 两行，当前节点仍是 Lv.5（称号 ↔ 等级解耦）', () {
      final List<FocusLevelTitleRow> rows = titleRowsOfLevel(7);
      expect(
        rows.where((FocusLevelTitleRow r) => r.unlocked).length,
        2,
        reason: 'Lv.7 只解锁 Lv.1 与 Lv.5 两个称号节点',
      );
      expect(
        rows.where((FocusLevelTitleRow r) => r.isCurrent).length,
        1,
        reason: '当前称号唯一（9 行里只有一行高亮 + ✨）',
      );
      final FocusLevelTitleRow current =
          rows.firstWhere((FocusLevelTitleRow r) => r.isCurrent);
      expect(current.level, 5);
      expect(current.title, '专注小苗苗');
    });

    test('未解锁（level 0）：无一行 isCurrent，全部未解锁', () {
      final List<FocusLevelTitleRow> rows = titleRowsOfLevel(0);
      expect(rows.length, 9);
      expect(rows.any((FocusLevelTitleRow r) => r.unlocked), isFalse);
      expect(rows.any((FocusLevelTitleRow r) => r.isCurrent), isFalse);
    });

    test('满级（Lv.40）：9 行全解锁，当前节点 = Lv.40', () {
      final List<FocusLevelTitleRow> rows = titleRowsOfLevel(40);
      expect(rows.every((FocusLevelTitleRow r) => r.unlocked), isTrue);
      final FocusLevelTitleRow current =
          rows.firstWhere((FocusLevelTitleRow r) => r.isCurrent);
      expect(current.level, 40);
      expect(current.title, '时光大贤者');
    });

    test('压线：Lv.5（480 分钟）→ 当前节点恰是 Lv.5 自己', () {
      final List<FocusLevelTitleRow> rows = titleRowsOfLevel(5);
      expect(
        rows.firstWhere((FocusLevelTitleRow r) => r.isCurrent).level,
        5,
        reason: '踩到节点门槛的那一刻就切换当前称号',
      );
    });
  });

  // i18n B3（T02）：`nextLevelGapTextOf` 已从 domain 删除 —— 迁到
  // `nextLevelGapTextL10n(progress, l10n)`；渲染结果与迁移前逐字节一致。
  group('TC-16 nextLevelGapTextL10n（距下一级 = 下一级门槛 − 累计）', () {
    final AppLocalizationsZh zh = AppLocalizationsZh();

    test('非满级：Lv.7（900）→ 「距 Lv.8 还差 4 小时」', () {
      expect(nextLevelGapTextL10n(progressOf(900), zh), '距 Lv.8 还差 4 小时',
          reason: 'Lv.8 门槛 1140 − 900 = 240 分钟');
    });

    test('未解锁：59.9 分钟 → 「距 Lv.1 还差 1 分钟」', () {
      expect(nextLevelGapTextL10n(progressOf(59.9), zh), '距 Lv.1 还差 1 分钟',
          reason: 'minutesToNext = ceil(60 − 59.9)');
    });

    test('跨级压线：120 分钟 = Lv.2 → 「距 Lv.3 还差 2 小时」', () {
      expect(nextLevelGapTextL10n(progressOf(120), zh), '距 Lv.3 还差 2 小时',
          reason: 'Lv.3 门槛 240 − 120 = 120 分钟');
    });

    test('满级：显示满级文案（单点收敛到 ARB shared_level_gap_max）', () {
      expect(
        nextLevelGapTextL10n(progressOf(21900), zh),
        '已是最高称号 · 时光大贤者',
      );
    });
  });

  // ── TC-06 · 快路径 ──────────────────────────────────────────────────────
  test('TC-06 快路径零账本查询（sp=18, current=18）', () async {
    final _FakeLedger ledger = _FakeLedger()..seedGranted(5, 5);
    final _FakeStore store = _FakeStore()..value = 18;
    final FocusLevelSettleResult r = await _service(ledger, store).settle(4320);
    expect(r.currentLevel, 17, reason: '4320 分钟 = 72h = Lv.17');
    expect(r.granted, isEmpty);
    expect(r.totalSunlight, 0);
    expect(ledger.queryCount, 0, reason: '快路径不该查账本');
  });

  // ── TC-07/08 · 首用 ─────────────────────────────────────────────────────
  group('TC-07/08 首用', () {
    test('TC-07 老用户首用静默：5000 分钟（Lv.18）→ 认等级、账本零新增、firstUseSilent',
        () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore();
      final FocusLevelSettleResult r = await _service(ledger, store).settle(5000);
      expect(r.currentLevel, 18);
      expect(r.settledLevel, 18);
      expect(r.firstUseSilent, isTrue);
      expect(r.granted, isEmpty, reason: '🔴 不补发历史称号阳光（C74 §9）');
      expect(r.totalSunlight, 0);
      expect(ledger.entries, isEmpty, reason: '账本不得新增任何行');
      expect(store.value, 18);
      // 再次进入：走快路径，仍零发放。
      final FocusLevelSettleResult again =
          await _service(ledger, store).settle(5000);
      expect(again.firstUseSilent, isFalse);
      expect(again.granted, isEmpty);
      expect(ledger.entries, isEmpty);
    });

    test('TC-08 新用户 0 分钟：level = 0、SP 写 0、无阳光无演出', () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore();
      final FocusLevelSettleResult r = await _service(ledger, store).settle(0);
      expect(r.currentLevel, 0);
      expect(r.firstUseSilent, isTrue);
      expect(r.granted, isEmpty);
      expect(store.value, 0);
      expect(ledger.entries, isEmpty);
    });

    test('TC-08b 首用后跨过 Lv.1：60 分钟 → 解锁 Lv.1 属性，零阳光零账本行（C78）',
        () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r = await _service(ledger, store).settle(60);
      expect(r.currentLevel, 1);
      expect(r.granted, <LevelGrant>[const LevelGrant(level: 1, amount: 0)],
          reason: 'granted 非空 ⇒ 播称号演出；amount 恒 0（C78）');
      expect(r.totalSunlight, 0);
      expect(ledger.entries, isEmpty, reason: 'C78 后零账本写入');
    });
  });

  // ── TC-09~14 · 结算与幂等 ───────────────────────────────────────────────
  group('TC-09~14 结算编排与幂等', () {
    test('TC-09 单节点：settled=4 → Lv.5 结算成功（amount 0），账本零新增', () async {
      final _FakeLedger ledger = _FakeLedger(initialBalance: 100);
      final _FakeStore store = _FakeStore()..value = 4;
      final FocusLevelSettleResult r = await _service(ledger, store).settle(480);
      expect(r.granted, <LevelGrant>[const LevelGrant(level: 5, amount: 0)]);
      expect(r.totalSunlight, 0);
      expect(ledger.entries, isEmpty, reason: 'C78 后零账本写入');
      expect(await ledger.balance(), 100, reason: '余额不变');
    });

    test('TC-02b 普通升级：Lv.1 → Lv.4（跨 3 个非称号等级）→ 零阳光零 grant', () async {
      final _FakeLedger ledger = _FakeLedger()..seedGranted(1, 3);
      final _FakeStore store = _FakeStore()..value = 1;
      final FocusLevelSettleResult r = await _service(ledger, store).settle(360);
      expect(r.currentLevel, 4);
      expect(r.granted, isEmpty, reason: 'Lv.2/3/4 都不是称号节点 ⇒ 不播演出');
      expect(r.totalSunlight, 0);
      expect(ledger.entries.length, 1, reason: '只有预置的那条历史记录');
      expect(store.value, 4, reason: 'SP 仍推进到 Lv.4（下轮从 4 起算）');
    });

    test('TC-10 重复进页 5 次：账本零新增、余额恒定（I1 幂等）', () async {
      final _FakeLedger ledger = _FakeLedger(initialBalance: 20);
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelService svc = _service(ledger, store);
      for (int i = 0; i < 5; i++) {
        final FocusLevelSettleResult r = await svc.settle(480); // Lv.5
        expect(r.totalSunlight, 0);
      }
      expect(ledger.entries, isEmpty, reason: 'C78 后零账本写入，重复进页也不新增');
      expect(await ledger.balance(), 20, reason: '余额恒定');
    });

    test('TC-11a 老用户首用一次跳到 Lv.23：🔴 静默，逐雨后零阳光零演出（C74 §9）',
        () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore(); // SP 未写过 = 首次进入本功能
      final FocusLevelSettleResult r =
          await _service(ledger, store).settle(7620); // 127h = Lv.23
      expect(r.currentLevel, 23);
      expect(r.firstUseSilent, isTrue);
      expect(r.granted, isEmpty, reason: '🔴 老用户首用不补发 lv1/5/10/15/20');
      expect(r.totalSunlight, 0);
      expect(ledger.entries, isEmpty);
      expect(store.value, 23);
    });

    test('TC-11b 跨多级（已过首用，settled=0 → Lv.23）：逐节点结算 5 个称号，'
        '零阳光零账本行（C78），只算一场演出量', () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r =
          await _service(ledger, store).settle(7620); // 127h = Lv.23
      expect(r.currentLevel, 23);
      // ⚠️ 已达成称号节点 = 1h/8h/28h/**57h**/98h 五个（Lv.15 门槛是 57 小时，不是 15 小时）。
      expect(
        r.granted,
        <LevelGrant>[
          const LevelGrant(level: 1, amount: 0),
          const LevelGrant(level: 5, amount: 0),
          const LevelGrant(level: 10, amount: 0),
          const LevelGrant(level: 15, amount: 0),
          const LevelGrant(level: 20, amount: 0),
        ],
      );
      expect(r.totalSunlight, 0, reason: 'C78：恒 0');
      expect(r.titlesGained, 5, reason: '演出**只播 1 场**'
          '（由调用方按 granted 非空判定）');
      expect(ledger.entries, isEmpty, reason: 'C78 后零账本写入');
      expect(store.value, 23);
      // 再次进入：零结算（幂等 + SP 已推进）。
      final FocusLevelSettleResult again =
          await _service(ledger, store).settle(7620);
      expect(again.granted, isEmpty);
      expect(again.totalSunlight, 0);
      expect(ledger.entries, isEmpty);
    });

    test('TC-12a 双锚点取大：账本已发 lv5 ⇒ settled 抬到 5，本次零发放', () async {
      final _FakeLedger ledger = _FakeLedger()..seedGranted(5, 5);
      final _FakeStore store = _FakeStore()..value = 4; // SP 还停在 4
      final FocusLevelSettleResult r = await _service(ledger, store).settle(480);
      expect(r.settledLevel, 5, reason: 'settled = max(SP 4, 账本 K 5) = 5');
      expect(r.granted, isEmpty, reason: '🔴 Lv.5 已发过 ⇒ 绝不重复发');
      expect(ledger.entries.length, 1, reason: '未新增任何账本行');
    });

    test('TC-12b 账本已有 lv1（历史行）⇒ 不重播 lv1 演出，只结算新的称号节点', () async {
      final _FakeLedger ledger = _FakeLedger()..seedGranted(1, 3);
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r = await _service(ledger, store).settle(480);
      expect(
        r.granted,
        <LevelGrant>[const LevelGrant(level: 5, amount: 0)],
        reason: 'Lv.1 已在账本里 ⇒ 二级幂等生效，只结算 Lv.5',
      );
      expect(ledger.entries.length, 1, reason: 'C78 后零新增，只剩预置的 lv1 历史行');
      expect(
        ledger.balanceOfRefId(levelRefIdOf(1)),
        1,
        reason: 'lv1 历史行原样保留（append-only）',
      );
    });

    test('TC-13 SP 丢失恢复：账本有 lv20 → settled = 20，绝不补发 lv1/5/10', () async {
      final _FakeLedger ledger = _FakeLedger()..seedGranted(20, 11);
      final _FakeStore store = _FakeStore(); // = null（SP 丢失）
      final FocusLevelSettleResult r = await _service(ledger, store).settle(7620);
      expect(r.granted, isEmpty, reason: '🔴 丢 SP 场景绝不补发历史节点（lv1/5/10/15）');
      expect(r.totalSunlight, 0);
      expect(ledger.entries.length, 1, reason: '只有预置的 lv20 一行');
      expect(store.value, 23,
          reason: '21~23 都是非称号等级 ⇒ settled 一路推进到当前等级');
    });

    test('TC-14 C78 后零写入：即便账本 append 抛错，结算也全量通过、零账本行', () async {
      final _FakeLedger ledger = _FakeLedger(throwOnAmount: 7);
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r = await _service(ledger, store).settle(1980);
      expect(r.currentLevel, 11, reason: '1980 分钟 = 33h = Lv.11');
      expect(r.granted, <LevelGrant>[
        const LevelGrant(level: 1, amount: 0),
        const LevelGrant(level: 5, amount: 0),
        const LevelGrant(level: 10, amount: 0),
      ]);
      expect(r.settledLevel, 11,
          reason: 'C78 零写入：append 抛错不再可发生，节点全部结算成功');
      expect(ledger.entries, isEmpty);
    });

    test('全部 9 个称号节点跑完 → 零阳光、零账本行（C78）', () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r =
          await _service(ledger, store).settle(21900);
      expect(r.currentLevel, kFocusLevelMaxLevel);
      expect(r.totalSunlight, 0);
      expect(r.titlesGained, 9, reason: '9 个节点全部结算成功（amount 恒 0）');
      expect(ledger.entries, isEmpty, reason: 'C78 后零账本写入');
      expect(await ledger.balance(), 0);
    });
  });
}
