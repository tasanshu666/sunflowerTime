/// F142 · QA 布局量测探针 B（**断言版**，严过关 Round 1）。
///
/// ## 与工程师 `f142_tablet_layout_shift_test.dart` 的差异（独立性声明）
/// 工程师用例未覆盖：834×1194 档位、「label 是否被栏高裁掉」的逐 label 实测、
/// `textScaler 1.3` 破例档（iPad 13″ label ≈25px）、`AdaptiveNavBarHost` 600 限宽的
/// 渲染盒实测。本探针补齐这四块，且期望值全部写成**字面算式**（不引用被测常量）。
///
/// ## 「max 陷阱」的证伪设计
/// 若实现把 +40 加在 `max()` **之后**，卡顶会是 `0.40H + 80`；本探针用
/// `closeTo(0.40H + 40, 0.5)` 与 `lessThan(0.40H + 79)` 双断言把 80 / 0 两个
/// 错误值同时排除；呼吸带用「卡顶 − 分界线」实测，排除「−4」（底图没同步下移
/// 时 band = 3%H − 40 < 0）与「76」（卡片多移了一次 40）。
///
/// ⚠️ 全程禁用 `pumpAndSettle`（今日页无限动画）。
library f142_qa_layout_probe_test;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:sunflower_time/shared/adaptive_nav_bar.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

// ── 视口（iPad 11″ 两种逻辑分辨率都测）───────────────────────────────────────
const Size _kIpad11A = Size(834, 1194);
const Size _kIpad11B = Size(834, 1210);
const Size _kIpad13 = Size(1032, 1376);

// ── 今日页仓储假件（与探针 A 同款：无假件时今日页走真实仓储装配会崩）─────────
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

class _FakeTask implements TaskRepository {
  @override
  Future<List<Task>> tasks() async => <Task>[
        const Task(
          id: 'qa_probe_b_t',
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

class _QaProbeHarness {
  final List<Object> exceptions = <Object>[];

  /// ⚠️ harness 在 main() 里单例复用 → 每个用例 pump 前必须清零，
  /// 否则上一个用例抽到的异常会污染本用例的 `expect(exceptions, isEmpty)`。
  void _resetExceptions() => exceptions.clear();

  void _useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 0);
    addTearDown(tester.view.reset);
  }

  Widget _app(Widget home, ProviderContainer container,
      {TextScaler? forceScaler}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (BuildContext ctx, Widget? child) {
            final Widget content = child ?? const SizedBox.shrink();
            MediaQueryData mq =
                MediaQuery.maybeOf(ctx) ?? const MediaQueryData();
            mq = applyTabletTextScaling(mq);
            if (forceScaler != null) {
              // 探针专用：把系统档文字倍率**强制**换成指定值（模拟「系统大字体 1.3」
              // 叠在平板注入之上之前的状态 —— C97 口径下的裸系统档）。
              mq = mq.copyWith(textScaler: forceScaler);
            }
            if (identical(mq, MediaQuery.maybeOf(ctx))) return content;
            return MediaQuery(data: mq, child: content);
          },
          home: home,
        ),
      );

  ProviderContainer _todayContainer() {
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
              idFactory: () => 'qa-probe-b',
            )),
      ],
    );
    addTearDown(container.dispose);
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfToday;
    container.read(childShellOnStageProvider.notifier).state = true;
    return container;
  }

  Future<void> _pumpFrames(WidgetTester tester, {int frames = 16}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void _drain(WidgetTester tester) {
    for (int i = 0; i < 20; i++) {
      final Object? e = tester.takeException();
      if (e == null) break;
      exceptions.add(e);
    }
  }

  // ── 今日页量测 ──

  double todayCardTop(WidgetTester tester) {
    final Finder card = find.ancestor(
      of: find.text('今日获取阳光'),
      matching: find.byType(Container),
    );
    expect(card, findsOneWidget);
    return tester.renderObject<RenderBox>(card).localToGlobal(Offset.zero).dy;
  }

  double todayPanelLineY(WidgetTester tester) {
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

  Future<void> pumpToday(WidgetTester tester, Size screen) async {
    _resetExceptions();
    _useScreen(tester, screen);
    await tester.pumpWidget(_app(const ChildTodayPage(), _todayContainer()));
    await _pumpFrames(tester);
    _drain(tester);
  }

  /// 「成长」页列表裁剪上沿（= sceneGap 实测）。
  double taskSceneGap(WidgetTester tester) {
    final Finder clip = find
        .ancestor(of: find.byType(ListView), matching: find.byType(ClipRect))
        .first;
    return tester.getTopLeft(clip).dy;
  }

  Future<void> pumpTask(WidgetTester tester, Size screen) async {
    _resetExceptions();
    _useScreen(tester, screen);
    final ProviderContainer container = _todayContainer();
    container.read(childShellTabIndexProvider.notifier).state =
        kChildTabIndexOfGrowth;
    // 任务卡用 InkWell → 必须套 Scaffold（外壳里由外层 Material 提供）。
    await tester.pumpWidget(
      _app(const Scaffold(body: ChildTaskPage()), container),
    );
    await _pumpFrames(tester);
    _drain(tester);
  }

  // ── 外壳 / 底栏量测 ──

  /// 建库 + 造数 + pump 真实外壳，返回底栏渲染盒。
  Future<void> pumpShell(
    WidgetTester tester,
    Size screen, {
    TextScaler? forceScaler,
  }) async {
    _resetExceptions();
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
        id: 'plant_qa_probe_b',
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
    await tester.pumpWidget(_app(const ChildShellPage(), container,
        forceScaler: forceScaler));
    await _pumpFrames(tester, frames: 20);
    _drain(tester);
  }

  /// 逐 label 实测：渲染高度 vs 单行内在高度（被裁/换行 ⇒ 不等），
  /// 且整个 label 落在 NavigationBar 渲染盒内。
  void expectLabelsFullyVisible(WidgetTester tester, String tag) {
    final RenderBox nav = tester.renderObject<RenderBox>(
      find.byType(NavigationBar),
    );
    final double navTop = nav.localToGlobal(Offset.zero).dy;
    final double navBottom = navTop + nav.size.height;

    const List<String> labels = <String>['今日', '成长', '花园', '商店', '我的'];
    for (final String label in labels) {
      final Finder f = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      expect(f, findsWidgets, reason: '$tag 找不到 label「$label」');
      final RenderParagraph rp = tester.renderObject<RenderParagraph>(f.first);

      // 单行内在高度（同 span、同倍率、无宽度约束）。
      final TextPainter tp = TextPainter(
        text: rp.text,
        textDirection: TextDirection.ltr,
        textScaler: rp.textScaler,
      )..layout();
      final double intrinsicH = tp.height;

      expect(rp.size.height, closeTo(intrinsicH, 0.8),
          reason: '$tag label「$label」被裁/换行：渲染高 '
              '${rp.size.height.toStringAsFixed(1)} vs 单行内在高 '
              '${intrinsicH.toStringAsFixed(1)}');
      final double top = rp.localToGlobal(Offset.zero).dy;
      final double bottom = top + rp.size.height;
      expect(top, greaterThanOrEqualTo(navTop),
          reason: '$tag label「$label」顶 $top 越出栏顶 $navTop');
      expect(bottom, lessThanOrEqualTo(navBottom),
          reason: '$tag label「$label」底 $bottom 越出栏底 $navBottom');
      print('QA_PROBE_B label $tag「$label」h=${rp.size.height.toStringAsFixed(2)} '
          'top=${top.toStringAsFixed(2)} bottom=${bottom.toStringAsFixed(2)} '
          '(bar $navTop..$navBottom)');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _QaProbeHarness h = _QaProbeHarness();

  // ── Q3-①：平板卡顶 == 0.40H + 40（不是 +80 / +0）；呼吸带仍是 3%H ──────────
  for (final (String tag, Size screen) in <(String, Size)>[
    ('ipad11_1194', _kIpad11A),
    ('ipad11_1210', _kIpad11B),
    ('ipad13', _kIpad13),
  ]) {
    final double hgt = screen.height;
    testWidgets('$tag · 卡顶 = 0.40H+40（排除 +80/+0），分界线 = 0.37H+40，呼吸带 = 3%H',
        (WidgetTester tester) async {
      await h.pumpToday(tester, screen);

      final double cardTop = h.todayCardTop(tester);
      final double panelTop = h.todayPanelLineY(tester);

      expect(cardTop, closeTo(hgt * 0.40 + 40, 0.5),
          reason: '$tag 卡顶必须 = ${hgt * 0.40 + 40}（+80 ⇒ ${hgt * 0.40 + 80}；'
              '+0 ⇒ ${hgt * 0.40}；实测 $cardTop）');
      expect(cardTop, lessThan(hgt * 0.40 + 79),
          reason: '$tag 排除「max 之后又加一次 40」的 +80 实现（实测 $cardTop）');
      expect(panelTop, closeTo(hgt * 0.37 + 40, 0.5),
          reason: '$tag 底图分界线必须同步 +40 = ${hgt * 0.37 + 40}（实测 $panelTop）');
      // 呼吸带：仍 = 3% 屏高（不是 3%H+40=76、也不是 3%H−40=−4）。
      expect(cardTop - panelTop, closeTo(hgt * 0.03, 0.5),
          reason: '$tag 呼吸带必须仍是 3%H = ${hgt * 0.03}（实测 ${cardTop - panelTop}）');
      expect(h.exceptions, isEmpty);
    });
  }

  // ── Q3-②：手机今日页零回归（卡顶 = 分界线 + 3%H，绝不吃 40pt）────────────
  testWidgets('phone 390×844 · 卡顶 = 分界线 + 3%H（HEAD 同式），无 40pt 下移',
      (WidgetTester tester) async {
    const Size screen = Size(390, 844);
    await h.pumpToday(tester, screen);

    final double cardTop = h.todayCardTop(tester);
    final double panelTop = h.todayPanelLineY(tester);

    expect(cardTop, closeTo(panelTop + 844 * 0.03, 0.5),
        reason: '手机卡顶必须仍是「分界线 + 3% 屏高」= ${panelTop + 844 * 0.03}'
            '（实测 $cardTop；这是 HEAD 的同一条公式）');
    expect(cardTop, lessThan(844 * 0.40 + 40),
        reason: '手机绝不许吃平板 40pt 下移（实测 $cardTop）');
    // 阳光气泡：手机 top = 0.25H（+0）。⚠️ 气泡带漂浮动画（实测振幅 ≈±12pt），
    // 容差取 20pt —— 仍足以区分 +0（211）/ +40（251）/ +80（291）三档。
    final RenderBox bubble = tester.renderObject<RenderBox>(
      find.byKey(ChildTodayPage.sunBubbleKey),
    );
    expect(bubble.localToGlobal(Offset.zero).dy, closeTo(844 * 0.25, 20),
        reason: '手机气泡 top 必须仍是 0.25×屏高 = 211（±20 动画振幅；实测 '
            '${bubble.localToGlobal(Offset.zero).dy}）');
    expect(h.exceptions, isEmpty);
  });

  // ── Q3-③：平板阳光气泡 / 徽章同向下移（+40 只加一次）────────────────────
  for (final (String tag, Size screen) in <(String, Size)>[
    ('ipad11_1210', _kIpad11B),
    ('ipad13', _kIpad13),
  ]) {
    final double hgt = screen.height;
    testWidgets('$tag · 阳光气泡 top = 0.25H + 40（同向下移一次）',
        (WidgetTester tester) async {
      await h.pumpToday(tester, screen);

      final RenderBox bubble = tester.renderObject<RenderBox>(
        find.byKey(ChildTodayPage.sunBubbleKey),
      );
      final double top = bubble.localToGlobal(Offset.zero).dy;
      // ⚠️ 气泡带漂浮动画（实测振幅 ≈±12pt）→ 容差 20pt，仍可区分 +0/+40/+80。
      expect(top, closeTo(hgt * 0.25 + 40, 20),
          reason: '$tag 气泡 top 必须 = ${hgt * 0.25 + 40}'
              '（+80 ⇒ ${hgt * 0.25 + 80}；+0 ⇒ ${hgt * 0.25}；实测 $top）');
      expect(h.exceptions, isEmpty);
    });
  }

  // ── Q3-④：成长页 sceneGap = 0.34H + 40（平板）/ 0.34H（手机）──────────────
  testWidgets('ipad13 · 成长页列表起点 = 0.34H + 40 = 507.84',
      (WidgetTester tester) async {
    await h.pumpTask(tester, _kIpad13);
    final double gap = h.taskSceneGap(tester);
    expect(gap, closeTo(1376 * 0.34 + 40, 0.5),
        reason: 'iPad 13″ 成长页起点必须 = 467.84 + 40 = 507.84（实测 $gap）');
    expect(h.exceptions, isEmpty);
  });

  testWidgets('phone 390×844 · 成长页列表起点 = 0.34H = 286.96（零回归）',
      (WidgetTester tester) async {
    await h.pumpTask(tester, const Size(390, 844));
    final double gap = h.taskSceneGap(tester);
    expect(gap, closeTo(844 * 0.34, 0.5),
        reason: '手机成长页起点必须仍是 286.96（实测 $gap）');
    expect(h.exceptions, isEmpty);
  });

  // ── Q4-①：平板 5 个 label 完整可见（不裁、不省略、不越栏）──────────────────
  testWidgets('iPad 11″ 834×1210 · 5 个 label 完整可见 + 600 限宽', (WidgetTester tester) async {
    await h.pumpShell(tester, _kIpad11B);

    h.expectLabelsFullyVisible(tester, 'ipad11');
    // 渲染树级字号断言（防「Theme 声明了但没落到 Text 上」；也是 M3 变异的观测点：
    // `kNavBarLabelFontSize * s` 改回 `kNavBarLabelFontSize` 时这里必须红）。
    final RenderParagraph rp0 = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('今日'),
      ).first,
    );
    expect(rp0.text.style?.fontSize, closeTo(12 * 1.3, 0.01),
        reason: 'iPad 11″ label 渲染字号必须 = 12 × 1.3 = 15.6'
            '（实测 ${rp0.text.style?.fontSize}）');
    final RenderBox nav = tester.renderObject<RenderBox>(
      find.byType(NavigationBar),
    );
    expect(nav.size.width, lessThanOrEqualTo(kNavBarMaxWidth + 0.5),
        reason: '平板 NavigationBar 净宽必须 ≤ 600（实测 ${nav.size.width}）');
    // 居中：栏中心 ≈ 屏中心（host 通栏补色）。
    final double barCenter =
        nav.localToGlobal(Offset.zero).dx + nav.size.width / 2;
    expect(barCenter, closeTo(834 / 2, 0.6),
        reason: '600 限宽后必须水平居中（实测中心 $barCenter）');
    final Finder host = find.byType(AdaptiveNavBarHost);
    expect(host, findsOneWidget);
    expect(tester.renderObject<RenderBox>(host).size.width, 834,
        reason: 'host 通栏补色必须占满屏宽');
    expect(h.exceptions, isEmpty);
  });

  testWidgets('iPad 13″ 1032×1376 · 5 个 label 完整可见 + 600 限宽居中',
      (WidgetTester tester) async {
    await h.pumpShell(tester, _kIpad13);

    h.expectLabelsFullyVisible(tester, 'ipad13');
    final BuildContext navCtx = tester.element(find.byType(NavigationBar));
    print('QA_PROBE_B navCtxNormal ipad13 textScaler='
        '${MediaQuery.textScalerOf(navCtx).scale(1.0)}');
    final RenderBox nav = tester.renderObject<RenderBox>(
      find.byType(NavigationBar),
    );
    expect(nav.size.width, lessThanOrEqualTo(kNavBarMaxWidth + 0.5));
    final double barCenter =
        nav.localToGlobal(Offset.zero).dx + nav.size.width / 2;
    expect(barCenter, closeTo(1032 / 2, 0.6));
    expect(h.exceptions, isEmpty);
  });

  // ── Q4-②：破例档 —— iPad 13″ + 系统档 textScaler 1.3（label ≈ 25px）────────
  // 已知破例（玄参拍板豁免）：这里**不断言不裁**，只实测并把表现写进结论。
  testWidgets('iPad 13″ + textScaler 1.3 · label ≈25px 实际表现（观察档）',
      (WidgetTester tester) async {
    await h.pumpShell(tester, _kIpad13,
        forceScaler: const TextScaler.linear(1.3));

    // 诊断：确认 forceScaler 真正到达 NavigationBar 子树。
    final BuildContext navCtx = tester.element(find.byType(NavigationBar));
    print('QA_PROBE_B scale1.3 navCtx textScaler='
        '${MediaQuery.textScalerOf(navCtx).scale(1.0)}');

    final RenderBox nav = tester.renderObject<RenderBox>(
      find.byType(NavigationBar),
    );
    final double navTop = nav.localToGlobal(Offset.zero).dy;
    final double navBottom = navTop + nav.size.height;
    const List<String> labels = <String>['今日', '成长', '花园', '商店', '我的'];
    for (final String label in labels) {
      final Finder f = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      final RenderParagraph rp = tester.renderObject<RenderParagraph>(f.first);
      final TextPainter tp = TextPainter(
        text: rp.text,
        textDirection: TextDirection.ltr,
        textScaler: rp.textScaler,
      )..layout();
      final double top = rp.localToGlobal(Offset.zero).dy;
      final double bottom = top + rp.size.height;
      final bool clipped = (rp.size.height - tp.height).abs() > 0.8 ||
          top < navTop - 0.1 ||
          bottom > navBottom + 0.1;
      print('QA_PROBE_B scale1.3 ipad13「$label」spanFontSize='
          '${rp.text.style?.fontSize} scalerScale192='
          '${rp.textScaler.scale(19.2).toStringAsFixed(2)} '
          'scalerScale12=${rp.textScaler.scale(12).toStringAsFixed(2)} '
          'renderH=${rp.size.height.toStringAsFixed(2)} '
          'intrinsicH=${tp.height.toStringAsFixed(2)} top='
          '${top.toStringAsFixed(2)} bottom=${bottom.toStringAsFixed(2)} '
          'barBottom=$navBottom clipped=$clipped');
    }
    print('QA_PROBE_B scale1.3 ipad13 exceptions=${h.exceptions.length} '
        'detail=${h.exceptions.take(3)}');
  });
}
