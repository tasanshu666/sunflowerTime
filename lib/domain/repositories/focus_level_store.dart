/// C74 · 「已结算到的最高等级」持久化**抽象**（**纯 Dart**：只 import `dart:`）。
///
/// ## 为什么抽象一层（依赖倒置）
/// `package:shared_preferences` 是 **Flutter 插件**（依赖 `flutter/services`），
/// domain 一旦直接 import 就破了「纯 Dart → 可被 `package:test` 直接单测」的底线。
/// 故在此定义纯 Dart 抽象，由 `data/local/focus_level_prefs_store.dart` 用 SP 实现
/// —— 与 C14 防沉迷（SP + 不升 schemaVersion）同款先例。
///
/// ## 值的语义（🔴 必读）
/// 存的是「**已结算到的最高等级**」（1..8，**只增不减**），**不是**「首用基线」：
/// 它同时承担两个职责（设计 §5.24.3）
///  ① 老用户首用：写入当前等级 ⇒ 下次据此判定「不补发历史等级阳光」；
///  ② 幂等锚点之一：`settledLevel = max(SP 值, 账本已发最大等级)`。
///
/// 从未写过 ⇒ [read] 返回 `null`（等价于 1）。
library focus_level_store;

/// 「已结算到的最高等级」读写抽象。
abstract class FocusLevelSettledStore {
  /// 读已结算到的最高等级；从未写过返回 `null`（等价 Lv.1）。
  Future<int?> read();

  /// 写已结算到的最高等级（实现内部必须**取 max**，保证只增不减）。
  Future<void> write(int settledLevel);

  /// 清除记录（测试 / 「一键删除全部本地数据」用）。
  Future<void> clear();
}
