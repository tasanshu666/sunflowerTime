// QA 缺陷复现（M1 批次一 · T06 FocusEngine）—— 红测，作为缺陷证据保留。
//
// 缺陷：`onAbsent()` / `onPresent()` **不更新** `_lastTick`，与 `pause()/resume()`
// 的处理不对称（`resume()` 会重置 `_lastTick`）。若驱动方的 ticker 在离席期间被系统
// 挂起（灭屏休眠 / Doze），恢复后的首次 `tick()` 会把**整段离席时长**当作
// running 态吞入 `_focusSeconds`，导致：
//   ① 实际专注分钟被离席时长注水 → 可能误越过 ≥5 分钟门槛（PRD §6.2 防作弊失守）；
//   ② `SunlightService.settle()` 以 `actualFocusMin` 计算 S → **为离席时间发阳光**；
//   ③ 离席 300s 的「打断」因期间无 tick 而**被跳过**（onPresent 已把 state 翻回 running，
//      恢复首帧 tick 不再进入 `_checkWake`）。
//
// 触发条件：ticker 在离席窗口内未触发（本机为纯逻辑复现，真机触发与否取决于 ROM
// 是否冻结进程——本机无法验证，故严重级暂定 P1「应修」）。
import 'package:test/test.dart';

import 'package:sunflower_time/domain/services/focus_engine.dart';

void main() {
  test('P1-a：离席期间无 tick → 恢复首帧 tick 吞掉整段离席时长（实际专注被注水）', () {
    var now = DateTime(2026, 9, 15, 9, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 20),
      clock: () => now,
    );
    e.start(now);
    now = now.add(const Duration(seconds: 10));
    e.tick(now); // 在场 10s，_lastTick = T+10
    e.onAbsent(); // 灭屏 → 离席
    now = now.add(const Duration(seconds: 60)); // 离席 60s，期间无 tick
    e.onPresent(now); // 亮屏 → 恢复
    now = now.add(const Duration(seconds: 1));
    e.tick(now); // 恢复后首帧 tick

    // 期望：实际专注 = 10s(在场) + 1s(回满窗口) ≈ 11s。
    // 现状：被吞入 61s，actualFocusMin = 71/60 ≈ 1.183 → 本断言会 FAIL。
    expect(e.actualFocusMin, closeTo(11 / 60, 1e-3));
  });

  test('P1-b：离席满 300s 但期间无 tick → 恢复后不再打断（离席计时丢失）', () {
    var now = DateTime(2026, 9, 15, 9, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 30),
      clock: () => now,
    );
    e.start(now);
    now = now.add(const Duration(seconds: 10));
    e.tick(now);
    e.onAbsent();
    now = now.add(const Duration(seconds: 300)); // 离席满 5 分钟，无 tick
    e.onPresent(now); // 恢复
    now = now.add(const Duration(seconds: 1));
    e.tick(now);

    // 期望：离席 300s 触发打断结束；现状：未结束（onPresent 已翻回 running）→ FAIL。
    expect(e.isFinished, isTrue,
        reason: '离席累计 300s 应打断，不该因 ticker 暂停而丢失');
  });
}
