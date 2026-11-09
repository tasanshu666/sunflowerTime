/// 花园页左上角「今日券」小胶囊（第四批 A）。
///
/// 位置由调用方（`garden_page.dart` 根 Stack 的那个 `Positioned`）决定：
/// 与既有资源 chips 同一列、**chips 行下方 8pt**。样式照抄 `_SeedCountChip`
/// （白 88% 底 + 圆角 20 + elevation 2 + `Padding(8, 6)`）。
///
/// ## 🔴 三条硬约束（踩过坑，别「优化」掉）
/// 1. **文案里绝不能出现 `×` 字符**：`weather_a3_banner_ui_test.dart` 用
///    `find.textContaining('×').first` 定位资源 chips 行、`garden_bloom_reward_ui_test`
///    断言 `find.text('×0') findsNWidgets(3)` —— chip 里只要有一个 `×` 就会改口径。
/// 2. **高度不写死、宽度必须可收缩**：`en_overflow_probe_test.dart` 在
///    320×568 + en + 1.3 倍字号下钉死「GardenPage 无 RenderFlex overflow」。
///    靠 `Padding` 撑高、文字用 `Flexible` + `ellipsis`（照 `guard_pill.dart`）；
///    **禁止 `FittedBox`**（`guard_pill.dart` 有禁令注释：大字号是无障碍设置）。
/// 3. **图标乘 `uiScaleOf(context)`、文字不乘**（文字只走全局 textScaler）：
///    双重放大会把胶囊撑破。
///
/// ## 展示口径
/// · 🔴 **所有券都只显示 buff 本身，不显示「剩 N」**（玄参 2026-11-09：
///   劳动券「剩 4」与浇水券「剩 6」先后去掉；剩余额度仍在存档记账、
///   只影响确认卡价格计算，不上屏）；
/// · 额度用完（[GuardBuffState.isExhausted]）时券**仍然显示**，只在文案后追加
///   「· 已用完」——「用完了」与「从来没有」是两种不同的展示。
library guard_buff_chip;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/i18n/l10n_scope.dart' show l10nOf;
import 'package:sunflower_time/domain/entities/guard_day_state.dart';
import 'package:sunflower_time/domain/services/guard_voucher.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/shared/responsive.dart';

/// 今日券胶囊（纯展示，**不碰任何服务 / 账本**）。
class GuardBuffChip extends StatelessWidget {
  /// 度量 / 查找用的稳定 Key（测试据此断言「券是否仍在屏上」）。
  static const Key chipKey = Key('gardenGuardBuffChip');

  /// 今日 buff 快照（调用方保证非 null 且 `kind != none`）。
  final GuardBuffState buff;

  const GuardBuffChip({super.key, required this.buff});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = l10nOf(context);
    final String label = labelOf(buff, t);
    if (label.isEmpty) return const SizedBox.shrink();
    return Material(
      key: chipKey,
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 阳光图标（与资源 chips 同源；缺失回退内置太阳 Icon）。
            // C65：图标显式乘平板倍率，文字由 textScaler 自动放大。
            Image.asset(
              'assets/rewards/sunlight.png',
              width: 16 * uiScaleOf(context),
              height: 16 * uiScaleOf(context),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  Icon(
                Icons.wb_sunny,
                size: 16 * uiScaleOf(context),
                color: const Color(0xFFF0A500),
              ),
            ),
            const SizedBox(width: 3),
            // 🔴 Flexible + ellipsis：窄屏 / 大字号下**收缩**而不是溢出。
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B6252),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 券 → 文案（纯函数，便于单测；未知 / 无道具档返回空串 = 调用方不渲染）。
  static String labelOf(GuardBuffState buff, AppLocalizations t) {
    final GuardVoucherKind? kind = GuardVoucherKind.of(buff.kind);
    if (kind == null) return '';
    final String base;
    switch (kind) {
      case GuardVoucherKind.water:
        // 玄参 2026-11-09：浇水券也不显示「剩 N」，只显示 buff 本身
        //（与劳动券同口径；剩余额度仍在存档记账，只是不上屏）。
        base = t.garden_guard_buff_water;
      case GuardVoucherKind.labor:
        base = t.garden_guard_buff_labor;
      case GuardVoucherKind.fertilize:
        base = t.garden_guard_buff_fertilize;
      case GuardVoucherKind.freeWater:
        base = t.garden_guard_buff_free_water;
      case GuardVoucherKind.freeFertilize:
        base = t.garden_guard_buff_free_fertilize;
    }
    if (!buff.isExhausted) return base;
    return '$base · ${t.garden_guard_buff_exhausted}';
  }
}
