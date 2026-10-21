/// 冷启动/切换语言解析纯函数单测（i18n B1，架构设计「核心数据结构」）。
///
/// 覆盖：SP 存档值往返、脏值兜底、resolveEffectiveLocale 全真值表
///（显式 zh/en / system+平台 / 测试垫片）。
library locale_resolve_test;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/app_language.dart';

void main() {
  group('appLanguageFromStored', () {
    test('null / 空串 / 脏值 → system', () {
      expect(appLanguageFromStored(null), AppLanguage.system);
      expect(appLanguageFromStored(''), AppLanguage.system);
      expect(appLanguageFromStored('junk'), AppLanguage.system);
      expect(appLanguageFromStored('ZH'), AppLanguage.system, reason: '大小写敏感，脏值兜底');
    });

    test('合法值往返（from∘to == id）', () {
      for (final AppLanguage lang in AppLanguage.values) {
        expect(appLanguageFromStored(appLanguageToKey(lang)), lang);
      }
    });
  });

  group('resolveEffectiveLocale', () {
    test('显式 zh / en 恒生效（含测试环境）', () {
      const Locale platformEn = Locale('en');
      const Locale platformZh = Locale('zh');
      expect(
        resolveEffectiveLocale(AppLanguage.zh,
            platformLocale: platformEn, isTestEnv: false),
        const Locale('zh'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.en,
            platformLocale: platformZh, isTestEnv: false),
        const Locale('en'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.en,
            platformLocale: platformZh, isTestEnv: true),
        const Locale('en'),
      );
    });

    test('system：平台 en → en，否则 zh', () {
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: const Locale('en'), isTestEnv: false),
        const Locale('en'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: const Locale('en', 'US'), isTestEnv: false),
        const Locale('en'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: const Locale('zh'), isTestEnv: false),
        const Locale('zh'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: const Locale('ja'), isTestEnv: false),
        const Locale('zh'),
      );
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: null, isTestEnv: false),
        const Locale('zh'),
      );
    });

    test('测试垫片：isTestEnv && system → zh（平台 en 也不例外）', () {
      expect(
        resolveEffectiveLocale(AppLanguage.system,
            platformLocale: const Locale('en'), isTestEnv: true),
        const Locale('zh'),
      );
    });
  });
}
