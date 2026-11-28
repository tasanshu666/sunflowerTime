/// 支付宝 App 支付平台缝（Android-only MethodChannel 门面）。
///
/// 🔴 **iOS 硬隔离**（技术方案 §10.3）：本文件不 import 任何支付宝 SDK 符号，
/// `Platform.isAndroid` 为硬门控——非 Android 直接返回 `unsupported`（收敛为 4000）
/// 或 `false`，**从不触碰 MethodChannel**，也不往 iOS 工程引入任何依赖。
///
/// Kotlin 侧对应 `android/app/src/main/kotlin/com/sunflowertime/app/AlipayPlugin.kt`。
/// 失败安全：任何平台异常 / 通道缺失 / 脏返回都归一化结果对象，绝不裸抛。
library alipay_bridge;

import 'dart:io' show Platform;

import 'package:flutter/services.dart' show MethodChannel, PlatformException;

import 'package:sunflower_time/domain/services/alipay_unlock_controller.dart'
    show AlipayPayBridge, AlipayPayResult;

/// 与 Kotlin `AlipayPlugin.CHANNEL` 严格一致（单点口径，勿改）。
const String kAlipayMethodChannel = 'sunfocus/alipay';

/// `AlipayPayBridge` 的 MethodChannel 实现。
class AlipayBridge implements AlipayPayBridge {
  /// [channel] 可注入以便单测打桩；默认构造**不触平台**。
  AlipayBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kAlipayMethodChannel);

  final MethodChannel _channel;

  /// 真实宿主是否 Android（不采信 `defaultTargetPlatform`，见付费页同款说明）。
  static bool get isAndroidRuntime {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AlipayPayResult> pay(String orderString) async {
    if (!isAndroidRuntime) {
      return const AlipayPayResult(
        resultStatus: '4000',
        memo: 'unsupported platform',
      );
    }
    try {
      final Map<dynamic, dynamic> raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pay',
        <String, dynamic>{'orderString': orderString},
      ) ??
          <dynamic, dynamic>{};
      return AlipayPayResult.fromMap(
        raw.map<String, dynamic>(
          (dynamic key, dynamic value) => MapEntry<String, dynamic>('$key', value),
        ),
      );
    } on PlatformException catch (e) {
      return AlipayPayResult(resultStatus: '4000', memo: e.message);
    } catch (_) {
      return const AlipayPayResult(
        resultStatus: '4000',
        memo: 'alipay channel unavailable',
      );
    }
  }

  @override
  Future<bool> isInstalled() async {
    if (!isAndroidRuntime) return false;
    try {
      return await _channel.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }
}
