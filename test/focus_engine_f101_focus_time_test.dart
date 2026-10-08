// F101（玄参 2026-10-08 反馈）回归测试：到时判定切「专注时长」口径。
//
// 缺陷：原到时判定用墙钟（`_sessionElapsed`，含离席窗口），而 `actualFocusMin`
// 只累计 running 秒数。任务行跳转 `planned = task.minFocusMin`，孩子中途任何一次
// 短离席（灭屏 / 离开 < 300s 不打断）都会让到时结束时 `actualFocusMin < minFocusMin`
// → 联动任务被静默判 rejected：不打勾、不发奖励。荣耀平板 release 包（无 debug
// 快进按钮）自然使用必现；小米 debug 包因快进注水时长而掩盖。
//
// 修复：到时判定与 remaining 均改用专注时长口径（`_focusSeconds`）——
// 「计划 15 分钟」= 坐够 15 分钟，离席时间顺延，离席产出停止口径不变。
import 'package:test/test.dart';

import 'package:sunflower_time/domain/services/focus_engine.dart';

void main() {
  test('F101-a：短离席不吞专注进度——离席 2 分钟后继续坐满 15 分钟才到时', () {
    var now = DateTime(2026, 10, 8, 19, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 15),
      clock: () => now,
    );
    e.start(now);

    // 在场专注 10 分钟。
    now = now.add(const Duration(minutes: 10));
    e.tick(now);
    expect(e.actualFocusMin, closeTo(10, 1e-6));

    // 短离席 2 分钟（< 300s 不触发打断）。
    e.onAbsent();
    now = now.add(const Duration(minutes: 2));
    e.tick(now);
    expect(e.actualFocusMin, closeTo(10, 1e-6),
        reason: '离席窗口不计入专注时长（§4.1.5 口径不变）');
    expect(e.remaining, const Duration(minutes: 5),
        reason: 'remaining 用专注时长口径，离席时不缩水');

    // 回来继续坐 5 分钟 → 专注凑满 15 分钟才到时（墙钟此刻是 17 分钟）。
    e.onPresent();
    now = now.add(const Duration(minutes: 5));
    e.tick(now);

    expect(e.isFinished, isTrue, reason: '专注时长凑满计划 → 到时结束');
    expect(e.outcome!.endReason, FocusEndReason.timedOut);
    expect(e.actualFocusMin, closeTo(15, 1e-6),
        reason: '核心断言：actualFocusMin == 计划 15 分钟 ≥ 任务门槛，不再被离席吞掉');
  });

  test('F101-b：旧口径对照——墙钟 15 分到点时若离席过则不结束（修复后行为）', () {
    var now = DateTime(2026, 10, 8, 19, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 15),
      clock: () => now,
    );
    e.start(now);
    now = now.add(const Duration(minutes: 12));
    e.tick(now);
    e.onAbsent();
    now = now.add(const Duration(minutes: 3)); // 墙钟累计 15 分钟整
    e.tick(now);

    expect(e.isFinished, isFalse,
        reason: '墙钟到点但专注只有 12 分钟 → 不得结束（旧口径此处 finish，actual=12 < 门槛）');
    expect(e.actualFocusMin, closeTo(12, 1e-6));
  });

  test('F101-c：暂停窗口同样不吞专注进度（退出确认卡挂起后再坐满）', () {
    var now = DateTime(2026, 10, 8, 19, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 15),
      clock: () => now,
    );
    e.start(now);
    now = now.add(const Duration(minutes: 8));
    e.tick(now);
    e.pause(); // 退出确认卡弹出（挂起 3 分钟）
    now = now.add(const Duration(minutes: 3));
    e.resume(now);
    now = now.add(const Duration(minutes: 7));
    e.tick(now);

    expect(e.isFinished, isTrue);
    expect(e.actualFocusMin, closeTo(15, 1e-6));
  });

  test('F101-d：手动提前结束仍按真实专注结算（不达标 rejected 的既有口径不变）', () {
    var now = DateTime(2026, 10, 8, 19, 0, 0);
    final e = FocusEngine(
      planned: const Duration(minutes: 15),
      clock: () => now,
    );
    e.start(now);
    now = now.add(const Duration(minutes: 7));
    e.tick(now);
    e.stop();

    expect(e.isFinished, isTrue);
    expect(e.outcome!.endReason, FocusEndReason.manual);
    expect(e.actualFocusMin, closeTo(7, 1e-6),
        reason: '没坐够就是没坐够：手动结束 < 门槛的行为不变');
  });
}
