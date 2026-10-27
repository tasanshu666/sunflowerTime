/// 生效 locale 运行期单点（i18n B1 批次，架构设计「核心数据结构」）。
///
/// 三个内存源必须**同源同向**（谁也不能漂移）：
///  1. [AppLocaleController.current] —— 页级 [L10nScope]（裸测试宿主无 app 壳）消费；
///  2. `appLanguageProvider`（Riverpod）—— App 壳 `locale:` 消费；
///  3. SP 存档 —— 冷启动恢复。
///
/// [set] 同时推进 ①②③（①②立即、③异步落盘），冷启动由 `main` 调 [init] 一次性
/// 对齐三者。测试宿主不跑 `main`，此时 [current] 默认 = 测试垫片 zh，[onChanged]
/// 为 null（控件层自行同步 provider，见 `language_picker.dart`）。
library app_locale_controller;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;

import 'package:sunflower_time/core/i18n/app_language.dart';
import 'package:sunflower_time/data/local/settings_store.dart';

class AppLocaleController {
  AppLocaleController._();

  /// 是否处于 Flutter 测试环境（`flutter test` 会注入 FLUTTER_TEST 环境变量）。
  static final bool isTestEnv = _detectTestEnv();

  static bool _detectTestEnv() {
    if (kIsWeb) {
      return false;
    }
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// 平台 locale（无绑定/异常时回 null，[resolveEffectiveLocale] 自行兜底 zh）。
  static Locale? get _platformLocale {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale;
    } catch (_) {
      return null;
    }
  }

  /// 当前用户选择（默认「跟随系统」）。
  static AppLanguage _language = AppLanguage.system;

  /// 当前生效 locale（[L10nScope] / App 壳消费）。
  ///
  /// 默认值 = 测试垫片 zh：测试宿主不跑 `main`（无 [init]），裸泵页面时
  /// 文案恒为现网中文，1783 条 zh 断言零改动。
  static Locale current = resolveEffectiveLocale(
    AppLanguage.system,
    platformLocale: null,
    isTestEnv: isTestEnv,
  );

  /// [set] 变更后的回调（`main` 注入：同步 `appLanguageProvider`；测试宿主为 null）。
  static void Function(AppLanguage lang)? onChanged;

  /// 生效 locale 变更通知（i18n F154）。
  ///
  /// 为什么需要：页级 [L10nScope] 用自己的 `Localizations` 遮蔽了 App 壳那层，
  /// 而 L10nScope 原来只在自身重建时才重读 [current] —— 已挂载的页面在切换
  /// 语言后不重建就永远显示旧语言（家长端实测：切英文后本页不切，退出重进才切）。
  /// [_apply] 推进本计数，L10nScope 监听后整体重建 → 全 App 文案同帧切换。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 持久化后端（`main` 经 [init] 注入；测试宿主为 null = 不落盘）。
  static SettingsStore? _store;

  /// 当前用户选择（诊断 / 展示用）。
  static AppLanguage get language => _language;

  /// 冷启动初始化：绑定存档语言与持久化后端（幂等，仅 `main` 调用一次）。
  static void init(AppLanguage lang, {SettingsStore? store}) {
    _store = store;
    _apply(lang);
  }

  /// 切换界面语言：① SP 落盘 ② 更新静态 current ③ 同步 Riverpod（经回调）。
  ///
  /// 持久化失败静默降级（内存态已生效，重启回旧值，不阻塞 UI）。
  static Future<void> set(AppLanguage lang) async {
    _apply(lang);
    final SettingsStore? store = _store;
    if (store != null) {
      try {
        await store.setAppLanguage(lang);
      } catch (_) {
        // 落盘失败不回滚内存态：本次会话仍按新语言显示。
      }
    }
    final void Function(AppLanguage lang)? hook = onChanged;
    if (hook != null) {
      hook(lang);
    }
  }

  /// 由「用户选择」解析生效 locale（App 壳按 `appLanguageProvider` 值调用，
  /// 与 [current] 同源同向——都走 [resolveEffectiveLocale] 纯函数）。
  static Locale localeFor(AppLanguage lang) => resolveEffectiveLocale(
        lang,
        platformLocale: _platformLocale,
        isTestEnv: isTestEnv,
      );

  /// 内部：同步用户选择与生效 locale。
  static void _apply(AppLanguage lang) {
    _language = lang;
    current = resolveEffectiveLocale(
      lang,
      platformLocale: _platformLocale,
      isTestEnv: isTestEnv,
    );
    revision.value++; // 通知 L10nScope 重建（F154 语言即时切换）
  }
}
