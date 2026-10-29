/// F164 溢出探测（临时探针）：补 `en_overflow_probe_test` **未覆盖**的页面。
///
/// 起因（玄参 2026-10-29）：F161/F162/F163 连续三处「容器给死宽度、文字不许收」
/// 的英文挤压/溢出，要求全仓排查。静态扫描挑出 13 处「Row 里裸 Text 与
/// Expanded/Flexible 混排」的候选点；本文件用**最坏组合**（en + textScaler 1.3）
/// 在两个手机屏宽档（320 极窄 / 392 真机档）把候选页面真挂起来 ——
/// 用实测代替按字符数估算。
///
/// 口径同 `en_overflow_probe_test`：有界 `pump`、禁 `pumpAndSettle`（无限动画）。
library f164_overflow_probe_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/task_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_sunlight_history_page.dart';
import 'package:sunflower_time/presentation/child/pages/store_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_task_config_page.dart';
import 'package:sunflower_time/presentation/parent/pages/parent_today_page.dart';

/// 显示档：320 = 极窄档（既有探针口径）；392 = 小米 14 Pro 真机逻辑宽。
const List<double> _kWidths = <double>[320, 392];

void _useScreen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 568);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// 收集 layout 异常的**完整描述**（含出错 widget），比 `takeException` 只拿
/// 一句「overflowed by N pixels」有用得多。
class _LayoutProbe {
  final List<String> messages = <String>[];
  void Function(FlutterErrorDetails)? _old;

  void start() {
    _old = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      messages.add(details.toString());
    };
  }

  void stop() {
    FlutterError.onError = _old;
  }
}

/// 内存库 + 真实仓储；造「2 个每日任务（1 个已核销）+ 1 个每周任务」。
///
/// weekly 项是必要的：`_progressHeader` 那段最长的英文 `· Plus N weekly item(s)`
/// 只在 `board.weeklyCount > 0` 时渲染 —— 不造就测不到真正的风险行。
Future<ProviderContainer> _bootWithTasks() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences sp = await SharedPreferences.getInstance();
  final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);

  final AccountService account = AccountService(
    children: ChildProfileLocalRepository(database),
    settings: SettingsLocalRepository(database),
    prefs: sp,
  );
  await account.initialize();
  final TaskLocalRepository repo =
      TaskLocalRepository(database, account: account);

  await repo.saveTask(const Task(
    id: 't_daily_done',
    name: 'Read for 20 minutes',
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 0,
    sunlightReward: 8,
    isCustom: true,
  ));
  await repo.saveTask(const Task(
    id: 't_daily_todo',
    name: 'Practice piano for half an hour',
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 0,
    sunlightReward: 8,
    isCustom: true,
  ));
  await repo.saveTask(const Task(
    id: 't_weekly',
    name: 'Clean up the desk and put every book back on the shelf',
    subject: TaskSubject.general,
    requiresFocus: false,
    minFocusMin: 0,
    sunlightReward: 8,
    isCustom: true,
    repeatRule: 'weekly',
  ));

  final DateTime now = DateTime.now();
  await repo.checkIn(CheckIn(
    id: 'c_daily_done',
    taskId: 't_daily_done',
    date: now,
    completedAt: now,
    sessionId: 's_daily_done',
    isPerfectDay: false,
    status: CheckInStatus.verified,
    sunlightGross: 8,
    sunlightGranted: 8,
  ));

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(database),
      accountServiceProvider.overrideWithValue(account),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container, Widget page) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: L10nScope(child: Scaffold(body: page)),
      ),
    );

/// 挂一页、跑若干帧，返回收集到的 layout 异常（空 = 无溢出）。
Future<List<String>> _probe(
  WidgetTester tester,
  Widget page, {
  required double width,
  int frames = 14,
}) async {
  _useScreen(tester, width);
  final ProviderContainer container = await _bootWithTasks();
  final _LayoutProbe probe = _LayoutProbe()..start();
  try {
    await tester.pumpWidget(_host(container, page));
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } finally {
    probe.stop();
  }
  return probe.messages;
}

/// 把异常压成一行可读摘要（只取「overflowed by N」+ 出错 widget 的前两行）。
String _brief(String raw) {
  final List<String> lines = raw
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .toList();
  final String head = lines.firstWhere(
    (String l) => l.contains('overflowed') || l.contains('Exception'),
    orElse: () => lines.isEmpty ? '' : lines.first,
  );
  final int idx = lines.indexWhere((String l) => l.contains('creator'));
  final String where = idx >= 0
      ? lines.sublist(idx, (idx + 6).clamp(0, lines.length)).join(' >> ')
      : lines.take(8).join(' >> ');
  return '$head <<< $where';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() => AppLocaleController.init(AppLanguage.en));
  tearDown(() => AppLocaleController.init(AppLanguage.system));

  for (final double w in _kWidths) {
    testWidgets('① 孩子端「成长」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs = await _probe(
        tester,
        const ChildTaskPage(),
        width: w,
      );
      for (final String e in errs) {
        debugPrint('PROBE1 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下成长页不得溢出');
    });

    testWidgets('② 家长端「成长任务」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs = await _probe(
        tester,
        const ParentTaskConfigPage(embedded: true),
        width: w,
      );
      for (final String e in errs) {
        debugPrint('PROBE2 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty,
          reason: 'EN + 1.3 + ${w.toInt()} 宽下成长任务页不得溢出');
    });

    testWidgets('③ 家长端「今日」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs = await _probe(
        tester,
        const ParentTodayPage(),
        width: w,
      );
      for (final String e in errs) {
        debugPrint('PROBE3 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下家长今日页不得溢出');
    });

    // ④~⑦ 孩子端其余页：静态扫描未见裸 Text 抢宽，但同属「英文比中文长」的
    // 高危区，一并纳入探针，结论以实测为准。
    testWidgets('④ 孩子端「今日」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs =
          await _probe(tester, const ChildTodayPage(), width: w);
      for (final String e in errs) {
        debugPrint('PROBE4 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下孩子今日页不得溢出');
    });

    testWidgets('⑤ 孩子端「商店」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs =
          await _probe(tester, const StorePage(embedded: true), width: w);
      for (final String e in errs) {
        debugPrint('PROBE5 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下商店页不得溢出');
    });

    testWidgets('⑥ 孩子端「我的」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs =
          await _probe(tester, const ChildProfilePage(), width: w);
      for (final String e in errs) {
        debugPrint('PROBE6 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下「我的」页不得溢出');
    });

    testWidgets('⑦ 孩子端「阳光明细」页 · ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      final List<String> errs =
          await _probe(tester, const ChildSunlightHistoryPage(), width: w);
      for (final String e in errs) {
        debugPrint('PROBE7 ${w.toInt()}: ${_brief(e)}');
      }
      expect(errs, isEmpty, reason: 'EN + 1.3 + ${w.toInt()} 宽下阳光明细页不得溢出');
    });

    // ⑧ 任务编辑弹窗：**从真实入口进**（成长任务页「新建」按钮），而不是直挂
    //   组件 —— 弹窗宽度由 `showDialog` 的 `insetPadding` 决定，直挂测不到
    //   生产里那份留白（F164 正是靠收窄窄屏留白修的，直挂会假红）。
    testWidgets('⑧ 家长端任务编辑弹窗（真实入口）· ${w.toInt()} 宽 → 无布局异常',
        (WidgetTester tester) async {
      _useScreen(tester, w);
      final ProviderContainer container = await _bootWithTasks();
      final _LayoutProbe probe = _LayoutProbe()..start();
      try {
        await tester.pumpWidget(
            _host(container, const ParentTaskConfigPage(embedded: true)));
        for (int i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final Finder addBtn = find.text('New growth item');
        expect(addBtn, findsOneWidget,
            reason: '找不到「新建」按钮 → 本用例没走到目标分支（免费档上限 5，'
                '测试数据造了 3 个，不应被配额挡住）');
        await tester.tap(addBtn);
        for (int i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(Slider), findsWidgets,
            reason: '弹窗没打开 → 后面的溢出检测等于空跑');

        // 打开「需专注」链路 → 奖励滑块变联动（走另一条 Row）。
        final Finder focusSwitch = find.byType(Switch);
        if (focusSwitch.evaluate().isNotEmpty) {
          await tester.tap(focusSwitch.first);
          for (int i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      } finally {
        probe.stop();
      }
      for (final String e in probe.messages) {
        debugPrint('PROBE8 ${w.toInt()}: ${_brief(e)}');
      }
      expect(probe.messages, isEmpty,
          reason: 'EN + 1.3 + ${w.toInt()} 宽下任务编辑弹窗不得溢出');
    });
  }

  // ─────────────────── ⑨ 花园「加盆」格：价格是否被省略号吃掉 ───────────────────
  //
  // 这一格是 `ConstrainedBox(maxWidth: 格宽) + maxLines:1 + ellipsis` ——
  // **不抛异常**，所以上面的溢出探针永远抓不到它；但它一旦截断，
  // 被吃掉的是**价格**（`Add pot · 300☀` / `Need 120☀ more` 的数字或单位）。
  // 故单独用 `RenderParagraph.didExceedMaxLines` 直读真实布局结果。
  //
  // 格宽推算：手机 3 列（`GardenGrid.columns = 3`，`crossAxisSpacing = 6`），
  // 392 屏扣花园页左右内边距后每格 ≈ 118；320 屏 ≈ 96（组件注释同款口径）。
  for (final double cellW in <double>[96, 118]) {
    testWidgets('⑨ 花园「加盆」格 · 格宽 ${cellW.toInt()} × 1.3 字号 → 价格不被截断',
        (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpWidget(MaterialApp(
        home: L10nScope(
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: cellW,
                child: ExpandPotSlot(
                  cost: 300,
                  shortfall: 120,
                  busy: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      const String expected = 'Need 120☀ more';
      expect(find.text(expected), findsOneWidget,
          reason: '文案对不上 → 探的不是目标分支');

      final RenderParagraph p =
          tester.renderObject<RenderParagraph>(find.text(expected));
      debugPrint('PROBE9 ${cellW.toInt()}: '
          'exceeded=${p.didExceedMaxLines} size=${p.size}');
      expect(p.didExceedMaxLines, isFalse,
          reason: '「Need 120☀ more」被省略号截断了 —— 价格/数字被吃掉，'
              '孩子端会看不懂还差多少阳光');
    });
  }
}
