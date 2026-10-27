/// 空花盆干扰物 · **多孩子隔离 + 全量清除**（F155-B 收口，玄参 2026-10-27 拍板）。
///
/// ## 为什么单独一份文件
/// `test/m3/migration_v31_test.dart` 只钉「表结构与迁移」、`empty_pot_disturbance_test.dart`
/// 只钉「域算法（内存 Fake）」，两者都不碰**真实仓储 + 真实 AccountService**。
/// 本文件补上最后一环（QA 在第一轮指出的覆盖缺口）：
///  ① 复合主键 `(childId, potIndex)` 在**真实链路**里真的隔离 —— 孩子 A 的盆 0 与
///     孩子 B 的盆 0 各存一行、互不可见（C90 期 2 口径：写入落当前孩子、读取按当前孩子过滤）；
///  ② 数据管理「删除全部本地数据」`AppDatabase.deleteEverything()` 必须把这张**新表**
///     也清空（漏清 = 家长删完数据还残留干扰物，属隐私/一致性缺陷）。
///
/// 脚手架与 `test/c90/child_data_isolation_batch2_test.dart` 同款：
/// 内存 Drift 库 + mock SharedPreferences + 真 Dao / 真仓储 / 真 AccountService，无平台通道。
library empty_pot_child_isolation_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/pot_disturbance_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

final DateTime _today = DateTime(2026, 10, 27);

/// 表行数（真实 SQL 计数，绕开仓储的孩子过滤，用来看「物理上到底几行」）。
Future<int> _rawRowCount(db.AppDatabase d) async =>
    (await d.customSelect('SELECT COUNT(*) AS n FROM empty_pot_disturbances;')
            .getSingle())
        .read<int>('n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 真依赖组装：内存库 + mock SP + 真 AccountService + 真空盆仓储（同一实例跨孩子复用）。
  Future<(AccountService, db.AppDatabase, PotDisturbanceLocalRepository)>
      build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    return (account, database, PotDisturbanceLocalRepository(database, account: account));
  }

  group('① 复合主键 (childId, potIndex) 在真实链路里隔离两个孩子', () {
    test('A 的盆 0 与 B 的盆 0 互不可见；物理上各存一行（共 2 行）', () async {
      final (AccountService account, db.AppDatabase database,
          PotDisturbanceLocalRepository repo) = await build();
      addTearDown(database.close);

      // 孩子 A（默认孩子）：盆 0 长草。
      await repo.save(PotDisturbance(potIndex: 0, weedAt: _today, rollDay: _today));
      expect((await repo.disturbanceOf(0))?.hasWeed, isTrue);
      expect(await _rawRowCount(database), 1);

      // 切到孩子 B：同一盆号读不到 A 的任何东西。
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await repo.disturbances(), isEmpty,
          reason: 'B 不得看到 A 的空盆干扰物（复合主键按孩子隔离）');
      expect(await repo.disturbanceOf(0), isNull);

      // B 自己长虫（同盆号 0）。
      await repo.save(PotDisturbance(potIndex: 0, pestAt: _today, rollDay: _today));
      final PotDisturbance? bRecord = await repo.disturbanceOf(0);
      expect(bRecord?.hasPest, isTrue);
      expect(bRecord?.hasWeed, isFalse, reason: 'B 的盆 0 只有虫，不能被 A 的草串味');
      expect(await _rawRowCount(database), 2,
          reason: '复合主键 (childId, potIndex) → 两个孩子的盆 0 各存一行');

      // 切回 A：看到的仍是自己的草，且 B 的虫不可见。
      await account.switchTo(kChildIdDefault);
      final PotDisturbance? aRecord = await repo.disturbanceOf(0);
      expect(aRecord?.hasWeed, isTrue);
      expect(aRecord?.hasPest, isFalse);

      // B 删自己那盆 → 不影响 A。
      await account.switchTo(second.id);
      await repo.deletePot(0);
      expect(await _rawRowCount(database), 1);
      await account.switchTo(kChildIdDefault);
      expect((await repo.disturbanceOf(0))?.hasWeed, isTrue,
          reason: 'B 删自己的记录不得动到 A 的');
    });

    test('deleteAll() 只清当前孩子（另一个孩子数据保留）', () async {
      final (AccountService account, db.AppDatabase database,
          PotDisturbanceLocalRepository repo) = await build();
      addTearDown(database.close);

      await repo.save(PotDisturbance(potIndex: 0, weedAt: _today));
      await repo.save(PotDisturbance(potIndex: 1, weedAt: _today));
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      await repo.save(PotDisturbance(potIndex: 0, weedAt: _today));
      expect(await _rawRowCount(database), 3);

      await repo.deleteAll();
      expect(await repo.disturbances(), isEmpty);
      expect(await _rawRowCount(database), 2,
          reason: 'deleteAll 只清当前孩子（B 的 1 行被删，A 的 2 行保留）');
    });
  });

  group('② 数据管理「删除全部本地数据」必须覆盖新表', () {
    test('deleteEverything() 后 empty_pot_disturbances 归零（含两个孩子的行）', () async {
      final (AccountService account, db.AppDatabase database,
          PotDisturbanceLocalRepository repo) = await build();
      addTearDown(database.close);

      await repo.save(PotDisturbance(potIndex: 0, weedAt: _today));
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      await repo.save(PotDisturbance(potIndex: 0, pestAt: _today));
      expect(await _rawRowCount(database), 2);

      // 家长端「删除全部本地数据」。
      await database.deleteEverything();
      expect(await _rawRowCount(database), 0,
          reason: '🔴 deleteEverything 漏清新表 = 家长删完数据仍残留干扰物');
      expect(await repo.disturbances(), isEmpty);
    });
  });
}
