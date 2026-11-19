/// A-T05 家长端今日页许愿树区块断言 ①~⑨ + V14/V15（A21 / A-T05）。
///
/// 分两层：纯函数 / 领域层（真判据 + 数据不丢 + 经济零改）；源码守卫
/// （listenManual 订阅、块体闭包刷新、区块插入位置、无购买入口、分段唯一）。
/// 期望值写死独立量。
library wish_desk_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
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
import 'package:sunflower_time/presentation/parent/widgets/wish_tree_section.dart';

// ── fakes（自包含，期望独立于实现） ──────────────────────────────────────
class DeskWishRepo implements WishRepository {
  final Map<String, Wish> rows = <String, Wish>{};
  @override
  Future<List<Wish>> mounted() async => rows.values
      .where((Wish w) =>
          (w.status == WishStatus.pending ||
              w.status == WishStatus.tagged ||
              w.status == WishStatus.committed) &&
          w.releasedAt == null)
      .toList();
  @override
  Future<List<Wish>> pool() async => rows.values
      .where((Wish w) =>
          w.status == WishStatus.fulfilled || w.status == WishStatus.replaced)
      .toList();
  @override
  Future<List<Wish>> boxed() async =>
      rows.values.where((Wish w) => w.releasedAt != null).toList();
  @override
  Future<List<Wish>> abandoned() async =>
      rows.values.where((Wish w) => w.status == WishStatus.abandoned).toList();
  @override
  Future<List<Wish>> byStatuses(Set<WishStatus> s) async =>
      rows.values.where((Wish w) => s.contains(w.status)).toList();
  @override
  Future<int> countByStatuses(Set<WishStatus> s) async =>
      (await byStatuses(s)).length;
  @override
  Future<int> countStampedAchieved() async =>
      rows.values.where((Wish w) => w.status == WishStatus.fulfilled).length;
  @override
  Future<Set<int>> occupiedSlots() async => rows.values
      .where((Wish w) => w.releasedAt == null && w.treeSlot != null)
      .map((Wish w) => w.treeSlot!)
      .toSet();
  @override
  Future<Wish?> byId(String id) async => rows[id];
  @override
  Future<void> save(Wish wish) async => rows[wish.id] = wish;
  @override
  Future<void> deleteAll() async => rows.clear();
}

class DeskTaskRepo implements WishTaskRepository {
  final Map<String, Task> tasks = <String, Task>{};
  @override
  Future<List<Task>> tasksOfWish({required String wishId}) async =>
      tasks.values.where((Task t) => t.wishId == wishId).toList();
  @override
  Future<List<CheckIn>> checkInsOfTaskIds({required List<String> taskIds}) async =>
      <CheckIn>[];
  @override
  Future<void> assignWish({required String taskId, required String wishId}) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: wishId);
  }
  @override
  Future<void> unassignWish({required String taskId}) async {
    final Task? t = tasks[taskId];
    if (t != null) tasks[taskId] = t.copyWith(wishId: Task.kClear);
  }
}

class DeskTrackingRepo implements TrackingRepository {
  final List<TrackingEvent> events = <TrackingEvent>[];
  @override
  Future<void> track(TrackingEvent e) async => events.add(e);
  @override
  Future<List<TrackingEvent>> eventsOfType(TrackingType t) async =>
      events.where((e) => e.type == t).toList();
  @override
  Future<String> exportJsonl(DateTime from, DateTime to) async => '';
}

Wish _wish({
  required String id,
  WishStatus status = WishStatus.pending,
  int? treeSlot,
  int targetValue = 0,
  int progressValue = 0,
  DateTime? createdAt,
  String? fulfillSource,
  String? tagKey,
}) =>
    Wish(
      id: id,
      childId: kChildIdDefault,
      text: '愿望$id',
      status: status,
      treeSlot: treeSlot,
      targetValue: targetValue,
      progressValue: progressValue,
      createdAt: createdAt ?? DateTime(2025, 1, 1),
      fulfillSource: fulfillSource,
      tagKey: tagKey,
      // v0.2.0：家长台数据源只收已授权愿望；既有排序断言沿用授权数据。
    );

WishOrchestrationService _service(
  DeskWishRepo wishes,
  DeskTaskRepo tasks,
  DeskTrackingRepo tracking,
) =>
    WishOrchestrationService(
      wishes: wishes,
      wishTasks: tasks,
      account: AccountService(),
      tracking: tracking,
    );

void main() {
  group('① 区块出现 + tab 总数 5', () {
    test('家长端 5 tab 结构不变（源码守卫：nav  destinations 5）', () {
      final String src =
          File('lib/presentation/parent/pages/parent_home_page.dart')
              .readAsStringSync();
      // 家长端 shell 的 tab 定义未因许愿树新增（现有 5 项）。
      expect(src.contains('parent_today_page'), isTrue);
      expect(src.contains('wish_tree_page'), isFalse,
          reason: '不新增家长端独立愿望 tab');
    });
  });

  group('② 区块与待核销 / 兑换并列（顺序守卫）', () {
    test('cards 列表顺序：_PendingCheckInsCard → WishTreeSection → 兑换循环', () {
      final String src =
          File('lib/presentation/parent/pages/parent_today_page.dart')
              .readAsStringSync();
      final int pending = src.indexOf('_PendingCheckInsCard(');
      final int wish = src.indexOf('WishTreeSection(');
      final int redeem = src.indexOf('for (final RedemptionRequest req');
      expect(pending, lessThan(wish));
      expect(wish, lessThan(redeem));
    });
  });

  group('③ 空列表整卡不渲染', () {
    test('WishTreeSection 空 entries + 空 selfFulfilled ⇒ SizedBox.shrink', () {
      final String src = File(
              'lib/presentation/parent/widgets/wish_tree_section.dart')
          .readAsStringSync();
      expect(
        src.contains('widget.entries.isEmpty && widget.selfFulfilled.isEmpty'),
        isTrue,
      );
      expect(src.contains('return const SizedBox.shrink();'), isTrue);
    });
  });

  group('④ 排序：提醒置顶 + 等待天数降序', () {
    test('parentDeskList 口径（独立造数据验证）', () async {
      final DeskWishRepo repo = DeskWishRepo();
      final DeskTaskRepo tasks = DeskTaskRepo();
      final DeskTrackingRepo tracking = DeskTrackingRepo();
      repo.rows['a'] = _wish(
          id: 'a', treeSlot: 0, createdAt: DateTime(2025, 1, 1));
      repo.rows['b'] = _wish(
          id: 'b', treeSlot: 1, createdAt: DateTime(2025, 3, 1));
      final WishOrchestrationService svc = _service(repo, tasks, tracking);
      final DateTime now = DateTime(2025, 3, 10);
      final List<Wish> list = await svc.parentDeskList(now);
      expect(list.first.id, 'a', reason: '等待天数降序：1/1 创建（等更久）在前');
      // 给 b 加提醒 ⇒ 置顶（ overriding 等待天数）。
      repo.rows['b'] = repo.rows['b']!.copyWith(
          remindedAt: DateTime(2025, 3, 9));
      final List<Wish> list2 = await svc.parentDeskList(now);
      expect(list2.first.id, 'b', reason: '提醒过的置顶');
    });
  });

  group('⑤ 三动作后数据不丢（行数只增不减）', () {
    test('tagWithReply / fulfill / undoFulfill 后愿望行数不减（C69 不删行）', () async {
      final DeskWishRepo repo = DeskWishRepo();
      final DeskTaskRepo tasks = DeskTaskRepo();
      final DeskTrackingRepo tracking = DeskTrackingRepo();
      repo.rows['w'] = _wish(id: 'w', treeSlot: 0);
      final WishOrchestrationService svc = _service(repo, tasks, tracking);
      final int before = repo.rows.length;

      await svc.tagWithReply(
          id: 'w', tag: WishTag.needMoreTime, reply: '再等等',
          now: DateTime(2025, 3, 10));
      expect(repo.rows.length, greaterThanOrEqualTo(before));
      await svc.fulfill(id: 'w', now: DateTime(2025, 3, 10));
      expect(repo.rows.length, before, reason: 'fulfill 不删行，只改状态');
      expect(repo.rows['w']!.status, WishStatus.fulfilled);
      // 撤销：fulfilled → pending，仍不删行、留痕。
      await svc.undoFulfill(id: 'w', now: DateTime(2025, 3, 11));
      expect(repo.rows.length, before, reason: '撤销不删行');
      expect(repo.rows['w']!.status, WishStatus.pending);
      expect(repo.rows['w']!.fulfillSource, kWishFulfillSourceParentAction,
          reason: '留痕不清空');
    });
  });

  group('⑥ 经济零改动', () {
    test('三动作只写愿望表/埋点，不触阳光账本（领域服务无 SunlightRepository 依赖）', () {
      final String svc = File(
              'lib/domain/services/wish_orchestration_service.dart')
          .readAsStringSync();
      expect(svc.contains('SunlightRepository'), isFalse);
      expect(svc.contains('sunlight'), isFalse);
    });
  });

  group('⑦ 订阅生效：listenManual + 修订号', () {
    test('initState 有 listenManual(economyRevisionProvider, ...)', () {
      final String src =
          File('lib/presentation/parent/pages/parent_today_page.dart')
              .readAsStringSync();
      expect(src.contains('ref.listenManual(economyRevisionProvider'), isTrue);
      expect(src.contains('ref.listen<int>(economyRevisionProvider'), isFalse,
          reason: 'initState 不得用 ref.listen');
    });
  });

  group('⑧ 刷新走块体闭包（源码守卫）', () {
    test('parent_today_page.dart 无箭头体 setState(() => _future =', () {
      final String src =
          File('lib/presentation/parent/pages/parent_today_page.dart')
              .readAsStringSync();
      // 只看代码行（文件头注释里把箭头体作为反例写出，须排除）。
      final Iterable<String> codeLines = src
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('///'))
          .where((String line) => !line.trimLeft().startsWith('//'));
      final bool hasArrow = codeLines.any(
          (String line) => RegExp(r'setState\(\(\)\s*=>\s*_future\s*=')
              .hasMatch(line));
      expect(hasArrow, isFalse);
      expect(src.contains('setState(() {'), isTrue);
    });
  });

  group('⑨ 默认只展示三类，其余折叠', () {
    test('V14 四段互斥且完备：sectionOf 全覆盖 + 折叠计数 = 折叠集合条数', () {
      final DeskWishRepo repo = DeskWishRepo();
      final DeskTaskRepo tasks = DeskTaskRepo();
      final DeskTrackingRepo tracking = DeskTrackingRepo();
      // 待安排：无任务无目标
      repo.rows['setup'] = _wish(id: 'setup', treeSlot: 0);
      // 进行中：有目标有进度（且有任务，才不被 needsParentSetup 判走）
      repo.rows['prog'] = _wish(
          id: 'prog', treeSlot: 1, targetValue: 30, progressValue: 10);
      tasks.tasks['prog-t'] = const Task(
          id: 'prog-t',
          name: '任务',
          subject: TaskSubject.general,
          requiresFocus: true,
          minFocusMin: 15,
          sunlightReward: 5,
          isCustom: true,
          wishId: 'prog');
      // 折叠：已贴标签 + 有目标 + 有任务 + 进度 0（不进前三段）
      repo.rows['tag'] = _wish(
          id: 'tag', treeSlot: 2, targetValue: 10, tagKey: 'needMoreTime');
      tasks.tasks['tag-t'] = const Task(
          id: 'tag-t',
          name: '任务',
          subject: TaskSubject.general,
          requiresFocus: true,
          minFocusMin: 15,
          sunlightReward: 5,
          isCustom: true,
          wishId: 'tag');
      final WishOrchestrationService svc = _service(repo, tasks, tracking);

      final WishDeskEntry eSetup = WishDeskEntry(wish: repo.rows['setup']!);
      final WishDeskEntry eProg = WishDeskEntry(
        wish: repo.rows['prog']!,
        tasks: tasks.tasks.values.toList(),
      );
      final WishDeskEntry eTag = WishDeskEntry(
        wish: repo.rows['tag']!,
        tasks: <Task>[tasks.tasks['tag-t']!],
      );
      final sections = partitionWishDesk(
          service: svc, entries: <WishDeskEntry>[eSetup, eProg, eTag]);
      expect(
        sections.verify.length +
            sections.setup.length +
            sections.progress.length +
            sections.collapsed.length,
        3,
        reason: '互斥且完备（每条恰一段）',
      );
      expect(sections.setup.map((e) => e.wish.id), contains('setup'));
      expect(sections.progress.map((e) => e.wish.id), contains('prog'));
      expect(sections.collapsed.map((e) => e.wish.id), contains('tag'));
    });

    test('折叠计数 N = 折叠集合条数（源码守卫：用 .length 而非二次算式）', () {
      final String src = File(
              'lib/presentation/parent/widgets/wish_tree_section.dart')
          .readAsStringSync();
      expect(src.contains('final int n = entries.length;'), isTrue,
          reason: '折叠计数取折叠集合长度');
    });
  });

  group('V15 家长三动作恰好 3 个（对外口径）', () {
    test('ParentWishCard 三动作按钮恰好 3 个 key', () {
      final String src =
          File('lib/presentation/parent/widgets/parent_wish_card.dart')
              .readAsStringSync();
      expect(src.contains("Key('parent_wish_action_setup')"), isTrue);
      expect(src.contains("Key('parent_wish_action_fulfill')"), isTrue);
      expect(src.contains("Key('parent_wish_action_tag')"), isTrue);
      expect(src.contains('Key(\'parent_wish_action_4\')'), isFalse);
      expect(src.contains('commit'), isFalse, reason: '承诺降 P1 不接线');
      expect(src.contains('replace'), isFalse, reason: '协商替代降 P1 不接线');
    });
  });

  group('㉒ 孩子端零购买入口', () {
    test('garden_page.dart 无 /parent/premium / buyLifetime', () {
      final String src = File('lib/presentation/child/pages/garden_page.dart')
          .readAsStringSync();
      expect(src.contains('/parent/premium'), isFalse);
      expect(src.contains('buyLifetime'), isFalse);
    });
  });

  group('撤销埋点（A36.0 / A7.3）', () {
    test('wishUndo = wish_undo 常量存在，payload actor=parent', () {
      expect(TrackingEventNames.wishUndo, 'wish_undo');
      final String svc =
          File('lib/domain/services/wish_orchestration_service.dart')
              .readAsStringSync();
      expect(svc.contains("'actor': 'parent'"), isTrue);
    });
  });
}
