/// QA 严过关（Yan）· 许愿树 v0.2 三条改动【独立验证】
///
/// 与工程师自测完全独立编写：领域用例全部跑在**真实 in-memory Drift 库 +
/// 真实仓储 / 真实服务装配**上，不复用工程师 Fake；断言用独立取值写死，
/// 不引用被测实现的中间变量。覆盖 team-lead 要求的 6 条核心断言：
///  - Y1 显式进池真闭环（targetValue==0 手动任务型，真实 Drift）；
///  - Y2 门控拦截 + 防误报（status 不变 / 不发 fulfilled 埋点）；
///  - Y3 按钮两态互斥 + 蛋联动（纯函数真值表 + WishCardDetail widget 双层）；
///  - Y4 iPhone 缩放 + iPad 逐字节不变（compactScaleFor / 图2 / 图3）；
///  - Y5 既有天气测试期望值改动审查（逐 hunk diff 审计，见本轮 QA 报告）；
///  - Y6 v0.1 零回归（六路径门控 / target>=1 自动进池 / 普通任务 / 冻结契约）。
///
/// 受控变异对照：临时摘掉 putIntoPool 的 _tryComplete 门控 / emit 守卫 /
/// 蛋判据 tasksAllDone / iPad 分支后，对应用例必须转 RED（见 QA 报告）。
library wish_v02_yan_independent_test;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/focus_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/sunlight_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/wish_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/repositories/tracking_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/wish_face_state.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/wish_tree_page.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_card_detail.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_top_entry_cluster.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_scene.dart';
import 'package:sunflower_time/presentation/child/widgets/wish_tree_weather_entry.dart';
import 'package:sunflower_time/shared/responsive.dart';

final DateTime kYanNow = DateTime(2026, 11, 22, 10, 30);
final AppLocalizations kYanT = AppLocalizationsZh();

// ── 独立数据工厂（取值与工程师用例刻意不同）────────────────────────────────

Task _yanTask(
  String id, {
  required String? wishId,
  required bool focus,
  int minFocusMin = 15,
}) =>
    Task(
      id: id,
      name: 'Yan任务-$id',
      subject: TaskSubject.general,
      requiresFocus: focus,
      minFocusMin: minFocusMin,
      sunlightReward: 9,
      isCustom: true,
      wishId: wishId,
    );

Wish _yanWish(
  String id, {
  required String text,
  int target = 0,
  int progress = 0,
  int treeSlot = 0,
  WishGoalMode mode = WishGoalMode.taskCount,
}) =>
    Wish(
      id: id,
      childId: kChildIdDefault,
      text: text,
      createdAt: DateTime(2026, 11, 19),
      treeSlot: treeSlot,
      targetMode: mode,
      targetValue: target,
      progressValue: progress,
    );

CheckIn _yanCheckIn(
  String id,
  String taskId, {
  CheckInStatus status = CheckInStatus.verified,
}) =>
    CheckIn(
      id: id,
      taskId: taskId,
      date: kYanNow,
      completedAt: kYanNow,
      isPerfectDay: false,
      status: status,
      sunlightGross: 0.0,
      sunlightGranted: 0.0,
    );

FocusSession _yanSession(String id, double minutes) => FocusSession(
      id: id,
      start: kYanNow.subtract(Duration(minutes: minutes.round())),
      end: kYanNow,
      plannedMin: minutes.round(),
      actualFocusMin: minutes,
      status: FocusStatus.completed,
      sunlightEarned: minutes,
      createdAt: kYanNow,
    );

/// 埋点录制器（真实 repository 接口，记录全部 event 供精确计数）。
class _YanTracking implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];

  @override
  Future<void> track(TrackingEvent event) async => events.add(event);

  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType type) async =>
      events.where((TrackingEvent e) => e.type == type).toList();

  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';

  List<TrackingEvent> ofKind(String kind) => events
      .where((TrackingEvent e) => e.payload['kind'] == kind)
      .toList();
}

class _YanFx {
  _YanFx(this.database, this.tasks, this.wishes, this.ledger, this.os,
      this.checkIns, this.tracking);

  final db.AppDatabase database;
  final TaskLocalRepository tasks;
  final WishLocalRepository wishes;
  final SunlightLocalRepository ledger;
  final WishOrchestrationService os;
  final TaskCheckInService checkIns;
  final _YanTracking tracking;
}

Future<_YanFx> _yanFx() async {
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  final TaskLocalRepository tasks = TaskLocalRepository(database);
  final WishLocalRepository wishes = WishLocalRepository(database);
  final SunlightLocalRepository ledger = SunlightLocalRepository(database);
  final _YanTracking tracking = _YanTracking();
  final WishOrchestrationService os = WishOrchestrationService(
    wishes: wishes,
    wishTasks: tasks,
    account: AccountService(),
    tracking: tracking,
  );
  final TaskCheckInService checkIns = TaskCheckInService(
    tasks: tasks,
    ledger: ledger,
    focus: FocusLocalRepository(database),
    settings: SettingsLocalRepository(database),
    wishTasks: tasks,
    wishFocusWriter: tasks,
    onWishEvent: (String wishId, WishEventKind kind, DateTime now) =>
        os.emitCrossEndEvent(wishId: wishId, kind: kind, now: now),
    onWishCheckInVerified: (Task task, CheckIn checkIn, DateTime now) =>
        os.registerCheckIn(
      wishId: task.wishId ?? '',
      checkIn: checkIn,
      task: task,
      now: now,
    ),
  );
  addTearDown(database.close);
  return _YanFx(database, tasks, wishes, ledger, os, checkIns, tracking);
}

Widget _yanHost(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // Y1 · 显式进池真闭环（真实 Drift，targetValue==0 手动任务型）
  // ═══════════════════════════════════════════════════════════════════════
  group('Y1 显式进池真闭环（真实 Drift）', () {
    test('家长确认后不自动进池 → putIntoPool 一次成真：fulfilled/Progress/盖章+1/清树位/进池/恰好1埋点/0阳光',
        () async {
      final _YanFx f = await _yanFx();
      await f.wishes.save(
          _yanWish('Y_W_PLANE', text: '想要一架小飞机', target: 0));
      await f.tasks.saveTask(
          _yanTask('Y_T_FLY', wishId: 'Y_W_PLANE', focus: false));

      // 孩子提交 → pending；家长核销 → verified（target==0 闸门拦，不自动进池）。
      final Task task = (await f.tasks.wishTaskById('Y_T_FLY'))!;
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kYanNow);
      expect(child.status, CheckInStatus.pending);
      final TaskCheckInOutcome verified =
          await f.checkIns.verifyCheckIn(child.checkInId, kYanNow);
      expect(verified.status, CheckInStatus.verified);

      Wish mid = (await f.wishes.byId('Y_W_PLANE'))!;
      expect(mid.status, WishStatus.pending,
          reason: '根因复现：targetValue==0 家长确认仍挂树');
      expect(mid.treeSlot, 0, reason: '仍占挂载位');
      expect(f.tracking.ofKind('fulfilled'), isEmpty,
          reason: '自动进池未发生，未发达成埋点');

      // 显式「放进愿望池」——领域薄入口。
      final Wish pooled = await f.os.putIntoPool(
        id: 'Y_W_PLANE',
        now: kYanNow,
      );
      expect(pooled.status, WishStatus.fulfilled);
      expect(pooled.fulfillSource, kWishFulfillSourceProgress,
          reason: 'source=progress，不误挂「我自己做到的」徽标');
      expect(pooled.fulfilledAt, kYanNow);
      expect(pooled.treeSlot, isNull, reason: '清树位');

      mid = (await f.wishes.byId('Y_W_PLANE'))!;
      expect(mid.status, WishStatus.fulfilled, reason: '落库真写');
      expect(await f.os.stampedAchievedCount(), 1, reason: '盖章 +1');
      final List<Wish> pool = await f.os.poolWishes();
      expect(pool.map((Wish w) => w.id), contains('Y_W_PLANE'),
          reason: '进达成所愿池');

      final List<TrackingEvent> fulfilledEvents = f.tracking.ofKind('fulfilled');
      expect(fulfilledEvents, hasLength(1), reason: '发且仅发 1 次 fulfilled 埋点');
      expect(fulfilledEvents.single.payload['wish_id'], 'Y_W_PLANE');
      expect(f.tracking.ofKind('selfFulfilled'), isEmpty,
          reason: '不得冒充孩子自助达成');
      expect(await f.ledger.all(), isEmpty, reason: '愿望任务 0 阳光');
    });

    test('二次确认语义：直接对未完成任务调用 putIntoPool 不得落库（防御路径）',
        () async {
      final _YanFx f = await _yanFx();
      await f.wishes.save(_yanWish('Y_W_EARLY', text: '未完成的小船', target: 0));
      // 必须挂一条未 verified 的手动任务；无任务愿望按 v0.5 口径门控放行。
      await f.tasks
          .saveTask(_yanTask('Y_T_EARLY', wishId: 'Y_W_EARLY', focus: false));
      final Wish result = await f.os.putIntoPool(id: 'Y_W_EARLY', now: kYanNow);
      expect(result.status, WishStatus.pending,
          reason: '门控未过：status 不变（变异对照点①）');
      expect((await f.wishes.byId('Y_W_EARLY'))!.status, WishStatus.pending,
          reason: '不得落库');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Y2 · 门控拦截 + 防误报
  // ═══════════════════════════════════════════════════════════════════════
  group('Y2 门控拦截 + 防误报', () {
    test('两条手动任务只核销一条：putIntoPool 拦截，status/树位/source 全不变，不发 fulfilled',
        () async {
      final _YanFx f = await _yanFx();
      await f.wishes
          .save(_yanWish('Y_W_MULTI', text: '去科技馆看火箭', target: 0));
      await f.tasks
          .saveTask(_yanTask('Y_T_A', wishId: 'Y_W_MULTI', focus: false));
      await f.tasks
          .saveTask(_yanTask('Y_T_B', wishId: 'Y_W_MULTI', focus: false));
      // 只落一条 verified，另一条保持无打卡。
      await f.tasks.checkIn(_yanCheckIn('Y_C_A', 'Y_T_A'));

      final Wish result = await f.os.putIntoPool(
        id: 'Y_W_MULTI',
        now: kYanNow,
      );
      expect(result.status, WishStatus.pending,
          reason: '门控拦下：status 不变（变异对照点①：去门控则转 RED）');
      expect(result.treeSlot, 0, reason: '仍挂树');
      expect(result.fulfillSource, isNull, reason: 'source 不得写入');
      expect(result.fulfilledAt, isNull);
      expect(await f.os.poolWishes(), isEmpty, reason: '不进池');
      expect(await f.os.stampedAchievedCount(), 0, reason: '盖章不 +1');
      expect(f.tracking.ofKind('fulfilled'), isEmpty,
          reason: '拦截时误发 fulfilled ⇒ 变异对照点②转 RED');
      expect(await f.ledger.all(), isEmpty, reason: '0 阳光');
    });

    test('有 pending（未家长确认）任务时同样拦截：pending 不算完成', () async {
      final _YanFx f = await _yanFx();
      await f.wishes.save(_yanWish('Y_W_PENDING', text: '等确认的愿望', target: 0));
      await f.tasks
          .saveTask(_yanTask('Y_T_P', wishId: 'Y_W_PENDING', focus: false));
      await f.tasks.checkIn(_yanCheckIn(
        'Y_C_P',
        'Y_T_P',
        status: CheckInStatus.pending,
      ));

      final Wish result = await f.os.putIntoPool(
        id: 'Y_W_PENDING',
        now: kYanNow,
      );
      expect(result.status, WishStatus.pending,
          reason: 'pending 不是 verified，门控必须拦');
      expect(f.tracking.ofKind('fulfilled'), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Y3 · 按钮两态互斥 + 蛋联动（纯函数 + widget 双层）
  // ═══════════════════════════════════════════════════════════════════════
  group('Y3 按钮两态互斥 + 蛋联动', () {
    test('wishPoolButtonOf 三态真值表（写死期望，不用实现常量）', () {
      // 全完成 + 手动任务 + 树上 ⇒ 单进池按钮
      expect(
        wishPoolButtonOf(
            onTree: true, hasManualTask: true, tasksAllDone: true),
        WishPoolButton.putInPool,
      );
      // 有未完成任务 ⇒ 维持两按钮
      expect(
        wishPoolButtonOf(
            onTree: true, hasManualTask: true, tasksAllDone: false),
        WishPoolButton.changeAndCollect,
      );
      // 纯专注任务 / 无任务愿望（hasManualTask=false）⇒ 不显进池按钮
      expect(
        wishPoolButtonOf(
            onTree: true, hasManualTask: false, tasksAllDone: true),
        WishPoolButton.changeAndCollect,
      );
      expect(
        wishPoolButtonOf(
            onTree: true, hasManualTask: false, tasksAllDone: false),
        WishPoolButton.changeAndCollect,
      );
      // 非树上（收藏箱/终态）⇒ 无进池入口
      expect(
        wishPoolButtonOf(
            onTree: false, hasManualTask: true, tasksAllDone: true),
        WishPoolButton.none,
      );
    });

    test('wishTreeEggOf / wishTreeEggAssetOf 四态真值表（写死 asset 字符串）', () {
      // hasWays + 全完成 ⇒ 实现蛋
      final WishTreeEgg done = wishTreeEggOf(
        face: WishTreeFace.hasWays,
        tasksAllDone: true,
      );
      expect(done, WishTreeEgg.done);
      expect(wishTreeEggAssetOf(done), 'assets/wish_tree/egg_done.webp');

      // hasWays + 未完成 ⇒ 正在实现蛋
      final WishTreeEgg growing = wishTreeEggOf(
        face: WishTreeFace.hasWays,
        tasksAllDone: false,
      );
      expect(growing, WishTreeEgg.growing);
      expect(wishTreeEggAssetOf(growing), 'assets/wish_tree/egg_growing.webp');

      // 无任务（face != hasWays）即便空任务 tasksAllDone=true 也不误判
      for (final WishTreeFace face in <WishTreeFace>[
        WishTreeFace.hanging,
        WishTreeFace.parentResponded,
      ]) {
        final WishTreeEgg egg =
            wishTreeEggOf(face: face, tasksAllDone: true);
        expect(egg, WishTreeEgg.wish, reason: '$face 必须保持 egg_wish');
        expect(wishTreeEggAssetOf(egg), 'assets/wish_tree/egg_wish.webp');
      }
      // 变异对照点③：去掉 tasksAllDone 条件 ⇒ growing 用例转 RED。
    });

    testWidgets('widget 层：canPutInPool=true 只显单个进池按钮，两次级按钮与主按钮全消失',
        (WidgetTester tester) async {
      await tester.pumpWidget(_yanHost(WishCardDetail(
        wish: _yanWish('Y_W_BTN', text: '想要小火车'),
        t: kYanT,
        waitDays: 1,
        confirmTitle: kYanT.wishRealizedCongrats,
        confirmLabel: kYanT.wishDetailRealized,
        cancelLabel: kYanT.shared_cancel,
        face: WishTreeFace.hasWays,
        taskCount: 1,
        canSelfFulfill: false,
        canPutInPool: true,
        putInPoolLabel: '放进愿望池',
        onPutInPool: () {},
      )));
      expect(find.byKey(const Key('wish_detail_put_in_pool')), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_change')), findsNothing,
          reason: '「换个愿望」隐藏');
      expect(find.byKey(const Key('wish_detail_collect')), findsNothing,
          reason: '「放进收藏箱」隐藏');
      expect(find.byKey(const Key('wish_detail_self_fulfill')), findsNothing,
          reason: '「实现了」主按钮也不与之并存');
      expect(find.text('放进愿望池'), findsOneWidget);
    });

    testWidgets('widget 层：canPutInPool=false 维持「换个愿望 + 放进收藏箱」两按钮，无进池按钮',
        (WidgetTester tester) async {
      await tester.pumpWidget(_yanHost(WishCardDetail(
        wish: _yanWish('Y_W_BTN2', text: '未完成的愿望'),
        t: kYanT,
        waitDays: 1,
        confirmTitle: kYanT.wishRealizedCongrats,
        confirmLabel: kYanT.wishDetailRealized,
        cancelLabel: kYanT.shared_cancel,
        face: WishTreeFace.hasWays,
        taskCount: 1,
        canSelfFulfill: false,
        // canPutInPool 默认 false
      )));
      expect(find.byKey(const Key('wish_detail_put_in_pool')), findsNothing);
      expect(find.byKey(const Key('wish_detail_change')), findsOneWidget);
      expect(find.byKey(const Key('wish_detail_collect')), findsOneWidget);
    });

    test('池段 wish_pool_tile.dart:67 零改动（源码守卫：固定 eggDone、无 tasksAllDone 分支）',
        () {
      final String src =
          File('lib/presentation/child/widgets/wish_pool_tile.dart')
              .readAsStringSync();
      expect(src, contains('WishTreeArt.eggDone'));
      expect(src, isNot(contains('tasksAllDone')),
          reason: '池段不得新增蛋判据');
      expect(src, isNot(contains('wishTreeEggOf')),
          reason: '池段蛋表现固定，不随任务完成度变化');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Y4 · iPhone 缩放 + iPad 逐字节不变
  // ═══════════════════════════════════════════════════════════════════════
  group('Y4 iPhone 缩放 + iPad 逐字节不变', () {
    test('compactScaleFor 真值表：手机 0.8 / iPad 1.0，常量单点 0.8', () {
      expect(kPhoneEntryScale, 0.8);
      expect(compactScaleFor(isTablet: false), closeTo(0.8, 0.0001));
      expect(compactScaleFor(isTablet: true), 1.0,
          reason: 'iPad 恒 1.0（变异对照点④：改成 0.8 则转 RED）');
      expect(compactScaleFor(isTablet: true) * 56.0, 56.0,
          reason: '×1.0 逐位相等');
    });

    testWidgets('图2 手机：许愿树入口视觉 44.8dp、热区由外层 ≥48dp 兜底',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_yanHost(SizedBox(
        width: 390,
        height: 844,
        child: WishTopEntryCluster(
          scale: compactScaleFor(isTablet: false),
          icon: WishTreeWeatherEntry(
            label: '许愿树',
            scale: compactScaleFor(isTablet: false),
          ),
          label: '许愿树',
          labelKey: const Key('Y_weather_label'),
        ),
      )));

      // 视觉本体（kWishTreeWeatherEntryKey）= 56 × uiScale(1.0) × 0.8
      final Size visual = tester.getSize(find.byKey(kWishTreeWeatherEntryKey));
      expect(visual.width, closeTo(44.8, 0.01),
          reason: '手机视觉缩到 44.8dp');
      expect(visual.height, closeTo(44.8, 0.01));
      // 热区（整簇 ConstrainedBox min48）不随视觉缩小
      final Size hit = tester.getSize(find.byType(WishTopEntryCluster));
      expect(hit.width, greaterThanOrEqualTo(48));
      expect(hit.height, greaterThanOrEqualTo(48));
    });

    testWidgets('图2 iPad：视觉仍 56×uiScale，逐字节不变（scale=1.0）',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_yanHost(SizedBox(
        width: 834,
        height: 1194,
        child: WishTreeWeatherEntry(
          label: '许愿树',
          scale: compactScaleFor(isTablet: true),
        ),
      )));
      // 直接读内部 SizedBox 的边长（与既有 entry icon shape 测试同法，
      // 避开外层 Scaffold 约束干扰）：iPad 11″ uiScale=1.3 × compact=1.0。
      final SizedBox box = tester.widget<SizedBox>(find
          .descendant(
            of: find.byKey(kWishTreeWeatherEntryKey),
            matching: find.byType(SizedBox),
          )
          .first);
      expect(box.width, closeTo(56.0 * 1.3, 0.01),
          reason: 'iPad 视觉 56×1.3，compact=1.0 逐位不变');
      expect(box.height, closeTo(56.0 * 1.3, 0.01));
    });

    testWidgets('图3 手机：底部三圆形按钮 85.8×0.8≈68.6dp（非分段 chip）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_yanSceneHost(const Size(390, 844), 0.8));
      for (final String key in <String>[
        'wish_scene_box_button',
        'wish_scene_start_button',
        'wish_scene_pool_button',
      ]) {
        final Size s = _yanActionSize(tester, key);
        expect(s.width, closeTo(85.8 * 0.8, 0.01),
            reason: '$key 先 clamp(84,92)=85.8 再 ×0.8');
        expect(s.height, closeTo(85.8 * 0.8, 0.01));
        expect(s.width, greaterThanOrEqualTo(48), reason: '热区底线');
      }
    });

    testWidgets('图3 iPad：底部三圆形按钮 85.8dp 一字不变（scale=1.0）',
        (WidgetTester tester) async {
      await tester.pumpWidget(_yanSceneHost(const Size(390, 844), 1.0));
      for (final String key in <String>[
        'wish_scene_box_button',
        'wish_scene_start_button',
        'wish_scene_pool_button',
      ]) {
        final Size s = _yanActionSize(tester, key);
        expect(s.width, closeTo(85.8, 0.01), reason: '$key iPad 逐位不变');
        expect(s.height, closeTo(85.8, 0.01));
      }
    });

    test('图2 接线守卫：只有上面两枚传 scale，浇水壶/第三枚不传', () {
      final String src =
          File('lib/presentation/child/pages/garden_page.dart')
              .readAsStringSync();
      expect('scale: compact'.allMatches(src).length, 4,
          reason: '两枚 × (cluster + icon) = 4 处，第三枚不传');
      expect(src, contains('compactScaleOf(context)'),
          reason: '页面读一次系数');
      final int third = src.indexOf('BloomDebugEntry(onTap: _openDebugPanel)');
      expect(third, greaterThan(0), reason: '第三枚入口仍在');
      expect(src.substring(third, third + 80), isNot(contains('scale:')),
          reason: '第三枚（浇水壶位）不随手机系数缩');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Y6 · v0.1 零回归
  // ═══════════════════════════════════════════════════════════════════════
  group('Y6 v0.1 零回归', () {
    test('targetValue >= 1：家长确认自动进池仍成立（旧断言口径）', () async {
      final _YanFx f = await _yanFx();
      await f.wishes.save(
          _yanWish('Y_W_AUTO', text: '有目标的愿望', target: 1));
      await f.tasks
          .saveTask(_yanTask('Y_T_AUTO', wishId: 'Y_W_AUTO', focus: false));
      final Task task = (await f.tasks.wishTaskById('Y_T_AUTO'))!;
      final TaskCheckInOutcome child =
          await f.checkIns.checkIn(task: task, now: kYanNow);
      await f.checkIns.verifyCheckIn(child.checkInId, kYanNow);

      final Wish wish = (await f.wishes.byId('Y_W_AUTO'))!;
      expect(wish.status, WishStatus.fulfilled,
          reason: 'target=1 时 registerCheckIn 闸门不拦，自动进池照旧');
      expect(wish.fulfillSource, kWishFulfillSourceProgress);
      expect(wish.treeSlot, isNull);
      expect(await f.os.stampedAchievedCount(), 1);
      expect(await f.ledger.all(), isEmpty, reason: '愿望任务仍 0 阳光');
    });

    test('第 6 条路径 settleWishFocus：专注刷满但另有未完成任务 ⇒ 只加进度不成真',
        () async {
      final _YanFx f = await _yanFx();
      await f.wishes.save(_yanWish(
        'Y_W_FOCUS',
        text: '专注型愿望',
        target: 15,
        mode: WishGoalMode.focusMinutes,
      ));
      await f.tasks
          .saveTask(_yanTask('Y_T_FOCUS', wishId: 'Y_W_FOCUS', focus: true));
      await f.tasks
          .saveTask(_yanTask('Y_T_EXTRA', wishId: 'Y_W_FOCUS', focus: false));

      await f.checkIns.settleWishFocusTask(
        task: (await f.tasks.wishTaskById('Y_T_FOCUS'))!,
        session: _yanSession('Y_SESS', 30),
        now: kYanNow,
      );
      final Wish wish = (await f.wishes.byId('Y_W_FOCUS'))!;
      expect(wish.progressValue, 15, reason: '进度照常累加');
      expect(wish.status, WishStatus.pending, reason: 'Y_T_EXTRA 未完成 ⇒ 门控拦');
      expect(wish.treeSlot, 0);
      expect(await f.os.poolWishes(), isEmpty);
      expect(f.tracking.ofKind('fulfilled'), isEmpty, reason: '不发 fulfilled');
      expect(await f.ledger.all(), isEmpty, reason: '0 阳光');
    });

    test('其余领域路径（fulfill / selfFulfill / setGoal / advanceProgress）仍受门控',
        () async {
      // fulfill：家长确认但有未完成任务 ⇒ 不得成真
      final _YanFx a = await _yanFx();
      await a.wishes.save(_yanWish('Y_W_F1', text: 'A', target: 1));
      await a.tasks.saveTask(_yanTask('Y_T_F1', wishId: 'Y_W_F1', focus: false));
      final Wish r1 = await a.os.fulfill(id: 'Y_W_F1', now: kYanNow);
      expect(r1.status, WishStatus.pending, reason: 'fulfill 被门控拦');
      expect(a.tracking.ofKind('fulfilled'), isEmpty,
          reason: 'fulfill 拦截也不得误发埋点');

      // selfFulfill：孩子自助但有未完成任务 ⇒ 不得成真
      final _YanFx b = await _yanFx();
      await b.wishes.save(_yanWish('Y_W_S1', text: 'B', target: 1));
      await b.tasks.saveTask(_yanTask('Y_T_S1', wishId: 'Y_W_S1', focus: false));
      final Wish r2 = await b.os.selfFulfill(id: 'Y_W_S1', now: kYanNow);
      expect(r2.status, WishStatus.pending, reason: 'selfFulfill 被门控拦');
      expect(b.tracking.ofKind('selfFulfilled'), isEmpty);

      // setGoal：设定目标即 ripe 但有未完成任务 ⇒ 不得成真
      final _YanFx c = await _yanFx();
      await c.wishes.save(_yanWish('Y_W_G1', text: 'C', target: 0));
      await c.tasks.saveTask(_yanTask('Y_T_G1', wishId: 'Y_W_G1', focus: false));
      final Wish r3 = await c.os.setGoal(
        wishId: 'Y_W_G1',
        mode: WishGoalMode.taskCount,
        targetValue: 1,
        now: kYanNow,
      );
      expect(r3.status, WishStatus.pending, reason: 'setGoal 被门控拦');

      // advanceProgress：直接推满进度但有未完成任务 ⇒ 不得成真
      final _YanFx d = await _yanFx();
      await d.wishes.save(_yanWish('Y_W_A1', text: 'D', target: 5, progress: 4));
      await d.tasks.saveTask(_yanTask('Y_T_A1', wishId: 'Y_W_A1', focus: false));
      final Wish r4 = await d.os.advanceProgress(
        wishId: 'Y_W_A1',
        delta: 1,
        now: kYanNow,
      );
      expect(r4.status, WishStatus.pending, reason: 'advanceProgress 被门控拦');
      expect(r4.progressValue, 5, reason: '进度照常写入');
    });

    test('普通成长任务（wishId==null）与无任务愿望行为不变', () async {
      final _YanFx f = await _yanFx();
      // 普通任务仍发阳光（gross>0）：无 wishId 的任务用工厂对象直接打卡
      // （wishTaskById 只查关联愿望的任务，故不走它）。
      final Task ordinary =
          _yanTask('Y_T_ORDINARY', wishId: null, focus: false);
      await f.tasks.saveTask(ordinary);
      final TaskCheckInOutcome out =
          await f.checkIns.checkIn(task: ordinary, now: kYanNow);
      expect(out.reward, greaterThan(0), reason: '普通任务仍有阳光奖励');
      expect(out.status, CheckInStatus.pending);

      // 无任务愿望：进池按钮判据为 changeAndCollect，蛋为 egg_wish。
      final Wish noTask = _yanWish('Y_W_NONE', text: '无任务愿望', target: 0);
      expect(
        wishPoolButtonOf(
            onTree: true, hasManualTask: false, tasksAllDone: true),
        WishPoolButton.changeAndCollect,
      );
      expect(
        wishTreeEggOf(
            face: wishTreeFaceOf(wish: noTask, wayCount: 0),
            tasksAllDone: true),
        WishTreeEgg.wish,
      );
    });

    test('冻结契约：WishStatus 6 态 index / 3 个 source 常量 / schemaVersion 32 / Wish 22 字段',
        () async {
      expect(WishStatus.values, hasLength(6));
      expect(WishStatus.pending.index, 0);
      expect(WishStatus.tagged.index, 1);
      expect(WishStatus.committed.index, 2);
      expect(WishStatus.fulfilled.index, 3);
      expect(WishStatus.replaced.index, 4);
      expect(WishStatus.abandoned.index, 5);

      expect(kWishFulfillSourceParentAction, 'parentAction');
      expect(kWishFulfillSourceProgress, 'progress');
      expect(kWishFulfillSourceChild, 'child');

      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      expect(database.schemaVersion, 32);
      await database.close();

      final String wishSrc =
          File('lib/domain/entities/wish.dart').readAsStringSync();
      final int start = wishSrc.indexOf('class Wish {');
      final int end = wishSrc.indexOf('const Wish({', start);
      final int fields = RegExp(r'^  final ', multiLine: true)
          .allMatches(wishSrc.substring(start, end))
          .length;
      expect(fields, 22, reason: 'Wish 仍 22 字段');
    });
  });
}

/// 图3 场景宿主：固定视口宽 390 ⇒ raw = 390×0.22 = 85.8（clamp 84~92 内）。
Widget _yanSceneHost(Size size, double actionScale) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: 1.0),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: WishTreeScene(
              actionScale: actionScale,
              eggs: <WishEgg>[
                WishEgg(
                  asset: WishTreeArt.eggWish,
                  label: '愿望一',
                  onTap: () {},
                  key: const Key('Y_egg'),
                ),
              ],
              onStartWish: () {},
              onOpenBox: () {},
              onOpenPool: () {},
              boxLabel: '收藏箱',
              poolLabel: '愿望池',
              startLabel: '许愿',
            ),
          ),
        ),
      ),
    );

/// 读三按钮圆形 Container 的边长（Container 的 BoxConstraints.maxWidth == size）。
Size _yanActionSize(WidgetTester tester, String key) {
  final Container c = tester.widget<Container>(find
      .descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Container),
      )
      .first);
  return Size(c.constraints!.maxWidth, c.constraints!.maxHeight);
}
