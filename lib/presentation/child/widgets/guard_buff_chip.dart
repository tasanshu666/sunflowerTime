/// 花园页左上角「今日 buff 增益卡」（第四批 A 引入为胶囊；B13.2 改竖排小卡；
/// 🔴 B13.5 玄参交付券卡美术 ⇒ 改**卡面图 + 券名 + 增益描述**三段卡）。
///
/// 版式（玄参 2026-11-11 原话：「在对应卡券美术素材的上面，你自己写上浇水卡券，
/// 下面写清楚 buff 增益，如今日浇水可减少1阳光消耗，方便进行中英文变换」）：
/// * 卡面图（`GuardArt.voucherCard`；浇水 / 劳动无烤字、施肥按语言选烤字版、
///   免费券复用浇水 / 施肥卡面 —— 券名与描述用自己的 ARB 文字，不混淆）；
/// * 券名（`guard_voucher_name_*`，11pt 粗体）；
/// * 增益描述（`guard_voucher_desc_*`，9pt，最多 3 行 ellipsis）。
///
/// 位置由调用方（`garden_page.dart` 左上 chips 列）决定：与既有资源 chips
/// 同列、**chips 行下方 8pt**。
///
/// ## 🔴 硬约束（踩过坑，别「优化」掉）
/// 1. **文案里绝不能出现 `×` 字符**：`weather_a3_banner_ui_test.dart` 用
///    `find.textContaining('×').first` 定位资源 chips 行、`garden_bloom_reward_ui_test`
///    断言 `find.text('×0') findsNWidgets(3)` —— 卡片里只要有一个 `×` 就会改口径。
/// 2. **高度不写死、宽度必须可收缩**：`en_overflow_probe_test.dart` 在
///    320×568 + en + 1.3 倍字号下钉死「GardenPage 无 RenderFlex overflow」。
///    宽度用 `ConstrainedBox` 封顶 + 文字 `ellipsis`（照 `guard_pill.dart`）；
///    **禁止 `FittedBox`**（`guard_pill.dart` 有禁令注释：大字号是无障碍设置）。
/// 3. **图宽随 `ConstrainedBox` 收缩、文字不乘 uiScale**（文字只走全局
///    textScaler）：双重放大会把卡片撑破。
///
/// ## 展示口径
/// · **所有券都只显示卡名 + 增益，不显示「剩 N」**（玄参 2026-11-09）；
/// · 🔴 B13.4：浇水 / 劳动券当日不限次 ⇒ **永不追加「已用完」**；
///   施肥 / 免费券额度用完时描述后追加「· 已用完」（[garden_guard_buff_exhausted]）。
library guard_buff_chip;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/entities/guard_drop.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/presentation/child/widgets/guard_art.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 今日 buff 增益卡（纯展示，**不碰任何服务 / 账本**）。
class GuardBuffChip extends StatelessWidget {
  /// 度量 / 查找用的稳定 Key（测试据此断言「券是否仍在屏上」）。
  static const Key chipKey = Key('gardenGuardBuffChip');

  /// 今日 buff 快照（调用方保证非 null 且 `kind != none`）。
  final GuardBuffState buff;

  const GuardBuffChip({super.key, required this.buff});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final GuardDropKind kind = buff.kind;
    final bool isZh = Localizations.localeOf(context).languageCode == 'zh';
    if (GuardVoucherKind.of(kind) == null) return const SizedBox.shrink();

    // 🔴 B13.2/13.5：宽度封顶 + ellipsis（en + 1.3 大字号不撑破花园浮层）。
    // 🔴 B13.5：整卡 `IgnorePointer` —— 卡是**纯展示**（doc 注释第一条），
    //    且 B13.5 起卡面高约 200pt，挂在左上 chips 列下会与第一排花盆的
    //    语义区重叠；不加穿透会让「点第一盆花」在卡区域直接失效
    //    （guard_voucher_garden_wiring_test ⑤/⑭ 抓过：tap 落在卡的 RenderImage 上）。
    return IgnorePointer(
      child: Material(
        key: chipKey,
        color: const Color(0xFFFFFBF1),
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8A600), width: 1.5),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 120 * uiScaleOf(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ① 券卡面（顶随容器圆角裁切；缺失回退金色块，不 crash）。
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12.5),
                  ),
                  child: GuardArt.voucherCard(kind, isZh: isZh),
                ),
                // ② 券名（硬约束 1：无 ×；硬约束 2：ellipsis 收缩）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
                  child: Text(
                    nameOf(kind, t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B4A00),
                    ),
                  ),
                ),
                // ③ 增益描述（最多 3 行；用完的非不限次券追加「· 已用完」）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 7),
                  child: Text(
                    descLineOf(kind, buff, t),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1.3,
                      color: Color(0xFF6B6252),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  /// 增益描述行（🔴 单点：不限次券（浇水 / 劳动，B13.4）永不追加「已用完」；
  /// 施肥 / 免费券额度用完时追加「· 已用完」）。
  static String descLineOf(
    GuardDropKind kind,
    GuardBuffState buff,
    AppLocalizations t,
  ) {
    final bool unlimited = GuardVoucherKind.of(kind)?.isUnlimitedDaily ?? false;
    final String base = descOf(kind, t);
    if (unlimited || !buff.isExhausted) return base;
    return '$base · ${t.garden_guard_buff_exhausted}';
  }
}
