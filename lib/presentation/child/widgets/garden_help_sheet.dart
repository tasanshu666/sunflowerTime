/// 「花园说明」弹窗内容（2026-09-24 花园页 v3 改造）。
///
/// ## 为什么单独一个文件
/// v3 删掉了贴底的半透明白块（容量 + 养护节奏），把这些信息收进左下角木牌的弹窗。
/// 弹窗内容抽成**公开、无业务依赖**的 [GardenHelpSheet]（数据经构造参数传入），
/// 便于纯 widget 测试直接渲染，无需拉起 Riverpod / 数据库。
///
/// ## 数字口径（硬要求）
/// 弹窗里出现的**所有数字**都必须取自 [prd_params] 的常量或调用方传入的当前 state，
/// **禁止任何裸字面量**（3 / 12 / 1% / 5% 都不许直接写）。`* 100` 与 `/ 24` 是「比例
/// 转百分比」「小时转天」的**单位换算**，非产品参数，可保留。
library garden_help_sheet;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';

/// 「花园说明」弹窗（由木牌热区点击后用 `showModalBottomSheet` 弹出）。
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
                  '花园说明',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _HelpRow(
              icon: Icons.yard,
              title: '花园容量',
              detail: '$capacity / $kGardenPotCapacityMax 盆',
            ),
            const _HelpRow(
              icon: Icons.local_florist,
              title: '怎么种',
              detail: '点一个空花盆 → 选一株植物 → 花阳光种下',
            ),
            _HelpRow(
              icon: Icons.water_drop,
              title: '怎么照顾',
              detail: '浇水 +${(kPlantWaterProgressGain * 100).round()}%'
                  '（每天最多 $kPlantWaterMaxPerDay 次，两次之间要隔 '
                  '$kPlantWaterIntervalMinutes 分钟）\n'
                  '施肥 +${(kPlantFertilizeProgressGain * 100).round()}%'
                  '（每天 $kPlantFertilizeMaxPerDay 次）',
            ),
            const _HelpRow(
              icon: Icons.schedule,
              title: '自然生长',
              // 不写死天数：普通植物 240h/阶段（约 10 天）、精品 480h/阶段（约 20 天）不同，
              // 写单一数字会对另一类不成立（QA 缺陷 5）。
              detail: '不照顾植物也会随时间自然生长，品种不同快慢也不同',
            ),
            const _HelpRow(
              icon: Icons.local_fire_department,
              title: '枯萎与开花',
              // 语义依据 plant_growth_service._applyWiltAndDeath：枯萎由「距上次浇水
              // kPlantWiltDays 天」触发（浇水 / 施肥都会刷新 lastWaterAt 计时）；
              // wilting 再持续 kPlantDeathDays 天则枯死。花期时长见 kBloomDurationDays。
              detail: '约 $kPlantWiltDays 天不给它浇水就会枯萎'
                  '（浇水或施肥都能把计时重新算起）；'
                  '成株开花后可保持 $kBloomDurationDays 天，'
                  '之后进入休整，再养满就会重新开花',
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
