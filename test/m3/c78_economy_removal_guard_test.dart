/// C78 · **称号奖励经济层删除守卫**（设计 §0.2「v2.0 增量修订（C78）」）。
///
/// 钉住两件事：
///  ① **跨多级结算零阳光账本行**：预置「历史已发」的 `focus_level_up` 账本行（模拟
///     老号），从 0 分钟一路结算到满级——账本**零新增行**、无负向对冲行、余额不动、
///     `LevelGrant.amount` / `totalSunlight` 恒 0；重复结算（幂等）同样零写入；
///  ② **删除守卫（grep 红线）**：C78 废止的 6 个符号（`kFocusLevelUpSunlight` /
///     `sunlightOfLevel` / `sunlightTotalOf` / `kFocusLevelTotalSunlight` /
///     `_TitleRowReward` / `kLevelDetailPerkRightColMaxWidth`）在 `lib/**` 必须
///     **0 命中**——防止「复制粘贴复活」；同时正对照：冻结符号
///     `kFocusLevelUpRefType`（账本 refType 值冻结）必须仍存在。
///
/// 🟢 纯 Dart + dart:io，零 flutter widget；`flutter test` 直跑。
library c78_economy_removal_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_level.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';

// ───────────────────────────────────────────────────────────────────────────
// 夹具（与 focus_level_service_test 同构的最小内存假实现）
// ───────────────────────────────────────────────────────────────────────────

/// 内存账本假实现：append 真实累计余额，全量记录便于断言「零新增」。
class _FakeLedger implements SunlightRepository {
  _FakeLedger({double initialBalance = 0}) : _balance = initialBalance;

  final List<SunlightEntry> entries = <SunlightEntry>[];
  double _balance;

  /// 预置一条「历史已发」的称号阳光行（模拟 C78 前老号账本）。
  void seedGranted(int level, int amount) {
    entries.add(
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

  @override
  Future<double> append(SunlightEntry entry) async {
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
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType &&
              e.refId == refId &&
              e.dayKey == dayKey)
          .length;

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      entries
          .where((SunlightEntry e) =>
              e.refType == refType && e.refId == refId && !e.ts.isBefore(since))
          .length;

  @override
  Future<int> countByRefType(String refType) async =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType == refType &&
          e.refId == refId &&
          (last == null || e.ts.isAfter(last))) {
        last = e.ts;
      }
    }
    return last;
  }
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

FocusLevelService _service(_FakeLedger ledger, _FakeStore store) =>
    FocusLevelService(
      ledger: ledger,
      store: store,
      idFactory: () => 'id-${DateTime.now().microsecondsSinceEpoch}',
    );

/// 递归收集 `lib/**.dart` 源码文本（删除守卫 grep 用）。
List<File> _libDartFiles() {
  final List<File> files = <File>[];
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) {
    return files;
  }
  final List<File> stack = <File>[];
  stack.addAll(
    lib.listSync(recursive: true).whereType<File>().where(
          (File f) => f.path.endsWith('.dart'),
        ),
  );
  files.addAll(stack);
  return files;
}

void main() {
  // ── ① 跨多级结算零阳光账本行 ────────────────────────────────────────────
  group('① C78 跨多级结算：零阳光账本行（append-only 纪律）', () {
    test('老号（历史行已存在，发到 Lv.5）从 0 结算到满级：账本零新增、无对冲行、余额不动', () async {
      final _FakeLedger ledger = _FakeLedger();
      // 模拟 C78 前老号：只发到 Lv.5（账本里有 2 条历史行，append-only 永不清理）。
      const int grantedUpTo = 5;
      for (final int node in kFocusLevelTitleLevels) {
        if (node > grantedUpTo) break;
        ledger.seedGranted(node, 1);
      }
      final double balanceBefore = await ledger.balance();
      final int rowsBefore = ledger.entries.length;
      expect(rowsBefore, 2, reason: '预置：Lv.1 / Lv.5 两条历史行');

      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelSettleResult r =
          await _service(ledger, store).settle(21900); // 一口气到满级

      // 老号保护：Lv.1 / Lv.5 已有账本行 → 不重播；其余 7 个节点入列（演出照播）。
      expect(
        r.granted.map((LevelGrant g) => g.level).toList(),
        <int>[10, 15, 20, 25, 30, 35, 40],
        reason: '历史行覆盖的节点跳过，未覆盖节点补入 granted（amount 恒 0）',
      );
      expect(ledger.entries.length, rowsBefore,
          reason: 'C78：结算不得新增任何账本行（历史行保留，新节点零写入）');
      expect(await ledger.balance(), balanceBefore,
          reason: '余额不得因结算变动');
      expect(r.totalSunlight, 0, reason: 'totalSunlight 恒 0（C78）');
      for (final LevelGrant g in r.granted) {
        expect(g.amount, 0, reason: 'Lv.${g.level} 的 LevelGrant.amount 恒 0');
      }
      // 零负向对冲行：结算零新增行，天然无 spend 行。
      expect(
        ledger.entries
            .where((SunlightEntry e) => e.refType == kFocusLevelUpRefType)
            .length,
        2,
        reason: 'focus_level_up 行仍恰为 2 条历史行（无新增、无对冲）',
      );
    });

    test('幂等：同一进度重复结算零写入', () async {
      final _FakeLedger ledger = _FakeLedger();
      final _FakeStore store = _FakeStore()..value = 0;
      final FocusLevelService svc = _service(ledger, store);
      await svc.settle(21900);
      final int rowsAfterFirst = ledger.entries.length;
      expect(rowsAfterFirst, 0, reason: '首次结算（新号）也应零写入');

      await svc.settle(21900); // 重复进页 / 重复结算
      expect(ledger.entries.length, rowsAfterFirst,
          reason: 'C78 后幂等不再依赖账本查询，重复结算依旧零写入');
    });
  });

  // ── ② 删除守卫（grep 红线）────────────────────────────────────────────
  group('② C78 删除守卫：废止符号在 lib/** 0 命中', () {
    final List<File> files = _libDartFiles();
    test('lib/ 目录存在且含 dart 源码（守卫前置自检）', () {
      expect(files, isNotEmpty, reason: '守卫必须在仓库根目录可找到 lib/**.dart');
    });

    for (final String symbol in <String>[
      'kFocusLevelUpSunlight',
      'sunlightOfLevel',
      'sunlightTotalOf',
      'kFocusLevelTotalSunlight',
      '_TitleRowReward',
      'kLevelDetailPerkRightColMaxWidth',
    ]) {
      test('「$symbol」在 lib/** 0 命中（C78 废止，防复制粘贴复活）', () {
        final List<String> hits = <String>[
          for (final File f in files)
            if (f.readAsStringSync().contains(symbol)) f.path,
        ];
        expect(hits, isEmpty,
            reason: 'C78 已删除「$symbol」，lib/** 不得再次出现：$hits');
      });
    }

    test('正对照：冻结符号 kFocusLevelUpRefType 仍存在（账本 refType 值冻结）', () {
      expect(kFocusLevelUpRefType, 'focus_level_up');
      final List<String> hits = <String>[
        for (final File f in files)
          if (f.readAsStringSync().contains('kFocusLevelUpRefType')) f.path,
      ];
      expect(hits, isNotEmpty, reason: '冻结符号必须仍在 lib/**（老号账本幂等依赖）');
    });
  });
}
