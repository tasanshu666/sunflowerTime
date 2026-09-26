/// 迁移回归测试 v5 → v6（§5 验收证据）：`check_ins` 补 5 列（家长核销流水）。
///
/// 背景（承重经济漏洞，必读）：M4 起「非联动成长项」改为「打卡落 **pending**、
/// 家长核销通过后才发阳光」，`check_ins` 因此新增
/// `status` / `sunlight_gross` / `sunlight_granted` / `resolved_at` / `parent_note`，
/// `schemaVersion` 应为 6。老库（v5）升级后必须满足：
///  ① 5 个新列补齐；
///  ② **历史打卡 `status` 默认 0 = verified（已核销）**——历史行为本就是「打卡即入账」，
///     绝不能升级后突然冒出一堆待核销把家长淹掉（故 `CheckInStatus.verified` 刻意排在 index 0）；
///  ③ 数据不丢（历史行的 `date` / `task_id` 原样保留，新列取默认 / NULL）。
///
/// 关键教训（同 v4→v5）：光升 `schemaVersion` 不够、光加 `_ensureColumn` 也不够，
/// 两者缺一不可；`flutter analyze` 与常规单测都抓不到（5 和 6 都是合法 Dart），
/// 只能靠「拿老库真跑一次迁移」来验。故本测试钉死三件事：
///  ① `AppDatabase.schemaVersion` 为最新（v6 时为 6；v7 植物成长 V2 起为 7）；
///  ② v5 老库升级后 5 列存在、历史行 status==0(verified)、数据不丢、可写读新列；
///  ③ **跨版本跳跃**（v3 直跳 v6）也补得齐（plants 表 + garden_pot_capacity +
///     custom_subject + check_ins 5 列）。
///
/// 注意 DateTime 存储：本工程未开 `storeDateTimesAsText`，drift 默认把 DateTime
/// 存成 **unix 秒（INTEGER）**（见 drift `SqlTypes.storeDateTimesAsText` 默认 false）。
/// 故「老库」DDL 的日期列一律用 `INTEGER`，否则读回历史行会因类型不匹配而失败。
library migration_v5_to_v6_test;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// unix 秒（drift DateTime 默认落库格式）。
int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

/// 历史打卡时间（用于断言「迁移不丢数据」）。
final DateTime _legacyDate = DateTime(2026, 9, 22, 9, 0);
final DateTime _legacyCompleted = DateTime(2026, 9, 22, 9, 5);

/// 按版本特征拼「老库」建表 DDL。
///
/// 四个开关对应各代 schema 的增量，组合即可还原 v3 / v5：
///  · [withPlantsTable] / [withGardenPotCapacity]：M3（v4）新增的植物表与花园容量列；
///  · [withCustomSubject]：M3 修订（v5）新增的自定义科目列；
///  · [withLegacyCheckIn]：预置一条 v5 时代的历史打卡（验证迁移不丢数据 +
///    status 默认 verified；v6 之前 check_ins **无** 5 个新列）。
List<String> _schemaDdl({
  required bool withPlantsTable,
  required bool withGardenPotCapacity,
  required bool withCustomSubject,
  required bool withLegacyCheckIn,
}) {
  return <String>[
    'CREATE TABLE settings ('
        'id INTEGER NOT NULL, '
        'age_tier INTEGER NOT NULL, '
        'night_boundary_hour INTEGER NOT NULL DEFAULT 21, '
        'night_boundary_minute INTEGER NOT NULL DEFAULT 0, '
        'daily_focus_cap INTEGER NOT NULL, '
        'daily_app_cap_minutes INTEGER NOT NULL, '
        'rest_after_sessions INTEGER NOT NULL, '
        'rest_minutes INTEGER NOT NULL, '
        'task_sunlight INTEGER NOT NULL, '
        'monthly_pool_budget INTEGER NOT NULL, '
        'quiet_mode INTEGER NOT NULL DEFAULT 0, '
        'sound_on INTEGER NOT NULL DEFAULT 1, '
        'bgm_on INTEGER NOT NULL DEFAULT 0, '
        'detection_on INTEGER NOT NULL DEFAULT 1, '
        'auto_confirm_single_high INTEGER NOT NULL DEFAULT 130, '
        'auto_confirm_single_low INTEGER NOT NULL DEFAULT 50, '
        'auto_confirm_monthly_pct REAL NOT NULL DEFAULT 0.25, '
        'currency_rate REAL NOT NULL DEFAULT 0.25, '
        'theme_dark INTEGER NOT NULL DEFAULT 1, '
        'autonomous_mode INTEGER NOT NULL DEFAULT 0, '
        '${withGardenPotCapacity ? 'garden_pot_capacity INTEGER NOT NULL DEFAULT 4, ' : ''}'
        'PRIMARY KEY (id));',
    if (withPlantsTable)
      'CREATE TABLE plants ('
          'id TEXT NOT NULL, '
          'species_id TEXT NOT NULL, '
          'pot_index INTEGER NOT NULL, '
          'stage INTEGER NOT NULL, '
          'stage_started_at INTEGER NOT NULL, '
          'growth_progress REAL NOT NULL DEFAULT 0.0, '
          'growth_factor REAL NOT NULL DEFAULT 1.0, '
          'water_used INTEGER NOT NULL DEFAULT 0, '
          'fertilizer_used INTEGER NOT NULL DEFAULT 0, '
          'status INTEGER NOT NULL, '
          'planted_at INTEGER NOT NULL, '
          'last_water_at INTEGER, '
          'wilted_at INTEGER, '
          'dead_at INTEGER, '
          'mood INTEGER NOT NULL DEFAULT 0, '
          'PRIMARY KEY (id));',
    'CREATE TABLE focus_sessions ('
        'id TEXT NOT NULL, '
        'start INTEGER NOT NULL, '
        'end INTEGER, '
        'planned_min INTEGER NOT NULL, '
        'actual_focus_min REAL NOT NULL, '
        'status INTEGER NOT NULL, '
        'sunlight_earned REAL NOT NULL, '
        'created_at INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE sunlight_ledgers ('
        'id TEXT NOT NULL, '
        'ts INTEGER NOT NULL, '
        'type INTEGER NOT NULL, '
        'gross REAL NOT NULL, '
        'net REAL NOT NULL, '
        'balance_after REAL NOT NULL, '
        'ref_type TEXT, '
        'ref_id TEXT, '
        'day_key TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE reward_templates ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'category INTEGER NOT NULL, '
        'base_cost INTEGER NOT NULL DEFAULT 50, '
        'freq_limit INTEGER, '
        'cooldown_rule INTEGER NOT NULL DEFAULT 1, '
        'enabled INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY (id));',
    'CREATE TABLE redemption_requests ('
        'id TEXT NOT NULL, '
        'template_id TEXT NOT NULL, '
        'requested_at INTEGER NOT NULL, '
        'cost INTEGER NOT NULL, '
        'status INTEGER NOT NULL, '
        'auto_approved INTEGER NOT NULL DEFAULT 0, '
        'queue_position INTEGER, '
        'verified_at INTEGER, '
        'parent_note TEXT, '
        'child_id TEXT NOT NULL DEFAULT \'single-child\', '
        'PRIMARY KEY (id));',
    'CREATE TABLE monthly_pools ('
        'month_key TEXT NOT NULL, '
        'budget INTEGER NOT NULL, '
        'used INTEGER NOT NULL DEFAULT 0, '
        'auto_released INTEGER NOT NULL DEFAULT 0, '
        'reset_at INTEGER NOT NULL, '
        'PRIMARY KEY (month_key));',
    // tasks：v5 起含 custom_subject
    'CREATE TABLE tasks ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL, '
        'subject INTEGER NOT NULL, '
        '${withCustomSubject ? 'custom_subject TEXT, ' : ''}'
        'requires_focus INTEGER NOT NULL, '
        'min_focus_min INTEGER NOT NULL DEFAULT 15, '
        'sunlight_reward INTEGER NOT NULL DEFAULT 12, '
        'repeat_rule TEXT, '
        'is_custom INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    // check_ins：v6 之前**无** status / sunlight_gross / sunlight_granted /
    // resolved_at / parent_note 五列。日期列按 drift 默认用 INTEGER（unix 秒）。
    'CREATE TABLE check_ins ('
        'id TEXT NOT NULL, '
        'task_id TEXT NOT NULL, '
        'date INTEGER NOT NULL, '
        'completed_at INTEGER NOT NULL, '
        'session_id TEXT, '
        'is_perfect_day INTEGER NOT NULL, '
        'PRIMARY KEY (id));',
    'CREATE TABLE cooldown_counters ('
        'template_id TEXT NOT NULL, '
        'period INTEGER NOT NULL, '
        'used_count INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (template_id, period));',
    'CREATE TABLE tracking_events ('
        'id TEXT NOT NULL, '
        'name TEXT NOT NULL DEFAULT \'\', '
        'type INTEGER NOT NULL, '
        'ts INTEGER NOT NULL, '
        'payload TEXT NOT NULL, '
        'PRIMARY KEY (id));',
    // 历史打卡：迁移后 status 应为 0(verified)，日期/任务 id 不得被改动。
    if (withLegacyCheckIn)
      'INSERT INTO check_ins (id, task_id, date, completed_at, session_id, '
          'is_perfect_day) '
          'VALUES (\'legacy_checkin\', \'legacy_task\', ${_secs(_legacyDate)}, '
          '${_secs(_legacyCompleted)}, NULL, 0);',
  ];
}

/// 读取某表当前所有列名（PRAGMA table_info）。
Future<Set<String>> _columns(db.AppDatabase database, String table) async {
  final List<QueryRow> rows =
      await database.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toSet();
}

/// 某表是否存在（sqlite_master）。
Future<bool> _tableExists(db.AppDatabase database, String table) async {
  final List<QueryRow> rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';",
      )
      .get();
  return rows.isNotEmpty;
}

/// 手工构造「老库」并让 AppDatabase 触发迁移。
Future<db.AppDatabase> _openMigrated(
  List<String> legacyDdl,
  int userVersion,
) async {
  final NativeDatabase executor = NativeDatabase.memory(
    setup: (rawDb) {
      for (final String sql in legacyDdl) {
        rawDb.execute(sql);
      }
      rawDb.execute('PRAGMA user_version = $userVersion;');
    },
  );

  final db.AppDatabase database = db.AppDatabase(executor);
  // 触发迁移：首次访问数据库会执行 onUpgrade。
  await database.customSelect('SELECT 1').get();
  addTearDown(() => database.close());
  return database;
}

/// v5 线上 schema：有 plants / garden_pot_capacity / custom_subject，
/// check_ins **无** 5 个新列。含一条历史打卡。
List<String> _v5Ddl() => _schemaDdl(
      withPlantsTable: true,
      withGardenPotCapacity: true,
      withCustomSubject: true,
      withLegacyCheckIn: true,
    );

/// v3 线上 schema：无 plants 表、无 garden_pot_capacity、无 custom_subject、
/// check_ins **无** 5 个新列。
List<String> _v3Ddl() => _schemaDdl(
      withPlantsTable: false,
      withGardenPotCapacity: false,
      withCustomSubject: false,
      withLegacyCheckIn: false,
    );

void main() {
  group('迁移 v5->v6：check_ins 补 5 列（家长核销流水）', () {
    test('schemaVersion 必须为最新 7（版本号与建表改动不许脱节）', () async {
      final db.AppDatabase database = await _openMigrated(_v5Ddl(), 5);
      // 这一条是本次改动的直接护栏：版本号若停在 5，onUpgrade 不跑，
      // 下面所有列断言都会红。
      // 注：植物成长 V2（v7，玄参大人 2026-09-22）把版本号从 6 上移到 7
      //（见 test/m3/migration_v6_to_v7_test.dart），本护栏随之跟进。
      expect(database.schemaVersion, 9);
    });

    test('v5 老库迁移后 check_ins 含 5 新列；历史行 status=0(verified)、新列取默认', () async {
      final db.AppDatabase database = await _openMigrated(_v5Ddl(), 5);

      final Set<String> cols = await _columns(database, 'check_ins');
      expect(
        cols,
        containsAll(<String>[
          'status',
          'sunlight_gross',
          'sunlight_granted',
          'resolved_at',
          'parent_note',
        ]),
      );
      // 不误伤既有列
      expect(
        cols,
        containsAll(<String>[
          'id',
          'task_id',
          'date',
          'completed_at',
          'session_id',
          'is_perfect_day',
        ]),
      );

      final db.CheckIn? c =
          await database.taskDao.checkInById('legacy_checkin');
      expect(c, isNotNull);
      expect(c!.taskId, 'legacy_task');
      // 日期可读回（证明 INTEGER 编码与 drift 一致，迁移未破坏既有列）。
      expect(c.date, _legacyDate);
      expect(c.completedAt, _legacyCompleted);
      // 核心：历史打卡默认「已核销」，绝不变成待核销。
      expect(c.status, CheckInStatus.verified.index); // == 0
      expect(c.sunlightGross, 0.0);
      expect(c.sunlightGranted, 0.0);
      expect(c.resolvedAt, isNull);
      expect(c.parentNote, isNull);
    });

    test('迁移后可写入 / 读回核销字段（复现真机报错的验收点）', () async {
      final db.AppDatabase database = await _openMigrated(_v5Ddl(), 5);

      // 旧代码在这步必炸：SqliteException(1) table check_ins has no column
      // named status（真机报错原样复现）。
      final DateTime at = DateTime(2026, 9, 22, 10, 0);
      await database.taskDao.insertCheckIn(
        db.CheckInsCompanion(
          id: const Value('c_pending'),
          taskId: const Value('t1'),
          date: Value(at),
          completedAt: Value(at),
          isPerfectDay: const Value(false),
          status: Value(CheckInStatus.pending.index),
          sunlightGross: const Value(18.0),
          sunlightGranted: const Value(0.0),
        ),
      );

      final db.CheckIn? c = await database.taskDao.checkInById('c_pending');
      expect(c, isNotNull);
      expect(c!.status, CheckInStatus.pending.index);
      expect(c.sunlightGross, 18.0);
      expect(c.sunlightGranted, 0.0);
      expect(c.resolvedAt, isNull);
      expect(c.parentNote, isNull);
    });
  });

  group('迁移 v3->v6：跨三个版本跳跃升级', () {
    test('v3 老库直跳 v6：植物表、花园容量、自定义科目、check_ins 5 列全部补齐', () async {
      // 场景：玄参大人跳过了中间几版安装，库还停在 v3（无 plants 表、无
      // garden_pot_capacity、无 custom_subject、check_ins 无 5 新列），直接升到 v6。
      final db.AppDatabase database = await _openMigrated(_v3Ddl(), 3);

      // ① 表：plants 由 m.createAll() 建出来。
      expect(await _tableExists(database, 'plants'), isTrue);
      // ② 列：settings.garden_pot_capacity（v4）+ tasks.custom_subject（v5）
      //    + check_ins 5 列（v6）。
      expect(await _columns(database, 'settings'),
          contains('garden_pot_capacity'));
      expect(await _columns(database, 'tasks'), contains('custom_subject'));
      expect(
        await _columns(database, 'check_ins'),
        containsAll(<String>[
          'status',
          'sunlight_gross',
          'sunlight_granted',
          'resolved_at',
          'parent_note',
        ]),
      );

      // ③ 端到端：pending 打卡能真正写入并读回（旧代码在缺列时必抛）。
      final DateTime at = DateTime(2026, 9, 22, 11, 0);
      await database.taskDao.insertCheckIn(
        db.CheckInsCompanion(
          id: const Value('c_jump'),
          taskId: const Value('t1'),
          date: Value(at),
          completedAt: Value(at),
          isPerfectDay: const Value(false),
          status: Value(CheckInStatus.pending.index),
          sunlightGross: const Value(12.0),
        ),
      );
      final db.CheckIn? c = await database.taskDao.checkInById('c_jump');
      expect(c, isNotNull);
      expect(c!.status, CheckInStatus.pending.index);
      expect(c.sunlightGross, 12.0);
      expect(c.date, at);
    });
  });
}
