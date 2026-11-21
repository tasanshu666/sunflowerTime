/// 大招能量服务（纯 Dart）：read / credit / spend + 串行闸门 + sessionId 幂等。
///
/// 🔴 与旧 `GuardService._creditAndReadEnergy` **独立一套**：独立 store、独立
/// `creditedSessionIds`、独立串行队列，绝不混写旧集合（口径 1 / C3 / 架构 §8-S6）。
/// 本服务自身不读权益、不读 dayKey、不做 15min 有效门槛 —— 那些是旧入场券口径
/// （C4），大招按累计在场分钟（B4）。
library guard_ultimate_service;

import 'dart:async';

import 'package:sunflower_time/domain/entities/guard_ultimate_energy.dart';
import 'package:sunflower_time/domain/repositories/guard_ultimate_energy_store.dart';

/// 大招能量服务，同时实现 [UltimateFocusWriter] 供 `SunlightService` 可选注入。
class GuardUltimateService implements UltimateFocusWriter {
  GuardUltimateService({
    required GuardUltimateEnergyStore store,
    required String Function() childId,
  })  : _store = store,
        _childId = childId;

  final GuardUltimateEnergyStore _store;
  final String Function() _childId;

  /// 能量变更广播（credit / spend 后发射），供 UI 即时刷新（P0-03②）。
  final StreamController<UltimateEnergy> _changes =
      StreamController<UltimateEnergy>.broadcast();

  /// 监听能量变更；订阅时先发一次当前状态（异步读），之后每次变更都发。
  Stream<UltimateEnergy> watchEnergy() async* {
    yield await read();
    yield* _changes.stream;
  }

  /// 释放资源（provider 生命周期结束时可选调用）。
  void dispose() {
    _changes.close();
  }

  /// 串行闸门尾（所有写操作排队，杜绝并发 read→write 丢更新）。
  Future<void> _tail = Future<void>.value();

  /// 把 [action] 挂到串行队列末尾，返回其结果；前一个失败也不阻断后一个。
  Future<T> _serialized<T>(Future<T> Function() action) {
    final Future<T> result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) => null,
      onError: (Object _) => null,
    );
    return result;
  }

  /// 读当前孩子的大招能量（走串行闸门，与写操作同序）。
  Future<UltimateEnergy> read() =>
      _serialized<UltimateEnergy>(() => _store.read(_childId()));

  /// 累计落库唯一入口；幂等键 = [sessionId]。
  ///
  /// read → 查重 → credit → write（状态 + ids 同批写）。中途退出照常计入
  /// （不看 status、不设 15min 门槛）；跨天不读 dayKey / 不 expire。
  @override
  Future<bool> creditFocus({
    required String sessionId,
    required String childId,
    required double actualFocusMin,
  }) {
    return _serialized<bool>(() async {
      final Set<String> ids =
          Set<String>.from(await _store.readCreditedSessionIds(childId));
      if (ids.contains(sessionId)) return false; // 幂等命中
      final UltimateEnergy current = await _store.read(childId);
      final UltimateEnergy next = credit(current, actualFocusMin);
      ids.add(sessionId);
      // 状态与去重集合同批写：即便中途失败，最坏是重入一次被 ids 挡下。
      await _store.write(childId, next);
      await _store.writeCreditedSessionIds(childId, ids);
      _emit(next);
      return true;
    });
  }

  /// 释放扣 1 格（只扣整格，`fractionMin` 不动）；0 格时 no-op。
  Future<UltimateEnergy> spendCell() {
    return _serialized<UltimateEnergy>(() async {
      final String childId = _childId();
      final UltimateEnergy current = await _store.read(childId);
      final UltimateEnergy next = spend(current);
      if (next != current) {
        await _store.write(childId, next);
        _emit(next);
      }
      return next;
    });
  }

  /// 🔴 调试专用：给当前孩子的大招能量**加 1 格**（钳到 [UltimateEnergy.maxCells]）。
  ///
  /// 只改三个数字中的两个：`filledCells +1`、`fractionMin` 清零；
  /// `totalFocusMin` 保留、`creditedSessionIds` 一个不动（不制造假专注会话）。
  /// 与 [spendCell] 同一套串行闸门 / read→write→emit 纪律 ⇒ 能量条当帧刷新，
  /// 且与真实 credit / spend 不会丢更新。满格时 no-op（不写、不广播）。
  ///
  /// **仅 debug 使用**：领域层零 Flutter（不能 import `kDebugMode`），这里用纯 Dart
  /// 的 `dart.vm.product` 断言兜底；表现层按钮入口另有 `assert(kDebugMode)`。
  /// 生产路径（含 release 构建）不得调用。
  Future<UltimateEnergy> grantCellForDebug() {
    assert(
      !const bool.fromEnvironment('dart.vm.product'),
      'grantCellForDebug is debug-only (no release caller)',
    );
    return _serialized<UltimateEnergy>(() async {
      final String childId = _childId();
      final UltimateEnergy current = await _store.read(childId);
      if (current.filledCells >= UltimateEnergy.maxCells) return current;
      final UltimateEnergy next = UltimateEnergy(
        filledCells: current.filledCells + 1,
        fractionMin: 0,
        totalFocusMin: current.totalFocusMin,
      );
      await _store.write(childId, next);
      _emit(next);
      return next;
    });
  }

  void _emit(UltimateEnergy energy) {
    if (!_changes.isClosed) _changes.add(energy);
  }
}
