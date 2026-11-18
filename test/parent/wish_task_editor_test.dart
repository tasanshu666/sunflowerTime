/// A-T05 家长端 WishTaskEditor 断言 ⑩~⑬（A21.4 / PRD W23.2 / R1~R8）。
///
/// 期望值写死独立量，不引用实现常量；护栏判据独立构造输入，
/// 通过UI编辑器暴露的纯函数 [judgeGoalChange] / [goalValueChoices] 验证。
library wish_task_editor_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/presentation/parent/widgets/wish_task_editor.dart';

void main() {
  group('⑩ 口径切换与 mode0 行为型收窄', () {
    test('目标值真量生成：mode0 含 10/600 不含 5；mode1 含 1/5 不含 6', () {
      final List<int> focus = goalValueChoices(WishGoalMode.focusMinutes);
      final List<int> count = goalValueChoices(WishGoalMode.taskCount);
      expect(focus.contains(10), isTrue);
      expect(focus.contains(kWishGoalFocusMinutesMax), isTrue);
      expect(focus.contains(5), isFalse, reason: '低于 focus min（10）');
      expect(count.contains(1), isTrue);
      expect(count.contains(5), isTrue);
      expect(count.contains(6), isFalse, reason: '高于 task max（5）');
      expect(count.length, 5, reason: 'task 口径 1..5，真量 5 个');
    });

    test('mode0 编辑器不给行为型选项（源码守卫：focusMode 强制 requiresFocus=true）', () {
      final String src = File(
              'lib/presentation/parent/widgets/wish_task_editor.dart')
          .readAsStringSync();
      // mode0 下新建任务的 requiresFocus 恒 true，且行为型开关被 if(!_focusMode) 包住。
      expect(src.contains('requiresFocus: _focusMode ? true : draft.requiresFocus'),
          isTrue,
          reason: 'mode0 强制专注型（R8）');
      expect(src.contains('if (!_focusMode)'), isTrue,
          reason: '专注型开关只在非 mode0 显示');
    });
  });

  group('⑪ 任务条数达上限的提示', () {
    test('kWishTaskMaxCount 真量 = 5；上限提示文案含最大值', () {
      expect(kWishTaskMaxCount, 5);
      expect(srcHasMaxHint(), isTrue);
    });
  });

  group('⑫ 新建任务不改分母（进度不跳动）', () {
    test('assignTasks 判据：只写 tasks.wishId，不碰 target/progress（领域源码守卫）', () {
      final String src =
          File('lib/domain/services/wish_orchestration_service.dart')
              .readAsStringSync();
      final int start = src.indexOf('Future<List<String>> assignTasks(');
      final int end = src.indexOf('Future<Wish> fulfill(', start);
      final String body = src.substring(start, end);
      expect(body.contains('assignWish('), isTrue);
      expect(body.contains('copyWith('), isFalse,
          reason: 'assignTasks 不写愿望行（分母/进度不动）');
      expect(RegExp(r'targetValue\s*:').hasMatch(body), isFalse);
      expect(RegExp(r'progressValue\s*:').hasMatch(body), isFalse);
    });
  });

  group('⑬ 目标下调 / 上调护栏', () {
    test('下调 ⇒ decrease + 钳制到 max(requested, progress)', () {
      final GoalChangeVerdict v = judgeGoalChange(
        oldTarget: 30,
        requestedTarget: 20,
        progressValue: 25,
      );
      expect(v.kind, GoalChangeKind.decrease);
      expect(v.clampedValue, 25, reason: '钳制到已完成 25');

      final GoalChangeVerdict v2 = judgeGoalChange(
        oldTarget: 30,
        requestedTarget: 10,
        progressValue: 5,
      );
      expect(v2.kind, GoalChangeKind.decrease);
      expect(v2.clampedValue, 10, reason: 'progress<requested 时钳到 requested');
    });

    test('上调超双重护栏 ⇒ rejected（请分几次调整）', () {
      // 旧目标 10，已做 3：ratio 上限 floor(10*1.5)=15；progress 上限 3*3=9 ⇒ cap=9。
      final GoalChangeVerdict v = judgeGoalChange(
        oldTarget: 10,
        requestedTarget: 12,
        progressValue: 3,
        rejectReason: '请分几次调整',
      );
      expect(v.kind, GoalChangeKind.rejected);
      expect(v.reason, '请分几次调整');
    });

    test('上调配额内 ⇒ increase；未变更 ⇒ unchanged', () {
      final GoalChangeVerdict inc = judgeGoalChange(
        oldTarget: 20,
        requestedTarget: 25,
        progressValue: 20,
      );
      expect(inc.kind, GoalChangeKind.increase);
      final GoalChangeVerdict same = judgeGoalChange(
        oldTarget: 20,
        requestedTarget: 20,
        progressValue: 8,
      );
      expect(same.kind, GoalChangeKind.unchanged);
    });

    test('首次设定（oldTarget=0）不走护栏，直接 increase', () {
      final GoalChangeVerdict v = judgeGoalChange(
        oldTarget: 0,
        requestedTarget: 30,
        progressValue: 0,
      );
      expect(v.kind, GoalChangeKind.increase);
    });

    test('护栏真源复用领域函数（clampedGoalAfterDecrease / upscaleAllowed）', () {
      // 编辑器判据须与领域纯函数逐值一致，不允许另写公式。
      expect(
        judgeGoalChange(
          oldTarget: 100,
          requestedTarget: 50,
          progressValue: 70,
        ).clampedValue,
        clampedGoalAfterDecrease(requestedTarget: 50, progressValue: 70),
      );
      expect(
        judgeGoalChange(
          oldTarget: 10,
          requestedTarget: 14,
          progressValue: 3,
        ).kind == GoalChangeKind.rejected,
        isTrue,
        reason: '14 > min(15, 9)=9 ⇒ 拒（与 upscaleAllowed 同口径）',
      );
    });
  });
}

/// 上限提示文案存在（独立读源码，不依赖编辑器实例）。
bool srcHasMaxHint() => File('lib/presentation/parent/widgets/wish_task_editor.dart')
    .readAsStringSync()
    .contains('parent_wish_task_max(kWishTaskMaxCount)');
