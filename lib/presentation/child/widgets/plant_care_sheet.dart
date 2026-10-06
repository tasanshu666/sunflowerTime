/// 植物养护卡（**屏幕中央弹出**，2026-09-29 由底部面板改居中卡；2026-09-23 花园显示改造）。
///
/// ## 为什么独立成组件
/// 改造后草地上不再摊按钮，**点花盆里的植物才弹出养护**。面板要满足两条硬要求：
///  1. **动作后自己刷新**（浇一次水，面板里的进度条与「今日剩余」要立刻变），
///     所以它不接收外层传进来的死数据，而是自己按 [plantId] 走仓储读最新值；
///  2. **与草地解耦**（草地只负责点击回调），因此面板自带加载/异常态，
///     即使植物在面板打开期间被别处删掉也不会崩。
///
/// 展示与按钮复用 [PlantCard] —— 单一真源，避免「卡片一套口径、面板另一套」。
library plant_care_sheet;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/repositories/plant_repository.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';

import 'care_effect_overlay.dart';
import 'child_snack.dart';
import 'plant_card.dart';

/// 养护卡关闭时的结果（C29 扩展）：
///  · [effect] = 最后一次成功养护（浇水 / 施肥）的动效类型，供花园页在该花盆播放动效；
///  · [shovelRefund] = 本次铲除**实际返还**的阳光数（未铲除为 null；返还 0 也可能合法，
///    如向日葵免费首株 / 死亡株）。
class PlantCareResult {
  final CareEffectType? effect;
  final int? shovelRefund;

  const PlantCareResult({this.effect, this.shovelRefund});
}

/// 以**屏幕中央弹出卡**形式打开某株植物的养护面板（2026-09-29 玄参：
/// 「不要从下面弹出来，要单独弹出来卡片」——由底部 ModalBottomSheet 改为居中 Dialog）。
///
/// 返回的 Future 在卡片关闭后完成 —— 调用方（花园页）据此刷新草地上的进度条。
/// 若期间发生过成功的养护动作（浇水 / 施肥 / 铲除），返回值携带最后一次的
/// [CareEffectType] 或铲除返还额（见 [PlantCareResult]）。
Future<PlantCareResult> showPlantCareCard(BuildContext context, String plantId) {
  CareEffectType? lastEffect;
  int? lastShovelRefund;
  return showDialog<PlantCareResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (BuildContext ctx) => PlantCareCard(
      plantId: plantId,
      onCareSuccess: (CareEffectType e) => lastEffect = e,
      onShoveled: (int refund) => lastShovelRefund = refund,
    ),
  ).then((_) => PlantCareResult(effect: lastEffect, shovelRefund: lastShovelRefund));
}

class PlantCareCard extends ConsumerStatefulWidget {
  final String plantId;

  /// 养护动作成功后的回调（浇水/施肥），供花园页触发一次性动效。清理枯萎不触发。
  final ValueChanged<CareEffectType>? onCareSuccess;

  /// 铲除成功后的回调（C29）：携带**实际返还**阳光数（可为 0）。
  final ValueChanged<int>? onShoveled;

  const PlantCareCard({
    super.key,
    required this.plantId,
    this.onCareSuccess,
    this.onShoveled,
  });

  @override
  ConsumerState<PlantCareCard> createState() => _PlantCareCardState();
}

class _PlantCareCardState extends ConsumerState<PlantCareCard> {
  Plant? _plant;
  PlantSpecies? _species;
  PlantCareQuota? _quota;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取该株植物 + 物种 + 今日养护额度（三者都从仓储取最新值）。
  Future<void> _load() async {
    try {
      final PlantRepository repo = ref.read(plantRepositoryProvider);
      final Plant? p = await repo.plant(widget.plantId);
      if (p != null) {
        final List<PlantSpecies> all = await repo.species();
        _plant = p;
        _species = all.firstWhere(
          (PlantSpecies s) => s.id == p.speciesId,
          orElse: () => _unknownSpecies(p.speciesId),
        );
        _quota = (await ref
            .read(plantGrowthServiceProvider)
            .careQuotas(<Plant>[p], DateTime.now()))[p.id];
      } else {
        _plant = null;
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 物种被删/种子变更时的兜底，与花园页同款（不显示「未知植物」的空白卡）。
  PlantSpecies _unknownSpecies(String id) => PlantSpecies(
        id: id,
        name: '未知植物',
        rarity: Rarity.common,
        baseCostHigh: 0,
        baseCostLow: 0,
        growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
      );

  void _snack(String msg) {
    if (mounted) showChildSnack(context, msg);
  }

  /// 执行养护动作：串行闸门 → 扣费 → 自增经济修订号 → 重新读取本株数据。
  ///
  /// [closeAfter] 用于「清理枯萎植物」：删完这株就没什么可看的了，直接关面板。
  /// [effect] 非 null 表示这是一次成功的养护（浇水/施肥），成功后会通过
  /// [PlantCareCard.onCareSuccess] 上报，供花园页播放一次性动效；清理枯萎不传。
  Future<void> _run(
    Future<void> Function() action, {
    bool closeAfter = false,
    CareEffectType? effect,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // 通知孩子端其它页面（商店/我的）重算余额与次数。
      ref.read(economyRevisionProvider.notifier).state++;
      // 成功的养护动作：上报类型，花园页据此在该花盆位置播放动效。
      if (effect != null) widget.onCareSuccess?.call(effect);
      // 养护成功 → 关掉面板，让花园露出，动效叠加层在其上播放。
      // 覆盖「浇水 / 施肥」（effect != null）与「清理枯萎」（closeAfter）两路：
      // pop 时机在「上报成功」之后，不破坏任何业务逻辑（扣费 / 账本 / 额度判定已在上行完成）。
      if (closeAfter || effect != null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await _load();
      if (!mounted) return;
      // 植物已不在（比如被别处删掉）→ 关面板，避免停在空壳上。
      if (_plant == null) Navigator.of(context).pop();
    } on PlantOperationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 铲除（口径 C29）：先弹**二次确认卡**（明示返还额，防误铲）→ 确认后调领域层
  /// [PlantGrowthService.shovel]（删株 + 返还）→ 上报返还额 → 关面板。
  /// 取消 / 关闭确认卡 → 分毫不返、植株不动。
  Future<void> _shovel() async {
    if (_busy || _plant == null) return;
    final Plant plant = _plant!;
    final int refund =
        plant.status == PlantStatus.dead ? 0 : plant.shovelRefund;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('要铲除「${_species?.name ?? '这株植物'}」吗？'),
        content: Text(
          refund > 0
              ? '铲除后这株植物会消失。\n返还种植阳光：$refund ☀（浇水施肥的阳光不返还）'
              : '铲除后这株植物会消失。\n本次铲除不返还阳光。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定铲除'),
          ),
        ],
      ),
    );
    if (ok != true) return; // 取消 → 什么都不做
    await _run(
      () async {
        final int refunded = await ref
            .read(plantGrowthServiceProvider)
            .shovel(plant.id, DateTime.now());
        widget.onShoveled?.call(refunded);
      },
      closeAfter: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Text('加载失败：$_error'),
      );
    } else if (_plant == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Text('这株植物已经不在花园里啦'),
      );
    } else {
      final Plant plant = _plant!;
      final PlantSpecies species = _species!;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: PlantCard(
          plant: plant,
          species: species,
          quota: _quota,
          onWater: () => _run(
            () => ref.read(plantGrowthServiceProvider).water(plant.id, DateTime.now()),
            effect: CareEffectType.water,
          ),
          onFertilize: () => _run(
            () => ref
                .read(plantGrowthServiceProvider)
                .fertilize(plant.id, DateTime.now()),
            effect: CareEffectType.fertilize,
          ),
          onClear: () => _run(
            () => ref.read(plantRepositoryProvider).deletePlant(plant.id),
            closeAfter: true,
          ),
          onShovel: _shovel,
        ),
      );
    }

    // 居中弹出大卡：暖奶油底 + 大圆角，内容超高时内部滚动（不顶破屏幕）。
    return Dialog(
      backgroundColor: Colors.transparent,
      // 居中大卡：左右留 24 边距、上下留 40，超宽超高都不贴边。
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          decoration: BoxDecoration(
            // 暖奶油底（与花园草地的暖色调一致），替代通底白 —— 玄参 2026-09-25：
            // 「不要通底，都是白底，要有一些分层」。卡片本体是白色圆角大卡（见 PlantCard），
            // 与奶油底形成两层，进度/心情在卡内再做浅色分区。
            color: const Color(0xFFFBF4E4),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFFFE3B0), width: 1.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF8A5A00).withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                body,
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '植物也会随时间自然生长，按时养护才能早点开花 🌻\n'
                    '成株盛开后，每周浇 3 次水 + 施 1 次肥才能继续开花 🌻',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
