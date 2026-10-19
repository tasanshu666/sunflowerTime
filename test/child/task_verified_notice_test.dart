/// F126（玄参 2026-10-19 反馈）：**家长审批成长任务后，孩子端缺金色确认卡** ——
/// 体验缺口补齐后的回归守卫。
///
/// 现象：家长端「今日」页核销**商店兑换**后，孩子端会弹金色卡片（米色底 + 金色
/// 奖杯 + 条目 + 「知道啦」）；但家长审批**成长任务打卡**（点「确认发放」）后，
/// 孩子端**什么都没有**，只有家长端一条 SnackBar —— 孩子感知不到任务被确认了。
///
/// 修复口径（与兑换核销卡完全对称，视觉复用 `gold_notice_dialog.dart`）：
///  · 数据源 = `checkInsByStatus(verified)` 中 `resolvedAt != null`（**排除联动项
///    自动结算**）且处理时间在最近 24 小时内的记录；
///  · 按 `resolvedAt` 倒序，先剔除已读再取最多 3 条；
///  · 已读快照键按孩子分键：`acked_task_checkin_ids_read_$childId`。
///
/// ⚠️ 时间夹具一律相对 `DateTime.now()`（项目铁律），不用固定日期。
library task_verified_notice_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart';

/// 卡头标题（钉死字面量：孩子看到的就这句）。
const String _kTitle = '🎉 家长已确认你的成长任务';

/// 造一个最小可用成长任务。
Task _task(String id, String name) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: true,
    );

/// 造一条**已核销**打卡。
///
/// [resolvedAt] 传 null = 联动项自动结算（不是家长动作，绝不该弹「家长已确认」卡）。
CheckIn _checkIn({
  required String id,
  required String taskId,
  DateTime? resolvedAt,
  double gross = 12,
  double granted = 12,
}) {
  final DateTime now = DateTime.now();
  return CheckIn(
    id: id,
    taskId: taskId,
    date: now,
    completedAt: now.subtract(const Duration(hours: 3)),
    isPerfectDay: false,
    status: CheckInStatus.verified,
    sunlightGross: gross,
    sunlightGranted: granted,
    resolvedAt: resolvedAt,
  );
}

Future<SharedPreferences> _mockSp() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

/// 挂载孩子端外壳（脚手架参照 `test/c91/verify_notice_child_isolation_test.dart`）。
///
/// 大字号布局回归（用例 ⑩）**不走**这条路径：外壳自身在 320×568 + 1.3 倍字号下
/// 曾有与本卡无关的既有右向溢出（F127 已在 `_StatCard` 修掉），⑩ 仍改用
/// [_pumpGoldDialogDirect] 单独挂卡 —— 卡片布局必须能独立于外壳被量，混在一起
/// 断言就无法定位责任方。
Future<void> _pumpShell(
  WidgetTester tester, {
  required SharedPreferences sp,
  required db.AppDatabase database,
  required AccountService account,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      ),
      child: const MaterialApp(home: ChildShellPage()),
    ),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 卸载当前外壳（下次 [_pumpShell] 即 remount，initState 重跑一遍通知检查）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 点「知道啦」并等 dialog 关闭后的异步写回完成。
Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.text('知道啦'));
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 把「金色卡」单独挂在**真实 Dialog 路由**里（不经孩子端外壳）。
///
/// 用途：小屏 / 大字号布局回归（用例 ⑩）。为什么不挂外壳 —— 探针实测外壳自身在
/// 320×568 + 1.3 倍字号下已有**与本卡无关**的既有 14px 右向溢出（同尺寸下完全
/// 不放卡片也照样溢出），混在一起断言就无法定位责任方。
/// 仍然走 `showGoldNoticeDialog` → 真实 Dialog 路由，约束与线上一致（Dialog 的
/// `insetPadding` 也照常生效）。
/// 🔴 `textScaler` 必须从 `MaterialApp.builder` 注入：`home` 子树里的 MediaQuery
/// 覆盖不到 Dialog 路由（overlay 在 builder 之下、home 之上）。
Future<void> _pumpGoldDialogDirect(
  WidgetTester tester, {
  required List<GoldNoticeItem> items,
  required String footerText,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext ctx, Widget? child) => MediaQuery(
        data:
            MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showGoldNoticeDialog(
                ctx,
                title: _kTitle,
                items: items,
                footerText: footerText,
              ),
              child: const Text('打开卡片'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('打开卡片'));
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 家长审批成长任务 → 孩子端弹金色确认卡（任务名 + 实发阳光 + 合计）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    final DateTime now = DateTime.now();
    await repo.saveTask(_task('t_a', '朗读英语'));
    await repo.saveTask(_task('t_b', '整理书桌'));
    // 家长 1 小时前确认了「朗读英语」(+12)，2 小时前确认了「整理书桌」(+8)。
    await repo.checkIn(_checkIn(
      id: 'c_a',
      taskId: 't_a',
      resolvedAt: now.subtract(const Duration(hours: 1)),
    ));
    await repo.checkIn(_checkIn(
      id: 'c_b',
      taskId: 't_b',
      resolvedAt: now.subtract(const Duration(hours: 2)),
      gross: 8,
      granted: 8,
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsOneWidget, reason: '家长审批后孩子端必须有确认卡');
    expect(find.text('朗读英语'), findsOneWidget);
    expect(find.text('整理书桌'), findsOneWidget);
    expect(find.text('+12 阳光'), findsOneWidget);
    expect(find.text('+8 阳光'), findsOneWidget);
    expect(find.text('共获得 20 阳光'), findsOneWidget);
    expect(find.text('知道啦'), findsOneWidget);

    await _tapConfirm(tester);
    expect(sp.getStringList(ackedTaskCheckInIdsKey(kChildIdDefault)),
        <String>['c_a', 'c_b'],
        reason: '已读快照按 resolvedAt 倒序写入（最新在前）');

    // 已读去重：再进孩子端不重复弹。
    await _unmount(tester);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kTitle), findsNothing, reason: '已读后不再重复弹卡');
  });

  testWidgets('② 联动项自动结算（resolvedAt == null）绝不弹「家长已确认」卡',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    await repo.saveTask(_task('t_focus', '专注联动'));
    // verified + resolvedAt == null = 专注联动自动结算（没有家长动作）。
    await repo.checkIn(_checkIn(id: 'c_auto', taskId: 't_focus'));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsNothing,
        reason: '自动结算不是家长审批，弹卡会让孩子误以为家长一直在看');
    expect(sp.getStringList(ackedTaskCheckInIdsKey(kChildIdDefault)), isNull,
        reason: '没有可展示的行 → 不写快照键');
  });

  testWidgets('③ 超出 24 小时时间窗的历史打卡不弹（避免首次上线一次弹几十条）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    await repo.saveTask(_task('t_old', '昨天的任务'));
    await repo.checkIn(_checkIn(
      id: 'c_old',
      taskId: 't_old',
      resolvedAt: DateTime.now().subtract(const Duration(hours: 25)),
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsNothing, reason: '25 小时前处理的属历史，不打扰孩子');
  });

  testWidgets('④ 单次最多列 3 条：超出部分留到下次补弹（不丢通知）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    final DateTime now = DateTime.now();
    // 5 条最近 5 小时内被处理的打卡（第 n 条 = n 小时前）。
    for (int i = 1; i <= 5; i++) {
      await repo.saveTask(_task('t_$i', '任务$i'));
      await repo.checkIn(_checkIn(
        id: 'c_$i',
        taskId: 't_$i',
        resolvedAt: now.subtract(Duration(hours: i)),
      ));
    }

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsOneWidget);
    // 最新 3 条 = 任务1/2/3（1 小时前 → 3 小时前）。
    expect(find.text('任务1'), findsOneWidget);
    expect(find.text('任务2'), findsOneWidget);
    expect(find.text('任务3'), findsOneWidget);
    expect(find.text('任务4'), findsNothing, reason: '单次最多 3 条，不撑爆屏幕');
    expect(find.text('任务5'), findsNothing);

    await _tapConfirm(tester);
    expect(sp.getStringList(ackedTaskCheckInIdsKey(kChildIdDefault)),
        <String>['c_1', 'c_2', 'c_3']);

    // 第二次进入：剩下 2 条补弹（通知不丢）。
    await _unmount(tester);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kTitle), findsOneWidget);
    expect(find.text('任务4'), findsOneWidget);
    expect(find.text('任务5'), findsOneWidget);
    await _tapConfirm(tester);
    expect(sp.getStringList(ackedTaskCheckInIdsKey(kChildIdDefault)),
        <String>['c_1', 'c_2', 'c_3', 'c_4', 'c_5']);
  });

  testWidgets('⑤ 跨孩子：A 的审批卡绝不在 B 的孩子端弹（已读快照按孩子分键）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    // A（默认孩子）的打卡被家长确认。
    await repo.saveTask(_task('t_a', 'A的任务'));
    await repo.checkIn(_checkIn(
      id: 'c_a',
      taskId: 't_a',
      resolvedAt: DateTime.now().subtract(const Duration(minutes: 30)),
    ));

    // 当前孩子 = B → 仓储级过滤（F123 同源）看不到 A 的打卡 → 不弹卡。
    await account.switchTo(second.id);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kTitle), findsNothing, reason: 'B 的孩子端绝不弹 A 的任务确认卡');
    expect(sp.getStringList(ackedTaskCheckInIdsKey(second.id)), isNull,
        reason: 'B 没有可展示的行 → 快照键保持为空');

    // 切回 A：A 的通知不丢。
    await _unmount(tester);
    await account.switchTo(kChildIdDefault);
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kTitle), findsOneWidget, reason: 'A 自己的确认卡照常弹');
  });

  testWidgets('⑥ 已读写入时机：卡片弹出但**未点「知道啦」前**不得写快照（挡住未看先读）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    await repo.saveTask(_task('t_gate', '背单词'));
    await repo.checkIn(_checkIn(
      id: 'c_gate',
      taskId: 't_gate',
      resolvedAt: DateTime.now().subtract(const Duration(minutes: 15)),
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text(_kTitle), findsOneWidget, reason: '卡片已弹出');

    // ⚠️ 关键断言：卡片**还开着**（孩子还没点「知道啦」）→ 快照必须仍为空。
    // 若把已读写到 `await showDialog` 之前（未看先读），这里会拿到 ['c_gate'] 而红。
    final SettingsStore store = SettingsStore(sp);
    expect(await store.acknowledgedTaskCheckInIds(childId: kChildIdDefault),
        isEmpty,
        reason: '孩子还没看到卡片，绝不能提前标记已读');

    await _tapConfirm(tester);
    expect(await store.acknowledgedTaskCheckInIds(childId: kChildIdDefault),
        <String>['c_gate'],
        reason: '点了「知道啦」之后才写已读');
  });

  testWidgets('⑦ capped=0 显示口径：实发 0 → 「今日额度已满」，绝不虚报 +12 阳光',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    final DateTime now = DateTime.now();
    await repo.saveTask(_task('t_cap', '晨读'));
    // 当日成长奖励额度用尽：家长仍点了「确认发放」→ granted = 0，gross = 12。
    await repo.checkIn(_checkIn(
      id: 'c_cap',
      taskId: 't_cap',
      resolvedAt: now.subtract(const Duration(minutes: 20)),
      gross: 12,
      granted: 0,
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsOneWidget, reason: '确认这件事发生了，卡照弹');
    expect(find.text('晨读'), findsOneWidget);
    expect(find.text('今日额度已满'), findsOneWidget,
        reason: '实发 0 → 该行显示「今日额度已满」');
    expect(find.text('+12 阳光'), findsNothing,
        reason: '⚠️ 绝不能把应发 gross 当实发报给孩子（虚报阳光 = 口径错误）');
    expect(find.text('今日成长奖励已达上限，本次没有新增阳光'), findsOneWidget,
        reason: '全部条目实发 0 → 合计说明本次没有新增阳光');
    await _tapConfirm(tester);

    // ② 混合档：一条封顶 + 一条实发 → 合计要标明「X 项今日额度已满，未发放」。
    await sp.clear();
    await _unmount(tester);
    await repo.saveTask(_task('t_ok', '跳绳'));
    await repo.checkIn(_checkIn(
      id: 'c_ok',
      taskId: 't_ok',
      resolvedAt: now.subtract(const Duration(minutes: 5)),
      gross: 8,
      granted: 8,
    ));
    await _pumpShell(tester, sp: sp, database: database, account: account);
    expect(find.text('+8 阳光'), findsOneWidget);
    expect(find.text('今日额度已满'), findsOneWidget);
    expect(find.text('共获得 8 阳光（1 项今日额度已满，未发放）'), findsOneWidget,
        reason: '部分封顶时合计必须同时交代到账额与未发放项数');
  });

  testWidgets('⑧ 任务已删除：条目名回退「成长任务」（不给空标题）',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    // 打卡指向一个**不存在**的 taskId（家长审批后把任务删了 / 老数据残留）。
    await repo.checkIn(_checkIn(
      id: 'c_orphan',
      taskId: 't_gone',
      resolvedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsOneWidget);
    expect(find.text('成长任务'), findsOneWidget,
        reason: '任务名映射不到时必须回退「成长任务」，不能显示空串');
  });

  testWidgets(
      '⑨ 封顶判据用原始 double：granted=0.4 不得误报「今日额度已满」/「没有新增阳光」',
      (WidgetTester tester) async {
    final SharedPreferences sp = await _mockSp();
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final AccountService account = AccountService(
      children: ChildProfileLocalRepository(database),
      settings: SettingsLocalRepository(database),
      prefs: sp,
    );
    await account.initialize();
    final TaskLocalRepository repo =
        TaskLocalRepository(database, account: account);

    await repo.saveTask(_task('t_frac', '背单词'));
    // 入账 0.4（**不是 0**，只是不足 1）：判据必须看原始 double。
    await repo.checkIn(_checkIn(
      id: 'c_frac',
      taskId: 't_frac',
      resolvedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      gross: 12,
      granted: 0.4,
    ));

    await _pumpShell(tester, sp: sp, database: database, account: account);

    expect(find.text(_kTitle), findsOneWidget);
    // ⚠️ 这两条是本用例的核心：把 capped 判据绑到「显示取整」上就会误报。
    expect(find.text('今日额度已满'), findsNothing,
        reason: '0.4 已经入账（只是不足 1），绝不能标成封顶');
    expect(find.text('今日成长奖励已达上限，本次没有新增阳光'), findsNothing,
        reason: '同上：合计不得说「没有新增阳光」');
    expect(find.text('+0 阳光'), findsOneWidget,
        reason: 'F105 向下取整口径：0.4 显示为 +0 阳光（已知且接受的显示截断，不改成四舍五入）');
    expect(find.text('共获得 0 阳光'), findsOneWidget,
        reason: '合计同样吃 F105 截断（0.4 → 0），但走的是「无封顶」这一档');
  });

  testWidgets('⑩ 320×568 + textScaler 1.3 + 3 条混合档 → 卡片不溢出（超出才卡内滚动）',
      (WidgetTester tester) async {
    // 小屏 + 大字号：QA 实测旧结构在此溢出 95px（长任务名可达 125px）。
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ⚠️ 本用例**只隔离卡片自身**，不经孩子端外壳 —— 外壳在 320×568 + 1.3 倍字号
    // 下曾有**与本卡无关的既有 14px 右向溢出**（同尺寸下完全不放卡片也照样溢出）。
    // 该溢出于 F127 已在 `child_today_page.dart` 的 `_StatCard` 里结构性修掉
    // （回归守卫见 `shell_narrow_large_text_test.dart`）；本用例仍**刻意**只量卡片
    // 本身 —— 卡片布局要能独立于外壳被度量，混在一起断言就无法定位责任方。
    // 卡片仍走**真实 Dialog 路由**（含 Dialog 的 insetPadding / 路由约束），
    // 否则量到的布局约束与线上不一致。
    await _pumpGoldDialogDirect(
      tester,
      items: const <GoldNoticeItem>[
        GoldNoticeItem(icon: Icons.task_alt, name: '背单词', amountText: '+8 阳光'),
        GoldNoticeItem(
          icon: Icons.task_alt,
          name: '练口算',
          amountText: '今日额度已满',
          amountMuted: true,
        ),
        GoldNoticeItem(icon: Icons.task_alt, name: '读绘本', amountText: '+8 阳光'),
      ],
      // 混合档 = **最长的 footer**。
      footerText: '共获得 16 阳光（1 项今日额度已满，未发放）',
      textScale: 1.3,
    );

    // 核心断言：RenderFlex overflow 会以 FlutterError 形式被 takeException 捕获。
    expect(tester.takeException(), isNull,
        reason: '320×568 + 1.3 倍字号 + 3 条不得出现 overflow');
    expect(find.text('共获得 16 阳光（1 项今日额度已满，未发放）'), findsOneWidget,
        reason: '长 footer 文案一字未缩短（只靠卡内滚动解决空间问题）');

    final Finder card = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Container))
        .first;
    // 1) 高度被 ConstrainedBox 钉在 70% 屏高（397.6 = 568 × 0.7）——
    //    去掉约束后这里会变成内容自然高度，断言立刻红。
    expect(tester.getSize(card).height, closeTo(568 * 0.7, 0.5),
        reason: '超出部分进滚动，卡片高度不超过 70% 屏高');
    // 2) 卡内确实有滚动容器（内容超出时可滚，而不是被裁掉/顶出屏幕）。
    expect(
        find.descendant(of: find.byType(Dialog), matching: find.byType(SingleChildScrollView)),
        findsOneWidget,
        reason: '卡片内容必须在 SingleChildScrollView 里');
  });
}
