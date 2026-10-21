/// 应用壳：Riverpod ProviderScope + Theme + Router（§5 T01）。
///
/// M3 修订：主题模式由 `settings.themeDark` 驱动（原先只挂了 `theme: lightTheme`，
/// 家长端深色开关写进库却无人消费 → 真机反馈「开关没变化」）。
library app;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/shared/app_router.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/shared/theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // 设置尚未读出时回落浅色（默认皮肤），避免首帧闪深色。
    // 家长端设置页保存后 invalidate 本 Provider，切换即时生效。
    final bool dark = ref.watch(settingsProvider).value?.themeDark ?? false;
    // i18n（B1 批次）：界面语言 —— watch appLanguageProvider（切换语言时本壳
    // 重建 → locale 即时生效）；生效值与页级 L10nScope 的 AppLocaleController.current
    // 同源同向（都走 resolveEffectiveLocale 纯函数，测试垫片口径一致）。
    final AppLanguage lang = ref.watch(appLanguageProvider);
    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).app_title,
      locale: AppLocaleController.localeFor(lang),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // C65（2026-10-13 玄参 iPad 实测拍板）：**平板全局放大字号**。
      // F129（2026-10-19 玄参 iPad Pro 13″ 实测）：倍率不再固定 1.3，改为
      // **随屏短边派生**（834 = iPad 11″ → 1.3 ／ 1032 = iPad 13″ → 1.6）。
      //
      // 为什么放在这里（单点）：平板逻辑尺寸远大于手机而字号不变 → 一切文字「相对
      // 屏幕」偏小。用 `MediaQuery.textScaler` 一处注入 → 全 App（孩子端 5 tab +
      // 家长端 + 专注/护眼/结算 + 弹窗）的 `Text` 自动等比放大，页面代码零改动。
      //
      // ⚠️ 三条纪律：
      //  ① **仅平板**：手机端直接 `return child`（不包 MediaQuery）→ 零像素回归；
      //  ② 与设备自带缩放**相乘**再钳上限（见 `tabletTextScaler`），不覆盖无障碍设置；
      // ③ 只放大**文字**：素材图片/徽标等定尺寸元素要各自乘 `uiScaleOf(context)`
      //     （文字会自动缩、图片不会），否则出现「字大了图标还那么小」。
      // ④ **判定、倍率派生与钳制全部收口在 `applyTabletTextScaling`**（纯函数，可单测），
      //     本处只负责把它包成 `MediaQuery`；写在这里的只有「壳」。
      //     ⚠️ F129 起**不要**在这里自行算倍率 —— 尺寸（`mq.size`）必须交给注入点，
      //     否则又会出现「换台大平板就重新配一次」的老问题。
      builder: (BuildContext context, Widget? child) {
        final Widget content = child ?? const SizedBox.shrink();
        final MediaQueryData mq =
            MediaQuery.maybeOf(context) ?? const MediaQueryData();
        final MediaQueryData scaled = applyTabletTextScaling(mq);
        if (identical(scaled, mq)) return content; // 手机：不引入 MediaQuery
        return MediaQuery(data: scaled, child: content);
      },
    );
  }
}
