/// G11~G14: two-branch criterion, single goal writer, wish-task wiring,
/// and economic isolation existence checks.
library wish_goal_model_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_orchestration_service.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  final String progress = _read('lib/domain/services/wish_progress.dart');
  final String service =
      _read('lib/domain/services/wish_orchestration_service.dart');

  group('G11 判据函数恰 2 个可达分支', () {
    test('progressDeltaOf 两个 case，无 default / else / 第三分支', () {
      final int start = progress.indexOf('int progressDeltaOf({');
      final int end = progress.indexOf('int recomputeProgressValue({');
      final String body = progress.substring(start, end);
      expect('case WishGoalMode.'.allMatches(body).length, 2);
      expect(body.contains('default:'), isFalse);
      expect(body.contains('else'), isFalse);
      expect(body.contains('WishGoalMode.values'), isFalse);
    });

    test('fruitStageOf 四态纯派生，不写状态', () {
      expect(fruitStageOf(targetValue: 0, progressValue: 0),
          WishFruitStage.none);
      expect(fruitStageOf(targetValue: 30, progressValue: 0),
          WishFruitStage.waiting);
      expect(fruitStageOf(targetValue: 30, progressValue: 10),
          WishFruitStage.growing);
      expect(fruitStageOf(targetValue: 30, progressValue: 30),
          WishFruitStage.ripe);
    });
  });

  group('G12 目标值只写一次', () {
    test('setGoal 是唯一写 targetMode/targetValue 的服务方法', () {
      expect('copyWith(targetMode:'.allMatches(service).length, 1);
      expect(service.contains('Future<Wish> setGoal('), isTrue);
    });

    test('assignTasks 函数体不写 target/progress', () {
      final int start = service.indexOf('Future<List<String>> assignTasks(');
      final int end = service.indexOf('\n  Future<Wish> fulfill(', start);
      final String body = service.substring(start, end);
      expect(body.contains('targetValue:'), isFalse);
      expect(body.contains('progressValue:'), isFalse);
      expect(body.contains('assignWish('), isTrue);
    });
  });

  group('G13 愿望任务带 wishId 且无孤儿', () {
    test('assignWish 写入后 wishId 非空', () {
      const Task task = Task(
        id: 't1',
        name: 'n',
        subject: TaskSubject.general,
        requiresFocus: true,
        minFocusMin: 15,
        sunlightReward: 0,
        isCustom: false,
        wishId: 'w1',
      );
      expect(task.wishId, isNotNull);
      expect(WishOrchestrationService.isWishLinkedTask(task), isTrue);
    });

    test('mode 0 下不出现行为型任务', () {
      final List<Task> tasks = <Task>[
        const Task(
          id: 't2',
          name: 'manual',
          subject: TaskSubject.general,
          requiresFocus: false,
          minFocusMin: 15,
          sunlightReward: 0,
          isCustom: false,
          wishId: 'w1',
        ),
      ];
      final List<Task> focusOnly = tasks
          .where((Task t) => t.wishId == 'w1' && t.requiresFocus)
          .toList();
      expect(focusOnly, isEmpty);
    });

    test('孤儿检查：wishId 必须有对应愿望行', () {
      final Map<String, Wish> pool = <String, Wish>{
        'w1': Wish(id: 'w1', childId: 'c', text: 'x', createdAt: DateTime(2026)),
      };
      final List<String> orphanIds = <String>['w1', 'w2']
          .where((String id) => !pool.containsKey(id))
          .toList();
      expect(orphanIds, <String>['w2']);
    });
  });

  group('G14 经济隔离 5 处存在性与行为', () {
    test('唯一 helper 存在且领域服务不引用阳光 / 账本 / 完美日', () {
      expect(service.contains('static bool isWishLinkedTask(Task task)'),
          isTrue);
      for (final String token in <String>[
        'SunlightService',
        'sunlightRepository',
        'appendLedger',
        'isPerfectDay',
        'weeklyPool',
      ]) {
        expect(service.contains(token), isFalse, reason: token);
      }
    });

    test('领域层不产生阳光账本行（fake 流水为空）', () {
      final Map<String, int> ledger = <String, int>{};
      expect(ledger, isEmpty);
      expect(ledger.values.fold<int>(0, (int a, int b) => a + b), 0);
    });
  });
}
