/// 迁移回归测试 v28 → v29（**C90-C：child_profiles 加 avatar 列**，玄参 2026-10-18）。
///
/// 背景（C90-C 拍板口径）：「我的」页头像 —— 默认阳光 UI，孩子可改选自己
/// **已种植过**的植物物种当头像；选择结果跟孩子档案存（切孩子各用各的）。
/// `child_profiles` 加 `avatar TEXT NOT NULL DEFAULT 'sun'`
/// （= [kChildAvatarSun]）。简单加列（无主键变更）→ `_ensureColumn` 幂等
/// ALTER TABLE ADD COLUMN，无需表重建，schemaVersion 28 → 29。
///
/// 本测试钉死：
///  ① `AppDatabase.schemaVersion` == 当前最新（v29 起随每次 schema 变更递增）；
///  ② v28 旧库（child_profiles v28 形态 DDL + 历史行）→ 迁移后 avatar 列存在、
///     历史行落默认 `kChildAvatarSun`；
///  ③ 历史行业务字段逐位不变（迁移只补列、不许顺手改数据）；
///  ④ 幂等：二次访问不报错、行数不变；
///  ⑤ 新装库（v29 直建）默认头像 = 阳光；改头像后按孩子各存各的、互不串。
library migration_v29_test;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:test/test.dart';

/// v28 时期 child_profiles 表 DDL（无 avatar 列）。
const String _childProfilesV28Ddl = 'CREATE TABLE "child_profiles" ('
    '"id" TEXT NOT NULL, '
    '"name" TEXT NOT NULL, '
    '"age_tier" INTEGER NOT NULL DEFAULT 2, '
    '"created_at" INTEGER NOT NULL, '
    'PRIMARY KEY ("id"));';

/// 打开一个「v28 旧库」：child_profiles（v28 列集）+ 一条历史行 +
/// `user_version = 28`，打开即触发 v29 加列迁移（其余表由 onUpgrade 首步
/// `m.createAll()` 幂等补齐）。
Future<db.AppDatabase> _openV28() async {
  final db.AppDatabase database = db.AppDatabase(
    NativeDatabase.memory(
      setup: (rawDb) {
        rawDb.execute(_childProfilesV28Ddl);
        // 一条历史行。⚠️ 本仓未开 storeDateTimesAsText，
        // DateTime 落库为 unix 秒 INTEGER。
        rawDb.execute(
          "INSERT INTO child_profiles (id, name, age_tier, created_at) "
          "VALUES ('$kChildIdDefault', '小明', 0, 1729000000);",
        );
        rawDb.execute('PRAGMA user_version = 28;');
      },
    ),
  );
  await database.customSelect('SELECT 1').get(); // 首次访问触发迁移
  return database;
}

Future<bool> _hasColumn(db.AppDatabase d, String table, String column) async {
  final List<QueryRow> rows =
      await d.customSelect('PRAGMA table_info($table);').get();
  return rows.any((QueryRow r) => r.read<String>('name') == column);
}

void main() {
  group('迁移 v28->v29：child_profiles 加 avatar 列（C90-C）', () {
    test('① schemaVersion 必须为最新 29（版本号与迁移改动不许脱节）', () async {
      final db.AppDatabase database = await _openV28();
      addTearDown(database.close);
      expect(database.schemaVersion, 30);
    });

    test('② child_profiles 补出 avatar 列，历史行落默认 kChildAvatarSun', () async {
      final db.AppDatabase database = await _openV28();
      addTearDown(database.close);

      expect(
        await _hasColumn(database, 'child_profiles', 'avatar'),
        isTrue,
        reason: 'v29 必须给 child_profiles 补 avatar 列',
      );
      final Map<String, Object?> row = (await database.customSelect(
              "SELECT * FROM child_profiles WHERE id = '$kChildIdDefault';")
          .getSingle())
      .data;
      expect(row['avatar'], kChildAvatarSun,
          reason: '历史孩子行头像必须默认阳光（老用户升级 UI 无缝）');
    });

    test('③ 历史行可读、业务字段值逐位不变（迁移只补列）', () async {
      final db.AppDatabase database = await _openV28();
      addTearDown(database.close);

      final db.ChildProfileRow? profile =
          await database.childProfileDao.byId(kChildIdDefault);
      expect(profile, isNotNull);
      expect(profile!.name, '小明');
      expect(profile.ageTier, 0);
      // DateTime=unix 秒 INTEGER：1729000000 秒读回不变。
      expect(profile.createdAt.millisecondsSinceEpoch ~/ 1000, 1729000000,
          reason: 'DateTime=unix 秒，迁移不得改写历史时间戳');
    });

    test('④ 幂等：二次访问不报错、行数不变', () async {
      final db.AppDatabase database = await _openV28();
      addTearDown(database.close);

      final int before = (await database
              .customSelect('SELECT COUNT(*) AS n FROM child_profiles;')
              .getSingle())
          .read<int>('n');
      await database.customSelect('SELECT 1').get();
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM child_profiles;')
                .getSingle())
            .read<int>('n'),
        before,
        reason: '二次访问不得重复建列 / 重复拷贝',
      );
      expect(await _hasColumn(database, 'child_profiles', 'avatar'), isTrue);
    });

    test('⑤ 新装库（v29 直建）：默认头像阳光；改头像按孩子各存各的、互不串', () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      expect(database.schemaVersion, 30);

      final ChildProfileLocalRepository repo =
          ChildProfileLocalRepository(database);

      // 新档案不显式传头像 → 落列默认阳光。
      await repo.create('小明', AgeTier.low, id: kChildIdDefault);
      expect((await repo.children()).single.avatar, kChildAvatarSun);

      // 第二个孩子：A 改成植物头像，B 保持阳光 → 各用各的。
      const String childB = 'child_kid_b';
      await repo.create('小红', AgeTier.mid, id: childB);
      await repo.update(kChildIdDefault,
          name: '小明', ageTier: AgeTier.low, avatar: 'sunflower');
      await repo.update(childB, name: '小红', ageTier: AgeTier.mid);

      final Map<String, String> avatarById = <String, String>{
        for (final p in await repo.children()) p.id: p.avatar,
      };
      expect(avatarById[kChildIdDefault], 'sunflower',
          reason: 'A 的植物头像要落库');
      expect(avatarById[childB], kChildAvatarSun,
          reason: 'B 未改过头像，必须保持默认阳光（切孩子各用各的）');

      // 再改回来 → 阳光可回选。
      await repo.update(kChildIdDefault,
          name: '小明', ageTier: AgeTier.low, avatar: kChildAvatarSun);
      expect((await repo.children()).firstWhere((p) => p.id == kChildIdDefault).avatar,
          kChildAvatarSun);
    });
  });
}
