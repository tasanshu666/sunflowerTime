/// 界面语言选择（i18n B1 批次，架构设计「核心数据结构」）。
///
/// 纯 Dart 文件（零 Flutter / Riverpod 依赖），可被领域无关的单测直接验证。
/// 序即 UI 展示序（跟随系统 / 简体中文 / English），**永不重排**（纪律同
/// `RequestStatus` 等按序落库的枚举）。
library app_language;

import 'dart:ui' show Locale;

/// 用户可选的界面语言。
enum AppLanguage { system, zh, en }

/// SP 存档值 → 枚举：null / 脏值（手工改 SP、老版本遗留）一律回 [AppLanguage.system]。
AppLanguage appLanguageFromStored(String? key) {
  switch (key) {
    case 'zh':
      return AppLanguage.zh;
    case 'en':
      return AppLanguage.en;
    default:
      return AppLanguage.system;
  }
}

/// 枚举 → SP 存档值（[appLanguageFromStored] 的逆运算，二者必须互逆）。
String appLanguageToKey(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.system:
      return 'system';
    case AppLanguage.zh:
      return 'zh';
    case AppLanguage.en:
      return 'en';
  }
}

/// 解析「用户选择 → 生效 locale」（纯函数，可单测）。
///
/// 规则（架构设计定稿）：
///  · zh → zh / en → en（显式选择恒生效）；
///  · system → 平台 locale 为 en 时用 en，否则 zh（默认语言 = zh）；
///  · `isTestEnv && system` → zh（**测试垫片**：测试宿主平台 locale 常为 en，
///    为保 1783 条 zh 断言零改动，测试中「跟随系统」恒解析为 zh）。
Locale resolveEffectiveLocale(
  AppLanguage lang, {
  required Locale? platformLocale,
  required bool isTestEnv,
}) {
  switch (lang) {
    case AppLanguage.zh:
      return const Locale('zh');
    case AppLanguage.en:
      return const Locale('en');
    case AppLanguage.system:
      if (isTestEnv) {
        return const Locale('zh');
      }
      final String? code = platformLocale?.languageCode;
      return code == 'en' ? const Locale('en') : const Locale('zh');
  }
}
