/// 花园页左上角「今日 buff 增益卡」（第四批 A 引入为胶囊；B13.2 改竖排小卡；
/// 🔴 **B13.9 改「小图标 + 右侧文字」横排** —— 玄参原话「图标缩小到现在的一半，
/// 图标右边直接文字显示：今日浇水-1阳光（UI）」）。
///
/// 版式演进：B13.5 三段卡（宽 120）→ B13.6 截图样式（宽 88）→ B13.7 迷你卡
/// （宽 48）→ B13.8 翻转卡（正面插画 / 点击翻面）→ **B13.9 横排卡**：翻转卡
/// 退役（玄参反馈「不要点击翻面这种交互」），改为：
/// * **左侧图标** = 券卡插画缩到 **24** 宽（48 的一半，AspectRatio 276/294）；
/// * **右侧单行文字** = 「今日浇水 −1☀」（`guard_chip_inline_prefix` + `shortOf`
///   + `effectValueOf` 组装，☀ 用 `assets/rewards/sunlight.png` 的 `WidgetSpan`
///   内联小图，缺失回退内置 `Icons.wb_sunny`）。
/// * **无点击行为** ⇒ 🔴 **整卡包回 `IgnorePointer`**（B13.8 为翻转删过一次；
///   历史上它挡过花盆点击，横排纯展示必须包回去 —— 改动时重跑
///   `guard_voucher_garden_wiring_test` ⑤/⑭ 花盆点击用例确认）。
/// * 「· 已用完」态保留：灰显 + 文案，判定单点 [GuardBuffChip.usedUpOf]
///   （与 [GuardBuffChip.descLineOf] 共用，B13.4 不限次口径不变）。
///
/// ## 🔴 B13.8 素材二次裁切教训（仍有效）
/// 素材源图此前 328×475（带上下空白带），已 PIL 裁成 **276×294**（只剩中间
/// 插画：黄底面板 + 图案，无边框无文字）。代码里所有引用 328/475 的宽高比
/// 已统一改为 276/294。再从源目录拷图必须核对尺寸，别直接覆盖！
///
/// ## 🔴 硬约束（踩过坑，别「优化」掉）
/// 1. **文案里绝不能出现 `×` 字符**：`weather_a3_banner_ui_test.dart` 用
///    `find.textContaining('×').first` 定位资源 chips 行、`garden_bloom_reward_ui_test`
///    断言 `find.text('×0') findsNWidgets(3)` —— 卡片里只要有一个 `×` 就会改口径。
///    （横排文字同样受此约束；`shortOf` / `effectValueOf` 都不含 `×`。）
/// 2. **高度不写死、宽度必须可收缩**：`en_overflow_probe_test.dart` 在
///    320×568 + en + 1.3 倍字号下钉死「GardenPage 无 RenderFlex overflow」。
///    宽度用 `ConstrainedBox` 封顶 + 文字 `ellipsis`；**禁止 `FittedBox`**
///    （大字号是无障碍设置）。
/// 3. **图宽随 `ConstrainedBox` 收缩、文字不乘 uiScale**（文字只走全局
///    textScaler）：双重放大会把卡片撑破。
///
/// ## 展示口径
/// · **不显示「剩 N」**（玄参 2026-11-09）；
/// · 🔴 B13.4：浇水 / 劳动券当日不限次 ⇒ **永不出现「已用完」**（横排同样遵守）。
library guard_buff_chip;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart'
    show
        kGuardFertilizerVoucherSave,
        kGuardLaborVoucherBonus,
        kGuardWaterVoucherSave;
import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 券名 / 增益的红色（玄参截图取色：亮正红）。
const Color _kRedText = Color(0xFFD93025);

/// 「已用完」态的灰（正文与数值同步灰显，图标随之降透明度）。
const Color _kGreyText = Color(0xFF9A8F7F);

/// 阳光 UI 小图标的素材路径（B13.9 横排文字尾部内联 ☀，与花园余额行同源）。
const String _kSunAsset = 'assets/rewards/sunlight.png';

/// 今日 buff 增益卡（**B13.9 横排卡**：左小图标 + 右单行文字；纯展示，
/// **不碰任何服务 / 账本**，`IgnorePointer` 整卡放行下层手势）。
class GuardBuffChip extends StatelessWidget {
  /// 度量 / 查找用的稳定 Key（测试据此断言「券是否仍在屏上」）。
  static const Key chipKey = Key('gardenGuardBuffChip');

  /// 今日 buff 快照（调用方保证非 null 且 `kind != none`）。
  final GuardBuffState buff;

  const GuardBuffChip({super.key, required this.buff});

  /// 券名（纯函数，便于单测；无道具档返回空串 = 调用方不渲染）。
  static String nameOf(GuardDropKind kind, AppLocalizations t) {
    switch (GuardVoucherKind.of(kind)) {
      case GuardVoucherKind.water:
        return t.guard_voucher_name_water;
      case GuardVoucherKind.labor:
        return t.guard_voucher_name_labor;
      case GuardVoucherKind.fertilize:
        return t.guard_voucher_name_fertilize;
      case GuardVoucherKind.freeWater:
        return t.guard_voucher_name_free_water;
      case GuardVoucherKind.freeFertilize:
        return t.guard_voucher_name_free_fertilize;
      case null:
        return '';
    }
  }

  /// 迷你卡**正面标题**（B13.7 遗留纯函数；B13.9 横排不直接用，测试/详情复用）：
  /// 付费券用全名（浇水卡券，4 字放得下），免费券用短名（「免费浇水」）。
  static String titleOf(GuardDropKind kind, AppLocalizations t) {
    switch (GuardVoucherKind.of(kind)) {
      case GuardVoucherKind.water:
        return t.guard_voucher_name_water;
      case GuardVoucherKind.labor:
        return t.guard_voucher_name_labor;
      case GuardVoucherKind.fertilize:
        return t.guard_voucher_name_fertilize;
      case GuardVoucherKind.freeWater:
        return t.guard_voucher_short_free_water;
      case GuardVoucherKind.freeFertilize:
        return t.guard_voucher_short_free_fertilize;
      case null:
        return '';
    }
  }

  /// 迷你卡**短动作词**（B13.7：「浇水 -1 阳光」里的「浇水」；B13.9 横排组装用）。
  static String shortOf(GuardDropKind kind, AppLocalizations t) {
    switch (GuardVoucherKind.of(kind)) {
      case GuardVoucherKind.water:
        return t.guard_voucher_short_water;
      case GuardVoucherKind.labor:
        return t.guard_voucher_short_labor;
      case GuardVoucherKind.fertilize:
        return t.guard_voucher_short_fertilize;
      case GuardVoucherKind.freeWater:
        return t.guard_voucher_short_water;
      case GuardVoucherKind.freeFertilize:
        return t.guard_voucher_short_fertilize;
      case null:
        return '';
    }
  }

  /// 迷你卡**数值**（字符串，符号内嵌）：从常量派生，**禁写死**。
  /// 浇水 −1 / 除草 +1 / 施肥 −2 / 免费券 0（= 该动作花 0 ☀）。
  /// 🔴 符号口径与 [descLineOf] 一致：浇水 / 施肥类是省（−N），劳动类是加（+N）。
  static String effectValueOf(GuardDropKind kind) {
    switch (GuardVoucherKind.of(kind)) {
      case GuardVoucherKind.water:
        return '-$kGuardWaterVoucherSave';
      case GuardVoucherKind.labor:
        return '+$kGuardLaborVoucherBonus';
      case GuardVoucherKind.fertilize:
        return '-$kGuardFertilizerVoucherSave';
      case GuardVoucherKind.freeWater:
      case GuardVoucherKind.freeFertilize:
        return '0';
      case null:
        return '';
    }
  }

  /// 增益描述（纯函数，便于单测；无道具档返回空串）。
  static String descOf(GuardDropKind kind, AppLocalizations t) {
    switch (GuardVoucherKind.of(kind)) {
      case GuardVoucherKind.water:
        return t.guard_voucher_desc_water;
      case GuardVoucherKind.labor:
        return t.guard_voucher_desc_labor;
      case GuardVoucherKind.fertilize:
        return t.guard_voucher_desc_fertilize;
      case GuardVoucherKind.freeWater:
        return t.guard_voucher_desc_free_water;
      case GuardVoucherKind.freeFertilize:
        return t.guard_voucher_desc_free_fertilize;
      case null:
        return '';
    }
  }

  /// 「已用完」判定单点（🔴 B13.9 横排卡与 [descLineOf] 共用）：不限次券
  /// （浇水 / 劳动，B13.4）永不「已用完」；施肥 / 免费券额度用完才算。
  static bool usedUpOf(GuardDropKind kind, GuardBuffState buff) {
    final bool unlimited = GuardVoucherKind.of(kind)?.isUnlimitedDaily ?? false;
    return !unlimited && buff.isExhausted;
  }

  /// 增益描述行（🔴 单点：不限次券（浇水 / 劳动，B13.4）永不追加「已用完」；
  /// 施肥 / 免费券额度用完时追加「· 已用完」）。
  static String descLineOf(
    GuardDropKind kind,
    GuardBuffState buff,
    AppLocalizations t,
  ) {
    final String base = descOf(kind, t);
    if (!usedUpOf(kind, buff)) return base;
    return '$base · ${t.garden_guard_buff_exhausted}';
  }

  /// 横排文字的**纯文本段**（不含尾部 ☀ 小图）：
  /// `guard_chip_inline_prefix(action: shortOf + ' ' + effectValueOf)` ——
  /// zh = 「今日浇水 −1」、en = 「Today: Watering −1」（语序由 ARB 决定）。
  ///
  /// 已用完态在其后追加「 · 已用完」（文案单点 [descLineOf] 同源判定）。
  static String inlineTextOf(
    GuardDropKind kind,
    GuardBuffState buff,
    AppLocalizations t,
  ) {
    final String action =
        '${shortOf(kind, t)} ${effectValueOf(kind)}'.trim();
    String line = t.guard_chip_inline_prefix(action);
    if (usedUpOf(kind, buff)) {
      line += ' · ${t.garden_guard_buff_exhausted}';
    }
    return line;
  }

  /// 尾部内联 ☀ 小图（WidgetSpan 用；素材缺失回退内置图标，不 crash）。
  static Widget inlineSunGlyph({double size = 10}) {
    return Image.asset(
      _kSunAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.wb_sunny, size: 10, color: Color(0xFFE8A600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final GuardDropKind kind = buff.kind;
    final bool isZh = Localizations.localeOf(context).languageCode == 'zh';
    if (GuardVoucherKind.of(kind) == null) return const SizedBox.shrink();

    final bool exhausted = usedUpOf(kind, buff);
    final Color textColor = exhausted ? _kGreyText : _kRedText;

    return Material(
      key: GuardBuffChip.chipKey,
      // 🔴 B13.16（玄参截图反馈「开出 2 个 buff 卡后在植物上显示的有点看不清」）：
      //    旧版 Material 透明只有投影，红色文字直接叠在植物叶片上 ⇒ 撞色看不清。
      //    改为**实底白卡**（奶油风 0.96 白 + 10 圆角，与守卫结算卡同族）——
      //    文字永远坐在自己的底色上，不与背景撞色。内边距 h6/v3 让白底完整包住
      //    文字与图标；maxWidth 封顶不变（en 大字号溢出探针仍受控）。
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 2,
      shadowColor: const Color(0x40000000),
      borderRadius: BorderRadius.circular(10),
      // 🔴 B13.9：横排**无点击行为** ⇒ 整卡 IgnorePointer（放行下层手势，
      // 花盆点击测试 ⑤/⑭ 回归覆盖）。
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 132 * uiScaleOf(context)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 左：券卡插画缩半（B13.8 宽 48 → **24**，美术原比 276:294）。
              SizedBox(
                width: 24 * uiScaleOf(context),
                child: AspectRatio(
                  aspectRatio: 276 / 294,
                  child: GuardArt.voucherCard(kind, isZh: isZh),
                ),
              ),
              const SizedBox(width: 4),
              // 右：单行文字「今日浇水 −1☀」，☀ 用素材内联小图（WidgetSpan）。
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: inlineTextOf(kind, buff, t),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                    children: <InlineSpan>[
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: exhausted
                            ? Opacity(
                                opacity: 0.45,
                                child: inlineSunGlyph(),
                              )
                            : inlineSunGlyph(),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
