/// 专注期系统勿扰（DND）控制器（F01）。
///
/// 通过 `MethodChannel('sunfocus/dnd')` 调用 Android 通知策略接口：
/// - 查询是否已获勿扰授权；
/// - 跳转系统勿扰权限设置页；
/// - 启用/恢复勿扰（专注开始屏蔽通知，结束恢复）。
///
/// 非 Android 平台（iOS 等）全部 no-op，专注主流程不受影响。
library dnd_controller;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 专注期勿扰控制器。
class DndController {
  static const MethodChannel _channel = MethodChannel('sunfocus/dnd');

  /// 是否已获得勿扰策略授权（Android NotificationManager.isNotificationPolicyAccessGranted）。
  ///
  /// 非 Android 直接返回 false。
  Future<bool> isGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? granted =
          await _channel.invokeMethod<bool>('isDndPolicyGranted');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 跳转系统勿扰权限设置页（ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS）。
  ///
  /// 非 Android 直接 no-op。
  Future<void> requestAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openDndSettings');
    } on PlatformException {
      // 跳转失败不影响主流程。
    }
  }

  /// 启用/恢复勿扰：[on]=true → INTERRUPTION_FILTER_NONE（屏蔽通知）；
  /// false → INTERRUPTION_FILTER_ALL（恢复）。
  ///
  /// 原生侧 `setDnd` 不再抛异常，而是返回「实际生效的过滤档位」（-1 表示未生效，
  /// 典型为未授权）。Dart 侧据此 [debugPrint] 自证链路是否打通（B30 诊断用），
  /// 同时 try/catch 兜底通道异常，专注主流程继续。
  /// 非 Android 直接 no-op。
  Future<int> setEnabled(bool on) async {
    if (!Platform.isAndroid) return -2; // 非 Android 标记
    try {
      final int? actual = await _channel.invokeMethod<int>('setDnd', {'enabled': on});
      debugPrint('[DND] setEnabled(on=$on) -> actualFilter=${actual ?? 'n/a'}');
      return actual ?? -1;
    } on PlatformException catch (e) {
      debugPrint('[DND] setEnabled failed: ${e.message}');
      return -1;
    }
  }
}
