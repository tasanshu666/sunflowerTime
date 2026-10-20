/// F142 · 平板布局微调的证据性测试（玄参 iPad Pro 13″ 真机反馈）。
///
/// ## 需求（玄参 2026-10-20 拍板）
///  ① 「今日」与「成长」两页内容（含底图）在**平板**上下移 **40 逻辑点**
///     （单位 = pt，iPad 11″ 与 13″ 同量，不做屏高比例换算）→ 切 tab 不跳动；
///  ② 底部 5 个 tab 的 **label 文字太小** → 平板下 label 字号 / icon / 栏高三者
///     同乘 `uiScaleOf`（iPad 11″ ×1.3 = 15.6 / iPad 13″ ×1.6 = 19.2，栏高 104 / 128）；
///  ③ **手机必须逐像素零回归**（本文件的手机档断言就是回归证据）。
///
/// ## 度量手法（= 玄参「AI 不截图不自查 UI」纪律）
/// 不猜数值、不引用被测常量自指：一律读**真实 RenderBox**（卡片顶 / 底图分界线 /
/// 列表裁剪上沿 / NavigationBar 渲染盒），期望值**独立写成字面算式**。
///
/// ⚠️ 全程禁用 `pumpAndSettle`：今日页阳光气泡、花园页木牌呼吸是无限动画。
library f142_tablet_layout_shift_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
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
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

// ── 视口样本 ─────────────────────────────────────────────────────────────────

/// iPhone 6.1″（玄参手机截图机型）。
const Size _kPhone390 = Size(390, 844);

/// 仓库既有手机基准（iPhone 17）。
const Size _kPhone402 = Size(402, 874);

/// iPad Pro 11″ 竖屏 —— 倍率锚点屏（1.3）。
const Size _kIpad11 = Size(834, 1210);

/// iPad Pro 13″ 竖屏 —— 本次缺陷机型（1.6）。
const Size _kIpad13 = Size(1032, 1376);

// ── 假件（供「今日」「成长」两页最小可渲染装配）──────────────────────────────

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
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

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

/// 一条「今日必做」成长项（`repeatRule == null` ⇒ isDaily）。
Task _dailyTask() => const Task(
      id: 'f142_t_read',
      name: '朗读英语',
      subject: TaskSubject.general,
      requiresFocus: false,
      minFocusMin: 15,
      sunlightReward: 12,
      isCustom: true,
    );

class _FakeTask implements TaskRepository {
  _FakeTask() : _store = <Task>[_dailyTask()];

  final List<Task> _store;

  @override
  Future<List<Task>> tasks() async => List<Task>.of(_store);

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
        dailyFocusCap: kDailyFocusCapLow,
        dailyAppCapMinutes: 30,
        restAfterSessions: 2,
        restMinutes: 10,
        taskSunlight: 12,
        poolBudget: kPoolBudgetDefaultLow,
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

// ── 通用夹具 ─────────────────────────────────────────────────────────────────

/// 设视口 + 注入平板文字倍率（与 `app.dart` **同一个**注入点
/// [applyTabletTextScaling]，避免「测的是我写死的 1.6」）。
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
          if (identical(scaled, mq)) return content; // 手机：不引入 MediaQuery
          return MediaQuery(data: scaled, child: content);
        },
        home: home,
      ),
    );

/// 「今日」「成长」两页的共用容器（页面只吃这几个仓储）。
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
            idFactory: () => 'f142-probe',
          )),
    ],
  );
  addTearDown(container.dispose);
  container.read(childShellOnStageProvider.notifier).state = true;
  return container;
}

/// 有界 pump（两页都有无限动画，禁用 `pumpAndSettle`）。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 抽干本帧期间的**全部**异常（overflow 以 FlutterError 形式进入这里）。
List<Object> _drainExceptions(WidgetTester tester) {
  final List<Object> all = <Object>[];
  for (int i = 0; i < 20; i++) {
    final Object? e = tester.takeException();
    if (e == null) break;
    all.add(e);
  }
  return all;
}

// ── 度量 ─────────────────────────────────────────────────────────────────────

/// 「今日」页第一张统计卡的**全局顶 y**（RenderBox 实测）。
double _todayCardTop(WidgetTester tester) {
  final Finder card = find.ancestor(
    of: find.text('今日获取阳光'),
    matching: find.byType(Container),
  );
  expect(card, findsOneWidget, reason: '今日页应有「今日获取阳光」统计卡');
  return tester.renderObject<RenderBox>(card).localToGlobal(Offset.zero).dy;
}

/// 今日页底图「场景 ↔ 留白」分界线**全局 y**（由真实对齐值 + cover 几何反算）。
double _todayPanelLineY(WidgetTester tester) {
  final Finder decoration = find.byKey(TabBackground.decorationKey);
  expect(decoration, findsOneWidget, reason: '今日页应有一张底图');
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

/// 「成长」页列表**裁剪上沿 / 列表起点**（= 顶部留白 `sceneGap` 的实测值）。
///
/// 结构（`_taskList`）= `Column[ SizedBox(height: sceneGap), Expanded(ClipRect(ListView)) ]`
/// → 最近一个包住 ListView 的 ClipRect 的顶 = sceneGap。
double _taskSceneGap(WidgetTester tester) {
  final Finder clip = find
      .ancestor(of: find.byType(ListView), matching: find.byType(ClipRect))
      .first;
  return tester.getTopLeft(clip).dy;
}

Future<void> _pumpToday(WidgetTester tester, Size screen) async {
  _useScreen(tester, screen);
  final ProviderContainer container = _pagesContainer();
  container.read(childShellTabIndexProvider.notifier).state =
      kChildTabIndexOfToday;
  await tester.pumpWidget(_app(const ChildTodayPage(), container));
  await _pumpFrames(tester, frames: 16);
}

Future<void> _pumpTask(WidgetTester tester, Size screen) async {
  _useScreen(tester, screen);
  final ProviderContainer container = _pagesContainer();
  container.read(childShellTabIndexProvider.notifier).state =
      kChildTabIndexOfGrowth;
  // ⚠️ 必须套一层 [Scaffold]：任务卡用 InkWell（墨溅需要 Material 祖先），
  // 外壳里本来由外层的 Material 提供；直挂会抛 `No Material widget found`。
  await tester.pumpWidget(
    _app(const Scaffold(body: ChildTaskPage()), container),
  );
  await _pumpFrames(tester, frames: 16);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 手机：逐像素零回归 ────────────────────────────────────────────────
  group('① 手机零回归（手机侧 downshift 恒 0）', () {
    testWidgets('390×844 · 今日：卡顶 == 实测分界线 + 3% 屏高（与改动前同式）',
        (WidgetTester tester) async {
      await _pumpToday(tester, _kPhone390);

      final double cardTop = _todayCardTop(tester);
      final double panelTop = _todayPanelLineY(tester);

      // 呼吸带 = 3% 屏高 = 25.32pt（手机由 cover 几何决定，不含 40pt 下移）。
      expect(cardTop - panelTop, closeTo(844 * 0.03, 0.5),
          reason: '手机呼吸带必须仍是 3% 屏高 25.32pt（实测 ${cardTop - panelTop}）');
      // 零回归的**绝对**证据：卡顶远小于「0.40 × 屏高 + 40」。
      expect(cardTop, lessThan(844 * 0.40 + kTabletContentDownshift - 1),
          reason: '手机绝不许吃平板的 40pt 下移（实测卡顶 $cardTop）');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('402×874 · 今日：卡顶 == 实测分界线 + 3% 屏高、且无 40pt 下移',
        (WidgetTester tester) async {
      await _pumpToday(tester, _kPhone402);

      final double cardTop = _todayCardTop(tester);
      final double panelTop = _todayPanelLineY(tester);

      expect(cardTop - panelTop, closeTo(874 * 0.03, 0.5),
          reason: '手机呼吸带 = 26.22pt（实测 ${cardTop - panelTop}）');
      expect(cardTop, lessThan(874 * 0.40 + kTabletContentDownshift - 1));
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('390×844 · 成长：列表起点 == 屏高 × 0.34（286.96pt）',
        (WidgetTester tester) async {
      await _pumpTask(tester, _kPhone390);

      expect(_taskSceneGap(tester), closeTo(844 * 0.34, 0.5),
          reason: '手机成长页列表起点必须仍是 844 × 0.34 = 286.96pt');
      expect(_taskSceneGap(tester), lessThan(844 * 0.34 + 1),
          reason: '手机不许吃 40pt 下移');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('402×874 · 成长：列表起点 == 屏高 × 0.34（297.16pt）',
        (WidgetTester tester) async {
      await _pumpTask(tester, _kPhone402);

      expect(_taskSceneGap(tester), closeTo(874 * 0.34, 0.5),
          reason: '手机成长页列表起点必须仍是 874 × 0.34 = 297.16pt');
      expect(_drainExceptions(tester), isEmpty);
    });
  });

  // ── ② 平板：整体下移 40 逻辑点 ──────────────────────────────────────────
  group('② 平板下移 40pt（含底图同步，切 tab 不跳动）', () {
    testWidgets('iPad 11″ 834×1210 · 今日：卡顶 == 0.40×屏高 + 40 = 524.0',
        (WidgetTester tester) async {
      await _pumpToday(tester, _kIpad11);

      final double cardTop = _todayCardTop(tester);
      final double panelTop = _todayPanelLineY(tester);

      expect(kTabletContentDownshift, 40.0, reason: '玄参拍板：单位逻辑点 40');
      expect(cardTop, closeTo(1210 * 0.40 + 40, 0.5),
          reason: 'iPad 11″ 卡顶必须 = 484.0 + 40 = 524.0（实测 $cardTop）');
      // 底图同步下移 → 分界线 = 447.7 + 40 = 487.7（呼吸带仍是 36.3pt）。
      expect(panelTop, closeTo(1210 * 0.37 + 40, 0.5),
          reason: 'iPad 11″ 分界线必须 = 447.7 + 40 = 487.7（实测 $panelTop）');
      expect(cardTop - panelTop, closeTo(36.3, 0.5),
          reason: 'C67 的 36.3pt 呼吸带必须原样保住');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('iPad 13″ 1032×1376 · 今日：卡顶 == 0.40×屏高 + 40 = 590.4',
        (WidgetTester tester) async {
      await _pumpToday(tester, _kIpad13);

      final double cardTop = _todayCardTop(tester);
      final double panelTop = _todayPanelLineY(tester);

      expect(cardTop, closeTo(1376 * 0.40 + 40, 0.5),
          reason: 'iPad 13″ 卡顶必须 = 550.4 + 40 = 590.4（实测 $cardTop）');
      expect(panelTop, closeTo(1376 * 0.37 + 40, 0.5),
          reason: 'iPad 13″ 分界线必须 = 509.1 + 40 = 549.1（实测 $panelTop）');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('iPad 11″ · 成长：列表起点 == 0.34×屏高 + 40 = 451.4',
        (WidgetTester tester) async {
      await _pumpTask(tester, _kIpad11);

      expect(_taskSceneGap(tester), closeTo(1210 * 0.34 + 40, 0.5),
          reason: 'iPad 11″ 成长页起点必须 = 411.4 + 40 = 451.4pt');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('iPad 13″ · 成长：列表起点 == 0.34×屏高 + 40 = 507.84',
        (WidgetTester tester) async {
      await _pumpTask(tester, _kIpad13);

      expect(_taskSceneGap(tester), closeTo(1376 * 0.34 + 40, 0.5),
          reason: 'iPad 13″ 成长页起点必须 = 467.84 + 40 = 507.84pt');
      expect(_drainExceptions(tester), isEmpty);
    });
  });

  // ── ③ 底部 tab 栏（真实 ChildShellPage）──────────────────────────────────
  group('③ 底部 tab 栏：平板放大 / 手机原样', () {
    late db.AppDatabase database;

    /// 建库 + 造数（一株植物防花园页空态）+ 设视口，pump 真实外壳。
    Future<void> bootShell(WidgetTester tester, Size size) async {
      _useScreen(tester, size);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences sp = await SharedPreferences.getInstance();
      database = db.AppDatabase(NativeDatabase.memory());
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
          id: 'plant_f142',
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
    }

    testWidgets('手机 402×874：**零 Theme 覆盖**、栏高仍是 80、label 仍是 M3 默认 12',
        (WidgetTester tester) async {
      await bootShell(tester, _kPhone402);

      final BuildContext navCtx = tester.element(find.byType(NavigationBar));
      final NavigationBarThemeData theme = NavigationBarTheme.of(navCtx);

      // 零回归的最强形式：手机端**一个字段都没覆盖**。
      expect(theme.height, isNull, reason: '手机端不得覆盖栏高（走 M3 默认 80）');
      expect(theme.labelTextStyle, isNull, reason: '手机端不得覆盖 label 样式');
      expect(theme.iconTheme, isNull, reason: '手机端不得覆盖 icon 尺寸');
      expect(tester.getSize(find.byType(NavigationBar)).height, 80,
          reason: '手机栏高必须仍是 M3 默认 80pt');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('手机 390×844：同样零覆盖（小屏手机也不许放大）',
        (WidgetTester tester) async {
      await bootShell(tester, _kPhone390);

      final NavigationBarThemeData theme =
          NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
      expect(theme.height, isNull);
      expect(theme.labelTextStyle, isNull);
      expect(tester.getSize(find.byType(NavigationBar)).height, 80);
    });

    testWidgets('iPad 11″ 834×1210：label 15.6 / icon 31.2 / 栏高 104',
        (WidgetTester tester) async {
      await bootShell(tester, _kIpad11);

      final BuildContext navCtx = tester.element(find.byType(NavigationBar));
      final NavigationBarThemeData theme = NavigationBarTheme.of(navCtx);
      final ColorScheme cs = Theme.of(navCtx).colorScheme;

      expect(uiScaleOf(navCtx), 1.3, reason: '锚点屏倍率必须仍是 1.3');
      final TextStyle? selected = theme.labelTextStyle
          ?.resolve(<WidgetState>{WidgetState.selected});
      final TextStyle? unselected =
          theme.labelTextStyle?.resolve(<WidgetState>{});
      expect(selected?.fontSize, closeTo(12 * 1.3, 0.01),
          reason: 'label 字号 = 12 × 1.3 = 15.6');
      expect(unselected?.fontSize, closeTo(12 * 1.3, 0.01));
      // M3 语义色必须保住（覆盖 labelTextStyle 时最容易丢的就是 color）。
      expect(selected?.color, cs.onSurface,
          reason: '选中态 label 必须仍是 onSurface（M3 语义）');
      expect(unselected?.color, cs.onSurfaceVariant,
          reason: '未选中态 label 必须仍是 onSurfaceVariant（M3 语义）');

      final IconThemeData? icon =
          theme.iconTheme?.resolve(<WidgetState>{WidgetState.selected});
      expect(icon?.size, closeTo(24 * 1.3, 0.01),
          reason: 'icon 尺寸 = 24 × 1.3 = 31.2');
      expect(tester.getSize(find.byType(NavigationBar)).height, closeTo(104, 0.01),
          reason: '栏高 = 80 × 1.3 = 104');
      expect(_drainExceptions(tester), isEmpty);
    });

    testWidgets('iPad 13″ 1032×1376：label 19.2 / icon 38.4 / 栏高 128',
        (WidgetTester tester) async {
      await bootShell(tester, _kIpad13);

      final BuildContext navCtx = tester.element(find.byType(NavigationBar));
      final NavigationBarThemeData theme = NavigationBarTheme.of(navCtx);

      expect(uiScaleOf(navCtx), 1.6, reason: 'iPad 13″ 倍率钳到上限 1.6');
      final TextStyle? selected = theme.labelTextStyle
          ?.resolve(<WidgetState>{WidgetState.selected});
      expect(selected?.fontSize, closeTo(12 * 1.6, 0.01),
          reason: 'label 字号 = 12 × 1.6 = 19.2');
      final IconThemeData? icon =
          theme.iconTheme?.resolve(<WidgetState>{WidgetState.selected});
      expect(icon?.size, closeTo(24 * 1.6, 0.01),
          reason: 'icon 尺寸 = 24 × 1.6 = 38.4');
      expect(tester.getSize(find.byType(NavigationBar)).height, closeTo(128, 0.01),
          reason: '栏高 = 80 × 1.6 = 128');
      expect(_drainExceptions(tester), isEmpty);
    });
  });

  // ── ④ 常量自检（防「改基线常量代替叠加增量」）──────────────────────────────
  test('④ C67/C46d 冻结基线常量不得被本次改动（只允许叠加 40pt 增量）', () {
    expect(kTodayCardTopRatio, 0.40, reason: 'C67 冻结值不许动');
    expect(kTodayBgPanelTargetRatio, 0.37, reason: 'C67 冻结值不许动');
    expect(kGrowthListTopRatio, 0.34, reason: 'C46d 标定值不许动');
    expect(kTabletContentDownshift, 40.0, reason: 'F142 增量 = 40 逻辑点');
    // 增量与基线是两个独立概念：增量绝不该被折进基线。
    expect(kTodayCardTopRatio * 1210 + kTabletContentDownshift,
        closeTo(524.0, 0.001));
    expect(kGrowthListTopRatio * 1210 + kTabletContentDownshift,
        closeTo(451.4, 0.001));
  });
}
