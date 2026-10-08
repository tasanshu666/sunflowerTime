/// 系统提示音（Android ToneGenerator 内置「叮」，专注结束 3s 倒计时用）。
///
/// 玄参 2026-10-08：「3s 倒计时缺提示音，先用系统音填充一声叮」。走系统
/// `ToneGenerator`（非音频素材），后续交付正式「叮」素材后本文件可整体替换。
///
/// 设计要点：
/// - **STREAM_MUSIC** → 跟随媒体音量（专注期勿扰为 PRIORITY 档，媒体照常出声）；
/// - 非 Android 平台（iOS 等）no-op；
/// - fire-and-forget + 全异常静默降级：提示音失败绝不影响专注主流程。
library system_tone;

import 'dart:io';

import 'package:flutter/services.dart';

/// 系统提示音帮手（薄封装，方法通道到原生 `playDing`）。
class SystemTone {
  const SystemTone();

  static const MethodChannel _channel = MethodChannel('sunfocus/tone');

  /// 播一声系统「叮」（TONE_PROP_BEEP，约 150ms）。
  ///
  /// 非 Android 直接 no-op；通道异常（如页面尚未挂好 handler）静默吞掉。
  Future<void> playDing() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('playDing');
    } on PlatformException {
      // 静默降级：提示音失败不影响主流程。
    } on MissingPluginException {
      // 冷启动早期 handler 未就绪：同样静默。
    }
  }
}
