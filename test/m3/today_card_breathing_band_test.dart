/// C67 · 今日页「呼吸带」**真机度量护栏**（2026-10-14 玄参 iOS 模拟器实测回归）。
///
/// ## 背景（玄参 iOS 手机模拟器截图实证）
/// 孩子端「今日」tab 第一张统计卡**顶部超出底图白色面板上沿**，骑在面板圆角上，
/// C67 那条 36pt 奶油「呼吸带」在手机上**不存在**。
///
/// ## 本文件用 RenderBox 实测证明两件事
///  ① **卡片位置合规**：第一张统计卡的实测顶部 == `屏高 × kTodayCardTopRatio`
///     （C67 冻结 0.40）—— 证明卡片没有被任何改动顶上去；
///  ② **呼吸带存在**：`卡片顶 ≥ 底图分界线`（底图分界线由 `TabBackground` 的
///     `DecorationImage.alignment` + `BoxFit.cover` 几何**实测反算**，不猜数值）。
///
/// ⚠️ 分界线是**量出来的**：读 `TabBackground.decorationKey` 的真实 `RenderBox`
/// 尺寸与对齐值，再交给 [panelTopScreenY] 反算 —— 与 `tab_bg_alignment_test.dart`
/// 同源手法，符合玄参「AI 不截图不自查 UI，布局只能靠可度量断言证明」的纪律。
///
/// 🟢 夹具纪律：不依赖网络 / 不依赖真机，纯 widget 度量。
library today_card_breathing_band_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_level_store.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

// ── 夹具（与 focus_level_today_page_test.dart 同款精简版）─────────────────

class _FakeSunlight implements SunlightRepository {
  final List<SunlightEntry> entries = <SunlightEntry>[];
  double balanceValue = 0;

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
      _refCount(refType, refId);

  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      _refCount(refType, refId);

  @override
  Future<int> countByRefType(String refType) async => 0;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) =>
      Future<DateTime?>.value(null);

  int _refCount(String refType, String refId) => entries
      .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
      .length;
}

class _FakeFocus implements FocusRepository {
  _FakeFocus({required this.totalMinutes});
  final double totalMinutes;

  @override
  Future<void> saveSession(FocusSession session) async {}

  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];

  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;

  @override
  Future<FocusStats> totalStats() async => FocusStats(
        totalFocusMinutes: totalMinutes,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _FakeTask implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[];

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

class _MemoryStore implements FocusLevelSettledStore {
  int? value;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int settledLevel) async {
    value = value == null
        ? settledLevel
        : (value! > settledLevel ? value : settledLevel);
  }

  @override
  Future<void> clear() async => value = null;
}

// ── 度量 ──────────────────────────────────────────────────────────────────

/// iPhone 6.1″（390×844）—— 玄参截图机型。
const Size _iPhone61 = Size(390, 844);

/// 仓库既有手机基准（iPhone 17，402×874）。
const Size _iPhone17 = Size(402, 874);

/// iPhone SE（375×667）—— 长宽比最「方」，cover 抬升分界线最狠的极端样本。
const Size _iPhoneSE = Size(375, 667);

/// 外壳 body 高 = 屏高 − 底部导航 ≈80（`extendBody` 未开，body 不吃底栏）。
const double _navBarH = 80;

/// 今日页第一张统计卡的**全局顶部 y**（RenderBox 实测）。
double _firstCardTop(WidgetTester tester) {
  final Finder card = find.ancestor(
    of: find.text('今日获取阳光'),
    matching: find.byType(Container),
  );
  expect(card, findsOneWidget, reason: '今日页应有「今日获取阳光」统计卡');
  final RenderBox box = tester.renderObject<RenderBox>(card);
  return box.localToGlobal(Offset.zero).dy;
}

/// 底图「场景 ↔ 留白」分界线的**全局 y**（由真实对齐值 + cover 几何反算）。
double _panelLineY(WidgetTester tester) {
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

/// 装配并 pump 今日页（模拟外壳 body：顶到屏顶、高 = 屏高 − 底栏）。
///
/// [withAppBar] = true 时套一层真实 `Scaffold + AppBar('今日')`
/// （`extendBodyBehindAppBar: true`），用于度量「徽章是否压到『今日』标题」。
Future<void> _pumpToday(WidgetTester tester, Size screen,
    {bool withAppBar = false, double statusBarHeight = 0}) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3.0;
  // 模拟 iOS 状态栏（真机上 AppBar 会被它整体下推，不模拟就量不出重叠）。
  tester.view.padding = FakeViewPadding(
    top: statusBarHeight,
    bottom: 0,
    left: 0,
    right: 0,
  );
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlight()),
      focusRepositoryProvider
          .overrideWithValue(_FakeFocus(totalMinutes: 900)),
      taskRepositoryProvider.overrideWithValue(_FakeTask()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      focusLevelStoreProvider.overrideWithValue(_MemoryStore()..value = 0),
      focusLevelServiceProvider.overrideWith((Ref ref) => FocusLevelService(
            ledger: ref.watch(sunlightRepositoryProvider),
            store: ref.watch(focusLevelStoreProvider),
            idFactory: () => 'band-probe',
          )),
    ],
  );
  addTearDown(container.dispose);
  container.read(childShellTabIndexProvider.notifier).state =
      kChildTabIndexOfToday;

  const Widget page = ChildTodayPage();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: withAppBar
            // 与 child_shell_page 同款沉浸式：AppBar 透明 + body 延伸到其下。
            ? Scaffold(
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  title: const Text('今日'),
                ),
                body: page,
              )
            : Align(
                // 外壳：extendBodyBehindAppBar ⇒ body 顶部 = 屏顶；底栏不吃 body。
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: screen.width,
                  height: screen.height - _navBarH,
                  child: page,
                ),
              ),
      ),
    ),
  );
  for (int i = 0; i < 240; i++) {
    if (find.byKey(FocusLevelBadge.badgeKey).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 16));
}

/// iPad Pro 11″ 竖屏（834×1210，shortestSide ≥ 600 → 平板档，底图主动对齐）。
const Size _iPadScreen = Size(834, 1210);

void main() {
  // ── ①a 平板：C67 冻结常量**本身不动**，内容整体下移 40pt（F142）───────────
  testWidgets('iPad 834×1210 · ①a 卡顶 == 屏高 × 0.40 + 40（F142 平板下移）',
      (WidgetTester tester) async {
    await _pumpToday(tester, _iPadScreen);

    final double cardTop = _firstCardTop(tester);
    final double panelTop = _panelLineY(tester);

    // 独立列出期望值（不引用被测常量，防自指）。
    // F142（玄参 2026-10-20 拍板）：平板内容与底图**同时**下移 40 逻辑点
    // （kTabletContentDownshift）→ 卡顶 / 分界线各 +40，呼吸带仍是 36.3pt。
    // 🔴 C67 冻结常量 0.40 / 0.37 **一个都没改**（见 tab_bg_alignment_test），
    //    这里加的是叠加在基线之上的平板增量。
    expect(cardTop, closeTo(1210 * 0.40 + kTabletContentDownshift, 0.5),
        reason: 'iPad 上卡片 = 0.40 × 屏高 + 40 = 524.0，实测 $cardTop');
    // 顺带证明平板上「0.40 − 0.37 = 3%」这条减法仍成立 ⇒ 呼吸带 36.3pt 原样。
    expect(panelTop, closeTo(1210 * 0.37 + kTabletContentDownshift, 0.5),
        reason: 'iPad 上分界线 = 0.37 × 屏高 + 40 = 487.7，实测 $panelTop');
    expect(cardTop - panelTop, closeTo(1210 * 0.03, 0.5),
        reason: 'iPad 呼吸带仍是 3% 屏高（C67 实测 36.3pt）');
  });

  // 各机型**真实状态栏高**（insets，非同值假数据）：非全面屏 SE 只有 20pt，
  // 刘海/灵动岛机型 47~59pt。用真实值，否则「徽章 ↔ 标题」断言会测出一个
  // 物理上不存在的挤占（2026-10-14 徽章上移到 0.12 后尤其敏感）。
  for (final (String name, Size screen, double statusH) in <(String, Size, double)>[
    ('iPhone 6.1″ 390×844', _iPhone61, 47),
    ('iPhone 17 402×874', _iPhone17, 59),
    // 最「方」的机型（长宽比 1.78 最偏离底图的 0.45）⇒ cover 把分界线抬得最高，
    // 是本次 bug 的**极端样本**：修法若只针对 16:9 机型，这里会立刻变红。
    ('iPhone SE 375×667', _iPhoneSE, 20),
  ]) {
    testWidgets('$name · ③徽章不侵占卡片区：徽章底 < 卡顶',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen);

      final RenderBox badge =
          tester.renderObject<RenderBox>(find.byKey(FocusLevelBadge.badgeKey));
      final double badgeBottom =
          badge.localToGlobal(Offset.zero).dy + badge.size.height;
      final double cardTop = _firstCardTop(tester);

      expect(
        badgeBottom,
        lessThan(cardTop),
        reason: 'C74 徽章（左上身份）必须整块落在卡片区之上 '
            '(徽章底 ${badgeBottom.toStringAsFixed(1)} / 卡顶 ${cardTop.toStringAsFixed(1)})',
      );
    });

    testWidgets('$name · ②呼吸带存在：实测卡顶 ≥ 底图分界线',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen);

      final double cardTop = _firstCardTop(tester);
      final double panelTop = _panelLineY(tester);

      expect(
        cardTop,
        greaterThanOrEqualTo(panelTop),
        reason: 'C67 呼吸带：卡片必须落在底图分界线**之下** '
            '(卡顶 ${cardTop.toStringAsFixed(1)} / 分界线 ${panelTop.toStringAsFixed(1)})',
      );
    });

    testWidgets('$name · ④ 徽章不与「今日」标题重叠（玄参截图反馈 · 位置下移）',
        (WidgetTester tester) async {
      // 用该机型**真实状态栏高**（见上方机型表注释）——模拟值失真会把
      // 「不重叠」测成「重叠」。
      await _pumpToday(tester, screen,
          withAppBar: true, statusBarHeight: statusH);

      final RenderBox titleBox =
          tester.renderObject<RenderBox>(find.text('今日'));
      final double titleBottom =
          titleBox.localToGlobal(Offset.zero).dy + titleBox.size.height;
      final RenderBox badge =
          tester.renderObject<RenderBox>(find.byKey(FocusLevelBadge.badgeKey));
      final double badgeTop = badge.localToGlobal(Offset.zero).dy;

      expect(
        badgeTop,
        greaterThan(titleBottom),
        reason: '徽章必须整块落在「今日」标题**之下** '
            '(标题底 ${titleBottom.toStringAsFixed(1)} / 徽章顶 ${badgeTop.toStringAsFixed(1)})',
      );
    });

    testWidgets('$name · ①b 手机：卡顶 == 实测分界线 + 3% × 屏高（同平板口径）',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen);

      final double cardTop = _firstCardTop(tester);
      final double panelTop = _panelLineY(tester);

      // 独立列出期望值（不引用被测常量，防自指）。
      expect(cardTop, closeTo(panelTop + screen.height * 0.03, 0.5),
          reason: '手机上卡片也必须落在「分界线 + 3% 屏高呼吸带」，实测 $cardTop');
      // 手机端分界线由 cover 几何决定（恒 topCenter），**不等于** 0.37 × 屏高 ——
      // 这正是本 bug 的根源，断言它以免有人把「0.40 − 0.37」的减法再搬回手机。
      expect(panelTop, isNot(closeTo(screen.height * 0.37, 1.0)),
          reason: '手机端底图恒 topCenter ⇒ 分界线 ≠ 0.37 × 屏高（本 bug 根因）');
    });
  }
}
