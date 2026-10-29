/// 应用主题（§4.1.4 低打扰、明亮向日葵基调）。
library theme;

import 'package:flutter/material.dart';

/// 主色种子：阳光黄（品牌色）。
const Color sunlightYellow = Color(0xFFF5C542);

/// 提示条（SnackBar）配色 —— 孩子端：暖棕底 + 米白字 + 阳光黄按钮。
///
/// 为什么必须显式配：M3 浅色主题的 SnackBar 默认走 `inverseSurface`（**深灰近黑**），
/// 与暖米白 App 完全不是一个调子（玄参 2026-10-29：「这种黑色的弹窗也太丑了，
/// 不符合我这个 APP 的风格」）。这里统一换成品牌暖棕，27 处提示一处改动全生效。
const SnackBarThemeData _childSnackBarTheme = SnackBarThemeData(
  backgroundColor: Color(0xFF5A4A2F), // 与 AppBar 前景同款暖棕
  contentTextStyle: TextStyle(color: Color(0xFFFBF6EC), fontSize: 13.5),
  actionTextColor: sunlightYellow,
);

/// 提示条配色 —— 家长端：沉静青灰底 + 冷白字 + 浅青按钮（与孩子端可区分）。
const SnackBarThemeData _parentSnackBarTheme = SnackBarThemeData(
  backgroundColor: Color(0xFF27454F),
  contentTextStyle: TextStyle(color: Color(0xFFEFF4F6), fontSize: 13.5),
  actionTextColor: Color(0xFF7FC4DA),
);

/// 浅色暖黄主题（向日葵风）：暖米白底 + 阳光黄主色 + 大圆角卡片/按钮。
final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorSchemeSeed: sunlightYellow,
  scaffoldBackgroundColor: const Color(0xFFFBF6EC), // 暖米白
  snackBarTheme: _childSnackBarTheme,
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
  // 覆盖孩子端暖棕：家长端提示走青色系（copyWith 会继承 lightTheme 的值）。
  snackBarTheme: _parentSnackBarTheme,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFEFF4F6),
    foregroundColor: Color(0xFF27454F),
    elevation: 0,
    centerTitle: true,
  ),
);

/// 深色主题（孩子端）：深底 + 阳光黄点缀。
///
/// M3 修订：原先只在 `app.dart` 挂了 `theme: lightTheme`、**完全没接 `themeMode`**，
/// 于是家长端「深色主题」开关写进库却无人消费（玄参大人真机反馈「开关没变化」）。
/// 现在由 `settings.themeDark` 驱动 `MaterialApp.themeMode`，此处补齐可用的深色皮肤。
final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: sunlightYellow,
  scaffoldBackgroundColor: const Color(0xFF16162A),
  // 深色下 M3 默认提示条几乎与背景同色、辨识度差 → 提亮到卡色之上。
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF2F2F4E),
    contentTextStyle: TextStyle(color: Color(0xFFF3E3B8), fontSize: 13.5),
    actionTextColor: sunlightYellow,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF16162A),
    foregroundColor: Color(0xFFF3E3B8),
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    elevation: 1,
    color: const Color(0xFF23233C),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

/// 家长端深色主题：深蓝灰底 + 青蓝主色（与孩子端深色可区分）。
final ThemeData parentDarkTheme = darkTheme.copyWith(
  colorScheme: ColorScheme.fromSeed(
    seedColor: parentSeed,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF121A1F),
  // 家长端深色提示条：跟着青色系提亮一档。
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF20313A),
    contentTextStyle: TextStyle(color: Color(0xFFCFE3EA), fontSize: 13.5),
    actionTextColor: Color(0xFF7FC4DA),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF121A1F),
    foregroundColor: Color(0xFFCFE3EA),
    elevation: 0,
    centerTitle: true,
  ),
);

/// 按当前亮度取家长端主题（浅色 = 青蓝冷调；深色 = 家长端深色）。
ThemeData parentThemeFor(Brightness brightness) =>
    brightness == Brightness.dark ? parentDarkTheme : parentTheme;
