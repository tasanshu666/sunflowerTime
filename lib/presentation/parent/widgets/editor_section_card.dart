/// 家长端编辑弹窗的「分区卡片」容器（F178，玄参 2026-11-04 拍板）。
///
/// 纯视觉组件：把一组表单控件装进一张圆角描边卡片，配一个「图标 + 分区标题」。
/// 只负责外观，不掺业务；控件之间的间距仍由调用方用既有 `SizedBox` 维持，
/// 保证改造前后「干湿」间距逐像素一致。
///
/// 尺寸常量**一律不乘 `uiScaleOf`**：卡片内文字已随 `textScaler` 放大，内距再乘
/// 会双倍膨胀——这是 K27 那条坑的教训。
library editor_section_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/shared/theme.dart';

class EditorSectionCard extends StatelessWidget {
  const EditorSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  /// 分区图标（标题行左侧）。
  final IconData icon;

  /// 分区标题文案（调用方经 ARB 传入）。
  final String title;

  /// 分区内容（表单控件，调用方自行维持彼此间距）。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final bool dark = theme.brightness == Brightness.dark;

    // 底板色：深色用 `surfaceContainerHigh`（当前 Flutter 3.44 的 Material 3
    // ColorScheme 已内置该成员，见 SDK `color_scheme.dart:197`）。
    final Color cardColor = dark ? scheme.surfaceContainerHigh : Colors.white;
    // 描边：亮色固定浅蓝灰；深色走主题 outlineVariant。
    final Color borderColor =
        dark ? scheme.outlineVariant : const Color(0xFFDCE7EC);
    // 阴影基色：亮色用 parentSeed（家长端主题种子色），深色用纯黑。
    final Color shadowBase = dark ? Colors.black : parentSeed;

    return Container(
      // start 对齐下若不撑满会缩成内容宽 → 显式 width: double.infinity。
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(width: 1, color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: shadowBase.withValues(alpha: dark ? 0.24 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 🔴 F178：内容包一层**透明 Material**——卡内的 `SwitchListTile` 是 ListTile，
      // 其 ink 画在最近的 Material 上；若最近 Material 之上还有带底色的 DecoratedBox
      // （本卡 Container 的 BoxDecoration），Flutter 会在 debug 期抛
      // 「ListTile background color or ink splashes may be invisible」断言（F164 探针
      // 会红）。这里在装饰之下垫一层透明 Material，ListTile 的 ink 落在它上面、
      // 位于卡底色之上可见，断言消除，且视觉无变化（透明）。
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 17, color: scheme.primary),
                const SizedBox(width: 6),
                // 必须 Expanded 包标题（英文标题历史出过挤压问题，见 F161 / F164）。
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
