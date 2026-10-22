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
// C77 称号专属属性取值函数：本文件已 import 同名类 `PlantPerk`（能力接口骨架，
// `domain/entities/plant_perk.dart`），故称号属性侧**加前缀**避免类名冲突。
import 'package:sunflower_time/domain/services/plant_perk.dart' as title_perk
    show waterCostOf, fertilizeCostOf, PlantPerk;
import 'package:sunflower_time/domain/services/plant_perk_registry.dart';
import 'package:sunflower_time/shared/plant_rarity_style.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

import 'plant_artwork.dart';
import 'package:sunflower_time/core/i18n/error_l10n.dart';
import 'package:sunflower_time/core/i18n/species_l10n.dart';

class PlantCard extends StatelessWidget {
  final Plant plant;
  final PlantSpecies species;

  /// 养护额度快照（null = 尚未加载完成，按「禁用」渲染，避免乐观放行）。
  final PlantCareQuota? quota;

  final VoidCallback? onWater;
  final VoidCallback? onFertilize;
  final VoidCallback? onClear;

  /// 铲除（C29，非死亡株也可铲）：点击后由调用方弹二次确认卡再执行。
  final VoidCallback? onShovel;

  /// C77 · 当前称号专属属性（缺省 null → 按钮 cost 显示基础价 = 旧口径，零回归）。
  final title_perk.PlantPerk? perk;

  const PlantCard({
    super.key,
    required this.plant,
    required this.species,
    this.quota,
    this.onWater,
    this.onFertilize,
    this.onClear,
    this.onShovel,
    this.perk,
  });

  String _stageLabel(AppLocalizations l10n) {
    final String stageName = switch (plant.stage) {
      PlantStage.seed => l10n.card_stage_seed,
      PlantStage.sprout => l10n.card_stage_sprout,
      PlantStage.adult => l10n.card_stage_adult,
    };
    final String statusName = switch (plant.status) {
      PlantStatus.growing => l10n.card_status_growing,
      PlantStatus.bloomed => l10n.card_status_bloomed,
      PlantStatus.wilting => l10n.card_status_wilting,
      PlantStatus.dead => l10n.card_status_dead,
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

  String _moodLabel(AppLocalizations l10n) {
    switch (plant.mood) {
      case PlantMood.happy:
        return l10n.card_mood_happy;
      case PlantMood.calm:
        return l10n.card_mood_calm;
      case PlantMood.thirsty:
        return l10n.card_mood_thirsty;
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
  String _nextStageHint(AppLocalizations l10n) {
    if (plant.status == PlantStatus.bloomed) {
      // F111：盛开期可养护（防枯萎 + 保次日晨露满额），不再暗示「养护能延长花期」。
      return l10n.card_hint_bloomed;
    }
    final double remaining = (1.0 - plant.growthProgress).clamp(0.0, 1.0);
    if (remaining <= 0.001) return l10n.card_hint_next_soon;

    // 兜底：阶段时长 / 每日推进量之一无效时退化为「只报百分比」，绝不显示荒谬数字。
    final String percentOnly =
        l10n.card_hint_progress((plant.growthProgress * 100).toInt());
    final double hoursPerStage = species.growthHoursPerStage;
    if (hoursPerStage <= 0) return percentOnly;
    final double perDay = (24.0 / hoursPerStage) +
        kPlantWaterMaxPerDay * kPlantWaterProgressGain +
        kPlantFertilizeMaxPerDay * kPlantFertilizeProgressGain;
    if (perDay <= 0) return percentOnly;

    final int days = (remaining / perDay).ceil().clamp(1, 999);
    return l10n.card_hint_grow_days(days);
  }

  /// 花期剩余文案（**仅「盛开」时**返回非 null；其余状态返回 null，不显示）。
  ///
  /// 花期时长分档：普通 [kBloomDurationDays]（3 天）/ 精品 [kBloomDurationDaysPremium]（4.5 天），
  /// 档位按 [PlantSpecies.isPremium] 判定 —— 与领域层 `PlantGrowthService._bloomDuration`
  /// **同口径**（单点常量，改常量文案自动跟随）。
  /// 剩余 = 花期时长 − (now − [Plant.bloomedAt])；`bloomedAt` 缺失（老库升级来的已开花植物
  /// 尚未补计时）时返回 null，绝不编造数字。
  String? _bloomRemainingHint(AppLocalizations l10n) {
    if (plant.status != PlantStatus.bloomed || plant.bloomedAt == null) {
      return null;
    }
    final double days = species.isPremium
        ? kBloomDurationDaysPremium
        : kBloomDurationDays.toDouble();
    final Duration total =
        Duration(milliseconds: (days * Duration.millisecondsPerDay).round());
    final Duration left = total - DateTime.now().difference(plant.bloomedAt!);
    final double daysLeft =
        (left.inMinutes / Duration.minutesPerDay).clamp(0, 999).toDouble();
    return l10n.card_hint_bloom_left(_fmtDays(daysLeft));
  }

  /// 天数格式：整数不带小数（3.0 → '3'），非整数保留一位（4.5 → '4.5'）。
  String _fmtDays(double d) {
    final String s = d.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// 本次养护的真实进度增量（F68）：走领域层公开单点口径
  /// [PlantGrowthService.careProgressGain]——首花 +1%/+3%，复开花 +0.8%/+1.2%
  /// （精品再 ÷1.5），与实际落库增量**恒等**，杜绝文案承诺与涨幅不符。
  double _careGain({
    required double firstGain,
    required double rebloomGain,
  }) =>
      PlantGrowthService.careProgressGain(
        bloomCount: plant.bloomCount,
        isPremium: species.isPremium,
        firstGain: firstGain,
        rebloomGain: rebloomGain,
      );

  /// 增量百分比格式：整数不带小数（3%），非整数保留一位（1.2% / 0.8%）。
  String _fmtGain(double gain) {
    final double pct = gain * 100;
    final String s = pct.toStringAsFixed(1);
    return s.endsWith('.0') ? pct.round().toString() : s;
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
    final AppLocalizations l10n = l10nOf(context);
    final bool isDead = plant.status == PlantStatus.dead;
    final bool isWilting = plant.status == PlantStatus.wilting;
    final PlantCareQuota? q = quota;
    // 额度未加载完成 → 一律禁用，避免绕过限额（宁可晚一点可点，也不能超限扣账）。
    final bool canWater = q != null && q.canWater && onWater != null;
    final bool canFertilize = q != null && q.canFertilize && onFertilize != null;
    // i18n B3（T03）：额度阻塞原因从「中文串」变为 [PlantBlockReason]（语义码 +
    // 数值载荷）—— 领域层不再持有人类文案，提示语在此单点装配。
    final PlantBlockReason? blockReason =
        q?.waterBlockReason ?? q?.fertilizeBlockReason;
    final String? hint = blockReason == null
        ? null
        : plantBlockReasonMessage(blockReason, l10n);
    final String? bloomLeft = _bloomRemainingHint(l10n);
    final List<Widget> perkEntries = _perkEntries();

    // ── 分层设计（玄参 2026-09-25：不要通底白，要有层次）──────────────────
    // 白色圆角大卡为底 → 进度/心情各自成「浅色分区」→ 动作按钮双行式。
    // 旧版是一条 Column 通到底 + 全灰小字，信息层级糊在一起。
    // C63（2026-10-13 玄参）：精英植物属性卡加配色区分 —— 淡紫底 + 紫描边，
    // 与花园页文字胶囊 / 选种卡同源（`kRarity*` 单点收口）；普通档维持纯白。
    final bool elite = species.isPremium;
    return Container(
      decoration: BoxDecoration(
        color: elite ? kRarityEliteCardTint : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: elite
            ? Border.all(
                color: kRarityEliteAccent.withValues(alpha: 0.45),
                width: 1.5,
              )
            : null,
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
          // 铲除入口（C29；2026-10-05 玄参反馈「放右上角，底部排版不协调」）：
          // 头部行尾红色小图标按钮，点击后由调用方弹二次确认卡（明示返还额）再执行。
          Row(
            children: <Widget>[
              PlantArtwork(
                plant: plant,
                species: species,
                // C65：随平板 UI 倍率放大 —— 名称/属性字号已 1.3×，盆栽图不动
                // 会让卡片头部左锚点相对缩水（手机 = 1.0，零回归）。
                size: 48 * uiScaleOf(context),
                tint: _statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            speciesNameOr(species.id, species.name, l10n),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                        // C63：精英档名称旁挂「精英」徽标（与选种卡稀有度徽章同色）。
                        if (elite) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: kRarityEliteTint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              l10n.garden_rarity_premium,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kRarityEliteAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
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
                        _stageLabel(l10n),
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
              // 铲除入口（C29；2026-10-05 二次修订「图标变大 + 下方红色小字标注铲除」）：
              // 图标 26 + 下方 11px 红字，命中区 ≥44×44。点击后由调用方弹二次确认卡。
              if (onShovel != null)
                SizedBox(
                  width: 44,
                  child: InkWell(
                    onTap: onShovel,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.delete_outline,
                              size: 26, color: Colors.red.shade400),
                          Text(
                            l10n.card_action_shovel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  _nextStageHint(l10n),
                  style: TextStyle(
                      fontSize: 12, color: Colors.teal.shade700),
                ),
                if (bloomLeft != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    bloomLeft,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700),
                  ),
                ],
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
              _moodLabel(l10n),
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
                label: Text(l10n.card_action_clear),
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
                        ? l10n.card_action_water
                        : l10n.card_action_water_gain(_fmtGain(_careGain(
                            firstGain: kPlantWaterProgressGain,
                            rebloomGain: kRebloomWaterProgressGain))),
                    cost: title_perk.waterCostOf(perk ?? title_perk.PlantPerk.none),
                    enabled: canWater,
                    onTap: onWater,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    icon: Icons.eco,
                    title: q == null
                        ? l10n.card_action_fertilize
                        : l10n.card_action_fertilize_gain(_fmtGain(_careGain(
                            firstGain: kPlantFertilizeProgressGain,
                            rebloomGain: kRebloomFertilizeProgressGain))),
                    cost: title_perk.fertilizeCostOf(perk ?? title_perk.PlantPerk.none),
                    enabled: canFertilize,
                    onTap: onFertilize,
                  ),
                ),
              ],
            ),
            if (q != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.card_quota_left(q.waterRemaining, kPlantWaterMaxPerDay,
                    q.fertilizeRemaining, kPlantFertilizeMaxPerDay),
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
                    ? l10n.card_wilt_easy
                    : l10n.card_wilt_hard(kPlantWiltRecoverHardWater,
                        kPlantWiltRecoverHardFertilize),
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
              // C65：跟随注入后的 textScaler，与右侧按钮文案同步缩放。
              Icon(icon, size: 18, color: mainColor, applyTextScaling: true),
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
