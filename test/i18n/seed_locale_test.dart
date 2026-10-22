/// 种子模板 / 默认孩子名的语言守卫（i18n B3 · T05）。
///
/// ## 迁移动机
/// 迁移前「种子数据的 name 就是文案」，英文用户首装看到的是
/// 「完成学校作业 / 练习数学口算 / 小零食」—— 因为播种发生在冷启动、文案写死在
/// `kSeedTasks[i].name` / `kSeedRewardTemplates[i].name` 里。
///
/// ## 本文件守什么（三组）
/// ① **zh 逐字节等价**：注入 zh 取值器时，落库的任务 / 奖励 / 孩子名必须与迁移前
///    一字不差（含「阅读 20 分钟」这种带空格的、和「1分钟跳绳170个以上」这种无空格的）；
/// ② **en 真英文且无 CJK**：这是本批的目的；
/// ③ **预置中文行 byte 级不变**：库里已有中文行时，用 en 取值器再播种必须是 **no-op**
///    —— 换语言**不许**改写用户数据（C69 / F109）。这条是本批最容易被「优化」掉的
///    约束，故直接断言落库字符串的 UTF-8 字节。
///
/// 装配：内存 drift 库 + 真实仓储（`TaskLocalRepository` / `RewardLocalRepository` /
/// `ChildProfileLocalRepository`），只覆盖基础设施，不 mock 仓储。
library seed_locale_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/i18n/seed_l10n.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/reward_seed.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/data/local/task_seed.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// zh 任务种子名（迁移前 `kSeedTasks[i].name` 原文，逐字节）。
const List<String> _zhTaskNames = <String>[
  '完成学校作业',
  '练习数学口算',
  '阅读 20 分钟',
  '1分钟跳绳170个以上',
  '帮助家长打扫卫生',
];

/// en 任务种子名。
const List<String> _enTaskNames = <String>[
  'Finish school homework',
  'Practice mental math',
  'Read for 20 minutes',
  'Jump rope 170+ times in a minute',
  'Help tidy up at home',
];

/// zh 奖励种子名（迁移前 `kSeedRewardTemplates[i].name` 原文）。
const List<String> _zhRewardNames = <String>[
  '小零食',
  '睡前多玩10分钟',
  '看一集动画片',
  '买一个小玩具',
  '周末出去玩',
];

/// en 奖励种子名。
const List<String> _enRewardNames = <String>[
  'A small snack',
  '10 more minutes before bed',
  'Watch one cartoon episode',
  'A small toy',
  'A weekend outing',
];

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  late db.AppDatabase database;
  late TaskLocalRepository taskRepo;
  late RewardLocalRepository rewardRepo;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    taskRepo = TaskLocalRepository(database);
    rewardRepo = RewardLocalRepository(database);
  });

  // ───────────────────── ① zh 逐字节等价 ─────────────────────
  group('① zh 逐字节等价（注入 zh 取值器 = 迁移前行为）', () {
    test('5 条任务名一字不差（顺序 = kTaskSeedTemplates）', () async {
      await ensureTaskSeed(taskRepo, nameOf: (String id) => taskSeedName(id, zh));
      final List<String> names = <String>[
        for (final String id in kTaskSeedIds)
          (await taskRepo.tasks()).firstWhere((t) => t.id == id).name,
      ];
      expect(names, _zhTaskNames);
    });

    test('5 条奖励名一字不差', () async {
      await ensureRewardSeed(
          rewardRepo, nameOf: (String id) => rewardSeedName(id, zh));
      final List<String> names = <String>[
        for (final String id in kRewardSeedIds)
          (await rewardRepo.templates()).firstWhere((t) => t.id == id).name,
      ];
      expect(names, _zhRewardNames);
    });

    test('默认孩子名 = 「孩子」', () {
      expect(defaultChildName(zh), '孩子');
    });
  });

  // ───────────────────── ② en 真英文 ─────────────────────
  group('② en 生效（本批目的）', () {
    test('5 条任务名英文且无 CJK', () async {
      await ensureTaskSeed(taskRepo, nameOf: (String id) => taskSeedName(id, en));
      final List<String> names = <String>[
        for (final String id in kTaskSeedIds)
          (await taskRepo.tasks()).firstWhere((t) => t.id == id).name,
      ];
      expect(names, _enTaskNames);
      for (final String n in names) {
        expect(_cjk.hasMatch(n), isFalse, reason: 'en 任务名含 CJK：$n');
      }
    });

    test('5 条奖励名英文且无 CJK', () async {
      await ensureRewardSeed(
          rewardRepo, nameOf: (String id) => rewardSeedName(id, en));
      final List<String> names = <String>[
        for (final String id in kRewardSeedIds)
          (await rewardRepo.templates()).firstWhere((t) => t.id == id).name,
      ];
      expect(names, _enRewardNames);
      for (final String n in names) {
        expect(_cjk.hasMatch(n), isFalse, reason: 'en 奖励名含 CJK：$n');
      }
    });

    test('默认孩子名 = Child', () {
      expect(defaultChildName(en), 'Child');
    });

    test('种子 id 全覆盖：没有一个 id 落到「回退 id」分支', () {
      for (final String id in kTaskSeedIds) {
        expect(taskSeedName(id, zh), isNot(id),
            reason: '$id 未在 taskSeedName 的 switch 里（漏了就上屏 id）');
        expect(taskSeedName(id, en), isNot(id));
      }
      for (final String id in kRewardSeedIds) {
        expect(rewardSeedName(id, zh), isNot(id),
            reason: '$id 未在 rewardSeedName 的 switch 里');
        expect(rewardSeedName(id, en), isNot(id));
      }
    });

    test('未知 id 回退 id 本身（不是空串，便于立刻发现漏配）', () {
      expect(taskSeedName('seed_task_unknown', en), 'seed_task_unknown');
      expect(rewardSeedName('seed_unknown', en), 'seed_unknown');
    });
  });

  // ───────────────── ③ 预置中文行 byte 级不变 ─────────────────
  group('③ 已有中文行不许被改写（换语言不改用户数据）', () {
    test('任务：先 zh 播种，再用 en 取值器播种 → 表非空即 no-op', () async {
      await ensureTaskSeed(taskRepo, nameOf: (String id) => taskSeedName(id, zh));
      final List<String> before = <String>[
        for (final String id in kTaskSeedIds)
          (await taskRepo.tasks()).firstWhere((t) => t.id == id).name,
      ];

      // 关键：**同一个库**，换成 en 取值器再播一次。
      await ensureTaskSeed(taskRepo, nameOf: (String id) => taskSeedName(id, en));

      final List<String> after = <String>[
        for (final String id in kTaskSeedIds)
          (await taskRepo.tasks()).firstWhere((t) => t.id == id).name,
      ];
      expect(after, before, reason: '表非空 → 播种必须是 no-op');
      // byte 级：UTF-8 编码后逐字节相同（比 == 更硬，连 NFC/NFD 差异都能抓）。
      for (int i = 0; i < before.length; i++) {
        expect(after[i].codeUnits, before[i].codeUnits,
            reason: '第 $i 条任务名的 UTF-16 码元序列必须完全一致');
        expect(_cjk.hasMatch(after[i]), isTrue,
            reason: '历史中文行必须还是中文（不许被英文覆盖）');
      }
      expect(after, _zhTaskNames);
    });

    test('奖励：同上', () async {
      await ensureRewardSeed(
          rewardRepo, nameOf: (String id) => rewardSeedName(id, zh));
      await ensureRewardSeed(
          rewardRepo, nameOf: (String id) => rewardSeedName(id, en));

      final List<String> after = <String>[
        for (final String id in kRewardSeedIds)
          (await rewardRepo.templates()).firstWhere((t) => t.id == id).name,
      ];
      expect(after, _zhRewardNames,
          reason: '已有奖励模板的中文名不许被 en 播种覆盖');
    });

    test('孩子档案：已有档案不会被改语言影响', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final ChildProfileLocalRepository children =
          ChildProfileLocalRepository(database);

      // 先用 zh 取值器补建默认孩子。
      final AccountService first = AccountService(
        children: children,
        settings: SettingsLocalRepository(database),
        prefs: sp,
        defaultChildName: () => defaultChildName(zh),
      );
      await first.initialize();
      expect((await children.children()).single.name, '孩子');

      // 再用 en 取值器 initialize（新实例 = 冷启动切语言后的场景）。
      final AccountService second = AccountService(
        children: children,
        settings: SettingsLocalRepository(database),
        prefs: sp,
        defaultChildName: () => defaultChildName(en),
      );
      await second.initialize();
      expect((await children.children()).single.name, '孩子',
          reason: '表非空 → 不补建，已有「孩子」档案不许被改成 Child');
    });
  });

  // ───────────────── ④ 模板本身不再持有 name ─────────────────
  group('④ 模板结构守卫（name 已彻底移出）', () {
    test('kTaskSeedTemplates / kSeedRewardTemplates 各 5 条，id 与 id 清单一致', () {
      expect(kTaskSeedTemplates.length, 5);
      expect(kSeedRewardTemplates.length, 5);
      expect(
        kTaskSeedTemplates.map((TaskSeedTemplate t) => t.id).toList(),
        kTaskSeedIds,
        reason: '模板顺序必须与 seed_l10n 的 id 清单一致（错位即换名）',
      );
      expect(
        kSeedRewardTemplates.map((RewardSeedTemplate t) => t.id).toList(),
        kRewardSeedIds,
      );
    });

    test('toTask / toTemplate 只吃 name（其余字段自洽）', () {
      final TaskSeedTemplate task = kTaskSeedTemplates.first;
      expect(task.toTask(name: 'X').name, 'X');
      expect(task.toTask(name: 'X').id, task.id);
      expect(task.toTask(name: 'X').isCustom, isFalse,
          reason: '种子任务不是用户自定义');

      final RewardSeedTemplate reward = kSeedRewardTemplates.first;
      expect(reward.toTemplate(name: 'Y').name, 'Y');
      expect(reward.toTemplate(name: 'Y').id, reward.id);
    });

    test('奖励种子保留 parentHandled + weekly（口径不漂移）', () {
      for (final RewardSeedTemplate t in kSeedRewardTemplates) {
        expect(t.category, RewardCategory.parentHandled);
        expect(t.cooldownRule, CooldownRule.weekly);
      }
    });
  });
}
