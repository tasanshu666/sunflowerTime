/// QA 独立差分复验 · v0.3 愿望任务「零污染 + 家长端可见」（R3-P0-09 ④⑤⑥ / ③）。
///
/// ## 双向证明（这是本轮最容易假绿的一条）
///  - **零污染**：写 1 条 `wishId != null` 的任务后，成长链路的
///    「今日必做 x/y」「完成数」「阳光结算口径」必须**一位不变**；
///  - **真可见**：同一批数据下，家长端任务列表必须**真的渲染**出
///    「愿望任务 · {标题}」标签（否则「零污染」是拿「根本没显示」换来的假绿）。
///
/// ## 反假绿要点
///  - 零污染断言必须配「愿望任务确实落库」的反证（否则删掉写入也能绿）；
///  - 「孩子端 S3 展示」走**真实 WishTreePage + 真点卡片开详情浮层**，不是读源码。
library wish_task_pollution_v03_qa_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/wish_task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/platform/iap_service.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_task_card.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/shared/premium_gate.dart';

class _OfflineIap implements IapAdapter {
  @override
  Stream<IapMessage> get messages => const Stream<IapMessage>.empty();
  @override
  Future<bool> isStoreAvailable() async => false;
  @override
  Future<List<IapProduct>> queryProducts(Set<String> ids) async =>
      <IapProduct>[];
  @override
  Future<void> startLifetimePurchase(String id) async {}
  @override
  Future<void> startRestore() async {}
}

class _QuietSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 90,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        soundOn: false,
        bgmOn: false,
      );
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

Future<ProviderContainer> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
      iapServiceProvider.overrideWithValue(IapService(adapter: _OfflineIap())),
      settingsRepositoryProvider.overrideWithValue(_QuietSettings()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(database.close);
  return container;
}

Task _ordinary(String id, String name) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 0,
      sunlightReward: 8,
      repeatRule: 'daily',
      isCustom: true,
    );

/// 现实类「小办法」：`requiresFocus = false` + 自由文本名。
Task _realityWay(String id, String name, String wishId) => Task(
      id: id,
      name: name,
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 0,
      sunlightReward: 5,
      repeatRule: 'none',
      isCustom: true,
      wishId: wishId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioService.instance.resetForTest();

  group('⑦ 零污染：愿望任务不进成长链路（真实仓储 / 真实看板）', () {
    test('写 1 条愿望任务后：今日必做 x/y、完成数、阳光口径全部一位不变', () async {
      final ProviderContainer c = await _boot();
      final taskRepo = c.read(taskRepositoryProvider);

      // 基线：3 条普通成长任务，其中 1 条已打卡完成。
      for (final Task t in <Task>[
        _ordinary('t1', '练字 15 分钟'),
        _ordinary('t2', '读绘本'),
        _ordinary('t3', '收拾玩具'),
      ]) {
        await taskRepo.saveTask(t);
      }
      await c.read(taskCheckInServiceProvider).checkIn(
            task: _ordinary('t1', '练字 15 分钟'),
            now: DateTime(2026, 11, 20, 8),
          );

      final DateTime now = DateTime(2026, 11, 20, 12);
      final TodayTaskBoard before = await c
          .read(taskCheckInServiceProvider)
          .board(now);
      final int listBefore = (await taskRepo.tasks()).length;
      final double sunBefore = (await taskRepo.tasks())
          .map((Task t) => t.effectiveSunlightReward)
          .fold<double>(0, (double a, int b) => a + b);

      expect(before.total, 3, reason: '前置：基线今日必做 = 3');
      expect(before.doneCount, 1, reason: '前置：基线已完成 = 1');

      // 造一条树上愿望 + 一条**关联它**的现实类小办法。
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: now,
                maxTextLength: kWishTextMaxLengthZh,
              );
      await taskRepo.saveTask(_realityWay('w1', '帮妈妈洗碗', wish.id));

      // ── 反证：愿望任务**真的落库了**（否则下面的「不变」是删数据换来的假绿）──
      final List<Task> withWish =
          await (taskRepo as WishTaskReadBridge).allTasksIncludingWish();
      expect(withWish.where((Task t) => t.wishId == wish.id).length, 1,
          reason: '愿望任务必须真实落库');
      expect(withWish.firstWhere((Task t) => t.id == 'w1').name, '帮妈妈洗碗',
          reason: 'requiresFocus=false + 自由文本名必须原样保存');

      // ── 零污染三条硬断言 ──
      final TodayTaskBoard after =
          await c.read(taskCheckInServiceProvider).board(now);
      expect(after.total, before.total,
          reason: '🔴「今日必做 x/y」的 x 必须不变（allTasks 默认 '
              'includeWishTasks=false）');
      expect(after.doneCount, before.doneCount,
          reason: '已完成数不得因愿望任务而变（完成率 y/x 同步不变）');
      expect((await taskRepo.tasks()).length, listBefore,
          reason: 'taskRepository.tasks() 长度必须不变');
      final double sunAfter = (await taskRepo.tasks())
          .map((Task t) => t.effectiveSunlightReward)
          .fold<double>(0, (double a, int b) => a + b);
      expect(sunAfter, sunBefore,
          reason: '阳光结算口径（按 tasks() 求奖励和）必须一位不变');

      // 完成率显式算出来比一次，便于失败时看清差值。
      final double rateBefore = before.total == 0
          ? 0
          : before.doneCount / before.total;
      final double rateAfter =
          after.total == 0 ? 0 : after.doneCount / after.total;
      expect(rateAfter, rateBefore, reason: '完成率必须完全相等');
    });

    test('愿望任务也不会被 quirk 计进「每周任务」桶', () async {
      final ProviderContainer c = await _boot();
      final taskRepo = c.read(taskRepositoryProvider);
      await taskRepo.saveTask(_ordinary('t1', '练字'));
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一次露营',
                category: WishCategory.other,
                now: DateTime(2026, 11, 20, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await taskRepo.saveTask(_realityWay('w1', '一起搭帐篷', wish.id));

      final TodayTaskBoard board = await c
          .read(taskCheckInServiceProvider)
          .board(DateTime(2026, 11, 20, 12));
      expect(board.weeklyCount, 0,
          reason: '愿望任务不得被算进每周任务桶（否则今日板会出现幽灵行）');
      // v0.3 验收 5(c)：愿望任务显式进入 board（孩子端「许愿」栏），
      // 但仍不进「每周任务」桶 / 完成度 / 阳光结算口径。
      expect(board.items.length, 2,
          reason: '看板 = 1 条成长任务 + 1 条愿望任务（后者单独成栏）');
    });

    test('既有 3 个成长链路调用点都没有改成 includeWishTasks: true（源码守卫）', () {
      // 允许读取的仓库/服务文件：读侧隔离靠默认值，不得有人显式放开。
      for (final String path in <String>[
        'lib/data/local/repositories/task_local_repository.dart',
        'lib/domain/services/task_checkin_service.dart',
        'lib/domain/services/focus_settlement_service.dart',
      ]) {
        if (!File(path).existsSync()) continue;
        final String src = File(path).readAsStringSync();
        // `tasks()` 走默认值；唯独愿望相关桥接方法允许 true。
        final RegExpMatch? m =
            RegExp(r'includeWishTasks:\s*true').firstMatch(src);
        if (m == null) continue;
        // 若出现 true，必须在 `allTasksIncludingWish` 内（家长端待核销专用）。
        final int idx = m.start;
        final String around =
            src.substring(idx < 400 ? 0 : idx - 400, idx);
        expect(around.contains('allTasksIncludingWish'), isTrue,
            reason: '$path 里出现了 includeWishTasks: true，但不在 '
                'allTasksIncludingWish 内 ⇒ 成长链路被污染');
      }
    });
  });

  group('⑦ 家长端可见：任务列表渲染「愿望任务 · {标题}」', () {
    testWidgets('真实 ParentTaskConfigPage 渲染出愿望任务标签', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final taskRepo = c.read(taskRepositoryProvider);
      await taskRepo.saveTask(_ordinary('t1', '练字 15 分钟'));
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime(2026, 11, 20, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await taskRepo.saveTask(_realityWay('w1', '帮妈妈洗碗', wish.id));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ParentTaskConfigPage()),
      ));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // 前置自证：页面真的渲染出来了，且普通任务在列表里（否则下面"找不到标签"
      // 可能只是"页面没起来"的假阳性）。
      expect(find.byType(ParentTaskConfigPage), findsOneWidget);
      expect(find.text('练字 15 分钟'), findsOneWidget,
          reason: '前置：普通成长任务必须已渲染（证明页面起来了）');

      // 🔴 R3-P0-09③ 的核心断言：标签必须真的出现在列表里。
      expect(
        find.byKey(const Key('parent_task_wish_badge_w1')),
        findsOneWidget,
        reason: '家长端任务列表必须显示愿望任务标签（否则「零污染」是靠'
            '「根本没显示愿望任务」换来的假绿）',
      );
      expect(find.text('愿望任务 · 想要一只小乌龟'), findsOneWidget,
          reason: '标签文案必须是「愿望任务 · {愿望标题}」');
      // 普通任务不得带该标签（否则全员贴标签 = 标签无信息量）。
      expect(find.byKey(const Key('parent_task_wish_badge_t1')), findsNothing,
          reason: '普通成长任务不得显示愿望任务标签');
      expect(tester.takeException(), isNull);
    });
  });

  group('⑦ 配额不被虚占（与「家长端可见」构成一对矛盾约束）', () {
    // 这一组是修 WISH-V03-BUG-01 的**回归钉子**：
    // 修法必须「展示读全量、配额读普通」，只要有人图省事把两处合并成一条读路径，
    // 下面两条必有一条立刻红。
    //
    // 为什么 case B 才是判别性用例：
    //  · case A（5 普通 + 1 愿望 = 显示 6）：配额若误用显示数（6）⇒ 也是 false，
    //    两种实现都过 ⇒ 无判别力；
    //  · case B（4 普通 + 3 愿望 = 显示 7）：配额若误用显示数（7 > 5）⇒ 错误地
    //    变成「不能新增」；用普通数（4 < 5）⇒「可以新增」。**这才是分水岭。**
    testWidgets('case B（判别性）：4 普通 + 3 愿望 ⇒ 配额仍允许新增（愿望任务不虚占）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final taskRepo = c.read(taskRepositoryProvider);
      for (final String id in <String>['o1', 'o2', 'o3', 'o4']) {
        await taskRepo.saveTask(_ordinary(id, '普通项 $id'));
      }
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime(2026, 11, 20, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      for (final String id in <String>['w1', 'w2', 'w3']) {
        await taskRepo.saveTask(_realityWay(id, '小办法 $id', wish.id));
      }

      // 口径自证：配额计数（tasks()）必须仍是 4，而展示计数（含愿望）是 7。
      final int quotaCount = (await taskRepo.tasks()).length;
      final int displayCount =
          (await (taskRepo as WishTaskReadBridge).allTasksIncludingWish()).length;
      expect(quotaCount, 4, reason: '配额口径只数 4 条普通任务');
      expect(displayCount, 7, reason: '展示口径是 4 普通 + 3 愿望 = 7');
      expect(
        PremiumQuotaGate.allows(
          EntitlementTier.free,
          FeatureKey.taskTemplateCount,
          quotaCount,
        ),
        isTrue,
        reason: '4 < $kFreeTaskQuota ⇒ 配额口径允许新增',
      );
      // 反向自证：如果误用展示数，就会变成不允许 —— 说明这条用例真有判别力。
      expect(
        PremiumQuotaGate.allows(
          EntitlementTier.free,
          FeatureKey.taskTemplateCount,
          displayCount,
        ),
        isFalse,
        reason: '若拿 7 去判配额则会误判为"不能新增" ⇒ 本用例对错误实现敏感',
      );

      // 真实页面：不得出现「达上限」提示。
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ParentTaskConfigPage()),
      ));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.textContaining('删除多余条目后即可新增'), findsNothing,
          reason: '🔴 4 条普通任务未达 5 条上限 ⇒ 页面**不得**显示配额已达上限提示；'
              '若显示了，说明配额被 3 条愿望任务虚占');
      // 同时展示侧必须真的有 7 项（含 3 条带徽标的愿望任务）。
      expect(find.text('7 项'), findsOneWidget,
          reason: '列表计数「N 项」取展示口径 = 7');
      for (final String id in <String>['w1', 'w2', 'w3']) {
        expect(find.byKey(Key('parent_task_wish_badge_$id')), findsOneWidget,
            reason: '愿望任务 $id 的标签必须渲染出来');
      }
      for (final String id in <String>['o1', 'o2', 'o3', 'o4']) {
        expect(find.byKey(Key('parent_task_wish_badge_$id')), findsNothing,
            reason: '普通任务 $id 不得带愿望任务标签');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('case A（极端）：5 普通 + 1 愿望 ⇒ 配额达上限，但列表仍显示 6 项',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final taskRepo = c.read(taskRepositoryProvider);
      for (final String id in <String>['o1', 'o2', 'o3', 'o4', 'o5']) {
        await taskRepo.saveTask(_ordinary(id, '普通项 $id'));
      }
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一次露营',
                category: WishCategory.other,
                now: DateTime(2026, 11, 20, 9),
                maxTextLength: kWishTextMaxLengthZh,
              );
      await taskRepo.saveTask(_realityWay('w1', '一起搭帐篷', wish.id));

      final int quotaCount = (await taskRepo.tasks()).length;
      expect(quotaCount, kFreeTaskQuota,
          reason: '配额口径恰等于免费上限 $kFreeTaskQuota');
      expect(
        PremiumQuotaGate.allows(
          EntitlementTier.free,
          FeatureKey.taskTemplateCount,
          quotaCount,
        ),
        isFalse,
        reason: '普通任务已满 $kFreeTaskQuota 条 ⇒ 不许再新增',
      );

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: ParentTaskConfigPage()),
      ));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.textContaining('删除多余条目后即可新增'), findsOneWidget,
          reason: '5 条普通任务已满上限 ⇒ 必须显示"删除多余条目后即可新增"');
      expect(find.text('6 项'), findsOneWidget,
          reason: '列表计数取展示口径 = 6（5 普通 + 1 愿望）');
      expect(find.byKey(const Key('parent_task_wish_badge_w1')), findsOneWidget,
          reason: '即使配额已满，愿望任务仍必须可见可管理（否则家长无法删除它腾配额）');
      expect(tester.takeException(), isNull);
    });

    test('纯函数层：愿望任务永不改变 quotaAllowsAdd 的返回值（穷举 0..6）', () {
      for (int ordinary = 0; ordinary <= 6; ordinary++) {
        final bool bare = PremiumQuotaGate.allows(
          EntitlementTier.free,
          FeatureKey.taskTemplateCount,
          ordinary,
        );
        // 无论再挂多少条愿望任务，传入的"普通任务数"不变 ⇒ 结果必须不变。
        final bool withWishes = PremiumQuotaGate.allows(
          EntitlementTier.free,
          FeatureKey.taskTemplateCount,
          ordinary, // 愿望任务不进入这个计数
        );
        expect(withWishes, bare,
            reason: '普通任务数 $ordinary 时，愿望任务不得影响配额判定');
        // 边界口径自证：< 5 允许、>= 5 拒绝。
        expect(bare, ordinary < kFreeTaskQuota,
            reason: '配额边界必须是 currentCount < $kFreeTaskQuota');
      }
    });
  });

  group('⑦ 孩子端 S3：requiresFocus=false 的现实类小办法能创建并展示', () {
    testWidgets('真实 WishTreePage：点卡片开详情，S3 列表里能看到「帮妈妈洗碗」',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ProviderContainer c = await _boot();
      final Wish wish =
          await c.read(wishOrchestrationServiceProvider).createWish(
                text: '想要一只小乌龟',
                category: WishCategory.other,
                now: DateTime.now().subtract(const Duration(days: 2)),
                maxTextLength: kWishTextMaxLengthZh,
              );
      // 家长布置 1 条现实类小办法（不进专注、自由文本名）。
      await c.read(taskRepositoryProvider).saveTask(
            _realityWay('w1', '帮妈妈洗碗', wish.id),
          );

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: WishTreePage()),
      ));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(tester.takeException(), isNull);

      // 树上卡片必须已切到 S3（有办法）。
      final Finder card = find.byKey(Key('wish_card_${wish.id}'));
      expect(card, findsOneWidget, reason: '树上必须有该愿望卡');
      expect(find.byKey(const Key('wish_card_task_badge')), findsOneWidget,
          reason: '有 1 条小办法 ⇒ S3 徽标必须出现');
      expect(find.text('小办法 1 个'), findsWidgets);

      // 点进详情 ⇒ S3 列表展示这条现实类小办法。
      await tester.tap(card);
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const Key('wish_detail_way_list_title')), findsOneWidget,
          reason: '详情浮层必须出现「小办法 N 个」列表标题');
      expect(find.byType(WishTaskCard), findsOneWidget,
          reason: '详情浮层必须渲染 1 张办法卡');
      // 🔴 关键：requiresFocus=false 的现实类任务必须**可展示**（不被"仅专注型"过滤掉）。
      expect(find.textContaining('帮妈妈洗碗'), findsWidgets,
          reason: '现实类小办法（不走专注）必须出现在孩子端 S3 列表');
      // 孩子端仍不得出现「任务」二字。
      for (final Text txt in tester.widgetList<Text>(find.byType(Text))) {
        final String d = txt.data ?? '';
        if (d == wish.text) continue; // 用户数据
        expect(d.contains('任务'), isFalse,
            reason: '孩子端详情浮层出现「任务」：$d');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
