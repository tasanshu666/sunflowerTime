/// 植物卡片（孩子端花园，M3 T02 / M3 修订）。
///
/// 展示单株植物：外观 / 当前阶段进度条 / 心情 / 养护动作（浇水 / 施肥 / 铲除清理枯萎植物）。
/// 动作可用性由 [PlantCareQuota]（账本口径：今日次数 + 30 分钟浇水间隔）决定，与
/// [PlantGrowthService] 完全一致——按钮禁用时把原因直接写在卡面上，避免「点了没反应」。
///
/// 经济可见性（M3 修订）：浇水 / 施肥**明码标价**（5 / 10 阳光）并显示今日剩余次数，
/// 否则孩子扣了阳光却看不出（玄参大人真机反馈「浇水没消耗阳光」的根因）。
///
/// 外观（2026-09-22 接口化）：植物长什么样**不在本文件里画**，统一交给
/// [PlantArtwork] —— 美术资源按命名规范丢进 `assets/plants/` 即自动生效，
/// 本文件一行都不用改；资源缺失时自动回退内置自绘简笔。
///
/// 能力入口（2026-09-22 接口化）：成株后的额外玩法（产阳光 / 互动等）走
/// [PlantPerkRegistry]。注册表当前为空 → 卡片视觉与改动前完全一致；
/// 未来注册任意 [PlantPerk] 后，入口会自动长出来，本文件同样不用改。
library plant_card;

import 'package:flutter/material.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_perk.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/plant_perk_registry.dart';

import 'plant_artwork.dart';

class PlantCard extends StatelessWidget {
  final Plant plant;
  final PlantSpecies species;

  /// 养护额度快照（null = 尚未加载完成，按「禁用」渲染，避免乐观放行）。
  final PlantCareQuota? quota;

  final VoidCallback? onWater;
  final VoidCallback? onFertilize;
  final VoidCallback? onClear;

  const PlantCard({
    super.key,
    required this.plant,
    required this.species,
    this.quota,
    this.onWater,
    this.onFertilize,
    this.onClear,
  });

  String get _stageLabel {
    final String stageName = switch (plant.stage) {
      PlantStage.seed => '种子',
      PlantStage.sprout => '幼苗',
      PlantStage.adult => '成株',
    };
    final String statusName = switch (plant.status) {
      PlantStatus.growing => '成长中',
      PlantStatus.bloomed => '已开花 🌻',
      PlantStatus.wilting => '枯萎中（快救回！）',
      PlantStatus.dead => '已枯萎',
    };
    return '$stageName · $statusName';
  }

  Color get _statusColor {
    switch (plant.status) {
      case PlantStatus.bloomed:
        return Colors.green.shade700;
      case PlantStatus.wilting:
        return Colors.orange.shade700;
      case PlantStatus.dead:
        return Colors.grey;
      case PlantStatus.growing:
        return Colors.teal.shade600;
    }
  }

  String get _moodLabel {
    switch (plant.mood) {
      case PlantMood.happy:
        return '😊 今天有专注，我很开心';
      case PlantMood.calm:
        return '😌 状态平稳';
      case PlantMood.thirsty:
        return '🥵 有点口渴，该浇水啦';
    }
  }

  /// 心情徽章配色（分层设计：不同心情不同色温，替代通底灰字）。
  Color get _moodBg {
    switch (plant.mood) {
      case PlantMood.happy:
        return const Color(0xFFE8F5E9); // 淡绿
      case PlantMood.calm:
        return const Color(0xFFEFEFEA); // 暖灰
      case PlantMood.thirsty:
        return const Color(0xFFFFF3D6); // 淡橙黄
    }
  }

  Color get _moodFg {
    switch (plant.mood) {
      case PlantMood.happy:
        return Colors.green.shade800;
      case PlantMood.calm:
        return Colors.blueGrey.shade700;
      case PlantMood.thirsty:
        return Colors.deepOrange.shade800;
    }
  }

  /// 距下一阶段还需约多少天（V2 数值，用户 2026-09-22）。
  ///
  /// 旧文案「还需约 N 次浇水」在新数值下会算出荒谬结果（浇水仅 +1%/次 → 100 次），
  /// 对孩子毫无意义，故改为**时间口径**：
  ///   每日推进量 = 自然成长 + 当天养护上限（按「每天都养护做满」估算，未养护会更久）。
  ///  - 自然成长：一阶段需 [PlantSpecies.growthHoursPerStage] 小时（普通 240 / 精品 480），
  ///    故每天推进 24 / growthHoursPerStage（普通约 10%/天、精品约 5%/天）；
  ///  - 养护上限：浇水 [kPlantWaterMaxPerDay] 次 × [kPlantWaterProgressGain]
  ///    + 施肥 [kPlantFertilizeMaxPerDay] 次 × [kPlantFertilizeProgressGain]。
  ///
  /// 口径只用于卡片展示，不写回任何数据；常量变了文案自动跟随，无裸字面量。
  String get _nextStageHint {
    if (plant.status == PlantStatus.bloomed) {
      return '已开花 🌻 持续养护可保持';
    }
    final double remaining = (1.0 - plant.growthProgress).clamp(0.0, 1.0);
    if (remaining <= 0.001) return '即将进入下一阶段…';

    // 兜底：阶段时长 / 每日推进量之一无效时退化为「只报百分比」，绝不显示荒谬数字。
    final String percentOnly = '本阶段成长 ${(plant.growthProgress * 100).toInt()}%';
    final double hoursPerStage = species.growthHoursPerStage;
    if (hoursPerStage <= 0) return percentOnly;
    final double perDay = (24.0 / hoursPerStage) +
        kPlantWaterMaxPerDay * kPlantWaterProgressGain +
        kPlantFertilizeMaxPerDay * kPlantFertilizeProgressGain;
    if (perDay <= 0) return percentOnly;

    final int days = (remaining / perDay).ceil().clamp(1, 999);
    return '每天按时养护，还需约 $days 天长成';
  }

  /// 当前「有事可做」的能力入口（未来玩法的统一挂点）。
  ///
  /// 注册表默认为空 → 返回空列表 → 卡片不新增任何视觉元素。
  /// 未来 `PlantPerkRegistry.instance.register(...)` 后，这里自动长出 chip，
  /// 本卡片代码零改动。点击行为留给具体玩法接入时补（本轮不定义任何玩法规则）。
  List<Widget> _perkEntries() {
    final List<PlantPerk> ready = PlantPerkRegistry.instance.readyFor(
      plant: plant,
      species: species,
      now: DateTime.now(),
    );
    return ready
        .map(
          (PlantPerk perk) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text(perk.displayName),
              visualDensity: VisualDensity.compact,
              backgroundColor: _statusColor.withOpacity(0.12),
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDead = plant.status == PlantStatus.dead;
    final bool isWilting = plant.status == PlantStatus.wilting;
    final PlantCareQuota? q = quota;
    // 额度未加载完成 → 一律禁用，避免绕过限额（宁可晚一点可点，也不能超限扣账）。
    final bool canWater = q != null && q.canWater && onWater != null;
    final bool canFertilize = q != null && q.canFertilize && onFertilize != null;
    final String? hint = q?.waterBlockReason ?? q?.fertilizeBlockReason;
    final List<Widget> perkEntries = _perkEntries();

    // ── 分层设计（玄参 2026-09-25：不要通底白，要有层次）──────────────────
    // 白色圆角大卡为底 → 进度/心情各自成「浅色分区」→ 动作按钮双行式。
    // 旧版是一条 Column 通到底 + 全灰小字，信息层级糊在一起。
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── ① 头部：外观 + 名称 + 状态徽章（替代两行灰绿字）─────────────
          Row(
            children: <Widget>[
              PlantArtwork(
                plant: plant,
                species: species,
                size: 48,
                tint: _statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      species.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _stageLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── ② 成长分区：进度条 + 百分比 + 距离下一阶段（浅色圆角底）──────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: plant.growthProgress.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.white,
                          color: _statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(plant.growthProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _nextStageHint,
                  style: TextStyle(
                      fontSize: 12, color: Colors.teal.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── ③ 心情徽章（按心情着色的胶囊，替代通底一行字）───────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _moodBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _moodLabel,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: _moodFg),
            ),
          ),
          if (perkEntries.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(children: perkEntries),
          ],
          const SizedBox(height: 14),
          // ── ④ 动作区 ───────────────────────────────────────────────────
          if (isDead)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('铲除回收'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red),
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _actionButton(
                    icon: Icons.water_drop,
                    title: q == null
                        ? '浇水'
                        : '浇水 +${(kPlantWaterProgressGain * 100).round()}%',
                    cost: kPlantWaterCost,
                    enabled: canWater,
                    onTap: onWater,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    icon: Icons.eco,
                    title: q == null
                        ? '施肥'
                        : '施肥 +${(kPlantFertilizeProgressGain * 100).round()}%',
                    cost: kPlantFertilizeCost,
                    enabled: canFertilize,
                    onTap: onFertilize,
                  ),
                ),
              ],
            ),
            if (q != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '今日剩余：浇水 ${q.waterRemaining}/$kPlantWaterMaxPerDay 次'
                ' · 施肥 ${q.fertilizeRemaining}/$kPlantFertilizeMaxPerDay 次',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (hint != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            if (isWilting && plant.wiltedAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                DateTime.now().difference(plant.wiltedAt!) <
                        Duration(days: kPlantWiltRecoverHardDays)
                    ? '浇水 1 次即可救回'
                    : '需浇水 $kPlantWiltRecoverHardWater 次 + 施肥 $kPlantWiltRecoverHardFertilize 次才能救回',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 双行式动作按钮：上行「图标 + 动作 + 增幅」、下行「价格」。
  ///
  /// ⚠️ 为什么不用单行 `OutlinedButton.icon('浇水 +1% · 5 ☀')`：窄屏下单行放不下，
  /// `maxLines:1 + ellipsis` 会把**价格**截掉（玄参 2026-09-25 截图「浇水 +1% · 5...」，
  /// 价格恰恰是最不能丢的信息）。拆成两行后各自都有充足宽度，永不截断。
  Widget _actionButton({
    required IconData icon,
    required String title,
    required int cost,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final Color mainColor =
        enabled ? Colors.teal.shade800 : Colors.grey.shade500;
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: enabled ? Colors.teal.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: mainColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: mainColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$cost ☀',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.brown.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
