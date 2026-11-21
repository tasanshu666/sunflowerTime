/// 大招能量累计落库与幂等测试（定死点① / A1/A2/A10 / B4）。
///
/// 覆盖：sessionId 去重、跨会话累加、跨天不清零、旧能量零污染、
/// `shortAborted` 照常计入、writer 缺省 null 旧行为零改动。
/// 测试期望值独立写死，禁止复用被测函数自证。
library guard_ultimate_credit_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/data/local/guard_ultimate_energy_prefs_store.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/guard_ultimate_energy_store.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/services/focus_engine.dart';
import 'package:sunflower_time/domain/services/guard_ultimate_service.dart';
import 'package:sunflower_time/domain/services/sunlight_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String child = 'kid-A';

  group('GuardUltimateService · 累计落库与幂等', () {
    late GuardUltimateEnergyPrefsStore store;
    late GuardUltimateService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      store = GuardUltimateEnergyPrefsStore(sp);
      service = GuardUltimateService(
        store: store,
        childId: () => child,
      );
    });

    test('同一 sessionId 重复结算只计一次（幂等）', () async {
      expect(await service.creditFocus(
        sessionId: 's1',
        childId: child,
        actualFocusMin: 29,
      ), isTrue);
      expect(await service.creditFocus(
        sessionId: 's1',
        childId: child,
        actualFocusMin: 29,
      ), isFalse);
      final UltimateEnergy e = await service.read();
      expect(e.filledCells, 0);
      expect(e.fractionMin, 29); // 没被重复累加
      expect(e.totalFocusMin, 29.0);
    });

    test('跨会话累加：29 + 1 ⇒ 点亮 1 格（A1）', () async {
      await service.creditFocus(
          sessionId: 's1', childId: child, actualFocusMin: 29);
      await service.creditFocus(
          sessionId: 's2', childId: child, actualFocusMin: 1);
      final UltimateEnergy e = await service.read();
      expect(e.filledCells, 1);
      expect(e.fractionMin, 0);
    });

    test('满 2 格后继续结算不再增长（B1）', () async {
      for (int i = 0; i < 8; i++) {
        await service.creditFocus(
            sessionId: 's$i', childId: child, actualFocusMin: 15);
      }
      final UltimateEnergy e = await service.read();
      expect(e.filledCells, 2);
      expect(e.fractionMin, 0);
      expect(e.totalFocusMin, 60.0, reason: '满 2 格后总量停止增长（第 5 次起早返回）');
    });

    test('跨天不清零：cold restart（重建 service 读同一 prefs）值不变（A2）', () async {
      await service.creditFocus(
          sessionId: 's1', childId: child, actualFocusMin: 59);
      // 模拟跨天 / 冷启动：新建 service 指向同一 store。
      final GuardUltimateService afterReboot = GuardUltimateService(
        store: store,
        childId: () => child,
      );
      final UltimateEnergy e = await afterReboot.read();
      expect(e.filledCells, 1);
      expect(e.fractionMin, 29, reason: '零头跨天保留，不清零');
    });

    test('释放扣 1 格 + fractionMin 不动', () async {
      await service.creditFocus(
          sessionId: 's1', childId: child, actualFocusMin: 44); // 1 格 + 14
      final UltimateEnergy after = await service.spendCell();
      expect(after.filledCells, 0);
      expect(after.fractionMin, 14);
      expect((await service.read()).filledCells, 0);
    });

    test('0 格释放 no-op', () async {
      final UltimateEnergy e = await service.spendCell();
      expect(e.filledCells, 0);
    });
  });

  group('存储隔离 · 旧能量零污染（口径 1 / C3 / A10）', () {
    test('新 key 与旧 guard_energy_v1_* 物理分离', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final GuardUltimateEnergyPrefsStore store =
          GuardUltimateEnergyPrefsStore(sp);
      await store.write(child, const UltimateEnergy(filledCells: 1, fractionMin: 14));

      expect(
        GuardUltimateEnergyPrefsStore.keyOf(child),
        'guard_ultimate_v1_$child',
      );
      expect(
        GuardUltimateEnergyPrefsStore.creditedKeyOf(child),
        'guard_ultimate_v1_credited_$child',
      );
      // 旧能量的键完全没被写入。
      expect(sp.getKeys().any((String k) => k.startsWith('guard_energy_v1_')),
          isFalse);
      expect(sp.getKeys().any((String k) => k.startsWith('guard_day_state_v2_')),
          isFalse);
    });

    test('不同 childId 相互隔离', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final GuardUltimateEnergyPrefsStore store =
          GuardUltimateEnergyPrefsStore(sp);
      await store.write('kid-A', const UltimateEnergy(filledCells: 2, fractionMin: 0));
      expect((await store.read('kid-B')).filledCells, 0);
    });
  });

  group('SunlightService 落库点 · 可选 writer 注入', () {
    // 用一个极简 Fake writer 记录 creditFocus 调用，验证 settle 确实在
    // saveSession 之后调用它，且 shortAborted 也照常计入（B4）。
    late _RecordingWriter writer;

    setUp(() {
      writer = _RecordingWriter();
    });

    SunlightService makeService({required UltimateFocusWriter? writer}) {
      final _FakeFocus focus = _FakeFocus();
      final SunlightService svc = SunlightService(
        ledger: _FakeLedger(),
        focus: focus,
        ultimateFocusWriter: writer,
      );
      return svc;
    }

    FocusOutcome outcomeOf(double min, FocusStatus status) => FocusOutcome(
          actualFocusMin: min,
          rawSunlight: status == FocusStatus.shortAborted ? 0 : min,
          status: status,
          endReason: status == FocusStatus.shortAborted
              ? FocusEndReason.manual
              : FocusEndReason.timedOut,
          wakeCount: 0,
          strongWakeCount: 0,
        );

    test('writer 缺省 null 时 settle 不报错（旧行为零改动）', () async {
      final SunlightService svc = makeService(writer: null);
      final FocusSettlement r = await svc.settle(
        outcome: outcomeOf(30, FocusStatus.completed),
        start: DateTime(2026, 11, 20, 9, 0),
        end: DateTime(2026, 11, 20, 9, 30),
        plannedMin: 30,
        dailyFocusCap: 120,
      );
      expect(r.sessionId, isNotEmpty);
      expect(r.actualFocusMin, 30.0);
    });

    test('正常专注：settle 在 saveSession 后调用 writer 并传真实分钟', () async {
      final SunlightService svc = makeService(writer: writer);
      await svc.settle(
        outcome: outcomeOf(30, FocusStatus.completed),
        start: DateTime(2026, 11, 20, 9, 0),
        end: DateTime(2026, 11, 20, 9, 30),
        plannedMin: 30,
        dailyFocusCap: 120,
      );
      expect(writer.calls.length, 1);
      expect(writer.calls.first.$1, isNotEmpty, reason: 'sessionId 非空');
      expect(writer.calls.first.$3, 30.0, reason: 'actualFocusMin 透传');
    });

    test('shortAborted（<15min）也照常计入（C4：门槛不适用大招）', () async {
      final SunlightService svc = makeService(writer: writer);
      await svc.settle(
        outcome: outcomeOf(3, FocusStatus.shortAborted),
        start: DateTime(2026, 11, 20, 9, 0),
        end: DateTime(2026, 11, 20, 9, 3),
        plannedMin: 30,
        dailyFocusCap: 120,
      );
      expect(writer.calls.length, 1, reason: '中途退出也调 writer');
      expect(writer.calls.first.$3, 3.0, reason: '中途退出真实分钟照常计入');
    });
  });
}

/// 记录调用参数的 Fake writer。
class _RecordingWriter implements UltimateFocusWriter {
  final List<(String, String, double)> calls = <(String, String, double)>[];

  @override
  Future<bool> creditFocus({
    required String sessionId,
    required String childId,
    required double actualFocusMin,
  }) async {
    calls.add((sessionId, childId, actualFocusMin));
    return true;
  }
}

/// 内存 FocusRepository 桩（只需 saveSession 真实记录，其余返回空）。
class _FakeFocus implements FocusRepository {
  final List<FocusSession> saved = <FocusSession>[];

  @override
  Future<void> saveSession(FocusSession session) async => saved.add(session);

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      List<FocusSession>.unmodifiable(saved);

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

/// 内存 SunlightRepository 桩（账本操作全空实现）。
class _FakeLedger implements SunlightRepository {
  double _balance = 0;

  @override
  Future<double> append(SunlightEntry entry) async {
    _balance += entry.net;
    return _balance;
  }

  @override
  Future<double> balance() async => _balance;

  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];

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
          String refType, String refId, String dayKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;

  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
}
