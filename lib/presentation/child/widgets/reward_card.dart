/// 奖励卡（M2 T-E，§4.1 商店页可复用展示组件）。
///
/// 纯展示组件：所有异步（冷却查询、submit）由 StorePage 预算好
/// [submitting] / [onRedeem] 后传入，卡内不做任何异步。
///
/// [weeklyLimit] 为该模板「每周可兑换次数」上限（来自 RewardTemplate.frequencyLimitPerWeek）；
/// [weeklyUsed] 为本周已领次数（来自 cooldownCount）。卡片展示「剩余次数」= limit - used：
///   · limit<=0              → 「不限次数」；
///   · remaining>=1          → 「周限 N 次」（N = 剩余可兑换次数）；
///   · remaining==0（领完）  → 隐藏（由卡片禁用态 / 「本周已领」承载）。
/// 注意：冷却放行逻辑在 StorePage / RedemptionOrchestrationService 侧，本卡只负责展示文案。
///
/// **C62（2026-10-13）**：新增 [sunlightShort] / [weeklyQuotaFull] 两个只读标记，
/// 买不起时由 StorePage 传 `onRedeem: null` 置灰，并在此**内联显示原因**
/// （「阳光不足」/「本周额度已满」）—— 避免「按钮灰了但不说为何」的静默失败。
library reward_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_icons.dart';
import 'package:sunflower_time/presentation/shared/cream_card.dart';
// F130：平板 UI 倍率（文字之外的定尺寸元素一律乘 `uiScaleOf(context)`）。
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

class RewardCard extends StatelessWidget {
  final RewardTemplate template;
  final int costForTier;
  final int weeklyLimit; // 该模板每周可兑换次数上限（frequencyLimitPerWeek；<=0 不限）
  final int weeklyUsed; // 本周已领次数（cooldownCount）；卡片展示 = limit - used 的剩余次数
  final bool submitting;
  /// C62：可用阳光（账本余额 − 待核销/排队中）不足本笔价格 → 内联「阳光不足」。
  final bool sunlightShort;
  /// C62：当周池已放不下本笔 → 内联「本周额度已满」（超池不再排队）。
  final bool weeklyQuotaFull;
  final VoidCallback? onRedeem;

  const RewardCard({
    super.key,
    required this.template,
    required this.costForTier,
    this.weeklyLimit = 0,
    this.weeklyUsed = 0,
    this.submitting = false,
    this.sunlightShort = false,
    this.weeklyQuotaFull = false,
    this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = l10nOf(context);
    final ThemeData theme = Theme.of(context);

    // F130（2026-10-19 玄参 iPad Pro 13″ 实测截图）：平板 **UI 放大倍率**
    // （手机 1.0 / iPad 11″ 1.3 / iPad 13″ 1.6）。
    //
    // 为什么在这里取一次：`responsive.dart` 铁律——**文字走 textScaler 自动放大，
    // 文字之外的定尺寸元素（图标 / 方块 / 圆角 / 间距）必须自己乘 `uiScaleOf`**，
    // 两者同源同值才能等比。本卡此前所有尺寸都是写死常量，于是 1.6 倍下出现
    // 「字大了、阳光图标还是 17pt」以及「64 宽的兑换按钮装不下放大后的价格」。
    // 只算一次（build 顶部）而不是每处各自调用：避免同一帧内多次读 MediaQuery。
    final double s = uiScaleOf(context);
    // 是否平板（F130 二轮）：**标题限行只在平板生效** —— 手机修前不限制行数，
    // 一刀切加 maxLines 会截断长名字（QA 实测 29 字长名在 390 宽被 2 行截断）。
    final bool tablet = isTabletOf(context);

    // 每周可兑换次数提示：按「剩余次数」（limit - used）动态渲染，领完则隐藏。
    final Widget? weeklyHint = _weeklyLimitHint();

    // C62：买不起的内联原因（与置灰按钮配对）。与限次提示**共用同一行位**，
    // 保持卡片高度不变（不因多一行把 88pt 的卡撑高）。余额不足优先于超池。
    final String? blockLabel = sunlightShort
        ? l10n.shared_no_sunlight
        : (weeklyQuotaFull ? l10n.shared_week_quota_full : null);

    // 每行条目左侧彩色圆角图标块（马卡龙色底 + emoji 占位图标），按模板稳定轮换。
    final Color iconBg = macaronColorById(template.id).bg;

    // C47（玄参 2026-10-09）：卡片高度与成长页任务卡对齐（≈88pt）——
    // padding 14→12、图标 56→64（与成长页一致）、右列两行收紧
    //（价格胶囊 v6→4 / 兑换按钮压到 32pt 高 / 行距 8→6）。
    // F130：padding / 圆角 / 图标块 / 间距**全部乘 `s`** —— 手机 s=1.0，乘法本身
    // 逐位等于原常量（**这些尺寸**零回归）；平板则整体等比放大，与文字同步。
    // ⚠️「手机零回归」只针对这些乘法尺寸：本卡另有两处**按平台**分流的改动
    //（标题限行见 `tablet`），不要在注释里混为一谈（F130 二轮 QA 指出过这个矛盾）。
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Colors.white, Color(0xFFFDF3DD)],
        ),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: const Color(0x26E8A600)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F8A5A00),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(12 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 左侧图标块：优先美术图标（按奖励名关键词映射，见 growth_icons），
          // 加载失败回退马卡龙色块 + emoji 占位。
          Container(
            width: 64 * s,
            height: 64 * s,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(16 * s),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16 * s),
              // 素材自带圆角卡底（512² 方形），cover 满铺圆角块。
              child: Image.asset(
                rewardIconAssetFor(template),
                fit: BoxFit.cover,
                // F130：emoji 回退**只跟随 textScaler**（字号 32 不动）——
                // 文字类元素由 MediaQuery.textScaler 统一放大，乘 s 会放大两次。
                errorBuilder: (_, __, ___) => Center(
                  child: Text(template.contentCategory.icon,
                      style: const TextStyle(fontSize: 32)),
                ),
              ),
            ),
          ),
          SizedBox(width: 12 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // F130（QA 二轮修正）：**只有平板才限制 2 行**。
                //
                // 为什么必须按平台分流：修前手机端**无 maxLines**（长名字可自由折
                // 3 行以上）。一轮里我一刀切加了 `maxLines: 2`，在手机上把 29 字长名
                // 截断了（QA 实测 `size=165.6×48, exceeded=true`）—— 这是我自己引入的
                // 手机回归。平板才有限高压力（文字 1.6 倍 + 按钮变宽挤占横向空间），
                // 故：平板 2 行 + 省略号；**手机 maxLines: null，与修前逐位一致**。
                Text(
                  template.name,
                  maxLines: tablet ? 2 : null,
                  overflow: tablet ? TextOverflow.ellipsis : null,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4 * s),
                // 限次提示（领完即 null → 隐藏）；纯文字小字，无图标。
                // C62：买不起时改显内联原因（同一位，不增行高）。
                if (blockLabel != null)
                  Text(
                    blockLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD14343),
                    ),
                  )
                else if (weeklyHint != null)
                  weeklyHint,
              ],
            ),
          ),
          SizedBox(width: 10 * s),
          // 兑换按钮（C47d，玄参 2026-10-09：「再大一些，可以跟左边的图标大小保持一致」）
          // 尺寸口径（F130 二轮如实订正，旧注释「定为 64×64 方正按钮」已与实现不符）：
          //  **最小 64×64**（随平板倍率放大为 102.4×102.4），**宽度随价格内容增长**
          //  （三位数价格实测需要 ≈104pt → 按钮变宽而非溢出），高度保底 → 与左侧
          //  图标块等高。按钮内上下两行：上排「☀ 图标 + 价格」、下排「兑换」。
          // 保持 ElevatedButton + 文案「兑换」不变（既有测试按类型/文案断言可点性）。
          //
          // 🔴 F130 修法：`SizedBox(width: 64)` 是**死宽**——里面「数字 + 阳光图标」
          // 被 textScaler 放大后宽度超过 64 → 真机 `RIGHT OVERFLOWED BY 2.5 PIXELS`。
          // 改成 `ConstrainedBox(minWidth/minHeight)`：**宽度随内容自然增长、高度保底
          // 64*s**。为什么不是「把 64 也乘 1.6」：那只是把上限抬到 102.4，三位数价格
          // 在 1.6 倍下已占 ≈72pt + 图标 27.2 + 间距 4.8 ≈ 104pt，余量为负；家长把
          // 价格调到四位数就必然再溢出。最小尺寸约束对任意位数都安全。
          //   · 高度仍能得到「与左侧图标块等高」的观感（内容不足时由 minHeight 撑住；
          //     四位数价格时按钮实测 128.4×102.4，**已不是正方形**——旧注释里的
          //     「方正」一词与实现不符，F130 三轮 QA P3-2 已订正）；
          //   · 左侧标题区是 `Expanded`，会自动收缩让位 —— 卡片总宽始终受屏宽约束。
          // ⚠️ 禁用 FittedBox / AutoSizeText / 改小 fontSize 来压字（大字号是需求）。
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 64 * s,
              minHeight: 64 * s,
            ),
            child: ElevatedButton(
              onPressed: submitting ? null : onRedeem,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16 * s),
                ),
              ),
              child: submitting
                  ? SizedBox(
                      width: 20 * s,
                      height: 20 * s,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // 价格数字 + 阳光素材图标（C48，玄参 2026-10-10：
                            // 「将数字放在阳光UI的前面」→「20 ☀」）。
                            // F130：`maxLines: 1` —— 价格与图标必须同一行（换行会让
                            // 按钮高度失控）；字号不动（走 textScaler）。
                            Text(
                              '$costForTier',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF8D6E00),
                              ),
                            ),
                            SizedBox(width: 3 * s),
                            // F130：17 → 17*s（iPad 13″ = 27.2），与放大后的数字等高；
                            // 此前固定 17 在 1.6 倍下明显偏小（真机截图实证）。
                            Image.asset(
                              'assets/rewards/sunlight.png',
                              width: 17 * s,
                              height: 17 * s,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.wb_sunny,
                                  color: const Color(0xFFE8A600),
                                  size: 17 * s),
                            ),
                          ],
                        ),
                        SizedBox(height: 2 * s),
                        Text(
                          l10n.shared_redeem,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 每周可兑换次数提示文案部件（按「剩余次数」动态渲染）。
  ///
  /// 口径（玄参已确认）：limit<=0「不限次数」；remaining>=1「周限 N 次」；
  /// remaining==0（领完）→ 返回 null 隐藏，由卡片禁用态 / 「本周已领」承载。
  Widget? _weeklyLimitHint() {
    final String? text = weeklyRedeemLabel(weeklyLimit, weeklyUsed);
    if (text == null) return null;
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
    );
  }
}
