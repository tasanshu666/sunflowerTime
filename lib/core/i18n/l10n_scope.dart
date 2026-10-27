/// 页级 L10n 范围（i18n B1 批次，架构设计「🔴 页级 L10nScope」）。
///
/// 为什么存在：现网 1783 条 widget 测试全是裸 `MaterialApp(home: XxxPage())`，
/// 不挂 `localizationsDelegates` —— 页内一旦直调 `AppLocalizations.of(ctx)` 会
/// 全量爆红。每个迁移页在外层包 [L10nScope]，页内即可经
/// `AppLocalizations.of(ctx)` 取文案，测试宿主零改动。
///
/// 🔴 **铁律**：`showDialog` / `showModalBottomSheet` / `SnackBar` 的 builder
/// 上下文在页级 scope 之外（挂在根 Navigator 上）→ **弹窗/浮层内部严禁直调
/// AppLocalizations**，文案由页级 scope 内取好经参数槽位传入（与 C105 弹窗壳
/// 「文案调用方给」同构）。
library l10n_scope;

import 'package:flutter/widgets.dart';

import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 安全取当前文案（i18n B1）：
///  · 生产 / 正常测试宿主：页级 [L10nScope] 之下 → 取 scope 内的 [AppLocalizations]；
///  · 裸 `MaterialApp` 测试宿主（无 delegates，如直接挂载 GardenPot / PlantCard
///    的既有用例）→ 回退中文 [AppLocalizationsZh]，与迁移前行为一致。
AppLocalizations l10nOf(BuildContext context) {
  try {
    return AppLocalizations.of(context);
  } catch (_) {
    return AppLocalizationsZh();
  }
}

/// 页级 L10n 包装：注入当前生效 locale 与全套本地化 delegates。
///
/// F154（2026-10-26 玄参实测反馈「切语言后家长端不切换、退出重进才切」）：
/// 本壳监听 [AppLocaleController.revision] —— 切换语言时全部已挂载的
/// L10nScope 同帧重建，`Localizations` 拿到新 locale 后按 Flutter 标准机制
/// 通知所有 `AppLocalizations.of` 依赖方刷新文案，无需退出重进。
/// 故意不用 `ref`（纯 StatelessWidget，裸测试宿主无 ProviderScope 也能挂）。
class L10nScope extends StatelessWidget {
  const L10nScope({required this.child, super.key});

  /// 页面主体。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocaleController.revision,
      builder: (BuildContext context, Widget? _) => Localizations(
        locale: AppLocaleController.current,
        delegates: AppLocalizations.localizationsDelegates,
        child: child,
      ),
    );
  }
}
