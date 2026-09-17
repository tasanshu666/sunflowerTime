/// PresenceDetector 单元测试（M1 批次二 · 修复「竖屏结束卡片灵时不灵」B18）。
///
/// 核心回归：设备「横屏静止」时，`native_device_orientation` 在宽限期后不再回调方向事件，
/// 旧实现依赖宽限期后收到横屏事件才能武装（[_PresenceDetectorState._armed]），静止横屏永远
/// 无法武装 → 转竖屏不弹确认框。本修复在宽限期内记录最近方向 [_PresenceDetectorLastOrientation]，
/// 并在宽限期后由一次性定时器 [_maybeArmAfterGrace] 完成武装，不再依赖后续事件。
///
/// 测试用注入的 [StreamController] 取代真实传感器（生产路径 [_orientationStream] 为 null），
/// 并使用真实时钟 + 真实 `Timer`（plain `test()`，非 FakeAsync）精确等待宽限期与竖屏去抖。
/// 注意：PresenceDetector 的宽限判定基于注入的真实 `DateTime.now()`，与真实 `Timer` 同源，
/// 因此必须「真实等待」而非 FakeAsync 快进，否则宽限判定会失真。
library presence_detector_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import 'package:sunflower_time/domain/services/presence_detector.dart';

void main() {
  // 初始化 Flutter 绑定：PresenceDetector.start/stop 会访问 WidgetsBinding.instance。
  TestWidgetsFlutterBinding.ensureInitialized();

  // 短宽限期（仅用于加速测试；与生产默认 3s 的机制完全一致）。
  const Duration kTestGrace = Duration(milliseconds: 100);
  // 竖屏去抖固定为 kPortraitExitDebounceSeconds = 1.5s，等待时略留余量。
  const Duration kDebounceWait = Duration(milliseconds: 1600);

  group('回归 A（核心）：横屏静止也能武装 → 转竖屏触发 onPortraitIntent', () {
    test('宽限期内观测到横屏且其后静止，转竖屏必须触发', () async {
      final StreamController<NativeDeviceOrientation> controller =
          StreamController<NativeDeviceOrientation>.broadcast();
      int portraitCalls = 0;

      final PresenceDetector detector = PresenceDetector(
        onPortraitIntent: () => portraitCalls++,
        orientationStream: controller.stream,
        grace: kTestGrace,
      );
      detector.start();

      // 宽限期内 emit 一次 landscapeLeft，使 _lastOrientation = landscape（仅记录，宽限期内不武装）。
      controller.add(NativeDeviceOrientation.landscapeLeft);

      // 模拟「静止」：不再发任何事件，真实等待越过宽限期，让 _maybeArmAfterGrace 的
      // 一次性 Timer 触发（真实时钟与真实 Timer 同源）。
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(portraitCalls, 0, reason: '静止横屏期间不应触发，仅完成武装');

      // 用户拿起手机想结束 → 转竖屏。
      controller.add(NativeDeviceOrientation.portraitUp);

      // 等待竖屏去抖定时器（kPortraitExitDebounceSeconds = 1.5s）触发。
      await Future<void>.delayed(kDebounceWait);

      expect(portraitCalls, 1,
          reason: '横屏静止已武装，转竖屏必须触发 onPortraitIntent');
      detector.stop();
      await controller.close();
    });
  });

  group('回归 B：既有行为不被破坏', () {
    test('B1：宽限期内 emit portraitUp 不触发 onPortraitIntent', () async {
      final StreamController<NativeDeviceOrientation> controller =
          StreamController<NativeDeviceOrientation>.broadcast();
      int portraitCalls = 0;

      final PresenceDetector detector = PresenceDetector(
        onPortraitIntent: () => portraitCalls++,
        orientationStream: controller.stream,
        grace: kTestGrace,
      );
      detector.start();

      // 宽限期内竖屏：记录 _lastOrientation=portrait 但宽限期内 early-return，不武装、不计时。
      controller.add(NativeDeviceOrientation.portraitUp);
      await Future<void>.delayed(const Duration(milliseconds: 150)); // 过宽限期
      await Future<void>.delayed(kDebounceWait); // 再等去抖窗口也无需触发

      expect(portraitCalls, 0,
          reason: '宽限期内竖屏且未武装，不应触发 onPortraitIntent');
      detector.stop();
      await controller.close();
    });

    test('B2：横屏事件武装（既有分支）→ 转竖屏仍触发 onPortraitIntent', () async {
      final StreamController<NativeDeviceOrientation> controller =
          StreamController<NativeDeviceOrientation>.broadcast();
      int portraitCalls = 0;

      final PresenceDetector detector = PresenceDetector(
        onPortraitIntent: () => portraitCalls++,
        orientationStream: controller.stream,
        grace: kTestGrace,
      );
      detector.start();

      // 宽限期内先竖屏（记录为 portrait，不武装）。
      controller.add(NativeDeviceOrientation.portraitUp);
      await Future<void>.delayed(const Duration(milliseconds: 150)); // 过宽限期，_maybeArmAfterGrace 不武装

      // 宽限期后横屏 → 走 _onOrientation 横屏分支武装（既有行为）。
      controller.add(NativeDeviceOrientation.landscapeLeft);
      // 再转竖屏。
      controller.add(NativeDeviceOrientation.portraitUp);

      await Future<void>.delayed(kDebounceWait); // 去抖触发

      expect(portraitCalls, 1,
          reason: '横屏事件武装后转竖屏应触发 onPortraitIntent（既有行为不变）');
      detector.stop();
      await controller.close();
    });
  });
}
