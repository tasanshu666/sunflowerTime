/// 方向桥（§1.3）：锁横屏 + 物理方向流。
///
/// 竖屏动作（物理竖屏 OR 手动退出）触发暂停+确认的逻辑在 focus_page 内处理；
/// 此处只负责「锁横屏」与「暴露物理方向流」（已用 useSensor:true 绕过 UI 锁）。
library orientation_bridge;

import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class OrientationBridge {
  /// 锁横屏（打盹屏进入时调用）。
  static Future<void> lockLandscape() =>
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  /// 解除方向锁（退出打盹屏时调用）。
  static Future<void> unlock() =>
      SystemChrome.setPreferredOrientations([]);

  /// 物理方向流（传感器模式，不受 UI 锁影响）。
  static Stream<NativeDeviceOrientation> orientationStream() =>
      NativeDeviceOrientationCommunicator().onOrientationChanged(useSensor: true);
}
