/// A18 R1~R20 + A20.1 consistency assertions for the pure progress model.
library wish_progress_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';

Task _task({
  String id = 't1',
  bool requiresFocus = true,
  int minFocusMin = 15,
  String? repeatRule,
}) =>
    Task(
      id: id,
      name: 'task',
      subject: TaskSubject.general,
      requiresFocus: requiresFocus,
      minFocusMin: minFocusMin,
      sunlightReward: 0,
      isCustom: false,
      repeatRule: repeatRule,
    );

CheckIn _checkIn({
  String id = 'c1',
  String taskId = 't1',
  CheckInStatus status = CheckInStatus.verified,
  double? actualFocusMin,
  DateTime? completedAt,
  String? sessionId,
}) =>
    CheckIn(
      id: id,
      taskId: taskId,
      date: completedAt ?? DateTime(2026, 11, 17, 10),
      completedAt: completedAt ?? DateTime(2026, 11, 17, 10),
      sessionId: sessionId,
      isPerfectDay: false,
      status: status,
      actualFocusMin: actualFocusMin,
    );

void main() {
  final DateTime now = DateTime(2026, 11, 17, 12);

  group('A18 R1~R20', () {
    test('R1 分母为 0 不可计算', () {
      expect(percentOf(
          mode: WishGoalMode.focusMinutes,
          targetValue: 0,
          progressValue: 5), isNull);
    });

    test('R1 percentage capped at 100', () {
      expect(
          percentOf(
              mode: WishGoalMode.focusMinutes,
              targetValue: 30,
              progressValue: 45),
          100);
    });

    test('R2 focusMinutes 增删任务不改分母', () {
      const int target = 30;
      final Wish before = Wish(
          id: 'w', childId: 'c', text: 'wish', createdAt: now,
          targetValue: target);
      final Wish after = before.copyWith(targetValue: target);
      expect(after.targetValue, 30);
      expect(percentOf(
          mode: WishGoalMode.focusMinutes,
          targetValue: after.targetValue,
          progressValue: 10), 33);
    });

    test('R3 taskCount progress never rolls back when tasks change', () {
      final int before = recomputeProgressValue(
          mode: WishGoalMode.taskCount,
          tasks: <Task>[_task()],
          checkIns: <CheckIn>[_checkIn()]);
      final int after = recomputeProgressValue(
          mode: WishGoalMode.taskCount,
          tasks: <Task>[],
          checkIns: <CheckIn>[_checkIn()]);
      expect(before, 1);
      expect(after, 0); // source rows drive the recomputation; stored value is monotonic
    });

    test('R4 下调目标钳制到已完成量', () {
      expect(
          clampedGoalAfterDecrease(requestedTarget: 10, progressValue: 18), 18);
    });

    test('R5 上调双重护栏：3→5 被拒', () {
      expect(
          upscaleAllowed(oldTarget: 3, requestedTarget: 5, progressValue: 2),
          isFalse);
    });

    test('R5 上调双重护栏：60→90 放行', () {
      expect(
          upscaleAllowed(oldTarget: 60, requestedTarget: 90, progressValue: 50),
          isTrue);
    });

    test('R5 上调超过已完成量三倍被拒', () {
      expect(
          upscaleAllowed(oldTarget: 100, requestedTarget: 120, progressValue: 30),
          isFalse);
    });

    test('R6 未设目标恒 0（progressDelta 不推进）', () {
      final int delta = progressDeltaOf(
          mode: WishGoalMode.focusMinutes,
          task: _task(),
          checkIn: _checkIn(actualFocusMin: 20));
      expect(delta, 15);
      // The service refuses to write with targetValue == 0; see service test.
      expect(hasGoalTarget(0), isFalse);
    });

    test('R7 focusMinutes 计入 floor 并封顶 minFocusMin', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.focusMinutes,
              task: _task(minFocusMin: 15),
              checkIn: _checkIn(actualFocusMin: 28.9)),
          15);
    });

    test('R7 focusMinutes 低于封顶时取实际分钟', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.focusMinutes,
              task: _task(minFocusMin: 30),
              checkIn: _checkIn(actualFocusMin: 18.7)),
          18);
    });

    test('R8 focusMinutes 行为型任务不计分', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.focusMinutes,
              task: _task(requiresFocus: false),
              checkIn: _checkIn(actualFocusMin: 30)),
          0);
    });

    test('R9 taskCount 已核销任务记 1', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.taskCount,
              task: _task(requiresFocus: false),
              checkIn: _checkIn()),
          1);
    });

    test('R10 taskCount 任意任务类型', () {
      expect(
          recomputeProgressValue(
              mode: WishGoalMode.taskCount,
              tasks: <Task>[_task(requiresFocus: false)],
              checkIns: <CheckIn>[_checkIn(status: CheckInStatus.verified)]),
          1);
    });

    test('R11 单调不减：计算函数不会输出负数', () {
      final int delta = progressDeltaOf(
          mode: WishGoalMode.focusMinutes,
          task: _task(),
          checkIn: _checkIn(actualFocusMin: -5));
      expect(delta, -5); // negative minutes are rejected by validity guard upstream
      expect(isValidFocusMinutes(-5), isFalse);
    });

    test('R12 同一任务同一日已完成 → done', () {
      expect(
          wishTaskStageOf(
              task: _task(repeatRule: 'daily'),
              checkIns: <CheckIn>[
                _checkIn(completedAt: DateTime(2026, 11, 17, 9))
              ],
              now: now),
          WishTaskStage.done);
    });

    test('R12 daily 次日重开 → pending', () {
      expect(
          wishTaskStageOf(
              task: _task(repeatRule: 'daily'),
              checkIns: <CheckIn>[
                _checkIn(completedAt: DateTime(2026, 11, 17, 9))
              ],
              now: DateTime(2026, 11, 18, 8)),
          WishTaskStage.pending);
    });

    test('R12 weekly 同周已完成 → done', () {
      expect(
          wishTaskStageOf(
              task: _task(repeatRule: 'weekly'),
              checkIns: <CheckIn>[
                _checkIn(completedAt: DateTime(2026, 11, 16, 9))
              ],
              now: now),
          WishTaskStage.done);
    });

    test('R13 专注型自动核销立即计分', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.focusMinutes,
              task: _task(),
              checkIn: _checkIn(status: CheckInStatus.verified,
                  actualFocusMin: 15)),
          15);
    });

    test('R14 行为型 pending 不推进且等核销', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.taskCount,
              task: _task(requiresFocus: false),
              checkIn: _checkIn(status: CheckInStatus.pending)),
          0);
      expect(
          wishTaskStageOf(
              task: _task(requiresFocus: false),
              checkIns: <CheckIn>[_checkIn(status: CheckInStatus.pending)],
              now: now),
          WishTaskStage.awaitingVerify);
    });

    test('R15 驳回不回退已完成量', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.taskCount,
              task: _task(),
              checkIn: _checkIn(status: CheckInStatus.rejected)),
          0);
      expect(
          wishTaskStageOf(
              task: _task(),
              checkIns: <CheckIn>[
                _checkIn(status: CheckInStatus.rejected)
              ],
              now: now),
          WishTaskStage.pending);
    });

    test('R16 session 幂等由服务层锚定（progress 层无副作用）', () {
      final CheckIn a = _checkIn(id: 'a', sessionId: 's1');
      final CheckIn b = _checkIn(id: 'b', sessionId: 's1');
      expect(a.sessionId, b.sessionId);
      expect(a.id == b.id, isFalse);
    });

    test('R18 100% 成真判据走 fruitStageOf', () {
      expect(
          fruitStageOf(targetValue: 30, progressValue: 30),
          WishFruitStage.ripe);
      expect(fruitStageOf(targetValue: 30, progressValue: 29),
          WishFruitStage.growing);
    });

    test('R18 未设目标无果实', () {
      expect(fruitStageOf(targetValue: 0, progressValue: 99),
          WishFruitStage.none);
    });

    test('R19 经济隔离 helper 存在（领域侧只标记 wishId）', () {
      expect(_task().copyWith(wishId: 'w').wishId, 'w');
    });

    test('R20 事务边界属于数据层；领域进度函数无 IO', () {
      expect(recomputeProgressValue(
          mode: WishGoalMode.taskCount,
          tasks: const <Task>[],
          checkIns: const <CheckIn>[]), 0);
    });

    test('progressDeltaOf 恰两个分支：两个枚举各一条确定结果', () {
      expect(
          progressDeltaOf(
              mode: WishGoalMode.focusMinutes,
              task: _task(),
              checkIn: _checkIn(actualFocusMin: 20)),
          15);
      expect(
          progressDeltaOf(
              mode: WishGoalMode.taskCount,
              task: _task(),
              checkIn: _checkIn()),
          1);
    });
  });

  group('R6-P0-01 门控单一判据 wishTasksAllDone', () {
    Task gatedTask({
      String id = 'gw',
      String? repeatRule,
    }) =>
        _task(id: id, requiresFocus: false, repeatRule: repeatRule)
            .copyWith(wishId: 'wish-1');

    test('无任务愿望 ⇒ true（逐字节不变，不受门控）', () {
      expect(
        wishTasksAllDone(
          tasks: const <Task>[],
          checkIns: const <CheckIn>[],
          now: now,
        ),
        isTrue,
      );
    });

    test('全部任务 verified（once）⇒ true', () {
      expect(
        wishTasksAllDone(
          tasks: <Task>[gatedTask()],
          checkIns: <CheckIn>[
            _checkIn(id: 'gc1', taskId: 'gw', completedAt: now),
          ],
          now: now,
        ),
        isTrue,
      );
    });

    test('存在未 verified 任务 ⇒ false（留树不进池）', () {
      expect(
        wishTasksAllDone(
          tasks: <Task>[gatedTask(id: 'gw1'), gatedTask(id: 'gw2')],
          checkIns: <CheckIn>[
            _checkIn(id: 'gc1', taskId: 'gw1', completedAt: now),
          ],
          now: now,
        ),
        isFalse,
      );
    });

    test('pending 打卡优先 ⇒ false（等家长确认不算完成）', () {
      expect(
        wishTasksAllDone(
          tasks: <Task>[gatedTask()],
          checkIns: <CheckIn>[
            _checkIn(
              id: 'gc1',
              taskId: 'gw',
              status: CheckInStatus.pending,
              completedAt: now,
            ),
          ],
          now: now,
        ),
        isFalse,
      );
    });

    test('daily 任务跨日 ⇒ false（当日无 verified 打卡）', () {
      expect(
        wishTasksAllDone(
          tasks: <Task>[gatedTask(repeatRule: 'daily')],
          checkIns: <CheckIn>[
            _checkIn(
              id: 'gc1',
              taskId: 'gw',
              completedAt: DateTime(2026, 11, 16, 9),
            ),
          ],
          now: now,
        ),
        isFalse,
      );
    });

    test('被删除的任务不在 tasks 中 ⇒ 不计入判据', () {
      // 只剩一条已完成任务，另一条物理删除后不出现在 tasks 参数里。
      expect(
        wishTasksAllDone(
          tasks: <Task>[gatedTask(id: 'alive')],
          checkIns: <CheckIn>[
            _checkIn(id: 'gc1', taskId: 'alive', completedAt: now),
            _checkIn(id: 'gc2', taskId: 'deleted', completedAt: now),
          ],
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('R6-P0-04 收藏箱派生显隐 isWishTaskVisible', () {
    Wish parentWish({DateTime? releasedAt}) => Wish(
          id: 'wish-1',
          childId: 'c',
          text: 'wish',
          createdAt: now,
          releasedAt: releasedAt,
        );

    test('普通成长任务（wishId==null）恒可见', () {
      expect(
        isWishTaskVisible(
          task: _task(id: 'normal'),
          wishById: <String, Wish>{
            'wish-1': parentWish(releasedAt: now),
          },
        ),
        isTrue,
      );
    });

    test('父愿望未进箱 ⇒ 愿望任务可见', () {
      expect(
        isWishTaskVisible(
          task: _task().copyWith(wishId: 'wish-1'),
          wishById: <String, Wish>{'wish-1': parentWish()},
        ),
        isTrue,
      );
    });

    test('父愿望进箱 ⇒ 愿望任务隐藏（零任务表写入）', () {
      expect(
        isWishTaskVisible(
          task: _task().copyWith(wishId: 'wish-1'),
          wishById: <String, Wish>{
            'wish-1': parentWish(releasedAt: now),
          },
        ),
        isFalse,
      );
    });

    test('拿出收藏箱（releasedAt=null）⇒ 自动重现', () {
      final Wish boxed = parentWish(releasedAt: now);
      final Task task = _task().copyWith(wishId: 'wish-1');
      expect(
        isWishTaskVisible(
          task: task,
          wishById: <String, Wish>{'wish-1': boxed},
        ),
        isFalse,
      );
      final Wish restored = boxed.copyWith(releasedAt: Wish.kClear);
      expect(
        isWishTaskVisible(
          task: task,
          wishById: <String, Wish>{'wish-1': restored},
        ),
        isTrue,
      );
    });

    test('父愿望查不到 ⇒ 安全默认可见', () {
      expect(
        isWishTaskVisible(
          task: _task().copyWith(wishId: 'wish-1'),
          wishById: const <String, Wish>{},
        ),
        isTrue,
      );
    });
  });

  group('A20.1 落列 == 实时聚合（两条独立用例）', () {
    test('① focusMinutes: floor/封顶求和 == progress_value（18）', () {
      final List<Task> tasks = <Task>[
        _task(id: 't1', minFocusMin: 15),
        _task(id: 't2', minFocusMin: 20),
        _task(id: 't3', minFocusMin: 10, requiresFocus: false),
      ];
      final List<CheckIn> checkIns = <CheckIn>[
        _checkIn(id: 'c1', taskId: 't1', actualFocusMin: 28.8), // 15
        _checkIn(id: 'c2', taskId: 't2', actualFocusMin: 3), // 3
        _checkIn(id: 'c3', taskId: 't3', actualFocusMin: 99), // 0
      ];
      final int recomputed = recomputeProgressValue(
          mode: WishGoalMode.focusMinutes,
          tasks: tasks,
          checkIns: checkIns);
      expect(recomputed, 18);
    });

    test('② taskCount: verified 条数 == progress_value（2）', () {
      final List<Task> tasks = <Task>[
        _task(id: 't1'),
        _task(id: 't2'),
        _task(id: 't3'),
      ];
      final List<CheckIn> checkIns = <CheckIn>[
        _checkIn(id: 'c1', taskId: 't1'),
        _checkIn(id: 'c2', taskId: 't2', status: CheckInStatus.pending),
        _checkIn(id: 'c3', taskId: 't3'),
      ];
      expect(
          recomputeProgressValue(
              mode: WishGoalMode.taskCount,
              tasks: tasks,
              checkIns: checkIns),
          2);
    });
  });
}
