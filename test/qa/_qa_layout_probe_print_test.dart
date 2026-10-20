/// F142 · QA 布局量测探针 A（**打印版**，严过关 Round 1）。
///
/// ## 用途
/// 只**打印**实测数值、不做 F142 断言 —— 同一份文件在两个树上跑：
///  · 本树（工作区，含 F142 改动）→ 得到「改后」数值表；
///  · /tmp 私有副本（lib 全部回退 HEAD）→ 得到「改前」数值表；
/// 两表逐行 diff ⇒ 手机端「逐像素一致」与平板端「恰 +40」的**实测**证据。
///
/// 只依赖 HEAD 就存在的冻结常量（kTodayCardTopRatio / kTodayBgPanelTargetRatio /
/// kGrowthListTopRatio / kTodayBgSrcSize / kTodayBgPanelTopFraction），
/// 故在 HEAD 树也能编译。
library qa_layout_probe_print_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/data/local/database/app_database.dart' as db;
import 'package:sunflower_time/data/local/repositories/child_profile_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/plant_local_repository.dart';
import 'package:sunflower_time/data/local/repositories/settings_local_repository.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/account_service.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_shell_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_task_page.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/shared/adaptive_nav_bar.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

const List<(String, Size)> _kScreens = <(String, Size)>[
  ('phone390', Size(390, 844)),
  ('phone402', Size(402, 874)),
  ('ipad11_1194', Size(834, 1194)),
  ('ipad11_1210', Size(834, 1210)),
  ('ipad13', Size(1032, 1376)),
];

class _FakeSunlight implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double balanceValue = 320;

  @override
  Future<double> append(SunlightEntry entry) async {
    entries.add(entry);
    balanceValue += entry.net;
    return balanceValue;
  }

  @override
  Future<double> balance() async => balanceValue;

  @override
  Future<List<SunlightEntry>> all() async => List<SunlightEntry>.of(entries);

  @override
  Future<double> dayNet(String dayKey) async => 0;

  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;

  @override
  Future<double> earnNetOnDay(String dayKey) async => 52;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async => 0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
          String refType, String refId, String dayKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) =>
      Future<DateTime?>.value(null);
}

class _FakeFocus implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 900,
        totalSessions: 12,
        totalValidDays: 5,
      );
}

class _FakeTask implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[
        const Task(
          id: 'qa_probe_t',
          name: '朗读英语',
          subject: TaskSubject.general,
          requiresFocus: false,
          minFocusMin: 15,
          sunlightReward: 12,
          isCustom: true,
        ),
      ];

  @override
  Future<void> saveTask(Task task) async {}

  @override
  Future<void> deleteTaskById(String id) async {}

  @override
  Future<void> checkIn(CheckIn checkIn) async {}

  @override
  Future<List<CheckIn>> checkInsOfDay(String dayKey) async => <CheckIn>[];

  @override
  Future<int> totalCheckInCount() async => 0;
}

class _FakeSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings(
        ageTier: AgeTier.low,
        dailyFocusCap: 60,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: 160,
        gardenPotCapacity: 4,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _MemoryLevelStore implements FocusLevelSettledStore {
  int? value;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int settledLevel) async {
    value = settledLevel;
  }

  @override
  Future<void> clear() async => value = null;
}

void _useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 0);
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (BuildContext ctx, Widget? child) {
          final Widget content = child ?? const SizedBox.shrink();
          final MediaQueryData mq =
              MediaQuery.maybeOf(ctx) ?? const MediaQueryData();
          final MediaQueryData scaled = applyTabletTextScaling(mq);
          if (identical(scaled, mq)) return content;
          return MediaQuery(data: scaled, child: content);
        },
        home: home,
      ),
    );

ProviderContainer _pagesContainer() {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlight()),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      taskRepositoryProvider.overrideWithValue(_FakeTask()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      focusLevelStoreProvider.overrideWithValue(_MemoryLevelStore()),
      focusLevelServiceProvider.overrideWith((Ref ref) => FocusLevelService(
            ledger: ref.watch(sunlightRepositoryProvider),
            store: ref.watch(focusLevelStoreProvider),
            idFactory: () => 'qa-probe',
          )),
    ],
  );
  addTearDown(container.dispose);
  container.read(childShellOnStageProvider.notifier).state = true;
  return container;
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 16}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _todayCardTop(WidgetTester tester) {
  final Finder card = find.ancestor(
    of: find.text('今日获取阳光'),
    matching: find.byType(Container),
  );
  return tester.renderObject<RenderBox>(card).localToGlobal(Offset.zero).dy;
}

double _todayPanelLineY(WidgetTester tester) {
  final Finder decoration = find.byKey(TabBackground.decorationKey);
  final RenderBox box = tester.renderObject<RenderBox>(decoration);
  final DecoratedBox widget = tester.widget<DecoratedBox>(decoration);
  final BoxDecoration deco = widget.decoration as BoxDecoration;
  final Alignment alignment = deco.image!.alignment as Alignment;
  final double localY = panelTopScreenY(
    box: box.size,
    src: kTodayBgSrcSize,
    panelTopFraction: kTodayBgPanelTopFraction,
    alignmentY: alignment.y,
  );
  return box.localToGlobal(Offset.zero).dy + localY;
}

double _taskSceneGap(WidgetTester tester) {
  final Finder clip = find
      .ancestor(of: find.byType(ListView), matching: find.byType(ClipRect))
      .first;
  return tester.getTopLeft(clip).dy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA 探针 A：今日/成长 页实测数值表（打印）', (WidgetTester tester) async {
    for (final (String name, Size screen) in _kScreens) {
      // 今日页
      _useScreen(tester, screen);
      final ProviderContainer c = _pagesContainer();
      c.read(childShellTabIndexProvider.notifier).state = kChildTabIndexOfToday;
      await tester.pumpWidget(_app(const ChildTodayPage(), c));
      await _pumpFrames(tester);
      final double cardTop = _todayCardTop(tester);
      final double panelTop = _todayPanelLineY(tester);
      print('QA_PROBE_A today $name cardTop=${cardTop.toStringAsFixed(2)} '
          'panelTop=${panelTop.toStringAsFixed(2)} '
          'band=${(cardTop - panelTop).toStringAsFixed(2)}');

      // 成长页
      final ProviderContainer c2 = _pagesContainer();
      c2.read(childShellTabIndexProvider.notifier).state =
          kChildTabIndexOfGrowth;
      await tester.pumpWidget(
        _app(const Scaffold(body: ChildTaskPage()), c2),
      );
      await _pumpFrames(tester);
      final double gap = _taskSceneGap(tester);
      print('QA_PROBE_A task  $name sceneGap=${gap.toStringAsFixed(2)}');
    }
  });

  testWidgets('QA 探针 A：外壳底栏实测数值表（打印）', (WidgetTester tester) async {
    for (final (String name, Size screen) in _kScreens) {
      _useScreen(tester, screen);
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
      final DateTime now = DateTime.now();
      await PlantLocalRepository(database, account: account).savePlant(
        Plant(
          id: 'plant_qa_probe',
          speciesId: 'sunflower',
          potIndex: 0,
          stage: PlantStage.seed,
          stageStartedAt: now,
          growthFactor: 1.0,
          status: PlantStatus.growing,
          plantedAt: now,
        ),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(sp),
          appDatabaseProvider.overrideWithValue(database),
          accountServiceProvider.overrideWithValue(account),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_app(const ChildShellPage(), container));
      await _pumpFrames(tester, frames: 20);

      final RenderBox nav =
          tester.renderObject<RenderBox>(find.byType(NavigationBar));
      final Size navSize = nav.size;
      final Offset navOrigin = nav.localToGlobal(Offset.zero);
      final Finder host = find.byType(AdaptiveNavBarHost);
      final String hostW = host.evaluate().isEmpty
          ? 'absent'
          : tester
              .renderObject<RenderBox>(host)
              .size
              .width
              .toStringAsFixed(2);
      // label 实测（第一个 label 即可代表行高表现；逐 label 在探针 B 断言）。
      final Finder label0 = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('今日'),
      );
      final String labelInfo = label0.evaluate().isEmpty
          ? 'absent'
          : () {
              final RenderParagraph rp =
                  tester.renderObject<RenderParagraph>(label0);
              return 'h=${rp.size.height.toStringAsFixed(2)} '
                  'top=${rp.localToGlobal(Offset.zero).dy.toStringAsFixed(2)}';
            }();
      print('QA_PROBE_A nav    $name barH=${navSize.height.toStringAsFixed(2)} '
          'barW=${navSize.width.toStringAsFixed(2)} '
          'barTop=${navOrigin.dy.toStringAsFixed(2)} hostW=$hostW label($labelInfo)');
    }
  });
}
