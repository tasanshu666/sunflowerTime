/// 「花园玩法」弹窗内容（2026-09-24 花园页 v3 改造 / 2026-09-23 玩法说明扩充）。
///
/// ## 为什么单独一个文件
/// v3 删掉了贴底的半透明白块（容量 + 养护节奏），把这些信息连同**完整玩法**一起收进
/// 左下角木牌的弹窗。弹窗内容抽成**公开、无业务依赖**的 [GardenHelpSheet]（数据经构造
/// 参数传入），便于纯 widget 测试直接渲染，无需拉起 Riverpod / 数据库。
///
/// ## 覆盖的主题（玄参 2026-09-23 拍板，木牌 = 玩法说明书；**2026-10-22 同步批次**
/// 补齐此后上线的新玩法：护眼奖励 / 种子与碎片 / 开花惊喜与晨露 / 杂草害虫 /
/// 枯萎救回 / 联动任务按比例结算）
///  1. 怎么挣阳光（专注 → 阳光入账 + 任务打卡奖励 + 护眼休息奖励）；
///  2. 阳光能干什么（种植（阳光或碎片） / 浇水施肥 / 铲除返一半 / 商店兑奖励）；
///  3. 植物怎么长大（自动成长 + 浇水/施肥加成 + 满进度开花 + 花谢后再生）；
///  4. 别让植物枯萎（几天不浇水会枯萎、再几天会枯死 + 枯萎救回口径）；
///  5. 任务打卡与家长核销（联动项按实际专注比例结算 / 非联动项待家长确认）；
///  6. 开花的小惊喜（开花保底阳光 + 碎片/种子/大额概率惊喜 + 花期晨露）；
///  7. 杂草和害虫（点掉 + 阳光奖励）；
///  8. 种子和碎片（种子当支付方式 + 重复分解 + 精英档碎片价）；
///  另有花园容量与扩容价。
///
/// ## 数字口径（硬要求）
/// 弹窗里出现的**所有数字**都必须取自 [prd_params] / [app_constants] 的常量或调用方
/// 传入的当前 state，**禁止任何裸字面量**（3 / 12 / 1% / 5% 都不许直接写）。`* 100` 是
/// 「比例转百分比」的**单位换算**，非产品参数，可保留。
library garden_help_sheet;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 「花园玩法」弹窗（由木牌热区点击后用 `showModalBottomSheet` 弹出）。
class GardenHelpSheet extends StatelessWidget {
  const GardenHelpSheet({
    super.key,
    required this.capacity,
    required this.expandCost,
  });

  /// 当前花园容量（盆）——取自花园页 state。
  final int capacity;

  /// 扩容一只花盆的阳光价（随年段变化，由调用方按当前 state 传入）。
  final int expandCost;

  @override
  Widget build(BuildContext context) {
    // 🔴 底部弹层上下文在页面 scope 之外：自包 L10nScope（i18n B1 约定）。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = l10nOf(context);
          // 每分钟专注入账的阳光数（kSunlightPerFocusMinute = 1.0 → 1）。
          final int perMinute = kSunlightPerFocusMinute.toInt();
          return _buildList(context, l10n, perMinute);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n, int perMinute) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.menu_book, size: 22, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  l10n.ghelp_title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _HelpRow(
              icon: Icons.wb_sunny_outlined,
              iconAsset: 'assets/rewards/sunlight.png',
              title: l10n.ghelp_earn_title,
              // 玄参 2026-10-23 测试反馈：任务打卡奖励按专注时长比例结算（F143），
              // 不是固定值 → 文案定性化，不传 {taskReward} 数字。
              detail: l10n.ghelp_earn_detail(perMinute, kEyeCareRewardSunlight),
            ),
            _HelpRow(
              icon: Icons.local_florist,
              title: l10n.ghelp_use_title,
              detail: l10n.ghelp_use_detail(kSpeciesSunlightCostCommon,
                  kSpeciesFragmentCostCommon, kPlantWaterCost, kPlantFertilizeCost),
            ),
            _HelpRow(
              icon: Icons.schedule,
              title: l10n.ghelp_grow_title,
              detail: l10n.ghelp_grow_detail(
                (kPlantWaterProgressGain * 100).round(),
                (kPlantFertilizeProgressGain * 100).round(),
                kPlantWaterMaxPerDay,
                kPlantFertilizeMaxPerDay,
                kPlantWaterIntervalMinutes,
                kBloomDurationDays,
              ),
            ),
            _HelpRow(
              icon: Icons.local_fire_department,
              title: l10n.ghelp_wilt_title,
              detail: l10n.ghelp_wilt_detail(kPlantWiltDays, kPlantDeathDays,
                  kPlantWiltRecoverHardDays, kPlantWiltRecoverHardWater,
                  kPlantWiltRecoverHardFertilize),
            ),
            _HelpRow(
              icon: Icons.check_circle_outline,
              title: l10n.ghelp_task_title,
              detail: l10n.ghelp_task_detail,
            ),
            _HelpRow(
              icon: Icons.auto_awesome,
              title: l10n.ghelp_bloom_title,
              detail: l10n.ghelp_bloom_detail(kBloomInstantSunlight),
            ),
            _HelpRow(
              icon: Icons.bug_report_outlined,
              title: l10n.ghelp_weed_title,
              detail: l10n.ghelp_weed_detail(
                  kGardenWeedReward.round(), kGardenPestReward.round()),
            ),
            _HelpRow(
              icon: Icons.eco_outlined,
              title: l10n.ghelp_seed_title,
              detail: l10n.ghelp_seed_detail(kSpeciesFragmentCostPremium),
            ),
            _HelpRow(
              icon: Icons.yard,
              title: l10n.ghelp_capacity_title,
              detail: l10n.ghelp_capacity_detail(
                  capacity, kGardenPotCapacityMax),
            ),
            _HelpRow(
              icon: Icons.add_circle_outline,
              title: l10n.ghelp_expand_title,
              detail: l10n.ghelp_expand_detail(
                  expandCost, kGardenPotCapacityMax),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗内的单行说明：小图标 + 标题 + 详情。
class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.iconAsset,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// 美术图标（2026-10-06 玄参交付 `assets/rewards/sunlight.png`，「所有用到
  /// 阳光图标的地方都替换」）；提供时优先用素材，缺失/失败回退 [icon]。
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          iconAsset != null
              ? Image.asset(
                  iconAsset!,
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                      Icon(icon, size: 18, color: Colors.green.shade700),
                )
              : Icon(icon, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.black87,
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
