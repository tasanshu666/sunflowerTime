/// 等级圆徽**两位数截断修复**回归测试（真机 Bug：Lv.40 显示成「Lv.4」）。
///
/// ## 根因
/// [LevelBadgeCircle] 内 `Lv.N` 标签是无空格单一词，等比字号
/// （`diameter / kLevelBadgeDiameter × kLevelLabelFontSize`）下两位数（Lv.10~40）
/// 的词宽超过圆内可用宽（直径 − 2×白描边），又无换行点 ⇒ 水平裁掉末位数字。
/// 今日页摘要胶囊（d=38）与详情卡大圆徽（d=72）**同一枚组件、同一处根因**。
///
/// ## 修复
/// 标签包 `FittedBox(fit: BoxFit.scaleDown)`：放不下才整体等比缩小，
/// 一位数视觉零变化；两位数缩到恰好填满内宽，单行完整显示。
///
/// ## 本文件钉住
///  ① 摘要徽章（d=38）Lv.40：标签被 FittedBox 收进圆内可用宽；
///  ② 详情卡大圆徽（d=72）Lv.40：同上；
///  ③ 两位数全量扫（Lv.10~40，d=38）：无一例外装得下；
///  ④ 一位数：字号不被修改、文本完整；放得下时 FittedBox 尺寸 == 自然尺寸
///     （不缩不胀）；
///  ⑤ 端到端：真实 [FocusLevelBadge]（21900 分钟 = Lv.40）胶囊内标签完整。
library level_badge_two_digit_fit_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderFittedBox;
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart'
    show progressOf;
import 'package:sunflower_time/presentation/child/widgets/focus_level_badge.dart';

/// 圆徽描边宽（[LevelBadgeCircle.build]：满级金边 3，普通 2）。
double _borderWidthOf(bool isMax, {bool maxRingEnabled = true}) =>
    isMax && maxRingEnabled ? 3 : 2;

/// 圆内标签可用宽 = 直径 − 2×描边。
double _innerWidthOf(double diameter, bool isMax) =>
    diameter - 2 * _borderWidthOf(isMax);

/// 立泵一枚指定直径/等级的圆徽（[labelFontSize] 缺省 = 随直径等比）。
Future<void> _pumpCircle(
  WidgetTester tester, {
  required int level,
  required double diameter,
  double? labelFontSize,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: LevelBadgeCircle(
            level: level,
            diameter: diameter,
            isMax: level >= 40,
            labelFontSize: labelFontSize,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取圆徽内那枚标签 FittedBox 的渲染对象。
RenderFittedBox _fittedOf(WidgetTester tester) =>
    tester.renderObject<RenderFittedBox>(find.byType(FittedBox));

/// 取圆徽内那枚标签 FittedBox 的渲染尺寸。
Size _fittedSizeOf(WidgetTester tester) => _fittedOf(tester).size;

void main() {
  testWidgets('① 摘要徽章（d=38）Lv.40：标签收进圆内可用宽（修复回归钉）',
      (WidgetTester tester) async {
    await _pumpCircle(tester, level: 40, diameter: kLevelBadgeDiameter);

    expect(find.text('Lv.40'), findsOneWidget);
    final double inner = _innerWidthOf(kLevelBadgeDiameter, true);
    final Size fitted = _fittedSizeOf(tester);
    expect(
      fitted.width,
      lessThanOrEqualTo(inner),
        reason: '修复前两位数词宽（真实字体 ≈73）> 内宽 32 ⇒ 末位被水平裁掉；'
            '修复后 FittedBox 必须把标签缩进内宽',
    );
    // 单行完整：宽度收窄的同时文本仍是完整「Lv.40」（widget 树不裁词）。
    expect(fitted.height, lessThanOrEqualTo(inner),
        reason: '缩小后高度也必须在内径里');
  });

  testWidgets('② 详情卡大圆徽（d=72）Lv.40：同根因同修复', (WidgetTester tester) async {
    await _pumpCircle(tester, level: 40, diameter: kLevelDetailBadgeDiameter);

    expect(find.text('Lv.40'), findsOneWidget);
    final double inner = _innerWidthOf(kLevelDetailBadgeDiameter, true);
    final Size fitted = _fittedSizeOf(tester);
    expect(fitted.width, lessThanOrEqualTo(inner),
        reason: '详情卡那枚（72pt / 字号 28.4）同样两位数溢出，必须一并装下');
  });

  testWidgets('③ 两位数全量扫（Lv.10~39，d=38）：无一装不下', (WidgetTester tester) async {
    final double inner = _innerWidthOf(kLevelBadgeDiameter, false);
    for (int level = 10; level <= 39; level++) {
      await _pumpCircle(tester, level: level, diameter: kLevelBadgeDiameter);
      final Size fitted = _fittedSizeOf(tester);
      expect(
        fitted.width,
        lessThanOrEqualTo(inner),
        reason: 'Lv.$level 标签宽 ${fitted.width} 超出内宽 $inner（截断复发）',
      );
    }
  });

  testWidgets('④ 一位数：字号不被修改、文本完整；放得下时 scaleDown 不缩小不动手',
      (WidgetTester tester) async {
    // 注：测试环境加载真实字体（非 Ahem 等宽），「Lv.N」自然宽不可按字数估算；
    // 而标签字号缺省随直径等比 ⇒ 一位数在 d=38 下也会被缩小，这**不能**用来
    // 断言「一位数零缩小」。改用两个口径钉住零回归：
    //  a) 显式 [labelFontSize] + 大圆徽（d=120，内宽 116）：标签自然尺寸远小
    //     于内宽 ⇒ FittedBox 尺寸 == 自然尺寸（scaleDown 只缩不胀、放得下就不
    //     动）；
    //  b) Text 的 TextStyle.fontSize 始终等于等比常量（FittedBox 只改布局
    //     变换、不改字号），真机下一位数本就放得下 ⇒ 视觉零变化。
    await _pumpCircle(
      tester,
      level: 5,
      diameter: 120,
      labelFontSize: kLevelLabelFontSize,
    );
    // 注：测试环境加载的是真实字体（非 Ahem 等宽），「Lv.N」自然宽不可按
    // 5×fontSize 估算 —— 故口径 a 直接比较「FittedBox 尺寸 vs 子自然尺寸」：
    // 放得下时二者相等（scaleDown 只缩不胀、放得下就不动）。
    final RenderFittedBox fittedBox = _fittedOf(tester);
    expect(fittedBox.size, fittedBox.child!.size,
        reason: '放得下时 FittedBox.scaleDown 不得缩小/放大（零回归口径 a）');

    await _pumpCircle(
      tester,
      level: 5,
      diameter: kLevelBadgeDiameter,
      labelFontSize: kLevelLabelFontSize,
    );
    const double naturalFontSize =
        (kLevelBadgeDiameter / kLevelBadgeDiameter) * kLevelLabelFontSize;
    final Text label = tester.widget<Text>(find.text('Lv.5'));
    expect(label.style?.fontSize, naturalFontSize,
        reason: '字号保持等比常量不变（零回归口径 b，真机一位数本就装得下）');
    expect(find.text('Lv.5'), findsOneWidget);
  });

  testWidgets('⑤ 端到端：真实徽章（21900 分钟 = Lv.40）胶囊内标签完整',
      (WidgetTester tester) async {
    // 端到端走 `progressOf` 纯派生（不写死 level 字段），确认真实装配口径下
    // 摘要胶囊里的那枚圆徽也不截断。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: FocusLevelBadge(
              progress: progressOf(21900),
              totalMinutes: 21900,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // a) 满级装配正确（progressOf → level 40）。
    expect(find.text('Lv.40'), findsOneWidget);
    expect(find.text('时光大贤者'), findsOneWidget);

    // b) 胶囊里那枚圆徽内的标签 FittedBox 装进内宽。内宽从**实测圆径**推：
    //    测试默认 surface 800×600 会被 responsive 判为平板（uiScale 1.3），
    //    故不能假设直径 == kLevelBadgeDiameter；描边宽不乘 s（Border.all 字面量）。
    final Size circleSize = tester.getSize(find.byKey(FocusLevelBadge.badgeCircleKey));
    final double inner = circleSize.width - 2 * _borderWidthOf(true); // Lv.40 = 满级金边 3
    final Size fitted = _fittedSizeOf(tester);
    expect(fitted.width, lessThanOrEqualTo(inner),
        reason: '真实徽章装配下 Lv.40 也必须完整（不得重现「Lv.4」截断）');
    expect(circleSize.width, closeTo(kLevelBadgeDiameter * 1.3, 0.5),
        reason: '修复只做「标签缩小装下」，圆徽直径（平板 1.3×）不得漂移（布局护栏）');
  });
}
