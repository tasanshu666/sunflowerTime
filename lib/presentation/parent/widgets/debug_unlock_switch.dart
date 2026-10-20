/// 🐞 **仅 Debug** · 「会员模式」开关（C85 起点 / F142 修复）。
///
/// 为什么需要它：付费内容（月 / 年报告、近 4 周稳定性、全年热力图、深度报告、
/// 花盆扩容到 12 盆、多孩子档案…）在真机上只有先买一次才能看到，而 App Store
/// 沙盒购买在自测时非常折腾。本开关把「会员态」写进**内存态**，重启 App 即失效
/// （不落库、不写票据），让设计与测试可以在真机上直接预览买断后的界面。
///
/// ## F142 修复点：同时覆盖 **UI 门控** 与 **领域层配额判定**
///
/// 权益态有**两个独立内存源**：UI 层读 `entitlementProvider`，领域层读权益服务的
/// 私有内存态（`can()` / `quotaOf()`）。旧版本只写前者 → 真机表现是
/// 「花园扩容按钮亮着，一按就被告知需要升级解锁」（域层仍按免费档 4 盆判定）。
/// 现在 `debugSetPremiumUnlock` 会把两源**同时**写向同一目标态，故开关打开后
/// 扩容、报告、档案等**所有**付费能力（含域层防线）都真的放开。
///
/// ## 三重隔离（release 绝不出现）
///  1. 唯一挂载点 `parent_settings_page.dart` 里由 `shouldShowDebugUi(...)` 包裹 →
///     **整段被 tree-shake**，release 包中不存在这个 widget；
///  2. 权益写入收口在 `debugSetPremiumUnlock`（`core/di/providers.dart`）→
///     本文件**零权益标识符**（`test/qa/entitlement_gate_guard_test.dart` 守卫仍紧）；
///  3. 冷启动 `main.dart` 的 `hydrateEntitlement` 会按**真实票据**覆盖内存态 →
///     即便误触，重启即恢复真实状态。
library debug_unlock_switch;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';

/// 「会员模式（仅调试）」开关行（挂在家长设置页底部 Debug 区）。
class DebugUnlockSwitch extends ConsumerWidget {
  const DebugUnlockSwitch({super.key});

  /// 开关标题文案（测试按此文本定位）。
  static const String titleText = '会员模式（仅调试）';

  /// 开关副标题文案（说明作用范围 + 失效条件）。
  static const String subtitleText = '打开即解锁全部付费功能；重启 App 后失效';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch 内存态布尔值（而非权益实体）→ 开关控件拿到稳定的 `value`。
    final bool enabled = ref.watch(debugPremiumUnlockProvider);

    return SwitchListTile(
      value: enabled,
      // 🔴 唯一写路径：`debugSetPremiumUnlock` 同时写开关态、UI 权益态，
      // 以及**领域层**权益服务的内存态（F142：三者必须同向，否则出现
      // 「按钮亮着但域层拒绝」的半写状态）。
      onChanged: (bool next) => debugSetPremiumUnlock(ref, next),
      title: const Text(titleText),
      subtitle: const Text(subtitleText),
      secondary: const Icon(Icons.bug_report_outlined),
    );
  }
}
