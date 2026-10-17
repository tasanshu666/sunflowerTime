/// 🐞 **仅 Debug** · 「模拟已解锁」开关（C85）。
///
/// 为什么需要它：付费内容（月 / 年报告、近 4 周稳定性、全年热力图、深度报告）
/// 在真机上只有先买一次才能看到，而 App Store 沙盒购买在自测时非常折腾。
/// 本开关把「已解锁」写进**内存态**，重启 App 即失效（不落库、不写票据），
/// 让设计与测试可以在真机上直接预览买断后的界面。
///
/// ## 三重隔离（release 绝不出现）
///  1. 唯一挂载点 `parent_settings_page.dart` 里由 `if (kDebugMode)` 包裹 →
///     **整段被 tree-shake**，release 包中不存在这个 widget；
///  2. 权益写入收口在 `debugSetPremiumUnlock`（`core/di/providers.dart`）→
///     本文件**零权益标识符**（`test/qa/entitlement_gate_guard_test.dart` 守卫仍紧）；
///  3. 冷启动 `main.dart` 的 `hydrateEntitlement` 会按**真实票据**覆盖内存态 →
///     即便误触，重启即恢复真实状态。
library debug_unlock_switch;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';

/// 「模拟已解锁（仅调试）」开关行（挂在家长设置页底部 Debug 区）。
class DebugUnlockSwitch extends ConsumerWidget {
  const DebugUnlockSwitch({super.key});

  /// 开关标题文案（测试按此文本定位）。
  static const String titleText = '模拟已解锁（仅调试）';

  /// 开关副标题文案（说明作用范围 + 失效条件）。
  static const String subtitleText = '预览月/年报告与热力图；重启 App 后失效';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch 内存态布尔值（而非权益实体）→ 开关控件拿到稳定的 `value`。
    final bool enabled = ref.watch(debugPremiumUnlockProvider);

    return SwitchListTile(
      value: enabled,
      // 🔴 唯一写路径：`debugSetPremiumUnlock` 同时写开关态与权益态。
      onChanged: (bool next) => debugSetPremiumUnlock(ref, next),
      title: const Text(titleText),
      subtitle: const Text(subtitleText),
      secondary: const Icon(Icons.bug_report_outlined),
    );
  }
}
