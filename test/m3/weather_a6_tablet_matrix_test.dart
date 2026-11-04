/// 天气系统 A6 期 · **天气薄行 × 9 日型 × 平板两档 × 中英** 溢出与几何矩阵。
///
/// ## 为什么需要这份文件（A6 盘点结论）
/// A3 收口时只给平板补了「M-G 一档」，且 **pump 的日型永远是 `drought`**
/// （`weather_a2_test.dart:2008` 写死 `const WeatherKind kind = WeatherKind.drought;`）。
/// 于是 9 种日型里另外 8 种**从没在平板视口出现过**，英文档更是零覆盖。
///
/// 每个日型的内容长度都不同，溢出来源也不同：
///  · 天气名：`晴` 1 字 vs `多云` 2 字（en：`Sunny` vs `Heavy rain`）；
///  · 提示语：`· 浇水`（干旱/暴雨，2 字）vs `· 浇浇水，晒晒太阳`（晴，8 字）；
///  · **大风 / 极寒没有提示语**（`weatherHintOf` 返回 `null`，`:373-374`）
///    ⇒ 这两档的胶囊结构与其余 7 档不同，是独立的结构分支；
///  · 道具名：`遮阳棚` / `遮雨棚` / `挡风板` / `保温棚` 四者等长，
///    但 en 分别是 `Sun shade` / `Rain cover` / `Windbreak` / `Warm cover`，长度差 3 字符。
///
/// 所以「9 日型各一条」不是凑数：它是把**结构不同的分支**（有无提示语、有无按钮、
/// 4 种道具名）逐个放进同一个几何约束下压一遍。红了用例名直接告诉你是哪个日型。
///
/// ## 口径纪律（A2/A3 期反复踩过的坑，这里一条都不许犯）
///  · 🔴 **不断言「某宽度 = 某档位」**：`flutter_test` 的测试字体是方块字体
///    （每字形 advance == 字号），与真机字体差 18pt，「宽度→档位」在本环境不成立。
///  · 🔴 **倍率一律从真实 `context` 取 `uiScaleOf`**，不写死 1.3 / 1.56；
///    期望值里的 28 / 32 / 44 / 20 是**规格常量**（写死），与实现取值不同源。
///  · 🔴 `ellipsis` 不抛异常 ⇒ 判「半截」必须查 `didExceedMaxLines`，不能查异常。
///  · 🔴 只验不变式，不碰 K27 的 `12(s−1)` 已登记差异。
library weather_a6_tablet_matrix_test;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/presentation/child/widgets/weather_status_bar.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 平板两档视口（逻辑像素）。
///
///  · `834×1112` = iPad Air 11″，短边 834 ⇒ 1.3 档；
///  · `1032×1376` = iPad Pro 13″，短边 1032 ⇒ 1.56 档（派工书口语里的「1.6 档」）。
///
/// ⚠️ 倍率本身**不由本表决定**：用例里从 `uiScaleOf(context)` 取真量。
const List<List<double>> _kViewports = <List<double>>[
  <double>[834, 1112],
  <double>[1032, 1376],
];

/// 天气行左右内距（与真页面 `kWeatherRowInset` 同口径）——可用宽 = 视口宽 − 2×12。
const double _kRowInset = 12;

/// 天气行宿主：与 `garden_page.dart` 的结构同源（左右各 12 内距 + 满宽）。
Widget _host({
  required WeatherKind kind,
  required double availableWidth,
}) {
  return MaterialApp(
    home: L10nScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: availableWidth,
            child: GardenWeatherRow(
              key: kWeatherRowKey,
              kind: kind,
              shelterRefType: kind.shelterRefType,
              bought: false,
              affordable: true,
              showShelterButton: true,
              onShelterTap: () {},
              onPillTap: null,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 天气行内**所有**文本段落（`Text` 渲染为 `RichText` → `RenderParagraph`）。
List<RenderParagraph> _paragraphs(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byKey(kWeatherRowKey),
        matching: find.byType(RichText),
      ),
    )
    .toList();

/// 天气行内**每一个** `FittedBox`：子内容的真实尺寸有没有超出它拿到的盒尺寸。
///
/// 返回**违反项**的描述（空列表 = 全部装得下），每项形如
/// `"阳光明媚" 自然 26.5×13.0 vs 配额 10.6×5.2`。
///
/// ## 为什么必须量这个（A6 自查结论，两次返工换来的）
/// 本行里除了提示语，每个文本都被 `SizedBox(width: 预算值) > FittedBox(scaleDown)`
/// 包着（`weather_status_bar.dart:810-818` / `:994-1004` / `:1010-1020`）。
/// `FittedBox` 的语义是「**装不下就等比缩小**」⇒
///  · 它**永远不会**触发 `didExceedMaxLines`（我原来那条「不许半截字」多断言
///    在结构上恒绿，已删除）；
///  · 它也**永远不会抛异常** ⇒ 预算算小了，孩子看到的是「字越来越小」而不是报错，
///    既有全部用例照样绿。这是本行最后一个**不抛异常的静默失败模式**。
///
/// ## 🔴 为什么不用 `getTransformTo(...).getMaxScaleOnAxis()`
/// 试过，**是错的**：`RenderFittedBox` 没有重写 `applyPaintTransform`，
/// 缩放是在 `paint` 里经 `pushTransform` 施加的 ⇒ 变换矩阵里**不含**这个缩放，
/// 量出来恒 1.000（我用 M-A6-10 把宽度预算砍到 0.4 倍，它照样报 1.000）。
/// 正确口径是比较两个**布局期真量**：`FittedBox.size`（配额）与
/// `FittedBox.child.size`（文本自然尺寸）。子内容 ≤ 配额 ⇒ 没有被迫缩字。
List<String> _fittedOverflows(WidgetTester tester) {
  final List<String> bad = <String>[];
  for (final RenderFittedBox b in tester.renderObjectList<RenderFittedBox>(
    find.descendant(
      of: find.byKey(kWeatherRowKey),
      matching: find.byType(FittedBox),
    ),
  )) {
    final RenderBox? child = b.child;
    if (child == null) continue;
    final double dw = child.size.width - b.size.width;
    final double dh = child.size.height - b.size.height;
    if (dw > 0.5 || dh > 0.5) {
      String label = '?';
      if (child is RenderParagraph) {
        label = child.text.toPlainText();
      } else {
        void visit(RenderObject o) {
          if (o is RenderParagraph) label = o.text.toPlainText();
          o.visitChildren(visit);
        }

        child.visitChildren(visit);
      }
      bad.add('"$label" 自然 ${child.size.width.toStringAsFixed(1)}×'
          '${child.size.height.toStringAsFixed(1)} vs 配额 '
          '${b.size.width.toStringAsFixed(1)}×${b.size.height.toStringAsFixed(1)}');
    }
  }
  return bad;
}

void main() {
  for (final List<double> vp in _kViewports) {
    group('平板 ${vp[0].toInt()}×${vp[1].toInt()}', () {
      for (final WeatherKind kind in WeatherKind.values) {
        for (final AppLanguage lang in <AppLanguage>[AppLanguage.zh, AppLanguage.en]) {
          final String langTag = lang == AppLanguage.en ? 'en' : 'zh';
          testWidgets(
            '${kind.name} / $langTag：无溢出，实体 28s / 槽 32s / 命中 44s，'
            '实体顶对齐槽顶，文本不得被静默缩字',
            (WidgetTester tester) async {
              // ── 视口 + 语言 ────────────────────────────────────────────────
              tester.view.physicalSize = Size(vp[0] * 3, vp[1] * 3);
              tester.view.devicePixelRatio = 3.0;
              addTearDown(tester.view.reset);
              AppLocaleController.init(lang);
              addTearDown(
                  () => AppLocaleController.init(AppLanguage.system));

              final double available = vp[0] - 2 * _kRowInset;
              await tester.pumpWidget(
                _host(kind: kind, availableWidth: available),
              );
              await tester.pump();

              // ── 前置：真的在平板倍率（否则本条量的是手机分支）─────────────
              final BuildContext ctx =
                  tester.element(find.byKey(kWeatherPillKey));
              final double s = uiScaleOf(ctx);
              expect(s, greaterThan(1.0),
                  reason: '前置：${vp[0].toInt()}×${vp[1].toInt()} 必须处于平板倍率');

              // ── ① 几何：每层 = 规格常量 × 真实倍率 ────────────────────────
              final Rect slot = tester.getRect(find.byKey(kWeatherPillSlotKey));
              final Rect entity = tester.getRect(find.byKey(kWeatherPillKey));
              final Rect pillHit = tester.getRect(find.byKey(kWeatherPillHitKey));

              expect(entity.height, closeTo(28 * s, 0.5),
                  reason: '胶囊实体高必须是 28×s（规格 28），实测 ${entity.height}，s=$s');
              expect(slot.height, closeTo(32 * s, 0.5),
                  reason: '胶囊槽高必须是 32×s（规格 32），实测 ${slot.height}，s=$s');
              expect(pillHit.height, closeTo(44 * s, 0.5),
                  reason: '命中容器高必须是 44×s（规格 44，A11y 下限），实测 ${pillHit.height}，s=$s');

              // 极端日（有按钮）时，道具按钮同样按 32s / 44s 两层给。
              if (kind.shelterRefType != null) {
                final Rect btnVisual =
                    tester.getRect(find.byKey(kShelterButtonVisualKey));
                final Rect btnHit =
                    tester.getRect(find.byKey(kShelterButtonHitKey));
                expect(btnVisual.height, closeTo(32 * s, 0.5),
                    reason: '道具按钮视觉高必须是 32×s，实测 ${btnVisual.height}');
                expect(btnHit.height, closeTo(44 * s, 0.5),
                    reason: '道具按钮命中高必须是 44×s，实测 ${btnHit.height}');
              }

              // ── ② 对齐：实体**顶对齐**槽顶（不是居中）──────────────────────
              expect(entity.top - slot.top, closeTo(0, 0.5),
                  reason: '胶囊实体必须顶对齐槽顶：entity.top=${entity.top} slot.top=${slot.top}');

              // ── ③ 文本没被静默缩字：每个 FittedBox 的子内容都装得下 ────────
              // 这是本行**唯一不抛异常**的失败模式（预算算小了 ⇒ 字越缩越小，
              // 既不红也不报错）。判据量是 `FittedBox.size` 与 `child.size`
              // 两个**布局期真量**；不用 `getTransformTo`（见 `_fittedOverflows` 注释）。
              final List<String> squeezed = _fittedOverflows(tester);
              expect(
                squeezed,
                isEmpty,
                reason: '以下文本装不进自己的宽度配额，被 FittedBox 静默缩小了'
                    '（详情见 `_fittedOverflows` 注释）',
              );

              // ── ④ 防假绿：行宽不得被压成 0 ────────────────────────────────
              expect(tester.getRect(find.byKey(kWeatherRowKey)).width,
                  greaterThan(0),
                  reason: '天气行宽度必须 > 0，否则上面的几何断言毫无意义');

              // ── ⑤ 渲染期零异常 ────────────────────────────────────────────
              expect(tester.takeException(), isNull,
                  reason: '${kind.name} / $langTag 在 '
                      '${vp[0].toInt()}×${vp[1].toInt()} 下不得有 RenderFlex overflow 等异常');
              // `_paragraphs` 只在这里用来证明「行里确实有文字」——
              // 半截字由 FittedBox 结构保证不可能（见 `_fittedOverflows` 注释）。
              expect(_paragraphs(tester), isNotEmpty,
                  reason: '天气行里必须有文本段落');
            },
          );
        }
      }
    });
  }
}
