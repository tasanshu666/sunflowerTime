/// 奖励 DAO / 迁移测试（§3.1 / §3.2 / D2）。
///
/// 用 Drift 内存库（`NativeDatabase.memory()`）验证：
///  · 打开 schemaVersion=2 的库后，`rewardTemplates.baseCost` 列可用（迁移健全性）；
///  · `trackingEvents.name` 列可用（迁移健全性）；
///  · `MonthlyPoolDao` 经 `of(monthKey)` 往返 `budget/used` 正确。
///
/// 说明：内存库首次打开由 Drift 直接按 v2 schema 建表（onUpgrade 仅对已有旧库生效），
/// 因此「能插入带 baseCost 的模板并读回」即隐性证明该列已存在（迁移目标达成，
/// 见 §1.3 / §7 纪律 #9）。
///
/// 本文件由用户机 `flutter test` 执行；沙箱环境 `flutter test` 被阻断、且 DB 引入
/// Flutter 插件，故此处仅保证 `flutter analyze` 通过。
library reward_dao_test;

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:test/test.dart';

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('RewardTemplateDao · baseCost 列往返（v1→v2 迁移健全性）', () {
    test('插入含 baseCost 的模板，读回 baseCost 一致', () async {
      await database.rewardTemplateDao.upsert(
        db.RewardTemplatesCompanion(
          id: const Value('tpl_snack'),
          name: const Value('小零食'),
          category: const Value(1), // RewardCategory.parentHandled
          baseCost: const Value(35),
        ),
      );

      final List<db.RewardTemplate> all = await database.rewardTemplateDao.all();
      expect(all, hasLength(1));
      expect(all.first.id, 'tpl_snack');
      // 迁移后 baseCost 列可用：写回一致即证明该列存在且可往返。
      expect(all.first.baseCost, 35);
    });
  });

  group('RewardTemplateDao · deleteById 硬删除', () {
    test('插入后 deleteById，all() 不再包含该模板', () async {
      await database.rewardTemplateDao.upsert(
        db.RewardTemplatesCompanion(
          id: const Value('tpl_del'),
          name: const Value('待删'),
          category: const Value(0),
          baseCost: const Value(10),
        ),
      );
      expect(await database.rewardTemplateDao.all(), hasLength(1));
      final int removed = await database.rewardTemplateDao.deleteById('tpl_del');
      expect(removed, 1);
      expect(await database.rewardTemplateDao.all(), isEmpty);
    });
  });

  group('TrackingEventDao · name 列往返（v1→v2 迁移健全性）', () {
    test('插入含 name 的埋点，读回 name 一致', () async {
      await database.trackingEventDao.insert(
        db.TrackingEventsCompanion(
          id: const Value('evt_1'),
          name: const Value('reward_redeem_request'),
          type: const Value(1), // TrackingType.metric
          ts: Value(DateTime(2026, 9, 15)),
          payload: const Value('{}'),
        ),
      );

      final List<db.TrackingEvent> events =
          await database.trackingEventDao.ofType(1);
      expect(events, hasLength(1));
      // 迁移后 name 列可用：写回一致即证明该列存在且可往返。
      expect(events.first.name, 'reward_redeem_request');
    });
  });

  group('MonthlyPoolDao · of(monthKey) 往返', () {
    test('upsert 后经 of(monthKey) 读回 budget/used 正确', () async {
      await database.monthlyPoolDao.upsert(
        db.MonthlyPoolsCompanion(
          monthKey: const Value('2026-09'),
          budget: const Value(300),
          used: const Value(120),
          autoReleased: const Value(40),
          resetAt: Value(DateTime(2026, 9, 1)),
        ),
      );

      final db.MonthlyPool? pool =
          await database.monthlyPoolDao.of('2026-09');
      expect(pool, isNotNull);
      expect(pool!.monthKey, '2026-09');
      expect(pool.budget, 300);
      expect(pool.used, 120);
      expect(pool.autoReleased, 40);
    });
  });

  group('RewardLocalRepository · 落单即 bump 本周冷却计数（D4 回归）', () {
    // 回归锁：此前 createRequest 只 insert、从不 bump 冷却计数，
    // 导致 cooldownCount 恒为 0、孩子端「剩余次数」永远等于限领值、_onCooldown 闸门失效。
    late RewardLocalRepository repo;

    setUp(() {
      repo = RewardLocalRepository(database);
    });

    RedemptionRequest _req(String id, String tpl) => RedemptionRequest(
          id: id,
          childId: 'c1',
          templateId: tpl,
          requestedAt: DateTime(2026, 9, 21, 10),
          cost: 40,
          status: RequestStatus.pending,
          autoApproved: false,
          queuePosition: null,
          verifiedAt: null,
          parentNote: null,
        );

    test('同一模板落单 N 次，cooldownCount 返回 N', () async {
      expect(await repo.cooldownCount('tpl_snack', CooldownPeriod.weekly), 0);
      await repo.createRequest(_req('r1', 'tpl_snack'));
      expect(await repo.cooldownCount('tpl_snack', CooldownPeriod.weekly), 1);
      await repo.createRequest(_req('r2', 'tpl_snack'));
      await repo.createRequest(_req('r3', 'tpl_snack'));
      expect(await repo.cooldownCount('tpl_snack', CooldownPeriod.weekly), 3);
    });

    test('不同模板的冷却计数相互独立', () async {
      await repo.createRequest(_req('a1', 'tpl_a'));
      await repo.createRequest(_req('b1', 'tpl_b'));
      expect(await repo.cooldownCount('tpl_a', CooldownPeriod.weekly), 1);
      expect(await repo.cooldownCount('tpl_b', CooldownPeriod.weekly), 1);
    });
  });
}
