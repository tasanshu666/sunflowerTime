/// C90 期 2 第二批：孩子端「我的」页与当前孩子档案联动（玄参反馈）。
///
/// 钉死三条口径：
///  ① 显示**当前孩子档案** name（🔴 C91 修订：只显示昵称本身，不再拼
///     「· 低年级 / 8 岁及以下」档位后缀 —— 年龄段不是给孩子看的）；
///  ② 家长端改档（改名 / 调档）后 `childProfileRevisionProvider` 自增 →
///     本页经 ChildTabAutoRefresh 无条件刷新，展示即时跟档；
///  ③ 旧 SP 昵称键 `child_nickname` **停止读取**（留存不迁移）—— 即便盘上有
///     旧值也绝不显示，且孩子端改名入口已删。
///
/// 脚手架参照 `test/c90/child_data_isolation_test.dart`：内存 Drift 库 + mock SP +
/// 真 Dao / 真仓储全链路，无平台通道。
library child_profile_page_child_binding_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, AccountService, ChildProfileLocalRepository)>
      pumpPage(WidgetTester tester,
          {Map<String, Object> spValues = const <String, Object>{}}) async {
    SharedPreferences.setMockInitialValues(spValues);
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ChildProfileLocalRepository children =
        ChildProfileLocalRepository(database);
    final AccountService account = AccountService(
      children: children,
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
        child: const MaterialApp(home: Scaffold(body: ChildProfilePage())),
      ),
    );
    // 等待 _reload 完成（成就区出现即加载完成）。
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('累计成就').evaluate().isNotEmpty) break;
    }
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(ChildProfilePage)));
    return (container, account, children);
  }

  testWidgets('① 显示当前孩子档案 name（C91：只有昵称本身，无档位后缀）', (tester) async {
    final (_, AccountService account, _) = await pumpPage(tester);
    final ChildProfile second = await account.createChild('小明', AgeTier.low);
    await account.switchTo(second.id);

    // 切孩子会自增档案修订号 → mixin 无条件刷新；这里手动等价触发。
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(find.byType(ChildProfilePage)));
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('小明'), findsOneWidget, reason: 'C91：只显示昵称本身');
    // 档位后缀（C90 期 2 旧展示）不得再出现。
    expect(find.text('小明 · 低年级 · 8 岁及以下'), findsNothing);
    expect(find.textContaining('低年级'), findsNothing,
        reason: '年龄段不是给孩子看的，本页任何档位文案都不渲染');
    // 旧默认文案（无档案时的兜底）不得再出现。
    expect(find.text('小朋友 · 高年级 · 13 岁及以上'), findsNothing);
  });

  testWidgets('② 家长改档（改名 + 调档）后随修订号刷新展示', (tester) async {
    final (ProviderContainer container, AccountService account,
            ChildProfileLocalRepository children) =
        await pumpPage(tester);
    final ChildProfile second = await account.createChild('小明', AgeTier.low);
    await account.switchTo(second.id);
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('小明'), findsOneWidget);

    // 家长端编辑：改名 + 调档（等价 child_profile_bar._openEditFlow：update 落库
    // 后对当前孩子 switchTo 刷新 AccountService 活跃快照，再 bump 修订号）。
    await children.update(second.id, name: '明明', ageTier: AgeTier.mid);
    await account.switchTo(second.id);
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // C91：调档后展示仍是纯昵称（档位变化不影响本页展示）。
    expect(find.text('明明'), findsOneWidget);
    expect(find.textContaining('中年级'), findsNothing);
  });

  testWidgets('③ 旧 SP 昵称键 child_nickname 停止读取（有旧值也不显示）', (tester) async {
    await pumpPage(
      tester,
      spValues: <String, Object>{kPrefChildNicknameLegacy: '旧昵称'},
    );
    // 默认孩子档案 name = '孩子'（AccountService.initialize 空表补建）。
    expect(find.text('孩子'), findsOneWidget);
    expect(find.text('旧昵称'), findsNothing,
        reason: '旧 SP 昵称键已停止读取（历史值留存不迁移）');
    expect(find.byIcon(Icons.edit), findsNothing,
        reason: '孩子端改名入口已删除（改名只在家长天地）');
    expect(find.text('我的昵称'), findsNothing);
  });
}

/// 旧昵称 SP 键字面量（app_constants 已删除常量，测试以字面量钉死历史键行为）。
const String kPrefChildNicknameLegacy = 'child_nickname';
