/// 预制任务 / 奖励**显示名**跟随语言（F154，玄参 2026-10-26 拍板）。
///
/// ## 背景
/// 种子行只在首启播种一次（i18n B3 · T05），DB 里的 name 落定后不改写
///（`seed_locale_test.dart` ③ 钉死）。此前英文用户会在任务板 / 商店看到
/// DB 中文行（「完成学校作业 / 小零食」）。F154 起**显示层**映射：
/// `taskDisplayName` / `rewardDisplayName`（`core/i18n/seed_l10n.dart`）。
///
/// ## 本文件守什么（四组）
/// ① zh 库行 + en 显示 → 英文（本批目的）；en 库行 + zh 显示 → 中文（往返对称）；
/// ② 家长改过名（不是任何语言的默认名）→ **原样显示**（用户数据优先，绝不覆盖）；
/// ③ 非种子 id（自定义任务 / 奖励）→ 原样显示；
/// ④ en 种植卡量词（`garden_seed_count` 复数：1 seed / N seeds，本批顺带补单位）。
///
/// 纯 dart 测试：只测映射函数与 ARB 产物，不挂 widget。
library seed_display_name_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/seed_l10n.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  group('① 种子行显示名跟随语言（DB 行不动）', () {
    test('任务：zh 库名 → en 显示英文；en 库名 → zh 显示中文（往返对称）', () {
      for (final String id in kTaskSeedIds) {
        final String zhName = taskSeedName(id, zh);
        final String enName = taskSeedName(id, en);
        expect(taskDisplayName(id, zhName, en), enName,
            reason: '$id 的 zh 库名在 en 下必须显示英文名');
        expect(taskDisplayName(id, enName, zh), zhName,
            reason: '$id 的 en 库名在 zh 下必须显示中文名（往返对称）');
        // 同名同语言 = 原样（避免再走一遍映射仍出错）。
        expect(taskDisplayName(id, enName, en), enName);
      }
    });

    test('奖励：同上', () {
      for (final String id in kRewardSeedIds) {
        final String zhName = rewardSeedName(id, zh);
        final String enName = rewardSeedName(id, en);
        expect(rewardDisplayName(id, zhName, en), enName,
            reason: '$id 的 zh 库名在 en 下必须显示英文名');
        expect(rewardDisplayName(id, enName, zh), zhName,
            reason: '$id 的 en 库名在 zh 下必须显示中文名');
      }
    });

    test('isPreset 判定：两语言默认名都算预制，其它名不算', () {
      expect(isPresetTaskSeedName('seed_task_homework', '完成学校作业'), isTrue);
      expect(
          isPresetTaskSeedName('seed_task_homework', 'Finish school homework'),
          isTrue);
      expect(isPresetTaskSeedName('seed_task_homework', '写作业'), isFalse);
      expect(isPresetRewardSeedName('seed_snack', '小零食'), isTrue);
      expect(isPresetRewardSeedName('seed_snack', 'A small snack'), isTrue);
      expect(isPresetRewardSeedName('seed_snack', '好吃的'), isFalse);
    });
  });

  group('② 家长改过名 → 原样显示（用户数据优先）', () {
    test('任务改名后切语言不被映射回默认名', () {
      expect(taskDisplayName('seed_task_homework', '写作业', en), '写作业');
      expect(taskDisplayName('seed_task_homework', 'Homework time', zh),
          'Homework time');
    });

    test('奖励改名后同上', () {
      expect(rewardDisplayName('seed_snack', '一根棒棒糖', en), '一根棒棒糖');
      expect(rewardDisplayName('seed_snack', 'Lollipop', zh), 'Lollipop');
    });
  });

  group('③ 非种子 id（自定义任务 / 奖励）→ 原样显示', () {
    test('自定义 id 即使名字恰好等于默认名也不参与映射（id 优先判定）', () {
      // 名字撞默认名但 id 不是种子 → 原样（其实等价，但语义上走 fallback 分支）。
      expect(taskDisplayName('task_custom_1', '完成学校作业', en),
          '完成学校作业');
      expect(rewardDisplayName('reward_custom_1', '小零食', en), '小零食');
      // 普通 id + 普通名。
      expect(taskDisplayName('task_custom_1', '练琴', zh), '练琴');
      expect(rewardDisplayName('reward_custom_1', 'Park trip', en), 'Park trip');
    });

    test('未知种子 id 的名字不是默认名 → 原样（回退 id 分支不受影响）', () {
      // 历史被删的种子 id：taskSeedName 回退 id 本身，isPreset 对任意名 false
      //（名字 != id）→ 显示原名。
      expect(taskDisplayName('seed_task_gone', '旧任务', en), '旧任务');
    });
  });

  group('④ en 种植卡量词（F154 补单位）', () {
    test('garden_seed_count 复数：1 seed / N seeds', () {
      expect(en.garden_seed_count(1), '1 seed');
      expect(en.garden_seed_count(2), '2 seeds');
      expect(en.garden_seed_count(0), '0 seeds');
    });

    test('zh 保持「{count} 粒」（上一批口径不变）', () {
      expect(zh.garden_seed_count(1), '1 粒');
      expect(zh.garden_seed_count(0), '0 粒');
    });
  });
}
