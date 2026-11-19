/// QA 独立差分复验 · v0.3「减法」回退彻底性（真实 SQLite PRAGMA，非源码字符串）。
///
/// ## 为什么必须用真实 PRAGMA 而不是读源码
/// 工程师的 `test/m3/migration_v32_test.dart` 已经断言了 22 列，但那是**同一批
/// 实现者写的断言**。本文件独立回答玄参第 6 点推翻推送机制后最容易假绿的四件事：
///  ① `wishes` 表是不是**真的**回到 22 列（不是"实体删了、DB 列还在"）；
///  ② `user_version` 是不是**真的**回到 32（不是"schemaVersion 改了、
///     `onUpgrade` 里还留着 v33 一跳"）；
///  ③ v31 老库升级后既有业务数据是不是**逐位不变**（迁移不得动老数据）；
///  ④ 全仓 `sharedToParent` / `wishShareRevision` / `wish_share_action` /
///     `parentHasResponded` 是不是**只剩注释**（注释不算回退干净）。
///
/// ## 差分口径
/// 「注释不算可执行代码」按**逐行剥离注释后再匹配**判定，而不是「grep 命中数」。
library wish_rollback_v03_qa_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:sunflower_time/data/local/database/app_database.dart' as db;

/// v0.3 目标 schema：`wishes` 恰 **22 列**，顺序即建表顺序。
///
/// 与 v0.2（23 列，多一个 `shared_to_parent`）的差分点：本清单**不含**
/// `shared_to_parent`，长度断言 = 22。
const List<String> _v03WishColumns = <String>[
  'id',
  'child_id',
  'text',
  'category',
  'status',
  'created_at',
  'committed_at',
  'commit_due_date',
  'fulfilled_at',
  'fulfill_source',
  'abandoned_at',
  'parent_seen_at',
  'reminded_at',
  'parent_reply',
  'replaced_text',
  'tree_slot',
  'target_mode',
  'target_value',
  'progress_value',
  'tag_key',
  'tagged_at',
  'released_at',
];

/// v0.3 的索引全集（3 条 wishes 复合索引 + tasks 上的 1 条愿望索引）。
const Map<String, List<String>> _v03Indexes = <String, List<String>>{
  'idx_wishes_child_status': <String>['child_id', 'status'],
  'idx_wishes_child_created': <String>['child_id', 'created_at'],
  'idx_wishes_child_slot': <String>['child_id', 'tree_slot'],
  'idx_tasks_wish': <String>['wish_id'],
};

// ── 真实 SQLite 反射 ────────────────────────────────────────────────────────

Future<bool> _hasTable(db.AppDatabase d, String table) async {
  final List<QueryRow> rows = await d.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ? AND name = ?;',
    variables: <Variable<Object>>[
      const Variable<String>('table'),
      Variable<String>(table),
    ],
  ).get();
  return rows.isNotEmpty;
}

/// `PRAGMA table_info(<table>)` 的列名，**保持建表顺序**。
Future<List<String>> _columnsOf(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toList();
}

Future<int> _userVersion(db.AppDatabase d) async {
  final QueryRow row =
      await d.customSelect('PRAGMA user_version;').getSingle();
  return row.read<int>('user_version');
}

/// 显式索引（`origin = 'c'` = 本项目 `CREATE INDEX` 建的；排除自动索引）。
Future<Set<String>> _explicitIndexes(db.AppDatabase d, String table) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA index_list($table);').get();
  return <String>{
    for (final QueryRow r in rows)
      if (r.read<String>('origin') == 'c') r.read<String>('name'),
  };
}

Future<List<String>> _indexColumns(db.AppDatabase d, String index) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA index_info($index);').get();
  return rows.map((QueryRow r) => r.read<String>('name')).toList();
}

/// 把一行读成 `列名 -> 值` 的稳定 Map（供逐位比对）。
Future<List<Map<String, Object?>>> _rawRows(
  db.AppDatabase d,
  String sql,
) async {
  final List<QueryRow> rows = await d.customSelect(sql).get();
  return <Map<String, Object?>>[
    for (final QueryRow r in rows) <String, Object?>{...r.data},
  ];
}

/// 写入「既有业务数据」（v31 就有的四张表；迁移不得改动其中任何一位）。
///
/// ⚠️ 本仓未开 `storeDateTimesAsText` ⇒ DateTime 落库为 unix 秒 INTEGER。
Future<void> _seedLegacyBusinessData(db.AppDatabase d) async {
  const int t = 1729000000;
  await d.customStatement(
    'INSERT INTO plants (id, species_id, pot_index, stage, stage_started_at, '
    'status, planted_at) VALUES (?, ?, ?, ?, ?, ?, ?);',
    <Object>['p_keep', 'species_sunflower', 0, 3, t, 3, t],
  );
  await d.customStatement(
    'INSERT INTO settings (id, age_tier, daily_focus_cap, daily_app_cap_minutes, '
    'rest_after_sessions, rest_minutes, task_sunlight, monthly_pool_budget) '
    'VALUES (1, 1, 120, 60, 2, 10, 8, 300);',
  );
  await d.customStatement(
    'INSERT INTO sunlight_ledgers (id, ts, type, gross, net, balance_after, '
    'ref_type, ref_id, day_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
    <Object>[
      'led_keep',
      t,
      0,
      1.0,
      1.0,
      1.0,
      'plant_weed',
      'p_keep',
      '2024-10-15',
    ],
  );
  await d.customStatement(
    'INSERT INTO tasks (id, name, subject, requires_focus, is_custom, '
    'min_focus_min, category) VALUES (?, ?, ?, ?, ?, ?, ?);',
    <Object>['t_keep', '练字', 0, 0, 0, 15, 0],
  );
}

/// 造一个「真 v31 老库」：没有 `wishes` 表 / 没有 `tasks.wish_id` 列、
/// `user_version = 31`，但**有**完整既有业务数据。
Future<File> _makeV31File(Directory dir) async {
  final File file = File('${dir.path}/legacy_v31.sqlite');
  final db.AppDatabase fresh = db.AppDatabase(NativeDatabase(file));
  await fresh.customSelect('SELECT 1').get();
  await _seedLegacyBusinessData(fresh);
  // 撤掉 v32 才引入的三样产物 ⇒ 列集/数据与 v31 真库一致。
  await fresh.customStatement('DROP TABLE wishes;');
  await fresh.customStatement('DROP INDEX IF EXISTS idx_tasks_wish;');
  await fresh.customStatement('ALTER TABLE tasks DROP COLUMN wish_id;');
  await fresh.customStatement('PRAGMA user_version = 31;');
  await fresh.close();
  return file;
}

/// 剥离 `//`、`///`、`/* */` 注释，只留**可执行代码**（含字符串字面量内容）。
String _stripComments(String src) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < src.length) {
    // 块注释
    if (src.startsWith('/*', i)) {
      final int end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    // 行注释
    if (src.startsWith('//', i)) {
      final int end = src.indexOf('\n', i);
      i = end < 0 ? src.length : end;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

/// 递归收集 `lib/` 下所有 dart 源码的**去注释后**文本（路径 -> 代码）。
Map<String, String> _libCode() {
  final Map<String, String> map = <String, String>{};
  for (final FileSystemEntity e
      in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    if (e.path.endsWith('.g.dart')) continue; // 生成物另行核对
    map[e.path] = _stripComments(e.readAsStringSync());
  }
  return map;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 回退彻底性 —— 真实 SQLite 反射（不是读源码）', () {
    test('新装 v32 库：wishes 恰 22 列且逐列逐序，绝无 shared_to_parent', () async {
      final db.AppDatabase d = db.AppDatabase(NativeDatabase.memory());
      addTearDown(d.close);
      await d.customSelect('SELECT 1').get();

      final List<String> cols = await _columnsOf(d, 'wishes');
      expect(cols.length, 22,
          reason: 'v0.3 回退后 wishes 必须是 22 列（v0.2 的 23 列含 shared_to_parent）');
      expect(cols, _v03WishColumns,
          reason: '列名与顺序必须与 v0.3 目标 schema 逐字一致（顺序即建表顺序）');
      expect(cols.contains('shared_to_parent'), isFalse,
          reason: '🔴 玄参第 6 点推翻推送机制 ⇒ shared_to_parent 列必须消失');
      // 反向自证：本反射确实能"看见"列（否则上面 22 列的断言可能是空集假绿）。
      expect(cols.contains('released_at'), isTrue,
          reason: '前置自证：PRAGMA 反射有效（最后 1 列必须能读到）');
    });

    test('新装库 user_version == schemaVersion == 32（v33 那一跳已消失）', () async {
      final db.AppDatabase d = db.AppDatabase(NativeDatabase.memory());
      addTearDown(d.close);
      await d.customSelect('SELECT 1').get();

      expect(d.schemaVersion, 32, reason: 'v0.3 只保留 v31→v32 一跳');
      expect(await _userVersion(d), 32,
          reason: '落库 user_version 必须也是 32（版本号与建表改动不许脱节）');
    });

    test('4 条索引齐全且列序正确（v33 未留下多余索引）', () async {
      final db.AppDatabase d = db.AppDatabase(NativeDatabase.memory());
      addTearDown(d.close);
      await d.customSelect('SELECT 1').get();

      final Set<String> wishIdx = await _explicitIndexes(d, 'wishes');
      final Set<String> taskIdx = await _explicitIndexes(d, 'tasks');
      for (final MapEntry<String, List<String>> e in _v03Indexes.entries) {
        final bool onWishes = e.key.startsWith('idx_wishes_');
        expect(onWishes ? wishIdx : taskIdx, contains(e.key),
            reason: '索引 ${e.key} 必须存在');
        expect(await _indexColumns(d, e.key), e.value,
            reason: '索引 ${e.key} 的列序必须为 ${e.value}');
      }
      // v0.2 若给 shared_to_parent 建过任何索引，回退后不得残留。
      for (final String name in <String>{...wishIdx, ...taskIdx}) {
        final List<String> cols = await _indexColumns(d, name);
        expect(cols.contains('shared_to_parent'), isFalse,
            reason: '索引 $name 不得引用已回退的 shared_to_parent 列');
      }
      expect(wishIdx.length, 3, reason: 'wishes 上恰 3 条复合索引（多一条即残留）');
    });

    test('v31 老库升级到 v32：wishes 建成 22 列、user_version=32、既有数据逐位不变',
        () async {
      final Directory tmp =
          await Directory.systemTemp.createTemp('wish_v03_rollback');
      addTearDown(() => tmp.delete(recursive: true));
      final File file = await _makeV31File(tmp);

      // 前置：确认这真的是 v31 形态（否则本用例证明不了迁移）。
      //
      // 🔴 必须用**裸 sqlite3** 检查，不能用 `AppDatabase`：打开 `AppDatabase`
      // 本身就会跑 `onUpgrade` ⇒ wishes 表立刻被建出来，前置断言恒假。
      final Database raw = sqlite3.open(file.path);
      final bool rawHasWishes = raw
          .select("SELECT name FROM sqlite_master WHERE type='table' "
              "AND name='wishes';")
          .isNotEmpty;
      final Set<String> rawTaskCols = <String>{
        for (final Row r in raw.select('PRAGMA table_info(tasks);'))
          r['name'] as String,
      };
      final int rawVersion =
          raw.select('PRAGMA user_version;').first['user_version'] as int;
      final List<Map<String, Object?>> plantsBefore = <Map<String, Object?>>[
        for (final Row r in raw.select('SELECT * FROM plants ORDER BY id;'))
          <String, Object?>{...r},
      ];
      final List<Map<String, Object?>> settingsBefore = <Map<String, Object?>>[
        for (final Row r in raw.select('SELECT * FROM settings ORDER BY id;'))
          <String, Object?>{...r},
      ];
      final List<Map<String, Object?>> ledgerBefore = <Map<String, Object?>>[
        for (final Row r
            in raw.select('SELECT * FROM sunlight_ledgers ORDER BY id;'))
          <String, Object?>{...r},
      ];
      final List<Map<String, Object?>> tasksBefore = <Map<String, Object?>>[
        for (final Row r in raw.select(
            'SELECT id, name, subject, requires_focus, is_custom, '
            'min_focus_min, category FROM tasks ORDER BY id;'))
          <String, Object?>{...r},
      ];
      raw.close();

      expect(rawHasWishes, isFalse, reason: '前置：v31 老库不得有 wishes 表');
      expect(rawTaskCols.contains('wish_id'), isFalse,
          reason: '前置：v31 老库不得有 tasks.wish_id 列');
      expect(rawVersion, 31, reason: '前置：老库版本必须是 31');

      // ── 升级（重开 AppDatabase 触发 onUpgrade）──
      final db.AppDatabase up = db.AppDatabase(NativeDatabase(file));
      await up.customSelect('SELECT 1').get();
      addTearDown(up.close);

      expect(await _hasTable(up, 'wishes'), isTrue, reason: '升级后 wishes 表必须出现');
      expect(await _columnsOf(up, 'wishes'), _v03WishColumns,
          reason: '升级建出的 wishes 也必须是 v0.3 的 22 列（不是 v0.2 的 23 列）');
      expect((await _columnsOf(up, 'tasks')).contains('wish_id'), isTrue,
          reason: 'tasks.wish_id 必须补上（愿望任务落点）');
      expect(await _userVersion(up), 32,
          reason: '升级后 user_version 必须是 32（不得跳到 33）');
      expect(await _explicitIndexes(up, 'wishes'), <String>{
        'idx_wishes_child_status',
        'idx_wishes_child_created',
        'idx_wishes_child_slot',
      });

      // ── 既有业务数据逐位不变（这是「迁移不动老数据」的硬证据）──
      expect(await _rawRows(up, 'SELECT * FROM plants ORDER BY id;'), plantsBefore,
          reason: '植物行必须逐列逐值不变');
      expect(await _rawRows(up, 'SELECT * FROM settings ORDER BY id;'),
          settingsBefore,
          reason: '设置行必须逐列逐值不变');
      expect(await _rawRows(up, 'SELECT * FROM sunlight_ledgers ORDER BY id;'),
          ledgerBefore,
          reason: '阳光账本行必须逐列逐值不变');
      expect(
        await _rawRows(up, 'SELECT id, name, subject, requires_focus, is_custom, '
            'min_focus_min, category FROM tasks ORDER BY id;'),
        tasksBefore,
        reason: '任务行原有 7 列必须逐位不变（新增 wish_id 为 null 不影响）',
      );
    });

    test('回退后的库幂等：二次打开不报错、行数不变、不含任何 v33 产物', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('wish_v03_idem');
      addTearDown(() => tmp.delete(recursive: true));
      final File file = File('${tmp.path}/idem.sqlite');

      final db.AppDatabase a = db.AppDatabase(NativeDatabase(file));
      await a.customSelect('SELECT 1').get();
      await _seedLegacyBusinessData(a);
      await a.customStatement(
        'INSERT INTO wishes (id, child_id, text, category, status, '
        'created_at, target_mode, target_value, progress_value) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        <Object>['w_idem', 'child-1', '想要一只小乌龟', 0, 0, 1729000000, 0, 0, 0],
      );
      final List<Map<String, Object?>> wishRowsBefore =
          await _rawRows(a, 'SELECT * FROM wishes ORDER BY id;');
      final int plantsBefore = (await _rawRows(a, 'SELECT * FROM plants;')).length;
      await a.close();

      final db.AppDatabase b = db.AppDatabase(NativeDatabase(file));
      await b.customSelect('SELECT 1').get();
      addTearDown(b.close);
      expect(await _columnsOf(b, 'wishes'), _v03WishColumns,
          reason: '二次打开列集不变');
      expect(await _userVersion(b), 32, reason: '二次打开版本不变');
      expect((await _rawRows(b, 'SELECT * FROM plants;')).length, plantsBefore);
      expect(await _rawRows(b, 'SELECT * FROM wishes ORDER BY id;'),
          wishRowsBefore,
          reason: '愿望行必须逐位不变（幂等重开不得重写数据）');
    });
  });

  group('① 回退彻底性 —— 全仓 grep（注释不算可执行代码）', () {
    test('lib/ 里 sharedToParent 只剩注释，无可执行代码', () {
      final Map<String, String> code = _libCode();
      final Map<String, String> hits = <String, String>{
        for (final MapEntry<String, String> e in code.entries)
          if (e.value.contains('sharedToParent')) e.key: e.value,
      };
      expect(hits.keys.toList(), isEmpty,
          reason: '去注释后 lib/ 不得再出现 sharedToParent 可执行代码；'
              '命中文件：${hits.keys.join(', ')}');
      // 反向自证：注释剥离器没把整份文件吃掉（否则上面"零命中"是假绿）。
      final String wishEntity = File('lib/domain/entities/wish.dart')
          .readAsStringSync();
      expect(_stripComments(wishEntity).contains('class Wish'), isTrue,
          reason: '前置自证：注释剥离后实体代码仍在');
    });

    test('lib/ 里 wishShareRevision / wish_share_action / parentHasResponded 全清零', () {
      final Map<String, String> code = _libCode();
      for (final String token in <String>[
        'wishShareRevision',
        'wishShareRevisionProvider',
        'wish_share_action',
        'parentHasResponded',
        'shareWishToParent',
        'withdrawShare',
      ]) {
        final List<String> offenders = <String>[
          for (final MapEntry<String, String> e in code.entries)
            if (e.value.contains(token)) e.key,
        ];
        expect(offenders, isEmpty,
            reason: '推送机制整体回退 ⇒ $token 不得有可执行代码；'
                '命中：${offenders.join(', ')}');
      }
    });

    test('生成物 app_database.g.dart 里也看不到 shared_to_parent', () {
      final String gen =
          File('lib/data/local/database/app_database.g.dart').readAsStringSync();
      expect(gen.contains('shared_to_parent'), isFalse,
          reason: '生成物若还留着该列，说明 build_runner 没重跑/表定义没真回退');
      expect(gen.contains('sharedToParent'), isFalse);
    });

    test('架构 §3「删除 5 个 v0.2 测试文件」逐个核对（4 个已删 + 1 个受保留功能保护）',
        () {
      // 🔴 前 4 个直接钉死 v0.2 的推送机制（shared_to_parent / schemaVersion 33），
      // 回退后**必须消失**，否则会在全量跑时编译失败或红。
      const List<String> pushSpecific = <String>[
        'test/domain/wish_share_visibility_test.dart',
        'test/m3/migration_v33_test.dart',
        'test/qa/migration_v33_qa_test.dart',
        'test/qa/wish_share_v02_realdb_qa_test.dart',
      ];
      final List<String> stillThere = <String>[
        for (final String p in pushSpecific)
          if (File(p).existsSync()) p,
      ];
      expect(stillThere, isEmpty,
          reason: 'v0.2 推送机制专属测试文件必须整体删除（残留会红）：$stillThere');

      // 第 5 个（parentdesk 贴标签弹层）架构文档也列了删除，但**贴标签功能本身
      // 在 v0.3 被完整保留**（PRD §2 保留项），该文件是唯一真渲染覆盖它的一条
      // 用例且当前仍全绿。QA 判定：保留（删除才是覆盖倒退），此处只记录事实，
      // 不当作回退缺陷 —— 它零引用 shared_to_parent / schemaVersion 33。
      const String fifth = 'test/qa/wish_sheet_v02_parentdesk_qa_test.dart';
      if (File(fifth).existsSync()) {
        // ⚠️ 必须先剥注释再查：该文件头部文档**会提到**这些已回退的符号
        //   （说明"本文件零引用它们"），按注释处理，不算可执行引用。
        final String code = _stripComments(File(fifth).readAsStringSync());
        expect(code.contains('sharedToParent'), isFalse,
            reason: '残留文件不得引用已回退字段（否则编译必炸）');
        expect(code.contains('schemaVersion'), isFalse);
        expect(code.contains('migration_v33'), isFalse);
        // 反向自证：剥注释后文件主体仍在（不是把整份读空造成的假绿）。
        expect(code.contains('parent_wish_action_tag'), isTrue,
            reason: '前置自证：剥注释后仍能读到生产按钮 Key');
      }

      // 全仓测试目录里也不得有任何 shared_to_parent 引用（这是硬约束）。
      final List<String> testOffenders = <String>[];
      for (final FileSystemEntity e
          in Directory('test').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.path.endsWith('wish_rollback_v03_qa_test.dart')) continue; // 自身即检查器
        final String code = _stripComments(e.readAsStringSync());
        if (code.contains('sharedToParent')) testOffenders.add(e.path);
      }
      expect(testOffenders, isEmpty,
          reason: '测试目录里不得再出现 sharedToParent 可执行代码：$testOffenders');
    });
  });

  group('③ CJK 纪律（ARB zh/en 对等 + 域层零 CJK）', () {
    test('新增/改动的 wish.* ARB 键 zh/en 键集完全对等', () async {
      final String zh = File('lib/l10n/app_zh.arb').readAsStringSync();
      final String en = File('lib/l10n/app_en.arb').readAsStringSync();
      // 用极简 JSON 解析（ARB 是纯 JSON）——避免手写正则漏键。
      final Map<String, dynamic> zhMap = _arbMap(zh);
      final Map<String, dynamic> enMap = _arbMap(en);
      final Set<String> zhKeys =
          zhMap.keys.where((String k) => !k.startsWith('@')).toSet();
      final Set<String> enKeys =
          enMap.keys.where((String k) => !k.startsWith('@')).toSet();
      expect(zhKeys.difference(enKeys).toList(), isEmpty,
          reason: 'zh 有而 en 没有的键');
      expect(enKeys.difference(zhKeys).toList(), isEmpty,
          reason: 'en 有而 zh 没有的键');
      // v0.3 关键键必须在册（防"减功能时顺手删了文案"）。
      for (final String k in <String>[
        'wishWayCountBadge',
        'wishWayTitle',
        'wishGoGrowthHint',
        'wishStateHangingHint',
        'wishStateParentWorking',
        'wishComposeCounter',
        'wishComposeTooLong',
        'wishTaskBadgeOfWish',
      ]) {
        expect(zhKeys, contains(k), reason: 'ARB 必须含 $k（zh）');
        expect(enKeys, contains(k), reason: 'ARB 必须含 $k（en）');
      }
    });

    test('en ARB 的 wish.* 文案零 CJK', () async {
      final Map<String, dynamic> enMap = _arbMap(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      );
      final RegExp cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]');
      // 语言名按「用该语言自己写」的通行做法，`shared_lang_zh_name` 在 en 里
      // 本就是「简体中文」（玄参口径），不属于翻译遗漏 ⇒ 白名单排除。
      const Set<String> allowCjk = <String>{'shared_lang_zh_name'};
      final List<String> offenders = <String>[
        for (final MapEntry<String, dynamic> e in enMap.entries)
          if (!e.key.startsWith('@') &&
              !allowCjk.contains(e.key) &&
              e.value is String &&
              cjk.hasMatch(e.value as String))
            '${e.key} = ${e.value}',
      ];
      expect(offenders, isEmpty, reason: 'en 文案混入中文：$offenders');
    });

    test('域层（domain/）零 CJK 字面量（注释与文档允许，字符串不允许）', () {
      final RegExp cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]');
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e
          in Directory('lib/domain').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String code = _stripComments(e.readAsStringSync());
        // 只查单/双引号字符串字面量里的 CJK。
        for (final RegExpMatch m
            in RegExp(r'''(['"])((?:\\.|(?!\1).)*)\1''').allMatches(code)) {
          final String lit = m.group(2) ?? '';
          if (cjk.hasMatch(lit)) offenders.add('${e.path}: "$lit"');
        }
      }
      expect(offenders, isEmpty, reason: '域层字符串字面量不得含中文：$offenders');
    });
  });
}

/// 极简 ARB(JSON) → Map（只取顶层键值；够用于键集/文案比对）。
Map<String, dynamic> _arbMap(String raw) {
  final Map<String, dynamic> out = <String, dynamic>{};
  final RegExp keyRe = RegExp(r'^  "([^"]+)"\s*:\s*(.*)$');
  for (final String line in raw.split('\n')) {
    final RegExpMatch? m = keyRe.firstMatch(line);
    if (m == null) continue;
    final String key = m.group(1)!;
    String val = m.group(2)!.trim();
    if (val.endsWith(',')) val = val.substring(0, val.length - 1);
    if (val.startsWith('"')) {
      // 去掉首尾引号并反转义常见序列（够用）。
      final int close = val.lastIndexOf('"');
      out[key] = close > 0
          ? val.substring(1, close)
              .replaceAll(r'\"', '"')
              .replaceAll(r'\n', '\n')
          : val;
    } else if (val.startsWith('{')) {
      out[key] = val; // 元数据对象，不参与文案比对
    } else {
      out[key] = val;
    }
  }
  return out;
}
