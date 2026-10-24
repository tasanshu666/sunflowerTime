/// C90 期 2 数据隔离回归：六张表（plants / sunlight_ledgers / focus_sessions /
/// tasks / check_ins / eye_care_logs）按「当前孩子」写入落标 + 读取过滤。
///
/// 口径（玄参 2026-10-17 拍板）：
///  · 所有数据记**当前孩子**名下（[AccountService.childId] 同步 getter）；
///  · 🔴 仓储接口签名一律不变 —— 过滤在实现内部完成；
///  · 未注入 AccountService 的仓储（既有单测路径）= 恒按 kChildIdDefault，
///    行为与隔离前完全一致（本文件末组钉死）。
///
/// 脚手架参照 `test/domain/account_service_test.dart`：内存 Drift 库 + mock SP +
/// 真 Dao / 真仓储全链路，无平台通道。
library child_data_isolation_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/eye_care_log_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/child_profile.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

const String _dayKey = '2026-10-17';
final DateTime _now = DateTime(2026, 10, 17, 10);

Plant _plant(String id) => Plant(
      id: id,
      speciesId: 'sunflower',
      potIndex: 0,
      stage: PlantStage.seed,
      stageStartedAt: _now,
      growthFactor: 1.0,
      status: PlantStatus.growing,
      plantedAt: _now,
    );

Task _task(String id) => Task(
      id: id,
      name: '任务$id',
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 8,
      isCustom: true,
    );

CheckIn _checkIn(String id, String taskId) => CheckIn(
      id: id,
      taskId: taskId,
      date: DateTime(2026, 10, 17),
      completedAt: _now,
      isPerfectDay: false,
      status: CheckInStatus.pending,
    );

FocusSession _session(String id) => FocusSession(
      id: id,
      start: _now,
      plannedMin: 25,
      actualFocusMin: 25.0,
      status: FocusStatus.completed,
      sunlightEarned: 12.0,
      createdAt: _now,
    );

SunlightEntry _entry(String id, {double net = 12.0, String? refType}) =>
    SunlightEntry(
      id: id,
      ts: _now,
      type: SunlightType.earn,
      gross: net,
      net: net,
      balanceAfter: net,
      refType: refType,
      refId: null,
      dayKey: _dayKey,
    );

EyeCareLog _eyeCare(String id) => EyeCareLog(
      id: id,
      ts: _now,
      dayKey: _dayKey,
      result: EyeCareResultType.completed,
      watchedSeconds: 60,
      source: EyeCareSource.inSession,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 真依赖组装：内存 Drift 库 + mock SP + 六个真仓储（全部挂同一 AccountService）。
  Future<(
    AccountService,
    db.AppDatabase,
    PlantLocalRepository,
    SunlightLocalRepository,
    FocusLocalRepository,
    TaskLocalRepository,
    EyeCareLogLocalRepository,
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
      SunlightLocalRepository(database, account: account),
      FocusLocalRepository(database, account: account),
      TaskLocalRepository(database, account: account),
      EyeCareLogLocalRepository(database, account: account),
    );
  }

  group('C90 期 2 · plants 按孩子隔离', () {
    test('切换孩子后 plants 列表只出现当前孩子的植物；跨孩子按 id 读不到', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        PlantLocalRepository plants,
        _, _, _, _
      ) = await build();
      addTearDown(database.close);

      await plants.savePlant(_plant('p_a1'));
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(account.childId, isNot(kChildIdDefault));

      await plants.savePlant(_plant('p_b1'));

      // 当前孩子（二娃）：只有自己的植物。
      expect((await plants.plants()).map((Plant p) => p.id), <String>['p_b1']);
      expect(await plants.plant('p_a1'), isNull,
          reason: '另一孩子的植物按 id 也读不到（隔离）');
      expect(await plants.plant('p_b1'), isNotNull);

      // 切回默认孩子：只有自己的植物。
      await account.switchTo(kChildIdDefault);
      expect((await plants.plants()).map((Plant p) => p.id), <String>['p_a1']);
      expect(await plants.plant('p_b1'), isNull);
    });

    test('删除也按孩子过滤：删不动另一孩子的植物', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        PlantLocalRepository plants,
        _, _, _, _
      ) = await build();
      addTearDown(database.close);

      await plants.savePlant(_plant('p_a1'));
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      await plants.deletePlant('p_a1'); // 删的是别人的 id → 0 行
      await account.switchTo(kChildIdDefault);
      expect(await plants.plant('p_a1'), isNotNull,
          reason: '删除按 childId 过滤，另一孩子的植物不受影响');
    });
  });

  group('C90 期 2 · sunlight_ledgers 按孩子隔离', () {
    test('余额 / 当日净产出 / refType 计数全部按孩子分开', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _,
        SunlightLocalRepository ledger,
        _, _, _
      ) = await build();
      addTearDown(database.close);

      await ledger.append(_entry('l_a1', net: 30.0, refType: 'task_checkin'));

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      expect(await ledger.balance(), 0.0, reason: '另一孩子的余额不计入');
      expect(await ledger.dayNet(_dayKey), 0.0);
      expect(await ledger.earnGrossOnDay(_dayKey), 0.0);
      expect(await ledger.earnNetOnDay(_dayKey), 0.0);
      expect(await ledger.countByRefType('task_checkin'), 0);
      expect(await ledger.netByRefTypeOnDay('task_checkin', _dayKey), 0.0);

      await ledger.append(_entry('l_b1', net: 5.0, refType: 'parent_gift'));
      expect(await ledger.balance(), 5.0);
      expect(await ledger.countByRefType('task_checkin'), 0);
      expect(await ledger.countByRefType('parent_gift'), 1);

      // 切回默认孩子：余额与口径恢复自己的，且不含二娃的行。
      await account.switchTo(kChildIdDefault);
      expect(await ledger.balance(), 30.0);
      expect(await ledger.countByRefType('parent_gift'), 0);
      expect(await ledger.countByRefTypeAndRefIdOnDay(
          'task_checkin', 'x', _dayKey), 0);
      expect((await ledger.all()).map((e) => e.id), <String>['l_a1']);
    });

    test('F150 latestByRefType：返回指定 refType 最新一条 + 按孩子过滤',
        () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _,
        SunlightLocalRepository ledger,
        _, _, _
      ) = await build();
      addTearDown(database.close);

      SunlightEntry entryAt(String id, DateTime ts, String refType) =>
          SunlightEntry(
            id: id,
            ts: ts,
            type: SunlightType.earn,
            gross: 5,
            net: 5,
            balanceAfter: 5,
            refType: refType,
            refId: null,
            dayKey: _dayKey,
          );

      // 同 refType 两笔（时间乱序写入）+ 另一 refType 一笔。
      await ledger.append(entryAt('g_old', DateTime(2026, 10, 17, 8),
          'parent_gift'));
      await ledger.append(entryAt('t_1', DateTime(2026, 10, 17, 9),
          'task_checkin'));
      await ledger.append(entryAt('g_new', DateTime(2026, 10, 17, 12),
          'parent_gift'));

      final SunlightEntry? latest =
          await ledger.latestByRefType('parent_gift');
      expect(latest?.id, 'g_new', reason: '应取 ts 最新的那笔（非写入顺序）');

      // 孩子隔离：切到二娃 → 看不到大娃的赠予。
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);
      expect(await ledger.latestByRefType('parent_gift'), isNull,
          reason: '另一孩子的赠予记录绝不串读');
    });
  });

  group('C90 期 2 · focus_sessions 按孩子隔离', () {
    test('当日会话 / 区间查询 / 全量统计只算当前孩子', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _,
        _,
        FocusLocalRepository focus,
        _, _
      ) = await build();
      addTearDown(database.close);

      await focus.saveSession(_session('f_a1'));

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      expect(await focus.sessionsOfDay(_dayKey), isEmpty);
      expect(await focus.sessionsBetween(
          DateTime(2026, 10, 1), DateTime(2026, 11, 1)), isEmpty);
      expect(await focus.countValidFocusDaysLastWeek(_now), 0);
      final FocusStats stats = await focus.totalStats();
      expect(stats.totalSessions, 0, reason: '另一孩子的专注统计不计入');

      await focus.saveSession(_session('f_b1'));
      expect((await focus.sessionsOfDay(_dayKey)).map((s) => s.id),
          <String>['f_b1']);
      expect((await focus.totalStats()).totalSessions, 1);

      await account.switchTo(kChildIdDefault);
      expect((await focus.sessionsOfDay(_dayKey)).map((s) => s.id),
          <String>['f_a1']);
    });
  });

  group('C90 期 2 · tasks / check_ins 按孩子隔离', () {
    test('任务列表 / 打卡流水按孩子分开；家长核销 CAS 双保险', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _, _,
        _,
        TaskLocalRepository tasks,
        _
      ) = await build();
      addTearDown(database.close);

      await tasks.saveTask(_task('t_a1'));
      await tasks.checkIn(_checkIn('c_a1', 't_a1'));

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      expect(await tasks.tasks(), isEmpty,
          reason: '成长任务按孩子隔离：二娃初始任务清单为空（种子任务只挂默认孩子，报告已标注风险）');
      expect(await tasks.checkInsOfDay(_dayKey), isEmpty);
      expect(
          await tasks.checkInsByStatus(CheckInStatus.pending), isEmpty);
      expect(await tasks.checkInById('c_a1'), isNull,
          reason: '另一孩子的打卡按 id 读不到');
      expect(await tasks.totalCheckInCount(), 0);

      // 二娃自己的数据正常写入与读出。
      await tasks.saveTask(_task('t_b1'));
      await tasks.checkIn(_checkIn('c_b1', 't_b1'));
      expect((await tasks.tasks()).map((Task t) => t.id), <String>['t_b1']);
      expect(
          (await tasks.checkInsByStatus(CheckInStatus.pending))
              .map((CheckIn c) => c.id),
          <String>['c_b1']);

      // CAS 双保险：家长核销另一孩子的打卡 → where 带 childId 命中 0 行。
      expect(
        await tasks.resolveCheckInIfStatus(
          id: 'c_a1',
          from: CheckInStatus.pending,
          to: CheckInStatus.verified,
          sunlightGranted: 12,
          resolvedAt: _now,
        ),
        isFalse,
        reason: '跨孩子核销必须被 childId 过滤挡下（防误核销别人家的打卡）',
      );
      expect(
        await tasks.resolveCheckInIfStatus(
          id: 'c_b1',
          from: CheckInStatus.pending,
          to: CheckInStatus.verified,
          sunlightGranted: 12,
          resolvedAt: _now,
        ),
        isTrue,
      );

      await account.switchTo(kChildIdDefault);
      expect((await tasks.tasks()).map((Task t) => t.id), <String>['t_a1']);
      // c_a1 仍未被核销（上面跨孩子核销被挡下）。
      expect((await tasks.checkInById('c_a1'))!.status, CheckInStatus.pending);
    });

    test('删除任务按孩子过滤：删不动另一孩子的任务', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _, _,
        _,
        TaskLocalRepository tasks,
        _
      ) = await build();
      addTearDown(database.close);

      await tasks.saveTask(_task('t_a1'));
      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      await tasks.deleteTaskById('t_a1'); // 0 行
      await account.switchTo(kChildIdDefault);
      expect(await tasks.checkInById('t_a1'), isNull); // 打卡无此 id，仅为占位读
      expect(
        (await tasks.tasks()).map((Task t) => t.id),
        contains('t_a1'),
        reason: '删除按 childId 过滤，另一孩子的任务不受影响',
      );
    });
  });

  group('C90 期 2 · eye_care_logs 按孩子隔离', () {
    test('护眼统计只算当前孩子', () async {
      final (
        AccountService account,
        db.AppDatabase database,
        _, _, _, _,
        EyeCareLogLocalRepository eyeCare
      ) = await build();
      addTearDown(database.close);

      await eyeCare.append(_eyeCare('e_a1'));

      final ChildProfile second = await account.createChild('二娃', AgeTier.mid);
      await account.switchTo(second.id);

      expect(await eyeCare.countByResult(EyeCareResultType.completed), 0);
      expect(await eyeCare.watchedSecondsByResult(EyeCareResultType.completed),
          0);

      await eyeCare.append(_eyeCare('e_b1'));
      expect(await eyeCare.countByResult(EyeCareResultType.completed), 1);

      await account.switchTo(kChildIdDefault);
      expect(await eyeCare.countByResult(EyeCareResultType.completed), 1);
      expect(
          await eyeCare.watchedSecondsByResult(EyeCareResultType.completed),
          60);
    });
  });

  group('C90 期 2 · 未注入 AccountService 的仓储（既有单测路径）', () {
    test('行为与隔离前一致：写入落 kChildIdDefault，读取按默认孩子过滤', () async {
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

      // ⚠️ 不传 account：恒按 kChildIdDefault（Plan B 兼容语义）。
      final PlantLocalRepository plants = PlantLocalRepository(database);
      final SunlightLocalRepository ledger = SunlightLocalRepository(database);
      final TaskLocalRepository tasks = TaskLocalRepository(database);

      await plants.savePlant(_plant('p_stub'));
      await ledger.append(_entry('l_stub'));
      await tasks.saveTask(_task('t_stub'));

      // 即使 AccountService 当前活跃的是二娃，无 account 的仓储仍按默认孩子走。
      await account.switchTo(second.id);
      expect((await plants.plants()).map((Plant p) => p.id),
          <String>['p_stub']);
      expect(await ledger.balance(), greaterThan(0.0));
      expect((await tasks.tasks()).map((Task t) => t.id), <String>['t_stub']);
    });
  });
}
