/// 今日页「专注等级」徽章 **占位禁区** 度量护栏（2026-10-14 玄参真机反馈）。
///
/// ## 背景（玄参 iOS 手机模拟器截图实证）
/// 手机端徽章气泡「🌱 尚未解锁称号」压住向日葵花头左上；独立提示行
/// 「再专注 40 分钟解锁 专注小萌芽」横穿向日葵脸部、无托底完全不可读。
///
/// ## 修法（三版演进后定稿）
///  · v1：提示行收进气泡内 + 锚点 0.17 → **0.11**；
///  · v2（2026-10-14 下午拍板「**摘要 + 点按详情**」）：徽章降级为摘要 ——
///    只剩「圆徽 + 称号 + 细进度条」（≈**144×44pt**，旧版 220×54），提示文案
///    整体撤出、改由点按后的**详情卡**承载 ⇒ 墙区余量随之翻倍。
///  · 锚点机制：手机 [kTodayBadgeTopRatio]=0.11（left 两端共用
///    [kTodayBadgeLeftRatio]）；平板 F142 四轮起锚「花头立绘顶 −
///    [kTodayBadgeHeadGap]」再上移自身高度（贴花头上方，见下）。
///
/// ## 本文件用 RenderBox 实测钉死三条硬约束（team-lead 拍板）
///  a) **徽章整体 bounds 与向日葵立绘 bounds 不相交** —— 立绘矩形来自
///     `kTodayBgSunflowerNormalizedRect`（PIL 逐像素标定 `today.webp`：
///     花瓣顶 y583 / 左右缘 x205·x565 / 盆底 y1204，取整外扩），经
///     [todayBgSunflowerScreenRect] 用**真实渲染的对齐值 + cover 几何**映射到
///     屏幕矩形（与 `today_card_breathing_band_test.dart` 的分界线同源手法，
///     不猜数值）；
///  b) **徽章整体 bounds 与「今日」标题 pill bounds 不相交** —— 标题 pill 用
///     真实 `AppBar` 的文字 RenderBox 实测（`extendBodyBehindAppBar` 沉浸式，
///     状态栏用各机型**真实 inset**，非同值假数据）；
///  c) **摘要尺寸**：宽 ≤ [kLevelBadgeMaxWidth] 且 < 160（明显小于旧版 220）、
///     高 ≈44（旧版 54）—— 「大幅缩小」是拍板项，必须有数。
///
/// ## 平板：v4 右对齐（已废弃）→ F142 四轮回左上角「贴花头上方」
/// v4 时代（2026-10-15）：平板底图对齐到 0.37 × 屏高（C64/C67），花头被 cover
/// 抬到屏 y≈44、左上墙区被占 → 徽章曾移到「今日 pill 右下方红框」。
///
/// **F142 四轮（2026-10-20 玄参拍板「按 iPhone 的布局放回左上角」）**：平板
/// 内容整体下移（随屏宽）后花头顶回落到 ≈140pt，pill 与花头之间放得下徽章；
/// 平板改锚「花头立绘顶 − [kTodayBadgeHeadGap]」+ `FractionalTranslation(0,-1)`
/// 上移自身高度 = **徽章底边贴在花头上方**（等比复刻手机的相对关系；挂分界线
/// 实测值，下移/切 tab 自动同步）。
///
/// 本文件对 iPad 锁**五条硬约束**（RenderBox 度量，pump 在 textScaler 1.6 下）：
/// ① ∩ 今日 pill = ∅、② ∩ 家长图标 = ∅、③ ∩ 阳光胶囊 = ∅、
/// ④ 完全在屏内、⑤ 无 RenderFlex overflow；外加「底边 = 花头顶 − 8pt」的
/// 几何锚定断言（花头矩形来自真实 DecorationImage.alignment 反算，不猜数值）。
/// 手机端约束一条不松（不压立绘 / 不压「今日」pill / 右缘 < 0.60 屏宽 / 锚点=0.11）。
///
/// 🟢 夹具纪律：不依赖网络 / 不依赖真机，纯 widget 度量；夹具与
/// `today_card_breathing_band_test.dart` 同源。
library today_badge_bounds_test;

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
import 'package:sunflower_time/presentation/child/widgets/parent_entry_action.dart';
import 'package:sunflower_time/presentation/child/widgets/tab_background.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/tab_bg_layout.dart';

// ── 夹具（与 today_card_breathing_band_test.dart 同款）────────────────────

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

/// 各机型：名字 / 逻辑分辨率 / **真实状态栏高** / 是否平板。
///
/// 状态栏用真实 inset（非同值假数据）：非全面屏 SE 只有 20pt、iPad 24pt、
/// 刘海/灵动岛机型 47~59pt —— 「徽章 ↔ 标题」的墙区预算对此非常敏感。
const List<(String, Size, double, bool)> _devices = <(String, Size, double, bool)>[
  // 小屏 Android：短宽 360 + 长宽比恰 = 底图 0.45 ⇒ cover 无竖向裁剪、花头顶
  // 被抬到最高（≈145pt）而屏又矮 —— 全机型**最紧**的余量样本（≈3pt），必锁。
  ('Android 小屏 360×800', Size(360, 800), 28, false),
  ('iPhone 6.1″ 390×844', Size(390, 844), 47, false),
  ('iPhone 17 402×874', Size(402, 874), 59, false),
  ('iPhone 15 Pro 393×852', Size(393, 852), 59, false),
  ('iPhone SE 375×667', Size(375, 667), 20, false),
  ('iPad Pro 11" 834×1194', Size(834, 1194), 24, true),
];

/// 徽章胶囊的**全局矩形**（RenderBox 实测）。
Rect _badgeRect(WidgetTester tester) =>
    tester.getRect(find.byKey(FocusLevelBadge.badgeKey));

/// 「今日」标题 pill 的**全局矩形**（真实 AppBar 文字 RenderBox 实测）。
Rect _titleRect(WidgetTester tester) => tester.getRect(find.text('今日'));

/// 向日葵立绘的**全局屏幕矩形**。
///
/// 由 `TabBackground.decorationKey` 的真实 `RenderBox.size` 与真实
/// `DecorationImage.alignment` 反算（cover 几何 + 归一化标定矩形），不猜数值。
Rect _plantRect(WidgetTester tester) {
  final Finder decoration = find.byKey(TabBackground.decorationKey);
  expect(decoration, findsOneWidget, reason: '今日页应有一张底图');
  final RenderBox box = tester.renderObject<RenderBox>(decoration);
  final DecoratedBox widget = tester.widget<DecoratedBox>(decoration);
  final BoxDecoration deco = widget.decoration as BoxDecoration;
  final Alignment alignment = deco.image!.alignment as Alignment;
  final Rect local = todayBgSunflowerScreenRect(
    box: box.size,
    alignmentY: alignment.y,
  );
  return local.shift(box.localToGlobal(Offset.zero));
}

/// 右上角「家长天地」入口图标的**全局矩形**（真实 AppBar actions 渲染）。
///
/// 用 [ParentEntryAction.iconKey] —— shell 与测试引用同一份 widget，度量与
/// 生产同源（v3 徽章右对齐到本图标所在的竖线）。
Rect _parentIconRect(WidgetTester tester) =>
    tester.getRect(find.byKey(ParentEntryAction.iconKey));

/// 悬浮阳光胶囊的**全局矩形**（含飘动偏移，单帧实测）。
Rect _bubbleRect(WidgetTester tester) =>
    tester.getRect(find.byKey(ChildTodayPage.sunBubbleKey));

/// 装配并 pump 今日页（与 child_shell_page 同款沉浸式：透明 AppBar +
/// `extendBodyBehindAppBar`，状态栏 = 机型真实 inset）。
///
/// v4：注入 app.dart 同款的 `applyTabletTextScaling` 文字放大壳（手机 no-op）；
/// [deviceTextScale] 模拟设备无障碍文字缩放（>1.0 时平板 textScaler 走到上限
/// [kTabletTextScaleMax]=1.6），用于复现/锁死「平板最大文字缩放下徽章不溢出」。
Future<void> _pumpToday(
  WidgetTester tester,
  Size screen,
  double statusHeight, {
  double deviceTextScale = 1.0,
}) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = FakeViewPadding(
    top: statusHeight,
    bottom: 0,
    left: 0,
    right: 0,
  );
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlight()),
      focusRepositoryProvider
          .overrideWithValue(_FakeFocus(totalMinutes: 30)),
      taskRepositoryProvider.overrideWithValue(_FakeTask()),
      settingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      focusLevelStoreProvider.overrideWithValue(_MemoryStore()..value = 0),
      focusLevelServiceProvider.overrideWith((Ref ref) => FocusLevelService(
            ledger: ref.watch(sunlightRepositoryProvider),
            store: ref.watch(focusLevelStoreProvider),
            idFactory: () => 'badge-bounds-probe',
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
        // v4：app.dart 同款注入壳 —— 平板文字走 textScaler（手机 no-op，零回归）。
        builder: (BuildContext context, Widget? child) {
          final Widget content = child ?? const SizedBox.shrink();
          final MediaQueryData mq =
              MediaQuery.maybeOf(context) ?? const MediaQueryData();
          // 模拟设备无障碍文字缩放（默认 1.0 = 不放大）。
          final MediaQueryData deviceMq = deviceTextScale == 1.0
              ? mq
              : mq.copyWith(textScaler: TextScaler.linear(deviceTextScale));
          final MediaQueryData scaled = applyTabletTextScaling(deviceMq);
          if (identical(scaled, deviceMq)) return content; // 手机 no-op
          return MediaQuery(data: scaled, child: content);
        },
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('今日'),
            // v3：挂上与 shell 同源的 [ParentEntryAction]，度量护栏能量到真实家长图标。
            actions: const <Widget>[ParentEntryAction(immersive: true)],
          ),
          body: page,
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

void main() {
  // 未解锁态（30 分钟 → 🌱）：称号位最长（占位文案 6 字 > 9 个称号的 5 字）
  // —— 用**最宽**的情况做度量（提示文案已迁出，不再参与宽度）。
  for (final (String name, Size screen, double statusH, bool tablet)
      in _devices) {
    testWidgets('$name · ① 摘要尺寸：宽 ≤ kLevelBadgeMaxWidth 且明显小于旧版',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen, statusH);

      final Rect badge = _badgeRect(tester);
      // C65：平板所有定尺寸元素 × uiScaleOf(1.3)，判定阈值同步放大。
      final double s = tablet ? kTabletUiScale : 1.0;

      expect(badge.width, lessThanOrEqualTo((kLevelBadgeMaxWidth * s) + 0.5),
          reason: '宽度不得越过 [kLevelBadgeMaxWidth] 上界，实测 '
              '${badge.width.toStringAsFixed(1)}pt');
      expect(badge.width, lessThan(160 * s),
          reason: 'v2 摘要徽章必须「明显小于」旧版 220pt（实测自然宽 ≈144pt），'
              '实测 ${badge.width.toStringAsFixed(1)}pt');
      expect(badge.height, lessThan(50 * s),
          reason: 'v2 摘要徽章高度应 ≈44pt（旧版 54pt），实测 '
              '${badge.height.toStringAsFixed(1)}pt');
      expect(badge.height, greaterThan(34 * s),
          reason: '也不能缩到看不清（圆徽 = kLevelBadgeDiameter = 38pt）');
      // 摘要态三件齐备：圆徽 + 称号 + 细进度条；提示文案**已撤出**。
      expect(find.byKey(FocusLevelBadge.badgeCircleKey), findsOneWidget);
      expect(find.byKey(FocusLevelBadge.badgeBarKey), findsOneWidget);
      expect(find.text(kLevelBadgeLockedTitle), findsOneWidget);
    });

    // 平板（F142 四轮）：徽章贴花头上方（底边 = 花头顶 − 8pt），恢复「不压
    // 立绘」禁区 + 平板特有约束；手机仍是「不压立绘」（锚点 0.11 不变）。
    testWidgets(
        '$name · ${tablet ? '⑤ 平板五条硬约束（含无溢出）' : 'a 徽章不压向日葵立绘'}',
        (WidgetTester tester) async {
      if (tablet) {
        // v4：平板在最大文字缩放（textScaler 1.6，deviceTextScale 1.23 → ×1.3 钳
        // 上限）下 pump，验证徽章既不溢出、也满足 4 条位置约束。捕获 pump 期的
        // FlutterError（RenderFlex overflow 会经 onError 上报），断言无 overflow。
        final List<FlutterErrorDetails> renderErrors = <FlutterErrorDetails>[];
        final void Function(FlutterErrorDetails)? prevOnError =
            FlutterError.onError;
        FlutterError.onError = renderErrors.add;
        try {
          await _pumpToday(tester, screen, statusH, deviceTextScale: 1.23);
        } finally {
          FlutterError.onError = prevOnError;
        }

        final Rect badge = _badgeRect(tester);
        // F142 四轮：平板徽章回左上角，「贴花头上方」—— 底边 = 花头立绘顶 −
        // kTodayBadgeHeadGap(8pt)（FractionalTranslation(0,-1) 上移自身高度；
        // 花头矩形来自真实 DecorationImage.alignment 反算，与生产同源）。
        final Rect plant = _plantRect(tester);
        expect(badge.bottom, closeTo(plant.top - kTodayBadgeHeadGap, 1.0),
            reason: '平板徽章底边必须 = 花头顶 − 8pt（贴花头上方）'
                '(徽章底 ${badge.bottom.toStringAsFixed(1)} / '
                '花头顶 ${plant.top.toStringAsFixed(1)})');
        expect(badge.left, closeTo(screen.width * kTodayBadgeLeftRatio, 1.0),
            reason: '平板 left 与手机同款比例 kTodayBadgeLeftRatio(0.04)');
        // 徽章整体必须落在花头**上方**（四轮起几何上可能，恢复手机同款禁区）。
        expect(badge.overlaps(plant), isFalse,
            reason: '平板徽章 ∩ 向日葵立绘 = ∅ (徽章 $badge / 立绘 $plant)');
        // ① 徽章 ∩ 「今日」标题 pill = ∅。
        final Rect title = _titleRect(tester);
        expect(badge.overlaps(title), isFalse,
            reason: '平板徽章 ∩ 今日 pill = ∅ (徽章 $badge / 标题 $title)');
        // ② 徽章 ∩ 家长入口图标 = ∅（四轮起徽章在左上角，水平间距自然极大）。
        final Rect parentIcon = _parentIconRect(tester);
        expect(badge.overlaps(parentIcon), isFalse,
            reason: '平板徽章 ∩ 家长图标 = ∅ (徽章 $badge / 家长图标 $parentIcon)');
        // ③ 徽章 ∩ 阳光胶囊 = ∅（胶囊会飘动，单帧实测即可——间隙足够大）。
        final Rect bubble = _bubbleRect(tester);
        expect(badge.overlaps(bubble), isFalse,
            reason: '平板徽章 ∩ 阳光胶囊 = ∅ (徽章 $badge / 胶囊 $bubble)');
        // ④ 完全在屏内不越界。
        expect(badge.left, greaterThanOrEqualTo(0), reason: '左缘不越屏左');
        expect(badge.right, lessThanOrEqualTo(screen.width),
            reason: '右缘不越屏右');
        expect(badge.top, greaterThanOrEqualTo(0), reason: '顶不越屏顶');
        expect(badge.bottom, lessThanOrEqualTo(screen.height),
            reason: '底不越屏底');
        // ⑤ 无 RenderFlex overflow（textScaler 1.6 下徽章 Row 不得溢出）。
        expect(
          renderErrors.where((FlutterErrorDetails e) =>
              e.exception.toString().contains('overflow') ||
              e.exception.toString().contains('RenderFlex')),
          isEmpty,
          reason: '平板 textScaler 1.6 下徽章不得 RenderFlex overflow '
              '（捕获到的错误：$renderErrors）',
        );
        return;
      }

      // 手机：不压向日葵立绘（v3 既有约束，一条不松）。
      await _pumpToday(tester, screen, statusH);
      final Rect badge = _badgeRect(tester);
      final Rect plant = _plantRect(tester);
      expect(
        badge.overlaps(plant),
        isFalse,
        reason: '徽章必须落在「今日」pill ↔ 向日葵花头之间的空白墙区 —— '
            '与立绘 bounds 不相交 '
            '(徽章 $badge / 立绘 $plant)',
      );
      // 立绘矩形 sanity：手机 cover 恒 topCenter，花头顶应由源图 y580 直接决定
      // （390 → ≈157pt / 402 → ≈162pt），若对齐逻辑被误改这里会先红。
      expect(plant.top, closeTo(580 * screen.width / 1440, 1.0),
          reason: '手机底图恒 topCenter ⇒ 花头顶 = 源 y580 × 屏宽/1440');
    });

    testWidgets('$name · b 徽章不与「今日」标题 pill 重叠',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen, statusH);

      final Rect title = _titleRect(tester);
      final Rect badge = _badgeRect(tester);

      expect(
        badge.overlaps(title),
        isFalse,
        reason: '徽章上移后不得撞回「今日」标题 pill '
            '(标题 $title / 徽章 $badge)',
      );
      expect(badge.top, greaterThan(title.bottom),
          reason: '徽章必须整块落在标题 pill 之下');
    });
  }

  // 手机右缘红线（气泡区 x 241–379pt 在 402 宽上的口径）——已有
  // focus_level_today_page_test ⑦ 在 402×874 上钉过；这里对**全部手机机型**再锁
  // 一遍（v2 改宽度后这条更宽裕，但它是 C44g 拍板的红线，不许因为改版而松）。
  for (final (String name, Size screen, double statusH, bool tablet)
      in _devices) {
    if (tablet) continue;
    testWidgets('$name · c 右缘 < 气泡区红线（宽 × 0.60）',
        (WidgetTester tester) async {
      await _pumpToday(tester, screen, statusH);

      final Rect badge = _badgeRect(tester);
      expect(badge.right, lessThan(screen.width * 0.60),
          reason: '徽章右缘不得侵占右下阳光气泡活动区，实测 '
              '${badge.right.toStringAsFixed(1)}pt');
      expect(badge.top, closeTo(screen.height * kTodayBadgeTopRatio, 1.0),
          reason: '手机锚点 = kTodayBadgeTopRatio(0.11) × 屏高');
    });
  }
}
