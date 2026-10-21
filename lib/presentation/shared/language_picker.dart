/// 界面语言选择控件（i18n B1 批次）：欢迎页分段样式 + 家长设置对话框样式
/// 两套皮肤，同一数据源（[AppLanguage.values] 展示序，永不重排）与同一写入口。
library language_picker;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/core/i18n/app_locale_controller.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 皮肤。
enum LanguagePickerSkin {
  /// 欢迎页分段样式（`SegmentedButton` 三选）。
  segmented,

  /// 家长设置对话框样式（单选列表）。
  dialogList,
}

/// 界面语言选择控件。
///
/// 写入口统一为 [applyLanguage]：① `AppLocaleController.set`（SP 落盘 + 静态
/// current）② 同步 `appLanguageProvider` —— 测试宿主没有 `main` 注入的
/// [AppLocaleController.onChanged] 回调，此处显式兜底同步，两条路径幂等无冲突。
class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({required this.skin, super.key});

  /// 皮肤（欢迎页分段 / 家长设置对话框）。
  final LanguagePickerSkin skin;

  /// 统一写入口：内存态 + 持久化 + Riverpod 同步（幂等）。
  static Future<void> applyLanguage(WidgetRef ref, AppLanguage lang) async {
    await AppLocaleController.set(lang);
    ref.read(appLanguageProvider.notifier).state = lang;
  }

  /// 选项展示文案（zh/en 两种语言名固定原文展示，不做翻译；
  /// 「跟随系统」与「简体中文」走 ARB，英文名 `English` 本就是英文不译）。
  static String labelOf(AppLocalizations l10n, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.system:
        return l10n.shared_lang_follow_system;
      case AppLanguage.zh:
        return l10n.shared_lang_zh_name;
      case AppLanguage.en:
        return 'English';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLanguage current = ref.watch(appLanguageProvider);
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (skin) {
      case LanguagePickerSkin.segmented:
        return SegmentedButton<AppLanguage>(
          segments: AppLanguage.values
              .map<ButtonSegment<AppLanguage>>(
                (AppLanguage lang) => ButtonSegment<AppLanguage>(
                  value: lang,
                  label: Text(labelOf(l10n, lang)),
                ),
              )
              .toList(),
          selected: <AppLanguage>{current},
          onSelectionChanged: (Set<AppLanguage> selection) {
            applyLanguage(ref, selection.first);
          },
        );
      case LanguagePickerSkin.dialogList:
        // v3.32+ 弃用 RadioListTile.groupValue/onChanged → 统一走 RadioGroup。
        return RadioGroup<AppLanguage>(
          groupValue: current,
          onChanged: (AppLanguage? next) {
            if (next != null) {
              applyLanguage(ref, next);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppLanguage.values
                .map<Widget>(
                  (AppLanguage lang) => RadioListTile<AppLanguage>(
                    title: Text(labelOf(l10n, lang)),
                    value: lang,
                  ),
                )
                .toList(),
          ),
        );
    }
  }
}

/// 家长设置页「语言」入口对话框。
///
/// 🔴 弹窗纪律：builder 上下文在页级 scope 之外 → 标题 / 确定按钮文案由**调用方
/// 页面上下文**（[context]）取好后经参数传入；对话框内仅语言选项控件，用
/// [L10nScope] 自行包装（基础设置面板，可自取）。
Future<void> showLanguageDialog(
  BuildContext context,
  WidgetRef ref,
) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(l10n.shared_lang_title),
      content: const SizedBox(
        width: 320,
        child: L10nScope(
          child: LanguagePicker(skin: LanguagePickerSkin.dialogList),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.shared_ok),
        ),
      ],
    ),
  );
}
