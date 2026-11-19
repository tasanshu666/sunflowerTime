/// QA 独立复验 · 许愿树 A-T04 孩子端 UI（严过关 / 主理人派单的独立差分复验）。
///
/// 与工程师 50 条**不重复**：本文件只打**失败路径 / 边界 / 差分**——
///  · 历史今日：跨年边界（12-31 vs 01-01）、三段并集 + 主卡取 createdAt 最大 +
///    折叠 extras 倒序 + 今年/异日噪声不命中（真跑生产 provider，非照抄纯函数）；
///  · 频次：SettingsStore 按 childId 分键隔离（切孩子后 c1 的水位不影响 c2）；
///  · 里程碑幂等：初始 -1 → 0 播一次、同 stage 再进不播；
///  · 进度条：无目标整条不渲染（连文案消失）、有目标走绝对量且无 `%`、
///    fill 宽度 = 容器宽 × 百分比（比例断言不断言像素）；
///  · 收藏箱：入参即展示顺序、widget 不二次重排（仓储已 createdAt 倒序）；
///  · 源码守卫：花园入口追加在根 Stack 末尾 + 稳定 Key + 零购买入口、
///    `wishId==null` 徽标逐字节不变 + 异步补拉走 unawaited、双参互斥未被动、
///    页内 provider 只读组合服务不绕过经济隔离、A-T03 接线层文件未改。
///
/// 运行纪律：摘代理；禁并发。widget 宿主一律自带 Material 壳（工程师踩过
/// 裸 InkWell 无 Material 祖先的坑）。断言期望值写死，不引用实现常量。
library wish_ui_qa_test;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart'
    show
        AnniversaryResult,
        isAnniversaryMatch,
        shouldCelebrateMilestone,
        wishAnniversaryProvider;
import 'package:sunflower_time/presentation/child/widgets/wish_collection_box.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_progress_bar.dart';

// ── 测试替身（只读三段仓储；写方法 no-op，证明回顾只读） ───────────────────

/// 三段由测试直接注入，用于验证 provider 的「三段并集」确实横跨 mounted/boxed/pool。
class _QaWishRepo implements WishRepository {
  final List<Wish> mountedRows = <Wish>[];
  final List<Wish> boxedRows = <Wish>[];
  final List<Wish> poolRows = <Wish>[];

  int writeCalls = 0;

  @override
  Future<List<Wish>> mounted() async => List<Wish>.unmodifiable(mountedRows);

  @override
  Future<List<Wish>> boxed() async => List<Wish>.unmodifiable(boxedRows);

  @override
  Future<List<Wish>> pool() async => List<Wish>.unmodifiable(poolRows);

  @override
  Future<List<Wish>> abandoned() async => const <Wish>[];

  @override
  Future<List<Wish>> byStatuses(Set<WishStatus> statuses) async => const <Wish>[];

  @override
  Future<int> countByStatuses(Set<WishStatus> statuses) async => 0;

  @override
  Future<int> countStampedAchieved() async => 0;

  @override
  Future<Set<int>> occupiedSlots() async => const <int>{};

  @override
  Future<Wish?> byId(String id) async => null;

  @override
  Future<void> save(Wish wish) async => writeCalls++;

  @override
  Future<void> deleteAll() async => writeCalls++;
}

class _QaWishTasks implements WishTaskRepository {
  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async =>
      const <Task>[];

  @override
  Future<List<CheckIn>> checkInsOfTaskIds({required List<String> taskIds}) async =>
      const <CheckIn>[];

  @override
  Future<void> assignWish({required String taskId, required String wishId}) async {}

  @override
  Future<void> unassignWish({required String taskId}) async {}
}

class _QaTracking implements TrackingRepository {
  @override
  Future<void> track(TrackingEvent event) async {}

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      const <TrackingEvent>[];

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

WishOrchestrationService _serviceOf(_QaWishRepo repo) => WishOrchestrationService(
      wishes: repo,
      wishTasks: _QaWishTasks(),
      account: AccountService(),
      tracking: _QaTracking(),
    );

// ── 通用 ──────────────────────────────────────────────────────────────────

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Wish _wish({
  required String id,
  required DateTime createdAt,
  WishStatus status = WishStatus.pending,
  DateTime? releasedAt,
  DateTime? fulfilledAt,
  int? treeSlot,
  String text = '回礼貌物',
}) =>
    Wish(
      id: id,
      childId: 'qa-child',
      text: text,
      status: status,
      createdAt: createdAt,
      releasedAt: releasedAt,
      fulfilledAt: fulfilledAt,
      treeSlot: treeSlot,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AppLocalizations zh = AppLocalizationsZh();

  group('QA-A 历史今日 · 跨年边界（纯判据，固定日期独立期望）', () {
    final DateTime today = DateTime(2026, 1, 1, 9); // 元旦，专门打跨年边界

    test('QA-A1 去年 12-31 不命中今年 01-01（跨年相邻日不算同月同日）', () {
      expect(isAnniversaryMatch(_wish(id: 'd', createdAt: DateTime(2025, 12, 31)), today),
          isFalse);
    });

    test('QA-A2 前年 01-01 命中（年度回顾不看「只去年」）+ 未来年不命中', () {
      expect(isAnniversaryMatch(_wish(id: 'y2', createdAt: DateTime(2024, 1, 1)), today),
          isTrue, reason: '前年同月同日应命中');
      expect(isAnniversaryMatch(_wish(id: 'future', createdAt: DateTime(2027, 1, 1)), today),
          isFalse, reason: '未来年份绝不命中');
    });

    test('QA-A3 今年 01-01 不命中（今天刚许的不回顾）', () {
      expect(isAnniversaryMatch(_wish(id: 'now', createdAt: DateTime(2026, 1, 1)), today),
          isFalse);
    });
  });

  group('QA-B 历史今日 · 真跑生产 provider（三段并集 / 取最大 / extras 倒序 / 过滤）', () {
    test('QA-B1 三段各一条往年同日全部命中；主卡=createdAt 最大；extras 按 createdAt 倒序；噪声剔除',
        () async {
      // provider 内部用 DateTime.now()；用当天真实日期构造「同月同日」的往年愿望。
      final DateTime now = DateTime.now();
      // 闰日保护：2-29 在非闰年会被 DateTime 归一化，无法构造严格同月同日。
      if (now.month == 2 && now.day == 29) return;
      DateTime sameDayYearsAgo(int k) => DateTime(now.year - k, now.month, now.day, 8);

      final _QaWishRepo repo = _QaWishRepo()
        ..mountedRows.addAll(<Wish>[
          // 树上段命中：1 年前（应成为主卡）。
          _wish(id: 'tree', createdAt: sameDayYearsAgo(1), treeSlot: 0),
          // 噪声①：今年同日 → 不命中。
          _wish(id: 'this-year', createdAt: DateTime(now.year, now.month, now.day, 7)),
          // 噪声②：去年不同日 → 不命中。
          _wish(id: 'other-day', createdAt: sameDayYearsAgo(1).subtract(const Duration(days: 1))),
        ])
        ..boxedRows.add(
          // 收藏箱段命中：2 年前。
          _wish(id: 'box', createdAt: sameDayYearsAgo(2), releasedAt: DateTime(now.year - 1, 6, 1)),
        )
        ..poolRows.add(
          // 达成池段命中：3 年前。
          _wish(id: 'pool', createdAt: sameDayYearsAgo(3),
              status: WishStatus.fulfilled, fulfilledAt: DateTime(now.year - 2, 6, 1)),
        );

      final ProviderContainer container = ProviderContainer(overrides: <Override>[
        wishOrchestrationServiceProvider.overrideWithValue(_serviceOf(repo)),
      ]);
      addTearDown(container.dispose);

      final AnniversaryResult result = await container.read(wishAnniversaryProvider.future);

      expect(result.isEmpty, isFalse, reason: '三段并集必须有命中');
      expect(result.wish?.id, 'tree', reason: '主卡 = 命中中 createdAt 最大（最近往年）');
      expect(result.extras.map((Wish w) => w.id).toList(), <String>['box', 'pool'],
          reason: '折叠列表按 createdAt 倒序：2 年前 → 3 年前');
      expect(result.extraCount, 2, reason: '命中 3 条 ⇒ 折叠计数 = 3 − 1');
      expect(result.extras.map((Wish w) => w.id),
          isNot(containsAll(<String>['this-year', 'other-day'])),
          reason: '今年同日 / 去年异日噪声不得进入命中');
      expect(repo.writeCalls, 0, reason: 'A26.10.1 ③ 只读：回顾不得触发任何写');
    });

    test('QA-B2 无命中 ⇒ 空结果（主卡 null / 折叠 0），且三段无写入', () async {
      final _QaWishRepo repo = _QaWishRepo();
      final ProviderContainer container = ProviderContainer(overrides: <Override>[
        wishOrchestrationServiceProvider.overrideWithValue(_serviceOf(repo)),
      ]);
      addTearDown(container.dispose);

      final AnniversaryResult result = await container.read(wishAnniversaryProvider.future);
      expect(result.isEmpty, isTrue);
      expect(result.wish, isNull);
      expect(result.extraCount, 0);
      expect(repo.writeCalls, 0);
    });
  });

  group('QA-C 频次按 childId 隔离（切孩子后水位互不影响）', () {
    test('QA-C1 写 c1 今日 → c1 读出今日、c2 仍 null；两键名不同', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SettingsStore store = SettingsStore(await SharedPreferences.getInstance());

      expect(await store.wishAnniversaryShownOn(childId: 'c1'), isNull);
      expect(await store.wishAnniversaryShownOn(childId: 'c2'), isNull);

      await store.setWishAnniversaryShownOn(childId: 'c1', yyyyMmDd: '2026-03-07');

      expect(await store.wishAnniversaryShownOn(childId: 'c1'), '2026-03-07');
      expect(await store.wishAnniversaryShownOn(childId: 'c2'), isNull,
          reason: '切孩子后 c2 频次独立，不得被 c1 的水位挡住');
    });
  });

  group('QA-D 里程碑演出幂等', () {
    test('QA-D1 初始 -1 → 0 播一次；同 stage 再进不播；退档不播', () {
      expect(shouldCelebrateMilestone(0, -1), isTrue, reason: '首帧 0 > -1 播一次');
      expect(shouldCelebrateMilestone(0, 0), isFalse, reason: '同 stage 只播一次');
      expect(shouldCelebrateMilestone(2, 2), isFalse);
      expect(shouldCelebrateMilestone(1, 2), isFalse, reason: '退档不播');
    });

    test('QA-D2 源码守卫：写回 last 在 postFrame 且用 notifier.state（页级 StateProvider）', () {
      final String src = File('lib/presentation/child/pages/wish_tree_page.dart').readAsStringSync();
      expect(src, contains('addPostFrameCallback'), reason: '写回 last 延后一帧，避免 build 期改 provider');
      expect(src, contains('wishLastMilestoneProvider.notifier).state = milestone'),
          reason: '幂等写回页级 provider');
      expect(RegExp(r'if \(milestone > last\)').hasMatch(src), isTrue,
          reason: '幂等闸门 current > last');
    });
  });

  group('QA-E 进度条失败路径', () {
    testWidgets('QA-E1 targetValue=0 整条不渲染（连进度文案一起消失）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const WishProgressBar(
        mode: WishGoalMode.focusMinutes,
        targetValue: 0,
        progressValue: 5,
      )));
      expect(find.byKey(const Key('wish_progress_bar')), findsNothing);
      expect(find.byKey(const Key('wish_progress_label')), findsNothing);
      expect(find.byKey(const Key('wish_progress_track')), findsNothing);
    });

    testWidgets('QA-E2 有目标：fill 宽 = 容器宽 × 百分比（比例断言）；绝对量文案不含 %',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 200,
        child: WishProgressBar(
          mode: WishGoalMode.focusMinutes,
          targetValue: 100,
          progressValue: 25,
        ),
      )));
      final double trackW = tester.getSize(find.byKey(const Key('wish_progress_track'))).width;
      final double fillW = tester.getSize(find.byKey(const Key('wish_progress_fill'))).width;
      expect(trackW, greaterThan(0));
      expect(fillW / trackW, closeTo(0.25, 0.01), reason: '25/100 ⇒ fill 占容器 25%，不写死像素');

      final Text label = tester.widget<Text>(find.byKey(const Key('wish_progress_label')));
      expect(label.data, contains('25'));
      expect(label.data, contains('75'));
      expect(label.data, isNot(contains('%')), reason: 'v0.4 不变式：文案不含百分号');
    });

    testWidgets('QA-E3 mode1 任务条数口径文案走绝对量、不含 %', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        width: 180,
        child: WishProgressBar(
          mode: WishGoalMode.taskCount,
          targetValue: 4,
          progressValue: 1,
        ),
      )));
      final Text label = tester.widget<Text>(find.byKey(const Key('wish_progress_label')));
      expect(label.data, contains('1'));
      expect(label.data, contains('3'));
      expect(label.data, isNot(contains('%')));
    });
  });

  group('QA-F 收藏箱展示顺序（入参即展示；widget 不二次重排）', () {
    testWidgets('QA-F1 三段入参顺序原样渲染，widget 内无 sort 改写', (WidgetTester tester) async {
      final List<Wish> wishes = <Wish>[
        _wish(id: 'new', createdAt: DateTime(2025, 5, 1), text: '最新'),
        _wish(id: 'mid', createdAt: DateTime(2024, 5, 1), text: '中间'),
        _wish(id: 'old', createdAt: DateTime(2023, 5, 1), text: '最早'),
      ];
      await tester.pumpWidget(_host(SizedBox(
        width: 320,
        height: 600,
        child: WishCollectionBox(wishes: wishes, t: zh),
      )));
      final double yNew = tester.getTopLeft(find.byKey(const Key('wish_collection_tile_new'))).dy;
      final double yMid = tester.getTopLeft(find.byKey(const Key('wish_collection_tile_mid'))).dy;
      final double yOld = tester.getTopLeft(find.byKey(const Key('wish_collection_tile_old'))).dy;
      expect(yNew, lessThan(yMid), reason: 'createdAt 更晚的在上面');
      expect(yMid, lessThan(yOld));

      final String boxSrc =
          File('lib/presentation/child/widgets/wish_collection_box.dart').readAsStringSync();
      expect(boxSrc, isNot(contains('.sort(')), reason: '收藏箱 widget 只读展示，不再重排');
    });
  });

  group('QA-G 源码守卫 · 花园入口 / 徽标逐字节 / 双参互斥 / 接线层未破坏', () {
    test('QA-G1 花园入口收进右上角单簇 + 稳定 Key + 孩子端零购买入口', () {
      final String src = File('lib/presentation/child/pages/garden_page.dart').readAsStringSync();
      // v0.3.0（R3-P0-11）：入口从「左下角木牌上方热点」收进右上角单簇。
      expect(src, contains('kWishTreeTopClusterKey'), reason: '整簇稳定 Key');
      expect('WishTopEntryCluster('.allMatches(src).length, 2,
          reason: '簇只有两个：天气 + 许愿树（不得再有第三处并列定位）');
      expect(src, isNot(contains('WishTreeHotspot(')),
          reason: 'v0.3 减法：左下角旧热点已整体删除（Key 常量保留供旧断言引用）');
      expect(src, contains("context.push('/wish-tree')"), reason: '只 push 许愿树页');
      expect(src, isNot(contains('/parent/premium')), reason: '孩子端零购买入口');
      expect(src, isNot(contains('buyLifetime')));
      // 根因守卫：右上角必须是**单个 Positioned + Column**，
      // 不允许再出现「多个并列 Positioned 各自用未缩放常量算 top」。
      final int pos = src.indexOf('key: kWishTreeTopClusterKey');
      expect(pos, greaterThan(0), reason: '簇的 Positioned 带 Key');
      final int from = pos - 200 < 0 ? 0 : pos - 200;
      final String around = src.substring(from, pos + 1200);
      expect(around, contains('Positioned('), reason: '簇由单个 Positioned 定位');
      expect(around, contains('Column('), reason: '堆叠交给 Column，不留给常量');
      expect(src, isNot(contains('gardenDebugEntryTop(')),
          reason: '旧「手工 top 偏移」函数已废弃（调试入口随簇自然顺延）');
    });

    test('QA-G2 wishId==null 徽标逐字节不变 + 异步补拉走 unawaited（回归修复落点）', () {
      final String src =
          File('lib/presentation/child/pages/child_task_page.dart').readAsStringSync();
      expect(src, contains('if (item.task.wishId != null)'),
          reason: '徽标仅 wishId != null 时插入 ⇒ 普通成长任务逐字节不变');
      expect(src, contains('unawaited(_loadWishTitlesThenSet())'),
          reason: '愿望标题异步补拉不得阻塞 board 的 pump 时序（完美日/打卡回归修复）');
      expect(src, contains('Future<Map<String, String>> _loadWishTitles()'),
          reason: '补拉走独立只读方法，零新增服务方法');
      // 徽标插入点在 _dailyBadge 之后、标题 Text 之前，且被 if 包裹（非无条件）。
      final int badgeAt = src.indexOf('WishTaskBadge(');
      final String before = src.substring(badgeAt - 160, badgeAt);
      expect(before, contains('if (item.task.wishId != null)'),
          reason: 'WishTaskBadge 紧随非空判据，无裸调用');
    });

    test('QA-G3 双参互斥未被动：?task= 优先、wishTask 冲突置 null + warning', () {
      final String src = File('lib/shared/app_router.dart').readAsStringSync();
      final int focusStart = src.indexOf("path: '/focus'");
      expect(focusStart, greaterThan(-1));
      final String focus = src.substring(focusStart, focusStart + 3200);
      // 独立期望（不照抄 A-T03 guard 的断言串）：task 先读、冲突合取、wishTask 置空。
      expect(focus.indexOf("queryParameters['task']"),
          lessThan(focus.indexOf("queryParameters['wishTask']")),
          reason: '?task= 先读，既有链路优先');
      expect(RegExp(r'hasTask\s*&&\s*hasWishTask').hasMatch(focus), isTrue,
          reason: '冲突 = 两参都带');
      expect(RegExp(r'wishTaskId:\s*wishTaskConflict\s*\?\s*null\s*:\s*wishTaskId').hasMatch(focus),
          isTrue, reason: '冲突时丢弃 wishTask，走 ?task=');
      expect(focus, contains('wish_focus_conflict'), reason: '冲突埋点/warning 仍在');
    });

    test('QA-G4 页内 provider 只读组合既有服务、不绕过经济隔离；A-T03 接线层文件未改', () {
      final String page =
          File('lib/presentation/child/pages/wish_tree_page.dart').readAsStringSync();
      // 页级 provider 全部是读方法；写只经 orchestration 服务的既有公开方法。
      for (final String read in <String>[
        '.boxedWishes()',
        '.poolWishes()',
        '.tasksOf(',
        '.stampedAchievedCount()',
        '.mountedWishes()',
      ]) {
        expect(page, contains(read), reason: '页内以既有读方法组合，未自造仓储查询');
      }
      expect(page, isNot(contains('.save(')), reason: '页内不得绕过服务直接写库');
      expect(page, isNot(contains('economyRevisionProvider.notifier')),
          reason: '不得在页内自增/篡改修订号总线（A-T03 economyRevisionProvider 只读订阅）');
      // 改动文件清单不含 A-T03 孩子端接线层文件（工作区 diff 复验）。
      // 家长端 state/wish_state.dart 已在 v0.4 随「今日页愿望展示」整体删除。
      final ProcessResult diff = Process.runSync(
        'git', <String>['diff', '--name-only', 'HEAD'],
        workingDirectory: Directory.current.path,
      );
      final List<String> changed = (diff.stdout as String).split('\n');
      expect(
        changed.any((String p) => p.endsWith('child/state/wish_state.dart')),
        isFalse,
        reason: 'A-T03 孩子端接线层 state 文件必须与 HEAD 逐字节一致：v0.3 回退已把 '
            'v0.2 的 wishShareRevisionProvider watch 整体移除，文件内容回到 '
            'HEAD 原样 ⇒ 工作区 diff 为空（本批应绿，不是豁免）',
      );
      expect(
        File('lib/presentation/parent/state/wish_state.dart').existsSync(),
        isFalse,
        reason: 'v0.4 家长端今日页愿望展示已整块移除，专属 provider 文件不得残留',
      );
    });

    test('QA-G5 零新增列 / 索引 / tab：schema 与 5-tab 既有守卫保持断言', () {
      // 本批只新增 UI widget + SettingsStore KV 键；数据库快照 / tab 数由既有
      // migration 测试与 child_tab_refresh_test 覆盖。此处仅确认本批未触碰 schema。
      final ProcessResult diff = Process.runSync(
        'git', <String>['diff', '--name-only', 'HEAD', '--', 'lib/data/local/database'],
        workingDirectory: Directory.current.path,
      );
      final String changed = diff.stdout as String;
      expect(changed.trim(), isEmpty,
          reason: 'schemaVersion / 列 / 索引文件由 v0.2→v0.3 批次合法改动'
              '（回退到 22 列 / 4 索引 / schemaVersion 32）；'
              '本断言校验 git diff HEAD，待新 HEAD 提交后自然复绿');
      final String routerSrc = File('lib/shared/app_router.dart').readAsStringSync();
      expect(routerSrc, contains("path: '/wish-tree'"), reason: '许愿树是 push 路由，不是新 tab');
    });
  });
}
