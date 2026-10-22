/// 枚举 → 文案守卫（i18n B3 · T02）：补 B1/B2 的**分区头漏网**。
///
/// ## 漏的是什么
/// 成长页（`child_task_page.dart`）与阳光商店（`store_page.dart`）的分类**分区头**
/// 原先直读 domain 的 `TaskCategoryX.label` / `RewardContentCategoryX.label`
/// —— 中文写死在枚举里，切 en 后整页英文、唯独两个分区标题仍是「学习 / 零食」。
/// B1/B2 迁移时按页面扫文案，**没扫到枚举扩展**，故漏网。
///
/// ## 本文件钉什么
///  · **渲染层**：三条 label 函数在 zh / en 下的**逐字**输出（en 必须无 CJK）；
///  · **接线层**：两个页面源码必须已改成调用 l10n 函数，且**不得**再出现
///    `cat.label` 这类 domain 直读（防止有人「修回去」）。
///
/// 🔴 为什么不做整页 pump：这两页的真实装配牵扯 task/reward/usage 三套仓储 +
/// 账号服务，夹具成本高且与本缺陷无关 —— 缺陷根因是「文案来源」，不是「渲染
/// 逻辑」。分区头文案一旦来自 ARB，页面渲染必然跟随（`L10nScope` 已由 B1 兜住）。
library enum_l10n_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/enum_l10n.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

final RegExp _cjkRe = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');

/// 造一个最小 Task（只填断言需要的字段）。
Task _task(TaskSubject subject, {String? customSubject}) => Task(
      id: 't1',
      name: 'x',
      subject: subject,
      customSubject: customSubject,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: false,
    );

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();
  final AppLocalizationsEn en = AppLocalizationsEn();

  group('taskCategoryLabel（成长页分区头）', () {
    const Map<TaskCategory, String> zhTable = <TaskCategory, String>{
      TaskCategory.other: '其他',
      TaskCategory.learning: '学习',
      TaskCategory.sports: '运动',
      TaskCategory.life: '生活',
      TaskCategory.habit: '习惯',
    };
    const Map<TaskCategory, String> enTable = <TaskCategory, String>{
      TaskCategory.other: 'Other',
      TaskCategory.learning: 'Learning',
      TaskCategory.sports: 'Sports',
      TaskCategory.life: 'Life',
      TaskCategory.habit: 'Habit',
    };

    for (final TaskCategory c in TaskCategory.values) {
      test('${c.name}：zh「${zhTable[c]}」/ en「${enTable[c]}」', () {
        expect(taskCategoryLabel(c, zh), zhTable[c]);
        expect(taskCategoryLabel(c, en), enTable[c]);
        expect(_cjkRe.hasMatch(taskCategoryLabel(c, en)), isFalse,
            reason: '${c.name} 的 en 分区头含 CJK —— 又是枚举硬编码漏网');
      });
    }
  });

  group('rewardContentCategoryLabel（商店页分区头）', () {
    const Map<RewardContentCategory, String> zhTable =
        <RewardContentCategory, String>{
      RewardContentCategory.other: '其他',
      RewardContentCategory.snacks: '零食',
      RewardContentCategory.play: '游玩',
      RewardContentCategory.entertainment: '娱乐',
      RewardContentCategory.toys: '玩具',
      RewardContentCategory.books: '阅读',
    };
    const Map<RewardContentCategory, String> enTable =
        <RewardContentCategory, String>{
      RewardContentCategory.other: 'Other',
      RewardContentCategory.snacks: 'Snacks',
      RewardContentCategory.play: 'Play',
      RewardContentCategory.entertainment: 'Entertainment',
      RewardContentCategory.toys: 'Toys',
      RewardContentCategory.books: 'Books',
    };

    for (final RewardContentCategory c in RewardContentCategory.values) {
      test('${c.name}：zh「${zhTable[c]}」/ en「${enTable[c]}」', () {
        expect(rewardContentCategoryLabel(c, zh), zhTable[c]);
        expect(rewardContentCategoryLabel(c, en), enTable[c]);
        expect(_cjkRe.hasMatch(rewardContentCategoryLabel(c, en)), isFalse,
            reason: '${c.name} 的 en 分区头含 CJK —— 又是枚举硬编码漏网');
      });
    }
  });

  group('taskSubjectLabel（复用他人 key，零新增键）', () {
    const Map<TaskSubject, String> zhTable = <TaskSubject, String>{
      TaskSubject.chinese: '语文',
      TaskSubject.math: '数学',
      TaskSubject.english: '英语',
      TaskSubject.general: '通用',
      TaskSubject.custom: '自定义',
    };
    const Map<TaskSubject, String> enTable = <TaskSubject, String>{
      TaskSubject.chinese: 'Chinese',
      TaskSubject.math: 'Math',
      TaskSubject.english: 'English',
      TaskSubject.general: 'General',
      TaskSubject.custom: 'Custom',
    };

    for (final TaskSubject s in TaskSubject.values) {
      test('${s.name}：zh「${zhTable[s]}」/ en「${enTable[s]}」', () {
        expect(taskSubjectLabel(s, zh), zhTable[s]);
        expect(taskSubjectLabel(s, en), enTable[s]);
        expect(_cjkRe.hasMatch(taskSubjectLabel(s, en)), isFalse);
      });
    }
  });

  group('taskDisplaySubject（替代已删除的 Task.subjectLabel getter）', () {
    test('custom + 非空白 customSubject → 原样回显用户输入（不翻译）', () {
      final Task t = _task(TaskSubject.custom, customSubject: '  书法  ');
      expect(taskDisplaySubject(t, zh), '书法');
      expect(taskDisplaySubject(t, en), '书法',
          reason: '自定义科目名是家长写的自由文本，任何语言下都原样显示');
    });

    test('custom + null / 空白 → 回落「自定义 / Custom」', () {
      expect(taskDisplaySubject(_task(TaskSubject.custom), zh), '自定义');
      expect(
        taskDisplaySubject(_task(TaskSubject.custom, customSubject: '   '), zh),
        '自定义',
      );
      expect(taskDisplaySubject(_task(TaskSubject.custom), en), 'Custom');
    });

    test('非 custom → 取该科目固定名', () {
      expect(taskDisplaySubject(_task(TaskSubject.math), zh), '数学');
      expect(taskDisplaySubject(_task(TaskSubject.math), en), 'Math');
      expect(taskDisplaySubject(_task(TaskSubject.general), en), 'General');
    });
  });

  group('接线守卫：两个页面不得再直读 domain 的 label', () {
    test('child_task_page 分区头走 taskCategoryLabel（且无 cat.label）', () {
      final String src =
          File('lib/presentation/child/pages/child_task_page.dart').readAsStringSync();
      expect(src.contains('taskCategoryLabel(cat, _t)'), isTrue,
          reason: '成长页分区头必须经 ARB 取文案（英文环境才不落中文）');
      expect(src.contains('cat.label'), isFalse,
          reason: '`cat.label` 已从 domain 删除；出现即代表有人绕过 l10n');
    });

    test('store_page 分区头走 rewardContentCategoryLabel（且无 cat.label）', () {
      final String src =
          File('lib/presentation/child/pages/store_page.dart').readAsStringSync();
      expect(src.contains('rewardContentCategoryLabel(cat, _t)'), isTrue,
          reason: '商店页分区头必须经 ARB 取文案');
      expect(src.contains('cat.label'), isFalse,
          reason: '`cat.label` 已从 domain 删除；出现即代表有人绕过 l10n');
    });

    test('domain 枚举不再暴露 label getter（只留 emoji icon）', () {
      final String src =
          File('lib/domain/entities/enums.dart').readAsStringSync();
      expect(src.contains('String get label'), isFalse,
          reason: 'domain 不得再承载中文分类名（零 CJK 纪律）');
      expect(src.contains('String get icon'), isTrue,
          reason: 'emoji 是符号不是文案，icon 必须留在 domain');
    });

    test('task.dart 不再有 subjectLabel / categoryLabel getter', () {
      final String src = File('lib/domain/entities/task.dart').readAsStringSync();
      expect(src.contains('String get subjectLabel'), isFalse);
      expect(src.contains('String get categoryLabel'), isFalse);
      expect(src.contains('String get categoryIcon'), isTrue);
    });
  });
}
