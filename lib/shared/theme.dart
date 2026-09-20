/// 应用主题（§4.1.4 低打扰、明亮向日葵基调）。
library theme;

import 'package:flutter/material.dart';

/// 主色种子：阳光黄（品牌色）。
const Color sunlightYellow = Color(0xFFF5C542);

/// 浅色暖黄主题（向日葵风）：暖米白底 + 阳光黄主色 + 大圆角卡片/按钮。
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorSchemeSeed: sunlightYellow,
  scaffoldBackgroundColor: const Color(0xFFFBF6EC), // 暖米白
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFFBF6EC),
    foregroundColor: Color(0xFF5A4A2F), // 暖棕，避免纯黑标题
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  ),
);

/// 家长端配色种子：沉静青蓝（与孩子端阳光黄明显区分）。
const Color parentSeed = Color(0xFF3F7F99);

/// 家长端主题：同一浅色基调，换青蓝主色 + 冷调浅底，进家长端一眼可辨。
final ThemeData parentTheme = lightTheme.copyWith(
  colorScheme: ColorScheme.fromSeed(
    seedColor: parentSeed,
    brightness: Brightness.light,
  ),
  scaffoldBackgroundColor: const Color(0xFFEFF4F6),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFEFF4F6),
    foregroundColor: Color(0xFF27454F),
    elevation: 0,
    centerTitle: true,
  ),
);

/// 保留旧深色主题（暂未使用，避免误引用报红）。
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: sunlightYellow,
  scaffoldBackgroundColor: const Color(0xFF1B1B2F),
);
