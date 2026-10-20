/// C74 · 今日页「专注等级」端到端 widget 测试（2026-10-14 40 级 + 9 称号口径）。
///
/// 钉住七件事：
///  ① **未解锁态**：累计 30 分钟 → 徽章 🌱 +「再专注 X 分钟解锁 Lv.1」，
///     账本零发放、零演出；
///  ② **Lv.1 触发**：60 分钟 → 发 3 ☀ + 播 1 场演出（只播一场）；
///  ③ **普通升级不发不播**：已发 Lv.1 后升到 Lv.4 → 零入账、零演出，徽章仍更新到 Lv.4；
///  ④ **重复刷新幂等**：连续 5 次 `_reload`（C68 路径）→ 账本行数与余额恒定；
///  ⑤ **称号解耦**：累计 900 分钟（Lv.7）→ `Lv.7` + 称号仍是 Lv.5 的「专注小苗苗」，
///     进度文案指向**下一级**；
///  ⑥ **不可见不播**：tab 不是今日 ⇒ 仍入账（先写账本）但**不插演出浮层**；
///  ⑦ **空间红线**：C67 两个冻结常量未改；手机 / 平板视口徽章不侵占阳光气泡区。
///
/// 🟢 夹具纪律：时间戳一律相对 `DateTime.now()`。
library focus_level_today_page_test;

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
import 'package:sunflower_time/presentation/child/widgets/level_up_fx_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

// ── 夹具 ──────────────────────────────────────────────────────────────────

class _FakeSunlightRepository implements SunlightRepository {
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
  Future<double> earnNetOnDay(String dayKey) async => 0;

  @override
  Future<double> verifiedRedeemTotal() async => 0;

  @override
  Future<double> netByRefTypeOnDay(String refType, String dayKey) async => 0;

  @override
  Future<double> netByRefTypeInMonth(String refType, String monthKey) async =>
      0;

  @override
  Future<int> countByRefTypeAndRefIdOnDay(
    String refType,
    String refId,
    String dayKey,
  ) async =>
      refCount(refType, refId);

  @override
  Future<int> countByRefTypeAndRefIdSince(
    String refType,
    String refId,
    DateTime since,
  ) async =>
      refCount(refType, refId);

  @override
  Future<int> countByRefType(String refType) async =>
      entries.where((SunlightEntry e) => e.refType == refType).length;

  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
      String refType, String refId) async {
    DateTime? last;
    for (final SunlightEntry e in entries) {
      if (e.refType == refType && e.refId == refId) last ??= e.ts;
    }
    return last;
  }

  int refCount(String refType, String refId) => entries
      .where((SunlightEntry e) => e.refType == refType && e.refId == refId)
      .length;

  int levelRefCount(int level) =>
      refCount(kFocusLevelUpRefType, levelRefIdOf(level));

  /// 预置一条历史已发的称号阳光。
  void seedGranted(int level, int amount) {
    entries.add(
      SunlightEntry(
        id: 'seed-lv$level',
        ts: DateTime.now().subtract(const Duration(hours: 2)),
        type: SunlightType.earn,
        gross: amount.toDouble(),
        net: amount.toDouble(),
        balanceAfter: amount.toDouble(),
        refType: kFocusLevelUpRefType,
        refId: levelRefIdOf(level),
        dayKey: 'seed',
      ),
    );
    balanceValue += amount;
  }
}

class _FakeFocusRepository implements FocusRepository {
  _FakeFocusRepository({required this.totalMinutes});

  double totalMinutes;

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

class _FakeTaskRepository implements TaskRepository {
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

class _FakeSettingsRepository implements SettingsRepository {
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
    value =
        value == null ? settledLevel : (value! > settledLevel ? value : settledLevel);
  }

  @override
  Future<void> clear() async => value = null;
}

/// 今日页宿主页装配（一次 mount = 一次「进入今日页」）。
///
/// [settledBefore] = 「进入前的 SP 值」（null = 从未写过 = **老用户首用**分支）。
class _TodayHarness {
  factory _TodayHarness({
    required double totalMinutes,
    required int tab,
    int? settledBefore,
    List<int> seededLevels = const <int>[],
  }) {
    final _FakeSunlightRepository sunlight = _FakeSunlightRepository();
    final _FakeFocusRepository focus =
        _FakeFocusRepository(totalMinutes: totalMinutes);
    final _MemoryStore store = _MemoryStore()..value = settledBefore;
    for (final int lv in seededLevels) {
      // C78：amount 数值不再有口径意义（历史行语义），预置 1 即可。
      sunlight.seedGranted(lv, 1);
    }
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sunlightRepositoryProvider.overrideWithValue(sunlight),
        focusRepositoryProvider.overrideWithValue(focus),
        taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        focusLevelStoreProvider.overrideWithValue(store),
        focusLevelServiceProvider.overrideWith(
          (Ref ref) => FocusLevelService(
            ledger: ref.watch(sunlightRepositoryProvider),
            store: ref.watch(focusLevelStoreProvider),
            idFactory: () => 'fx-${DateTime.now().microsecondsSinceEpoch}',
          ),
        ),
      ],
    );
    container.read(childShellTabIndexProvider.notifier).state = tab;
    // F138：可见性判据改为「外壳在台前 **且** tab 是今日」。本用例把外壳的「上台」
    // 信号直接摆好（真实外壳由 `ChildShellPage.initState` 发布）—— 否则默认
    // onStage=false 会把今日页判成不可见，演出永不上屏（假红）。
    container.read(childShellOnStageProvider.notifier).state = true;
    return _TodayHarness._(container);
  }

  _TodayHarness._(this.container);

  final ProviderContainer container;

  _FakeSunlightRepository get sunlight =>
      container.read(sunlightRepositoryProvider) as _FakeSunlightRepository;

  _MemoryStore get store =>
      container.read(focusLevelStoreProvider) as _MemoryStore;

  Widget widget() => UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChildTodayPage())),
      );

  /// 模拟 C68 的刷新（切回 tab / 回前台）：经济修订号自增触发 `_reload`。
  void triggerReload() =>
      container.read(economyRevisionProvider.notifier).state++;
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxFrames = 240,
}) async {
  for (int i = 0; i < maxFrames; i++) {
    if (ready()) return true;
    await tester.pump(const Duration(milliseconds: 16));
  }
  return ready();
}

void main() {
  /// 装配并进入今日页（手机视口默认 402×874）。
  Future<_TodayHarness> enterTodayPage(
    WidgetTester tester, {
    required double totalMinutes,
    int tab = kChildTabIndexOfToday,
    Size size = const Size(402, 874),
    int? settledBefore,
    List<int> seededLevels = const <int>[],
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final _TodayHarness h = _TodayHarness(
      totalMinutes: totalMinutes,
      tab: tab,
      settledBefore: settledBefore,
      seededLevels: seededLevels,
    );
    addTearDown(h.container.dispose);
    await tester.pumpWidget(h.widget());
    final bool loaded = await _pumpUntil(
      tester,
      () => find.byKey(FocusLevelBadge.badgeKey).evaluate().isNotEmpty,
    );
    expect(loaded, isTrue, reason: '今日页应渲染出等级徽章');
    await tester.pump(const Duration(milliseconds: 16));
    return h;
  }

  testWidgets('① 未解锁：30 分钟 → 🌱 徽章 + 占位称号 + 进度条，零阳光零演出',
      (WidgetTester tester) async {
    final _TodayHarness h = await enterTodayPage(tester, totalMinutes: 30);
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.byKey(FocusLevelBadge.badgeCircleKey), findsOneWidget);
    expect(find.text(kLevelLockedGlyph), findsOneWidget);
    // v2 摘要态：称号位显示占位文案；「距 Lv.1 还差 X」已迁到详情卡（另有用例）。
    expect(find.text(kLevelBadgeLockedTitle), findsOneWidget);
    expect(find.byKey(FocusLevelBadge.badgeBarKey), findsOneWidget,
        reason: '未解锁也要有细进度条（指向 Lv.1）');
    expect(h.sunlight.entries, isEmpty, reason: '未解锁不得发阳光');
    expect(find.byKey(kLevelUpFxCardKey), findsNothing, reason: '未解锁不得播演出');
    // 既有今日页结构未被破坏（三张状态卡 + 开始专注按钮）。
    expect(find.text('今日获取阳光'), findsOneWidget);
    expect(find.text('今日专注'), findsOneWidget);
    expect(find.text('今日成长'), findsOneWidget);
    expect(find.text('开始专注'), findsOneWidget);
  });

  testWidgets('①b 未解锁三档（0 / 30 / 59 分钟）→ level 0 且标题为空',
      (WidgetTester tester) async {
    for (final double minutes in <double>[0, 30, 59]) {
      expect(levelOfMinutes(minutes), 0, reason: '$minutes 分钟应仍未解锁');
      final FocusLevelProgressForUI p = FocusLevelProgressForUI(minutes);
      expect(p.level, 0);
      expect(p.isLocked, isTrue);
      expect(p.minutesToNext, (60 - minutes).round());
    }
  });

  testWidgets('② Lv.1 触发：60 分钟 → 解锁称号 + 只播一场演出（零阳光零账本行，C78）',
      (WidgetTester tester) async {
    // SP = 0 表示「已过首用（此前累计 < 1 小时）」，否则会走首用静默分支。
    final _TodayHarness h =
        await enterTodayPage(tester, totalMinutes: 60, settledBefore: 0);
    await tester.pump(const Duration(milliseconds: 64));

    expect(h.sunlight.entries, isEmpty, reason: 'C78：称号节点零阳光、零账本行');
    expect(await h.sunlight.balance(), 0);
    expect(h.store.value, 1);

    final bool fxShown = await _pumpUntil(
      tester,
      () => find.byKey(kLevelUpFxCardKey).evaluate().isNotEmpty,
    );
    expect(fxShown, isTrue, reason: '称号节点解锁仍播演出（C78 演出保留）');
    expect(
      find.byKey(kLevelUpFxCardKey).evaluate().length,
      1,
      reason: '⚠️ 一次进页只播 1 场（in-flight 闸门）',
    );
    expect(find.text('解锁新称号！'), findsOneWidget);
    expect(find.text('Lv.1 · 专注小萌芽'), findsOneWidget);
    // C78：阳光行因 `totalSunlight > 0` 恒假自动隐藏，不得出现「+N」。
    expect(find.text('+3'), findsNothing, reason: 'C78 后不再显示 +N ☀ 阳光行');
  });

  // ⚠️ AC-03 已按 **C74 §6 修订二** 改写（2026-10-14 玄参拍板「每次升级都播」）：
  // 旧口径「普通升级零演出」作废；新口径 = **播 default 素材的演出，但零阳光、零账本行**。
  testWidgets(
      '③ 普通升级：播 default 演出 + 零阳光零账本行，徽章仍到 Lv.4',
      (WidgetTester tester) async {
    // 历史态：SP = 1（已发过 Lv.1），账本里也有 lv1 那条。
    final _TodayHarness h = await enterTodayPage(
      tester,
      totalMinutes: 360, // 6h = Lv.4
      settledBefore: 1,
      seededLevels: <int>[1],
    );
    for (int i = 0; i < 6; i++) {
      h.triggerReload();
      await tester.pump(const Duration(milliseconds: 32));
    }
    // 演出是 async 解析帧后插入的，多给几帧让它上屏。
    await tester.pump(const Duration(milliseconds: 96));

    // 🔴 经济层：零入账（C78：连称号节点也零账本行）。
    expect(h.sunlight.entries.length, 1,
        reason: 'Lv.2/3/4 都不是称号节点 ⇒ 零入账（只剩预置的 lv1 历史行）');
    expect(await h.sunlight.balance(), 1, reason: '余额仍是预置的 lv1 历史行');

    // 🔴 视觉层：普通升级**要播**一场（用 default 素材的标题，不是「解锁新称号」）。
    expect(find.byKey(kLevelUpFxCardKey), findsOneWidget,
        reason: 'C74 §6 修订二：普通升级也播演出');
    expect(find.text('升级啦！'), findsOneWidget,
        reason: '普通升级用 default 演出的标题');

    expect(find.text('Lv.4'), findsOneWidget, reason: '徽章仍更新到 Lv.4');
    expect(find.text('专注小萌芽'), findsOneWidget,
        reason: 'Lv.4 的称号仍是已解锁的最高称号节点 Lv.1');
  });

  // 玄参 2026-10-14 下午 v2「摘要 + 点按详情」：徽章**宽度不再靠提示语撑**，改由
  // 「称号实测量 vs 细进度条 [kLevelBarWidth]」取大决定。用 TextPainter 实测 +
  // RenderBox 实测量，证明上界 [kLevelBadgeMaxWidth]=152 定得既不截断也不浪费。
  testWidgets('⑧ 徽章摘要态尺寸：宽度由称号实测量决定、不被截断且明显小于旧版',
      (WidgetTester tester) async {
    await enterTodayPage(tester, totalMinutes: 900);

    // 文案列可用宽（与 focus_level_badge.dart 内层约束同式：152−20−38−8）。
    const double columnMax = kLevelBadgeMaxWidth -
        2 * kLevelBadgePadH -
        kLevelBadgeDiameter -
        kLevelBadgeGap;
    expect(columnMax, 86.0, reason: '文案列可用宽（改布局必改此处）');

    // 称号位候选：9 个称号（一律 5 字）+ 未解锁占位（6 字，最长）。
    double widest = 0;
    for (final String text
        in <String>{kLevelBadgeLockedTitle, ...kFocusLevelTitles}) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontSize: kLevelTitleFontSize,
            height: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: columnMax);
      if (painter.width > widest) widest = painter.width;
      expect(painter.didExceedMaxLines, isFalse,
          reason: '「$text」在摘要徽章里必须**一行**显示完（摘要态不放换行）');
    }
    expect(widest, lessThanOrEqualTo(columnMax),
        reason: '最宽称号 ${widest.toStringAsFixed(1)}pt 必须排得进文案列');

    // RenderBox 实测量：宽 ≪ 旧版 220、高 ≈44（旧版 54）。
    final Rect badge = tester.getRect(find.byKey(FocusLevelBadge.badgeKey));
    expect(badge.width, lessThanOrEqualTo(kLevelBadgeMaxWidth),
        reason: '徽章宽不得越界，实测 ${badge.width.toStringAsFixed(1)}pt');
    expect(badge.width, lessThan(160),
        reason: 'v2 摘要徽章应「明显小于」旧版 220pt，实测 '
            '${badge.width.toStringAsFixed(1)}pt');
    expect(badge.height, lessThan(50),
        reason: 'v2 摘要徽章高度应 ≈44pt（旧版 54），实测 '
            '${badge.height.toStringAsFixed(1)}pt');
  });

  testWidgets('④ 重复刷新幂等：连续 5 次 reload → 零阳光零账本行（C78）',
      (WidgetTester tester) async {
    final _TodayHarness h = await enterTodayPage(
      tester,
      totalMinutes: 480, // 8h = Lv.5
      settledBefore: 0,
    );
    await tester.pump(const Duration(milliseconds: 96));

    expect(h.sunlight.entries, isEmpty, reason: 'C78：首轮结算也零账本行');
    expect(await h.sunlight.balance(), 0);
    expect(h.store.value, 5);

    // 连续 5 次 C68 刷新（切回 tab / 回前台同路径）。
    for (int i = 0; i < 5; i++) {
      h.triggerReload();
      await tester.pump(const Duration(milliseconds: 96));
    }
    expect(h.sunlight.entries, isEmpty, reason: '🔴 重复进页也不新增（I1）');
    expect(await h.sunlight.balance(), 0);
    expect(h.store.value, 5);
  });

  testWidgets('⑤ 称号解耦：累计 900 分钟（Lv.7）→ Lv.7 + 称号仍是「专注小苗苗」',
      (WidgetTester tester) async {
    await enterTodayPage(tester, totalMinutes: 900);
    await tester.pump(const Duration(milliseconds: 96));

    expect(find.text('Lv.7'), findsOneWidget);
    expect(find.text('专注小苗苗'), findsOneWidget,
        reason: '🔑 Lv.7 的称号 = 已解锁的最高称号节点 Lv.5');
    // v2：摘要态只有「圆徽 + 称号 + 进度条」，进度文案移入详情卡
    // （「距 Lv.8 还需」口径由 `focus_level_detail_dialog_test.dart` 承接）。
    await tester.tap(find.byKey(FocusLevelBadge.badgeTapKey));
    // ⚠️ 不能用 `pumpAndSettle`：今日页有一支**永不停止**的飘动动画（阳光气泡
    // Lissajous），settle 永远等不到 —— 这里只推两帧等 Dialog 入场完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final Text gap =
        tester.widget<Text>(find.byKey(FocusLevelDetailDialog.gapTextKey));
    expect(gap.data, contains('距 Lv.8 还差'),
        reason: '进度指向**下一级**，不是下一个称号（详情卡承接原进度文案）');
  });

  testWidgets('⑥ 不可见不播：tab 不是今日 ⇒ 结算照常（零账本行，C78），但不插演出浮层',
      (WidgetTester tester) async {
    final _TodayHarness h = await enterTodayPage(
      tester,
      totalMinutes: 60,
      tab: kChildTabIndexOfGarden,
      settledBefore: 0,
    );
    await tester.pump(const Duration(milliseconds: 128));

    expect(h.sunlight.entries, isEmpty, reason: 'C78：结算零账本写入');
    expect(h.store.value, 1, reason: '结算照常推进 SP');
    expect(find.byKey(kLevelUpFxCardKey), findsNothing,
        reason: '页面不可见 ⇒ 只结算不播');
  });

  testWidgets('⑦ 空间红线：C67 冻结常量未改 + 手机视口徽章不侵占气泡区',
      (WidgetTester tester) async {
    expect(kTodayCardTopRatio, 0.40, reason: 'C67 冻结值');
    expect(kTodayBgPanelTargetRatio, 0.37, reason: 'C67 冻结值');

    await enterTodayPage(tester, totalMinutes: 900);
    await tester.pump(const Duration(milliseconds: 96));

    final Rect badgeRect =
        tester.getRect(find.byKey(FocusLevelBadge.badgeKey));
    expect(badgeRect.left, closeTo(402 * kTodayBadgeLeftRatio, 1.0));
    expect(badgeRect.top, closeTo(874 * kTodayBadgeTopRatio, 1.0));
    expect(badgeRect.right, lessThan(402 * 0.60),
        reason: '徽章不得侵占右下阳光气泡活动区（x 241–379pt）');
  });

  testWidgets('⑦b 平板适配：徽章尺寸 × uiScaleOf(1.3)，回左上角贴花头上方（F142 四轮）',
      (WidgetTester tester) async {
    await enterTodayPage(
      tester,
      totalMinutes: 900,
      size: const Size(834, 1194),
    );
    await tester.pump(const Duration(milliseconds: 96));

    final Rect circleRect =
        tester.getRect(find.byKey(FocusLevelBadge.badgeCircleKey));
    final Rect badgeRect =
        tester.getRect(find.byKey(FocusLevelBadge.badgeKey));
    expect(circleRect.width, closeTo(kLevelBadgeDiameter * kTabletUiScale, 0.8),
        reason: '平板：圆形徽章直径 × [kTabletUiScale]');
    // F142 四轮（玄参拍板「按 iPhone 的布局放回左上角」）：left 与手机同款比例。
    expect(badgeRect.left, closeTo(834 * kTodayBadgeLeftRatio, 1.0),
        reason: '平板徽章 left = 屏宽 × kTodayBadgeLeftRatio(0.04) ≈ 33.4pt');
    // top 锚「花头立绘顶 − kTodayBadgeHeadGap(8)」再上移自身高度 ⇒
    // 渲染后**底边 = 花头顶 − 8**（花头矩形由真实 DecorationImage.alignment
    // 反算，与生产 cover 几何同源，不猜数值）。
    final Rect decorationBox = tester.getRect(
        find.byKey(TabBackground.decorationKey));
    final DecoratedBox decorated = tester.widget<DecoratedBox>(
        find.byKey(TabBackground.decorationKey));
    final Alignment alignment =
        (decorated.decoration as BoxDecoration).image!.alignment as Alignment;
    final Rect plant = todayBgSunflowerScreenRect(
      box: decorationBox.size,
      alignmentY: alignment.y,
    ).shift(decorationBox.topLeft);
    expect(badgeRect.bottom, closeTo(plant.top - kTodayBadgeHeadGap, 1.0),
        reason: '平板徽章底边 = 花头顶 − 8pt（贴花头上方）'
            '(徽章底 ${badgeRect.bottom.toStringAsFixed(1)} / '
            '花头顶 ${plant.top.toStringAsFixed(1)})');
    expect(badgeRect.overlaps(plant), isFalse,
        reason: '平板徽章 ∩ 向日葵立绘 = ∅ (徽章 $badgeRect / 立绘 $plant)');
    expect(badgeRect.right, lessThanOrEqualTo(834), reason: '不越屏右');
  });
}

/// 测试内的小工具：按分钟算出徽章数据（避免每个用例重复写 transform）。
class FocusLevelProgressForUI {
  FocusLevelProgressForUI(this.minutes) : _p = progressOf(minutes);

  final double minutes;
  final dynamic _p;

  int get level => _p.level as int;
  bool get isLocked => _p.isLocked as bool;
  int get minutesToNext => _p.minutesToNext as int;
}
