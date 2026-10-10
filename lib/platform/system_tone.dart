/// [已废弃·无调用方] 系统提示音（Android ToneGenerator 内置「叮」）。
///
/// 玄参 2026-10-08：「3s 倒计时缺提示音，先用系统音填充一声叮」。
/// **同日晚 F100**：正式 5 秒倒计时素材 `5s_countdown.mp3` 交付后，倒计时音效
/// 改走 AudioService 的 `AudioCue.focusEndCountdown`（SFX 通道），本文件自此
/// **全仓库无任何调用方**（原生侧 `playDing` 通道同理闲置），仅保留备查；
/// 下次代码清理可连原生通道一起整体删除。
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
