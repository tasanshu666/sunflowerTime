/// 应用壳：Riverpod ProviderScope + Theme + Router（§5 T01）。
///
/// M3 修订：主题模式由 `settings.themeDark` 驱动（原先只挂了 `theme: lightTheme`，
/// 家长端深色开关写进库却无人消费 → 真机反馈「开关没变化」）。
library app;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
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
    return MaterialApp.router(
      title: 'SunFocus 向日葵专注',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // C65（2026-10-13 玄参 iPad 实测拍板）：**平板全局放大字号 1.3×**。
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
      // ④ **判定与钳制全部收口在 `applyTabletTextScaling`**（纯函数，可单测），
      //     本处只负责把它包成 `MediaQuery`；写在这里的只有「壳」。
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
