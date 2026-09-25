/// 孩子端花园页（M3 T02 / M3 修订 / 2026-09-24 花园页 v3 改造）。
///
/// ## 显示形态（2026-09-24 v3 改造）
/// 背景为整页草地（`assets/garden/background.png`，`BoxFit.cover`）。v3 相比上一版：
///  · 花盆网格**锁死 2 行高度**，12 盆以内不再往下撑；超出部分在网格区域内**纵向滚动**，
///    右侧滚动条**仅在内容溢出时**出现。滚动区底界落在背景菜地上沿之上，
///    滚动时花盆永不遮挡固定背景植物；
///  · 底部「容量 / 养护节奏」半透明白块**整块删除**，这些信息收进左下角**木牌**弹窗；
///  · 左下角木牌**可点击**、带轻微呼吸高亮，点开「玩法说明」。
///
/// ```
///   ┌── 整页草地背景（background.png 铺满 body）──────────────────────┐
///   │ [独立路由] 左上角阳光胶囊（内嵌 tab 由 shell AppBar 提供）        │
///   │   🌻    🌵    ✚   │ ← 3 列花盆网格（最多显示 2 行）             │
///   │  ▓▓░░  ▓░░       │   超出 → 区域内纵向滚动 + 右侧滚动条          │
///   │ [木牌●]           │ ← 左下角木牌（可点 → 玩法说明弹窗）           │
///   └────────────────────────────────────────────────────────────────┘
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
///  · 「加盆」格子**始终可点**（busy 除外）：阳光不足时点击弹分因提示，不静默。
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
import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';

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

  /// 网格区域滚动控制器（v3：网格锁 2 行高度，溢出时区域内滚动）。
  final ScrollController _gridScroll = ScrollController();

  /// 网格内容是否溢出可视区（决定是否显示滚动条）。
  bool _gridScrollable = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
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
    // 网格建好后，下一帧按实际滚动指标刷新滚动条可见性（仅溢出时显示）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollable());
  }

  /// 依据当前滚动指标刷新 [_gridScrollable]（仅内容溢出时显示滚动条）。
  void _syncScrollable() {
    if (!mounted || !_gridScroll.hasClients) return;
    final bool scrollable = _gridScroll.position.maxScrollExtent > 0;
    if (scrollable != _gridScrollable) {
      setState(() => _gridScrollable = scrollable);
    }
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

  /// 打开「玩法说明」弹窗（容量 / 种植 / 养护 / 生长 / 枯萎开花 / 扩容）。
  ///
  /// 全部数字取自 prd_params 常量或当前 state（见 [GardenHelpSheet]），无裸字面量。
  Future<void> _showGardenHelp() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => GardenHelpSheet(
        capacity: _capacity,
        expandCost: _expandCost,
      ),
    );
  }

  /// 扩容确认：先弹卡写明「当前阳光 / 将扣除多少 / 容量 N → N+1」，
  /// **只有点「确定，扣除」才真正调 `expandPot`**；点「取消」什么都不做、一分不扣。
  ///
  /// 仍经 [_run] 执行（异常 SnackBar + 经济修订号自增 + 静默刷新）。
  ///
  /// ⚠️ 2026-09-24 起本方法还承担**阳光不足时的分因提示**：`ExpandPotSlot`
  /// 在阳光不足时不再拦点击（旧口径 onTap: null → 孩子点了毫无反馈，被玄参
  /// 判定为缺陷），落到这里的兜底提示成了唯一反馈路径，文案要可执行。
  Future<void> _confirmAndExpand() async {
    if (_capacity >= kGardenPotCapacityMax || _busy) return;
    final int cost = _expandCost;
    // 阳光不足：不给确认卡，直接分因提示（此时格子虽可点，但绝不扣费）。
    if (_balance < cost) {
      _snack('阳光不足，还差 ${(cost - _balance).ceil()} ☀ —— 去专注赚阳光吧');
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

  /// 正常态花盆区：**锁 2 行高度 + 溢出时区域内纵向滚动**。
  ///
  /// 可视高度的**唯一真源**是纯函数 [gardenGridVisibleHeight]（页面不再自己内联算行高/行数，
  /// 「改行数 → 测试必红」）。网格区顶部取自 `LayoutBuilder` 的剩余高度，底界取自背景图映射
  /// [gardenPotAreaBottom]，保证滚动时花盆永不压到背景植物。
  Widget _buildGardenBody(Size size) {
    final double potAreaBottom = gardenPotAreaBottom(size);
    const double pagePadH = 12;
    const double gridSpacing = 6;
    final double gridInnerWidth = size.width - pagePadH * 2;

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        // 把整块可摆区高度锁在背景「菜地上沿」之内（[gardenPotAreaBottom]）。
        height: potAreaBottom,
        child: Padding(
          // 底部 padding 交给纯函数的 bottomInset（12px 呼吸间距，不再为已删白块留位）。
          padding: const EdgeInsets.fromLTRB(pagePadH, 12, pagePadH, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 独立路由 /garden 没有 shell 的 AppBar 胶囊，故在内容区左上角补一个；
              // 内嵌（花园 tab）时由 shell AppBar 提供，避免重复。
              if (!widget.embedded) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SunlightPill(),
                ),
                const SizedBox(height: 10),
              ],
              // Flexible（loose）：网格区占据「网格顶部 → 底界」的剩余高度；用 LayoutBuilder
              // 量出该剩余高度 → 还原网格区顶部 y → 交给纯函数算「锁 2 行 + 不越菜地上沿」。
              Flexible(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double firstRowTop = potAreaBottom - c.maxHeight;
                    final double viewport = gardenGridVisibleHeight(
                      box: size,
                      gridInnerWidth: gridInnerWidth,
                      firstRowTop: firstRowTop,
                      cellAspectRatio: GardenGrid.cellAspectRatio,
                      spacing: gridSpacing,
                      bottomInset: 12,
                    );
                    // 网格**本帧**就布局完成 → 帧末按真实滚动指标刷新滚动条可见性。
                    // ⚠️ 不能只在 `_reload` 的帧末检查：那时网格还没建好，永远读不到溢出；
                    // 也不能只靠 `ScrollMetricsNotification`：首次布局的指标通知不保证派发。
                    // `_syncScrollable` 内部按「maxScrollExtent > 0」判定且仅在变化时 setState，
                    // 收敛后不再触发帧，不会空转。
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _syncScrollable());
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: double.infinity,
                        height: viewport,
                        child: Scrollbar(
                          controller: _gridScroll,
                          thumbVisibility: _gridScrollable,
                          radius: const Radius.circular(6),
                          child: SingleChildScrollView(
                            controller: _gridScroll,
                            physics: const ClampingScrollPhysics(),
                            child: GardenGrid(cells: _buildCells()),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ IndexedStack 保活数据陈旧回归（2026-09-23 真机 Bug）：外壳切 tab 不重建本页，
    // initState 只跑一次 → 别处（专注结算 / 商店核销 / 「我的」页操作）变更余额后，
    // 本页缓存的 _balance 仍是旧值 → 加盆格误算「还差 N☀」被判不可点（点击无响应）。
    // 修法：监听经济修订号，任何入账/扣账后静默重读（silent 避免闪全屏 loading）。
    // ref.listen 只能写在 build() 内（写在 initState 会触发框架断言）。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });

    // 整页草地背景：铺满页面 body（内嵌 tab 用 SafeArea、独立路由用 Scaffold body），
    // 图片缺失/失败回退到绿色渐变。阳光胶囊与木牌热区都叠在图片之上。
    final Widget background = Positioned.fill(
      child: Image.asset(
        'assets/garden/background.png',
        fit: BoxFit.cover,
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) =>
            Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFBFE6A8), Color(0xFF8FCF74)],
            ),
          ),
        ),
      ),
    );

    // LayoutBuilder 拿到 body 可用尺寸：用于把木牌热区与花盆区底界都映射到背景图上。
    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final Widget content;
        if (_loading) {
          content = const Center(child: CircularProgressIndicator());
        } else if (_error != null) {
          content = Center(child: Text('加载失败：$_error'));
        } else {
          content = _buildGardenBody(size);
        }

        // 整页叠放：背景铺满 → 内容区（锁 2 行 + 区域内滚动）→ 左下角木牌热区。
        // 木牌在左下、花盆区在中上部，互不重叠，故不会挡住花盆点击。
        return Stack(
          children: <Widget>[
            background,
            Positioned.fill(child: content),
            Positioned.fromRect(
              rect: gardenSignScreenRect(size),
              child: GardenSignHotspot(onTap: _showGardenHelp),
            ),
          ],
        );
      },
    );

    // 内嵌（花园 tab）时不叠加第二层 Scaffold/AppBar，直接返回内容。
    if (widget.embedded) {
      return SafeArea(child: page);
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
      body: page,
    );
  }
}
