/// 植物养护面板（底部弹出，2026-09-23 花园显示改造）。
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
import 'plant_card.dart';

/// 以底部面板形式打开某株植物的养护面板。
///
/// 返回的 Future 在面板关闭后完成 —— 调用方（花园页）据此刷新草地上的进度条。
/// 若期间发生过成功的养护动作（浇水 / 施肥），返回值携带最后一次的 [CareEffectType]，
/// 供花园页在该花盆位置播放一次性动效（见 [CareEffectOverlay]）。
Future<CareEffectType?> showPlantCareSheet(BuildContext context, String plantId) {
  CareEffectType? lastEffect;
  return showModalBottomSheet<CareEffectType?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 暖奶油底（与花园草地的暖色调一致），替代通底白 —— 玄参 2026-09-25：
    // 「不要通底，都是白底，要有一些分层」。卡片本体是白色圆角大卡（见 PlantCard），
    // 与奶油底形成两层，进度/心情在卡内再做浅色分区。
    backgroundColor: const Color(0xFFFBF4E4),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) => PlantCareSheet(
      plantId: plantId,
      onCareSuccess: (CareEffectType e) => lastEffect = e,
    ),
  ).then((_) => lastEffect);
}

class PlantCareSheet extends ConsumerStatefulWidget {
  final String plantId;

  /// 养护动作成功后的回调（浇水/施肥），供花园页触发一次性动效。清理枯萎不触发。
  final ValueChanged<CareEffectType>? onCareSuccess;

  const PlantCareSheet({
    super.key,
    required this.plantId,
    this.onCareSuccess,
  });

  @override
  ConsumerState<PlantCareSheet> createState() => _PlantCareSheetState();
}

class _PlantCareSheetState extends ConsumerState<PlantCareSheet> {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// 执行养护动作：串行闸门 → 扣费 → 自增经济修订号 → 重新读取本株数据。
  ///
  /// [closeAfter] 用于「清理枯萎植物」：删完这株就没什么可看的了，直接关面板。
  /// [effect] 非 null 表示这是一次成功的养护（浇水/施肥），成功后会通过
  /// [PlantCareSheet.onCareSuccess] 上报，供花园页播放一次性动效；清理枯萎不传。
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
      if (closeAfter) {
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
        ),
      );
    }

    return SafeArea(
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
    );
  }
}
