/// F144 · A 项：**「开始专注」按钮固定屏幕底部**守卫。
///
/// ## 背景
/// 迁移前按钮是 `ListView` 的**最后一个子项** —— 孩子往上滚看「专注时的小设置」
/// 时按钮跟着滚走，想开始专注还得先滚回底部；图标还是硬写的 emoji `🌻`。
///
/// ## 修法（架构师定稿，禁用 `bottomNavigationBar` 槽）
/// `body: Column[Expanded(SafeArea(bottom:false, ListView)), 底部固定区]`；
/// 固定区外层 `SafeArea(top:false)` 吃 home indicator，内层 `Container` 用页面
/// 同款米色底 + 顶部 1px 分割线。
///
/// ⚠️ 刻意**不用** `Scaffold.bottomNavigationBar`：项目有 C105/F112 前科 ——
/// 该槽内 `Center`/`Align` 缺 `heightFactor: 1` 会把整页撑成空白。
///
/// ## 本文件锁三条
///  ① **不随滚动移动**：`tester.drag` 把 ListView 滚到底前后，按钮
///     `getRect().top` **不变**（且先证明「确实滚动了」，防假绿）；
///  ② **不出安全区**：按钮矩形底边 ≤ 屏高 − 底部安全区（含 iPhone home indicator）；
///  ③ **图标换成阳光美术**：按钮内不再有 `🌻` 文本，而是
///     `assets/rewards/sunlight.png`（`Image`），且尺寸乘了 `uiScaleOf`；
///  ④ 高度 60 × uiScale、文案不变；
///  ⑤ **底色 = 主题 primary**（F147：删 `_kAmber` 硬编码，与今日 tab 钉底
///     按钮同色同源 —— 主题相对断言，硬编码颜色写回来即红）。
library entry_sticky_button_test;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/settings_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/presentation/child/pages/entry_page.dart';

// ── 夹具（最小 Fake 集：入口页只读设置 / 会话 / 账本）─────────────────────

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
        gardenPotCapacity: 6,
      );

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> append(SunlightEntry entry) async => 0;
  @override
  Future<double> balance() async => 0;
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
          String refType, String refId, String dayKey) async =>
      0;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
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

/// 装配真实 [EntryPage]（页内自带 L10nScope，宿主不需要 delegates）。
Widget _host() => ProviderScope(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
        sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
        focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      ],
      child: const MaterialApp(home: EntryPage()),
    );

/// 手机 402×874 + iPhone home indicator（底部安全区 34pt）。
const Size _kPhone = Size(402, 874);
const double _kBottomInset = 34;

Future<void> _pumpEntry(WidgetTester tester) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = const FakeViewPadding(
    top: 59,
    bottom: _kBottomInset,
    left: 0,
    right: 0,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_host());
  // 有界 pump：等 `_loadRemaining` / `settingsProvider` 的异步首帧落地。
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// ListView 当前的滚动偏移（找不到 Scrollable 时返回 null）。
double? _scrollOffset(WidgetTester tester) {
  final Finder scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isEmpty) return null;
  return tester.state<ScrollableState>(scrollable.first).position.pixels;
}

void main() {
  testWidgets('① 主按钮固定底部：ListView 滚到底前后按钮 top 不变', (WidgetTester tester) async {
    await _pumpEntry(tester);

    final Finder button = find.byType(FilledButton);
    expect(button, findsOneWidget, reason: '入口页只有一颗主按钮');

    final Rect before = tester.getRect(button);
    final Offset chipAnchorBefore =
        tester.getRect(find.text('这次想专注多久？')).topLeft;

    // 往上拖 = 内容上移（滚到底）。
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final double? offset = _scrollOffset(tester);
    expect(offset, isNotNull, reason: '入口页应有可滚动列表');
    expect(offset, greaterThan(0),
        reason: '前置条件：本用例必须先**真的滚动起来**，否则「top 不变」是假绿');

    final Offset chipAnchorAfter =
        tester.getRect(find.text('这次想专注多久？')).topLeft;
    expect(chipAnchorAfter.dy, lessThan(chipAnchorBefore.dy),
        reason: '滚动内容必须真的上移了（锚点卡片标题上移）');

    final Rect after = tester.getRect(button);
    expect(after.top, closeTo(before.top, 0.01),
        reason: '🔴 主按钮固定在屏幕底部：滚动前后 top 必须逐像素一致 '
            '(before=${before.top} / after=${after.top})');
    expect(after.bottom, closeTo(before.bottom, 0.01),
        reason: '按钮底边同样不得随滚动变化');
  });

  testWidgets('② 按钮底边不越出底部安全区（home indicator 被 SafeArea 吃掉）',
      (WidgetTester tester) async {
    await _pumpEntry(tester);

    final Rect button = tester.getRect(find.byType(FilledButton));
    expect(button.bottom, lessThanOrEqualTo(_kPhone.height - _kBottomInset + 0.01),
        reason: '按钮矩形不得压进 home indicator 区（安全区底 ${_kPhone.height - _kBottomInset}）');
    expect(button.bottom, greaterThan(_kPhone.height * 0.75),
        reason: '按钮应该在屏幕下半部（固定在底部，而不是内容中间）');
    // 水平方向：左右各留 20pt 内边距，且整颗按钮在屏内。
    expect(button.left, closeTo(20, 0.01));
    expect(button.right, closeTo(_kPhone.width - 20, 0.01));
  });

  testWidgets('③ 图标换成阳光美术（不再有 🌻 文本；Image 尺寸 = 26 × uiScaleOf）',
      (WidgetTester tester) async {
    await _pumpEntry(tester);

    final Finder button = find.byType(FilledButton);
    expect(
      find.descendant(of: button, matching: find.text('🌻')),
      findsNothing,
      reason: 'F144：硬写 emoji 已换成 assets/rewards/sunlight.png',
    );

    final Finder icon = find.descendant(
      of: button,
      matching: find.byWidgetPredicate((Widget w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/rewards/sunlight.png'),
    );
    expect(icon, findsOneWidget, reason: '按钮内必须有阳光图标（Image.asset）');

    // 手机 uiScale = 1.0 ⇒ 26pt（平板乘 1.3 / 1.6，见 shared/responsive.dart）。
    final Size size = tester.getSize(icon);
    expect(size.width, closeTo(26, 0.01));
    expect(size.height, closeTo(26, 0.01));
  });

  testWidgets('④ 按钮高度 60pt（手机 uiScale 1.0）且文案仍是「开始专注」',
      (WidgetTester tester) async {
    await _pumpEntry(tester);

    final Rect button = tester.getRect(find.byType(FilledButton));
    // 60 是「只随屏幕变大」的绝对尺寸，手机 1.0 → 恰好 60。
    expect(button.height, closeTo(60, 0.01),
        reason: 'minimumSize: Size.fromHeight(60 * uiScaleOf) ⇒ 手机 60pt');
    expect(find.text('开始专注'), findsWidgets, reason: '主按钮文案不变');
  });

  testWidgets('⑤ 底色 = 主题 primary（F147：与今日 tab 钉底按钮同色同源）',
      (WidgetTester tester) async {
    await _pumpEntry(tester);

    // F147（玄参 2026-10-22 拍板「应该保持都是一样的底色」）：删除 `_kAmber`
    // 硬编码后，按钮底色回落主题 primary —— 与今日 tab 的 `FilledButton.icon`
    // （无 backgroundColor 覆盖）同源。守卫断言「渲染出的 Material 颜色 ==
    // Theme.colorScheme.primary」，主题相对 ⇒ 裸测试宿主与真机壳都成立；
    // 谁再把硬编码颜色写回来（无论什么颜色）即红。
    final Finder button = find.byType(FilledButton);
    final BuildContext btnCtx = tester.element(button);
    final Color expected = Theme.of(btnCtx).colorScheme.primary;

    final Finder material = find.descendant(
      of: button,
      matching: find.byWidgetPredicate((Widget w) =>
          w is Material && w.color != null),
    );
    expect(material, findsOneWidget,
        reason: 'FilledButton 内层应有带底色的 Material（FittedBox 之外的实体层）');
    final Color actual = tester.widget<Material>(material).color!;
    expect(actual, expected,
        reason: '入口页主按钮底色必须 = 主题 primary（橄榄绿，与今日 tab 一致）；'
            '实际 $actual ≠ $expected —— 大概率有人把硬编码颜色写回来了');
  });
}
