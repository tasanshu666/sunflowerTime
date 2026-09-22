/// 本地设置仓储（实现 domain 接口，§2.1）。数据来自 Drift settings 表。
library settings_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

class SettingsLocalRepository implements SettingsRepository {
  final AppDatabase _db;

  SettingsLocalRepository(this._db);

  @override
  Future<AppSettings> getSettings() async {
    final row = await _db.settingsDao.getRow();
    if (row == null) {
      // 首启用默认：高年段示例（实际应由首启引导选择，M1 落地）。
      return const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: kDailyFocusCapHigh,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultHigh,
      );
    }
    return AppSettings(
      ageTier: row.ageTier == 0 ? AgeTier.low : AgeTier.high,
      nightBoundaryHour: row.nightBoundaryHour,
      nightBoundaryMinute: row.nightBoundaryMinute,
      dailyFocusCap: row.dailyFocusCap,
      dailyAppCapMinutes: row.dailyAppCapMinutes,
      restAfterSessions: row.restAfterSessions,
      restMinutes: row.restMinutes,
      taskSunlight: row.taskSunlight,
      poolBudget: row.monthlyPoolBudget,
      gardenPotCapacity: row.gardenPotCapacity,
      quietMode: row.quietMode,
      soundOn: row.soundOn,
      bgmOn: row.bgmOn,
      detectionOn: row.detectionOn,
      autoConfirmSingleHigh: row.autoConfirmSingleHigh,
      autoConfirmSingleLow: row.autoConfirmSingleLow,
      autoConfirmMonthlyPct: row.autoConfirmMonthlyPct,
      currencyRate: row.currencyRate,
      themeDark: row.themeDark,
      autonomousMode: row.autonomousMode,
    );
  }

  @override
  Future<void> saveSettings(AppSettings s) async {
    await _db.settingsDao.upsert(
      SettingsCompanion(
        id: const Value(1),
        ageTier: Value(s.ageTier == AgeTier.low ? 0 : 1),
        nightBoundaryHour: Value(s.nightBoundaryHour),
        nightBoundaryMinute: Value(s.nightBoundaryMinute),
        dailyFocusCap: Value(s.dailyFocusCap),
        dailyAppCapMinutes: Value(s.dailyAppCapMinutes),
        restAfterSessions: Value(s.restAfterSessions),
        restMinutes: Value(s.restMinutes),
        taskSunlight: Value(s.taskSunlight),
        monthlyPoolBudget: Value(s.poolBudget),
        gardenPotCapacity: Value(s.gardenPotCapacity),
        quietMode: Value(s.quietMode),
        soundOn: Value(s.soundOn),
        bgmOn: Value(s.bgmOn),
        detectionOn: Value(s.detectionOn),
        autoConfirmSingleHigh: Value(s.autoConfirmSingleHigh),
        autoConfirmSingleLow: Value(s.autoConfirmSingleLow),
        autoConfirmMonthlyPct: Value(s.autoConfirmMonthlyPct),
        currencyRate: Value(s.currencyRate),
        themeDark: Value(s.themeDark),
        autonomousMode: Value(s.autonomousMode),
      ),
    );
  }
}
