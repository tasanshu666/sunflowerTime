/// 首次启动同意流（M0 关键交付 / §10.4 合规本地化）。同意后写首启标记。
///
/// ## 视觉美化（玄参 2026-10-07）
/// 用户口径：「初次进入程序的欢迎界面请美化一下，现在看起来都是文字，而且，请把向日葵
/// 盛开的图像放进去，作为软件的标记性宠物」。
///
/// 改版前：米色纯文字页（标题 + 三行小字 + 按钮），没有形象。改版后：
///  · 顶部**向日葵盛开美术图**作为吉祥物 / 标志性形象
///    （`assets/plants/species_sunflower_adult_bloomed.png`，1200×2000，自带花盆）；
///  · 奶油暖调底 + 白色大圆角卡片承载**合规文案**；
///  · 大号琥珀色圆角主按钮；
///  · 整体仍是竖屏友好 —— `SingleChildScrollView` + `ConstrainedBox(minHeight)`，
///    矮屏（如 360×640）内容超高时**可滚动**而非溢出。
///
/// ⚠️ **合规文案一个字都不改**（隐私说明是合规内容，仅做视觉层美化）。
library consent_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/shared/language_picker.dart';

/// 页面底色（奶油暖调，与入口页 / 花园页同源）。
const Color _kCream = Color(0xFFFBF4E4);

/// 深棕正文（儿童可读主文字色）。
const Color _kBrown = Color(0xFF5D4037);

/// 主琥珀（主按钮 / 强调）。
const Color _kAmber = Color(0xFFF9A825);

/// 向日葵吉祥物图资源（1200×2000，自带花盆，盆底贴底）。
const String kConsentSunflowerAsset =
    'assets/plants/sunflower/species_sunflower_adult_bloomed.png';

/// 向日葵吉祥物图片的公开 Key（供 widget 测试定位 / 度量）。
const Key kConsentSunflowerKey = Key('consentSunflowerMascot');

/// 向日葵吉祥物**外框**（[SizedBox]）的公开 Key（供 widget 测试**度量布局尺寸**）。
///
/// ⚠️ 测试环境可能缺图 → 内含 [Image] 走 errorBuilder 回退，其渲染尺寸不再等于外框；
/// 故度量「向日葵占屏宽比例」一律以**外框**为准。
const Key kConsentSunflowerBoxKey = Key('consentSunflowerBox');

class ConsentPage extends ConsumerWidget {
  const ConsentPage({super.key, this.preview = false});

  /// **只读预览模式**（玄参 2026-10-07「打开软件直接进主页，看不到欢迎页，无法反馈」）：
  /// 由花期调试面板（`bloom_debug_panel.dart`）打开，仅做视觉预览——按钮变「返回花园」，
  /// **不写任何同意状态、不走主流程跳转**。
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // i18n（B1）：watch 界面语言 → 切换语言时本页重建，L10nScope 重新读取
    // AppLocaleController.current，文案同帧生效（仿 app.dart themeDark 的 watch 模式）。
    ref.watch(appLanguageProvider);
    // 页级 L10n 范围 —— 裸 MaterialApp 测试宿主（无 delegates）也能取
    // 文案；页内文案一律经下方 builder 上下文的 `AppLocalizations.of(ctx)`。
    return L10nScope(
      child: Scaffold(
        backgroundColor: _kCream,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // ⚠️ 文案取用点必须在 L10nScope **之内**（此处 builder 上下文已入范围）。
              final AppLocalizations l10n = AppLocalizations.of(context);
              // 向日葵宽敞度：约屏宽 42%（玄参口径 40–45%；2026-10-07 真机反馈「美术太大、
              // 缩小一些」，由原 60% 下调）。显式宽高避免 loose 约束按原图逻辑尺寸
              // （1200×2000）撑爆布局（2026-09-24 事故纪律）。
              final double screenW = constraints.maxWidth;
              final double mascotW = (screenW * 0.42).clamp(120.0, 190.0);
              return SingleChildScrollView(
              // 矮屏内容超高 → 可滚动，绝不溢出（360×640 回归）。
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      // ── 吉祥物：向日葵盛开图 ─────────────────────────────
                      _Mascot(width: mascotW),
                      const SizedBox(height: 8),
                      // ── 语言选择（i18n B1）：吉祥物下方、合规卡上方；选 zh/en
                      //    立即落盘并同帧生效；与同意标记互不耦合。
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LanguagePicker(skin: LanguagePickerSkin.segmented),
                      ),
                      Text(
                        l10n.consent_welcome_title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _kBrown,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // ── 合规文案卡（文字一字不改）──────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFFFE3B0),
                            width: 1.5,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          l10n.consent_compliance_body,
                          style: const TextStyle(
                            height: 1.8,
                            color: _kBrown,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // ── 主按钮：同意并开始 ─────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: preview
                              ? () => Navigator.of(context).maybePop()
                              : () async {
                                  await ref
                                      .read(settingsStoreProvider)
                                      .setFirstLaunchConsented(true);
                                  if (context.mounted) context.go('/');
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kAmber,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              preview
                                  ? l10n.consent_btn_back_garden
                                  : l10n.consent_btn_agree,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}

/// 吉祥物：向日葵盛开图 + 身后柔光圆（可爱、暖调）。
///
/// ⚠️ 图片**显式宽高**（[width] × 1.5 半轴），资源缺失 / 测试环境无 AssetManifest 时
/// 回退内置花卉图标（[errorBuilder]），不让测试崩。
class _Mascot extends StatelessWidget {
  const _Mascot({required this.width});

  /// 展示宽度（高度按画布 1200×2000 等比 = width × 2000/1200）。
  final double width;

  @override
  Widget build(BuildContext context) {
    // 画布 1200×2000 → 高 = 宽 × (2000/1200)。
    final double height = width * 2000 / 1200;
    return SizedBox(
      key: kConsentSunflowerBoxKey,
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 身后柔光圆（暖黄渐变），衬托吉祥物。
          Container(
            width: width * 0.72,
            height: width * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  const Color(0xFFFFF1C8),
                  _kCream.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              kConsentSunflowerAsset,
              key: kConsentSunflowerKey,
              width: width,
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) =>
                  Icon(
                Icons.local_florist,
                size: width * 0.5,
                color: const Color(0xFFF9A825),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
