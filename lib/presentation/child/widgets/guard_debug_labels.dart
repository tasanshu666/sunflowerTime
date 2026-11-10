/// 守卫调试 · **模式文案**（表现层，仅 `kDebugMode` 的面板使用）。
///
/// ## 为什么单独一个文件（而不是塞进 `guard_debug_script.dart`）
/// `guard_debug_script.dart` 被 QA 的 i18n 探针（`guard_battle_i18n_probe_test`
/// W3-1）钉了硬门槛：**剥注释后代码零 CJK**，只允许 `assert()` 消息里有中文
/// （开发者向）。而「当前模式 / 已生效」是**面向用户的中文 UI 文案**，放进去
/// 会立刻判红，且确实违反「面向用户的文案必须走 ARB」这条红线。
///
/// ## 为什么文案要抽成函数（而不是面板内联两遍）
/// 面板顶部「当前模式」常显行与按钮「✓ 已生效 → …」回执必须是**同一口径**
/// （两边不一致比没有提示更糟：用户会认为按钮骗人），且行为测试可以只断言
/// 这个纯函数的字面量，不必拼 widget 文案。
///
/// ## 口径（[script] == null ⇒ 跟随真实 seed 派生；非空 ⇒ 显式覆盖）
/// * `当前模式：随机派生（跟随今日 seed）`
/// * `当前模式：强制覆盖 · 3 只 · 全 m1`
/// * `当前模式：强制覆盖 · 3 只 · 混编 m1/m2/m3`
/// * 全员取封顶偷取时追加 ` · 高偷窃 3☀`
library guard_debug_labels;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart';

/// 「当前模式」一行文案（面板常显行与按钮回执共用）。
String debugGuardModeLabel(GuardBattleScript? script) {
  if (script == null) return '当前模式：随机派生（跟随今日 seed）';
  final List<GuardBattleMonsterKind> kinds = script.monsters
      .map((GuardBattleMonsterSpec m) => m.kind)
      .toList(growable: false);
  final Set<GuardBattleMonsterKind> unique = kinds.toSet();
  final bool mixed = unique.length > 1;
  // 全员偷取都取到封顶值 ⇒ 就是「高偷窃战局」按钮造出来的那种（必有怪到门）。
  final bool cappedTheft = script.monsters
      .every((GuardBattleMonsterSpec m) => m.steal >= kGuardStealMax);
  final StringBuffer sb = StringBuffer(
    '当前模式：强制覆盖 · ${script.monsters.length} 只',
  );
  if (mixed) {
    sb.write(' · 混编 ${kinds.map((GuardBattleMonsterKind k) => k.id).join('/')}');
  } else {
    sb.write(' · 全 ${unique.first.id}');
  }
  if (cappedTheft) sb.write(' · 高偷窃 $kGuardStealMax☀');
  return sb.toString();
}
