/// 孩子端花园页（M3 T02 / M3 修订 / 2026-09-23 显示改造）。
///
/// ## 显示形态（2026-09-23 玄参大人要求改造）
/// 改造前是「纵向卡片列表」——一张卡一株植物，玄参原话「**这个花园现在都是卡片形式，
/// 它根本就不像个花园**」。改造后：
///
/// ```
///   ┌─ 阳光余额条 ─────────────────┐
///   ├─ 草地（渐变 + 草叶纹理）──────┤
///   │   🌻      🌵      ✚          │   ← 3 列花盆网格；空格可种植，
///   │  ╰─盆─╯  ╰─盆─╯  ╰─盆─╯      │     末尾格是「加盆」入口
///   │  ▓▓░░░   ▓░░░░               │   ← 盆下细进度条 + 短标签
///   └──────────────────────────────┘
///        花园容量 4 / 12 盆 · 养护节奏说明（小字）
/// ```
///
/// **点花盆里的植物**才弹出养护面板（[showPlantCareSheet]），按钮不再摊在草地上；
/// 空盆点击进入种植选择。花盆与植物外观都在 `garden_pot.dart` / `plant_artwork.dart`，
/// 本页只负责数据、布局与动作编排。
///
/// 进页即跑一次 [PlantGrowthService.tickAll] 推进成长与枯萎计时；任意养护操作后
/// 重新 tick 并刷新。扣减经同账本，余额变化后自增 [economyRevisionProvider] 使孩子端
/// 阳光商店同步。
///
/// 沿用 M3 修订的既有纪律：
///  · 页首常驻**阳光余额**（原先没有余额展示，扣了阳光看不出来，像「养护不消耗」）；
///  · 动作期间置 [_busy] 闸门，避免连点绕过「不能连续浇水」；
///  · 「加盆」三态互斥（已达上限 / 阳光不足不可点 / 可扩容带价），点击先确认卡。
library garden_page;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';

/// 孩子端花园：植物养成主界面。
///
/// [embedded] = true 时作为孩子端「花园」tab 的内容渲染（不叠加独立 Scaffold/AppBar，
/// 用 [SafeArea] 包裹）；false 时保留独立路由页形态（`/garden`，含刷新按钮）。
class GardenPage extends ConsumerStatefulWidget {
  const GardenPage({super.key, this.embedded = false});

  /// 是否以内嵌 tab 形态渲染（无独立 Scaffold/AppBar）。
  final bool embedded;

  @override
  ConsumerState<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends ConsumerState<GardenPage> {
  List<Plant> _plants = <Plant>[];
  List<PlantSpecies> _species = <PlantSpecies>[];
  AgeTier _tier = AgeTier.low;
  int _capacity = kGardenPotCapacityDefault;
  double _balance = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  int _price(PlantSpecies sp) =>
      _tier == AgeTier.low ? sp.baseCostLow : sp.baseCostHigh;

  /// 扩容一只花盆的阳光价（按年段，§4.6）：供按钮文案与确认卡使用，避免裸字面量。
  int get _expandCost =>
      _tier == AgeTier.low ? kPlantPotExpandCostLow : kPlantPotExpandCostHigh;

  /// [silent] = true 时不整页转圈（养护动作后静默刷新），避免每次浇水都闪一次
  /// 全屏 loading，孩子看着像「页面重载」而不是「浇完了」。
  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final DateTime now = DateTime.now();
      final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
      _plants = await svc.tickAll(now);
      final AppSettings settings =
          await ref.read(settingsRepositoryProvider).getSettings();
      _tier = settings.ageTier;
      _capacity = settings.gardenPotCapacity;
      _species = await ref.read(plantRepositoryProvider).species();
      // 注意：养护额度不在这里取——草地不展示次数，额度由弹出的养护面板自行读取
      // （见 PlantCareSheet），少一次查询，也避免两处口径漂移。
      _balance = await ref.read(sunlightRepositoryProvider).balance();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 执行养护动作：包裹异常 → SnackBar → 刷新 + 同步孩子端经济。
  ///
  /// [_busy] 期间直接忽略后续点击：浇水额度靠账本判定，但连点会在两次异步扣账
  /// 完成前同时通过校验，故必须在 UI 侧加串行闸门。
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload(silent: true);
    } on PlantOperationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// 点花盆里的植物 → 弹养护面板；面板关闭后**静默刷新草地**（进度条/形态可能变了）。
  ///
  /// 面板自己负责读数据与动作（见 [PlantCareSheet]），本页只做「打开 + 关闭后刷新」。
  Future<void> _openCareSheet(String plantId) async {
    await showPlantCareSheet(context, plantId);
    if (!mounted) return;
    await _reload(silent: true);
  }

  /// 扩容确认：先弹卡写明「当前阳光 / 将扣除多少 / 容量 N → N+1」，
  /// **只有点「确定，扣除」才真正调 `expandPot`**；点「取消」什么都不做、一分不扣。
  ///
  /// 仍经 [_run] 执行（异常 SnackBar + 经济修订号自增 + 静默刷新）。
  Future<void> _confirmAndExpand() async {
    if (_capacity >= kGardenPotCapacityMax || _busy) return;
    final int cost = _expandCost;
    // 兜底：格子已把不足态渲染为不可点，此处再拦一次，避免任何路径下扣了才报错。
    if (_balance < cost) {
      _snack('阳光不足，还差 ${(cost - _balance).ceil()} ☀');
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('要给花园腾一个花盆吗？'),
        content: Text(
          '当前阳光：${_balance.toInt()} ☀\n'
          '本次扩容将扣除：$cost ☀\n'
          '花园容量：$_capacity 盆 → ${_capacity + 1} 盆',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定，扣除'),
          ),
        ],
      ),
    );
    if (ok != true) return; // 取消 / 关闭对话框 → 不扣任何阳光
    await _run(() =>
        ref.read(plantGrowthServiceProvider).expandPot(DateTime.now()));
  }

  void _openPlantSheet(int potIndex) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('选择要种的植物',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Text('当前阳光：${_balance.toInt()} ☀',
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          ..._species.map((PlantSpecies sp) {
            final int price = _price(sp);
            final bool affordable = _balance >= price;
            return ListTile(
              leading: const Icon(Icons.local_florist),
              title: Text(sp.name),
              subtitle: Text(_rarityLabel(sp.rarity)),
              trailing: Text(
                '$price 阳光',
                style: TextStyle(
                  color: affordable ? null : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _run(() => ref
                    .read(plantGrowthServiceProvider)
                    .plant(sp.id, potIndex, DateTime.now()));
              },
            );
          }),
        ],
      ),
    );
  }

  String _rarityLabel(Rarity r) =>
      r == Rarity.legendary ? '优良' : r == Rarity.rare ? '稀有' : '普通';

  /// 按 potIndex 找到占用该花盆的植物（无则 null）。
  Plant? _occupantOf(int potIndex) {
    for (final Plant p in _plants) {
      if (p.potIndex == potIndex) return p;
    }
    return null;
  }

  PlantSpecies _speciesOf(Plant plant) {
    for (final PlantSpecies s in _species) {
      if (s.id == plant.speciesId) return s;
    }
    // 种子数据变更/物种缺失时的兜底：不显示空白格。
    return PlantSpecies(
      id: plant.speciesId,
      name: '未知植物',
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    );
  }

  /// 草地上的格子：0..capacity-1 是花盆（空/有植物），末尾追加「加盆」格（未达上限时）。
  List<Widget> _buildCells() {
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < _capacity; i++) {
      final Plant? occupant = _occupantOf(i);
      if (occupant == null) {
        cells.add(EmptyPot(potIndex: i, onTap: () => _openPlantSheet(i)));
      } else {
        cells.add(GardenPot(
          plant: occupant,
          species: _speciesOf(occupant),
          onTap: () => _openCareSheet(occupant.id),
        ));
      }
    }
    if (_capacity < kGardenPotCapacityMax) {
      cells.add(ExpandPotSlot(
        cost: _expandCost,
        shortfall: (_expandCost - _balance).ceil(),
        busy: _busy,
        onTap: _confirmAndExpand,
      ));
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final bool atMax = _capacity >= kGardenPotCapacityMax;

    final Widget content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text('加载失败：$_error'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  // 阳光余额横幅：养护扣费的可见性来源，内嵌下同样保留。
                  _SunlightBanner(balance: _balance),
                  const SizedBox(height: 10),
                  // 草地 + 3 列花盆网格（花盆与植物外观见 garden_pot.dart）。
                  _GrassArea(
                    child: GardenGrid(cells: _buildCells()),
                  ),
                  const SizedBox(height: 10),
                  // 容量一行 + 养护节奏一行（都是小字，把草地留给植物）。
                  Row(
                    children: <Widget>[
                      const Icon(Icons.yard, size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '花园容量：$_capacity / $kGardenPotCapacityMax 盆'
                          '${atMax ? ' · 已达上限' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 培养节奏说明（数值全部取自 prd_params，随常量自动跟随，无裸字面量）。
                  Text(
                    '浇水 +${(kPlantWaterProgressGain * 100).round()}%'
                    '（每天最多 $kPlantWaterMaxPerDay 次）· '
                    '施肥 +${(kPlantFertilizeProgressGain * 100).round()}%'
                    '（每天 $kPlantFertilizeMaxPerDay 次）· '
                    '植物也会随时间自然生长',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              );

    // 内嵌（花园 tab）时不叠加第二层 Scaffold/AppBar，直接返回内容。
    if (widget.embedded) {
      return SafeArea(child: content);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的花园'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新成长',
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: content,
    );
  }
}

/// 阳光余额横幅（养护消耗的可见性来源）。
class _SunlightBanner extends StatelessWidget {
  final double balance;
  const _SunlightBanner({required this.balance});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6DC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.wb_sunny, color: Color(0xFFE8A600)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('我的阳光',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              '${balance.toInt()} ☀',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD98F00)),
            ),
          ],
        ),
      );
}

/// 草地容器：绿色渐变 + 草叶纹理（自绘），花盆网格摆在里面。
///
/// 纯装饰，不参与任何业务；换背景美术时只改这里（或换成 Image.asset 背景图）。
class _GrassArea extends StatelessWidget {
  final Widget child;
  const _GrassArea({required this.child});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFBFE6A8), Color(0xFF8FCF74)],
            ),
          ),
          child: CustomPaint(
            painter: _GrassPainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
              child: child,
            ),
          ),
        ),
      );
}

/// 草叶纹理：交错的短线，纯装饰。
class _GrassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0x333F7D2E)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const double stepY = 24;
    const double stepX = 26;
    int row = 0;
    for (double y = 14; y < size.height; y += stepY) {
      // 隔行错开半个步长，避免出现整齐的竖条纹。
      for (double x = row.isEven ? 8 : 21; x < size.width; x += stepX) {
        canvas.drawLine(Offset(x, y), Offset(x + 2.5, y - 6), paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _GrassPainter oldDelegate) => false;
}
