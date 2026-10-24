/// F144 · E 项（返工版）：**手机端「我的」tab 阳光卡片英文被挤成 3 行** 守卫。
///
/// ## 背景（玄参实测）
/// 阳光卡片第二行原本是**一个** `Text(_t.profile_balance_line(n))`，而
/// `profile_balance_line` 的文案带尾缀 ` ☀`（例：`Sunlight: 1,000 ☀`）。
/// 该行左侧被 64pt 头像挤、右侧被「阳光来源」按钮挤 —— 英文模式下整行放不下，
/// 「☀」被折到**第三行**。
///
/// ## 修法（v2，禁缩字号、禁缩放变换）
///  ① `profile_balance_line` **去掉尾缀 ` ☀`**，文案与图标拆成
///     `Row [Flexible(Text(maxLines 2, ellipsis)), SizedBox(4), Image(18×uiScaleOf)]`；
///  ② **可让的组件先让**：`LayoutBuilder` 量宽，低于
///     `_kSourceButtonCompactThreshold(220)` 时「阳光来源」退化为纯 `IconButton`
///     （tooltip 保语义），把 60~110pt 还给文案；
///  ③ 🔴 **整行不含任何缩放变换**：无 `FittedBox`、不按宽度改 `fontSize`。
///     首版用 `FittedBox(scaleDown)` 兜底，320×568+en+1.3 实测把整行缩到
///     **4.5%**（余额不可读）→ 已废弃。字号恒 18（孩子端无障碍口径），
///     装不下折第 2 行 / 省略号（余额明细可点「阳光来源」查看）。
///
/// ## 本文件锁八条（真实排版/度量证据）
///  ① 前提：320×568 手机上 `uiScaleOf == 1.0`、`textScaler == 1.3`；
///  ② 真实装配（320×568 + en + 1.3）→ `takeException()` 为 null、仍是英文；
///  ③ 320×568 + en + 1.3 → 行高 ≤ 单行 × 2.15（**最多 2 行**）；
///  ④ 430×932 + en（玄参截图机型）→ **单行保障**：宽档结构 + 字符预算 ≤19
///     （🔴 真机行数不可用测试字体断，F141 镜像）；
///  ⑤ 430×932 + zh → 文案逐字节、单行、窄档**不触发**（按钮仍带文字）；
///  ⑥ 结构：文案无 `☀`、无任何 `FittedBox`、`maxLines == 2`、字号恒 18、
///     图标 `18 × uiScaleOf`、间距 4；
///  ⑦ zh 变更本身不新增宽度：新固定块（4+18）≤ 旧尾缀「 ☀」实测宽；
///  ⑧ 窄档按钮退化：320+en+1.3 下「来源」文字消失（纯图标）；430+zh 下文字在场
///     （同用例两阶段靠 `_pumpProfile` 的 per-phase key 强制 remount 防 locale 残留）。
library profile_balance_line_fit_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/check_in.dart';
import 'package:sunflower_time/domain/entities/focus_session.dart';
import 'package:sunflower_time/domain/entities/focus_stats.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/sunlight_entry.dart';
import 'package:sunflower_time/domain/entities/task.dart';
import 'package:sunflower_time/domain/repositories/focus_repository.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/repositories/sunlight_repository.dart';
import 'package:sunflower_time/domain/repositories/task_repository.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/presentation/child/pages/child_profile_page.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 阳光卡片第二行的文案字号（**无障碍口径，禁改**）。
const double _kBalanceFontSize = 18;

/// 文案与图标之间的固定间距（`SizedBox(width: 4)`）。
const double _kBalanceIconGap = 4;

/// 阳光图标边长（手机基准值；实际渲染再乘 `uiScaleOf`）。
const double _kBalanceIconSize = 18;

/// 最窄手机档 + 系统大字号（i18n 溢出探测沿用口径）。
const Size _kPhone320 = Size(320, 568);

/// 正常手机档（iPhone 15 Pro Max 逻辑宽 430）。
const Size _kPhone430 = Size(430, 932);

/// 阳光行那一行「文案 + 图标」的容器 `Row`（文案 `Text` 的最近祖先）。
Finder get _balanceLineFinder => find.ancestor(
      of: _balanceTextFinder,
      matching: find.byType(Row),
    ).first;

/// 阳光行文案 `Text`（稳定 Key，生产代码里已挂）。
Finder get _balanceTextFinder =>
    find.byKey(const ValueKey<String>('child_profile_balance_line'));

// ───────────────────────────────────────────────────────────────────────────
// 最小 Fake 集（只覆盖「我的」页 `_reload` 读到的四口）
// ───────────────────────────────────────────────────────────────────────────

class _FakeFocusRepository implements FocusRepository {
  @override
  Future<FocusStats> totalStats() async => const FocusStats(
        totalFocusMinutes: 1230,
        totalSessions: 42,
        totalValidDays: 18,
      );
  @override
  Future<void> saveSession(FocusSession session) async {}
  @override
  Future<List<FocusSession>> sessionsOfDay(String dayKey) async =>
      <FocusSession>[];
  @override
  Future<int> countValidFocusDaysLastWeek(DateTime now) async => 0;
}

class _FakeTaskRepository implements TaskRepository {
  @override
  Future<int> totalCheckInCount() async => 7;
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
  Future<List<PlantSpecies>> species() async => <PlantSpecies>[];
}

/// 阳光账本桩：余额给**四位数**（最宽的可能值，`9999` 比 `0` 宽）。
class _FakeSunlightRepository implements SunlightRepository {
  @override
  Future<double> balance() async => 9999;
  @override
  Future<int> countByRefType(String refType) async => 0;
  @override
  Future<double> append(SunlightEntry entry) async => 9999;
  @override
  Future<List<SunlightEntry>> all() async => <SunlightEntry>[];
  @override
  Future<SunlightEntry?> latestByRefType(String refType) async => null;
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
  Future<int> countByRefTypeAndRefIdSince(
          String refType, String refId, DateTime since) async =>
      0;
  @override
  Future<DateTime?> lastTsByRefTypeAndRefId(
          String refType, String refId) async =>
      null;
}

/// 真实装配「我的」页并等 `_reload` 落地（有界步进 pump）。
Future<void> _pumpProfile(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required AppLanguage lang,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  AppLocaleController.init(lang);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  addTearDown(() => AppLocaleController.init(AppLanguage.system));

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      focusRepositoryProvider.overrideWithValue(_FakeFocusRepository()),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      plantRepositoryProvider.overrideWithValue(_FakePlantRepository()),
      sunlightRepositoryProvider.overrideWithValue(_FakeSunlightRepository()),
    ],
    child: MaterialApp(
      // 🔴 每阶段一个 key：同用例二次 pump（如 ⑧ 先窄档后宽档）时，若 widget
      // 结构全同，Flutter 会**复用** element 树而非 remount —— 页内 `_l10n`/
      // Localizations 资源停在第一阶段 locale，「来源/History」找错对象。
      // key 随 (尺寸, 语言, 字号) 变化 ⇒ 阶段切换必然整树 remount。
      key: ValueKey<String>('${size.width}x${size.height}-${lang.name}-$textScale'),
      // 页级 scope 由生产壳（child shell）提供；本用例显式补上，否则
      // `l10nOf` 静默回退中文 → 探的其实是 zh，测不出 EN 折行。
      home: const L10nScope(child: Scaffold(body: ChildProfilePage())),
    ),
  ));

  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (_balanceTextFinder.evaluate().isNotEmpty) break;
  }
  expect(_balanceTextFinder, findsOneWidget,
      reason: '阳光行必须渲染出来（否则后面所有度量都是空转）');
}

void main() {
  final AppLocalizations en = AppLocalizationsEn();
  final AppLocalizations zh = AppLocalizationsZh();

  testWidgets('① 前提：320×568 手机档 uiScale = 1.0、textScaler 透传 1.3',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone320,
      textScale: 1.3,
      lang: AppLanguage.en,
    );

    final BuildContext ctx = tester.element(_balanceTextFinder);
    expect(uiScaleOf(ctx), closeTo(1.0, 0.001),
        reason: '320 宽手机上 uiScaleOf 必须回落到 1.0（不许靠平板倍率顺便变宽）');
    expect(MediaQuery.textScalerOf(ctx).scale(1.0), closeTo(1.3, 0.001),
        reason: '平台 textScaler 1.3 应原样透传到 MediaQuery');
  });

  testWidgets('② 真实装配（320×568 + en + 1.3）：无布局异常、仍是英文',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone320,
      textScale: 1.3,
      lang: AppLanguage.en,
    );

    // 防假绿：先证明渲染的**确实是英文**（回退 zh 会让下面的断言失去意义）。
    expect(tester.widget<Text>(_balanceTextFinder).data, contains('Sunlight'),
        reason: '本用例必须在 en 文案下探；出现中文说明又回退成 zh 了');

    expect(tester.takeException(), isNull,
        reason: 'EN + 1.3 倍字号 + 320 宽下「我的」页不得出现 RenderFlex overflow');
  });

  testWidgets('③ 320×568 + en + 1.3：行高 ≤ 单行 × 2.15（最多 2 行，绝不更多）',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone320,
      textScale: 1.3,
      lang: AppLanguage.en,
    );

    final RenderParagraph para =
        tester.renderObject<RenderParagraph>(_balanceTextFinder);
    final double rowHeight = tester.getSize(_balanceLineFinder).height;
    final double oneLineHeight = para.size.height / 2; // para 可能已是 2 行

    expect(rowHeight, lessThanOrEqualTo(oneLineHeight * 2 * 1.15),
        reason: '行高 ${rowHeight.toStringAsFixed(1)}pt 超过两行上限 —— '
            '文案折行数超出 maxLines: 2 的允许范围');
    expect(tester.takeException(), isNull);
  });

  testWidgets('④ 430×932 + en（玄参截图机型）：单行保障（字符预算 + 宽档结构）',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone430,
      textScale: 1.0,
      lang: AppLanguage.en,
    );

    expect(tester.widget<Text>(_balanceTextFinder).data, contains('Sunlight'),
        reason: '防假绿：必须真的在 en 下');

    // 宽档结构锚：430 宽档按钮不退化（文字在场），宽度全部留给文案。
    expect(find.text(en.profile_source_label), findsOneWidget,
        reason: '430 宽 + en 属宽档，「阳光来源」不得退化成纯图标');

    // 🔴 不得用测试字体断「行数」：FlutterTest 字体每个拉丁字形 ≈ 1em（18pt），
    // 'Sunlight: 9,999' 自然宽 ≈ 306pt > 测试环境可用宽 ⇒ 测试里**必然**折
    // 2 行（实测行高 52pt）；而真机 Roboto/SF 拉丁均宽 ≈ 0.5em ⇒ 同串 ≈ 162pt
    // < 可用 ≈ 175pt ⇒ **单行**（玄参 430 截图实证）。这是 F141「别信测试字体
    // 行数」教训的镜像：真机行数只能用**字符预算**守（见下方断言）。
    final double rowHeight = tester.getSize(_balanceLineFinder).height;
    expect(rowHeight, lessThanOrEqualTo(26 * 2 * 1.15),
        reason: '行高 ${rowHeight.toStringAsFixed(1)}pt —— 测试字体下折 2 行属'
            '预期（真机单行）；此断言只防「3 行」级的排版回归');

    // 字符预算（真机单行的守卫）：430 宽档可用文案宽 ≈ 366 − 64(头像) −
    // 12(间距) − 93(en 按钮「History」+图标，真机 Roboto) − 22(图标块 18+4)
    // ≈ 175pt；拉丁均宽 ≈ 0.5em = 9pt/char ⇒ 预算 19 字符。ARB 文案加长即红
    // —— 那正是「真机会折行」的先兆，改文案前先核对真机不折行。
    expect(en.profile_balance_line(9999).length, lessThanOrEqualTo(19),
        reason: 'en 余额文案超出真机单行字符预算（430 宽 ≈ 175pt ≈ 19 字符），'
            '加长会导致真机折行（玄参核心场景回归）');
  });

  testWidgets('⑤ 430×932 + zh：文案逐字节、单行、窄档不触发（按钮仍带文字）',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone430,
      textScale: 1.0,
      lang: AppLanguage.zh,
    );

    expect(tester.widget<Text>(_balanceTextFinder).data, startsWith('我的阳光'),
        reason: '中文宿主必须渲染中文文案');
    expect(tester.takeException(), isNull);

    // 零像素回归锚：zh + 430 下「来源」按钮必须还是带文字的宽档形态。
    expect(find.text(zh.profile_source_label), findsOneWidget,
        reason: '430 宽 + zh 属宽档，「阳光来源」不得退化成纯图标');

    final RenderParagraph para =
        tester.renderObject<RenderParagraph>(_balanceTextFinder);
    expect(para.size.height, lessThanOrEqualTo(26),
        reason: 'zh + 430 必须单行');
  });

  testWidgets('⑥ 结构：无 FittedBox、文案无 ☀、maxLines 2、字号恒 18、图标 18×uiScale、间距 4',
      (WidgetTester tester) async {
    await _pumpProfile(
      tester,
      size: _kPhone430,
      textScale: 1.0,
      lang: AppLanguage.en,
    );

    // 🔴 v2 核心：整行**不得存在任何缩放容器**（首版 FittedBox 曾把极端档
    // 缩到 4.5% ⇒ 余额不可读；此断言防后人把缩放兜底加回来）。
    expect(
      find.ancestor(of: _balanceLineFinder, matching: find.byType(FittedBox)),
      findsNothing,
      reason: '阳光行内禁 FittedBox：缩放变换 = 把无障碍字号一起缩掉（v1 教训）');

    final Text text = tester.widget<Text>(_balanceTextFinder);
    expect(text.data, isNot(contains('☀')),
        reason: '☀ 必须从文案里拿掉（emoji 在文案里无法被 ellipsis 优雅处理）');
    expect(text.maxLines, 2, reason: 'v2：允许最多 2 行（装不下折行，不缩放）');
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.style?.fontSize, _kBalanceFontSize,
        reason: '🔴 禁缩字号：18pt 是孩子端无障碍口径');

    final Finder icon = find.descendant(
      of: _balanceLineFinder,
      matching: find.byType(Image),
    );
    expect(icon, findsOneWidget, reason: '阳光行必须有且只有 1 枚图标');

    final double uiScale = uiScaleOf(tester.element(_balanceTextFinder));
    expect(uiScale, closeTo(1.0, 0.001), reason: '430 宽手机 uiScale = 1.0');
    expect(tester.getSize(icon),
        Size(_kBalanceIconSize * uiScale, _kBalanceIconSize * uiScale),
        reason: '图标是「只随屏幕变大」的绝对尺寸 ⇒ 必须乘 uiScaleOf');

    final Iterable<SizedBox> gaps = tester
        .widgetList<SizedBox>(find.descendant(
          of: _balanceLineFinder,
          matching: find.byType(SizedBox),
        ))
        .where((SizedBox b) => b.width == _kBalanceIconGap);
    expect(gaps, isNotEmpty, reason: '文案与图标之间必须有 4pt 固定间距');
  });

  testWidgets('⑦ zh 变更本身不新增宽度：新固定块（4+18）≤ 旧尾缀「 ☀」实测宽',
      (WidgetTester tester) async {
    // 最坏字体口径：测试字体（FlutterTest）每个字形恒占 1em ⇒ 空格与 emoji
    // 都按 18pt 宽松计算，是**比真机 Roboto/SF 更宽**的上界。
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 旧形态：尾缀「 ☀」含在同一个 `Text` 里（连前置空格一起量）。
              Text(' ☀',
                  key: ValueKey<String>('legacy_suffix'),
                  style: TextStyle(
                      fontSize: _kBalanceFontSize, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    ));

    final double legacySuffix =
        tester.getSize(find.byKey(const ValueKey<String>('legacy_suffix'))).width;
    const double newBlock = _kBalanceIconGap + _kBalanceIconSize;

    expect(newBlock, lessThanOrEqualTo(legacySuffix),
        reason: '中文模式这一行只会**变窄**：旧尾缀「 ☀」在 18pt × 1.3 下实测 '
            '${legacySuffix.toStringAsFixed(1)}pt，新固定块 $newBlock pt');

    // 顺带锁住 ARB 值本身（去掉 ☀ 后句法仍通顺、数字仍在）。
    expect(zh.profile_balance_line(1234), isNot(contains('☀')));
    expect(zh.profile_balance_line(1234), contains('1234'));
    expect(en.profile_balance_line(1234), isNot(contains('☀')));
    expect(en.profile_balance_line(1234), contains('1234'));
    expect(en.profile_balance_line(1234), startsWith('Sunlight'));
  });

  testWidgets('⑧ 窄档按钮退化：320+en+1.3 只剩图标；430 图标与文字都在',
      (WidgetTester tester) async {
    // 窄档：纯 IconButton（tooltip 承载语义），文字标签消失。
    await _pumpProfile(
      tester,
      size: _kPhone320,
      textScale: 1.3,
      lang: AppLanguage.en,
    );
    expect(find.byIcon(Icons.receipt_long), findsOneWidget,
        reason: '窄档下「阳光来源」入口必须仍在（图标形态）');
    expect(find.text(en.profile_source_label), findsNothing,
        reason: '窄档下不得再渲染文字标签（那是抢宽度的元凶）');

    // 宽档：图标 + 文字都在。
    await _pumpProfile(
      tester,
      size: _kPhone430,
      textScale: 1.0,
      lang: AppLanguage.zh,
    );
    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    expect(find.text(zh.profile_source_label), findsOneWidget,
        reason: '宽档下文字标签必须在场（零像素回归锚）');
  });
}
