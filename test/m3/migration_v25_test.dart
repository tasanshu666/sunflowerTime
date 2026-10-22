/// 迁移回归测试 v24 → v25（**设置页死开关清理 DROP COLUMN**，C79）。
///
/// 背景（玄参 2026-10-15 23:25 拍板）：设置页两个「死开关」清理——
///  · `detection_on`（在场检测）：全仓零消费，专注页 `PresenceDetector` **无条件
///    启动**（功能常开 = 防挂机核心，逻辑一行不动）→ 开关移除 + 列 DROP；
///  · `autonomous_mode`（自主模式 / 孩子自助核销）：全仓**零业务消费点**
///    （自主核销从未实现）→ 开关 / 实体字段 / 列**彻底删除**。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion == 25`；
///  ② v24 旧库（正确列类型建表 + settings 历史行）→ 迁移后**行保留**、
///     `detection_on` / `autonomous_mode` 两列**物理删除**（PRAGMA table_info）；
///  ③ 迁移后其余设置字段值逐位不变（不能因删列丢数据）；
///  ④ 端到端：迁移后 `SettingsLocalRepository` 读回 + 写回 + 再读全链路正常
///     （upsert 不再涉及两列）；
///  ⑤ 幂等：v25 库二次打开不报错、列不再复活。
library migration_v25_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// v24 时期 settings 表 DDL（v21 起无 DDL 变更，v24 与 v23 相同；
/// ⚠️ `detection_on` / `autonomous_mode` 是**历史实有列**，必须保留在老库 DDL 里）。
const String _settingsV24Ddl = 'CREATE TABLE settings ('
    'id INTEGER NOT NULL, age_tier INTEGER NOT NULL, '
    'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
    'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
    'daily_focus_cap INTEGER NOT NULL, daily_app_cap_minutes INTEGER NOT NULL, '
    'rest_after_sessions INTEGER NOT NULL, rest_minutes INTEGER NOT NULL, '
    'task_sunlight INTEGER NOT NULL, monthly_pool_budget INTEGER NOT NULL, '
    'quiet_mode INTEGER NOT NULL DEFAULT 0, sound_on INTEGER NOT NULL DEFAULT 1, '
    'bgm_on INTEGER NOT NULL DEFAULT 1, detection_on INTEGER NOT NULL DEFAULT 1, '
    'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
    'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
    'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
    'currency_rate REAL NOT NULL DEFAULT 0.25, theme_dark INTEGER NOT NULL DEFAULT 0, '
    'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
    'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, '
    'eye_care_enabled INTEGER NOT NULL DEFAULT 1, '
    'eye_care_interval_min INTEGER NOT NULL DEFAULT 20, '
    'eye_care_skip_allowed INTEGER NOT NULL DEFAULT 1, '
    'shovel_refund INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (id));';

/// settings 历史行：两列均为「家长动过」的非默认值（detection_on=0 /
/// autonomous_mode=1），迁移后**其余字段必须逐位保留**。
const String _settingsRowSeed = "INSERT INTO settings ("
    "id, age_tier, night_boundary_hour, night_boundary_minute, "
    "daily_focus_cap, daily_app_cap_minutes, rest_after_sessions, rest_minutes, "
    "task_sunlight, monthly_pool_budget, quiet_mode, sound_on, bgm_on, "
    "detection_on, auto_confirm_single_high, auto_confirm_single_low, "
    "auto_confirm_monthly_pct, currency_rate, theme_dark, autonomous_mode, "
    "garden_pot_capacity, eye_care_enabled, eye_care_interval_min, "
    "eye_care_skip_allowed) VALUES "
    "(1, 2, 22, 30, 90, 45, 3, 15, 12, 200, 1, 0, 1, 0, 130, 50, 0.25, 0.25, "
    "1, 1, 6, 1, 20, 0);";

/// 打开一个「v24 旧库」：settings 建表（v24 列集）+ 历史行 + `user_version = 24`，
/// 打开即触发 v25 迁移（其余表由 onUpgrade 首步 `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV24() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_settingsV24Ddl);
        rawDb.execute(_settingsRowSeed);
        rawDb.execute('PRAGMA user_version = 24;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get();
  return database;
}

/// settings 表中是否仍存在某物理列（PRAGMA table_info）。
Future<bool> _hasColumn(db.AppDatabase d, String column) async {
  final List<QueryRow> info =
      await d.customSelect('PRAGMA table_info(settings);').get();
  return info.any((QueryRow r) => r.read<String>('name') == column);
}

Future<Map<String, Object?>> _settingsRow(db.AppDatabase d) async {
  final List<QueryRow> rows =
      await d.customSelect('SELECT * FROM settings WHERE id = 1;').get();
  return rows.single.data;
}

void main() {
  group('迁移 v24->v25：死开关两列 DROP（C79）', () {
    test('① schemaVersion 必须为最新 25（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV24();
      addTearDown(database.close);
      expect(database.schemaVersion, 30);
    });

    test('② 两列物理删除；settings 历史行保留（其余字段逐位不变）', () async {
      final db.AppDatabase database = await _openV24();
      addTearDown(database.close);

      expect(await _hasColumn(database, 'detection_on'), isFalse,
          reason: 'detection_on 列必须被 DROP（C79）');
      expect(await _hasColumn(database, 'autonomous_mode'), isFalse,
          reason: 'autonomous_mode 列必须被 DROP（C79）');

      final Map<String, Object?> row = await _settingsRow(database);
      expect(row['quiet_mode'], 1, reason: '历史行保留：quiet_mode 不丢');
      expect(row['sound_on'], 0, reason: '历史行保留：sound_on 不丢');
      expect(row['bgm_on'], 1);
      expect(row['theme_dark'], 1);
      expect(row['night_boundary_hour'], 22);
      expect(row['night_boundary_minute'], 30);
      expect(row['daily_focus_cap'], 90);
      expect(row['daily_app_cap_minutes'], 45);
      expect(row['monthly_pool_budget'], 200);
      expect(row['garden_pot_capacity'], 6);
      expect(row['eye_care_skip_allowed'], 0);
      expect(row['eye_care_interval_min'], 20);
    });

    test('③ 端到端：迁移后仓储读回 → copyWith 写回 → 再读，全链路正常', () async {
      final db.AppDatabase database = await _openV24();
      addTearDown(database.close);
      final SettingsLocalRepository repo =
          SettingsLocalRepository(database);

      // 读回：历史行的其余字段经新实体（无 detectionOn / autonomousMode）完整还原。
      final s1 = await repo.getSettings();
      expect(s1.quietMode, isTrue);
      expect(s1.soundOn, isFalse);
      expect(s1.themeDark, isTrue);
      expect(s1.nightBoundaryHour, 22);
      expect(s1.gardenPotCapacity, 6);
      expect(s1.eyeCareSkipAllowed, isFalse);

      // 写回：家长改一个开关（copyWith 不再有两字段）→ upsert 落库。
      await repo.saveSettings(s1.copyWith(bgmOn: false, soundOn: true));

      final s2 = await repo.getSettings();
      expect(s2.bgmOn, isFalse, reason: '写回的 bgmOn 必须生效');
      expect(s2.soundOn, isTrue);
      expect(s2.quietMode, isTrue, reason: '未动字段保持');
      expect(s2.nightBoundaryHour, 22);
    });

    test('④ 幂等：v25 库二次打开不报错、两列不复活、数据稳定', () async {
      final db.AppDatabase database = await _openV24();
      await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
      addTearDown(database.close);

      expect(await _hasColumn(database, 'detection_on'), isFalse);
      expect(await _hasColumn(database, 'autonomous_mode'), isFalse);
      // 二次访问（模拟重启后重开）。
      await database.customSelect('SELECT COUNT(*) FROM settings;').getSingle();
      expect(await _hasColumn(database, 'detection_on'), isFalse);
      expect(await _hasColumn(database, 'autonomous_mode'), isFalse);
      final Map<String, Object?> row = await _settingsRow(database);
      expect(row['quiet_mode'], 1);
    });

    test('⑤ 新装库（v25 直建）settings 无两列，读写正常', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();

      expect(database.schemaVersion, 30);
      expect(await _hasColumn(database, 'detection_on'), isFalse,
          reason: '新 schema 不应再有 detection_on');
      expect(await _hasColumn(database, 'autonomous_mode'), isFalse,
          reason: '新 schema 不应再有 autonomous_mode');

      final SettingsLocalRepository repo = SettingsLocalRepository(database);
      final s = await repo.getSettings(); // 空表 → 默认值
      expect(s.ageTier, AgeTier.high);
      await repo.saveSettings(s.copyWith(themeDark: true));
      expect((await repo.getSettings()).themeDark, isTrue);
    });
  });
}
