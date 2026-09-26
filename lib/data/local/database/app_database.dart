/// Drift + SQLCipher 数据库入口（§3 / §10.4 C13 加密存储义务）。
///
/// opener 用 SQLCipher 打开本地库并设密钥（PRAGMA key）。MVP 口令来自
/// `app_constants.kDatabasePassphrase`（骨架阶段固定；生产应改为设备级密钥派生
/// + flutter_secure_storage 保管，见 T03 风险项）。
library app_database;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

import 'daos.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Settings,
    Plants,
    FocusSessions,
    SunlightLedgers,
    RewardTemplates,
    RedemptionRequests,
    MonthlyPools,
    Tasks,
    CheckIns,
    CooldownCounters,
    TrackingEvents,
  ],
  daos: [
    SettingsDao,
    PlantDao,
    TaskDao,
    SunlightLedgerDao,
    RewardTemplateDao,
    RedemptionRequestDao,
    MonthlyPoolDao,
    CooldownCounterDao,
    TrackingEventDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openEncryptedDb());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          // ① 幂等补齐所有表（CREATE TABLE IF NOT EXISTS，防御性对齐）。
          //    玄参大人真机库由 v1 升级而来，可能停留在 v2（缺列），此处先把
          //    所有表对齐到当前 schema，避免后续 addColumn/alterTable 因缺表报错。
          await m.createAll();

          // ② 幂等补齐 M2 期间新增的列（老库可能因历史迁移遗漏而缺列）。
          //    玄参大人现网库已是 v2，只有 from < 3 的新分支才会真正执行修复，
          //    光改 from < 2 分支救不了现网库。
          await _ensureColumn(m, rewardTemplates, rewardTemplates.baseCost);
          await _ensureColumn(m, rewardTemplates, rewardTemplates.cooldownRule);
          await _ensureColumn(
              m, redemptionRequests, redemptionRequests.childId);
          await _ensureColumn(m, trackingEvents, trackingEvents.name);
          // ④ M3 新增：garden_pot_capacity 列（老库从 v3 升级时可能缺此列）。
          await _ensureColumn(
              m, settings, settings.gardenPotCapacity);
          // ⑤ M3 修订（v5）：tasks.custom_subject 列（自定义科目名）。
          //    可空 TEXT，老库经 ALTER TABLE ADD COLUMN 补列，历史行取 NULL。
          await _ensureColumn(m, tasks, tasks.customSubject);

          // ⑨ M5（v9）：tasks.category 列（成长项内容分类）+ reward_templates.content_category 列
          //    （奖励内容分类）。均为 IntColumn 带默认值 0（=other）的 ALTER TABLE ADD COLUMN，
          //    历史行取默认值 0 → 读作「其他」，避免历史数据被误判成具体分类。
          //    幂等：_ensureColumn 先查 PRAGMA table_info 再决定是否补列。
          await _ensureColumn(m, tasks, tasks.category);
          await _ensureColumn(m, rewardTemplates, rewardTemplates.contentCategory);

          // ⑥ M4（v6）：check_ins 新增 5 列（家长核销流水）。
          //    status 默认 0 = verified（见 CheckInStatus 注释）：v5 及以前的打卡
          //    本就是「打卡即入账」，升级后必须保持「已核销」，不得变成待核销。
          await _ensureColumn(m, checkIns, checkIns.status);
          await _ensureColumn(m, checkIns, checkIns.sunlightGross);
          await _ensureColumn(m, checkIns, checkIns.sunlightGranted);
          await _ensureColumn(m, checkIns, checkIns.resolvedAt);
          await _ensureColumn(m, checkIns, checkIns.parentNote);

          // ③ 清除 v1 遗留的 base_cost_high / base_cost_low 两列：
          //    它们在 Dart 侧已删除、drift 不再写入，但老库物理列仍是
          //    INTEGER NOT NULL 无默认值，会导致 INSERT 触发
          //    "NOT NULL constraint failed"。用 drift 的表重建（12 步法）对齐当前
          //    schema，移除多余物理列。
          if (await _hasColumn(rewardTemplates.actualTableName, 'base_cost_high') ||
              await _hasColumn(
                  rewardTemplates.actualTableName, 'base_cost_low')) {
            await m.alterTable(TableMigration(rewardTemplates));
          }

          // ④ v1 的 age_tier=1 表示旧语义 high，重编号为新语义 high(2)。
          //    必须保持 from < 2 守卫：v2 库中 age_tier=1 已是新语义 mid，绝不能再改。
          if (from < 2) {
            await customStatement(
              'UPDATE settings SET age_tier = 2 WHERE age_tier = 1;',
            );
          }

          // ⑦ 植物成长 V2（v7）：成长进度算法改为幂等 + 成长数值重规划
          //    （每阶段 240h/480h、浇水 +1%、施肥 +5%）。旧进度是按 24h/阶段、
          //    ⚠️ 上面是 **v7 当时的口径**；施肥增量已于 2026-09-25 调为 **+3%**
          //    （`kPlantFertilizeProgressGain`），只改常量、不涉及本迁移。
          //    且非幂等累加出来的，**无法与新口径对齐**（真机上已表现为进度虚高）。
          //    玄参大人 2026-09-22 在「平滑衔接 / 老植物沿用旧参数 / 全部重置清零」
          //    三选项中明确选 **全部重置清零**。
          //
          //    仅重置 status = growing 的植物：已开花 bloomed / 枯萎中 wilting /
          //    已死亡 dead 的植物保持原样，不被清零。
          //
          //    ⚠️ 本仓未开 `storeDateTimesAsText`，drift 把 DateTime 落库为
          //       **unix 秒 INTEGER**；SQL 里必须写**秒**，写毫秒会算出 1970 年
          //       或让增量少算 1000 倍。
          if (from < 7) {
            final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await customStatement(
              'UPDATE plants SET stage = ${PlantStage.seed.index}, '
              'growth_progress = 0.0, stage_started_at = $nowSec '
              'WHERE status = ${PlantStatus.growing.index};',
            );
          }

          // ⑧ v8（M3 修订，玄参大人 2026-09-23 拍板「花谢循环」玩法）：plants 新增
          //    bloomed_at 列（进入盛开的计时起点，可空）。老库 ALTER TABLE ADD COLUMN
          //    补列，历史行取 NULL（表示「尚未记录花期起点」，首次 tick 自动补计时）。
          await _ensureColumn(m, plants, plants.bloomedAt);
        },
      );

  /// 清空全部业务表（合规删除权 §10.4 C5；供 DataManagementService.clearAll 调用）。
  ///
  /// 仅 DELETE 行、不 DROP 表：删除后 settings 单行由 SettingsLocalRepository
  /// 在下次读取时按需重建默认设置。
  Future<void> deleteEverything() => transaction(() async {
        await delete(settings).go();
        await delete(plants).go();
        await delete(focusSessions).go();
        await delete(sunlightLedgers).go();
        await delete(rewardTemplates).go();
        await delete(redemptionRequests).go();
        await delete(monthlyPools).go();
        await delete(tasks).go();
        await delete(checkIns).go();
        await delete(cooldownCounters).go();
        await delete(trackingEvents).go();
      });

  /// 该表当前是否含某列（PRAGMA table_info）。
  Future<bool> _hasColumn(String tableName, String columnName) async {
    final List<QueryRow> info =
        await customSelect('PRAGMA table_info($tableName);').get();
    return info.any((QueryRow r) => r.read<String>('name') == columnName);
  }

  /// 缺列才补（幂等），避免 "duplicate column name"。
  ///
  /// 语义与 [Migrator.addColumn] 一致：先查 [PRAGMA table_info] 再决定是否补列。
  Future<void> _ensureColumn<T extends Table, D>(
    Migrator m,
    TableInfo<T, D> table,
    GeneratedColumn column,
  ) async {
    if (!await _hasColumn(table.actualTableName, column.name)) {
      await m.addColumn(table, column);
    }
  }
}

/// SQLCipher 加密库打开器（Lazy：首次访问才建连）。
LazyDatabase openEncryptedDb() {
  return LazyDatabase(() async {
    // 注：sqlite3 3.x 已移除 open.overrideFor（改由原生资产 hook 决定加载哪个库）。
    // 本工程在 pubspec.yaml 的 hooks.user_defines 里配置：
    //   sqlite3: { source: system, name_android: sqlcipher }
    // —— Android 加载 sqlcipher_flutter_libs 经 Maven 提供的 libsqlcipher.so（ABI 兼容 sqlite3），
    //    `PRAGMA key` 因此生效；同时避免了从 GitHub 下载预编译库（本机被代理拦截）。
    // 旧 Android 上 SQLCipher 打开兼容处理（sqlcipher_flutter_libs 提供）。
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/$kDatabaseFileName');
    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$kDatabasePassphrase'");
      },
    );
  });
}
