// 🔴 C90-C（2026-10-18）：原 `autoConfirmSingleHigh/Low` / `autoConfirmMonthlyPct` /
// `currencyRate`（C5 免确认自动放行的设置侧遗留字段）已随自动放行功能删除 ——
// 全仓零业务消费点；settings 表同名历史列保留（默认值冻结为字面量，见 tables.dart）。
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

/// 全局设置（§3.1 settings，单例行）。夜间边界为唯一收口值（§6.1 不变式）。
class AppSettings {
  final AgeTier ageTier;
  final int nightBoundaryHour; // 夜间边界（唯一值 §6.1）
  final int nightBoundaryMinute;
  final int dailyFocusCap; // 每日专注上限（低 60 / 中 90 / 高 120，2026-09-22 拍板）
  final int dailyAppCapMinutes; // 30
  final int restAfterSessions; // 2
  final int restMinutes; // 10
  final int taskSunlight; // 12
  /// 周阳光池预算（🔴 **C90-C 同日二次修订起废弃**：家长手动设额入口已删除，
  /// 实际预算改由**当前孩子年级默认值**派生 —— `kAgeTierParams[tier].poolBudgetDefault`
  /// （低 300 / 中 600 / 高 [kWeeklyPoolBudgetUnlimited] 哨兵 0 不限额），判定
  /// 单点在 `WeeklyPoolService._budgetForCurrentTier`。实体字段与 DB 列保留
  /// （兼容存量库，不做迁移），读写仅为存量兼容映射，**消费链已清零**）。
  final int poolBudget;
  final bool quietMode;
  final bool soundOn;
  final bool bgmOn;
  // 🔴 C79（2026-10-15 玄参拍板）：原 `detectionOn`（在场检测）字段已删除 ——
  //  功能常开（专注页无条件启动 `PresenceDetector`，防挂机核心，逻辑一行不动），
  //  不再有可关的开关；schemaVersion 25 DROP COLUMN。
  final bool themeDark;
  // 🔴 C79（2026-10-15 玄参拍板）：原 `autonomousMode`（自主模式/孩子自助核销）
  //  字段已**彻底删除** —— 全仓排查零业务消费点（自主核销从未实现）；
  //  schemaVersion 25 DROP COLUMN。
  final int gardenPotCapacity; // 花园花盆容量（初始 4 → 解锁 12，§3.1 M3）

  // ── C28 少儿护眼休息（玄参 2026-10-04 拍板，口径裁定表 v1 C28 §4）───────────
  // 三项落 `settings` 表新列（`eye_care_enabled` / `eye_care_interval_min` /
  // `eye_care_skip_allowed`），默认值与合法区间单点收口 `prd_params.dart`。
  // ⚠️ 护眼**时长**（固定 60 秒）**不是**设置项，家长端不设、不可调，见
  // `kEyeCareDurationSeconds`（玄参 2026-10-04 明确砍掉「护眼时长」设置项）。
  /// 护眼提醒总开关（默认开）。
  final bool eyeCareEnabled;
  /// 护眼触发间隔：场内累计注视每满该**分钟**数触发一次（默认 20）。
  final int eyeCareIntervalMin;
  /// 是否允许孩子跳过护眼卡（默认允许；跳过不发奖励）。
  final bool eyeCareSkipAllowed;

  const AppSettings({
    required this.ageTier,
    this.nightBoundaryHour = kNightBoundaryDefaultHour,
    this.nightBoundaryMinute = 0,
    required this.dailyFocusCap,
    required this.dailyAppCapMinutes,
    required this.restAfterSessions,
    required this.restMinutes,
    required this.taskSunlight,
    required this.poolBudget,
    this.quietMode = false,
    this.soundOn = true,
    // 2026-09-29 玄参拍板：花园氛围音默认开启（家长端「背景音乐」可关）。
    this.bgmOn = true,
    this.themeDark = false, // 默认浅色（§4.1.4 明亮向日葵基调）；深色由家长显式开启
    this.gardenPotCapacity = kGardenPotCapacityDefault,
    this.eyeCareEnabled = kEyeCareEnabledDefault,
    this.eyeCareIntervalMin = kEyeCareIntervalMinDefault,
    this.eyeCareSkipAllowed = kEyeCareSkipAllowedDefault,
  });

  /// 不可变副本（M2 入口页持久化音效 / 背景音乐开关时使用）。
  AppSettings copyWith({
    AgeTier? ageTier,
    int? nightBoundaryHour,
    int? nightBoundaryMinute,
    int? dailyFocusCap,
    int? dailyAppCapMinutes,
    int? restAfterSessions,
    int? restMinutes,
    int? taskSunlight,
    int? poolBudget,
    bool? quietMode,
    bool? soundOn,
    bool? bgmOn,
    bool? themeDark,
    int? gardenPotCapacity,
    bool? eyeCareEnabled,
    int? eyeCareIntervalMin,
    bool? eyeCareSkipAllowed,
  }) {
    return AppSettings(
      ageTier: ageTier ?? this.ageTier,
      nightBoundaryHour: nightBoundaryHour ?? this.nightBoundaryHour,
      nightBoundaryMinute: nightBoundaryMinute ?? this.nightBoundaryMinute,
      dailyFocusCap: dailyFocusCap ?? this.dailyFocusCap,
      dailyAppCapMinutes: dailyAppCapMinutes ?? this.dailyAppCapMinutes,
      restAfterSessions: restAfterSessions ?? this.restAfterSessions,
      restMinutes: restMinutes ?? this.restMinutes,
      taskSunlight: taskSunlight ?? this.taskSunlight,
      poolBudget: poolBudget ?? this.poolBudget,
      quietMode: quietMode ?? this.quietMode,
      soundOn: soundOn ?? this.soundOn,
      bgmOn: bgmOn ?? this.bgmOn,
      themeDark: themeDark ?? this.themeDark,
      gardenPotCapacity: gardenPotCapacity ?? this.gardenPotCapacity,
      eyeCareEnabled: eyeCareEnabled ?? this.eyeCareEnabled,
      eyeCareIntervalMin: eyeCareIntervalMin ?? this.eyeCareIntervalMin,
      eyeCareSkipAllowed: eyeCareSkipAllowed ?? this.eyeCareSkipAllowed,
    );
  }
}
