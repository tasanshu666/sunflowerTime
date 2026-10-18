/// C90 期 2 第二批数据隔离回归：四张表（premium_fragments / unlocked_species /
/// monthly_pools / cooldown_counters）按「当前孩子」写入落标 + 读取过滤。
///
/// 口径（玄参 2026-10-17 拍板，schemaVersion 28 表重建）：
///  · 碎片货币 / 图鉴解锁（种植券）/ 周池 / 限领次数全记**当前孩子**名下；
///  · 🔴 仓储接口签名一律不变 —— 过滤在实现内部完成；
///  · 未注入 AccountService 的仓储（既有单测路径）= 恒按 kChildIdDefault，
///    行为与隔离前完全一致（本文件末组钉死）。
///
/// 脚手架参照 `test/c90/child_data_isolation_test.dart`（第一批）：内存 Drift 库 +
/// mock SP + 真 Dao / 真仓储全链路，无平台通道。
library child_data_isolation_batch2_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/weekly_pool_local_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/weekly_pool.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

final DateTime _now = DateTime(2026, 10, 17, 10);

RedemptionRequest _request(String id, String templateId) => RedemptionRequest(
      id: id,
      childId: kChildIdDefault, // 占位：仓储 createRequest 落库时会带行上 childId
      templateId: templateId,
      requestedAt: _now,
      cost: 10,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 真依赖组装：内存 Drift 库 + mock SP + 三个真仓储（全部挂同一 AccountService）。
  Future<(
    AccountService,
    db.AppDatabase,
    PlantLocalRepository,
    RewardLocalRepository,
    WeeklyPoolLocalRepository,
  )> build() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    return (
      account,
      database,
      PlantLocalRepository(database, account: account),
      RewardLocalRepository(database, account: account),
      WeeklyPoolLocalRepository(database, account: account),
    );
  }

  group('C90 期 2 第二批 · premium_fragments 按孩子隔离', () {
    test('碎片余额：孩子 A 写 → 切 B 读不到；各自独立记账', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        PlantLocalRepository bloom,
        _, _,
      ) = await build();
      addTearDown(database.close);

      await bloom.setPremiumFragmentBalance(30);
      expect(await bloom.premiumFragmentBalance(), 30);

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await bloom.premiumFragmentBalance(), 0,
          reason: '另一孩子的碎片余额不计入（B 从 0 起步）');

      await bloom.setPremiumFragmentBalance(8);
      expect(await bloom.premiumFragmentBalance(), 8);

      // 切回默认孩子：自己的余额原样，未被 B 的写入污染。
      await account.switchTo(kChildIdDefault);
      expect(await bloom.premiumFragmentBalance(), 30);
    });
  });

  group('C90 期 2 第二批 · unlocked_species 按孩子隔离', () {
    test('种植券：A 的券 B 看不见也消耗不掉；解锁互不串', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        PlantLocalRepository bloom,
        _, _,
      ) = await build();
      addTearDown(database.close);

      await bloom.unlockSpecies('sp_a');
      expect(await bloom.unlockedSpeciesIds(), <String>{'sp_a'});

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await bloom.unlockedSpeciesIds(), isEmpty,
          reason: '另一孩子的种植券不可见（B 空图鉴起步）');

      await bloom.unlockSpecies('sp_b');
      // A 的券 B 消耗不动（delete 按孩子过滤 → 0 行）。
      await bloom.consumeUnlock('sp_a');
      await account.switchTo(kChildIdDefault);
      expect(await bloom.unlockedSpeciesIds(), <String>{'sp_a'},
          reason: '跨孩子消耗券必须被 childId 过滤挡下');
      expect(await bloom.unlockedSpeciesIds(), isNot(contains('sp_b')));

      // B 自己的券正常消耗。
      await account.switchTo(second.id);
      await bloom.consumeUnlock('sp_b');
      expect(await bloom.unlockedSpeciesIds(), isEmpty);
    });
  });

  group('C90 期 2 第二批 · monthly_pools（周池）按孩子隔离', () {
    test('周池：A 写 → 切 B 读不到；各自独立记账', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _, _,
        WeeklyPoolLocalRepository pools,
      ) = await build();
      addTearDown(database.close);

      await pools.upsert(const WeeklyPool(
        weekKey: '2026-10-12',
        budget: 400,
        used: 50,
      ));
      expect((await pools.get('2026-10-12'))!.used, 50);

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await pools.get('2026-10-12'), isNull,
          reason: '另一孩子的周池不可见（B 新周池起步）');

      await pools.upsert(const WeeklyPool(
        weekKey: '2026-10-12',
        budget: 400,
        used: 20,
      ));
      expect((await pools.get('2026-10-12'))!.used, 20);

      await account.switchTo(kChildIdDefault);
      expect((await pools.get('2026-10-12'))!.used, 50,
          reason: '切回后 A 的周池原样');
    });
  });

  group('C90 期 2 第二批 · cooldown_counters 按孩子隔离', () {
    test('限领次数：A 落单 bump → B 计数 0；各自独立 bump / decrement', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _,
        RewardLocalRepository reward,
        _,
      ) = await build();
      addTearDown(database.close);

      await reward.createRequest(_request('r_a1', 'tpl_x'));
      expect(await reward.cooldownCount('tpl_x', CooldownPeriod.weekly), 1);

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await reward.cooldownCount('tpl_x', CooldownPeriod.weekly), 0,
          reason: '另一孩子的限领次数不计入（B 新账本起步）');

      await reward.createRequest(_request('r_b1', 'tpl_x'));
      await reward.decrementCooldown('tpl_x', CooldownPeriod.weekly);
      expect(await reward.cooldownCount('tpl_x', CooldownPeriod.weekly), 0);

      // 切回 A：自己的计数原样（B 的 bump / decrement 与 A 完全隔离）。
      await account.switchTo(kChildIdDefault);
      expect(await reward.cooldownCount('tpl_x', CooldownPeriod.weekly), 1);
    });
  });

  group('C90 期 2 第二批 · 未注入 AccountService 的仓储（既有单测路径）', () {
    test('行为与隔离前一致：写入落 kChildIdDefault、读取按默认孩子过滤', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final AccountService account = AccountService(
        children: ChildProfileLocalRepository(database),
        settings: SettingsLocalRepository(database),
        prefs: sp,
      );
      await account.initialize();
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      // ⚠️ 不传 account：恒按 kChildIdDefault（Plan B 兼容语义）。
      final PlantLocalRepository bloom = PlantLocalRepository(database);
      final RewardLocalRepository reward = RewardLocalRepository(database);
      final WeeklyPoolLocalRepository pools = WeeklyPoolLocalRepository(database);

      await bloom.setPremiumFragmentBalance(6);
      await reward.createRequest(_request('r_stub', 'tpl_y'));
      await pools.upsert(const WeeklyPool(weekKey: '2026-10-12', budget: 400));

      // 即使 AccountService 当前活跃的是二娃，无 account 的仓储仍按默认孩子走。
      expect(await bloom.premiumFragmentBalance(), 6);
      expect(
        await database.cooldownCounterDao
            .count('tpl_y', CooldownPeriod.weekly, childId: kChildIdDefault),
        1,
      );
      expect(
        await database.cooldownCounterDao
            .count('tpl_y', CooldownPeriod.weekly, childId: second.id),
        0,
      );
      expect((await pools.get('2026-10-12'))!.budget, 400);
    });
  });

  group('C90 期 2 第二批 · 已读通知键按孩子分键', () {
    test('同孩子键稳定、跨孩子键隔离；历史全局键不迁移（不读取）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // 历史全局键（旧版已读状态）：留存但**不再读取**（拍板：不迁移）。
        'acked_verify_ids': <String>['legacy_1'],
      });
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final SettingsStore store = SettingsStore(sp);

      await store.setAcknowledgedVerifyIds(<String>['r1'], childId: 'child_a');
      await store.setAcknowledgedRejectIds(<String>['j1'], childId: 'child_a');

      // 同孩子：读回一致。
      expect(
          await store.acknowledgedVerifyIds(childId: 'child_a'), <String>['r1']);
      expect(await store.acknowledgedRejectIds(childId: 'child_a'), <String>['j1']);

      // 跨孩子：互不可见（新键从空起步）。
      expect(await store.acknowledgedVerifyIds(childId: 'child_b'), isEmpty);
      expect(await store.acknowledgedRejectIds(childId: 'child_b'), isEmpty);

      // 历史全局键不迁移：新实现不读 'acked_verify_ids'。
      expect(
          await store.acknowledgedVerifyIds(childId: kChildIdDefault), isEmpty);

      // 键名单点 helper：落盘键形如 xxx_read_$childId。
      expect(sp.getStringList('acked_verify_ids_read_child_a'), <String>['r1']);
      expect(sp.getStringList('acked_reject_ids_read_child_a'), <String>['j1']);
    });
  });
}
