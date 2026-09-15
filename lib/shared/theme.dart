/// 应用主题（§4.1.4 低打扰、深色打盹屏基调）。
library theme;

import 'package:flutter/material.dart';

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFFF5C542), // 阳光黄
  scaffoldBackgroundColor: const Color(0xFF1B1B2F),
);

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorSchemeSeed: const Color(0xFFF5C542),
);
