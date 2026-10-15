/// 内置种子「条数 + 保留清单」常驻回归测试（付费墙 · 阶段 4）。
///
/// 背景：阶段 4 把内置种子砍到 5 条（对齐免费档任务 / 奖励上限 `kFreeTaskQuota` /
/// `kFreeRewardQuota`），避免新装免费用户一上来即超限。但**条数此前无任何断言** ——
/// 有人改回 9 / 6 条时全量测试仍会绿（静默漂移）。本测试把它钉死：
///   · 任务 / 奖励种子各 **5** 条；
///   · 且保留 id 恰为约定清单（多 / 少 / 换 id 即红）。
library seed_count_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/data/local/repositories/reward_seed.dart';
import 'package:sunflower_time/data/local/task_seed.dart';

void main() {
  group('内置种子 = 5 条（阶段 4 精简版）', () {
    test('任务种子 = 5 条', () {
      expect(kSeedTasks.length, 5,
          reason: '任务种子应对齐 kFreeTaskQuota=5，避免新装免费用户一上来即超限');
    });

    test('任务种子保留 id = 约定清单', () {
      expect(
        kSeedTasks.map((t) => t.id).toSet(),
        <String>{
          'seed_task_homework',
          'seed_task_math',
          'seed_task_read',
          'seed_task_rope_skip',
          'seed_task_chores',
        },
        reason: '保留清单：作业 / 口算 / 阅读 / 跳绳 / 打扫卫生',
      );
    });

    test('奖励种子 = 5 条', () {
      expect(kSeedRewardTemplates.length, 5,
          reason: '奖励种子应对齐 kFreeRewardQuota=5');
    });

    test('奖励种子保留 id = 约定清单', () {
      expect(
        kSeedRewardTemplates.map((t) => t.id).toSet(),
        <String>{
          'seed_snack',
          'seed_extra_play',
          'seed_cartoon',
          'seed_toy',
          'seed_weekend_outing',
        },
        reason: '保留清单：小零食 / 多玩10分钟 / 动画片 / 玩具 / 周末出去玩',
      );
    });

    test('已删的旧 id 不再出现（防误加回）', () {
      final Set<String> taskIds =
          kSeedTasks.map((t) => t.id).toSet();
      final Set<String> rewardIds =
          kSeedRewardTemplates.map((t) => t.id).toSet();
      for (final String removed in <String>[
        'seed_task_english_read',
        'seed_task_english_listen',
        'seed_task_homework_first',
        'seed_task_pushup',
      ]) {
        expect(taskIds.contains(removed), isFalse,
            reason: '阶段 4 已删除的任务种子不应回归：$removed');
      }
      expect(rewardIds.contains('seed_story'), isFalse,
          reason: '阶段 4 已删除的奖励种子 seed_story 不应回归');
    });
  });
}
