/// C91：家长端「记录」页兑换记录统一走全局当前孩子（玄参 2026-10-19 拍板）。
///
/// 钉死三条口径（**C90-C-1「切孩子仅改本段过滤」作废**）：
///  ① 段内孩子选择胶囊 `_ChildSelectorBar`（C90-C-1）**已下线** —— 页面不渲染
///     `child_history_selector`，切孩子统一走家长天地顶部全局胶囊；
///  ② 兑换记录按**全局当前孩子**显示：过滤下沉到仓储层（C91/F123
///     `RewardLocalRepository.verifiedRequests()` 按 childId 单点过滤），
///     段内零裁剪 —— 真仓储全链路下 B 的记录绝不混入 A 的视图；
///  ③ 汇总数字（本期兑换奖励 / 消耗阳光）随全局当前孩子走。
///
/// 脚手架参照 `test/c90/child_profile_page_child_binding_test.dart`：
/// 内存 Drift 库 + mock SP + 真 Dao / 真仓储全链路（兑换走真库，可跨孩子造数）。
library redemption_history_child_filter_test;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/redemption_request.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/parent/widgets/history_activity_section.dart';

/// 空 Fake：无打卡、无成长项（本文件只测兑换记录的孩子过滤，任务块保持空态）。
class _EmptyTaskRepository implements TaskRepository, CheckInAdminRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];
  @override
  Future<void> saveTask(Task task) async {}
  @override
  Future<void> deleteTaskById(String id) async {}
  @override
  Future<void> checkIn(CheckIn checkIn) async {}
  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];
  @override
  Future<int> totalCheckInCount() async => 0;
  @override
  Future<CheckIn?> checkInById(String id) async => null;
  @override
  Future<List<CheckIn>> checkInsByStatus(CheckInStatus status) async =>
      <CheckIn>[];
  @override
  Future<void> updateCheckIn(CheckIn checkIn) async {}
  @override
  Future<bool> resolveCheckInIfStatus({
    required String id,
    required CheckInStatus from,
    required CheckInStatus to,
    required double sunlightGranted,
    required DateTime resolvedAt,
    String? parentNote,
  }) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 期间锚点：日档默认 = 当天 → 两条核销记录都落 verifiedAt 当天。
  final DateTime now = DateTime(2026, 9, 15, 12);

  Future<(ProviderContainer, AccountService)> pumpSection(
    WidgetTester tester,
    db.AppDatabase database,
    AccountService account,
    SharedPreferences sp,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
          // C91：真仓储（按当前孩子过滤）—— 兑换记录隔离走全链路真库。
          rewardRepositoryProvider.overrideWithValue(
            RewardLocalRepository(database, account: account),
          ),
          taskRepositoryProvider.overrideWithValue(_EmptyTaskRepository()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HistoryActivitySection(now: now),
          ),
        ),
      ),
    );
    // 等待 FutureBuilder 首帧完成（汇总卡出现即加载完成）。
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.textContaining('本期兑换奖励').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final ProviderContainer container =
        ProviderScope.containerOf(tester.element(
      find.byType(HistoryActivitySection),
    ));
    return (container, account);
  }

  /// 两个孩子的核销记录：A（默认孩子）2 条冰淇淋；B（小明）1 条动画片
  /// + 1 条冰淇淋（确保「同一模板跨孩子」也不会混计）。
  ///
  /// 直接落库（childId 写死），绕开当前孩子语义 —— 造「跨孩子历史数据」。
  Future<void> seedVerifiedRequests(db.AppDatabase database) async {
    // 段内行名取自 reward_templates（tpl?.name ?? '（已删除的奖励）'）——
    // 两个被引用的模板必须真实存在，否则断言的模板名永远不出现（C91 修复：
    // 原脚手架漏种模板 → 用例②必红）。奖励模板为全局表，跨孩子共享。
    final RewardLocalRepository reward = RewardLocalRepository(database);
    await reward.saveTemplate(const RewardTemplate(
      id: 'tpl_icecream',
      name: '冰淇淋',
      category: RewardCategory.parentHandled,
      baseCost: 20,
      frequencyLimitPerWeek: 0,
    ));
    await reward.saveTemplate(const RewardTemplate(
      id: 'tpl_episode',
      name: '多看一集动画片',
      category: RewardCategory.parentHandled,
      baseCost: 50,
      frequencyLimitPerWeek: 0,
    ));

    // 直接经 DAO 落库（childId 写死，造「跨孩子历史数据」；不 bump 冷却计数）。
    final DateTime at = DateTime(2026, 9, 15, 10);
    final List<RedemptionRequest> rows = <RedemptionRequest>[
      RedemptionRequest(
        id: 'r_a1',
        childId: kChildIdDefault,
        templateId: 'tpl_icecream',
        requestedAt: at,
        cost: 20,
        status: RequestStatus.verified,
        verifiedAt: at,
      ),
      RedemptionRequest(
        id: 'r_a2',
        childId: kChildIdDefault,
        templateId: 'tpl_icecream',
        requestedAt: at.add(const Duration(hours: 1)),
        cost: 20,
        status: RequestStatus.verified,
        verifiedAt: at.add(const Duration(hours: 1)),
      ),
      RedemptionRequest(
        id: 'r_b1',
        childId: 'child_b',
        templateId: 'tpl_episode',
        requestedAt: at,
        cost: 50,
        status: RequestStatus.verified,
        verifiedAt: at,
      ),
      RedemptionRequest(
        id: 'r_b2',
        childId: 'child_b',
        templateId: 'tpl_icecream',
        requestedAt: at,
        cost: 20,
        status: RequestStatus.verified,
        verifiedAt: at,
      ),
    ];
    for (final RedemptionRequest r in rows) {
      await database.redemptionRequestDao.insert(db.RedemptionRequestsCompanion(
        id: Value(r.id),
        childId: Value(r.childId),
        templateId: Value(r.templateId),
        requestedAt: Value(r.requestedAt),
        cost: Value(r.cost),
        status: Value(r.status.index),
        autoApproved: Value(r.autoApproved),
        queuePosition: Value(r.queuePosition),
        verifiedAt: Value(r.verifiedAt),
        parentNote: Value(r.parentNote),
      ));
    }
  }

  Future<db.AppDatabase> buildDatabase() async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    return database;
  }

  testWidgets('① 只显示全局当前孩子的兑换记录；段内孩子选择栏已下线', (tester) async {
    final db.AppDatabase database = await buildDatabase();
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final ChildProfileLocalRepository children =
        ChildProfileLocalRepository(database);
    final AccountService account = AccountService(
      children: children,
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    // B 孩子档案（id 固定，与造数的 childId 对齐）。
    await children.create('小明', AgeTier.low, id: 'child_b');
    await seedVerifiedRequests(database);

    await pumpSection(tester, database, account, sp);

    // C91：段内选择胶囊不得再出现（切孩子统一走家长天地顶部全局胶囊）。
    expect(find.byKey(const ValueKey<String>('child_history_selector')),
        findsNothing);

    // 只显示 A（当前孩子）的记录：冰淇淋 2 次；B 的记录不出现。
    expect(find.text('兑换 2 次'), findsOneWidget);
    expect(find.text('共 2 次 · 消耗 40 阳光'), findsOneWidget);
    expect(find.text('兑换 1 次'), findsNothing,
        reason: 'B 的兑换记录不得混入当前孩子的视图');
    expect(find.text('多看一集动画片'), findsNothing,
        reason: 'B 专有的模板行不得出现在当前孩子的视图');
  });

  testWidgets('② 切全局当前孩子 → 记录跟随（全局语义，非段内过滤）', (tester) async {
    final db.AppDatabase database = await buildDatabase();
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final ChildProfileLocalRepository children =
        ChildProfileLocalRepository(database);
    final AccountService account = AccountService(
      children: children,
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    await children.create('小明', AgeTier.low, id: 'child_b');
    await seedVerifiedRequests(database);

    final (ProviderContainer container, AccountService accountRef) =
        await pumpSection(tester, database, account, sp);

    // 全局切到 B（等价家长天地顶部 ChildProfileBar 切孩子：switchTo + 修订号自增）。
    await accountRef.switchTo('child_b');
    container.read(childProfileRevisionProvider.notifier).state++;
    await tester.pumpAndSettle(const Duration(milliseconds: 150));

    // 段内数据随全局当前孩子刷新：B 的记录（动画片 1 次 + 冰淇淋 1 次）。
    expect(find.text('多看一集动画片'), findsOneWidget);
    expect(find.text('兑换 1 次'), findsNWidgets(2));
    expect(find.text('共 2 次 · 消耗 70 阳光'), findsOneWidget);
    // A 专有的「冰淇淋 2 次」聚合行消失。
    expect(find.text('兑换 2 次'), findsNothing);

    // 全局当前孩子确已切到 B（而非段内局部状态）。
    expect((await accountRef.currentProfile())!.id, 'child_b');
  });
}
