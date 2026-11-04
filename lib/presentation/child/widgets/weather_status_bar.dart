/// 花园页顶部「天气行」表现层（A2 · 天气系统二期）。
///
/// ## 一行里有什么
/// ```text
///  [🛡 遮阳棚 10 ☀]  [🌵 干旱 · 浇水]        ← 极端日（按钮在左，胶囊贴右）
///                    [☀ 阳光明媚 · 浇浇水，晒晒太阳]  ← 温和日（整条道具区不渲染）
/// ```
///
/// ## 为什么单独一个文件（三条理由，见设计文档 Q5）
///  · `garden_page.dart` 已 4100+ 行，再塞 400 行会让它逼近 4500 行；
///  · 压缩阶梯与三态样式必须能在**不装配 Riverpod / 数据库**的前提下被 widget 测试
///    直接渲染（与 `GardenHelpSheet` / `ChildConfirmCard` 同模式）；
///  · A5 换真美术时只改本文件，不动被源码守卫正则盯着的页面文件。
///
/// ## 顺序（对 PRD 示意图的 1 处微调，主理人已裁定 M1）
/// 内部顺序 = `[按钮][胶囊]`，胶囊贴右不动。理由：胶囊是**恒在元素**（9 种日型都
/// 渲染、`_loading == true` 的首帧就要在），它的位置必须绝对稳定；按钮是**条件元素**
/// （极端日才有、且要等账本读完才出现），按钮出现时只能「向左生长」，绝不推动胶囊。
///
/// ## 三个高度是三个不同的量（🔴 本批最容易被改坏的地方）
/// | 量 | 常量 | 含义 |
/// |---|---|---|
/// | 视觉带 | [kWeatherRowHeight] = 32 | **遮挡带**：跨零点切天气时顶部不许跳动 |
/// | 视觉件 | 胶囊实体 [kWeatherPillHeight] = 28（**顶对齐** 32 槽顶）/ 按钮 [kShelterButtonHeight] = 32 | 见下 |
/// | 命中容器 | [kWeatherHitHeight] = 44 | 真实可点区 |
///
/// 🔴 **胶囊是两层**（PRD v1.7 定稿 D-8 现行 / D-11 / D-12 准则 ②③）：
///  · **槽** [kWeatherPillSlotKey] = 32（**完全透明**）⇒ 「视觉带恒 32」由它保证；
///  · **实体** [kWeatherPillKey] = 28（白底 / radius 20 / elevation 2，**逐字复用**
///    既有 `_SeedCountChip`）⇒ 与 chips 同族；**顶对齐槽顶（槽底留 4pt 透明）**。
/// 实体矮 4pt 是 D-12 准则 ①「可点性优先于视觉对称」的**有意结果**（行内只能有
/// 一个「明显可按」的元素）。
/// ⚠️ **槽高 == 32 ≠ 实体高 == 28**：这两件事在 PRD v1.2~v1.8 之间来回过**四轮**
///    （28→32→28→32→28），根因是**只测了槽**。⇒ 实体必须有**独立断言**（A2-8⑧）。
///    🔴 **实体 key 与槽 key 不得同值 / 互为别名**（否则 A2-8⑧ 与 A2-2 恒红）。
///
/// 视觉带 32 **恒定**，与「今天有没有按钮」无关 ⇒ 温和日与极端日逐位相等。
/// 命中容器 44 **不破** 32 的视觉预算：本行是根 Stack 的 `Positioned` 浮层，
/// `Positioned` 不参与父级布局 ⇒ 对 `gardenGridVisibleHeight` 的影响**恒为 0**。
///
/// ## 🔴 触控热区（A2-10 · 真尺寸，不是「声明尺寸」）
/// Flutter 的 `RenderBox.hitTest` 首行即 `if (!size.contains(position)) return false;`
/// —— 若外层行容器只有 32 高，子树里「声明 44」的那层在**真实点击**里根本收不到事件
/// （点在 32~44 区间被行容器拒掉），而 `getSize` 却能量到 44 ⇒ **测试假绿、孩子按边缘
/// 没反应**。因此本行的**容器本身是 44pt**，视觉件在其中居中；竖直方向的 6+6
/// 透明留白由 `Padding` + `HitTestBehavior.opaque` 兑现为**真命中**。
///
/// 🔴 **禁止** `ConstrainedBox(minHeight:44) + OverflowBox` 这类「声明 44」的写法，
/// 也**禁止** `MaterialTapTargetSize.shrinkWrap`（会吃掉默认 8pt 外扩）。
///
/// ## 宽度预算与压缩阶梯（PRD v1.8 §5.3.2 + 设计文档 §3.2）
/// ```text
/// 档 ① full            天气名 + 道具名 + 价格 + 提示语 全在
/// 档 ② hintTruncated   提示语被逐字截断（唯一的 ellipsis 位），两个名字都完整
/// 档 ③ noHint          提示语整句消失，两个名字都完整
/// 档 ④ noShelterName   按钮降级为「道具图标 + 价格」（道具名整个不在树里）
/// 档 ⑤ noWeatherName   胶囊降级为「纯天气图标」（天气名整个不在树里）
/// 兜底                 连最省形态都放不下 ⇒ 外层 `FittedBox(scaleDown)` 等比缩整行
/// ```
/// 🔴 **硬规则**：天气图标 / 道具图标 / 价格「10 ☀」**任何宽度下都必留**；
/// 名字**要么完整出现、要么整体消失**（绝不出现「遮阳…」这种残字 —— 5~9 岁孩子
/// 不认字，残字反而干扰识别）；提示语是**唯一**允许出现 `…` 的元素。
/// 档位由**纯函数** [resolveWeatherRowTier] 决定（零 widget / 零 context 依赖 ⇒ 可在
/// 纯 Dart 单测里穷举边界）；名字 `Text` **永远不带 `overflow: ellipsis`**。
///
/// 🔴 **宽度结论只在指定字体口径下成立**（PRD D-14 / W-2 / W-3）：
/// `flutter_test` 用**方块字体**（每个字形 advance = 字号）⇒ `10 ☀` 在测试里量得
/// **48pt**、真机约 **30pt**（按钮完整态 121 vs 103）。落档差异**来自字体，不是实现
/// 的 bug** ⇒ **不许改 `_fitTier`、不许动视觉度量去迁就测试字体**（W-1）。
library weather_status_bar;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/gold_notice_dialog.dart'
    show GoldNoticeStyle;
import 'package:sunflower_time/shared/responsive.dart' show uiScaleOf;

// ── 稳定 Key（widget 测试按 Key 定位，**必须与 QA 用例逐字一致**）──────────────
// 🔴 v1.3 改名：`shelter_button_visual` → **`shelter_visual`**（PRD v1.4 §7.2 逐字）。

/// 天气行**容器**的稳定 Key（高 44 = 命中容器；A2-8⑥ 量它的 `globalTop`）。
const Key kWeatherRowKey = ValueKey<String>('weather_row');

/// 道具按钮的**命中盒**（44 高）。A2-10① 测它（PRD 逐字：`'shelter_button'`）；
/// A2-10⑥ 用它做真实点击探针。
const Key kShelterButtonHitKey = ValueKey<String>('shelter_button');

/// 道具按钮命中盒的**别名**（历史命名，保留是为了让老断言不必改 key 名）。
const Key kShelterBuyButtonKey = kShelterButtonHitKey;

/// 道具按钮的**视觉件**（32 高）。A2-8③ / A2-8⑥ / A2-10②⑤ 测它；三态都存在。
const Key kShelterButtonVisualKey = ValueKey<String>('shelter_visual');

/// 天气胶囊的**命中盒**（44 高）。P0 不可点故 A2-10 不强制，但结构已就位。
const Key kWeatherPillHitKey = ValueKey<String>('weather_pill_hit');

/// 天气胶囊的**视觉槽**（32 高，`SizedBox(height: 32*u)`，**完全透明**）。
///
/// A2-8③ 测它（9 种日型都 == 32u，逐点相等）。
/// 🔴 **A2-8⑦：槽本身必须完全透明** —— 无底色 / 无阴影 / 无边框。
///    槽只是**度量与占位容器**，视觉全部由槽内的实体绘制；槽若带白底会变成「药丸里嵌药丸」。
/// ⚠️ **槽高 == 32 不等于实体高 == 28**（PRD D-11）—— 实体由 [kWeatherPillKey] 单独断言。
const Key kWeatherPillSlotKey = ValueKey<String>('weather_pill_slot');

/// 天气胶囊**实体**（28 高，`Material`，白底 0.88 / radius 20 / elevation 2）。
///
/// A2-2 的「首帧可见」用 `find.byKey(kWeatherPillKey)` 命中。
/// 🔴 **A2-8⑧：实体高度必须被单独断言**（`size.height == 28 × uiScaleOf ± ε`）——
///    这是**唯一**能测出「实体被改成 32」的断言：32 实体装进 32 槽时，槽高与按钮高
///    照样是 32、A2-8③ 会全绿放行（PRD D-11 的教训，见设计文档 §7-K16）。
/// 🔴 **不得与 [kWeatherPillSlotKey] 同值 / 互为别名**（否则 A2-8⑧ 与 A2-2 恒红）。
const Key kWeatherPillKey = ValueKey<String>('weather_pill');

// ── 尺寸常量（**数字元素**全部乘 uiScaleOf(context)；文字不乘，交给平板倍率）──

/// **天气胶囊实体**视觉高 = **28**（PRD **v1.7 定稿** §5.2 + D-8 现行 + D-12 准则 ②）。
///
/// 🔴 **本批最反复的一段历史，必须留痕（PRD D-11 / D-12 逐字）**：
///    实体高度在 **28 → 32 → 28 → 32 → 28** 之间来回过**四轮**。根因是**只测了槽**：
///    28 实体装进 32 槽时**槽高照样是 32、按钮高照样是 32、A2-8③ 会全绿放行**，
///    但胶囊比按钮矮 4pt（层级表达与「同族」取舍随之变化）⇒ 实体必须有独立断言。
/// ✅ **v1.7 定稿 = 实体 28**（与既有资源 chips **逐字同款**：28 高 / radius 20 /
///    白底 0.88 / elevation 2），**顶对齐 32 高的透明槽顶**（槽底留 4pt 透明）。
/// ⚠️ 若产品将来改高度：**只需改这一个常量 + A2-8⑧ 的期望值**（结构不变）。
const double kWeatherPillHeight = 28;

/// **胶囊槽**高 = **32**（透明度量容器，实体**顶对齐**槽顶 ⇒ 槽底留 4pt 透明）。
const double kWeatherPillSlotHeight = 32;

/// 道具按钮视觉高（32）。
const double kShelterButtonHeight = 32;

/// **视觉带高 = 天气行的「垂直占用」**（PRD §5.0 高度预算表）。
///
/// 🔴 9 种日型**恒定** `max(槽 32, 按钮 32) = 32`，与「今天有没有按钮」无关：
///    温和日只有一个 32 槽、极端日是 32 槽 + 32 按钮并排 ⇒ 视觉带逐位相等
///    → 跨零点天气切换时顶部不跳动（A2-8③ 的 widget 断言就靠这一个常量成立）。
const double kWeatherRowHeight = 32;

/// **命中带高 = 44**（PRD §5.2.1 硬下限：热区 ≥44×44）。
///
/// 🔴 与 [kWeatherRowHeight] 的关系（本批最容易搞混的一对数字）：
///    · 32 = **视觉**占用（A2-8③ 测它，== 32 且 9 种日型逐点相等）；
///    · 44 = **命中**占用（A2-10① 测它，≥44×44）。
///    两者靠「透明 Padding 外扩」区分：命中盒 = 32 视觉 + 上下各 6 = 44。
const double kWeatherHitHeight = 44;

/// 热区**垂直**向外扩展量（PRD §5.2.1 纪律 2 逐字：上下各 6）。**两个控件都用**。
const double kHitPadVertical = 6;

/// 热区**水平**扩展量：**只给天气胶囊用**（左 4 / 右 6 = 10）。
///
/// 🔴 为什么按钮不给水平扩展（设计文档 v1.3 钉死）：道具按钮最窄态（图标 14 + 价格 30
///    + 内边距 12 = 56）本来就 ≥44，再给 10pt 纯属浪费；而天气胶囊最窄态（图标 18 +
///    内边距 16 = 34）**差 10pt**，必须补。
const double kHitPadLeft = 4;

/// 热区水平外扩的右侧部分（见 [kHitPadLeft]）。
const double kHitPadRight = 6;

/// 天气胶囊命中盒的水平外扩总量（= 左 4 + 右 6 = 10）。
const double kWeatherPillHitPadH = kHitPadLeft + kHitPadRight;

/// 天气胶囊水平内边距（PRD v1.8 §5.2 逐字：`horizontal 8`）。
const double kWeatherPillPaddingH = 8.0;

/// 天气胶囊的**纵向**留白（PRD **v1.9 定稿** §5.2 逐字：`horizontal 8, vertical 6`）。
///
/// ✅ **PRD v1.9 已裁定（纵向留白规则）**：纵向等效留白 = `min(上限 6, (实体高 28 − 图标尺寸) / 2)`
///    · **上限 6**：几何上限取 PRD §5.2 写死的 `vertical 6`，**不许**突破；
///    · **当前等效 5**：本实现取**图标 18**（层级表达不许缩水；与 chips 逐字同款的是
///      **高 / radius / 色**，不是图标）⇒ (28 − 18) / 2 = **5**；
///    · **装得下才用**：[WeatherPill] 里按「内容盒装不装得下图标」判定，装得下才真的
///      加 6 的内距（若图标改回 16 ⇒ 16 + 6 + 6 = 28 恰好装满 ⇒ 留白自动变回 6，**结构不变**）；
///    · **图标不缩水**：任何情况下**不许**为了让内距凑到 6 而缩小图标；
///    · **内容不得溢出实体**：留白与图标二选一，不许同时出现导致溢出。
const double kWeatherPillPaddingV = 6.0;

/// 天气胶囊圆角 = **20**（PRD v1.7 定稿，**逐字复用** chips 的药丸圆角）。
///
/// 🔴 **留痕**：20 → 16 → 20 → 16 → **20**（往复四轮；与实体高联动：实体 28 ⇒ 20）。
const double kWeatherPillRadius = 20;

/// 天气胶囊图标边长 18（比 chips 的 16 大一档 ⇒「天气 > 资源」的信息层级）。
const double kWeatherPillIconSize = 18;

/// 道具按钮图标边长 14（**故意比天气图标小一档**；PRD 算式表里的「16」是笔误）。
const double kShelterIconSize = 14;

/// 行内小间距（图标 ↔ 名字 / 名字 ↔ 名字）。
const double kWeatherRowInnerGap = 4;

/// 名字 ↔ 价格 的间距（设计文档 §3.2 常量块逐字）。
const double kShelterNamePriceGap = 4;

/// 道具按钮的**水平内边距**（左右各 6 ⇒ 合计 12）。
///
/// 🔴 **留痕**：PRD §5.3 算式里的 padding **12** 就是它（左右各 6）。
///    按钮视觉件的宽度预算与渲染**必须**用同一个值，否则宽度会漂。
const double kShelterButtonPaddingH = 6;

/// 按钮与胶囊的间距（PRD §5.2「chips ↔ 天气组 ≥ 8pt」同值）。
const double kWeatherRowGap = 8;

/// 天气行距屏幕左右边距（与既有 chips / FAB / 木牌同锚点）。
const double kWeatherRowInset = 12;

/// 可点元素的**命中区硬下限**（A2-10 / PRD §5.2.1：孩子手指目标一律 ≥44×44）。
const double kMinTapTarget = 44;

/// 提示语被**整体丢弃**的阈值宽度（低于它就只剩「· …」，不如没有）。
///
/// PRD §5.3.2 阶梯第 ① 档是「逐字截断 → 整句消失」：本常量就是这两步的分界。
const double kWeatherHintMinWidth = 24;

/// 灰态（阳光不足）的不透明度（PRD §4.3「整体 40% 透明度」）。
const double kShelterDisabledOpacity = 0.4;

/// 已购态底色（浅绿，与「成功」语义同源；不新造主色）。
const Color kShelterBoughtBg = Color(0xFFDFF3D8);

/// 已购态前景色（深绿文字 / 图标）。
const Color kShelterBoughtFg = Color(0xFF2E7D32);

/// 胶囊与按钮的正文色（逐字复用 `_SeedCountChip` 的 `×N` 颜色，不加新色）。
const Color kWeatherTextColor = Color(0xFF6B6252);

/// 胶囊提示语的弱化色（同色系、透明度降低，避免新增色值）。
const Color kWeatherHintColor = Color(0xFF8A8172);

// ── 文本样式（测量与渲染**必须**用同一套，否则宽度预算会漂）────────────────

/// 环境 `DefaultTextStyle`（M3 `bodyMedium`）自带字距，渲染实际生效的字距。
///
/// 🔴 **FD1 根因与修复**：组件里所有 `Text` 都**未显式**设 `letterSpacing`，于是
///    继承 `DefaultTextStyle`（M3 material2021 的 `bodyMedium` 含 `letterSpacing: 0.25`）
///    ⇒ 实际渲染宽 = 测量宽 + 0.25 × 字数。而 [measureTextWidth] 用这些显式样式测量时
///    **不含**这 0.25 ⇒ 量得比渲的窄 ⇒ 满档提示语预算算「放得下」⇒ 选满档 ⇒ 实际渲
///    更宽 ⇒ Flexible 位不够 ⇒ ellipsis 吞 1 字（「· 浇…」）。
///    修复：测量与渲染**共用同一套样式**（这里显式带上等效字距），使「量」==「渲」。
const double kWeatherLetterSpacing = 0.25;

/// 天气名的样式（胶囊内）。
TextStyle weatherNameTextStyle() => const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.0,
      letterSpacing: kWeatherLetterSpacing,
      color: kWeatherTextColor,
    );

/// 提示语的样式（胶囊内；**唯一**允许 ellipsis 的元素）。
TextStyle weatherHintTextStyle() => const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.0,
      letterSpacing: kWeatherLetterSpacing,
      color: kWeatherHintColor,
    );

/// 道具名的样式（按钮内）。
TextStyle shelterNameTextStyle() => const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.0,
      letterSpacing: kWeatherLetterSpacing,
      color: Color(0xFF5D4200),
    );

/// 已购态标签的样式（按钮内；浅绿底上的深绿字）。
TextStyle shelterBoughtTextStyle() => const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.0,
      letterSpacing: kWeatherLetterSpacing,
      color: kShelterBoughtFg,
    );

/// 价格样式的通用骨架（前景色随状态变，故前景色由调用方传）。
TextStyle shelterPriceTextStyle(Color fg) => TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.0,
      letterSpacing: kWeatherLetterSpacing,
      color: fg,
    );

// ── 宽度测算 ─────────────────────────────────────────────────────────────────

/// 量一段文本的**固有宽度**（单行、不换行、不省略）。
///
/// `maxWidth` 传 `double.infinity` 即得 intrinsic 宽；`textScaler` 必须传
/// `MediaQuery.textScalerOf(context)`（平板放大后宽度会变，量错就会误判档位）。
///
/// 🔴 **这是唯一允许的测量方式**：不要用 `GlobalKey` + 延迟 `postFrameCallback` 量
///    已渲染的 `RenderBox`（那是 v1.0 被主理人砍掉的方案，`R4′`）。`TextPainter`
///    是同步的、可在 build 内调用、不产生第二帧。
///
/// 🔴 **口径提示**（PRD D-14）：`flutter_test` 用**方块字体**（每个字形 advance = 字号）
///    ⇒ `'10 ☀'` 在测试里量得 **48pt**、真机约 **30pt**。任何「宽度 → 档位」的结论
///    **只在指定字体口径下成立**（真机口径 or 测试口径），跨口径一律降级为不变式。
double measureTextWidth(String text, TextStyle style, TextScaler textScaler) {
  if (text.isEmpty) return 0;
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

// ── 单点映射（新增日型 / 道具时只改这里；`switch` 穷举、无 default）──────────

/// 日型 → Material 图标（**A2 占位；A5-b 才换真美术**）。
///
/// 🔴 **A5 改口径（2026-11-04）**：本注释原文写「换真美术时**组件 API 不变**」，
///    **不成立** —— 本函数返回 [IconData]，承载不了 PNG / WebP。真美术到位时的真实
///    改动是：**新增 `weatherArtOf(kind, size) -> Widget`**（内部 `Image.asset` +
///    `errorBuilder` 回退到本函数）+ 替换 `_WeatherPill` 内的 `Icon(weatherIconOf(..))`
///    调用点 + `pubspec.yaml` 声明 `assets/weather/` 叶子目录（目录**不递归**）。
///    本函数**保留为回退路径**，不删。
///
/// 9 个图标**两两语义可辨**：多云 = 实心云、阴天 = 线框云；小雨 = 稀疏雨点、
/// 暴雨 = 雷雨云；微风 = 气流、大风 = 风力装置。
IconData weatherIconOf(WeatherKind kind) => switch (kind) {
      WeatherKind.sunny => Icons.wb_sunny_rounded,
      WeatherKind.breeze => Icons.air_rounded,
      WeatherKind.cloudy => Icons.cloud_rounded,
      WeatherKind.overcast => Icons.cloud_queue_rounded,
      WeatherKind.lightRain => Icons.grain_rounded,
      WeatherKind.drought => Icons.landscape_rounded,
      WeatherKind.wind => Icons.wind_power_rounded,
      WeatherKind.cold => Icons.ac_unit_rounded,
      WeatherKind.rainstorm => Icons.thunderstorm_rounded,
    };

/// 日型 → 天气名（ARB 下划线 getter）。
///
/// 🔴 **不走** `WeatherKind.l10nKey`：它返回点号格式（`'weather.sunny'`）且被 A1
/// 测试锁定（`test/m3/weather_system_test.dart:358`），而本仓 ARB 一律下划线。
/// 穷举 `switch` 还额外换来「将来加第 10 种日型时编译期就报错」，逼着补齐名字、
/// 提示语、图标三处 —— 编译期强于运行期。
String weatherNameOf(WeatherKind kind, AppLocalizations t) => switch (kind) {
      WeatherKind.sunny => t.weather_sunny,
      WeatherKind.breeze => t.weather_breeze,
      WeatherKind.cloudy => t.weather_cloudy,
      WeatherKind.overcast => t.weather_overcast,
      WeatherKind.lightRain => t.weather_light_rain,
      WeatherKind.drought => t.weather_drought,
      WeatherKind.wind => t.weather_wind,
      WeatherKind.cold => t.weather_cold,
      WeatherKind.rainstorm => t.weather_rainstorm,
    };

/// 日型 →「今天该做什么」一句提示；**大风 / 极寒返回 `null`**。
///
/// 大风 / 极寒的强制动作只有「买棚」一件事，按钮已经完整表达了；再给一句重复的话
/// 只会挤掉本已紧张的宽度（PRD §5.4）。
String? weatherHintOf(WeatherKind kind, AppLocalizations t) => switch (kind) {
      WeatherKind.sunny => t.garden_weather_hint_sunny,
      WeatherKind.breeze => t.garden_weather_hint_breeze,
      WeatherKind.cloudy => t.garden_weather_hint_cloudy,
      WeatherKind.overcast => t.garden_weather_hint_overcast,
      WeatherKind.lightRain => t.garden_weather_hint_light_rain,
      WeatherKind.drought => t.garden_weather_hint_drought,
      WeatherKind.wind => null,
      WeatherKind.cold => null,
      WeatherKind.rainstorm => t.garden_weather_hint_rainstorm,
    };

/// 道具 refType → 道具图标（**A2 占位；A5-b 才换真美术**）。
///
/// 🔴 **A5 改口径（2026-11-04）**：同 [weatherIconOf] —— 返回 [IconData] 承载不了位图，
///    真美术到位时新增 `shelterArtOf(refType, size) -> Widget`（`errorBuilder` 回退到本函数）。
///    ⚠️ 但「已购」态的 `Icons.check_circle_rounded` **必须保留 Material 图标**：
///    §9.5 的完成态语义优先于美术，换成位图会让「做成/没做成」的判别变模糊。
///
/// `String` 无法穷举，故保留 `default`：未知 refType 回退盾牌图标，
/// **绝不抛异常**（表现层不允许把异常抛到 build 里）。
IconData shelterIconOf(String refType) {
  switch (refType) {
    case kWeatherShelterRefTypeShade:
      return Icons.beach_access_rounded;
    case kWeatherShelterRefTypeRain:
      return Icons.umbrella_rounded;
    case kWeatherShelterRefTypeWind:
      return Icons.fence_rounded;
    case kWeatherShelterRefTypeWarm:
      return Icons.cottage_rounded;
    default:
      return Icons.shield_outlined;
  }
}

/// 道具 refType → 道具名（与 `refLabelOf` **共用同一批 ARB key**，不另造词）。
///
/// 未知 refType 回 `hist_other`：正常路径不可达（调用方只会传
/// `WeatherKind.shelterRefType` 的 4 个常量值），属防御分支。
String shelterNameOf(String refType, AppLocalizations t) {
  switch (refType) {
    case kWeatherShelterRefTypeShade:
      return t.garden_shelter_shade;
    case kWeatherShelterRefTypeRain:
      return t.garden_shelter_rain;
    case kWeatherShelterRefTypeWind:
      return t.garden_shelter_wind;
    case kWeatherShelterRefTypeWarm:
      return t.garden_shelter_warm;
    default:
      return t.hist_other;
  }
}

/// 道具 refType → 购买成功 toast（PRD §9.6 的四条，按道具分）。
///
/// 未知 refType 回「已搭好」：正常路径不可达，属防御分支。
String shelterBoughtToastOf(String refType, AppLocalizations t) {
  switch (refType) {
    case kWeatherShelterRefTypeShade:
      return t.garden_shelter_bought_shade;
    case kWeatherShelterRefTypeRain:
      return t.garden_shelter_bought_rain;
    case kWeatherShelterRefTypeWind:
      return t.garden_shelter_bought_wind;
    case kWeatherShelterRefTypeWarm:
      return t.garden_shelter_bought_warm;
    default:
      return t.garden_shelter_done;
  }
}

// ── 宽度降级：档位（PRD v1.8 §5.3.2 + A2-11，**名字整存整取，绝不 ellipsis**）──
//
// 铁律：天气图标 / 道具图标 / 价格「10 ☀」任何宽度下**必留**；
//      天气名 / 道具名 **要么完整在树里，要么整个 widget 不在树里**；
//      只有提示语允许出现 `…`。

/// 宽度降级档位。顺序 = 降级顺序（越靠后省得越多）。
///
/// 与 PRD §5.3.2 阶梯的对应关系：
///  ① 省提示语 → 分**两态**（[hintTruncated] 逐字截断 / [noHint] 整句消失）；
///  ② 省道具名 → [noShelterName]（按钮整体降级为「道具图标 + 价格」）；
///  ③ 省天气名 → [noWeatherName]（胶囊整体降级为「纯天气图标」）。
enum WeatherRowTier {
  /// 完整态：胶囊 = 图标 + 名字 + 提示语；按钮 = 图标 + 名字 + 价格。
  full,

  /// 提示语被**截断**（唯一的 ellipsis 位）：天气名与道具名都完整。
  hintTruncated,

  /// 提示语**整句消失**：天气名与道具名都完整。
  noHint,

  /// 道具名**整体消失**：按钮 = 图标 + 价格；胶囊仍是 图标 + 名字。
  noShelterName,

  /// 天气名**整体消失**：胶囊 = 纯天气图标；按钮 = 图标 + 价格。
  noWeatherName,
}

/// **纯函数**：给定「各档各自所需的**宽度**」与「可用宽」，选出最低可行档位。
///
/// 零 widget 依赖、零 context 依赖 —— 可以直接在纯 Dart 单测里穷举边界，
/// 不需要 pump 任何东西（这是本批唯一新增的纯函数，也是 A2-11 的可测性来源）。
///
/// 语义：`widthXxx` 由调用方用 [measureTextWidth] 量出后加上固定件宽度算好；
/// 本函数只做「取第一个放得下的档」，不做任何测量。
///
/// 🔴 **两个提示语门槛的区别**（架构师 R23 / 设计文档 v1.10 §8-R23 + §7-K25）：
///  · [widthHintTruncated] = 「提示语**被截断**到最小位（[kWeatherHintMinWidth]）
///    仍放得下」的门槛 —— 提示语**还在**，只是被 ellipsis 截短；
///  · [widthNoHint] = 「提示语**整句消失**、两个名字都完整」仍放得下」的门槛 ——
///    **不含**那 24pt 最小提示语位。
///  ⇒ 两者的差 = `kWeatherHintMinWidth × scale` = **`noHint` 档的生存区间宽度**
///    （非空 ⇒ 该档**可达**，不是死枚举）。
///  ⇒ 🔴 2026-11-03 之前本函数**只有 4 个分支**，`noHint` 是**死枚举**
///    ⇒ 真机 390（iPhone 14/15/16 逻辑宽）实际落 `noShelterName`（道具名被牺牲），
///    而 PRD §5.3.0.1 与设计 K20 都记载应落 `noHint`（两个名字都在）。
///    **死枚举编译器抓不到、不变式断言也抓不到**（图标恒在 / 名字整存整取 /
///    零 overflow / 视觉带恒 32 全部照样成立）⇒ 只能靠
///    `test/m3/weather_a2_test.dart` 的「5 档全部可达」契约测试守住。
///
/// 🔴 宽度数字**只在指定字体口径下有意义**（PRD D-14）：测试方块字体比真机宽 18pt
///    ⇒ 同一组数字在两种口径下可能落在不同档（PRD §5.3.0.1 的表）。
///
/// 🔴 **铁律 E**：**宽度口径以设计文档 §3.2（v1.11）为准**。
/// 🔴 **铁律 D-1**：本函数的 6 个门槛入参**必须**来自 [computeWeatherRowWidths]
///    （唯一真源）⇒ 判据与渲染共用同一套数字，**不许**在别处另算一遍。
WeatherRowTier resolveWeatherRowTier({
  required double availableWidth,
  required double widthFull,
  required double widthHintTruncated,
  required double widthNoHint,
  required double widthNoShelterName,
  required double widthNoWeatherName,
}) {
  if (widthFull <= availableWidth) return WeatherRowTier.full;
  if (widthHintTruncated <= availableWidth) return WeatherRowTier.hintTruncated;
  if (widthNoHint <= availableWidth) return WeatherRowTier.noHint;
  if (widthNoShelterName <= availableWidth) return WeatherRowTier.noShelterName;
  if (widthNoWeatherName <= availableWidth) return WeatherRowTier.noWeatherName;
  // 兜底：连最省形态都放不下 ⇒ 仍取最省档，由外层 `FittedBox(scaleDown)` 等比缩整行
  // （PRD §5.3.2 兜底档：缩的是尺寸，不是内容 ⇒ 价格与两个图标仍然在）。
  return WeatherRowTier.noWeatherName;
}

/// 天气行的**宽度预算**（行级统一测算 ⇒ 行与两个子件共用同一套数字）。
///
/// 为什么要有这么一层：压缩阶梯的判据是「**放不放得下**」，而「放得下」必须用
/// **同一套宽度口径**回答。文字宽度随语言 / 字号 / 平板倍率变化，写死阈值必然在
/// 某个语言或某个字号下失准 ⇒ 名字被截成残字（QA 会按缺陷报）。
/// 故：行级用 [measureTextWidth] 量一次，把量出来的数字下发给两个子件。
@immutable
class WeatherRowMetrics {
  const WeatherRowMetrics({
    required this.scale,
    required this.weatherNameWidth,
    required this.hintWidth,
    required this.shelterNameWidth,
    required this.priceWidth,
    required this.boughtLabelWidth,
  });

  /// 图形倍率（`uiScaleOf(context)`）。
  final double scale;

  /// 天气名的渲染宽度。
  final double weatherNameWidth;

  /// 提示语（**含前缀 '· '**）的渲染宽度。
  final double hintWidth;

  /// 道具名的渲染宽度。
  final double shelterNameWidth;

  /// 价格（「10 ☀」）的渲染宽度。
  final double priceWidth;

  /// 已购态标签（「已搭好」）的渲染宽度。
  final double boughtLabelWidth;

  /// 道具按钮**视觉件**宽。
  ///
  /// 结构（可买态）：`[图标 14][gap 4][名字][gap 4][价格]` + 水平内边距 6×2。
  /// 结构（已购态）：`[图标 14][gap 4][已搭好]` + 水平内边距 6×2。
  double buttonVisualWidth({required bool bought, required bool showName}) {
    double w = kShelterIconSize * scale + kShelterButtonPaddingH * scale * 2;
    if (bought) return w + kWeatherRowInnerGap * scale + boughtLabelWidth;
    if (showName) w += kWeatherRowInnerGap * scale + shelterNameWidth;
    return w + kShelterNamePriceGap * scale + priceWidth;
  }

  /// 道具按钮**命中盒**宽（= 视觉宽与 44pt 取大；**不加水平外扩**，见 [kHitPadLeft]）。
  double buttonHitWidth({required bool bought, required bool showName}) =>
      math.max(kMinTapTarget * scale, buttonVisualWidth(bought: bought, showName: showName));

  /// 天气胶囊**视觉件**宽。
  ///
  /// 结构：`[图标 18][gap 4][名字][gap 4][提示语]` + 水平内边距 8×2。
  double pillVisualWidth({required bool showName, required bool showHint}) {
    double w = kWeatherPillIconSize * scale + kWeatherPillPaddingH * scale * 2;
    if (showName) w += kWeatherRowInnerGap * scale + weatherNameWidth;
    if (showHint) w += kWeatherRowInnerGap * scale + hintWidth;
    return w;
  }

  /// 天气胶囊**命中盒**宽（= 视觉宽 + 水平外扩 10，与 44pt 取大）。
  double pillHitWidth({required bool showName, required bool showHint}) =>
      math.max(
        kMinTapTarget * scale,
        pillVisualWidth(showName: showName, showHint: showHint) +
            kWeatherPillHitPadH * scale,
      );
}

// ── 判据量的唯一真源（铁律 D-1 · 架构师 v1.11 §3.2）──────────────────────────

/// 量一次天气行的**宽度预算**（**唯一真源**：行内两个子件与阶梯判据共用这一套数字）。
///
/// 🔴 **铁律 D-1**：测试**直接调用**本函数拿真值，**绝对不许**在测试里复算公式
///    （复算 = 把实现抄一遍 ⇒ 实现改错测试跟着错，等于没测）。
/// 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。
WeatherRowMetrics measureWeatherRowMetrics({
  required WeatherKind kind,
  required String? shelterRefType,
  required bool hasButton,
  required AppLocalizations t,
  required TextScaler scaler,
  required double scale,
}) {
  final String? hint = weatherHintOf(kind, t);
  return WeatherRowMetrics(
    scale: scale,
    weatherNameWidth: measureTextWidth(
        weatherNameOf(kind, t), weatherNameTextStyle(), scaler),
    hintWidth: hint == null
        ? 0
        : measureTextWidth('· $hint', weatherHintTextStyle(), scaler),
    shelterNameWidth: hasButton && shelterRefType != null
        ? measureTextWidth(shelterNameOf(shelterRefType, t),
            shelterNameTextStyle(), scaler)
        : 0,
    priceWidth: measureTextWidth(
        '$kWeatherShelterPrice ☀', shelterPriceTextStyle(const Color(0xFF5D4200)),
        scaler),
    boughtLabelWidth:
        measureTextWidth(t.garden_shelter_done, shelterBoughtTextStyle(), scaler),
  );
}

/// 压缩阶梯的**判据量**（5 个宽度门槛 + 2 个按钮命中宽 + 3 个胶囊视觉宽）。
///
/// 🔴 **铁律 D-1**：本类由 [computeWeatherRowWidths] **唯一**产生，
///    并被**选档**（[resolveWeatherRowTier]）与**渲染**（胶囊的槽宽 / 按钮的视觉宽）
///    **共用** —— 「判据与渲染共用同一套数字」是本设计的核心不变量，**不许断**。
/// 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。
@immutable
class WeatherRowWidths {
  const WeatherRowWidths({
    required this.widthFull,
    required this.widthHintTruncated,
    required this.widthNoHint,
    required this.widthNoShelterName,
    required this.widthNoWeatherName,
    required this.buttonFullHit,
    required this.buttonIconPriceHit,
    required this.pillFull,
    required this.pillName,
    required this.pillIcon,
  });

  /// 「完整态」的总宽门槛（名字 + 提示语 + 道具名都在）。
  final double widthFull;

  /// 「提示语**被截断**」的总宽门槛（提示语还在，只是被截到最小位）。
  final double widthHintTruncated;

  /// 「提示语**整句消失**」的总宽门槛（**不含**那 24pt 最小提示语位）。
  final double widthNoHint;

  /// 「牺牲道具名」的总宽门槛。
  final double widthNoShelterName;

  /// 「牺牲天气名」的总宽门槛（最省形态）。
  final double widthNoWeatherName;

  /// 道具按钮**带名字**时的命中盒宽。
  final double buttonFullHit;

  /// 道具按钮**省掉名字**（图标 + 价格）时的命中盒宽。
  final double buttonIconPriceHit;

  /// 胶囊**完整形态**（名字 + 提示语）的视觉宽。
  final double pillFull;

  /// 胶囊**只有名字**（无提示语）的视觉宽。
  final double pillName;

  /// 胶囊**只有图标**（最省形态）的视觉宽。
  final double pillIcon;
}

/// 纯函数：算出压缩阶梯的**判据量**（**唯一真源**）。
///
/// 🔴 **铁律 D-1**：这 5 个门槛表达式从 [_fitTier] 里**原样搬家**过来，
///    **逐字未改**（只许搬家，不许改值）；[_fitTier] 与 [resolveWeatherRowTier]
///    都从这里取数 ⇒ 判据与渲染**共用同一套数字**，不许分家。
/// 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。
WeatherRowWidths computeWeatherRowWidths({
  required WeatherRowMetrics metrics,
  required bool bought,
  required bool hasButton,
}) {
  final double s = metrics.scale;
  final double gap = kWeatherRowGap * s;
  final double hitPadH = kWeatherPillHitPadH * s;

  final double buttonFullHit = hasButton
      ? metrics.buttonHitWidth(bought: bought, showName: true)
      : 0;
  final double buttonIconPriceHit = hasButton
      ? metrics.buttonHitWidth(bought: bought, showName: false)
      : 0;

  final double pillFull = metrics.pillVisualWidth(showName: true, showHint: true);
  final double pillName = metrics.pillVisualWidth(showName: true, showHint: false);
  final double pillIcon = metrics.pillVisualWidth(showName: false, showHint: false);

  // 各档的**总宽**（命中盒口径 —— 真正占位的是命中盒，不是视觉件）。
  final double widthFull = hasButton
      ? buttonFullHit + gap + pillFull + hitPadH
      : pillFull + hitPadH;
  // 🔴 「提示语**被截断**」档的门槛：提示语还在，只是被截到 [kWeatherHintMinWidth]
  //    的最小位（唯一允许 ellipsis 的元素）。
  final double widthHintTruncated = hasButton
      ? buttonFullHit + gap + pillName + kWeatherHintMinWidth * s + hitPadH
      : pillName + kWeatherHintMinWidth * s + hitPadH;
  // 🔴 「提示语**整句消失**、两个名字都完整」档的门槛：**不含**那 24pt 最小提示语位。
  //    它与 [widthHintTruncated] 的差 = `kWeatherHintMinWidth × s` ⇒
  //    `noHint` 档的生存区间宽度（非空 ⇒ 该档可达，架构师 R23 的恒等式）。
  final double widthNoHint = hasButton
      ? buttonFullHit + gap + pillName + hitPadH
      : pillName + hitPadH;
  final double widthNoShelterName = hasButton
      ? buttonIconPriceHit + gap + pillName + hitPadH
      : pillName + hitPadH;
  final double widthNoWeatherName = hasButton
      ? buttonIconPriceHit + gap + pillIcon + hitPadH
      : pillIcon + hitPadH;

  return WeatherRowWidths(
    widthFull: widthFull,
    widthHintTruncated: widthHintTruncated,
    widthNoHint: widthNoHint,
    widthNoShelterName: widthNoShelterName,
    widthNoWeatherName: widthNoWeatherName,
    buttonFullHit: buttonFullHit,
    buttonIconPriceHit: buttonIconPriceHit,
    pillFull: pillFull,
    pillName: pillName,
    pillIcon: pillIcon,
  );
}

// ── 组件 ─────────────────────────────────────────────────────────────────────

/// 天气胶囊：`[icon][天气名?][· 提示语?]`。
///
/// ## 尺寸（**三个量，各有各的断言，别混** —— PRD v1.7 定稿 + D-11 + D-12）
///  · **实体** [kWeatherPillKey] = **28**（`Material`；白底 0.88 / radius **20** /
///    elevation 2，逐字复用 `_SeedCountChip` 的色与 elevation，不加新色）⇒ **A2-8⑧ 单独断言它**；
///  · **槽** [kWeatherPillSlotKey] = **32**（`SizedBox(height: 32*u)`，**完全透明**：
///    无底色 / 无阴影 / 无边框）⇒ **A2-8③ 测它**、**A2-8⑦ 测它的透明度**；
///    实体 28 **顶对齐槽顶**（槽底留 4pt 透明）；
///  · **命中盒** [kWeatherPillHitKey] = **44**（32 + 上下各 6；水平另加 4+6 = 10）
///    ⇒ **A2-10① 量尺寸 + A2-10⑥ 真点击探针**。
///  ✅ 槽 32 / 实体 28 是**两层**：槽保证「视觉带恒 32」（跨零点不跳动），实体保证
///     「与 chips 同族」（D-12 准则 ②）。
///  ⚠️ **槽高 == 32 ≠ 实体高 == 28**（PRD D-11：这件事来回过四轮）。
///  🔴 **实体 key 不得与槽 key 同值 / 互为别名**（否则 A2-8⑧ / A2-2 恒红）。
///
/// ## 名字：整存整取（A2-11 / §5.3.2）
/// [showWeatherName] == false 时，天气名那个 `Text` **根本不进 widget 树**（`findsNothing`），
/// **不是**被 ellipsis 截成 `干…`。[showHint] 只控制提示语在不在树里；
/// 提示语**在树里时**允许被 ellipsis 截断（它是唯一允许 `…` 的元素）。
///
/// ## 🔴 「量」与「画」分离
/// [metrics] 与 [slotWidth] 由**行级**算好后下发（[WeatherRowMetrics] /
/// [resolveWeatherRowTier]），**本组件自己不许再量宽度**（否则两处量的口径会漂）。
///
/// ## 只准读 kind（PRD §8-9）
/// 本组件**不许**读 `growthFactor` / `waterFactor` / `fertilizeFactor` /
/// `waterQuota` / `fertilizeQuota` / `rainWaterBonusPp` —— 一个都不显示。
class WeatherPill extends StatelessWidget {
  const WeatherPill({
    super.key,
    required this.kind,
    required this.metrics,
    required this.slotWidth,
    required this.showWeatherName,
    required this.showHint,
    this.onTap,
  });

  /// 今日日型（由页面从 `WeatherSystem.ofDay` 直接传入，本组件不自算天气）。
  final WeatherKind kind;

  /// 宽度预算（行级下发，保证「量」与「画」同源）。
  final WeatherRowMetrics metrics;

  /// 视觉槽宽（行级算好）。
  final double slotWidth;

  /// 天气名是否整块出现。
  final bool showWeatherName;

  /// 提示语是否出现（出现时可能被截断 —— 唯一允许 ellipsis 的元素）。
  final bool showHint;

  /// 点击回调（`null` = 不可点；本批恒为 `null`，主理人裁定 R4）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double s = metrics.scale;
    final AppLocalizations t = l10nOf(context);
    final String name = weatherNameOf(kind, t);
    final String? hint = weatherHintOf(kind, t);

    // 图标**非弹性**（永不被挤掉，PRD §5.3.2 ①）。
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          weatherIconOf(kind),
          size: kWeatherPillIconSize * s,
          color: kWeatherTextColor,
        ),
        if (showWeatherName) ...<Widget>[
          const SizedBox(width: kWeatherRowInnerGap),
          // 名字：**整块**给出，宽度由预算算死；`FittedBox` 只在测量有亚像素误差时
          // 等比缩一档（**不截断**，也不产生残字）。
          SizedBox(
            width: metrics.weatherNameWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(name, maxLines: 1, softWrap: false,
                  style: weatherNameTextStyle()),
            ),
          ),
        ],
        if (showHint && hint != null) ...<Widget>[
          const SizedBox(width: kWeatherRowInnerGap),
          // 提示语：**唯一**允许 ellipsis 的元素（宽度不够时逐字截断）。
          Flexible(
            child: Text(
              '· $hint',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: weatherHintTextStyle(),
            ),
          ),
        ],
      ],
    );

    // 视觉件：**实体 28pt 高**的白胶囊（样式逐字复用既有 `_SeedCountChip`）。
    //
    // 🔴 纵向留白用「**装得下才用**」判定（见 [kWeatherPillPaddingV] 的 PRD v1.9 口径）：
    //    · 内容盒 = 实体高 − 2 × 纵向内距 = 28 − 12 = **16** < 天气图标 **18**
    //      ⇒ 此时**不加**纵向内距，改为内容居中（**等效留白 5**，图标保持 18 不缩水）；
    //    · 若图标改回 16（chips 同款）⇒ 内容盒 16 恰好装满 ⇒ 留白自动变回 6。
    final double padV = (kWeatherPillHeight - kWeatherPillIconSize) * s >=
            kWeatherPillPaddingV * 2 * s
        ? kWeatherPillPaddingV * s
        : 0.0;
    final Widget entity = SizedBox(
      key: kWeatherPillKey,
      height: kWeatherPillHeight * s,
      child: Material(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(kWeatherPillRadius),
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kWeatherPillPaddingH * s),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padV),
              child: row,
            ),
          ),
        ),
      ),
    );

    // 视觉槽：32pt 高（视觉带），实体 28 **顶对齐槽顶**（实体顶 == 槽顶，槽底留 4pt 透明）
    // —— 槽是**测量口径**，实体顶与 chips 顶齐边。
    //
    // 🔴 用 `Align(alignment: Alignment.topCenter)` 而不是 `Center`：
    //    `Center` 会把实体在 32 槽里上下各留 2pt ⇒ 实体顶比 chips 顶低 2pt（不齐边）；
    //    `Align` 必须**显式带** `alignment` 参数（不许写成裸 `child: entity`：
    //    裸 child 会被父级 tight 约束把实体拉回 32 高 ⇒ 实体不再是 28 ⇒ A2-8⑧ 退化）。
    final Widget slot = SizedBox(
      key: kWeatherPillSlotKey,
      width: slotWidth,
      height: kWeatherPillSlotHeight * s,
      child: Align(alignment: Alignment.topCenter, child: entity),
    );

    // 命中盒：44 高（32 槽 + 上下各 6 透明留白），水平左 4 / 右 6。
    // 🔴 `HitTestBehavior.opaque` 是关键：它让那 6pt 透明留白**也吃点击**。
    // 🔴 `onTap: null` 时 `GestureDetector` 一样参与布局（44 照常在树里），
    //    P1-1 落地时只改这一行、布局不跳。
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: kMinTapTarget * s,
        minHeight: kWeatherHitHeight * s,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: (kWeatherHitHeight - kWeatherPillSlotHeight) / 2 * s,
          ),
          // 胶囊**贴右**：命中盒比视觉槽宽时（水平外扩 10），多出来的空间在左边。
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Padding(
              padding: EdgeInsets.only(
                left: kHitPadLeft * s,
                right: kHitPadRight * s,
              ),
              child: slot,
            ),
          ),
        ),
      ),
    );
  }
}

/// 推荐道具按钮：三态（可买 / 已购 / 阳光不足灰态）。
///
/// 🔴 灰态**不是** `onTap: null`：本仓既有结论「`onTap: null` 让孩子点了毫无反馈」
/// 被判为缺陷（`garden_page.dart` 里 F166 的修订）。灰态只降不透明度到
/// [kShelterDisabledOpacity]，`onTap` **恒非 null**，点了由页面给浮层提示。
///
/// 🔴 价格（`10 ☀`）与道具图标**永不省略、永不截断**（R3 硬要求）：
///  · 价格是**独立的、非弹性的** `Text`（绝不与名字拼进同一个 `Text`，
///    也绝不塞进 `Flexible` / `Expanded` —— 那会让它被截成「10…」）；
///  · 名字是**独立**的一块，放不下时由压缩阶梯**整体撤掉**（见 [WeatherRowTier]）。
class ShelterBuyButton extends StatelessWidget {
  const ShelterBuyButton({
    super.key,
    required this.refType,
    required this.metrics,
    required this.visualWidth,
    required this.bought,
    required this.affordable,
    required this.showShelterName,
    required this.onTap,
  });

  /// 当日推荐道具 refType（调用方保证非 null；温和日根本不渲染本组件）。
  final String refType;

  /// 宽度预算（行级下发）。
  final WeatherRowMetrics metrics;

  /// 视觉件宽（行级算好，含当前形态下的全部元素）。
  final double visualWidth;

  /// 已购态：`✅ 已搭好`（浅绿底 + check 图标）。
  final bool bought;

  /// 余额 ≥ 价格。`false` → 灰态（不透明度 40%）。
  final bool affordable;

  /// 道具名是否整块出现（压缩阶梯第④档关闭时为 false）。
  final bool showShelterName;

  /// 点击回调（**灰态与已购态都必须非 null**）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double s = metrics.scale;
    final AppLocalizations t = l10nOf(context);

    final Color bg = bought ? kShelterBoughtBg : GoldNoticeStyle.gold;
    final Color fg = bought ? kShelterBoughtFg : GoldNoticeStyle.buttonFg;
    final String label = bought ? t.garden_shelter_done : shelterNameOf(refType, t);

    final List<Widget> children = <Widget>[
      // 道具图标：非弹性、永不被挤掉（R3）。
      Icon(
        bought ? Icons.check_circle_rounded : shelterIconOf(refType),
        size: kShelterIconSize * s,
        color: fg,
      ),
    ];
    if (bought) {
      children
        ..add(const SizedBox(width: kWeatherRowInnerGap))
        ..add(
          SizedBox(
            width: metrics.boughtLabelWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  maxLines: 1, softWrap: false,
                  style: shelterBoughtTextStyle()),
            ),
          ),
        );
    } else {
      if (showShelterName) {
        children
          ..add(const SizedBox(width: kWeatherRowInnerGap))
          ..add(
            // 名字：整块给出（不做 ellipsis）；宽度由预算算死。
            SizedBox(
              width: metrics.shelterNameWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    maxLines: 1, softWrap: false,
                    style: shelterNameTextStyle()),
              ),
            ),
          );
      }
      children
        ..add(const SizedBox(width: kShelterNamePriceGap))
        ..add(
          // 价格：**非弹性、无 overflow、无 maxLines** ⇒ 永不省略、永不截断。
          SizedBox(
            width: metrics.priceWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('$kWeatherShelterPrice ☀',
                  maxLines: 1, softWrap: false,
                  style: shelterPriceTextStyle(fg)),
            ),
          ),
        );
    }

    // 视觉件：32pt 高的阳光金胶囊。
    final Widget visual = SizedBox(
      key: kShelterButtonVisualKey,
      width: visualWidth,
      height: kShelterButtonHeight * s,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(kWeatherPillRadius),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(kWeatherPillRadius),
          // 🔴 恒非 null：灰态与已购态也必须有反馈（见类注释）。
          onTap: onTap,
          child: Padding(
            padding:
                EdgeInsets.symmetric(horizontal: kShelterButtonPaddingH * s),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );

    // 灰态：只降透明度，不换 onTap（F166）。
    final Widget tinted = (bought || affordable)
        ? visual
        : Opacity(opacity: kShelterDisabledOpacity, child: visual);

    // 命中盒：视觉 32pt，**真实命中盒 ≥44×44**（A2-10）。
    //
    // 🔴 不用 `ConstrainedBox(minHeight:44) + OverflowBox`「声明」44 ——
    //    那样 `getSize` 量得到 44（断言假绿），但真实点击在行容器那层就被
    //    `RenderBox.hitTest` 拒掉（`size.contains(position)` 为 false），
    //    孩子手指按在按钮边缘就是「按了没反应」。
    // 🔴 不用 `MaterialTapTargetSize.shrinkWrap`（会吃掉默认 8pt 外扩）。
    // ✅ 这里：`Padding(vertical 6+6)` 使 `GestureDetector` 自身尺寸 = 32+6+6 = 44，
    //    `HitTestBehavior.opaque` 让这 6pt 透明留白**也吃点击** ⇒ 命中盒是**真 44**。
    //    水平方向沿用 `minWidth: 44`（不多加透明 padding，省下窄屏宽度预算）。
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: kMinTapTarget * s,
        minHeight: kWeatherHitHeight * s,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 🔴 恒非 null：灰态与已购态也必须有反馈（见类注释）。
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: kHitPadVertical * s),
          child: Center(widthFactor: 1, heightFactor: 1, child: tinted),
        ),
      ),
    );
  }
}

/// 天气行布局壳：44pt 透明命中带内 `Row(min) [ 按钮?, gap?, 胶囊 ]`。
///
/// ## 两种「不渲染按钮」的情形（视觉上完全一致）
///  · 温和日（[shelterRefType] == null）：PRD §4.5 裁定整条道具区不渲染；
///  · 账本未读完（[showShelterButton] == false）：不让「买」字闪一下又变。
///
/// ## 压缩阶梯在这里决策（本类唯一职责）
/// 决策输入 = **可用宽度**（父级 `Flexible` 给的 loose 上界）与**实测渲染宽度**
/// （[WeatherRowMetrics]，由 [measureTextWidth] 量得）。输出 = 档位 + 两个子件的形态。
/// 两个子件只负责「按给定的形态画」，**自己不判断该不该降级** —— 单一决策点。
///
/// ## 零溢出（A2-8 ⑤）
/// 阶梯选出的形态**按构造**放得下（选不下的档位不会被选中）；
/// 极端窄屏（连最省形态都放不下）由外层 `FittedBox(scaleDown)` 等比收尾 —— 缩的是
/// 整行，**不删任何元素**（价格与两个图标始终在）。
class GardenWeatherRow extends StatelessWidget {
  const GardenWeatherRow({
    super.key,
    required this.kind,
    required this.shelterRefType,
    required this.bought,
    required this.affordable,
    required this.showShelterButton,
    required this.onShelterTap,
    this.onPillTap,
  });

  /// 今日日型（`WeatherSystem.ofDay(DateTime.now()).kind`，由页面传入）。
  final WeatherKind kind;

  /// 当日推荐道具 refType；**`null` = 温和日 → 整条道具区不渲染**（PRD §4.5）。
  final String? shelterRefType;

  /// 今日是否已买（账本判定；温和日恒 `false`）。
  final bool bought;

  /// 余额 ≥ [kWeatherShelterPrice]。
  final bool affordable;

  /// `false` 时**不渲染按钮**（账本未读完；胶囊仍然渲染 —— A2-2 首帧即可见）。
  final bool showShelterButton;

  /// 点推荐道具（三态都由页面分发，组件不做业务判断）。
  final VoidCallback onShelterTap;

  /// 点天气胶囊（`null` = 不可点；本批恒为 `null`，见主理人裁定 R4）。
  final VoidCallback? onPillTap;

  @override
  Widget build(BuildContext context) {
    final double s = uiScaleOf(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final AppLocalizations t = l10nOf(context);

    final String? refType = shelterRefType;
    final bool hasButton = refType != null && showShelterButton;

    // ── 量一次宽度（行与子件共用同一套数字）────────────────────────────────
    // 🔴 **铁律 D-1**：宽度的**测量入口**只有 [measureWeatherRowMetrics] 一个 ⇒
    //    行内两个子件、阶梯判据、测试**全部**用同一套数字（不许分家）。
    // 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。
    final String? hint = weatherHintOf(kind, t);
    final WeatherRowMetrics metrics = measureWeatherRowMetrics(
      kind: kind,
      shelterRefType: refType,
      hasButton: hasButton,
      t: t,
      scaler: scaler,
      scale: s,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;

        // ── 压缩阶梯决策（唯一决策点）──────────────────────────────────────
        final _TierFit fit = _fitTier(
          available: available,
          metrics: metrics,
          bought: bought,
          hasButton: hasButton,
          hasHint: hint != null,
        );

        final Widget button = hasButton
            ? ShelterBuyButton(
                key: kShelterButtonHitKey,
                refType: refType,
                metrics: metrics,
                visualWidth: fit.buttonWidth,
                bought: bought,
                affordable: affordable,
                showShelterName: fit.showShelterName,
                onTap: onShelterTap,
              )
            : const SizedBox.shrink();

        final Widget pill = WeatherPill(
          key: kWeatherPillHitKey,
          kind: kind,
          metrics: metrics,
          slotWidth: fit.pillWidth,
          showWeatherName: fit.showWeatherName,
          showHint: fit.showHint,
          onTap: onPillTap,
        );

        final Widget row = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (hasButton) ...<Widget>[
              button,
              SizedBox(width: fit.rowGap),
            ],
            pill,
          ],
        );

        return SizedBox(
          // 🔴 行**容器**高 44pt（= 命中容器）：视觉件在其中居中。
          //    必须是 44 而非 32 —— `RenderBox.hitTest` 首行即
          //    `if (!size.contains(position)) return false;`，容器只有 32 高时
          //    子树里 44 的命中盒收不到真实点击（`getSize` 却量得到 ⇒ 假绿）。
          //    `Positioned` 不参与父级布局 ⇒ 对 `gardenGridVisibleHeight` 影响恒为 0。
          // 🔴 视觉带恒 32（A2-8 ③）：由 [kShelterButtonVisualKey] / [kWeatherPillSlotKey]
          //    两个**视觉件**各自的尺寸保证，不依赖本容器高度。
          height: kWeatherHitHeight * s,
          child: FittedBox(
            // `scaleDown` **只缩不放**：能放下时（几乎总是）原样 1.0。
            // 窄到连最省形态都放不下时才等比缩小（此时命中区同比缩小，
            // 是宽屏不足的合理降级，不是「声明尺寸」）。
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: row,
          ),
        );
      },
    );
  }
}

/// 一档压缩的**测算结果**（形态 + 两个子件的宽度）。
@immutable
class _TierFit {
  const _TierFit({
    required this.tier,
    required this.showWeatherName,
    required this.showHint,
    required this.showShelterName,
    required this.buttonWidth,
    required this.pillWidth,
    required this.rowGap,
  });

  /// 所属档位。
  final WeatherRowTier tier;

  /// 天气名是否出现（**整块**，不做 ellipsis）。
  final bool showWeatherName;

  /// 提示语是否出现（出现时可能被截断）。
  final bool showHint;

  /// 道具名是否出现（**整块**，不做 ellipsis）。
  final bool showShelterName;

  /// 按钮视觉件宽。
  final double buttonWidth;

  /// 胶囊视觉槽宽。
  final double pillWidth;

  /// 按钮与胶囊之间的间距。
  final double rowGap;
}

/// 按可用宽度挑一档压缩形态（阶梯：提示语 → 道具名 → 天气名）。
///
/// ## 判据（「分配额」而不是「相加和」）
/// 先扣掉**按钮占掉的宽度**（命中盒宽 + 8pt 间距），剩下的就是**胶囊的分配额**；
/// 再拿分配额去比胶囊各形态的**自然宽度**。这样每一档的判断都是「胶囊还剩多少空间」，
/// 而不是「两堆宽度加在一起」—— 后者会被命中盒的 44pt 下限搅浑。
///
/// ## 阶梯是**顺序**的（PRD v1.8 §5.3.2）：提示语先没（可截断可消失），再没道具名，
/// 最后才没天气名。降一级**不会**把上一级的东西还回来（那会让「已经牺牲过的」
/// 状态反复横跳）。
///
/// 🔴 **口径提示**：本函数量出来的宽度**只在当前字体口径下有意义**
///    （PRD D-14 / W-3）。测试方块字体比真机宽 18pt ⇒ 390 上真机落档 ③、测试落档 ④。
///    这是**字体差异，不是实现的 bug**，**不许**为了对上某个宽度的落档去改视觉度量。
_TierFit _fitTier({
  required double available,
  required WeatherRowMetrics metrics,
  required bool bought,
  required bool hasButton,
  required bool hasHint,
}) {
  final double s = metrics.scale;
  final double gap = kWeatherRowGap * s;
  final double hitPadH = kWeatherPillHitPadH * s;

  /// 胶囊**分配额**（按钮在时先扣掉按钮 + 间距 + 胶囊命中盒的水平外扩）。
  double pillAllocFor(double buttonHitWidth) {
    if (!hasButton) return available - hitPadH;
    return available - gap - buttonHitWidth - hitPadH;
  }

  // 🔴 **铁律 D-1**：判据量由 [computeWeatherRowWidths] **直接暴露**（**唯一真源**）。
  //    5 个门槛的表达式与搬家前**逐字一致**（只许搬家，不许改值）。
  // 🔴 **铁律 E**：宽度口径以设计文档 §3.2（v1.11）为准。
  final WeatherRowWidths widths = computeWeatherRowWidths(
    metrics: metrics,
    bought: bought,
    hasButton: hasButton,
  );

  // 🔴 **判据与渲染共用同一套数字**（铁律 D-1 的核心不变量，不许断）：
  //    下面 4 个局部量是**从真量对象里取的别名**，**不重算** ——
  //    重算就会变成两份数字，改一处漏一处 ⇒ 判据与渲染分家。
  //    （用别名而不是直接写 `widths.xxx`，是为了让下面 5 个档位的
  //    `pillWidth` 公式与搬家前**逐字一致**，便于逐行比对。）
  final double buttonFullHit = widths.buttonFullHit;
  final double pillFull = widths.pillFull;
  final double pillName = widths.pillName;
  final double pillIcon = widths.pillIcon;

  final WeatherRowTier tier = resolveWeatherRowTier(
    availableWidth: available,
    widthFull: widths.widthFull,
    widthHintTruncated: widths.widthHintTruncated,
    widthNoHint: widths.widthNoHint,
    widthNoShelterName: widths.widthNoShelterName,
    widthNoWeatherName: widths.widthNoWeatherName,
  );

  final double allocFull = pillAllocFor(buttonFullHit);

  switch (tier) {
    case WeatherRowTier.full:
      return _TierFit(
        tier: tier,
        showWeatherName: true,
        showHint: hasHint,
        showShelterName: true,
        buttonWidth: metrics.buttonVisualWidth(bought: bought, showName: true),
        pillWidth: pillFull,
        rowGap: gap,
      );

    case WeatherRowTier.hintTruncated:
      // 提示语**逐字截断**（唯一的 ellipsis 位）：胶囊占满分配额，提示语被挤到只剩
      // 若干字（`Flexible` + `ellipsis` 在胶囊内部完成截断）。
      //
      // 🔴 槽宽**永远不小于**胶囊的自然宽（图标 + 名 + 内距）：宽度预算只决定
      //    「丢哪个元素」，**不决定「把元素压扁」** —— 压扁会让图标缩水
      //    （违反 R3「两个图标恒在」）。真的放不下时，交给外层
      //    `FittedBox(scaleDown)` 等比缩整行（PRD §5.3.2 兜底档）。
      return _TierFit(
        tier: tier,
        showWeatherName: true,
        showHint: hasHint,
        showShelterName: true,
        buttonWidth: metrics.buttonVisualWidth(bought: bought, showName: true),
        pillWidth: math.max(pillName, math.min(allocFull, pillFull)),
        rowGap: gap,
      );

    case WeatherRowTier.noHint:
      // 提示语**整句消失**（低于最小可用宽度 ⇒ 只剩「· …」这种碎片，不如没有）。
      return _TierFit(
        tier: tier,
        showWeatherName: true,
        showHint: false,
        showShelterName: true,
        buttonWidth: metrics.buttonVisualWidth(bought: bought, showName: true),
        pillWidth: pillName,
        rowGap: gap,
      );

    case WeatherRowTier.noShelterName:
      // 省道具名：按钮降级为「道具图标 + 价格」，腾出的宽度给胶囊的名字。
      return _TierFit(
        tier: tier,
        showWeatherName: true,
        showHint: false,
        showShelterName: false,
        buttonWidth: metrics.buttonVisualWidth(bought: bought, showName: false),
        pillWidth: pillName,
        rowGap: gap,
      );

    case WeatherRowTier.noWeatherName:
      // 省天气名：胶囊降级为「纯天气图标」—— 最省形态。
      //
      // 🔴 槽宽 = 胶囊的**自然宽**（图标 18 + 内距 16），**不再**按分配额裁剪：
      //    分配额 `allocReduced` 在极窄屏（可用宽 < 按钮命中宽 + 间距 + 外扩）时
      //    会变成**负数** ⇒ `SizedBox(width: 负数)` ⇒ `BoxConstraints has a
      //    negative minimum width` 崩溃（本批在 320×568 + 1.3 倍字号下实测到）。
      //    预算只决定「丢哪个元素」，缩放交给外层 `FittedBox(scaleDown)`。
      return _TierFit(
        tier: tier,
        showWeatherName: false,
        showHint: false,
        showShelterName: false,
        buttonWidth: metrics.buttonVisualWidth(bought: bought, showName: false),
        pillWidth: pillIcon,
        rowGap: gap,
      );
  }
}
