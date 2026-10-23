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
/// ⚠️ **合规摘要文案一个字都不改**（隐私说明是合规内容，仅做视觉层美化）。
///
/// ## 首启告知 2.0（玄参 2026-10-23 拍板「按建议做」，口径 C110）
/// 在 v1 美化版基础上补四块（只增不改）：
///  1. **「不同意」选项**：主按钮旁新增次按钮 → 说明卡（数据仅存本机、不同意
///     无法使用）+「再想想 / 退出应用」（`SystemNavigator.pop`）；
///  2. **条款应用内入口**：「查看完整隐私政策 ›」→ `/privacy-policy` 全文页；
///  3. **数据清单颗粒度**：合规摘要下新增「这个应用里有哪些数据」4 行清单；
///  4. **版本三要素 + 重弹**：同意状态改 `acceptCurrentPolicyConsent()`（版本号
///     + 时刻）；老版本升级 / 政策重大变更（记录版本 < 当前版本）时顶部展示
///     「政策已更新」提示条。
library consent_page;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
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

/// 「查看完整隐私政策」入口的公开 Key（供测试定位）。
const Key kConsentViewPolicyKey = Key('consentViewPolicy');

/// 「不同意」次按钮的公开 Key（供测试定位）。
const Key kConsentDisagreeKey = Key('consentDisagree');

/// 「政策已更新」提示条的公开 Key（重弹场景供测试定位；首启/预览不出现）。
const Key kConsentUpdateNoticeKey = Key('consentUpdateNotice');

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
                      const SizedBox(height: 12),
                      // ── 「政策已更新」提示条（首启告知 2.0 / C110）─────────
                      // 仅重弹场景（记录版本落后于当前版本）出现；preview 模式
                      // 不读同意状态（只读预览纪律），恒不显示。
                      if (!preview) const _UpdateNotice(),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      // ── 数据清单（颗粒度 / C110）：只增不改，摘要卡一字未动 ──
                      _DataInventory(l10n: l10n),
                      const SizedBox(height: 8),
                      // ── 条款应用内入口：政策全文页（双向免同意守卫）────────
                      // 预览模式同样可点（C110-F1：玄参目验要预览政策页整改效果）。
                      TextButton(
                        key: kConsentViewPolicyKey,
                        onPressed: () => context.push('/privacy-policy'),
                        child: Text(
                          l10n.consent_view_policy,
                          style: const TextStyle(color: _kBrown),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ── 按钮区（C110）：不同意（次）+ 同意并开始（主）──────
                      // preview（调试预览）保持单按钮「返回花园」，不写任何状态。
                      if (preview)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).maybePop(),
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
                                l10n.consent_btn_back_garden,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                key: kConsentDisagreeKey,
                                onPressed: () => _showDeclineDialog(
                                    context, l10n),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kBrown,
                                  side: const BorderSide(color: Color(0xFFD8C9A8)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  child: Text(
                                    l10n.consent_btn_disagree,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  await ref
                                      .read(settingsStoreProvider)
                                      .acceptCurrentPolicyConsent();
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  child: Text(
                                    l10n.consent_btn_agree,
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

/// 「政策已更新」提示条：记录的同意版本 > 0 且落后于当前内置版本（[kPrivacyPolicyVersion]）
/// 时显示（= 老用户升级 / 政策重大变更重弹，§10.3 重新确认机制）。
///
/// 只读 FutureBuilder（不缓存不重试）；preview 模式在调用点已排除。
class _UpdateNotice extends ConsumerWidget {
  const _UpdateNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(settingsStoreProvider).consentedPolicyVersion(),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        final int version = snap.data ?? 0;
        // 首启（0）或已记录当前版本（Future 竞态防御）→ 不显示。
        if (version <= 0 || version >= kPrivacyPolicyVersion) {
          return const SizedBox.shrink();
        }
        final AppLocalizations l10n = AppLocalizations.of(context);
        return Container(
          key: kConsentUpdateNoticeKey,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1C8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF9A825), width: 1.2),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.info_outline,
                  size: 20, color: Color(0xFFB37A12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.consent_update_notice('v$kPrivacyPolicyVersion'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF8A5B0B),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 数据清单卡（颗粒度 / C110）：把合规摘要里「收集什么」展开成 4 行具体条目。
/// 与摘要卡是**总-分**关系：摘要一字不改，清单只列不承诺新内容。
class _DataInventory extends StatelessWidget {
  const _DataInventory({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String)> rows = <(IconData, String)>[
      (Icons.timer_outlined, l10n.consent_data_focus),
      (Icons.local_florist_outlined, l10n.consent_data_garden),
      (Icons.lock_outline, l10n.consent_data_local),
      (Icons.block_outlined, l10n.consent_data_none),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE3B0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.consent_data_title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _kBrown,
            ),
          ),
          const SizedBox(height: 8),
          for (final (IconData icon, String text) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 16, color: const Color(0xFF8D6E63)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: _kBrown,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 「不同意」说明卡：讲清「本应用数据仅存本机、不同意无法使用」，给两条出路
/// ——「再想想」（默认动作，回同意页）与「退出应用」（`SystemNavigator.pop`；
/// iOS 平台可能不响应系统级退出，属平台行为，页面本身仍可停在同意页）。
Future<void> _showDeclineDialog(
  BuildContext context,
  AppLocalizations l10n,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(l10n.consent_decline_title),
        content: Text(l10n.consent_decline_body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.consent_decline_stay),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              SystemNavigator.pop();
            },
            child: Text(l10n.consent_decline_exit),
          ),
        ],
      );
    },
  );
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
