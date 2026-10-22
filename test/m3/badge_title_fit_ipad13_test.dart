/// F144 · F 项：**iPad Pro 13″ 今日页称号胶囊英文不被截断** 守卫。
///
/// ## 背景（玄参 iPad 13″ 实测）
/// 胶囊里显示 `Title not u…` —— 未解锁占位文案（en 原值 `Title not unlocked yet`，
/// 22 字符）远超胶囊可容纳宽度；解锁后若英文称号也偏长，同样会被 ellipsis。
///
/// ## 修法（三件事一起）
///  ① `prd_level_locked_title` 的 **en 值缩短为 `Locked`**（zh 保持「尚未解锁称号」）；
///  ② 9 条英文称号统一收到 **≤ 12 字符**（`shared_title_lv*`，长度预算见
///     `test/i18n/title_l10n_test.dart`）；
///  ③ 称号行包 `FittedBox(fit: BoxFit.scaleDown)` —— **只许 scaleDown**，
///     胶囊宽度预算（`kLevelBadgeMaxWidth = 152`）**不动**（提宽要先证明不撞右下
///     阳光气泡，护栏 `today_badge_bounds_test.dart` 的「徽章 ∩ 气泡 = ∅」）。
///
/// ## 胶囊可用宽的账（全部来自 `prd_params.dart`，不猜数值）
/// `152 − 2×padH(10) − 圆徽(38) − gap(8) = **86pt**`（手机基准）；
/// iPad13 的 `uiScaleOf` = **1.6**（`tabletUiScaleFor(1032)` 钳到
/// `kTabletTextScaleMax`）⇒ 可用宽 **137.6pt**，字号 13 × textScaler 1.6 = 20.8pt。
///
/// ## 本文件锁四条（**不用** `find.text` 查存在，而是真实排版证据）
///  ① 未解锁 en 文案值 == `Locked`（防回退到 22 字符长句）；
///  ② 真实渲染：称号 `RenderParagraph.didExceedMaxLines == false`（**没有** ellipsis）；
///  ③ `FittedBox` 的实际缩放比 ∈ [0.52, 1.0] —— 即使测试字体（等宽 1em/字，
///     比真机 Roboto/SF 的英文**宽得多**）也最多缩到 52%，仍清晰可读。
///     下限 0.52 按 F144 玄参终审采纳的 `Focus Knight`（12 字符，测试字体实测
///     缩放 53.7%）校准；真机 SF ≈0.5em/char ≈ 125pt < 预算 137.6pt ⇒ 缩放比
///     ≈1.0 **完全不缩**。旧下限 0.55 是按 10 字符 `Sun Knight` 校准的设计值；
///  ④ 字号仍是 `kLevelTitleFontSize`（缩的是绘制变换，**不是**字号）—— 无障碍
///     大字号口径不被破坏。
library badge_title_fit_ipad13_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/title_l10n.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// iPad Pro 13″（M5）竖屏逻辑尺寸 —— 玄参实测机型（同 `tablet_scale_ipad13_test`）。
const Size _kIpad13 = Size(1032, 1376);

/// 胶囊**满额**可用文字宽（手机基准值；断言处再乘 uiScale）。
double get _kTitleBudgetBase =>
    kLevelBadgeMaxWidth -
    2 * kLevelBadgePadH -
    kLevelBadgeDiameter -
    kLevelBadgeGap;

/// 定位胶囊里那一行**称号** `Text`（按字号区分：圆徽的 `Lv.N` / 🌱 不是这个字号）。
Finder get _titleTextFinder => find.descendant(
      of: find.byKey(FocusLevelBadge.badgeKey),
      matching: find.byWidgetPredicate((Widget w) =>
          w is Text && w.style?.fontSize == kLevelTitleFontSize),
    );

/// 装配真实 `FocusLevelBadge`（en + iPad13 + 平板文字放大链）。
Future<void> _pumpBadge(WidgetTester tester, double totalMinutes) async {
  tester.view.physicalSize = _kIpad13 * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // 与 `app.dart` 同款注入壳：平板文字走 `textScaler`（钳到 1.6）。
      builder: (BuildContext context, Widget? child) {
        final Widget content = child ?? const SizedBox.shrink();
        final MediaQueryData mq = MediaQuery.of(context);
        final MediaQueryData scaled = applyTabletTextScaling(mq);
        if (identical(scaled, mq)) return content;
        return MediaQuery(data: scaled, child: content);
      },
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FocusLevelBadge(
            progress: progressOf(totalMinutes),
            totalMinutes: totalMinutes,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 称号行那一层 `FittedBox`（**祖先定位**：胶囊里还有圆徽的 `Lv.N` 也包了
/// `FittedBox(alignment: center)`，按 `byType` 会命中 2 个）。
Finder get _titleFittedFinder => find.ancestor(
      of: _titleTextFinder,
      matching: find.byType(FittedBox),
    );

/// `FittedBox` 的实际缩放比（= 盒宽 ÷ 子 `RenderParagraph` 的自然宽，上限 1.0）。
///
/// 口径依据：`RenderFittedBox` 以**无约束**条件布局子节点（`RenderParagraph.size`
/// 即文案自然宽），再对绘制施加缩放变换；自身 `size` = 子尺寸 × scale（`scaleDown`
/// 且超宽时）。因此两者相除就是真实绘制缩放比，不依赖测试字体的具体字宽。
double _fittedScale(WidgetTester tester) {
  final Finder fitted = _titleFittedFinder;
  expect(fitted, findsOneWidget,
      reason: '称号行必须**恰好**包在一层 FittedBox 里（多层会让缩放比不可读）');

  final FittedBox widget = tester.widget<FittedBox>(fitted);
  expect(widget.fit, BoxFit.scaleDown,
      reason: '只许 scaleDown（禁 contain：contain 会放大短文案并留白）');
  expect(widget.alignment, Alignment.centerLeft,
      reason: '只缩不放，必须左对齐（居中会让称号与圆徽错位）');

  final double boxWidth = tester.getSize(fitted).width;
  final double naturalWidth = tester.getSize(_titleTextFinder).width;
  expect(naturalWidth, greaterThan(0), reason: '称号文案自然宽必须为正');
  final double ratio = boxWidth / naturalWidth;
  return ratio > 1 ? 1 : ratio;
}

/// 断言单条称号文案在 iPad13 + en 下「不截断、最多缩到 52%、字号不缩」。
void _expectFits(WidgetTester tester, String expectedText, String label) {
  final Finder title = _titleTextFinder;
  expect(title, findsOneWidget, reason: '$label：胶囊里应有且只有一行称号文案');
  expect(tester.widget<Text>(title).data, expectedText);

  // ④ 字号仍是 kLevelTitleFontSize（缩的是绘制变换，不是字号）。
  expect(tester.widget<Text>(title).style?.fontSize, kLevelTitleFontSize,
      reason: '$label：不许通过改 fontSize 来「塞下」文案（无障碍大字号是用户设置）');

  // ② 没有 ellipsis（FittedBox 内 Text 走不换行裁切；换行/省略都会让该属性为 true）。
  final RenderParagraph para = tester.renderObject<RenderParagraph>(title);
  expect(para.didExceedMaxLines, isFalse,
      reason: '$label：「$expectedText」在 iPad13 + en 下不得被省略/折行');
  expect(para.maxLines, 1, reason: '$label：称号行恒为单行');

  // ③ 缩放比不低于 0.52（测试字体 1em/字 = 比真机更宽的最坏情况；
  //    下限按 12 字符的 `Focus Knight` 实测 53.7% 校准，防病态加长）。
  final double scale = _fittedScale(tester);
  expect(scale, greaterThanOrEqualTo(0.52),
      reason: '$label：FittedBox 缩到 ${(scale * 100).toStringAsFixed(1)}% '
          '（下限 52%，低于此说明文案过长需要再缩短）');
  expect(scale, lessThanOrEqualTo(1.0001));

  // ③' 缩放后**实际占用宽**必须落在胶囊预算内 —— 这才是「没被截断」的充分证据：
  //     否则 Text 可以在 FittedBox 里排得很宽、但整体被父级 clip 掉。
  final BuildContext ctx = tester.element(find.byKey(FocusLevelBadge.badgeKey));
  final double budget = _kTitleBudgetBase * uiScaleOf(ctx);
  final double painted = para.size.width * scale;
  expect(painted, lessThanOrEqualTo(budget + 0.5),
      reason: '$label：缩放后占宽 ${painted.toStringAsFixed(1)}pt 超出胶囊预算 '
          '${budget.toStringAsFixed(1)}pt');
}

void main() {
  final AppLocalizations en = AppLocalizationsEn();

  /// 平板 UI 倍率（iPad13 shortestSide = 1032 → 1.6，钳 `kTabletTextScaleMax`）。
  final double s = tabletUiScaleFor(_kIpad13.shortestSide);

  testWidgets('前提：iPad13 的 uiScale 与 textScaler 都是 1.6、称号预算 = 137.6pt',
      (WidgetTester tester) async {
    await _pumpBadge(tester, 30); // 30 分钟 → 未解锁态
    expect(s, 1.6, reason: 'iPad13(1032) 的 uiScale 应为 1.6（钳到上限）');

    final BuildContext ctx = tester.element(find.byType(FocusLevelBadge));
    expect(MediaQuery.textScalerOf(ctx).scale(1.0), closeTo(1.6, 0.001),
        reason: 'applyTabletTextScaling 在 1032 短边上应给出 textScaler 1.6');
    expect(uiScaleOf(ctx), closeTo(1.6, 0.001));
    expect(_kTitleBudgetBase * s, closeTo(137.6, 0.01),
        reason: '胶囊称号行满额可用宽 = (152−20−38−8) × 1.6');
  });

  testWidgets('① 未解锁占位文案（en `Locked`）：不截断、几乎不缩放',
      (WidgetTester tester) async {
    await _pumpBadge(tester, 30);

    expect(en.prd_level_locked_title, 'Locked',
        reason: 'F144：en 未解锁占位文案缩到 Locked（原 22 字符会显示 Title not u…）');
    _expectFits(tester, 'Locked', '未解锁占位');
  });

  for (final int node in kFocusLevelTitleLevels) {
    testWidgets('② Lv.$node 英文称号「${focusLevelTitleRowL10n(node, en)}」不截断',
        (WidgetTester tester) async {
      // 累计分钟刚好踩到该节点门槛 → progress.level == node（当前称号 = 该节点）。
      final double minutes = thresholdMinutesOfLevel(node).toDouble();
      await _pumpBadge(tester, minutes);
      _expectFits(
        tester,
        focusLevelTitleRowL10n(node, en),
        'Lv.$node',
      );
    });
  }

  testWidgets('③ 胶囊宽度仍在 kLevelBadgeMaxWidth × 1.6 预算内（未提宽）',
      (WidgetTester tester) async {
    await _pumpBadge(tester, thresholdMinutesOfLevel(15).toDouble());
    final Rect badge = tester.getRect(find.byKey(FocusLevelBadge.badgeKey));
    expect(badge.width, lessThanOrEqualTo(kLevelBadgeMaxWidth * s + 0.5),
        reason: 'F144 不改宽度预算（提宽要先证明不撞右下阳光气泡）');
    // 高度不受 FittedBox 影响（缩放是绘制变换，不吃布局高度）。
    expect(badge.height, lessThan(50 * s),
        reason: 'FittedBox 不得撑高胶囊（仍 ≈44×s）');
  });
}
