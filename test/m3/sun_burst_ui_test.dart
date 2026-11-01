/// F170 · 点击阳光胶囊 → 阳光四散特效（玄参 2026-11-01 需求）。
///
/// 需求原话：「点一下这个胶囊，嘣就往外四散一下阳光，又慢慢消失的那种感觉。」
///
/// 两层覆盖：
///  · **组件层**（[SunBurst]）：粒子数、飞散几何、透明度衰减、结束时回调自清；
///  · **接线层**（今日页）：点**真实胶囊**（`ChildTodayPage.sunBubbleKey`）→
///    根 Overlay 出现 [SunBurst]；连点不叠层；播完自动消失。
///
/// 🔴 经济红线：本特效**纯视觉**。测试里同时断言「点 3 次后阳光余额不变」——
/// 将来若有人往里加阳光/写账本，这条会立刻变红。
library sun_burst_ui_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:sunflower_time/presentation/child/pages/child_today_page.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/sun_burst.dart';

// ── 夹具（与 today_badge_bounds_test 同源）──────────────────────────────────

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
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
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
        totalFocusMinutes: 30,
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

/// 今日页宿主（沉浸式 AppBar，与 shell 同款；简化掉机型矩阵，只跑 iPhone 尺寸）。
Future<_FakeSunlight> _pumpToday(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 0, left: 0, right: 0);
  addTearDown(tester.view.reset);

  final _FakeSunlight sunlight = _FakeSunlight();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(sunlight),
      focusRepositoryProvider.overrideWithValue(_FakeFocus()),
      taskRepositoryProvider.overrideWithValue(_FakeTask()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      focusLevelStoreProvider.overrideWithValue(_MemoryStore()..value = 0),
    ],
  );
  addTearDown(container.dispose);
  container.read(childShellTabIndexProvider.notifier).state =
      kChildTabIndexOfToday;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('今日'),
          ),
          body: const ChildTodayPage(),
        ),
      ),
    ),
  );
  // 有界 pump：胶囊有无限漂移动画，绝不 pumpAndSettle。
  for (int i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byKey(ChildTodayPage.sunBubbleKey).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 16));
  return sunlight;
}

/// 爆发浮层**内部**的粒子图元（排除胶囊自己的图标）。
Finder _burstParticles() => find.descendant(
      of: find.byType(SunBurst),
      matching: _particles(),
    );

/// 粒子图元（素材图或缺失回退的内置太阳）。
Finder _particles() => find.byWidgetPredicate((Widget w) =>
    (w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == kSunBurstAsset) ||
    (w is Icon && w.icon == Icons.wb_sunny));

void main() {
  group('SunBurst 组件', () {
    testWidgets('粒子数 = 10；飞到中点时已明显离开圆心；走完回调一次',
        (WidgetTester tester) async {
      int done = 0;
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      const Offset origin = Offset(200, 300);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: SunBurst(origin: origin, onComplete: () => done++),
              ),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(_particles(), findsNWidgets(kSunBurstParticleCount),
          reason: '应有 10 颗粒子');

      // 飞行中段（≈60% 时长）：粒子应已飞离圆心 20pt 以上。
      await tester.pump(const Duration(milliseconds: 370));
      final List<Rect> rects = <Rect>[
        for (int i = 0; i < kSunBurstParticleCount; i++)
          tester.getRect(_particles().at(i)),
      ];
      final List<double> distances = <double>[
        for (final Rect r in rects) (r.center - origin).distance,
      ];
      expect(
        distances.where((double d) => d > 20).length,
        greaterThanOrEqualTo(8),
        reason: '至少 8 颗已飞离圆心 20pt 以上（四散而不是原地缩小）',
      );
      // 方向要真的「四散」：左右两侧都得有粒子（不能全往一边飞）。
      expect(rects.any((Rect r) => r.center.dx < origin.dx - 10), isTrue);
      expect(rects.any((Rect r) => r.center.dx > origin.dx + 10), isTrue);
      expect(rects.any((Rect r) => r.center.dy < origin.dy - 10), isTrue);
      expect(rects.any((Rect r) => r.center.dy > origin.dy + 10), isTrue);

      // 播完：回调恰好一次（浮层自清的唯一出口）。
      await tester.pump(const Duration(milliseconds: 400));
      expect(done, 1, reason: '结束时必须回调一次，onComplete 是浮层自清的唯一出口');
    });

    testWidgets('中途透明度衰减（末段淡出，不是突然消失）', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: SunBurst(origin: Offset(200, 300), onComplete: _noop),
              ),
            ],
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      double minOpacity() {
        double m = 1;
        for (final Element e in find.byType(Opacity).evaluate()) {
          final Opacity o = e.widget as Opacity;
          if (o.opacity < m) m = o.opacity;
        }
        return m;
      }

      // 出发后不久：全部接近不透明。
      await tester.pump(const Duration(milliseconds: 120));
      expect(minOpacity(), greaterThan(0.6), reason: '出发初期粒子应基本不透明');

      // 临近结束：应已明显淡化（不是硬切）。
      await tester.pump(const Duration(milliseconds: 380));
      expect(minOpacity(), lessThan(0.6), reason: '末段应淡出');

      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('今日页接线', () {
    testWidgets('点胶囊 → 出现 SunBurst 浮层；播完自动消失', (WidgetTester tester) async {
      await _pumpToday(tester);

      expect(find.byType(SunBurst), findsNothing, reason: '默认不该有爆发浮层');

      await tester.tap(find.byKey(ChildTodayPage.sunBubbleKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(SunBurst), findsOneWidget, reason: '点胶囊应触发一次阳光四散');
      // 只数**浮层内**的粒子：胶囊自身也有一张 sunlight.png（图标），不能用全局计数。
      expect(_burstParticles(), findsNWidgets(kSunBurstParticleCount));

      // 播完 + 兜底定时器后自清。
      await tester.pump(const Duration(milliseconds: kSunBurstDurationMs + 400));
      expect(find.byType(SunBurst), findsNothing, reason: '浮层必须自清，不能滞留挡视线');
    });

    testWidgets('连点三下只保留一层浮层（不叠层）', (WidgetTester tester) async {
      await _pumpToday(tester);

      final Finder capsule = find.byKey(ChildTodayPage.sunBubbleKey);
      await tester.tap(capsule);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(capsule);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(capsule);
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(SunBurst), findsOneWidget, reason: '连点不得叠出多层浮层');
      expect(_burstParticles(), findsNWidgets(kSunBurstParticleCount),
          reason: '粒子总数仍是一轮的 10 颗（不是 20/30 颗叠出来的）');

      await tester.pump(const Duration(milliseconds: kSunBurstDurationMs + 400));
    });

    testWidgets('🔴 经济红线：点胶囊不加阳光、不写账本', (WidgetTester tester) async {
      final _FakeSunlight sunlight = await _pumpToday(tester);
      final double before = sunlight.balanceValue;
      final int entriesBefore = sunlight.entries.length;

      final Finder capsule = find.byKey(ChildTodayPage.sunBubbleKey);
      for (int i = 0; i < 3; i++) {
        await tester.tap(capsule);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: kSunBurstDurationMs + 400));

      expect(sunlight.balanceValue, before, reason: '特效纯视觉，绝不能改余额');
      expect(sunlight.entries.length, entriesBefore, reason: '绝不能写阳光账本');
    });
  });
}

void _noop() {}
