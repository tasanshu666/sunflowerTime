/// 本地设置仓储（实现 domain 接口，§2.1）。数据来自 Drift settings 表。
library settings_local_repository;

import 'package:drift/drift.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';

class SettingsLocalRepository implements SettingsRepository {
  final AppDatabase _db;

  SettingsLocalRepository(this._db);

  @override
  Future<AppSettings> getSettings() async {
    final row = await _db.settingsDao.getRow();
    if (row == null) {
      // 首启用默认：高年段示例（实际应由首启引导选择，M1 落地）。
      // C90-C 同日二次修订：`poolBudget` 字段已废弃（预算改由当前孩子年级
      // 默认值派生），此处仅落不限额哨兵 0 保存量兼容；实际预算判定单点在
      // `WeeklyPoolService._budgetForCurrentTier`。
      return const AppSettings(
        ageTier: AgeTier.high,
        dailyFocusCap: kDailyFocusCapHigh,
        dailyAppCapMinutes: kDailyAppCapMinutes,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kWeeklyPoolBudgetUnlimited,
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
      // C90-C 同日二次修订：`monthlyPoolBudget` 列保留但废弃（预算改由当前
      // 孩子年级默认值派生，消费链清零），此处仅为存量兼容映射。
      poolBudget: row.monthlyPoolBudget,
      gardenPotCapacity: row.gardenPotCapacity,
      quietMode: row.quietMode,
      soundOn: row.soundOn,
      bgmOn: row.bgmOn,
      themeDark: row.themeDark,
      // C79（2026-10-15）：`detectionOn` / `autonomousMode` 已随死开关清理删除
      //  （schemaVersion 25 DROP COLUMN）；旧库两列由迁移幂等删除，读回不再映射。
      // C28：护眼三项（口径裁定表 v1 C28 §4）。老库由 v15 迁移幂等补列并落默认值，
      // 这里直接取列值即可（若列缺失会因 schema 不一致抛错，属必配迁移未跑，不该静默兜底）。
      eyeCareEnabled: row.eyeCareEnabled,
      eyeCareIntervalMin: row.eyeCareIntervalMin,
      eyeCareSkipAllowed: row.eyeCareSkipAllowed,
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
        themeDark: Value(s.themeDark),
        eyeCareEnabled: Value(s.eyeCareEnabled),
        eyeCareIntervalMin: Value(s.eyeCareIntervalMin),
        eyeCareSkipAllowed: Value(s.eyeCareSkipAllowed),
      ),
    );
  }
}
