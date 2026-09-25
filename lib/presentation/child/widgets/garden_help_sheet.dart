/// 「花园玩法」弹窗内容（2026-09-24 花园页 v3 改造 / 2026-09-23 玩法说明扩充）。
///
/// ## 为什么单独一个文件
/// v3 删掉了贴底的半透明白块（容量 + 养护节奏），把这些信息连同**完整玩法**一起收进
/// 左下角木牌的弹窗。弹窗内容抽成**公开、无业务依赖**的 [GardenHelpSheet]（数据经构造
/// 参数传入），便于纯 widget 测试直接渲染，无需拉起 Riverpod / 数据库。
///
/// ## 覆盖的主题（玄参 2026-09-23 拍板，木牌 = 玩法说明书）
///  1. 怎么挣阳光（专注 → 阳光入账 + 任务打卡奖励）；
///  2. 阳光能干什么（花园种植物 / 浇水施肥 / 商店兑奖励）；
///  3. 植物怎么长大（自动成长 + 浇水/施肥加成 + 满进度开花 + 花谢后再生）；
///  4. 别让植物枯萎（几天不浇水会枯萎、再几天会枯死）；
///  5. 任务打卡与家长核销（联动项自动结算 / 非联动项待家长确认）；
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
    // 每分钟专注入账的阳光数（kSunlightPerFocusMinute = 1.0 → 1）。
    final int perMinute = kSunlightPerFocusMinute.toInt();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.menu_book, size: 22, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '玩法说明',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _HelpRow(
              icon: Icons.wb_sunny_outlined,
              title: '怎么挣阳光',
              detail: '白天专注就能挣阳光：每分钟 +$perMinute ☀；\n'
                  '完成成长任务打卡，每项还 +$kTaskSunlightReward ☀。',
            ),
            _HelpRow(
              icon: Icons.local_florist,
              title: '阳光能干什么',
              detail: '在花园种植物（点空花盆选一株，花 ☀ 种下）；\n'
                  '给植物浇水 $kPlantWaterCost ☀/次、施肥 $kPlantFertilizeCost ☀/次；\n'
                  '也可以去「商店」兑换喜欢的奖励。',
            ),
            _HelpRow(
              icon: Icons.schedule,
              title: '植物怎么长大',
              detail: '不照顾也会随时间自己长大；浇水 +${(kPlantWaterProgressGain * 100).round()}%、'
                  '施肥 +${(kPlantFertilizeProgressGain * 100).round()}% 长得更快\n'
                  '（每天最多浇 $kPlantWaterMaxPerDay 次、施 $kPlantFertilizeMaxPerDay 次，'
                  '两次浇水要隔 $kPlantWaterIntervalMinutes 分钟）；\n'
                  '进度养满就开花，开满 $kBloomDurationDays 天后花谢，再养满又能再开 🌻',
            ),
            _HelpRow(
              icon: Icons.local_fire_department,
              title: '别让植物枯萎',
              detail: '浇水或施肥能刷新计时；$kPlantWiltDays 天没浇水就会枯萎，\n'
                  '枯萎后再拖 $kPlantDeathDays 天就会枯死。记得常来看看它 🌱',
            ),
            const _HelpRow(
              icon: Icons.check_circle_outline,
              title: '任务打卡与家长核销',
              detail: '成长任务有两种：\n'
                  '「开始专注」的任务，达标后自动结算阳光；\n'
                  '「我做到了」的任务，先记成「等家长确认」，\n'
                  '爸爸妈妈核销通过后，阳光才真正到账。',
            ),
            _HelpRow(
              icon: Icons.yard,
              title: '花园容量',
              detail: '$capacity / $kGardenPotCapacityMax 盆',
            ),
            _HelpRow(
              icon: Icons.add_circle_outline,
              title: '扩容',
              detail: '点「+」格，花 $expandCost ☀ 可以多一个花盆'
                  '（上限 $kGardenPotCapacityMax 盆）',
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
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: Colors.green.shade700),
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
