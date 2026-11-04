/// F179（寇豆码 2026-10-30）：家长端·编辑卡片英文模式显中文 —— 回归守卫。
///
/// 根因（与 F154/F155-A 同源）：预制任务 / 奖励的显示名要跟随当前语言，靠
/// `seed_l10n.dart` 的 `taskDisplayName` / `rewardDisplayName` 换算；此前编辑卡片
/// 直接读 DB 里的中文 `name` 填进名称字段，英文模式下就漏成中文。
///
/// 修复（仅显示层）：`task_editor_dialog.dart` 与 `parent_reward_page.dart` 的名称字段
/// 初值改走 `taskDisplayName` / `rewardDisplayName`；存储与保存逻辑不变（用户改过名的
/// 项，`*DisplayName` 回退 storedName，原样可编辑）。
///
/// 验证（team-lead 硬性要求）：英文态（locale en）下，编辑卡片的**名称字段不含 CJK**
/// （正则 `[\u4e00-\u9FFF]` 不应匹配）；并反向确认 zh 态下**含** CJK，避免断言恒绿。
library f179_edit_card_en_no_cjk_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/seed_l10n.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/parent/widgets/task_editor_dialog.dart';

/// CJK 统一表意文字区段（U+4E00–U+9FFF）：命中即「还漏着中文」。
final RegExp _cjk = RegExp(r'[\u4e00-\u9FFF]');

/// 一条**预制种子任务**：落库名是中文默认名（模拟「首次在中文下 seed」）。
/// 其 id 命中 `kTaskSeedIds` 且 storedName 命中 `isPresetTaskSeedName`，
/// 因此 `*DisplayName` 在英文态会回退成英文。
Task _seedHomework() => const Task(
      id: 'seed_task_homework',
      name: '完成学校作业',
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: false,
    );

/// 把编辑卡片挂到**指定 locale** 的 `MaterialApp` 下并取出名称字段文本。
Future<String> _fieldText(WidgetTester tester, Locale locale, Task task) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: TaskEditorDialog(
            initial: task,
            onSave: (_) async {},
          ),
        ),
      ),
    ),
  );
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // 编辑卡里有多个 TextField（名称 + 自定义科目等）；种子任务无自定义科目，
  // 故「名称字段」= 文本非空的那个 TextField。
  final List<TextField> fields =
      tester.widgetList<TextField>(find.byType(TextField)).toList();
  final TextField tf =
      fields.firstWhere((TextField f) => (f.controller?.text ?? '').isNotEmpty);
  return tf.controller?.text ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① 英文态：编辑卡片名称字段**不含 CJK**（F179 修复点）',
      (WidgetTester tester) async {
    final String text = await _fieldText(tester, const Locale('en'), _seedHomework());

    // 核心断言：英文态下字段不得残留中文（独立于实现——只看 CJK 区段）。
    expect(text.contains(_cjk), isFalse,
        reason: '英文态下编辑卡片名称字段不得含中文（F179）');
    expect(text, isNotEmpty, reason: '字段应显示本地化名称，而非空');
    // 反向证明非恒绿：中文默认名绝不该出现在英文卡片里。
    expect(find.text('完成学校作业'), findsNothing,
        reason: '英文态下不得显示中文种子名');
  });

  testWidgets('② 反向对照：中文态下同一张卡片**含 CJK**（避免断言恒绿）',
      (WidgetTester tester) async {
    final String text = await _fieldText(tester, const Locale('zh'), _seedHomework());
    expect(text.contains(_cjk), isTrue,
        reason: '中文态下字段应显示中文（证明 F179 的 no-CJK 断言不是恒绿）');
  });

  test('③ 奖励侧同款修复：英文态 rewardDisplayName 不含 CJK（parent_reward_page 复用同一助手）',
      () {
    // parent_reward_page.dart:408 的名称字段初值走 rewardDisplayName —— 直接断言该
    // 助手在英文态对预制种子奖励返回非中文；中文态返回中文（反向对照）。
    const String zhStored = '小零食'; // seed_snack 的中文默认名
    final String en = rewardDisplayName('seed_snack', zhStored, AppLocalizationsEn());
    final String zh = rewardDisplayName('seed_snack', zhStored, AppLocalizationsZh());
    expect(en.contains(_cjk), isFalse, reason: '英文态奖励名不得含中文（F179）');
    expect(zh.contains(_cjk), isTrue, reason: '中文态奖励名应含中文（反向对照）');
  });
}
