/// C74 · 专注等级领域模型（**纯 Dart**：只 import `dart:` 与本仓 `domain/`）。
///
/// 三个实体均为**派生的只读值对象**（不含业务逻辑、不含持久化字段）：
///  · [FocusLevelProgress] —— 今日页徽章渲染用的展示模型（`progressOf` 产出）；
///  · [LevelGrant]         —— 本轮**实际入账**的一条称号阳光；
///  · [FocusLevelSettleResult] —— 一次结算的出参（决定「发不发 / 播不播」）。
///
/// ## 等级（40）与称号（9）**解耦**（C74 §3，全案最核心的设计）
///  · 等级：40 级，门槛见 `kFocusLevelThresholdMinutes`，**Lv.1 门槛 = 60 分钟**
///    → 累计不足 1 小时 ⇒ `level = 0`（**尚未解锁**，无称号）；
///  · 称号：只在 `kFocusLevelTitleLevels`（1/5/10/…/40）解锁，共 9 个；
///    **当前称号 = 已解锁的最高称号节点**（Lv.7 的称号仍是 Lv.5 节点那个称号）。
///
/// 🔴 纪律：本功能**不给任何实体表加 `focus_level` 计数列**（C12：账本即事实源），
/// 等级与已发称号全部由「会话聚合（`FocusStats.totalFocusMinutes`）+ 账本计数」派生。
library focus_level;

/// 徽章渲染用的**纯派生**展示模型（由累计专注分钟算出，零 I/O）。
///
/// 🔴 F144（i18n 补齐）：原 `title` 字段（中文称号文案）已**移出领域层** ——
/// 领域层只留 [level]（纯语义），上屏文案由 UI 经
/// `core/i18n/title_l10n.dart::focusLevelTitleL10n(level, l10n)` 取 ARB。
class FocusLevelProgress {
  const FocusLevelProgress({
    required this.level,
    required this.isLocked,
    required this.isMax,
    required this.progress,
    required this.minutesToNext,
    required this.nextLevel,
  });

  /// 当前等级（`0` = 尚未解锁 Lv.1；已解锁为 1..40）。
  final int level;

  /// 是否尚未解锁（`level == 0`，累计不足 60 分钟）。
  final bool isLocked;

  /// 是否已达最高等级（Lv.40）：徽章走满级视觉、隐藏进度条与进度文案。
  final bool isMax;

  /// **指向下一级**的进度（0.0 ~ 1.0）；满级恒 1.0。
  ///
  /// ⚠️ 不是「到下一个称号」的进度（等级与称号已解耦，见 C74 §3）。
  final double progress;

  /// 距**下一级**还需的分钟数（≥ 0）；满级恒 0。
  final int minutesToNext;

  /// 下一级等级号（满级为 null）。
  final int? nextLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusLevelProgress &&
          other.level == level &&
          other.isLocked == isLocked &&
          other.isMax == isMax &&
          other.progress == progress &&
          other.minutesToNext == minutesToNext &&
          other.nextLevel == nextLevel;

  @override
  int get hashCode => Object.hash(
        level,
        isLocked,
        isMax,
        progress,
        minutesToNext,
        nextLevel,
      );

  @override
  String toString() =>
      // i18n B3 / F144：`toString` 是**调试**输出（永不预上屏），且领域层注释外
      // 零 CJK 是硬门槛（`test/i18n/no_han_in_domain_test`）—— 称号文案不在此列，
      // 上屏文案一律走 `core/i18n/title_l10n.dart`。
      'FocusLevelProgress(Lv.$level, locked=$isLocked, isMax=$isMax, '
      'progress=$progress, minutesToNext=$minutesToNext, nextLevel=$nextLevel)';
}

/// 详情卡「9 个称号全列」的**一行**（纯派生，零 I/O；由 `titleRowsOfLevel` 产出）。
///
/// 9 个称号节点（`kFocusLevelTitleLevels`）**全部列出**：已解锁/未解锁由累计分钟
/// 派生，[isCurrent] 指的是「**当前称号 = 已解锁的最高称号节点**」（C74 §3，如
/// Lv.7 的当前节点仍是 Lv.5）—— 详情卡据此高亮（高亮底 + w800 加粗，C81 ⑤）。
///
/// 🔴 F144：本实体**不携带文案**（只有 [level]）；逐行称号由 UI 经
/// `core/i18n/title_l10n.dart::focusLevelTitleRowL10n(row.level, l10n)` 取。
class FocusLevelTitleRow {
  const FocusLevelTitleRow({
    required this.level,
    required this.unlocked,
    required this.isCurrent,
  });

  /// 称号节点等级（1/5/10/15/20/25/30/35/40）。
  final int level;

  /// 该节点是否已解锁（`当前等级 >= 本节点`）。
  final bool unlocked;

  /// 是否为「当前称号」（= 已解锁的**最高**称号节点；未解锁任何称号时全表 false）。
  final bool isCurrent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusLevelTitleRow &&
          other.level == level &&
          other.unlocked == unlocked &&
          other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(level, unlocked, isCurrent);

  @override
  String toString() =>
      'FocusLevelTitleRow(Lv.$level, unlocked=$unlocked, isCurrent=$isCurrent)';
}

/// 本轮结算命中的**一条称号节点**（按等级升序，供演出展示与对账）。
///
/// ⚠️ **v2.0（C78）起 [amount] 恒 0**（经济层删除：称号节点零阳光、零账本行）；
/// 字段保留防构造点/夹具连锁，演出判定只看 `granted` 是否非空。
class LevelGrant {
  const LevelGrant({required this.level, required this.amount});

  /// 节点对应的**称号等级**（1/5/10/15/20/25/30/35/40）。
  final int level;

  /// 该称号节点的阳光金额（**v2.0 起恒 0**，见上）；构造点仍要求显式传 0。
  final int amount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelGrant && other.level == level && other.amount == amount;

  @override
  int get hashCode => Object.hash(level, amount);

  @override
  String toString() => 'LevelGrant(Lv.$level, +$amount)';
}

/// 一次升级结算的**完整出参**（由 `FocusLevelService.settle` 返回）。
///
/// 调用方据此决定后续动作（🔑 **C74 §6 修订二**：每次升级都播演出；
/// **C78 后称号节点也不发阳光** —— 故「是否升级」与「是否解锁称号」仍是两个
/// **独立**判定）：
///  · `granted.isNotEmpty` ⇒ **称号节点**：播 `5leveUp` 演出（零阳光、零账本行）；
///  · `granted.isEmpty && leveledUp` ⇒ **普通升级**：播 `defaultLevelUp` 演出；
///  · `!leveledUp` ⇒ 没升级（快路径 / 首用静默）⇒ 什么都不播；
///  · `firstUseSilent == true` ⇒ 老用户首用，**静默**（已写 SP，不播演出）。
class FocusLevelSettleResult {
  const FocusLevelSettleResult({
    required this.currentLevel,
    required this.settledLevel,
    required this.settledBefore,
    required this.granted,
    required this.totalSunlight,
    required this.firstUseSilent,
  });

  /// 由累计专注分钟算出的当前等级（0..40）。
  final int currentLevel;

  /// 本轮结算后「已结算到的最高等级」（= 双锚点取大 + 本轮推进后的值）。
  final int settledLevel;

  /// 本轮**开始前**「已结算到的最高等级」（= 双锚点取大的结果，未含本轮推进）。
  ///
  /// 🔑 结算后 `settledLevel` 会被推进到 `currentLevel`，光看它**无法**判断
  /// 「本轮到底升没升级」—— 必须留一份推进前的值（C74 §6 修订二要求普通升级
  /// 也播演出，判定正是 `currentLevel > settledBefore`）。
  final int settledBefore;

  /// 本轮**实际写账成功**的称号节点清单（升序）；为空 = 无需演出。
  final List<LevelGrant> granted;

  /// 本轮合计发放阳光（**v2.0（C78）起恒 0**：称号节点零阳光、零账本行；
  /// 演出卡阳光行因既有条件 `totalSunlight > 0` 自动隐藏）。
  final int totalSunlight;

  /// 是否命中「老用户首用静默」分支（写已结算等级、不补发、不播演出）。
  final bool firstUseSilent;

  /// 本轮解锁了几个称号节点（0 = 非称号升级；跨多级时 > 1）。
  int get titlesGained => granted.length;

  /// 本轮**是否升过级**（`currentLevel` 超过了结算前的锚点）。
  ///
  /// 🔴 判定刻意**不看** [granted] —— 31 次普通升级 `granted` 为空但**确实升级了**
  /// （C74 §6 修订二：这类也要播演出）。首用静默不算「升级」（用户没看到等级变化）。
  // `settledBefore >= 0`，故 `currentLevel > settledBefore` 已蕴含「已解锁（≥1）」，
  // 无需再判 `> 0`。
  bool get leveledUp => !firstUseSilent && currentLevel > settledBefore;

  /// 本轮前进了几个等级（普通升级「连升 N 级！」用；未升级为 0）。
  int get levelsGained =>
      leveledUp ? currentLevel - settledBefore : 0;

  @override
  String toString() =>
      'FocusLevelSettleResult(current=Lv.$currentLevel, settled=Lv.$settledLevel, '
      'settledBefore=Lv.$settledBefore, granted=$granted, total=$totalSunlight, '
      'firstUseSilent=$firstUseSilent)';
}
