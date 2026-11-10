/// 守卫调试 · **可见反馈**护栏（玄参真机：「恢复随机剧本」点了没有任何响应）。
///
/// 真源：`guard_debug_script.dart`（覆盖注入点 + 按钮 Key）+
/// `guard_debug_labels.dart`（`debugGuardModeLabel` 单一文案口径）+
/// `bloom_debug_panel.dart` 的 `_guardSection()`（模式常显行 / 每按钮回执 /
/// 「恢复随机」置灰）。
///
/// ## 病根（为什么之前「点了没反应」）
/// 无覆盖时点「恢复随机」= `provider.state = null` 清 null ⇒ **值没变化**
/// ⇒ Riverpod 不通知 ⇒ 面板不重建 ⇒ 今日页也不 `ref.listen` 到变化
/// ⇒ 零反馈。用户视角与「按钮坏了」完全一致。
///
/// ## 覆盖
/// | # | 断言 | 层级 |
/// |---|---|---|
/// | ① | 无覆盖：模式行 = 「随机派生」；「恢复随机」`onPressed == null`（灰） | 面板 |
/// | ② | 点「强制 5 只怪」⇒ provider 写入 5 只 + 模式行当帧变「强制覆盖 · 5 只」+ 回执「已生效」+ 「恢复随机」亮起 | 面板 → provider |
/// | ③ | 有覆盖点「恢复随机」⇒ provider 归 null + 回执「已恢复随机剧本」+ 模式行回「随机派生」+ 按钮回灰 | 面板 → provider |
/// | ④ | 既有 7 个按钮也有回执（以「刷新出偷菜贼」为代表）⇒ 不是只给新按钮打补丁 | 面板 |
/// | ⑤ | `debugGuardModeLabel` 纯函数：null / 全 m1 / 混编 / 高偷窃 四档字面量 | 单元 |
///
/// 🔴 全文件有界 `pump`（面板含加载圈 + 无限动画，绝不 `pumpAndSettle`）。
library guard_debug_feedback_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/guard_battle_sim.dart'
    show GuardBattleMonsterKind, GuardBattleScript;
import 'package:sunflower_time/presentation/child/state/guard_debug_script.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_debug_labels.dart';

// ═══════════════════════════════════════════════════════════════════════
// 夹具（真库 + 真 prefs + 真面板；与 guard_debug_script_test 同款最小集）
// ═══════════════════════════════════════════════════════════════════════

class _Env {
  _Env({required this.sp, required this.database, required this.account});

  final SharedPreferences sp;
  final db.AppDatabase database;
  final AccountService account;
}

/// 空花园也能进守卫区块（`_guardSection()` 在 `_plants.isEmpty` 分支里）——
/// 本文件不种植物，故只建孩子档案 + 初始化账号。
Future<_Env> _makeEnv(String childId) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await ChildProfileLocalRepository(database)
      .create('回执调试娃', AgeTier.high, id: childId);
  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  return _Env(sp: sp, database: database, account: account);
}

ProviderContainer _container(_Env env) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(env.sp),
      appDatabaseProvider.overrideWithValue(env.database),
      accountServiceProvider.overrideWithValue(env.account),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _panelHost(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: BloomDebugSheet(maxHeight: 640)),
      ),
    );

/// 打开面板（直挂 sheet，不经路由动画）并滚到剧本按钮组。
///
/// 就绪信号 = 加载圈**消失**（`guard_debug_panel_test` 同款纪律：不能等文本，
/// 守卫分组在 `ListView` 最末尾、懒构建窗口外）。
Future<void> _openPanel(WidgetTester tester,
    ProviderContainer container) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_panelHost(container));
  bool loaded = false;
  for (int i = 0; i < 240; i++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      loaded = true;
      break;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(loaded, isTrue, reason: '面板应完成 _refresh（加载圈消失）');

  await tester.scrollUntilVisible(
    find.text('强制 3 只怪'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// 面板动作收尾（`_run` 的 `_refresh` + `onChanged` + bump 全异步 ⇒ 有界推进）。
Future<void> _settleAction(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// 按 Key 点击（先 `ensureVisible`：Wrap 末排按钮可能在视口外）。
Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settleAction(tester);
}

/// 按文本点击（既有 7 个按钮没有 Key，沿用面板既有 finder 口径）。
Future<void> _tapText(WidgetTester tester, String text) async {
  final Finder f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settleAction(tester);
}

FilledButton _button(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(find.byKey(ValueKey<String>(key)));

/// 读带 Key 的文本内容（模式常显行 / 回执行）。
String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key))).data ?? '';

// ═══════════════════════════════════════════════════════════════════════

void main() {
  testWidgets('① 无覆盖：模式行=随机派生，「恢复随机剧本」置灰（onPressed == null）',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('child_fb_1');
    final ProviderContainer c = _container(env);
    await _openPanel(tester, c);

    // 纯函数与面板文案必须同源（防两处漂移）。
    expect(_textOf(tester, kDebugGuardModeTextKey), debugGuardModeLabel(null));
    expect(_textOf(tester, kDebugGuardModeTextKey),
        '当前模式：随机派生（跟随今日 seed）');
    expect(_button(tester, kDebugGuardScriptKeyFollow).onPressed, isNull,
        reason: '无覆盖 ⇒ 「恢复随机」必须灰掉（null→null 是空操作，'
            '可点但无反应正是玄参连报两轮的根因）');
  });

  testWidgets('② 点「强制 5 只怪」⇒ 覆盖写入 + 模式行当帧更新 + 回执 + 恢复按钮亮起',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('child_fb_2');
    final ProviderContainer c = _container(env);
    await _openPanel(tester, c);

    await _tapKey(tester, kDebugGuardScriptKeyCount5);

    final GuardBattleScript? ov =
        c.read(debugGuardBattleScriptOverrideProvider);
    expect(ov, isNotNull, reason: '「强制 5 只怪」必须写覆盖');
    expect(ov!.monsters.length, 5);
    expect(_textOf(tester, kDebugGuardModeTextKey), contains('强制覆盖 · 5 只'));
    expect(_textOf(tester, kDebugGuardModeTextKey), '当前模式：强制覆盖 · 5 只 · 全 m1',
        reason: '缺省阵容全 m1（最慢 13pt/s，便于观察）；偷取轮转 1/2/3/1/2 '
            '不是全员封顶 ⇒ 不带「高偷窃」尾标');
    expect(_textOf(tester, kDebugGuardFeedbackTextKey), contains('已生效'),
        reason: '每个按钮都必须有面板内可见回执（玄参「点了没反应」）');
    expect(_textOf(tester, kDebugGuardFeedbackTextKey), contains('强制覆盖 · 5 只'));
    expect(_button(tester, kDebugGuardScriptKeyFollow).onPressed, isNotNull,
        reason: '有覆盖 ⇒ 「恢复随机」必须亮起');
  });

  testWidgets('③ 有覆盖点「恢复随机」⇒ provider 归 null + 回执 + 模式行回随机 + 按钮回灰',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('child_fb_3');
    final ProviderContainer c = _container(env);
    await _openPanel(tester, c);

    // 先用「强制三怪混编」造出覆盖（顺带覆盖混编尾标文案）。
    await _tapKey(tester, kDebugGuardScriptKeyMixed);
    expect(c.read(debugGuardBattleScriptOverrideProvider), isNotNull);
    expect(_textOf(tester, kDebugGuardModeTextKey), contains('混编 m1/m2/m3'));

    await _tapKey(tester, kDebugGuardScriptKeyFollow);

    expect(c.read(debugGuardBattleScriptOverrideProvider), isNull,
        reason: '「恢复随机」必须真正清覆盖');
    expect(_textOf(tester, kDebugGuardFeedbackTextKey), contains('已恢复随机剧本'));
    expect(_textOf(tester, kDebugGuardModeTextKey), debugGuardModeLabel(null));
    expect(_button(tester, kDebugGuardScriptKeyFollow).onPressed, isNull,
        reason: '清完覆盖 ⇒ 按钮立刻回到灰态（状态自洽）');
  });

  testWidgets('④ 既有按钮也有回执（「刷新出偷菜贼」）⇒ 反馈覆盖整个守卫区块',
      (WidgetTester tester) async {
    final _Env env = await _makeEnv('child_fb_4');
    final ProviderContainer c = _container(env);
    await _openPanel(tester, c);

    expect(find.byKey(const ValueKey<String>(kDebugGuardFeedbackTextKey)),
        findsNothing,
        reason: '未点任何按钮前不应有回执行（避免「假回执」）');

    await _tapText(tester, '刷新出偷菜贼');

    expect(_textOf(tester, kDebugGuardFeedbackTextKey), contains('已刷新出偷菜贼'),
        reason: '既有 7 个按钮同样必须有回执，不能只给 B5a 新按钮打补丁');
    // 造贼不动剧本覆盖 ⇒ 模式行仍是随机派生（回执与模式互不污染）。
    expect(_textOf(tester, kDebugGuardModeTextKey), debugGuardModeLabel(null));
  });

  test('⑤ debugGuardModeLabel：null / 全 m1 / 混编 / 高偷窃 四档字面量', () {
    expect(debugGuardModeLabel(null), '当前模式：随机派生（跟随今日 seed）');

    final GuardBattleScript three = buildGuardBattleScriptForDebug(monsterCount: 3);
    expect(debugGuardModeLabel(three), '当前模式：强制覆盖 · 3 只 · 全 m1');

    final GuardBattleScript mixed = buildGuardBattleScriptForDebug(
      monsterCount: 3,
      kinds: const <GuardBattleMonsterKind>[
        GuardBattleMonsterKind.m1,
        GuardBattleMonsterKind.m2,
        GuardBattleMonsterKind.m3,
      ],
    );
    expect(debugGuardModeLabel(mixed),
        '当前模式：强制覆盖 · 3 只 · 混编 m1/m2/m3');

    final GuardBattleScript theft =
        buildGuardBattleScriptForDebug(monsterCount: 3, highTheft: true);
    expect(debugGuardModeLabel(theft),
        '当前模式：强制覆盖 · 3 只 · 全 m1 · 高偷窃 3☀');
  });
}
