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
  final int monthlyPoolBudget; // 400(高)/160(低)，区间 100–1200
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

  const AppSettings({
    required this.ageTier,
    this.nightBoundaryHour = 21,
    this.nightBoundaryMinute = 0,
    required this.dailyFocusCap,
    required this.dailyAppCapMinutes,
    required this.restAfterSessions,
    required this.restMinutes,
    required this.taskSunlight,
    required this.monthlyPoolBudget,
    this.quietMode = false,
    this.soundOn = true,
    this.bgmOn = false,
    this.detectionOn = true,
    this.autoConfirmSingleHigh = 130,
    this.autoConfirmSingleLow = 50,
    this.autoConfirmMonthlyPct = 0.25,
    this.currencyRate = 0.25,
    this.themeDark = true,
    this.autonomousMode = false,
  });
}
