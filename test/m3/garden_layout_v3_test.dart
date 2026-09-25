/// 花园页 v3 改造的**布局与交互度量测试**（2026-09-24）。
///
/// ## 覆盖范围（对应 v3 四项改动）
///  1. 背景图 `BoxFit.cover` 映射 + 木牌屏幕矩形（纯函数，纯 dart test）；
///  2. 花盆区底界落在背景菜地上沿之上；
///  3. 网格**锁 2 行**（可视高度来自生产纯函数 [gardenGridVisibleHeight]）+
///     **真实 `GardenPage`** 用例断言第 3 行在视口外、滚动条可见、`maxScrollExtent > 0`；
///  4. 加号圆**对齐花盆视觉中心**（圆心 y、外径均按 pot.png 像素 bbox 独立推导）；
///  5. 三类格子底部文案底边对齐 + 五态字色 WCAG 对比度 ≥ 4.5:1；
///  6. 木牌热区可点 / 呼吸动画可关停 / 打开「玩法说明」。
///
/// ## 防自指纪律（QA 复核重点）
///  · 木牌屏幕矩形、加号圆心/外径的**期望值一律独立推导**（源图像素 / bbox 像素），
///    **不得引用被测常量** —— 否则改常量测试不变红，等于没有断言；
///  · 「锁 2 行」必须由**真实页面**覆盖（不能只在测试里复刻算式）。
///
/// ## 其它
///  · 呼吸动画是无限循环 → 涉及 `GardenPage` / `GardenSignHotspot(animate:true)` 处
///    **禁止 `pumpAndSettle`**，改用有界的 `pump(Duration)` 逐帧推进。
library garden_layout_v3_test;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/garden_page.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';

// ───────────────────────────────────────────────────────────────────────────
// 造数据 / 宿主辅助
// ───────────────────────────────────────────────────────────────────────────

/// 造一株测试用植物（字段取最小必需集）。
Plant _plant({
  String id = 'p1',
  int potIndex = 0,
  PlantStage stage = PlantStage.sprout,
  PlantStatus status = PlantStatus.growing,
  double progress = 0.4,
}) {
  final DateTime t = DateTime(2026, 9, 24, 8);
  return Plant(
    id: id,
    speciesId: 'species_sunflower',
    potIndex: potIndex,
    stage: stage,
    stageStartedAt: t,
    growthProgress: progress,
    growthFactor: 1.0,
    status: status,
    plantedAt: t,
  );
}

const PlantSpecies _sunflower = PlantSpecies(
  id: 'species_sunflower',
  name: '向日葵',
  rarity: Rarity.common,
  baseCostHigh: 40,
  baseCostLow: 20,
  growthHoursPerStage: 240,
);

/// 模拟手机屏（逻辑像素）。
void _setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 宿主：把某组件放进固定尺寸的盒子里渲染。
Widget _boxed({
  required double width,
  required double height,
  required Widget child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: width, height: height, child: child)),
    ),
  );
}

/// WCAG 2.x 相对亮度。
double _relativeLuminance(Color c) {
  double lin(double s) =>
      s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// WCAG 2.x 对比度（≥ 4.5:1 为 AA 正文达标）。
double _contrastRatio(Color fg, Color bg) {
  final double a = _relativeLuminance(fg);
  final double b = _relativeLuminance(bg);
  final double hi = math.max(a, b);
  final double lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// **独立推导**木牌屏幕矩形：直接用背景源图像素区间 + cover 映射公式算，
/// **不引用**被测常量 [kGardenSignNormalizedRect]（破自指 → 改常量必红）。
///
/// 标定来源：`background.png`（玄参 2026-09-23 换图后重标）左下角木牌，
/// 源图像素 x 86.6~272.4 / y 1499.7~1686.6，画布 1056×2336。
Rect _expectedSignScreenRect(Size box) {
  const double srcW = 1056, srcH = 2336;
  const double x0 = 86.6, x1 = 272.4, y0 = 1499.7, y1 = 1686.6;
  final double scale = math.max(box.width / srcW, box.height / srcH);
  final double drawnW = srcW * scale, drawnH = srcH * scale;
  final double ox = (box.width - drawnW) / 2;
  final double oy = (box.height - drawnH) / 2;
  double mapX(double sx) => ox + (sx / srcW) * drawnW;
  double mapY(double sy) => oy + (sy / srcH) * drawnH;
  return Rect.fromLTRB(mapX(x0), mapY(y0), mapX(x1), mapY(y1));
}

// ───────────────────────────────────────────────────────────────────────────
// 真实 GardenPage 宿主的假仓储（参考 test/nav/nav_structure_test.dart 的覆盖手法）
// ───────────────────────────────────────────────────────────────────────────

AppSettings _settingsWithCapacity(int capacity) => AppSettings(
      ageTier: AgeTier.low,
      dailyFocusCap: 90,
      dailyAppCapMinutes: 30,
      restAfterSessions: 2,
      restMinutes: 10,
      taskSunlight: 12,
      poolBudget: 160,
      gardenPotCapacity: capacity,
    );

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this.capacity);
  final int capacity;
  @override
  Future<AppSettings> getSettings() async => _settingsWithCapacity(capacity);
  @override
  Future<void> saveSettings(AppSettings s) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 999.0;
  @override
  Future<double> balance() async => 999.0;
  @override
  Future<double> dayNet(String dayKey) async => 0;
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
  Future<DateTime?> lastTsByRefTypeAndRefId(String refType, String refId) async =>
      null;
  @override
  Future<double> earnGrossOnDay(String dayKey) async => 0;
  @override
  Future<double> earnNetOnDay(String dayKey) async => 0;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
}

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 0,
        totalSessions: 0,
        totalValidDays: 0,
      );
}

class _FakePlantRepository implements PlantRepository {
  @override
  Future<List<Plant>> plants() async => <Plant>[];
  @override
  Future<Plant?> plant(String id) async => null;
  @override
  Future<void> savePlant(Plant plant) async {}
  @override
  Future<void> deletePlant(String id) async {}
  @override
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[_sunflower];
}

/// 渲染**真实** `GardenPage(embedded: true)`，容量由假设置决定。
Widget _realGarden({required int capacity}) => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider
            .overrideWithValue(_FakeSettingsRepository(capacity)),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
        plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: GardenPage(embedded: true))),
    );

/// 有界帧推进：最多 [maxFrames] 帧、每帧 [step]，直到 [ready] 为真即停。
///
/// 呼吸动画无限循环 → 一律 `pumpAndSettle` 会永不返回；这里用「**条件 + 有界**」推进，
/// 替代「网格出现后额外固定 N 帧」的魔数等待（QA §4：固定帧数既脆弱、又可能变成静默假绿）。
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 40,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(step);
  }
  return ready();
}

/// 推进真实花园页：先等网格出现，再等 [settled]（滚动条可见性/可滚性）**收敛**。
///
/// 传入「本用例关心的终态」判据，而非固定帧数；未在 [maxFrames] 帧内收敛则 fail ——
/// 这样异步抖动会**明确报错**而不是被多 pump 几帧悄悄掩盖。
Future<void> _pumpGridUntil(
  WidgetTester tester,
  bool Function() settled, {
  int maxFrames = 40,
}) async {
  final bool appeared = await _pumpUntil(
    tester,
    () => find.byType(EmptyPot).evaluate().isNotEmpty,
    maxFrames: maxFrames,
  );
  expect(appeared, isTrue, reason: '网格未在 $maxFrames 帧内出现（异步数据未就绪？）');
  final bool ok = await _pumpUntil(tester, settled, maxFrames: maxFrames);
  expect(ok, isTrue, reason: '滚动状态未在 $maxFrames 帧内收敛（判据未满足）');
}

/// 当前花园页滚动条是否可见（仅在网格已建好时调用）。
bool _gridThumbVisible(WidgetTester tester) =>
    tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility ?? false;

/// 取花园页网格的滚动位置。
///
/// 注意：`GardenGrid`（GridView，shrinkWrap + NeverScrollableScrollPhysics）**内部也会建一个
/// `Scrollable`**，故外层 `SingleChildScrollView` 下有两个 `Scrollable` —— 取**第一个**（最外层）
/// 才是花园页接管滚动的那个。
ScrollPosition _gridPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first)
    .position;

void main() {
  // ── 改动 1：背景映射纯函数 ────────────────────────────────────────────────
  group('gardenCoverRect · BoxFit.cover 映射（纯函数）', () {
    test('容器比图更「宽」（宽满、上下溢出、居中）', () {
      const Size box = Size(1056, 2000); // 与图同宽但更矮 → 宽度铺满
      final Rect r = gardenCoverRect(box);
      const double scale = 1056 / 1056; // = 1
      expect(r.width, closeTo(kGardenBackgroundSize.width * scale, 0.001));
      expect(r.height, closeTo(kGardenBackgroundSize.height * scale, 0.001));
      expect(r.left, closeTo((box.width - r.width) / 2, 0.001));
      expect(r.top, closeTo((box.height - r.height) / 2, 0.001));
      expect(r.top, lessThan(0)); // 上下溢出
      expect(r.size, kGardenBackgroundSize * scale);
    });

    test('容器比图更「高」（高满、左右溢出、居中）', () {
      const Size box = Size(600, 2336); // 与图同高但更窄 → 高度铺满
      final Rect r = gardenCoverRect(box);
      const double scale = 2336 / 2336; // = 1
      expect(r.width, closeTo(kGardenBackgroundSize.width * scale, 0.001));
      expect(r.height, closeTo(kGardenBackgroundSize.height * scale, 0.001));
      expect(r.left, lessThan(0)); // 左右溢出
      expect(r.top, closeTo(0, 0.001));
      expect(r.size, kGardenBackgroundSize * scale);
    });

    test('scale 取 max（不失真、覆盖容器）', () {
      const Size box = Size(720, 1280);
      final Rect r = gardenCoverRect(box);
      const double scale = 720 / 1056; // 0.6818 > 1280/2336 = 0.5479
      expect(scale, greaterThan(1280 / 2336));
      expect(r.width, closeTo(kGardenBackgroundSize.width * scale, 0.001));
      expect(r.height, closeTo(kGardenBackgroundSize.height * scale, 0.001));
      expect(r.width, greaterThanOrEqualTo(box.width - 0.001));
      expect(r.height, greaterThanOrEqualTo(box.height - 0.001));
    });
  });

  // ── 改动 1：花盆区底界 ────────────────────────────────────────────────────
  group('gardenPotAreaBottom · 花盆区底界', () {
    test('360×780：落在容器高 45%~100% 之间，且在图顶部之下', () {
      const Size box = Size(360, 780);
      final double bottom = gardenPotAreaBottom(box);
      expect(bottom, greaterThan(box.height * 0.45));
      expect(bottom, lessThan(box.height));
      expect(bottom, greaterThan(gardenCoverRect(box).top));
    });

    test('比例常量 = 0.70（留出背景菜地上沿）', () {
      expect(kGardenPotAreaBottomFraction, closeTo(0.70, 1e-9));
    });
  });

  // ── 改动 1：网格可视高度纯函数（「锁 2 行」的唯一真源） ─────────────────────
  group('gardenGridVisibleHeight · 锁 2 行（纯函数）', () {
    test('高屏：等于「两行高度」', () {
      final double h = gardenGridVisibleHeight(
        box: const Size(360, 780),
        gridInnerWidth: 336, // 360 - 12*2
        firstRowTop: 12,
        cellAspectRatio: GardenGrid.cellAspectRatio,
        spacing: 6,
        bottomInset: 12,
      );
      const double cellWidth = (336 - 12) / 3;
      const double rowHeight = cellWidth / GardenGrid.cellAspectRatio;
      const double twoRows = rowHeight * 2 + 6;
      expect(h, closeTo(twoRows, 0.01));
      // 自检：若被改成 3 行，此值必不同（防「改行数不变红」）。
      const double threeRows = rowHeight * 3 + 6 * 2;
      expect(h, isNot(closeTo(threeRows, 0.5)));
    });

    test('矮屏：受「花盆区底界 - 顶部 - bottomInset」钳制', () {
      const Size box = Size(360, 400);
      final double h = gardenGridVisibleHeight(
        box: box,
        gridInnerWidth: 336,
        firstRowTop: 12,
        cellAspectRatio: GardenGrid.cellAspectRatio,
        spacing: 6,
        bottomInset: 12,
      );
      expect(h, closeTo(gardenPotAreaBottom(box) - 12 - 12, 0.01));
    });

    test('统一使用 spacing=6、列数=3（与 GardenGrid 对齐）', () {
      final double h = gardenGridVisibleHeight(
        box: const Size(360, 780),
        gridInnerWidth: (360 - 44), // 旧测试 harness 宽，仅验证几何一致
        firstRowTop: 0,
        cellAspectRatio: 0.54,
      );
      const double cellWidth = (316 - 12) / 3;
      expect(h, closeTo(cellWidth / 0.54 * 2 + 6, 0.01));
    });
  });

  // ── 改动 4：木牌屏幕矩形（硬钉真实坐标，独立推导） ─────────────────────────
  group('gardenSignScreenRect · 木牌真实坐标', () {
    test('360×780：屏幕矩形与源图像素区间独立推导一致（容差 ≤ 0.05px）', () {
      const Size box = Size(360, 780);
      final Rect expected = _expectedSignScreenRect(box);
      final Rect actual = gardenSignScreenRect(box);
      expect(actual.left, closeTo(expected.left, 0.05));
      expect(actual.top, closeTo(expected.top, 0.05));
      expect(actual.right, closeTo(expected.right, 0.05));
      expect(actual.bottom, closeTo(expected.bottom, 0.05));
    });

    test('360×780：硬钉实测值（新图标定 29.52 / 503.08 / 92.88 / 566.79）', () {
      const Size box = Size(360, 780);
      final Rect r = gardenSignScreenRect(box);
      expect(r.left, closeTo(29.52, 0.05));
      expect(r.top, closeTo(503.08, 0.05));
      expect(r.right, closeTo(92.88, 0.05));
      expect(r.bottom, closeTo(566.79, 0.05));
      expect(r.width, closeTo(63.36, 0.05));
      expect(r.height, closeTo(63.71, 0.05));
      // cover 上下裁切证据（origin.dy 为负 → 木牌整体上移）。
      expect(gardenCoverRect(box).top, closeTo(-8.1818, 0.01));
    });

    test('400×880：硬钉实测值 + cover 裁切证据', () {
      const Size box = Size(400, 880);
      final Rect expected = _expectedSignScreenRect(box);
      final Rect r = gardenSignScreenRect(box);
      expect(r.left, closeTo(expected.left, 0.05));
      expect(r.top, closeTo(expected.top, 0.05));
      expect(r.right, closeTo(expected.right, 0.05));
      expect(r.bottom, closeTo(expected.bottom, 0.05));
      // 新图标定：32.80 / 565.65 / 103.20 / 636.44，尺寸 70.40×70.79。
      expect(r.width, closeTo(70.40, 0.2));
      expect(r.height, closeTo(70.79, 0.2));
      expect(gardenCoverRect(box).top, closeTo(-2.4242, 0.01));
    });

    test('多屏宽下宽高 ≥ 44 逻辑像素且基本落在容器内', () {
      for (final Size box in <Size>[
        const Size(320, 640),
        const Size(360, 780),
        const Size(390, 844),
        const Size(414, 896),
      ]) {
        final Rect r = gardenSignScreenRect(box);
        expect(r.width, greaterThanOrEqualTo(44), reason: '容器 $box');
        expect(r.height, greaterThanOrEqualTo(44), reason: '容器 $box');
        expect(r.left, greaterThanOrEqualTo(-1), reason: '容器 $box');
        expect(r.top, greaterThanOrEqualTo(-1), reason: '容器 $box');
        expect(r.right, lessThanOrEqualTo(box.width + 1), reason: '容器 $box');
        expect(r.bottom, lessThanOrEqualTo(box.height + 1), reason: '容器 $box');
      }
    });
  });

  // ── 改动 1：真实 GardenPage 锁 2 行 + 区域内滚动（防「测试复刻算式」） ──────
  group('真实 GardenPage · 锁 2 行 + 区域内滚动', () {
    testWidgets('容量 12（12 格，4 行）：第 3 行在视口外 + 滚动条可见 + 可滚',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_realGarden(capacity: 12));
      // 条件收敛：等「滚动条可见 且 确实可滚」成立即停（替代固定 N 帧）。
      await _pumpGridUntil(
        tester,
        () =>
            _gridThumbVisible(tester) && _gridPosition(tester).maxScrollExtent > 0,
      );

      expect(find.byType(EmptyPot), findsNWidgets(12));

      final Rect viewport = tester.getRect(find.byType(SingleChildScrollView));
      // 前两行（索引 0/3/5）在视口内。
      for (final int i in <int>[0, 3, 5]) {
        final Rect cell = tester.getRect(find.byType(EmptyPot).at(i));
        expect(cell.top, greaterThanOrEqualTo(viewport.top - 0.5));
        expect(cell.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
      }
      // 第 3 行（索引 6）顶边在视口下沿之外 —— 证明确实锁 2 行。
      final Rect row3 = tester.getRect(find.byType(EmptyPot).at(6));
      expect(row3.top, greaterThanOrEqualTo(viewport.bottom - 0.5));

      // 滚动条可见 + 确实可滚。
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isTrue,
      );
      expect(_gridPosition(tester).maxScrollExtent, greaterThan(0));
    });

    testWidgets('容量 4（5 格，2 行内）：不滚动 + 无滚动条',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_realGarden(capacity: 4));
      // 条件收敛：等「无滚动条 且 maxScrollExtent 归零」成立即停。
      await _pumpGridUntil(
        tester,
        () =>
            !_gridThumbVisible(tester) &&
            _gridPosition(tester).maxScrollExtent <= 0.5,
      );

      expect(find.byType(EmptyPot), findsNWidgets(4));
      expect(find.byType(ExpandPotSlot), findsOneWidget);
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isFalse,
      );
      expect(_gridPosition(tester).maxScrollExtent, lessThanOrEqualTo(0.5));
    });

    // ── QA N2 缺口：钉住页级 firstRowTop 传入值 ──────────────────────────────
    //
    // 背景：把 `garden_page._buildGardenBody` 里传给纯函数的 `firstRowTop`
    // （应为 `gardenPotAreaBottom(...) - c.maxHeight`）**改成 0** 时，原 360×780 用例
    // 仍全绿 —— 因为 360×780 下 `rowsHeight(406) < available(525.27)`，两行高度本身就
    // 小于可用高度，`firstRowTop` 被 `min(...)` 掩盖、传错也不影响结果。
    //
    // 只有**屏高更短**、使 `available < rowsHeight` 时该参数才真正起作用。
    // 选 360×380：可用高度 ≈ 325.27 < 两行 406（差 81px，余量充足），
    // 而 firstRowTop 传错会带来 +12px 偏差 → 可被 settle 后的像素级断言捕获。
    testWidgets('矮屏 360×380（可摆区比两行更矮）：可视高被「底界−顶部−呼吸间距」钳制，钉住 firstRowTop',
        (WidgetTester tester) async {
      const double w = 360, h = 380;
      _setScreen(tester, w, h);
      await tester.pumpWidget(_realGarden(capacity: 12));
      await _pumpGridUntil(
        tester,
        () =>
            _gridThumbVisible(tester) && _gridPosition(tester).maxScrollExtent > 0,
      );

      expect(find.byType(EmptyPot), findsNWidgets(12));

      // —— 期望值**独立推导**（不引用 garden_page 的私有变量）——
      // 页面 padding 口径（与 garden_page._buildGardenBody 一致的设计常量）：
      //   顶部 padding = 12，底部呼吸间距 bottomInset = 12。
      const double pageTopPad = 12;
      const double bottomInset = 12;
      const Size box = Size(w, h);
      final double expectedViewport =
          gardenPotAreaBottom(box) - pageTopPad - bottomInset;

      // 独立推导「两行高度」（格宽来自 3 列 + 间距 6 + 页面水平 padding 12×2）：
      const double gridInnerWidth = w - pageTopPad * 2; // 336
      const double cellWidth = (gridInnerWidth - 6 * 2) / 3; // 108
      final double twoRowsHeight =
          cellWidth / GardenGrid.cellAspectRatio * 2 + 6; // 406

      // 场景自检：必须「两行高度 > 可用高度」，否则 firstRowTop 依旧被 min() 掩盖，
      // 这条用例就退化回 QA N2 的无效覆盖 —— 显式断言挡住这种「假有效」。
      expect(twoRowsHeight, greaterThan(expectedViewport),
          reason: '所选矮屏必须让两行高度 > 可用高度，测试才有意义');

      final double viewportHeight =
          tester.getRect(find.byType(SingleChildScrollView)).height;

      // 钉死：可视高 == 花盆区底界 − 顶部 − 呼吸间距。
      // 若 firstRowTop 被错传为 0，此值会变为 expectedViewport + 12（≈337.27）→ 必红。
      expect(viewportHeight, closeTo(expectedViewport, 0.05),
          reason: 'firstRowTop 传错会让可视高偏 +12px');
      expect(viewportHeight, isNot(closeTo(expectedViewport + pageTopPad, 1.0)));
    });
  });

  // ── 改动 2：加号对齐盆心（期望值按 pot.png 像素 bbox 独立推导） ─────────────
  group('加号格 · 对齐花盆视觉中心', () {
    // pot.png：画布 1200×2000，内容 alpha bbox = (200, 1318, 1001, 2000)。
    const double potCanvasW = 1200;
    const double potCanvasH = 2000;
    const double bboxTop = 1318;
    const double bboxBottom = 2000;
    const double bboxLeft = 200;
    const double bboxRight = 1001;
    // 盆心 = 内容 bbox 的纵向中心；盆宽占比 = 内容 bbox 宽 / 画布宽（独立推导，非引用常量）。
    const double expectedCenterYFraction =
        (bboxTop + (bboxBottom - bboxTop) / 2) / potCanvasH; // = 0.8295
    const double expectedWidthFraction = (bboxRight - bboxLeft) / potCanvasW;
    const double designIconRatio = 0.92; // 设计口径：加号外径 = 盆宽 × 0.92

    test('独立推导自检：盆心比例 = 0.8295、盆宽占比 = 0.6675', () {
      expect(expectedCenterYFraction, closeTo(0.8295, 1e-9));
      expect(expectedWidthFraction, closeTo(0.6675, 1e-9));
    });

    testWidgets('圆心落在画框高的 82.95% 处、外径 ≈ 盆宽 × 92%',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 120,
              height: 260,
              child: ExpandPotSlot(
                cost: 400,
                shortfall: -100,
                busy: false,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final Rect artBox =
          tester.getRect(find.byKey(const Key('expand_pot_artbox')));
      final Rect icon = tester.getRect(find.byKey(const Key('expand_pot_icon')));

      // ① 圆心 y = 画框高 × 82.95%（独立推导，误差 ≤ 0.5px）。
      final double expectedCenterY =
          artBox.top + artBox.height * expectedCenterYFraction;
      expect(icon.center.dy, closeTo(expectedCenterY, 0.5));
      // ② 硬钉绝对坐标（本 harness：120×260 顶左对齐 → artBox.top ≈ 57.733）。
      expect(icon.center.dy, closeTo(195.65, 1.5));
      // ③ 不是画布正中（防回归成 50%）。
      expect(
        (icon.center.dy - (artBox.top + artBox.height / 2)).abs(),
        greaterThan(5.0),
      );
      // ④ 外径 = 画框宽 × 66.75% × 92%（独立推导，误差 ≤ 0.5px）。
      final double expectedDiameter =
          artBox.width * expectedWidthFraction * designIconRatio;
      expect(icon.width, closeTo(expectedDiameter, 0.5));
      expect(icon.height, closeTo(expectedDiameter, 0.5));
    });
  });

  // ── 改动 3：文案胶囊 + 底边对齐 + 五态对比度 ─────────────────────────────────
  group('底部文案 · 胶囊底 + 三类对齐 + 对比度', () {
    testWidgets('三类格子底部文案底边互差 ≤ 1px（同一行）',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      const double gridWidth = 360 - 44;
      await tester.pumpWidget(_boxed(
        width: gridWidth,
        height: 300,
        child: GardenGrid(cells: <Widget>[
          GardenPot(
            plant: _plant(status: PlantStatus.bloomed, progress: 1.0),
            species: _sunflower,
            onTap: () {},
          ),
          EmptyPot(potIndex: 1, onTap: () {}),
          ExpandPotSlot(
            cost: 400,
            shortfall: -100,
            busy: false,
            onTap: () {},
          ),
        ]),
      ));
      await tester.pumpAndSettle();

      final Rect potLabel = tester.getRect(find.byKey(const Key('garden_pot_label')));
      final Rect emptyFooter =
          tester.getRect(find.byKey(const Key('empty_pot_footer')));
      final Rect expandLabel =
          tester.getRect(find.byKey(const Key('expand_pot_label')));

      expect((potLabel.bottom - expandLabel.bottom).abs(), lessThanOrEqualTo(1.0));
      expect((potLabel.bottom - emptyFooter.bottom).abs(), lessThanOrEqualTo(1.0));
    });

    test('五态字色 WCAG 对比度 ≥ 4.5:1（相对胶囊底 composite）', () {
      // 胶囊底 0xE6FFFFFF 压草地上的 composite ≈ rgb(246,247,235)（QA 复算）。
      const Color pillOnGrass = Color(0xFFF6F7EB);
      const Color white = Color(0xFFFFFFFF); // 最坏情况（草地最亮）
      final Map<String, Color> colors = <String, Color>{
        '成长中': Colors.teal.shade800,
        '开花': Colors.green.shade800,
        '枯萎': Colors.deepOrange.shade900,
        '已枯萎': Colors.grey.shade700,
        '加盆·可点': Colors.green.shade800,
        '加盆·还差': Colors.grey.shade700,
      };
      colors.forEach((String name, Color c) {
        expect(_contrastRatio(c, pillOnGrass), greaterThanOrEqualTo(4.5),
            reason: '$name vs composite');
        expect(_contrastRatio(c, white), greaterThanOrEqualTo(4.5),
            reason: '$name vs 纯白');
      });
      // 防回退：旧色 orange.shade900 不达标，必须低于 4.5。
      expect(_contrastRatio(Colors.orange.shade900, pillOnGrass), lessThan(4.5));
    });

    testWidgets('不可点态（还差 N）字色 = grey.shade700', (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_boxed(
        width: (360 - 44) / 3,
        height: 240,
        child: Align(
          alignment: Alignment.topCenter,
          child: ExpandPotSlot(
            cost: 400,
            shortfall: 173,
            busy: false,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      final Text label = tester.widget<Text>(find.text('还差 173☀'));
      expect(label.style?.color, equals(Colors.grey.shade700));
    });

    testWidgets('枯萎态字色 = deepOrange.shade900（不是 orange.shade900）',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_boxed(
        width: (360 - 44) / 3,
        height: 240,
        child: Align(
          alignment: Alignment.topCenter,
          child: GardenPot(
            plant: _plant(status: PlantStatus.wilting),
            species: _sunflower,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      final Text label = tester.widget<Text>(find.text('向日葵 · 快救回'));
      expect(label.style?.color, equals(Colors.deepOrange.shade900));
      expect(label.style?.color, isNot(equals(Colors.orange.shade900)));
    });

    testWidgets('死亡态字色 = grey.shade700', (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_boxed(
        width: (360 - 44) / 3,
        height: 240,
        child: Align(
          alignment: Alignment.topCenter,
          child: GardenPot(
            plant: _plant(status: PlantStatus.dead),
            species: _sunflower,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      final Text label = tester.widget<Text>(find.text('向日葵 · 已枯萎'));
      expect(label.style?.color, equals(Colors.grey.shade700));
    });
  });

  // ── 改动 4：木牌热区 ──────────────────────────────────────────────────────
  group('木牌热区', () {
    testWidgets('animate:false 可点且回调触发（不阻塞 pumpSettle）',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      bool tapped = false;
      await tester.pumpWidget(_boxed(
        width: 100,
        height: 60,
        child: GardenSignHotspot(animate: false, onTap: () => tapped = true),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GardenSignHotspot));
      expect(tapped, isTrue);
    });

    testWidgets('animate:true 光晕透明度随时间变化（逐帧 pump，不用 settle）',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(_boxed(
        width: 100,
        height: 60,
        child: GardenSignHotspot(animate: true, onTap: () {}),
      ));
      await tester.pump();

      Color glowColor() {
        final Container c =
            tester.widget<Container>(find.byKey(const Key('garden_sign_glow')));
        return (c.decoration! as BoxDecoration).color!;
      }

      final Color c0 = glowColor();
      await tester.pump(const Duration(milliseconds: 500));
      final Color c1 = glowColor();
      await tester.pump(const Duration(milliseconds: 500));
      final Color c2 = glowColor();

      expect(c1 == c0 && c2 == c1, isFalse);
    });
  });

  // ── 改动 4：玩法说明弹窗 ──────────────────────────────────────────────────
  group('玩法说明弹窗', () {
    testWidgets('从木牌热区点开，弹出「玩法说明」并显示容量文案',
        (WidgetTester tester) async {
      _setScreen(tester, 360, 780);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 60,
              child: Builder(
                builder: (BuildContext ctx) => GardenSignHotspot(
                  animate: false,
                  onTap: () => showModalBottomSheet<void>(
                    context: ctx,
                    showDragHandle: true,
                    builder: (BuildContext _) => const GardenHelpSheet(
                      capacity: 4,
                      expandCost: 160,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(GardenSignHotspot));
      await tester.pumpAndSettle();

      expect(find.text('玩法说明'), findsOneWidget);
      expect(find.text('4 / 12 盆'), findsOneWidget);
      // 缺陷 5：不得再出现对精品植物不成立的「每阶段约 10 天」。
      expect(find.textContaining('10 天'), findsNothing);
    });
  });
}
