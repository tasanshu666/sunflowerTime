/// AccountService（C90 期 1 多档案底座）单元测试。
///
/// 钉死的行为：
///  · 默认孩子**只建一次**（幂等）：空表补建 id=kChildIdDefault / name='孩子' /
///    ageTier=当前 settings 单行值；重复 initialize 不再插；
///  · `switchTo` 校验存在 + 持久化到 SP（`active_child_id`）；新实例冷启动恢复；
///  · SP 指向不存在的孩子 → 回退第一个孩子（🔴 绝不删档案，C69）；
///  · `createChild` 后 count 正确；
///  · 桩模式兼容：无依赖构造时 `childId` 恒返 kChildIdDefault（store_page_test
///    等既有用法零改动）；云同步三方法保持 UnsupportedError（C1）。
library account_service_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/account_service.dart';

void main() {
  /// 真依赖组装：内存 Drift 库 + mock SP（全链路无平台通道）。
  Future<(AccountService, AppDatabase, SharedPreferences)> build({
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final SharedPreferences sp = await SharedPreferences.getInstance();
    // 🔴 内存执行器直开（同 migration_v26_test 先例）：
    // AppDatabase() 默认构造会走 SQLCipher + path_provider 平台通道，测试宿主不可用。
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final AccountService service = AccountService(
      children: ChildProfileLocalRepository(db),
      settings: SettingsLocalRepository(db),
      prefs: sp,
    );
    return (service, db, sp);
  }

  group('C90 默认孩子（冷启动补建）', () {
    test('空表 initialize → 建默认孩子（id/name/ageTier 取 settings 单行）', () async {
      final (AccountService service, AppDatabase db, _) = await build();
      addTearDown(db.close);

      await service.initialize();
      final List<ChildProfile> children =
          await ChildProfileLocalRepository(db).children();
      expect(children.length, 1);
      expect(children.single.id, kChildIdDefault);
      expect(children.single.name, '孩子');
      // 无 settings 行 → settings 空表默认语义 = high（同 SettingsLocalRepository）。
      expect(children.single.ageTier, AgeTier.high);
    });

    test('幂等：initialize 两次默认孩子只建一次', () async {
      final (AccountService service, AppDatabase db, _) = await build();
      addTearDown(db.close);

      await service.initialize();
      await service.initialize();
      expect(await ChildProfileLocalRepository(db).count(), 1);
    });

    test('老库升级场景：已有 settings 行 → 默认孩子 ageTier 取该值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await SettingsLocalRepository(db).saveSettings(
        (await SettingsLocalRepository(db).getSettings())
            .copyWith(ageTier: AgeTier.low),
      );

      final AccountService service = AccountService(
        children: ChildProfileLocalRepository(db),
        settings: SettingsLocalRepository(db),
        prefs: sp,
      );
      await service.initialize();
      final children = await ChildProfileLocalRepository(db).children();
      expect(children.single.ageTier, AgeTier.low);
    });
  });

  group('C90 switchTo（切换 + 持久化）', () {
    test('switchTo 写 SP；新实例 initialize 恢复活跃孩子（同步 childId 生效）',
        () async {
      final (AccountService service, AppDatabase db, SharedPreferences sp) =
          await build();
      addTearDown(db.close);
      await service.initialize();
      expect(service.childId, kChildIdDefault);

      final second = await service.createChild('二娃', AgeTier.mid);
      await service.switchTo(second.id);
      expect(service.childId, second.id, reason: '切换后同步 getter 立即生效');
      expect(service.currentChildId(), second.id);
      expect(sp.getString(kPrefActiveChildId), second.id,
          reason: '切换必须持久化到 SP');

      // 冷启动恢复：新实例（同 SP / 同库，模拟重启后重开）。
      final AccountService service2 = AccountService(
        children: ChildProfileLocalRepository(db),
        settings: SettingsLocalRepository(db),
        prefs: sp,
      );
      await service2.initialize();
      expect(service2.childId, second.id);
      expect((await service2.currentProfile())!.name, '二娃');
    });

    test('SP 指向不存在的孩子 → 回退第一个孩子（绝不删档案）', () async {
      // 先造两个档案 + SP 指向幽灵 id（同一 SP 实例贯穿两次冷启动）。
      SharedPreferences.setMockInitialValues(
        <String, Object>{kPrefActiveChildId: 'ghost-child'},
      );
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final AccountService service = AccountService(
        children: ChildProfileLocalRepository(db),
        settings: SettingsLocalRepository(db),
        prefs: sp,
      );
      await service.initialize(); // 空表建默认孩子（SP 无效）
      await service.createChild('二娃', AgeTier.mid);

      final AccountService service2 = AccountService(
        children: ChildProfileLocalRepository(db),
        settings: SettingsLocalRepository(db),
        prefs: sp,
      );
      await service2.initialize();

      final children = await ChildProfileLocalRepository(db).children();
      expect(children.length, 2, reason: 'C69：绝不删已存档案');
      expect(service2.childId, children.first.id,
          reason: '回退第一个孩子（创建最早的默认孩子）');
    });

    test('switchTo 不存在的 id → ArgumentError，活跃孩子不变', () async {
      final (AccountService service, AppDatabase db, _) = await build();
      addTearDown(db.close);
      await service.initialize();

      expect(() => service.switchTo('nope'), throwsArgumentError);
      expect(service.childId, kChildIdDefault);
    });
  });

  group('C90 createChild（新建档案）', () {
    test('createChild 后 count 正确（uuid 新 id，不动活跃孩子）', () async {
      final (AccountService service, AppDatabase db, _) = await build();
      addTearDown(db.close);
      await service.initialize();

      final a = await service.createChild('大娃', AgeTier.low);
      final b = await service.createChild('二娃', AgeTier.mid);
      expect(await ChildProfileLocalRepository(db).count(), 3); // 默认 + 2
      expect(a.id, isNot(kChildIdDefault));
      expect(b.id, isNot(a.id));
      expect(service.childId, kChildIdDefault,
          reason: '新建 ≠ 切换：活跃孩子不因 createChild 改变');
      expect(a.ageTier, AgeTier.low);
      expect(b.ageTier, AgeTier.mid);
    });
  });

  group('C90 桩模式兼容（无依赖构造）', () {
    test('childId 恒返 kChildIdDefault；initialize 可安全调用', () async {
      final AccountService stub = AccountService();
      await stub.initialize(); // 桩模式幂等无副作用
      expect(stub.childId, kChildIdDefault);
      expect(stub.currentChildId(), kChildIdDefault);
      expect(await stub.currentProfile(), isNull);
    });

    test('云同步三方法保持 UnsupportedError（C1）', () async {
      final AccountService service = AccountService();
      expect(() => service.signIn(), throwsUnsupportedError);
      expect(() => service.linkFamily(), throwsUnsupportedError);
      expect(() => service.syncProfile(), throwsUnsupportedError);
    });
  });
}
