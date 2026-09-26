/// 暖色儿童风卡片公共件（孩子端 / 家长端共用，保证风格统一，单点收口）。
///
/// 马卡龙色底 + 深字色来自孩子端阳光商店卡，集中在此避免「同一组色值散落多处」
/// （否则改配色要改 N 个文件）。真实角色立绘由玄参大人后续提供，图标先用 emoji 占位。
library cream_card;

import 'package:flutter/material.dart';

/// 马卡龙色底（图标块用），按条目稳定轮换 3-4 种明快色。
const List<Color> kMacaronBg = <Color>[
  Color(0xFFFFD9E0),
  Color(0xFFFFF1C2),
  Color(0xFFD9F2DD),
  Color(0xFFD9E8FF),
];

/// 马卡龙色底对应的深字色（保证对比度 ≥ 4.5:1）。
const List<Color> kMacaronFg = <Color>[
  Color(0xFFC2185B),
  Color(0xFF8D6E00),
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
];

/// 暖色儿童风卡片装饰：纯白大圆角 + 极柔阴影。
BoxDecoration creamCardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    );

/// 按 id 稳定选一组马卡龙配色（色底 + 深字色），相同 id 永远同色。
({Color bg, Color fg}) macaronColorById(String id) {
  final int idx = id.hashCode.abs() % kMacaronBg.length;
  return (bg: kMacaronBg[idx], fg: kMacaronFg[idx]);
}

/// 左侧彩色圆角图标块（马卡龙色底 + emoji 占位图标）。
Widget macaronIconBlock({required String emoji, required Color bg}) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );

/// 小胶囊标签（分类/状态用）：马卡龙色底 + 同组深字色，圆角。
Widget pillLabel({required String text, required Color bg, required Color fg}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
