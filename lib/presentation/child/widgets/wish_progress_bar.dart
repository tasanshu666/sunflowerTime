/// 愿望进度条（A-T04 / A24.6 / A22.1）。
///
/// ## 三条硬口径
///  ① **宽度 = 容器宽度 × 百分比**（`LayoutBuilder` 取 `constraints.maxWidth`，
///     绝不写死像素）——随卡片 / 屏宽自适应。
///  ② **`targetValue == 0`（未设目标）整条不渲染**（`SizedBox.shrink()`）——
///     未设目标时只能走「直接实现」，不显示进度条 / 进度文案（R6 / A24.7）。
///  ③ **文案用绝对量、不显示 `%`**（PRD W18.4 / W23.4 不变式 ④）：
///     - mode 0（专注分钟）：「已专注 {doneMinutes} 分钟，还差 {leftMinutes} 分钟」
///     - mode 1（任务条数）：「已完成 {doneCount} 个任务，还差 {leftCount} 个」
///
/// 百分比 / 剩余量的判据全部复用领域层 [WishProgress]（纯函数，不另写一套）。
/// 本 widget 只负责把领域算好的数字画成条 + 取 ARB 文案。
library wish_progress_bar;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/wish_progress.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 进度条轨道高度（dp）。
const double kWishProgressBarHeight = 10;

/// 进度条填充色（暖橙——与孩子端进度色系一致）。
const Color kWishProgressBarFill = Color(0xFFFF9F43);

/// 进度条轨道底色。
const Color kWishProgressBarTrack = Color(0xFFFFE9CC);

/// 愿望进度条。
///
/// [targetValue] / [progressValue] / [mode] 直接来自 [Wish]，本 widget 不读 provider。
/// [animate] 关掉可让 widget 测试 `pumpAndSettle` 正常返回（本组件**默认无动画**，
/// 保留参数仅为与其他热点组件 API 一致；首屏即时呈现进度，不做增长演出）。
class WishProgressBar extends StatelessWidget {
  const WishProgressBar({
    super.key,
    required this.mode,
    required this.targetValue,
    required this.progressValue,
    this.animate = false,
    this.showLabel = true,
  });

  final WishGoalMode mode;
  final int targetValue;
  final int progressValue;

  /// 保留参数：本组件不启动任何 controller，`false` 与 `true` 行为一致。
  final bool animate;

  /// 是否显示绝对量文案（收藏箱 / 达成池可只留条）。默认 true。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    // ② 无目标 ⇒ 整条不渲染（连文案一起消失）。
    if (!hasGoalTarget(targetValue)) return const SizedBox.shrink();

    final WishProgress progress = WishProgress(
      mode: mode,
      targetValue: targetValue,
      progressValue: progressValue,
    );
    final int percent = progress.percent ?? 0;
    final int done = progress.progressValue;
    final int left = progress.remainingValue;
    final AppLocalizations t = l10nOf(context);

    // ③ 绝对量文案，不含 `%`。
    final String label = mode == WishGoalMode.focusMinutes
        ? t.wishProgressFocusMinutes(done, left)
        : t.wishProgressTaskCount(done, left);

    return Column(
      key: const Key('wish_progress_bar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showLabel)
          Text(
            label,
            key: const Key('wish_progress_label'),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A7A66),
              fontWeight: FontWeight.w600,
            ),
          ),
        if (showLabel) const SizedBox(height: 5),
        // ① 宽度 = 容器宽度 × 百分比（不写死像素）。
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double barWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;
            return Container(
              key: const Key('wish_progress_track'),
              height: kWishProgressBarHeight,
              decoration: BoxDecoration(
                color: kWishProgressBarTrack,
                borderRadius: BorderRadius.circular(kWishProgressBarHeight / 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: const Key('wish_progress_fill'),
                  width: barWidth * (percent / kWishProgressPercentMax),
                  height: kWishProgressBarHeight,
                  decoration: BoxDecoration(
                    color: kWishProgressBarFill,
                    borderRadius:
                        BorderRadius.circular(kWishProgressBarHeight / 2),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
