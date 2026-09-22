import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

/// 全局设置（§3.1 settings，单例行）。夜间边界为唯一收口值（§6.1 不变式）。
class AppSettings {
  final AgeTier ageTier;
  final int nightBoundaryHour; // 夜间边界（唯一值 §6.1）
  final int nightBoundaryMinute;
  final int dailyFocusCap; // 60(高)/90(低)
  final int dailyAppCapMinutes; // 30
  final int restAfterSessions; // 2
  final int restMinutes; // 10
  final int taskSunlight; // 12
  final int poolBudget; // 周阳光池预算（家长可设定，建议值 400，区间 50–1200）
  final bool quietMode;
  final bool soundOn;
  final bool bgmOn;
  final bool detectionOn;
  final int autoConfirmSingleHigh; // 130
  final int autoConfirmSingleLow; // 50
  final double autoConfirmMonthlyPct; // 0.25
  final double currencyRate; // 0.25
  final bool themeDark;
  final bool autonomousMode;
  final int gardenPotCapacity; // 花园花盆容量（初始 4 → 解锁 12，§3.1 M3）

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
    this.bgmOn = false,
    this.detectionOn = true,
    this.autoConfirmSingleHigh = kAutoApproveMaxCostHigh,
    this.autoConfirmSingleLow = kAutoApproveMaxCostLow,
    this.autoConfirmMonthlyPct = kAutoApprovePoolRatio,
    this.currencyRate = kAutoApprovePoolRatio,
    this.themeDark = false, // 默认浅色（§4.1.4 明亮向日葵基调）；深色由家长显式开启
    this.autonomousMode = false,
    this.gardenPotCapacity = kGardenPotCapacityDefault,
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
    bool? detectionOn,
    int? autoConfirmSingleHigh,
    int? autoConfirmSingleLow,
    double? autoConfirmMonthlyPct,
    double? currencyRate,
    bool? themeDark,
    bool? autonomousMode,
    int? gardenPotCapacity,
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
      detectionOn: detectionOn ?? this.detectionOn,
      autoConfirmSingleHigh: autoConfirmSingleHigh ?? this.autoConfirmSingleHigh,
      autoConfirmSingleLow: autoConfirmSingleLow ?? this.autoConfirmSingleLow,
      autoConfirmMonthlyPct: autoConfirmMonthlyPct ?? this.autoConfirmMonthlyPct,
      currencyRate: currencyRate ?? this.currencyRate,
      themeDark: themeDark ?? this.themeDark,
      autonomousMode: autonomousMode ?? this.autonomousMode,
      gardenPotCapacity: gardenPotCapacity ?? this.gardenPotCapacity,
    );
  }
}
