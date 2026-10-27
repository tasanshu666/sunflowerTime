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
/// **点花盆里的植物**才弹出养护卡（[showPlantCareCard]，2026-09-29 由底部面板改居中卡），按钮不再摊在草地上；
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/entitlement_matrix.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/core/i18n/species_lore_l10n.dart';
import 'package:sunflower_time/data/local/settings_store.dart';
import 'package:sunflower_time/domain/entities/bloom_reward_outcome.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';
import 'package:sunflower_time/domain/entities/plant.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/domain/entities/pot_disturbance.dart';
import 'package:sunflower_time/domain/entities/settings.dart';
import 'package:sunflower_time/domain/services/empty_pot_service.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/plant_perk.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/state/child_tab_refresh.dart';
import 'package:sunflower_time/presentation/child/state/shell_tab.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_debug_panel.dart';
import 'package:sunflower_time/presentation/child/widgets/bloom_reward_icons.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';
import 'package:sunflower_time/presentation/child/widgets/care_effect_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/child_confirm_card.dart'
    show ConfirmCardBadge, ConfirmCardRow, showChildConfirmCard;
import 'package:sunflower_time/presentation/child/widgets/child_snack.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_background_layout.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_help_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_pot.dart';
import 'package:sunflower_time/presentation/child/widgets/growth_fx_overlay.dart';
import 'package:sunflower_time/presentation/child/widgets/garden_sign_hotspot.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_care_sheet.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_confirm_dialog.dart';
import 'package:sunflower_time/presentation/child/widgets/sunlight_pill.dart';
import 'package:sunflower_time/shared/plant_rarity_style.dart';
import 'package:sunflower_time/shared/responsive.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';
import 'package:sunflower_time/core/i18n/error_l10n.dart';
import 'package:sunflower_time/core/i18n/species_l10n.dart';

/// 养护动效浮层 / 成长演出浮层的**稳定 Key**（C82）。
///
/// ## 真要防的 bug（玄参 2026-10-16 小米真机「盛开帧播两次」）
/// 根 Stack 的 children 里，两个浮层都是**条件渲染**。当「养护动效 `_activeEffect` 结束置
/// null」把 `CareEffectOverlay` 从 children 移除时，后面所有兄弟**整体前移一位**；
/// `GrowthFxOverlay` 于是落到原先 `CareEffectOverlay` 的 index 上——**若两处浮层都没有 Key**，
/// 两个 `Positioned` 同类型 → `Widget.canUpdate`（同 runtimeType 且同 key）在 `null==null`
/// 下**误命中** → **原地复用**该元素、只换 child → 子类型 `CareEffectOverlay → GrowthFxOverlay`
/// 不匹配 → 旧的 GrowthFxOverlay 元素被卸载、**新建 State** → 一次性动画从第 0 帧**重放**
/// = 真机看到的「播两次」。
///
/// ## 实测边界（QA 复核 B，隔离副本删 Key 复跑；**勿再重推**）
///  · **M1** 只删成长 Key（保留养护 Key）→ 🟢 3/3 仍绿；
///  · **M1b** 只删养护 Key（保留成长 Key）→ 🟢 仍绿；
///  · **M1c** **两把 Key 全删** → 🔴 `Expected<1>/Actual<2>`（两次 `initState` = remount）。
/// ⇒ **任一方带独立 Key 即可断开位置匹配链**：顶对齐在该 index 因 key 不匹配而停，改由
/// **自底向上**按 (类型+key) 匹配 → `GrowthFxOverlay` 元素被保住；**只有两把都缺**才会原地
/// 复用 → remount。故两把 Key 都保留，作**双保险**（单把已足够，见上）。
const Key _kCareEffectOverlayKey = ValueKey<String>('gardenCareEffectOverlay');

/// 成长过渡演出浮层的稳定 Key（C82；机制与实测边界见 [_kCareEffectOverlayKey] 的说明）。
const Key _kGrowthFxOverlayKey = ValueKey<String>('gardenGrowthFxOverlay');

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

/// 正在播放的养护动效描述：类型 + 在页面 Stack 本地坐标里的位置/尺寸 + 关联植物（用于弹跳副本）。
class _CareEffectSpec {
  final CareEffectType type;
  final Offset offset;
  final Size size;
  final Plant? plant;
  final PlantSpecies? species;

  /// 效果帧 asset 列表（2026-09-28 起为正式路径；粒子路径不再使用时也一并携带）。
  final List<String> frames;

  /// 播放时长（毫秒）= 对应音频时长。
  final int durationMs;

  /// 动画播放完成后的业务收尾回调（2026-10-03 除草 / 除虫用）：在叠加层被移除前
  /// 执行（如「干扰物渐变消失 → 刷新草地 → 弹飘字」）。null = 只移除叠加层。
  final VoidCallback? onFinished;

  _CareEffectSpec({
    required this.type,
    required this.offset,
    required this.size,
    required this.frames,
    required this.durationMs,
    this.plant,
    this.species,
    this.onFinished,
  });
}

/// 正在播放的「成长过渡」演出描述（**屏幕中央焦点卡片**，玄参 2026-09-29 改口径）。
///
/// 2026-09-28 旧口径是「在目标花盆格上居中放大播放」——玄参实测：格子太小看不清、
/// 与底层花盆重叠显得乱，且因逐帧解码出现「一闪一闪」。
/// 新口径：画面正中弹出圆角白卡（宽 = 屏宽 [kGrowFxCardWidthRatio]），卡内放大播放
/// 序列帧 + 成长音频，播完**整卡淡出**消失（见 `growth_fx_overlay.dart`）。
class _GrowthFxSpec {
  final GrowTransition transition;

  /// 卡片标题文案（如「长大啦！」/「开花啦！」）。
  final String title;

  /// 实际帧列表（2026-10-12 五物种接入：按物种目录从 AssetManifest 实测，
  /// 帧数 25~27 各不同；解析失败回退 sunflower，见 `resolveGrowFxAssets`）。
  final List<String> frames;

  _GrowthFxSpec({
    required this.transition,
    required this.title,
    required this.frames,
  });
}

class _GardenPageState extends ConsumerState<GardenPage> with ChildTabAutoRefresh<GardenPage> {
  // ── C68：自动刷新接线（切回本 tab / 回前台 / 跨 08:00 或跨天）───────────────
  //
  // ⚠️ 本页就是 C68 的**事故现场**：盛开植物的「08:00 晨露」在库里到期了，但页面只在
  // 首次挂载 / 经济修订号变化 / 养护卡片关闭时重读 → 切回花园 tab 看不到头顶气泡，
  // 直到随手点开花盆再关掉（触发「卡片关闭」那条）才「突然看到阳光」。
  //
  // 内嵌（外壳 tab）时下标 = [kChildTabIndexOfGarden]；路由直推的 `GardenPage()`
  // 不在外壳里 → 返回 `null`（恒视为可见，只吃「回前台 + 时间边界」两条触发）。
  @override
  int? get refreshTabIndex =>
      widget.embedded ? kChildTabIndexOfGarden : null;

  /// 切回本 tab / 回前台 / 跨时间边界时的刷新入口。
  ///
  /// F132（玄参 2026-10-19「专注回来种子直接变幼芽、没有过渡动画」）：
  /// 顺序**不可交换** —— 先消费「不可见期间攒下的补播」，再 `_reload`。因为
  /// `_reload` 里的 `tickAll` 会把植物结算到最新，并把持久化快照推进到最新，
  /// 先刷就再也 diff 不出这次升级了。`_consumeQueuedGrowthFx` 只 await「写快照」，
  /// **不 await 演出时长**（4s+），不拖住数据刷新。
  @override
  Future<void> onTabRefreshRequested() async {
    await _consumeQueuedGrowthFx();
    return _reload(silent: true);
  }

  List<Plant> _plants = <Plant>[];
  List<PlantSpecies> _species = <PlantSpecies>[];
  AgeTier _tier = AgeTier.low;
  int _capacity = kGardenPotCapacityDefault;
  double _balance = 0;

  /// C77 · 当前称号专属属性（随 [_reload] 刷新；未就绪时 [PlantPerk.none] = 无加成）。
  PlantPerk _perk = PlantPerk.none;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// 当前页文案（build 期在 L10nScope 内赋值；异步回调经 [_t] 取，
  /// 尚未 build 过的极端早回调回退中文，与迁移前行为一致）。
  AppLocalizations? _l10n;

  /// 文案统一取用入口（i18n B1）。
  AppLocalizations get _t => _l10n ?? AppLocalizationsZh();

  /// 花盆上方刚清除掉的干扰物提示（口径 C26 + 2026-10-03 飘字口径）：
  /// `potIndex` 指明浮在哪一格；`label` = 「除草成功」/「除虫成功」；
  /// `sunlight` = 奖励阳光数（**渲染成阳光图标 + 「+N」**，玄参 2026-10-03 口径：
  /// 「阳光+1」的阳光二字要用图标不是文字，「就像之前那样显示」= 与头顶奖励
  /// 图标同源 `assets/rewards/sunlight.png`，缺失回退内置 `Icons.wb_sunny`）。
  /// 由 [_RisingHint] 自下而上飘动淡出（约 1.6s），走完经 onComplete 自清；
  /// 只保留**最后一条**（同格连点时后一条覆盖前一条）。
  ({int potIndex, String label, int sunlight})? _clearHint;

  /// 除草 / 除虫收尾序列计时器：**按票据（ticket）一条**，淡出结束后各自收尾。
  ///
  /// 🔴 为什么不是单例 `Timer? _clearSeqTimer`（F155-B 之后暴露的真缺陷）：
  /// 第二次清除若 `cancel()` 掉第一条定时器，第一张票据就永远留在 [_suppressTickets]
  /// 里 → [ _suppressReload ] 恒 true → **本页此后所有刷新一律被挡**（草地不刷新、
  /// 余额不更新、空盆 tick 不跑，已清掉的浮标还会「复活」并常驻）。
  ///
  /// 🔴 **两张票据确实会同时在飞（F156-A 实测）**：[_onClearAnimated] 先把 `_busy` 置
  /// false、再等 [kPestFadeOutMs]（300ms）淡出，这 300ms 内页面**已可操作**、而上一张
  /// 票据**尚未释放** → 点另一盆即构成重叠（盆 0 演出结束当帧点盆 1：两张票据同时存在，
  /// 两盆都真的清掉）。演出期内的那 4.1s 由 [_busy] 锁住，这一段重叠才构造不出来 ——
  /// 「UI 上完全不可构造重叠」**不成立**，只有「演出期间不可构造」成立。
  ///
  /// ⚠️ 但**「cancel 别人的定时器」在当前时序下不可观测**（别把它当活地雷）：
  /// 一张票据的定时器 300ms 内必触发，而第二张票据的 [_onClearAnimated] 至少晚
  /// 4.1s（[_busy] 串行化的演出）+ 一点才到 → 回退成「新票据进来 cancel 全部」时，
  /// 待取消的那条**早已触发完毕**，`empty_pot_ui_test.dart` 10 例仍全绿
  /// （QA 与本机各变异一次，均实测）。
  /// 🟢 **真正被用例钉住的是「每张票据最终都被释放」**：`empty_pot_ui_test.dart` 的
  /// 「淡出窗口内重叠清除：两张票据同时在飞也各自收尾」——注释掉本方法里的
  /// `_suppressTickets.remove(ticket)`（票据永不释放）→ 该用例 + 3 条旧用例立刻变红。
  /// 若日后**放宽 [_busy]**（例如允许演出期间操作其它盆），两张票据的收尾会拉近到
  /// 300ms 以内，届时 cancel-all 才会变成真缺陷 → 那时必须先补一条能构造「两次收尾
  /// 相距 <300ms」的用例。
  ///
  /// 实现要求（保留）：一张票据一条定时器、绝不 cancel 别人的、[dispose] 里统一 cancel
  /// —— 这是「未来放宽 [_busy]」时的**前置条件**，不是当下的可观测缺陷防护。
  ///
  /// 顺带事实（QA 核对项，无需改代码）：一键清除 / 一键护理**不触碰空盆干扰物**
  /// ——`OneClickPlan.careTargets` 只由有植物盆（`plants`）派生，且该路径不建票据；
  /// 故当前**没有**绕过 4.1s 演出的清空盆路径。
  final Map<int, Timer> _clearTimers = <int, Timer>{};

  /// 正在「渐变消失」的干扰物（2026-10-03 玄参口径：播完动画先淡出浮标再刷新草地）：
  /// `weed` 区分杂草 / 蝗虫；`potIndex` 定位花盆格。
  ///
  /// 🔴 F155-B 起**按「盆」识别**（原来是 `plantId`）：空花盆没有植物，只有盆序号。
  ///  · `plantId != null` → 有植物盆（仍按 plantId 精确匹配，植物的淡出行为一字不变）；
  ///  · `plantId == null` → 空花盆（按 `potIndex` 匹配）。
  ///
  /// 🔴 为什么是 `Set` 而不是单值（F155-B 之后的真缺陷）：300ms 淡出窗口内可以连续点
  /// 第二盆（见 [_clearTimers]：`_busy` 在淡出开始时就已放开、票据却还没释放）；
  /// 单值会让后一次**覆盖**前一次的淡出态 → 前一盆的浮标透明度弹回 1.0（闪一下）。
  /// F156-A 只把**演出期间**（4.1s）串行化了，淡出窗口这段重叠依旧成立 → 集合语义仍是
  /// 当下的正确模型（多盆各自淡出、互不干扰），也是「一键清除」等未来并发入口的前提。
  /// 元素值相等（record 结构相等）→ 同盆同类型重复 add 自动去重。
  final Set<({String? plantId, int potIndex, bool weed})> _fadingClears =
      <({String? plantId, int potIndex, bool weed})>{};

  /// 各空花盆当日的杂草 / 害虫状态（F155-B，玄参 2026-10-27 拍板）：`potIndex → 状态`。
  ///
  /// 数据源 = [EmptyPotService.tick]（每次 [_reload] 旁路跑一次每日 roll，见
  /// [_refreshEmptyPots]），只含**当前空盆**（种下后该盆记录被删除，自然从本映射消失）。
  Map<int, PotDisturbance> _potDisturbances = <int, PotDisturbance>{};

  /// 空盆 tick 是否在飞（防刷新风暴把 tick 堆起来；见 [_refreshEmptyPots]）。
  bool _emptyPotTickInFlight = false;

  // ── 一键操作（口径 C29，玄参 2026-10-05 拍板）────────────────────────────

  /// 一键操作汇总提示的**根 Overlay 浮层**（玄参 2026-10-07 真机复测修订）。
  ///
  /// 背景（真机「提示卡还是在屏幕最下面」的根因）：旧实现把提示挂在花园页**根 Stack**
  /// 内（`Positioned.fill(Center(...))`）——理论上居中，但**受父层布局链影响**
  /// （SafeArea / 嵌套 Stack 的约束来源不确定），真机上曾出现贴底。故改为**根 Overlay
  /// 全屏浮层**：`Overlay.of(context, rootOverlay: true)` 的坐标系恒等于屏幕，
  /// `Positioned.fill + Center` → **确定性居中**（与 [_showCollectGhost] 同款做法，
  /// 且脱离页面重建树、不受格内裁剪影响）。
  OverlayEntry? _batchHintEntry;

  /// 汇总提示兜底清除计时器（动画 onComplete 未触发时清理；dispose 必须取消）。
  Timer? _batchHintTimer;

  /// 收集成功提示浮层（玄参 2026-10-08「点收集弹出的卡片应显示在屏幕中间，
  /// 显示 1s 后淡出」）——同款根 Overlay 全屏浮层，`Positioned.fill + Center`
  /// 确定性居中，替换原贴底 SnackBar。
  OverlayEntry? _collectHintEntry;

  /// 收集成功提示兜底清除计时器（dispose 必须取消）。
  Timer? _collectHintTimer;

  /// 一键操作的每盆**轻量反馈**（不做 4s 完整动效）：potIndex → 动效类型，
  /// 短暂显示约 1.1s 后整批清除。
  final Map<int, CareEffectType> _batchPulse = <int, CareEffectType>{};

  /// 每盆轻量反馈的整批清除计时器（dispose 必须取消）。
  Timer? _batchPulseTimer;

  /// 收集奖励的「向上飘走」幽灵动效（玄参 2026-10-05「用户点击之后，向上飘动，
  /// 慢慢消失」）。
  ///
  /// ⚠️ 实现口径（2026-10-05 二次修订）：**根 Overlay 浮层**，不再挂在花盆格
  /// Stack 里 —— 收集成功后的 `_reload` 会重建格子子树（无 key 子节点整体重挂），
  /// 格内 [CollectGhost] 的动画元素被销毁重建导致动效被打断（玄参实测「点阳光
  /// 直接消失」的根因）；根 Overlay 完全脱离页面重建树、且不受格内裁剪影响。
  /// 约 0.9s 走完自清 + 950ms 定时器兜底双保险。
  OverlayEntry? _collectGhostEntry;

  /// 幽灵兜底清除计时器（dispose 必须取消）。
  Timer? _collectGhostTimer;

  /// 刷新抑制闸门（2026-10-03 除草/除虫动效回归修复）：清除干扰物**已写库但动画
  /// 未播完**期间置闸，挡住 [_run] 内部的 `_reload(silent)` 与
  /// `economyRevisionProvider` 监听触发的静默刷新 —— 否则草/虫在动画播完前就
  /// 从草地消失（玄参真机反馈「点击草之后，草直接消失了」的根因）。
  /// 动画收尾（[_onClearAnimated]）按**自己的票据**释放并统一补一次刷新。
  ///
  /// ⚠️ **票据制而非单个 bool**（2026-10-13 修复）：原为 `bool _suppressReload`，
  /// 两次清除动画（先除虫、未等淡出完就除草）**计时器重叠**时，前一次的收尾会把
  /// 闸门提前打开，放行本应被抑制的 `_reload` → 同一动作被重复结算（成长演出
  /// 「播两次」的结构性诱因之一）。改为「每动作一张票据，播完按各自的票据释放」。
  final Set<int> _suppressTickets = <int>{};
  int _suppressTicketSeq = 0;

  /// 是否处于刷新抑制期（任一清除动画未播完 → true）。
  bool get _suppressReload => _suppressTickets.isNotEmpty;

  /// 当前「可收集」的待收集奖励（`plantId → 待收集奖励列表`，变更 A/B）。
  /// 到期后在该花盆**上方**掉落「头顶奖励图标」（玄参 2026-09-27 图标化），点击收集
  /// （见 [_collectRewards]）。
  ///
  /// 变更 B 后同一株可能**同时**有两条：开花瞬间（`due = bloomedAt`，即刻可收集）+ 第二段
  /// （`due = bloomedAt + 48h`），故为列表；列表按 `dueAt` 升序（瞬间的更早）。
  Map<String, List<PendingBloomReward>> _collectibles =
      <String, List<PendingBloomReward>>{};

  /// 可用美术资源集合（`assets/rewards/*.png`；空集 → 头顶图标全回退内置 `Icons`）。
  ///
  /// 来源 [rewardAssetsProvider]（`AssetManifest.listAssets()`）。玄参后续丢素材进
  /// `assets/rewards/` 即自动生效，无需改代码。
  Set<String> _rewardAssets = <String>{};

  /// 精品碎片当前余额（花园页碎片入口展示，变更 B）。
  int _fragmentBalance = 0;

  /// 持有的免费种植券物种 id 集合（花园「选择要种的植物」列表判「种子兑换 · 免费」用）。
  Set<String> _unlockedSpecies = <String>{};

  /// 各物种支付按钮**预取缓存**（speciesId → buttons；玄参 2026-10-07「种子同步到
  /// 种植卡片里感觉有点慢」）：[_reload] 末尾统一预取（逐物种查库太慢，打开弹窗
  /// 逐个 await 会卡），[_openPlantSheet] 直接读缓存零等待；缓存未命中时弹窗内
  /// 现场查兜底（口径仍单点 [PlantGrowthService.plantPaymentOptions]）。
  final Map<String, List<_PlantPaymentButton>> _paymentButtonsCache =
      <String, List<_PlantPaymentButton>>{};

  /// 各花盆格的全局 Key（稳定）：用于在养护成功后定位该花盆在屏幕上的坐标，
  /// 把动效叠加层精确地摆到对应花盆之上。按 potIndex 懒创建、复用。
  final Map<int, GlobalKey> _potKeys = <int, GlobalKey>{};

  /// 页面根 Stack 的 Key：把花盆的全局坐标换算到本 Stack 的本地坐标系。
  final GlobalKey _pageStackKey = GlobalKey();

  /// 当前正在播放的一次性养护动效（null = 无）。动画结束由 [CareEffectOverlay.onComplete]
  /// 置回 null 以移除叠加层。
  _CareEffectSpec? _activeEffect;

  /// 当前正在播放的「成长过渡」演出（null = 无）。播完渐隐后由播放器回调移除。
  _GrowthFxSpec? _activeGrowth;

  /// 成长演出**在飞/在屏**闸门（2026-10-13 玄参实测「开花动画播了两次」）。
  ///
  /// 演出是幂等的：同一阶段跃迁可能被多条刷新路径各观测一次（一次养护动作会
  /// 触发 ≥2 次 `_reload`），若两次都上屏就会「重播」。故本闸门在
  /// [_playGrowthFx] 入口同步置位、演出结束（[GrowthFxOverlay.onComplete]）复位，
  /// 期间的后续请求一律忽略 —— 口径「一帧只播一场演出」。
  bool _growthFxInFlight = false;

  /// 上一轮快照：`plantId → 'stage.name:status.name'`。
  ///
  /// 🔴 F132 起**不再是主数据源**：跨会话 / 外壳重建的「上次看到」快照持久化在
  /// [SettingsStore.lastSeenPlantPhases]（SP，按孩子分键），见 [_detectGrowthTransitions]。
  /// 本字段只在 SP **不可用**时兜底（纯 widget 测试 / 极端环境），行为与修复前一致。
  Map<String, String> _lastPhases = <String, String>{};

  /// 不可见期间检测到、还没播过的补播项：`plantId|transition.name`。
  ///
  /// `Set` 天然去重：同一次升级被多条刷新路径各观测一次也只入队一条。孩子真正切到
  /// 花园（或回到前台）时由 [_consumeQueuedGrowthFx] 一次性消费（只播第一个）。
  /// 刻意放内存：进程活着就够用；进程被杀则持久化快照**没被推进**，下次进花园仍会
  /// 重新 diff 出这次升级（见 [_detectGrowthTransitions] 的不可见分支）。
  final Set<String> _queuedGrowthFx = <String>{};

  /// 本页祖先的 [TickerMode] 是否启用（外壳对隐藏 tab 包 `enabled: false`）。
  ///
  /// 在 [didChangeDependencies] 读取（合法的依赖读取时机，早于首次 `_reload` 的
  /// 异步结算完成），用作 [_gardenVisible] 的第二判据。见其注释。
  bool _tickerEnabled = true;

  /// 花园氛围音计时器（玄参 2026-09-28：进入花园立即播一次 background.mp3，
  /// 之后每 [kGardenAmbientIntervalSeconds] 秒一次；离开花园 tab 停止并取消）。
  Timer? _ambientTimer;

  /// 氛围音当前是否应处于「激活」（花园 tab 可见）状态；build 里按 TickerMode 可见性
  /// 驱动（IndexedStack 保活 tab 切换不会 dispose，用 TickerMode 判可见性）。
  bool _ambientActive = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode 必须在这里读（build 之前、initState 之后的合法依赖读取时机）；
    // 外壳切 tab 时它会显式变化 → 本回调重跑 → [_tickerEnabled] 跟上。
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    // ⚠️ dispose 内不得用 ref（unmount 先标 disposed，用必抛）——AudioService 用静态单例。
    _ambientTimer?.cancel();
    // ⚠️ 纯 Timer 字段（不碰 ref），dispose 里取消即可；不取消会让 setState 打到已卸载页。
    for (final Timer t in _clearTimers.values) {
      t.cancel();
    }
    _clearTimers.clear();
    _batchPulseTimer?.cancel();
    _collectGhostTimer?.cancel();
    _collectGhostEntry?.remove(); // 根 Overlay 浮层不随本页卸载，必须显式移除。
    _collectGhostEntry = null;
    _batchHintTimer?.cancel();
    _batchHintEntry?.remove(); // 汇总提示同为根 Overlay 浮层，必须显式移除。
    _batchHintEntry = null;
    _collectHintTimer?.cancel();
    _collectHintEntry?.remove(); // 收集成功提示同为根 Overlay 浮层，必须显式移除。
    _collectHintEntry = null;
    unawaited(AudioService.instance.stopGardenAmbient(reason: 'dispose'));
    _gridScroll.dispose();
    super.dispose();
  }

  /// 扩容一只花盆的阳光价（按年段 + C77 称号减免）：供按钮文案与确认卡使用。
  int get _expandCost => expandCostOf(_perk, premium: _tier != AgeTier.low);

  /// [silent] = true 时不整页转圈（养护动作后静默刷新），避免每次浇水都闪一次
  /// 全屏 loading，孩子看着像「页面重载」而不是「浇完了」。
  ///
  /// ⚠️ [_suppressReload] = true 期间一律跳过（除草/除虫动画播放中：数据已写库但
  /// 界面要等「播完 → 淡出」才更新，见 [_clearPest]）。
  Future<void> _reload({bool silent = false}) async {
    if (_suppressReload) return;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final DateTime now = DateTime.now();
      final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
      // 花谢兜底自动到账：收集本次 tick 自动结算的奖励 outcome（用于「花朵凋谢，奖励已自动
      // 收下：…」提示——玄参要求花谢自动到账**也要提示**）。
      final List<BloomRewardOutcome> autoSettled = <BloomRewardOutcome>[];
      _plants = await svc.tickAll(now, autoSettled: autoSettled);
      // 任务 A（玄参 2026-09-28）：刷新时把「v12 之前登记的零值哨兵旧 pending 行」
      // 按当前档位回写为明细，使旧数据头顶图标直接显示阳光/碎片/种子（不再礼物盒）。
      await svc.materializeLegacyBloomRewards(now);
      // C45（玄参 2026-10-09「一株头顶堆 20+ 图标」）：物理删除 B35 护栏上线前的
      // 历史重复登记行（同株同 dueAt 同 kind 只留一条），幂等无重复零删除。
      await svc.dedupePendingBloomRewards();
      final AppSettings settings =
          await ref.read(settingsRepositoryProvider).getSettings();
      // C90 期 2：档位跟当前孩子走（不再读全局 settings 单行；档案源不可用
      // 时回退 settings，与隔离前行为一致）。
      try {
        _tier = await ref.read(childAgeTierProvider.future);
      } catch (_) {
        _tier = settings.ageTier;
      }
      // C77：当前称号专属属性（与域层 [PlantGrowthService.currentPerk] 同源；随经济
      // 修订号 / tab 刷新重算）。批量路径以本值下发，避免逐株重读。
      _perk = await ref.read(currentPlantPerkProvider.future);
      _capacity = settings.gardenPotCapacity;
      // ── F155-B（玄参 2026-10-27 拍板）：空花盆也会长杂草 / 害虫 ─────────────
      // 每次刷新顺带跑一次「空盆每日 roll」（幂等：同日重复刷新不重 roll），
      // 结果进 [_potDisturbances] 供 [_buildCells] 画浮标。
      //
      // 🔴 **旁路执行（不 await）**，理由有两条，都是硬约束：
      //  ① 纯 widget 测试宿主常常没有注入 DB（`appDatabaseProvider` 默认实例要
      //     path_provider）—— 这些用例里 `tick()` 的 DB 查询**可能永远悬着**
      //     （不是抛错，是 await 不回来），一旦在主路径 await，整页会停在 loading、
      //     连草地都渲染不出来（实测：F155-A 回归用例因此找不到空花盆）；
      //  ② 空盆干扰物是**锦上添花**的叠加玩法，绝不值得拖慢草地首帧。
      // 降级 = 本轮不出浮标（见 [_refreshEmptyPots] 的独立 try/catch）。
      unawaited(_refreshEmptyPots(now));
      // 花园氛围音与音效开关（玄参 2026-09-28）：花园页也应用一次最新设置，
      // 保证从家长端改完开关回到花园立即生效（专注页进页时也会应用一次）。
      ref.read(audioServiceProvider).applySettings(
            soundOn: settings.soundOn,
            bgmOn: settings.bgmOn,
          );
      _species = await ref.read(plantRepositoryProvider).species();
      // 变更 A/B：读取当前「可收集」的待收集奖励（开花瞬间 + 每日晨露）→ 花盆上方
      // 头顶图标（C45 聚合展示），点击聚合收集；同株最多 ~6 条。
      // F111：晨露阳光按「前一日是否养护」折损后再展示（与发放同源，数字 = 实际到手）。
      _collectibles =
          await svc.withBloomDewDiscount(await svc.collectibleBloomRewards(now));
      // 头顶图标美术资源集合（缺失回退内置 Icons）。
      _rewardAssets = await ref.read(rewardAssetsProvider.future);
      // 变更 B：碎片入口余额。
      _fragmentBalance =
          await ref.read(bloomRewardRepositoryProvider).premiumFragmentBalance();
      // 玄参 2026-09-27 物种表改版：持有的免费种植券（「选择要种」列表判免费）。
      _unlockedSpecies =
          await ref.read(bloomRewardRepositoryProvider).unlockedSpeciesIds();
      // 注意：养护额度不在这里取——草地不展示次数，额度由弹出的养护面板自行读取
      // （见 PlantCareCard），少一次查询，也避免两处口径漂移。
      _balance = await ref.read(sunlightRepositoryProvider).balance();
      // 预取各物种支付按钮（玄参 2026-10-07「种子同步到种植卡片慢」）：余额 / 券 /
      // 碎片全部就绪后统一算一遍，打开选种弹窗零等待。逐物种仍走领域单点。
      final PlantGrowthService svcForButtons = ref.read(plantGrowthServiceProvider);
      _paymentButtonsCache.clear();
      for (final PlantSpecies sp in _species) {
        _paymentButtonsCache[sp.id] = await _plantPaymentButtons(sp, svcForButtons);
      }
      _error = null;
      // 升级检测：与「孩子上次看到」的持久化快照 diff，发现「阶段/开花」推进 →
      // 可见就播、不可见就入队（F132）。
      await _detectGrowthTransitions();
      // 花谢自动到账提示（有则可，无则静默）。
      if (autoSettled.isNotEmpty && mounted) {
        _snack(_t.garden_settle_withered(autoSettled.map(_outcomeParts).join('；')));
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
    // 网格建好后，下一帧按实际滚动指标刷新滚动条可见性（仅溢出时显示）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollable());
  }

  /// 旁路刷新「空盆干扰物」（F155-B）：**不 await、独立 try/catch、失败静默降级**。
  ///
  /// 为什么不在 [_reload] 主路径 await：
  ///  · 纯 widget 测试宿主没有 DB 时，`tick()` 的查询可能**永远不返回**（不是抛错），
  ///    await 会把整页钉死在 loading；
  ///  · 它是叠加玩法，绝不值得拖慢草地首帧。
  ///
  /// [_emptyPotTickInFlight] 用于防「刷新风暴」把 tick 堆起来（每次 [_reload] 都会触发；
  /// 经济修订号 / tab 刷新 / 动作收尾都走 [_reload]）。
  Future<void> _refreshEmptyPots(DateTime now) async {
    if (_emptyPotTickInFlight) return;
    _emptyPotTickInFlight = true;
    try {
      final List<int> emptyPots = <int>[
        for (int i = 0; i < _capacity; i++)
          if (_occupantOf(i) == null) i,
      ];
      final List<PotDisturbance> pots =
          await ref.read(emptyPotServiceProvider).tick(emptyPots, now);
      if (!mounted) return;
      final Map<int, PotDisturbance> next = <int, PotDisturbance>{
        for (final PotDisturbance d in pots) d.potIndex: d,
      };
      // 状态没变就不重建（同日幂等 tick 每次返回同样的列表，避免无意义 setState）。
      if (!_samePotDisturbances(_potDisturbances, next)) {
        setState(() => _potDisturbances = next);
      }
    } catch (e) {
      // 降级：本轮不出浮标（仓储不可用 / 极端环境）。不影响草地与任何其它玩法。
      // 🔴 但**不许静默**：留一行诊断输出，否则「空盆玩法整块失效」在真机上会
      //    完全无迹可寻（纯 widget 测试宿主没有 DB 也走这里，属预期噪声）。
      debugPrint('[garden] empty-pot tick failed, disturbances hidden: $e');
      if (!mounted) return;
      if (_potDisturbances.isNotEmpty) {
        setState(() => _potDisturbances = <int, PotDisturbance>{});
      }
    } finally {
      _emptyPotTickInFlight = false;
    }
  }

  /// 两个 `potIndex → 状态` 映射是否等价（[PotDisturbance] 已实现值相等）。
  bool _samePotDisturbances(
    Map<int, PotDisturbance> a,
    Map<int, PotDisturbance> b,
  ) {
    if (a.length != b.length) return false;
    for (final MapEntry<int, PotDisturbance> e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// 依据当前滚动指标刷新 [_gridScrollable]（仅内容溢出时显示滚动条）。
  void _syncScrollable() {
    if (!mounted || !_gridScroll.hasClients) return;
    final bool scrollable = _gridScroll.position.maxScrollExtent > 0;
    if (scrollable != _gridScrollable) {
      setState(() => _gridScrollable = scrollable);
    }
  }

  /// 执行养护动作：包裹异常 → SnackBar → 刷新 + 同步孩子端经济。返回是否成功（供成功提示用）。
  ///
  /// [_busy] 期间直接忽略后续点击：浇水额度靠账本判定，但连点会在两次异步扣账
  /// 完成前同时通过校验，故必须在 UI 侧加串行闸门。
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    bool ok = false;
    try {
      await action();
      ref.read(economyRevisionProvider.notifier).state++;
      await _reload(silent: true);
      ok = true;
    } on PlantOperationException catch (e) {
      // i18n B3（T03）：领域层只回语义码，文案经单点映射装配。
      _snack(plantErrorMessage(e, _t));
    } catch (e) {
      _snack(_t.shared_op_failed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return ok;
  }

  /// 花园页统一提示（儿童风浮空卡，2026-09-29 玄参：黑色默认 SnackBar 太丑）。
  void _snack(String msg) {
    if (mounted) showChildSnack(context, msg);
  }

  /// 点花盆里的植物 → 弹养护面板；面板关闭后**静默刷新草地**（进度条/形态可能变了）。
  ///
  /// 卡片自己负责读数据与动作（见 [PlantCareCard]），本页只做「打开 + 关闭后刷新」。
  /// 面板返回结果（C29 扩展）：浇水/施肥动效类型 → 在该花盆位置播放一次性动效；
  /// 铲除返还额 → 分因 SnackBar「铲除成功，返还 N ☀」（植物已删，飘字无格可挂）。
  Future<void> _openCareSheet(String plantId, int potIndex) async {
    final PlantCareResult result = await showPlantCareCard(context, plantId);
    if (!mounted) return;
    // 养护成功 → 在该花盆位置播放一次性动效（动效结束自动移除自身）。
    if (result.effect != null) _playCareEffect(potIndex, result.effect!);
    if (result.shovelRefund != null) {
      final int refund = result.shovelRefund!;
      // 铲除音效（2026-10-07 玄参交付 `shovel.mp3`；确认卡点「确定铲除」成功后播）。
      AudioService.instance.playSfx(AudioCue.shovel);
      _snack(refund > 0
          ? _t.garden_shovel_refund(refund)
          : _t.garden_shovel_ok);
    }
    await _reload(silent: true);
  }

  /// 点击头顶奖励图标（玄参 2026-10-05 动效口径）：先捕获本条图标规格并**就地起
  /// 「向上飘动 + 淡出」幽灵**（约 0.9s，纯视觉、不挡数据），随后**立即**走既有
  /// 收集流程（[_collectRewards]：写库 → 刷新 → 合并提示）。
  ///
  /// 2026-10-06 玄参加收集音效（**统一一个**，不按图标分类——阳光 / 碎片 / 种子
  /// 共用 `collect_reward.mp3`，素材待交付缺失时静默跳过）；点击仍收下整条 pending。
  /// 头顶奖励图标点击（C45 聚合口径）：点击任一聚合图标 = 收下它覆盖的**全部**
  /// pending 条目（晨露多槽位下同列多归并，见 [aggregateRewardIcons]）。
  ///
  /// [allInPlant] = 该株当前全部可收集条目（幽灵动效展示合并后的完整奖励清单用）。
  void _onCollectIconsTap(
    int potIndex,
    List<PendingBloomReward> covered,
    RewardIconSpec spec,
    List<PendingBloomReward> allInPlant,
  ) {
    if (_busy || covered.isEmpty) return; // 收集流程自带 _busy 闸门；动效期防重复点。
    AudioService.instance.playSfx(AudioCue.collectReward);
    // 幽灵展示该株**全部聚合后**的图标规格（点一下全飞走，与收集范围一致）。
    _showCollectGhost(
      potIndex,
      aggregateRewardIcons(allInPlant, isPremiumOf: _isPremiumSpecies)
          .map((AggregatedRewardIcon g) => g.spec)
          .toList(),
    );
    unawaited(_collectRewards(covered));
  }

  /// 在指定花盆格位置起「收集幽灵」根 Overlay 浮层（见 [_collectGhostEntry] 注释）。
  ///
  /// 位置用 [_potKey] 的 RenderBox 全局矩形（与养护动效同一定位源）；花盆尚未布局
  /// （极端情况）则静默跳过。资源缺失（测试环境）时 [CollectGhost] 无图可画 →
  /// 不可见，不产生 findable 节点。`IgnorePointer`：幽灵不挡任何命中。
  void _showCollectGhost(int potIndex, List<RewardIconSpec> specs) {
    _removeCollectGhost();
    final BuildContext? cellCtx = _potKey(potIndex).currentContext;
    if (cellCtx == null || !mounted) return;
    final RenderBox? rb = cellCtx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return;
    final Rect rect = rb.localToGlobal(Offset.zero) & rb.size;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: Center(
            child: CollectGhost(
              specs: specs,
              availableAssets: _rewardAssets,
              onComplete: _removeCollectGhost,
            ),
          ),
        ),
      ),
    );
    _collectGhostEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    // 兜底：动画 onEnd 因任何原因未触发（如页面被卸载重建）也保证浮层被清走。
    _collectGhostTimer = Timer(
      const Duration(milliseconds: 950),
      _removeCollectGhost,
    );
  }

  /// 移除收集幽灵浮层（幂等）。
  void _removeCollectGhost() {
    _collectGhostTimer?.cancel();
    _collectGhostTimer = null;
    _collectGhostEntry?.remove();
    _collectGhostEntry = null;
  }

  /// 弹出「一键操作汇总提示」**根 Overlay 全屏浮层**（玄参 2026-10-07 真机复测修订）。
  ///
  /// 与 [_showCollectGhost] 同款做法：`Overlay.of(rootOverlay:true)` 的坐标系恒等于屏幕，
  /// `Positioned.fill + Center` 保证**确定性居中**（不再受花园页布局链约束来源影响，
  /// 修复真机「仍在屏幕最下面」）。`IgnorePointer`：提示不挡任何点击。
  /// 停留 [kOneClickHintHoldMs] + 淡出 [kOneClickHintFadeMs]（总 = 淡入 + 停留 + 淡出），
  /// 走完 onComplete 自清；另加定时器兜底（页面被卸载重建等极端情况）。
  void _showBatchHint(String label, int sunlight, {bool showSunlight = true}) {
    _removeBatchHint();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: _RisingHint(
              label: label,
              sunlight: sunlight,
              showSunlight: showSunlight,
              holdMs: kOneClickHintHoldMs,
              fadeOutMs: kOneClickHintFadeMs,
              riseDistance: 0, // 原地居中（玄参「要在中间显示」）
              large: true, // 居中提示加大档（玄参 2026-10-08「文字和提示框有点小」）
              pillKey: kOneClickBatchHintPillKey,
              sunIconAsset:
                  _rewardAssets.contains('assets/rewards/sunlight.png')
                      ? 'assets/rewards/sunlight.png'
                      : null,
              onComplete: _removeBatchHint,
            ),
          ),
        ),
      ),
    );
    _batchHintEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    // 兜底：动画 onComplete 因任何原因未触发也保证浮层被清走。
    final int totalMs = kHintFadeInMs + kOneClickHintHoldMs + kOneClickHintFadeMs;
    _batchHintTimer = Timer(
      Duration(milliseconds: totalMs + 300),
      _removeBatchHint,
    );
  }

  /// 移除汇总提示浮层（幂等）。
  void _removeBatchHint() {
    _batchHintTimer?.cancel();
    _batchHintTimer = null;
    _batchHintEntry?.remove();
    _batchHintEntry = null;
  }

  /// 弹出「收集成功」**根 Overlay 居中卡片**（玄参 2026-10-08：显示在屏幕中间、
  /// 1s 后淡出——替换原贴底 SnackBar）。
  ///
  /// 复用 [_showBatchHint] 同款浮层骨架 + [_RisingHint] 大档（`showSunlight: false`，
  /// 完整文案已含数值）；节奏：淡入 [kHintFadeInMs] → 停留 [kOneClickHintHoldMs]
  /// （= 1s）→ 淡出 [kOneClickHintFadeMs]，走完 onComplete 自清 + 定时器兜底。
  void _showCollectHint(String text) {
    _removeCollectHint();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext _) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: _RisingHint(
              label: text,
              sunlight: 0,
              showSunlight: false,
              holdMs: kOneClickHintHoldMs,
              fadeOutMs: kOneClickHintFadeMs,
              riseDistance: 0, // 原地居中（玄参「显示在屏幕的中间」）
              large: true,
              onComplete: _removeCollectHint,
            ),
          ),
        ),
      ),
    );
    _collectHintEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    const int totalMs = kHintFadeInMs + kOneClickHintHoldMs + kOneClickHintFadeMs;
    _collectHintTimer = Timer(
      const Duration(milliseconds: totalMs + 300),
      _removeCollectHint,
    );
  }

  /// 移除收集成功提示浮层（幂等）。
  void _removeCollectHint() {
    _collectHintTimer?.cancel();
    _collectHintTimer = null;
    _collectHintEntry?.remove();
    _collectHintEntry = null;
  }

  /// 批量收集（C45 聚合口径）：一次 _busy 闸门内逐条结算，**合并为一条提示**；
  /// 逐条失败互不阻塞（如重复收集抛错只跳过该条），最后一次刷新 + 修订号自增。
  ///
  /// 成功后按**实际发放结果合计**提示（数值从 [BloomRewardOutcome] 拼、不写死）；
  /// 文案按阶段前缀（全部为开花瞬间 → 裸正文，否则前缀「盛开的礼物：」），多段
  /// 正文用「 · 」拼接（如 `+10 ☀ 阳光 · +1 植物碎片 · +5 ☀ 阳光`）。
  Future<void> _collectRewards(List<PendingBloomReward> rewards) async {
    if (_busy || rewards.isEmpty) return;
    setState(() => _busy = true);
    final List<BloomRewardOutcome> outcomes = <BloomRewardOutcome>[];
    try {
      for (final PendingBloomReward reward in rewards) {
        try {
          final BloomRewardOutcome outcome = await ref
              .read(plantGrowthServiceProvider)
              .collectBloomReward(reward.id, DateTime.now());
          outcomes.add(outcome);
        } on PlantOperationException {
          // 单条失败（如已收过）跳过继续，不中断整批。
        }
      }
      if (outcomes.isNotEmpty) {
        ref.read(economyRevisionProvider.notifier).state++;
        await _reload(silent: true);
      }
    } catch (e) {
      _snack(_t.shared_op_failed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (outcomes.isNotEmpty && mounted) {
      // 合并提示：多段正文用「 + 」拼接（如「+10 ☀ 阳光 + +1 植物碎片」读起来怪，
      // 用「 · 」分隔）；阶段前缀按首条判定（instant / 晨露）。
      final String body = outcomes.map(_outcomeParts).join(' · ');
      final bool allInstant = outcomes.every((BloomRewardOutcome o) => o.isInstantPhase);
      _showCollectHint(allInstant ? body : _t.garden_collect_gift_prefix(body));
    }
  }

  /// 拔草 / 除虫（花园干扰物玩法，口径 C26 + 2026-10-03 动效口径）：
  /// 点图标 → 写库 → **播效果帧 + 音效**（期间 [_busy] 锁整页，防连点重复写账本）→
  /// 播完干扰物**渐变消失**（[kPestFadeOutMs] 淡出）→ 刷新草地 + 花盆上方弹
  /// 「XX成功，阳光+N」飘字（[_RisingHint]，自下而上飘动淡出）。数值全部取自常量。
  ///
  /// 走 [_run]：异常 → SnackBar 分因提示；成功后 → 经济修订号自增。
  ///
  /// F155-B：两个入口共用本方法 ——
  ///  · [plantId] 非 null = 有植物盆（走 [PlantGrowthService]，与改前逐字节一致）；
  ///  · [plantId] 为 null = **空花盆**（走 [EmptyPotService]，按 [potIndex] 定位，
  ///    奖励与植物完全一致、`refId = 'pot:<potIndex>'`）。
  ///
  /// ⚠️ [_busy] 闸门在这里同样必要：浮标与整格是**嵌套热区**，若手势穿透导致
  /// 同一帧触发两次，第二次会被 [_run] 挡掉，不会写出两条阳光账本行。
  ///
  /// 🔴 F156-A（玄参 2026-10-27）：**空花盆与有植物盆的演出与节流口径完全一致** ——
  /// 都要完整播 4.1s 除草 / 除虫效果帧 + 音效，动画期间 [_busy] 保持 true（整页锁住），
  /// 播完才淡出浮标 → 刷新 → 飘字。故本条路径**没有**任何 `plantId == null` 的特例分支。
  Future<void> _clearPest(
    String? plantId,
    int potIndex, {
    required bool weed,
  }) async {
    // 先上抑制闸门再写库：[_run] 内部的 `_reload(silent)` 与 economyRevision 监听
    // 触发的刷新都必须被挡住，否则动画还没播草/虫就没了（玄参真机实证）。
    // 票据制：本动作持有自己的票据，收尾时只释放“自己这张”。
    final int ticket = ++_suppressTicketSeq;
    _suppressTickets.add(ticket);
    final String? pid = plantId; // 局部提纯：闭包内类型提升稳定
    final bool ok = await _run(() {
      final DateTime now = DateTime.now();
      if (pid != null) {
        final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
        return weed ? svc.clearWeed(pid, now) : svc.clearPest(pid, now);
      }
      final EmptyPotService svc = ref.read(emptyPotServiceProvider);
      return weed
          ? svc.clearWeed(potIndex, now, perk: _perk)
          : svc.clearPest(potIndex, now, perk: _perk);
    });
    if (!ok) {
      _suppressTickets.remove(ticket); // 写库失败（无草可除等）：释放刷新，SnackBar 已给分因。
      return;
    }
    if (!mounted) return;
    // [_run] 的 finally 已解锁，这里重新锁上：动画播放期间（约 4.1s）整页不可再操作，
    // 防止动画中途再次点干扰物 / 养护（数据已写库但草地未刷新，界面与库不一致）。
    setState(() => _busy = true);
    // 🔴 F156-A（玄参 2026-10-27 原话「空盆首日免疫可以，清理的时候为什么不播放动画呢？
    // ……我觉得是需要完整的播放动画的」）：**空花盆与有植物盆走同一条动效路径** ——
    // 不再「只播音效 + 立刻淡出」，而是完整播 4.1s 除草 / 除虫效果帧 + 音效，播完才
    // 进淡出收尾。技术上之所以以前做不到，是 [EmptyPot] 当时没挂 [_potKey] →
    // [_playCareEffect] 取不到落点 context（早退分支①：无动画、无音效），
    // 现在空盆格也挂了同一把 key，落点与有植物盆**同源同尺寸**（见 [_buildCells]）。
    // 音效由 [_playCareEffect] 内部统一播（[AudioService.playSfx]），此处**不得**再播
    // 一次，否则双播。
    _playCareEffect(
      potIndex,
      weed ? CareEffectType.weed : CareEffectType.pest,
      onFinished: () =>
          _onClearAnimated(pid, potIndex, weed: weed, ticket: ticket),
    );
  }

  /// 除草 / 除虫动画播完的业务收尾（玄参 2026-10-03 口径）：
  /// 1) 干扰物渐变消失：把「本盆」加入 [_fadingClears] → 该浮标透明度淡出（数据尚未刷新）；
  /// 2) 淡出结束（本票据自己的定时器）→ 释放**本张**票据 → 不再抑制时才刷新草地
  ///    （草/虫此时才从数据层消失）+ 弹飘字；
  /// 3) 花盆上方弹「XX成功，阳光+N」飘字（[_RisingHint] 自下而上飘动淡出，走完自清）。
  ///
  /// F155-B：[plantId] 为 null = 空花盆（[_isFading] 按 `potIndex` 匹配浮标）。
  /// F156-A（玄参 2026-10-27）：空花盆与有植物盆**同一条收尾时序**（4.1s 动效播完 →
  /// 300ms 淡出 → 释放票据 + 刷新 + 飘字），本方法对两者无任何分支差异。
  ///
  /// 🔴 **每张票据一条独立定时器，绝不 cancel 别人的**（F155-B 缺陷的根治手段）：
  /// 若这里 `cancel()` 掉别人的定时器，那张票据就再没有释放点 → [_suppressTickets]
  /// 永久非空 → 本页此后永不刷新。
  /// 🟢 被钉住的是**「票据必须被释放」**：`empty_pot_ui_test.dart`「淡出窗口内重叠清除」
  /// 用例注释掉本方法的 `_suppressTickets.remove(ticket)` 会立刻变红（另 3 条旧用例同红）。
  /// ⚠️ 而「cancel 别人的」这一细节当前**不可观测**（取消时那条定时器早已触发完毕），
  /// 变异成 cancel-all 仍全绿 —— 详见 [_clearTimers] 注释，别误以为有守卫。
  ///
  /// 收尾顺序（与有植物盆同构，**既有行为**）：先 `_busy = false`（本帧即可再操作其它盆），
  /// 再等 [kPestFadeOutMs] 淡出结束才释放本张票据并刷新 —— 这 300ms 内其它动作的刷新
  /// 会被本张票据挡着（[_suppressReload] 仍 true），这正是「淡出期间草地不刷新」的
  /// 实现方式，不是缺陷。
  void _onClearAnimated(
    String? plantId,
    int potIndex, {
    required bool weed,
    required int ticket,
  }) {
    if (!mounted) return;
    final ({String? plantId, int potIndex, bool weed}) fading =
        (plantId: plantId, potIndex: potIndex, weed: weed);
    setState(() {
      _fadingClears.add(fading);
      _busy = false;
    });
    // 同票据重入（理论上不会发生）：先收掉自己那条，避免叠加两条定时器。
    _clearTimers.remove(ticket)?.cancel();
    _clearTimers[ticket] = Timer(const Duration(milliseconds: kPestFadeOutMs), () {
      _clearTimers.remove(ticket);
      if (!mounted) return;
      // 淡出结束：释放**本动作自己的票据**（其余在播动作的票据不受影响）
      // → 不再抑制时才刷新草地（草/虫此时才从数据层消失）→ 弹飘字。
      _suppressTickets.remove(ticket);
      setState(() {
        _fadingClears.remove(fading);
        _clearHint = (
          potIndex: potIndex,
          label: weed ? _t.garden_cleared_weed : _t.garden_cleared_pest,
          sunlight: (weed ? weedRewardOf(_perk) : pestRewardOf(_perk)).toInt(),
        );
      });
      unawaited(_reload(silent: true));
    });
  }

  /// 某盆的某类干扰物是否正在淡出。
  ///
  /// 有植物盆按 `plantId` 精确匹配（与 F155-B 改前逐字节一致，植物侧淡出不受影响）；
  /// 空花盆按 `potIndex` 匹配（[plantId] 传 null 即走这条）。
  bool _isFading({
    String? plantId,
    required int potIndex,
    required bool weed,
  }) {
    for (final ({String? plantId, int potIndex, bool weed}) f
        in _fadingClears) {
      if (f.weed != weed) continue;
      if (plantId != null) {
        if (f.plantId == plantId) return true;
      } else if (f.plantId == null && f.potIndex == potIndex) {
        return true;
      }
    }
    return false;
  }

  /// 把一条奖励结果拼成用户可见文案（`+N ☀ 阳光` / `+N 植物碎片` /
  /// `掉落{稀有度}种子` / `重复的{稀有度}种子已分解为 N 植物碎片`）。
  ///
  /// 🔴 **F144（玄参 2026-10-22 拍板）**：种子类提示**只讲档位（普通 / 精英）**，
  /// 不再点物种名 —— 旧口径「掉落「草莓」种子」在英文模式下会串出中文物种名，
  /// 且与选种弹窗/种子计数 chip 的「普通种子 / 精英种子」口径不一致。
  String _outcomeParts(BloomRewardOutcome o) {
    final List<String> parts = <String>[];
    if (o.sunlight > 0) parts.add(_t.garden_reward_sunlight(o.sunlight));
    if (o.decomposedSeedSpeciesId != null) {
      // 重复种子自动分解（玄参 2026-09-29）：此时 fragments 即分解所得，勿重复拼「+N 植物碎片」。
      parts.add(_t.garden_seed_decomposed(
        o.fragments,
        _rarityLabelOf(o.decomposedSeedSpeciesId!),
      ));
    } else {
      if (o.fragments > 0) parts.add(_t.garden_reward_fragments(o.fragments));
      final String? seed = o.seedSpeciesId;
      if (seed != null) parts.add(_t.garden_seed_dropped(_rarityLabelOf(seed)));
    }
    return parts.isEmpty ? _t.garden_gift_default : parts.join(' · ');
  }

  /// 物种 id → **稀有度档位文案**（普通 / 精英）。
  ///
  /// 判据单点 = `PlantSpecies.isPremium`（与选种弹窗的档位标签、种子计数 chip 同源）；
  /// 找不到该 id（历史已删物种，如 `species_star_flower` / `species_rainbow_fern`
  /// 在旧库里的残留）→ 回落**普通档**：普通是默认档，比裸「种子」信息更完整，
  /// 且不会因物种缺失而丢提示。
  ///
  /// ⚠️ 不动 `BloomRewardOutcome.seedSpeciesId` / `unlockSpecies`（发放事实与
  /// 按 id 记券的库存口径），本方法**只影响上屏文案**。
  String _rarityLabelOf(String speciesId) {
    for (final PlantSpecies sp in _species) {
      if (sp.id == speciesId) {
        return sp.isPremium ? _t.garden_rarity_premium : _t.garden_rarity_common;
      }
    }
    return _t.garden_rarity_common;
  }

  /// 打开「精品碎片」信息页（玄参 2026-09-28 计价模型）。
  ///
  /// **只读**：展示当前碎片余额 + 「各物种可用支付方式」，引导孩子去空花盆兑换种下。
  /// 打开「碎片与种子说明」卡（玄参 2026-10-06 口径修订：**屏幕中间弹出** +
  /// 内容**只讲三类资源的用途与获得方法**，不再逐物种列碎片价目；
  /// 入口 = 碎片 chip **与两个种子 chip**，点哪个都能打开）。
  Future<void> _openFragmentSheet() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (BuildContext ctx) => const _RewardCurrencyDialog(),
    );
  }

  /// 打开「花期调试」面板（**仅 debug**）：验收花开花谢链路用。
  ///
  /// 面板内所有动作都「写字段 + tickAll」走真实领域结算；动作后回调静默刷新草地
  /// （进度 / 可收集气泡 / 余额）。release 构建下入口不渲染，本方法不会被触达。
  ///
  /// [onPreviewGrowth]（玄参 2026-10-13）：分段成长**演出预览**——面板选中的物种 + 指定
  /// 过渡，直接播该段成长演出 + 物种音效（复用 [_playGrowthFx] 单点），**不改植物状态**。
  Future<void> _openDebugPanel() {
    return showBloomDebugPanel(
      context,
      onChanged: () {
        if (mounted) _reload(silent: true);
      },
      onPreviewGrowth: (GrowTransition t, String speciesDir) {
        _playGrowthFx(t, speciesDir);
      },
    );
  }

  /// 懒取某花盆格的稳定 GlobalKey（用于定位其屏幕坐标）。
  GlobalKey _potKey(int potIndex) =>
      _potKeys.putIfAbsent(potIndex, GlobalKey.new);

  /// 在指定花盆位置叠加一次性养护动效。
  ///
  /// 通过计算该花盆格相对页面根 Stack 的本地坐标，用 [Positioned] 把 [CareEffectOverlay]
  /// 精确摆到花盆上。若此时花盆未布局（context 为空，极端情况）则静默跳过，不抛错。
  ///
  /// 2026-09-28 起：效果帧序列（`assets/fx/care/{water|fertilize}`）+ 对应音频，
  /// 「帧速 = 音频时长」（玄参口径）；音频经 [AudioService.playSfx]（受「音效」开关控制）。
  /// 2026-10-03 扩展除草 / 除虫（`{weed|pest}`，27 帧），并支持 [onFinished] 业务收尾。
  void _playCareEffect(
    int potIndex,
    CareEffectType type, {
    VoidCallback? onFinished,
  }) {
    final BuildContext? potCtx = _potKey(potIndex).currentContext;
    final BuildContext? stackCtx = _pageStackKey.currentContext;
    if (potCtx == null || stackCtx == null || !mounted) {
      // 拿不到坐标（极端情况）也要保证业务收尾不丢：直接执行并退出。
      // 🔴 早退分支①：拿不到花盆/页面 Stack 的 context（无动效、无音效，仅业务收尾）。
      onFinished?.call();
      return;
    }
    final RenderBox? potBox = potCtx.findRenderObject() as RenderBox?;
    final RenderBox? stackBox = stackCtx.findRenderObject() as RenderBox?;
    if (potBox == null || stackBox == null) {
      // 🔴 早退分支②：RenderBox 缺失。
      onFinished?.call();
      return;
    }
    final Offset local = stackBox.globalToLocal(potBox.localToGlobal(Offset.zero));
    final Plant? plant = _occupantOf(potIndex);
    final PlantSpecies? species =
        plant == null ? null : _speciesOf(plant);
    if (!mounted) {
      // 🔴 早退分支③：坐标换算后组件已卸载。
      return;
    }
    final List<String> frames;
    final int durationMs;
    final AudioCue cue;
    switch (type) {
      case CareEffectType.water:
        frames = fxFrameAssets(kCareWaterFxDir, kFxFrameCount);
        durationMs = kCareWaterDurationMs;
        cue = AudioCue.careWater;
      case CareEffectType.fertilize:
        frames = fxFrameAssets(kCareFertilizeFxDir, kFxFrameCount);
        durationMs = kCareFertilizeDurationMs;
        cue = AudioCue.careFertilize;
      case CareEffectType.weed:
        frames = fxFrameAssets(kCareWeedFxDir, kCareWeedFrameCount);
        durationMs = kCareWeedDurationMs;
        cue = AudioCue.careWeed;
      case CareEffectType.pest:
        frames = fxFrameAssets(kCarePestFxDir, kCarePestFrameCount);
        durationMs = kCarePestDurationMs;
        cue = AudioCue.carePest;
    }
    AudioService.instance.playSfx(cue);
    setState(() => _activeEffect = _CareEffectSpec(
          type: type,
          offset: local,
          size: potBox.size,
          plant: plant,
          species: species,
          frames: frames,
          durationMs: durationMs,
          onFinished: onFinished,
        ));
  }

  /// 本页此刻是否真的「在屏幕上」（决定成长演出**现在播**还是**入队**）。
  ///
  /// 判据 = 外壳 tab 可见（[ChildTabAutoRefresh.tabVisible]）**或**祖先 TickerMode 启用：
  ///  · 非嵌入（路由直推 `/garden`）→ 恒可见；
  ///  · 生产外壳对隐藏 tab 包 `TickerMode(enabled: false)`（见 `child_shell_page` 的
  ///    `IndexedStack`）→ 隐藏时两个判据皆 false，演出不会浪费在看不见的页面上
  ///    （F132 的核心：新外壳在「今日」tab 就把花园页建好了）；
  ///  · ⚠️ 纯 widget 测试把 `GardenPage(embedded: true)` 直接挂在**无外壳**的
  ///    MaterialApp 下，`childShellTabIndexProvider` 恒为默认 0（今日）→ 只认
  ///    `tabVisible` 会把这类既有守卫（`garden_care_repro` / `garden_growth_sfx_no_care`）
  ///    误判成隐藏，成长演出全被入队 → 假红。TickerMode 兜底与「孩子在屏幕上看不看得到」
  ///    同义，正好覆盖「独立挂载」形态，且不影响生产判据。
  ///
  /// 🔴 `embedded: false` 的**未来风险**（F138 P2-d 备忘，勿删）：
  /// `/garden`、`/store` 这类「独立整屏路由」目前是**死路由** —— lib 内**没有任何**
  /// `go('/garden')` / `go('/store')` 调用点，只有深链（deep link）可达。它们
  /// `embedded: false` → 本判据与氛围音判据的 `!widget.embedded` 分支都恒为可见，
  /// **因此完全不过外壳的防沉迷闸门**（防沉迷只在 `ChildShellPage._onSelectTab` /
  /// 恢复路径上拦娱乐 tab）。将来若给它们加入口（按钮 / 深链推广 / 新引导流），
  /// **必须同时补闸门**，否则等于凭空开一条免计时通道。
  bool get _gardenVisible =>
      !widget.embedded || tabVisible || _tickerEnabled;

  /// 阶段里程碑序号（跨级跃迁取「最接近当前状态的那一段」用）：
  /// `seed = 0`、`sprout = 1`、`adult:growing = 2`、`adult:bloomed = 3`。
  ///
  /// 未知 / 脏数据一律按 0（= 没有可比对的基线，不补播），见 [_transitionOf]。
  int _milestoneRank(String stage, String status) {
    if (stage == PlantStage.adult.name) {
      return status == PlantStatus.bloomed.name ? 3 : 2;
    }
    if (stage == PlantStage.sprout.name) return 1;
    return 0;
  }

  /// 由「上次看到的阶段」「当前植株」推出要补播的过渡；null = 不播。
  ///
  /// 只认**前进**（当前里程碑 > 上次）：花谢回落（`bloomed → growing`）、救活以外的
  /// 状态抖动都不播。
  ///
  /// 🔴 跨级取舍（F132）：一次结算跨多级时只播**最接近当前状态的那最后一段** ——
  /// `seed → adult` 播 `sproutToAdult`、`sprout → adult+bloomed` 与
  /// `seed → adult+bloomed` 都播 `adultToBloomed`。理由是孩子离开期间可能过了好几天，
  /// 让他连等 2~3 段演出（每段 4s+）体验更差；播「最新的那一步」信息量最大。
  GrowTransition? _transitionOf(String before, Plant p) {
    final List<String> parts = before.split(':');
    if (parts.length != 2) return null; // 脏数据：当作没有基线
    final int beforeRank = _milestoneRank(parts[0], parts[1]);
    final int nowRank = _milestoneRank(p.stage.name, p.status.name);
    if (nowRank <= beforeRank) return null;
    // 里程碑序号 ↔ 枚举顺序一一对应（0→? 1→seedToSprout 2→sproutToAdult
    // 3→adultToBloomed），故直接取 `values[nowRank - 1]`。
    return GrowTransition.values[nowRank - 1];
  }

  /// 与「孩子上次看到」的快照 diff 出「升级」并触发生长演出（玄参 2026-09-28 拍板三段全播）。
  ///
  /// ## 数据源（F132，2026-10-19）
  /// 快照 = [SettingsStore.lastSeenPlantPhases]（SP，按孩子分键），**不再是内存
  /// `_lastPhases`**。原因：专注结束 `context.go('/')` 会重建整个外壳 → 旧
  /// `_GardenPageState` 连同 `_lastPhases` 一起销毁，而新外壳在「今日」tab 就构建
  /// 花园页并 `_reload()`（`tickAll` 在这里把 seed 结算成 sprout）→ 内存基线为空的
  /// 首次加载把升级静默吞掉，孩子回到花园只看到「已经是幼芽」。
  ///
  /// ## 判定
  ///  · **prev 里没有该 plantId → 不播**（首次安装 / 新种植物；保住「进花园不该看到
  ///    满屏动画」的反向行为）；
  ///  · 只播前进的里程碑（种子→幼苗 / 幼苗→成株 / 成株→盛开），跨级取舍见 [_transitionOf]；
  ///  · 枯萎 / 死亡态不播（欢快动画配蔫花很怪）；植物被铲除（prev 有、current 无）静默；
  ///  · 一帧只播一场演出：多株同时升级只播第一个，其余丢弃。
  ///
  /// ## 可见性（F132 的核心）
  /// 不可见时**不播**（否则演在 `TickerMode(enabled: false)` 的隐藏页上，孩子仍然
  /// 看不到），只入队 [_queuedGrowthFx]，且**不推进持久化快照** —— 保持「孩子还没
  /// 看过」的事实：即使此时 App 被杀，下次进花园仍会重新 diff 出这次升级。
  /// 真正可见时才播，播完（= 发起播放后）才把快照推进到 current。
  Future<void> _detectGrowthTransitions() async {
    final String childId = ref.read(accountServiceProvider).childId;
    final Map<String, String> current = <String, String>{
      for (final Plant p in _plants) p.id: '${p.stage.name}:${p.status.name}',
    };

    Map<String, String> prev;
    bool persistable = true;
    try {
      prev = await ref
          .read(settingsStoreProvider)
          .lastSeenPlantPhases(childId: childId);
    } catch (_) {
      // SP 未注入（纯 widget 测试 / 极端环境）→ 退化为内存快照（= 修复前行为）。
      persistable = false;
      prev = _lastPhases;
    }
    if (!mounted) return;

    // 找出**第一株**可补播的植物（一帧只播一场演出）。
    Plant? hitPlant;
    String? hitBefore;
    GrowTransition? hitTransition;
    for (final Plant p in _plants) {
      final String? before = prev[p.id];
      // prev 无该 id → 首次安装 / 新植物：没有「上次看到」的基线，不补播。
      if (before == null || before == current[p.id]) continue;
      if (p.status == PlantStatus.wilting || p.status == PlantStatus.dead) {
        continue; // 枯萎/死亡态不播欢快动画
      }
      final GrowTransition? t = _transitionOf(before, p);
      if (t == null) continue;
      hitPlant = p;
      hitBefore = before;
      hitTransition = t;
      break;
    }

    if (!_gardenVisible) {
      if (hitPlant != null && hitTransition != null && hitBefore != null) {
        // 同株后来者覆盖前者（基线与观测时刻都取最新）；Set 键按 plantId 前缀去重。
        //
        // 🔴 队列里存的是**基线**（`plantId|stage:status`）而不是算好的 transition：
        // 隐藏期间植物还可能继续跨级，若把 transition 定死在入队时刻，孩子回来时会先播
        // 「过时的前一段」，并因 `_growthFxInFlight` 闸门把真正的新跃迁吃掉
        // （QA 复核 P2-2 实测构造：入队 seedToSprout → 期间长成 adult → 回来只播发芽）。
        // 存基线则消费时用 [_transitionOf] 现算，跨级自然取「最接近当前状态的那一段」。
        final String plantId = hitPlant.id;
        _queuedGrowthFx.removeWhere((String k) => k.startsWith('$plantId|'));
        _queuedGrowthFx.add('$plantId|$hitBefore');
      }
      if (!persistable) _lastPhases = current;
      return;
    }

    if (hitPlant != null && hitTransition != null && hitBefore != null) {
      // 「同一动作」判定（C82）：养护动作可能同时触发成长跃迁——
      //  · 浇水 / 施肥把枯萎的盛开成株**救活** → `wilting → bloomed`（救活回跳）；
      //  · 浇水 / 施肥把幼苗推进成株 → `sprout → adult`。
      // 这两种情况下，**同一个动作已经播了养护音效**，若再发起成长音效，会因 SFX 只有
      // 一个共享播放器、口径「后发起者赢」（F116）把先发起的养护音效**静默作废**
      // （真机「有动画没声音」）。故此时**不播成长音效**、保留该动作本来的养护音效；
      // 演出动画照常播放。判定 = 救活回跳 || 养护动效正屏上（同一动作）。
      final bool recoveryReEntry =
          hitBefore.split(':')[1] == PlantStatus.wilting.name;
      // 「同一动作」= 本株的养护动效正屏上（其音效已随同一动作发起）→ 不再发起成长音效。
      // 用 `plant.id` 对齐，避免「A 株养护动效在屏时误伤 B 株的自然成长音效」。
      final bool sameActionCareSound =
          recoveryReEntry || (_activeEffect?.plant?.id == hitPlant.id);
      _playGrowthFx(
        hitTransition,
        growSpeciesDir(hitPlant.speciesId),
        playGrowthSfx: !sameActionCareSound,
      );
    }

    // 可见 → 孩子马上就能看到（或已经没升级）：快照推进到 current。
    await _rememberPhases(childId, current, persistable: persistable);
  }

  /// 消费「不可见期间攒下的补播」——只在页面真正可见时播，一次只播一个。
  ///
  /// 由 [onTabRefreshRequested] 在 `_reload` **之前**调用（顺序见其注释）。
  /// 播放**不 await**：只 await「把快照推进到 current」，避免 4s+ 的演出时长
  /// 拖住数据刷新。队列里指向的植物已被铲除 / 枚举未知 → 静默丢弃。
  ///
  /// 🔴 三条必须守住的规则（QA 复核 P2-2 / P2-3 实测构造出来的）：
  ///  1. **入场先看闸门**：上一场演出仍在飞（`_growthFxInFlight`）时**直接返回**，
  ///     保留队列且**不推进快照** —— 否则队列被清、快照前进，这次补播永久丢失。
  ///  2. **消费时重新判定**：队列存的是基线，`_transitionOf` 现场重算。这样隐藏期间
  ///     继续跨级的植物播的是「最新那一段」，而不是入队时算出的旧段落。
  ///  3. **枯萎 / 死亡不播**：与 [_detectGrowthTransitions] 口径一致（欢快动画配蔫花
  ///     很怪）。跳过但仍推进快照，否则该株会永久滞留在队列里反复入队。
  Future<void> _consumeQueuedGrowthFx() async {
    if (_queuedGrowthFx.isEmpty) return;
    // 仍不可见（如家长改档触发的无条件刷新）→ 留着，等真正可见再播。
    if (!_gardenVisible) return;
    // 规则 1：演出在飞 → 保留队列 + 不推进快照，等下一次可见刷新重试。
    if (_growthFxInFlight) {
      return;
    }

    final List<String> keys = _queuedGrowthFx.toList();
    for (final String key in keys) {
      final int sep = key.indexOf('|');
      if (sep <= 0) continue;
      final String plantId = key.substring(0, sep);
      final String before = key.substring(sep + 1);
      Plant? plant;
      for (final Plant p in _plants) {
        if (p.id == plantId) {
          plant = p;
          break;
        }
      }
      if (plant == null) continue; // 已被铲除 → 静默
      // 规则 3：枯萎 / 死亡态不播欢快动画。
      if (plant.status == PlantStatus.wilting ||
          plant.status == PlantStatus.dead) {
        continue;
      }
      // 规则 2：用基线现场重算，跨级自动取「最接近当前状态的那一段」。
      final GrowTransition? transition = _transitionOf(before, plant);
      if (transition == null) continue;
      // 补播是「孩子没看到的那一次」，没有对应的养护动作 → 正常播成长音效。
      final bool started = _playGrowthFx(
        transition,
        growSpeciesDir(plant.speciesId),
        playGrowthSfx: true,
      );
      if (!started) {
        // 闸门恰好在这几行之间被别的路径置位（极窄窗口）→ 保留队列，下次重试。
        return;
      }
      break;
    }

    // 无论播没播（含全部被跳过），都清队列 + 把快照推进到 current：
    //  · 一次只播一个（见 [_detectGrowthTransitions]），其余项本就丢弃；
    //  · 被跳过的枯萎株也必须推进，否则会永久滞留队列反复入队。
    _queuedGrowthFx.clear();
    await _rememberPhases(
      ref.read(accountServiceProvider).childId,
      <String, String>{
        for (final Plant p in _plants) p.id: '${p.stage.name}:${p.status.name}',
      },
    );
  }

  /// 把「孩子已看到」的阶段快照推进到 [phases]（内存兜底 + SP 持久化）。
  ///
  /// 写失败（SP 不可用）**绝不外抛**：调用方在 `_reload` 的 try 里，抛出去会变成
  /// 整页「加载失败」。
  Future<void> _rememberPhases(
    String childId,
    Map<String, String> phases, {
    bool persistable = true,
  }) async {
    _lastPhases = phases;
    if (!persistable) return;
    try {
      await ref
          .read(settingsStoreProvider)
          .setLastSeenPlantPhases(phases, childId: childId);
    } catch (_) {
      // SP 不可用：内存快照已写好，行为与修复前一致。
    }
  }

  /// 播放「屏幕中央焦点卡片」成长演出（玄参 2026-09-29 口径）+ 对应成长音频。
  ///
  /// 不再按花盆格定位（旧口径格子太小、与底层重叠显得乱）：卡片由
  /// [GrowthFxOverlay] 自己在屏幕正中渲染，播完整卡淡出后由 [onComplete] 移除。
  ///
  /// 2026-10-12 五物种接入：帧列表按 [speciesDir] 从 AssetManifest 异步实测
  /// （各组帧数 25~27 不同；缺失回退 sunflower），解析完再上屏。
  /// 2026-10-13 音效按物种（口径 C59）：两级回退「物种专属 → 通用兜底」（[_growthCue] 给兜底路径）。
  ///
  /// [playGrowthSfx]（C82 玄参 2026-10-16 小米真机「养护音效全无」）：是否播放成长音效。
  /// 养护动作（浇水 / 施肥）把枯萎的盛开成株**救活**时会顺带触发一次 `adultToBloomed`
  /// 演出（域层 `wilting → growing → bloomed` 两跳）；但**同一动作已经播了养护音效**，
  /// 而 SFX 全局只有一个共享播放器、口径「后发起者赢」（F116）→ 后发起的成长音效会把
  /// **先发起的养护音效静默作废**（真机「有动画没声音」）。故「救活回跳」这一次演出**不播**
  /// 成长音效、保留该动作本来的养护音效；真正的成长升级（种子→幼苗 / 幼苗→成株 /
  /// 首次开花 / 自然复开花）不受影响，照常播成长音效。
  ///
  /// ⚠️ v1 曾加「按跃迁身份 token 去重」（`'${plant.id}:${transition.name}:${bloomCount}'`）
  /// 作第二道防线，但**实测无法构造任何触发路径**（除 `_growthFxInFlight` 闸门外，同一株的
  /// 同一 `transition` 必然伴随 `bloomCount` 变化 → token 恒不同；且 `_lastPhases` 只会前进、
  /// 不会让同一跃迁被 diff 出第二次）→ 经 team-lead 复核确认是**零覆盖死代码**，已移除。
  /// 返回值 = **是否真的起播了**（`true` 表示闸门已置位、动画会上屏）。
  ///
  /// 为什么要有返回值（F132 QA 复核 P2-3）：补播的调用方需要区分「已起播」与
  /// 「被在飞闸门挡掉」——挡掉时必须**保留队列与快照**等下次重试，否则这次补播
  /// 会被静默吞掉、再无机会。普通调用点忽略返回值即可。
  bool _playGrowthFx(
    GrowTransition transition,
    String speciesDir, {
    bool playGrowthSfx = true,
  }) {
    if (!mounted) return false;
    // ⚠️ 去重闸门（2026-10-13 玄参实测「开花动画播了两次」）：同一个阶段跃迁可能被
    // 多条刷新路径各观测一次，若两次都上屏就会重播。演出是幂等的 → 在飞/在屏期间
    // 一律忽略后续请求（口径「一帧只播一场演出」）。
    if (_growthFxInFlight) {
      return false;
    }
    _growthFxInFlight = true;
    if (playGrowthSfx) {
      AudioService.instance.playSfxPaths(growSfxAssetCandidates(
        transition,
        speciesDir,
        _growthCue(transition).assetPath,
      ));
    } else {
      // 同一动作已播养护音效 → 不再发起成长音效（避免共享播放器互相作废）。
    }
    unawaited(() async {
      try {
        final List<String> frames =
            await resolveGrowFxAssets(speciesDir, transition);
        if (!mounted) return; // 异步间隙页面已卸载：不再上屏
        setState(() => _activeGrowth = _GrowthFxSpec(
              transition: transition,
              title: _growthTitle(transition),
              frames: frames,
            ));
      } catch (_) {
        // 帧解析异常（资源缺失等）：解除闸门，避免后续演出被永久挡住。
        _growthFxInFlight = false;
        rethrow;
      }
    }());
    return true;
  }

  /// 成长演出卡片标题文案（单一真源，勿散在 build 里）。
  String _growthTitle(GrowTransition t) {
    switch (t) {
      case GrowTransition.seedToSprout:
        return _t.garden_fx_sprout;
      case GrowTransition.sproutToAdult:
        return _t.garden_fx_grow;
      case GrowTransition.adultToBloomed:
        return _t.garden_fx_bloom;
    }
  }

  /// 成长过渡对应的**通用兜底**音频 cue（物种专属音效缺失时的回退路径来源；
  /// 候选链见 `growSfxAssetCandidates`，口径 C59）。
  AudioCue _growthCue(GrowTransition t) {
    switch (t) {
      case GrowTransition.seedToSprout:
        return AudioCue.growthSeedToSprout;
      case GrowTransition.sproutToAdult:
        return AudioCue.growthSproutToAdult;
      case GrowTransition.adultToBloomed:
        return AudioCue.growthAdultToBloomed;
    }
  }

  /// 按花园 tab 可见性启停氛围音计时器（build 内调用，无 setState，幂等）。
  ///
  /// 外壳用 IndexedStack 保活 tab：切走不 dispose，故用 `TickerMode.of` 判可见性
  /// （外壳对隐藏 tab 包了 `TickerMode(enabled: false)`，切换会触发本页重建）。
  /// 进入花园立即播一次，之后每 [kGardenAmbientIntervalSeconds] 秒一次；离开即停。
  void _syncAmbientTimer() {
    if (_ambientActive && _ambientTimer == null) {
      AudioService.instance.playGardenAmbient();
      _ambientTimer = Timer.periodic(
        const Duration(seconds: kGardenAmbientIntervalSeconds),
        (_) => AudioService.instance.playGardenAmbient(),
      );
    } else if (!_ambientActive && _ambientTimer != null) {
      _ambientTimer!.cancel();
      _ambientTimer = null;
      unawaited(AudioService.instance.stopGardenAmbient(reason: 'leave'));
    }
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
    if (_capacity >= _potCapLimit || _busy) return;
    final int cost = _expandCost;
    // 阳光不足：不给确认卡，直接分因提示（此时格子虽可点，但绝不扣费）。
    if (_balance < cost) {
      _snack(_t.garden_need_more_sun((cost - _balance).ceil()));
      return;
    }
    // F135：改用**统一确认卡**（奶油底 + 阳光金 + 明细面板 + 收窄宽度），
    // 标题 / 按钮字面量逐字不变；明细拆成「本次扩容 / 当前阳光」两行，
    // 容量变化作为底部高亮小结（保留原文案片段「A 盆 → B 盆」）。
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: _t.garden_expand_title,
      hero: const ConfirmCardBadge(icon: Icons.yard),
      rows: <ConfirmCardRow>[
        ConfirmCardRow(
          icon: Icons.wb_sunny,
          name: _t.garden_row_expand_cost,
          value: '−$cost ☀',
        ),
        ConfirmCardRow(
          icon: Icons.account_balance_wallet_outlined,
          name: _t.garden_row_balance,
          value: '${_balance.toInt()} ☀',
          muted: true,
        ),
      ],
      note: _t.garden_expand_note(_capacity, _capacity + 1),
      confirmLabel: _t.garden_confirm_deduct,
      cancelLabel: _t.shared_cancel,
    );
    if (ok != true) return; // 取消 / 关闭对话框 → 不扣任何阳光
    await _run(() =>
        ref.read(plantGrowthServiceProvider).expandPot(DateTime.now(), perk: _perk));
  }

  // ── 一键操作（口径 C29，玄参 2026-10-05 拍板）────────────────────────────

  /// 当前**权益**档位（阶段 4 门控判定；build 期与回调期读取一致）。
  ///
  /// ⚠️ 命名带 `Ent` 前缀以区别于本页既有的 **[AgeTier] 年龄段字段 `_tier`**
  /// （用于扩容定价，见 [`_expandCost`]）——两者语义不同（年龄段 vs 权益档），
  /// 若同名会编译冲突。
  ///
  /// 用 `read` 而非 `watch`：本页会因 tab 刷新 / 经济修订号 / 时间边界频繁重建，
  /// 购买发生在家长端，孩子回到花园 tab 即重读，足以拿到最新档位。
  EntitlementTier get _entTier => ref.read(entitlementProvider).tier;

  /// 当前档位的花盆容量上限（阶段 4：免费 [kFreeGardenPotQuota]=4 / 买断
  /// [kPremiumGardenPotQuota]=12）。**只用于「扩容」闸门，绝不压低已有盆位**（C69）。
  int get _potCapLimit =>
      featureQuotaFor(FeatureKey.gardenPotCapacity, _entTier);

  /// 免费档是否允许「一键操作」（D3：free 隐藏一键 FAB，单株动作不退化）。
  bool get _oneClickUnlocked =>
      featureAllowedFor(FeatureKey.oneClickCare, _entTier);

  /// 悬浮按钮出现条件：**存活株 ≥ [kOneClickMinPlants]**（「花园植物大于 3 盆」；
  /// 死亡残株不算）**且当前档位已解锁一键操作**（阶段 4：free 隐藏）。
  bool get _showOneClickFab =>
      _oneClickUnlocked &&
      _plants.where((Plant p) => p.status != PlantStatus.dead).length >=
          kOneClickMinPlants;

  /// 一键操作入口（悬浮按钮下拉菜单选中后）：
  ///  1. [PlantGrowthService.oneClickPlan] 纯读计划（跳过已达上限 / 间隔中的株）；
  ///  2. 空计划 → 分因提示（「没有需要护理的植物」等）；
  ///  3. 阳光不足 → **整体拦截**（一株都不执行）+ 提示还差多少；
  ///  4. 确认卡（**明示合计价**）→ 确认才执行；
  ///  5. 逐株执行既有单株方法（各自再校验一次额度，幂等安全）→ 每盆轻量反馈 +
  ///     顶部汇总飘字「一键XX成功 ×N ☀-M」（护理为 ☀+M）。
  Future<void> _onOneClick(PlantOneClickKind kind) async {
    if (_busy) return;
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    final DateTime now = DateTime.now();
    final OneClickPlan plan = await svc.oneClickPlan(kind, now, perk: _perk);
    if (!mounted) return;
    // 一键操作的「计划为空 / 不可执行」提示统一走**居中 Overlay 浮层**（玄参 2026-10-07
    // 截图实证：旧 `_snack` 是屏幕最下面的 SnackBar，停留久且不居中）——复用 [_showBatchHint]，
    // 与一键成功汇总**同节奏**（淡入 [kHintFadeInMs] → 停留 [kOneClickHintHoldMs] → 淡出
    // [kOneClickHintFadeMs]）；无阳光数值，故 `showSunlight: false`。
    switch (kind) {
      case PlantOneClickKind.water:
        if (plan.isEmpty) {
          _showBatchHint(_t.garden_batch_none_water, 0, showSunlight: false);
          return;
        }
      case PlantOneClickKind.fertilize:
        if (plan.isEmpty) {
          _showBatchHint(_t.garden_batch_none_fertilize, 0, showSunlight: false);
          return;
        }
      case PlantOneClickKind.care:
        if (plan.isEmpty) {
          _showBatchHint(_t.garden_batch_none_care, 0, showSunlight: false);
          return;
        }
    }
    // 阳光不足 → 整体拦截（玄参拍板：一株都不执行，避免「浇一半没阳光」的挫败）。
    if (kind != PlantOneClickKind.care && _balance < plan.totalCost) {
      _showBatchHint(
        _t.garden_need_more_sun((plan.totalCost - _balance).ceil()),
        0,
        showSunlight: false,
      );
      return;
    }
    // 确认卡（F135 起走**统一确认卡**卡壳）：明细 = 合计扣除 + 当前阳光，
    // 底部小结说明「对几盆各做几次」，标题三选一与按钮 `取消` / `确定` 逐字不变
    // （`one_click_batch_hint_center_test` / `qa_independent_p0_ui_test` 用 find.text 钉死）。
    final ({List<ConfirmCardRow> rows, String note, IconData icon}) brief =
        switch (kind) {
      PlantOneClickKind.water => (
          rows: <ConfirmCardRow>[
            ConfirmCardRow(
              icon: Icons.wb_sunny,
              name: _t.garden_row_total_cost,
              value: '−${plan.totalCost} ☀',
            ),
            ConfirmCardRow(
              icon: Icons.account_balance_wallet_outlined,
              name: _t.garden_row_balance,
              value: '${_balance.toInt()} ☀',
              muted: true,
            ),
          ],
          note: _t.garden_water_note(
              plan.plantIds.length, waterCostOf(_perk)),
          icon: Icons.water_drop_outlined,
        ),
      PlantOneClickKind.fertilize => (
          rows: <ConfirmCardRow>[
            ConfirmCardRow(
              icon: Icons.wb_sunny,
              name: _t.garden_row_total_cost,
              value: '−${plan.totalCost} ☀',
            ),
            ConfirmCardRow(
              icon: Icons.account_balance_wallet_outlined,
              name: _t.garden_row_balance,
              value: '${_balance.toInt()} ☀',
              muted: true,
            ),
          ],
          note: _t.garden_fertilize_note(
              plan.plantIds.length, fertilizeCostOf(_perk)),
          icon: Icons.eco_outlined,
        ),
      PlantOneClickKind.care => (
          rows: <ConfirmCardRow>[
            ConfirmCardRow(
              icon: Icons.cleaning_services_outlined,
              name: _t.garden_row_cleanup,
              value: _t.garden_cleanup_count(plan.actionCount),
            ),
            ConfirmCardRow(
              icon: Icons.account_balance_wallet_outlined,
              name: _t.garden_row_balance,
              value: '${_balance.toInt()} ☀',
              muted: true,
            ),
          ],
          note: _t.garden_care_note(weedRewardOf(_perk).toInt(),
              pestRewardOf(_perk).toInt()),
          icon: Icons.cleaning_services_outlined,
        ),
    };
    final bool? ok = await showChildConfirmCard(
      context: context,
      title: switch (kind) {
        PlantOneClickKind.water => _t.garden_oneclick_water_title,
        PlantOneClickKind.fertilize => _t.garden_oneclick_fertilize_title,
        PlantOneClickKind.care => _t.garden_oneclick_care_title,
      },
      hero: ConfirmCardBadge(icon: brief.icon),
      rows: brief.rows,
      note: brief.note,
      confirmLabel: _t.shared_ok,
      cancelLabel: _t.shared_cancel,
    );
    if (ok != true) return; // 取消 → 分毫不扣
    // 一键浇水 / 施肥各播**一次**对应养护音效（玄参 2026-10-06「对应着播放一次音效」；
    // 不逐株连播——N 盆 N 声会糊成一片）。一键护理的除草/除虫音效逐株照旧。
    switch (kind) {
      case PlantOneClickKind.water:
        AudioService.instance.playSfx(AudioCue.careWater);
      case PlantOneClickKind.fertilize:
        AudioService.instance.playSfx(AudioCue.careFertilize);
      case PlantOneClickKind.care:
        break;
    }
    // 执行前先抓「plantId → potIndex」映射（_run 末尾会刷新 _plants）。
    final Map<String, int> potOf = <String, int>{
      for (final Plant p in _plants) p.id: p.potIndex,
    };
    await _run(() async {
      switch (kind) {
        case PlantOneClickKind.water:
          for (final String id in plan.plantIds) {
            await svc.water(id, now, perk: _perk);
          }
        case PlantOneClickKind.fertilize:
          for (final String id in plan.plantIds) {
            await svc.fertilize(id, now, perk: _perk);
          }
        case PlantOneClickKind.care:
          for (final ({String plantId, bool weed}) t in plan.careTargets) {
            t.weed
                ? await svc.clearWeed(t.plantId, now, perk: _perk)
                : await svc.clearPest(t.plantId, now, perk: _perk);
          }
      }
    });
    if (!mounted) return;
    // 成功收尾：每盆轻量反馈 + 顶部汇总飘字。
    final Map<int, CareEffectType> pulse = <int, CareEffectType>{};
    switch (kind) {
      case PlantOneClickKind.water:
      case PlantOneClickKind.fertilize:
        final CareEffectType t = kind == PlantOneClickKind.water
            ? CareEffectType.water
            : CareEffectType.fertilize;
        for (final String id in plan.plantIds) {
          final int? pot = potOf[id];
          if (pot != null) pulse[pot] = t;
        }
      case PlantOneClickKind.care:
        for (final ({String plantId, bool weed}) t in plan.careTargets) {
          final int? pot = potOf[t.plantId];
          if (pot != null) {
            pulse[pot] = t.weed ? CareEffectType.weed : CareEffectType.pest;
          }
        }
    }
    final int careEarned = plan.careTargets.fold<int>(
      0,
      (int sum, ({String plantId, bool weed}) t) =>
          sum + (t.weed ? weedRewardOf(_perk) : pestRewardOf(_perk)).toInt(),
    );
    setState(() {
      _batchPulse
        ..clear()
        ..addAll(pulse);
    });
    // 汇总提示（**根 Overlay 全屏浮层**，确定性居中）：「一键XX成功 ×N」+ 阳光增减
    // （扣费负数 / 护理奖励正数），走 envelope 自清。
    final (String hintLabel, int hintSunlight) = switch (kind) {
      PlantOneClickKind.water =>
        (_t.garden_oneclick_water_ok(plan.plantIds.length), -plan.totalCost),
      PlantOneClickKind.fertilize =>
        (_t.garden_oneclick_fertilize_ok(plan.plantIds.length), -plan.totalCost),
      PlantOneClickKind.care =>
        (_t.garden_oneclick_care_ok(plan.actionCount), careEarned),
    };
    _showBatchHint(hintLabel, hintSunlight);
    // 一键护理 = 除草 / 除虫合集，成功时**整批只播一次**，且按**实际护理内容**选音效
    // （玄参 2026-10-07：「如果只有杂草，就播放除草的音效；如果有除虫和除草，就播放除虫
    // 的音效」）——存在任一害虫目标 → carePest；全是杂草 → careWeed；不逐株连播、不叠加。
    if (kind == PlantOneClickKind.care) {
      final bool hasPest = plan.careTargets.any((t) => !t.weed);
      AudioService.instance
          .playSfx(hasPest ? AudioCue.carePest : AudioCue.careWeed);
    }
    _batchPulseTimer?.cancel();
    // 清场定时器 = 本类脉冲显示时长 + 150ms 余量（浇水/施肥与音效等长，玄参 2026-10-06；
    // 一键护理 2026-10-07 对齐除虫音效 = kCarePestDurationMs + 150ms）。
    final int pulseClearMs = switch (kind) {
      PlantOneClickKind.water => kCareWaterDurationMs + 150,
      PlantOneClickKind.fertilize => kCareFertilizeDurationMs + 150,
      PlantOneClickKind.care => kCarePestDurationMs + 150,
    };
    _batchPulseTimer = Timer(Duration(milliseconds: pulseClearMs), () {
      if (!mounted) return;
      setState(() => _batchPulse.clear());
    });
  }

  /// 打开「选择要种的植物」弹窗（玄参 2026-09-28 计价模型 + C29 可重复种植；
  /// 2026-10-05 玄参口径修订：**屏幕中间弹出**（不再是底部抽屉）+ 卡片美化）。
  ///
  /// 列表顺序 = 物种表顺序（向日葵第一、月光兰第二…）。每张卡（[_PlantTile]）展示：
  ///  · 物种**成株/开花美术图**（[SpeciesPreviewArt]，缺失回退内置花卉图标）；
  ///  · 名称 + 稀有度徽章（普通绿 / 精英紫，卡片描边同色区分）；
  ///  · 支付方式按钮：**阳光/碎片用素材图标 + 数字**（不再写「N 阳光」文字）。
  /// 点击某支付方式按钮 → 关闭弹窗后 `plant(..., payWith: kind)`。
  ///
  /// 计价口径与领域层 [PlantGrowthService.plantPaymentOptions] **一致**（单点真源）。
  Future<void> _openPlantSheet(int potIndex) async {
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    final List<({PlantSpecies sp, List<_PlantPaymentButton> buttons})> rows =
        <({PlantSpecies sp, List<_PlantPaymentButton> buttons})>[];
    for (final PlantSpecies sp in _species) {
      // 优先读 [_reload] 预取缓存（玄参 2026-10-07「同步慢」）；未命中现场查兜底。
      rows.add((
        sp: sp,
        buttons: _paymentButtonsCache[sp.id] ??
            await _plantPaymentButtons(sp, svc),
      ));
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (BuildContext ctx) {
        // 🔴 弹窗上下文在页面 L10nScope 之外（根 Navigator），自包一层 scope。
        return L10nScope(
          child: Builder(
            builder: (BuildContext scopeCtx) {
              final AppLocalizations l10n = AppLocalizations.of(scopeCtx);
              return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF4E4), // 暖奶油底（与养护卡同层语言）
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFFFE3B0), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Text(l10n.garden_pick_plant_title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                // 余额行：阳光 / 碎片均用素材图标（玄参「阳光和植物碎片使用素材替换」）。
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _AssetGlyph(
                      asset: _rewardAssets
                              .contains('assets/rewards/sunlight.png')
                          ? 'assets/rewards/sunlight.png'
                          : null,
                      fallbackIcon: Icons.wb_sunny,
                      fallbackColor: const Color(0xFFE8A33D),
                    ),
                    Text(' ${_balance.toInt()}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 16),
                    _AssetGlyph(
                      asset: _rewardAssets
                              .contains('assets/rewards/fragment.png')
                          ? 'assets/rewards/fragment.png'
                          : null,
                      fallbackIcon: Icons.extension,
                      fallbackColor: const Color(0xFF7E57C2),
                    ),
                    Text(' $_fragmentBalance',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  // SingleChildScrollView + Column（非 ListView）：全部卡片**常驻
                  // 构建树**（懒加载列表的屏外项不构建，会漏 find 断言）。
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 卡片间留 10px 空隙（玄参 2026-10-05「卡片与卡片之间要留点
                        // 空隙，现在看起来太拥挤了」）。
                        for (int i = 0; i < rows.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(height: 10),
                          _PlantTile(
                            species: rows[i].sp,
                            buttons: rows[i].buttons,
                            rewardAssets: _rewardAssets,
                            onPay: (PlantCostKind kind) async {
                              Navigator.of(ctx).pop();
                              await _confirmAndPlant(
                                  rows[i].sp, kind, potIndex);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
              ); // Dialog（缩进保持原位，注释定位收口）
            }, // scopeCtx builder
          ), // Builder
        ); // L10nScope
      }, // dialog builder
    );
  }

  /// 计算某物种在「选择要种的植物」弹窗里的可用支付方式按钮（可用性 + 文案 + 禁用原因）。
  ///
  /// 计价口径与领域层 [PlantGrowthService.plantPaymentOptions] **一致**（单点真源）；
  /// 依赖账本与余额 → 异步，UI 不得自行重算价格。
  /// C29：植物**可重复种植**，不再按「已有存活植株」禁用（同物种可多株并存）；
  /// 禁用只看余额（阳光不足 / 碎片不足并写明当前片数）。
  ///  · free → 「免费」（仅向日葵首株）；seed → 「种子」（前置分档种子图，玄参 2026-10-07
  ///    「文案精简」）；sunlight → 「N 阳光」（阳光不足禁用）；fragments → 「N 植物碎片」
  ///    （碎片不足禁用）。
  Future<List<_PlantPaymentButton>> _plantPaymentButtons(
    PlantSpecies sp,
    PlantGrowthService svc,
  ) async {
    final List<PlantPaymentOption> options = await svc.plantPaymentOptions(sp);
    final List<_PlantPaymentButton> buttons = <_PlantPaymentButton>[];
    for (final PlantPaymentOption opt in options) {
      String label;
      bool enabled;
      String? reason;
      switch (opt.kind) {
        case PlantCostKind.free:
          // 免费入口现在只剩向日葵首株（2026-10-07：种子独立成第三支付方式，不再并入 free）。
          label = _t.garden_cost_free;
          enabled = true;
        case PlantCostKind.seed:
          // 第三支付方式（玄参 2026-10-07）：文案精简为「种子」，分档种子图在按钮组件前置。
          label = _t.garden_cost_seed;
          enabled = true;
        case PlantCostKind.sunlight:
          label = _t.garden_cost_sunlight(opt.amount);
          if (_balance < opt.amount) {
            enabled = false;
            reason = _t.garden_reason_no_sun;
          } else {
            enabled = true;
          }
        case PlantCostKind.fragments:
          label = _t.garden_cost_fragments(opt.amount);
          if (_fragmentBalance < opt.amount) {
            enabled = false;
            reason = _t.garden_reason_no_fragments(_fragmentBalance);
          } else {
            enabled = true;
          }
      }
      buttons.add(_PlantPaymentButton(
        kind: opt.kind,
        amount: opt.amount,
        label: label,
        enabled: enabled,
        disabledReason: reason,
        seedIsPremium: opt.kind == PlantCostKind.seed ? sp.isPremium : null,
      ));
    }
    return buttons;
  }

  /// 种植**二次确认**（玄参 2026-10-05 反馈「点阳光 / 植物碎片 / 种子都需二次确认，
  /// 防止误操作」）：选种弹窗点任一支付按钮 → 关闭选种弹窗 → 再弹一张确认卡
  /// （明示本次消耗与当前余额）→ 点「确定种植」才真正 `plant(...)`；
  /// 点「取消」/ 关闭 → 分毫不扣、种子券不消耗（领域层未触达）。
  ///
  /// 金额与 [PlantGrowthService.plantPaymentOptions] 同源重查（口径单点，不读
  /// 选种弹窗的快照）；余额在弹窗间隙变化的兜底由 `plant()` 内部再校验——
  /// 抛错走 [_run] 的分因 SnackBar，绝不静默扣费。
  Future<void> _confirmAndPlant(
    PlantSpecies sp,
    PlantCostKind kind,
    int potIndex,
  ) async {
    if (_busy) return;
    final PlantGrowthService svc = ref.read(plantGrowthServiceProvider);
    PlantPaymentOption? opt;
    for (final PlantPaymentOption o in await svc.plantPaymentOptions(sp)) {
      if (o.kind == kind) {
        opt = o;
        break;
      }
    }
    if (opt == null || !mounted) return;
    // F134：改走统一「种植确认卡」（奶油底 + 阳光金 + 物种预览 + 明细面板），
    // 文案与语义与旧 AlertDialog 完全一致（标题 / 按钮被测试钉死，见组件头注释）。
    // 每种支付方式给两行明细 + 一句「种下后剩余」，让孩子一眼看出扣完还剩多少。
    final ({List<PlantConfirmRow> rows, String? remaining}) brief = switch (kind) {
      PlantCostKind.free => (
          rows: <PlantConfirmRow>[
            PlantConfirmRow(
                icon: Icons.spa,
                name: _t.garden_row_plant,
                value: _t.garden_cost_free),
          ],
          remaining: null,
        ),
      PlantCostKind.seed => () {
          final int left = sp.isPremium ? _premiumSeedCount : _commonSeedCount;
          return (
            rows: <PlantConfirmRow>[
              PlantConfirmRow(
                icon: Icons.confirmation_number_outlined,
                name: _t.garden_row_use_seed(sp.isPremium
                        ? _t.garden_rarity_premium
                        : _t.garden_rarity_common),
                value: _t.garden_seed_count(1),
              ),
              PlantConfirmRow(
                icon: Icons.inventory_2_outlined,
                name: _t.garden_row_seed_balance,
                value: _t.garden_seed_count(left),
                muted: true,
              ),
            ],
            remaining: _t.garden_seed_remaining(left > 0 ? left - 1 : 0),
          );
        }(),
      PlantCostKind.sunlight => () {
          final int balance = _balance.toInt();
          final int remain = balance - opt!.amount;
          return (
            rows: <PlantConfirmRow>[
              PlantConfirmRow(
                icon: Icons.wb_sunny,
                name: _t.garden_row_plant,
                value: '−${opt.amount} ☀',
              ),
              PlantConfirmRow(
                icon: Icons.account_balance_wallet_outlined,
                name: _t.garden_row_balance,
                value: '$balance ☀',
                muted: true,
              ),
            ],
            remaining: _t.garden_sun_remaining(remain > 0 ? remain : 0),
          );
        }(),
      PlantCostKind.fragments => () {
          final int remain = _fragmentBalance - opt!.amount;
          return (
            rows: <PlantConfirmRow>[
              PlantConfirmRow(
                icon: Icons.extension_outlined,
                name: _t.garden_row_use_fragments,
                value: _t.garden_fragment_cost(opt.amount),
              ),
              PlantConfirmRow(
                icon: Icons.inventory_2_outlined,
                name: _t.garden_row_fragment_balance,
                value: _t.garden_fragment_count(_fragmentBalance),
                muted: true,
              ),
            ],
            remaining: _t.garden_fragment_remaining(remain > 0 ? remain : 0),
          );
        }(),
    };
    final bool? ok = await showPlantConfirmDialog(
      context: context,
      species: sp,
      rows: brief.rows,
      remainingText: brief.remaining,
      // i18n B1：文案在页级 scope 内解析后传给弹窗。
      // 🔴 F155-A（玄参 2026-10-27 真机实锤「英文模式显示 Plant the 葡萄?」）：
      // 这里曾经直传 `sp.name`（= 数据库落库用的**中文原名**），英文环境必然串中文。
      // 物种名一律经 `speciesNameOr(speciesId, species.name, l10n)` 单点解析
      // （与花盆格标签 2923 / 选种卡 3008 行同一写法）；未知 id 才回退 `species.name`。
      title: _t.plant_confirm_title(speciesNameOr(sp.id, sp.name, _t)),
      confirmLabel: _t.plant_confirm_ok,
      cancelLabel: _t.shared_cancel,
    );
    if (ok != true) return; // 取消 / 关闭 → 不扣任何资源
    // 种植音效（玄参 2026-10-07 交付 `cultivate.mp3`）：**仅种下成功后播放一次**
    // （_run 返回 true）；选择卡片弹出 / 取消 / 种植失败时一律不播。
    final bool planted = await _run(() async {
      await svc.plant(sp.id, potIndex, DateTime.now(), payWith: kind);
      // F155-B（玄参 2026-10-27 拍板）：种下后该盆的**空盆干扰物立即消失**
      //（不返还、不再显示）。与 `plant` 同一 `_run` 事务内完成，只触发一次刷新。
      // 🔴 独立 try/catch：「种下即清」是**附加语义**，不是种植成功的前置条件 ——
      //    空盆仓储不可用（纯 widget 测试宿主 / 极端环境）绝不能把种植判成失败。
      try {
        await ref.read(emptyPotServiceProvider).clearForPlanting(potIndex);
      } catch (e) {
        // 降级：该盆的记录会在下次 `_reload` 的 tick 里被「非空盆行」防御性清掉。
        // 🔴 同样不静默（与 [_refreshEmptyPots] 同纪律）：留一行诊断输出。
        debugPrint('[garden] clearForPlanting failed (pot $potIndex): $e');
      }
    });
    if (planted) AudioService.instance.playSfx(AudioCue.cultivate);
  }

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
      name: _t.garden_unknown_plant,
      rarity: Rarity.common,
      baseCostHigh: 0,
      baseCostLow: 0,
      growthHoursPerStage: kPlantGrowthHoursPerStageDefault,
    );
  }

  /// 物种档位查询（物种缺失时按普通档兜底）——种子奖励图标据此选分档图。
  bool _isPremiumSpecies(String speciesId) {
    for (final PlantSpecies s in _species) {
      if (s.id == speciesId) return s.isPremium;
    }
    return false;
  }

  /// 当前持有的**普通档**种子（免费种植券）个数（花园左上角种子计数，玄参 2026-10-05
  /// 「在植物碎片的右边，并列显示普通种子和精英种子的个数」）。
  int get _commonSeedCount {
    int n = 0;
    for (final PlantSpecies s in _species) {
      if (!s.isPremium && _unlockedSpecies.contains(s.id)) n++;
    }
    return n;
  }

  /// 当前持有的**精英档**种子个数（口径同 [_commonSeedCount]）。
  int get _premiumSeedCount {
    int n = 0;
    for (final PlantSpecies s in _species) {
      if (s.isPremium && _unlockedSpecies.contains(s.id)) n++;
    }
    return n;
  }

  /// 草地上的格子：0..capacity-1 是花盆（空/有植物），末尾追加「加盆」格（未达上限时）。
  ///
  /// 变更 A/B + v12 图标化：有植物且存在「可收集」待收集奖励的花盆，**花盆上方**叠加一排
  /// 头顶奖励图标（`Positioned` 叠加、**不占布局高度**，避免改动矮屏测试钉死的网格高度）。
  /// 图标由奖励三列（阳光 / 植物碎片 / 种子）派生，点击任一图标 = 收下该条 pending 全部奖励。
  ///
  /// F155-B：空花盆也会长杂草 / 害虫（玄参 2026-10-27 拍板）—— 空盆分支同样拿
  /// [_potDisturbances] 的状态画浮标，并与有植物盆**共用同一层叠加结构**（清除飘字 /
  /// 一键反馈继续按 `potIndex` 落在同一格上）。
  List<Widget> _buildCells() {
    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < _capacity; i++) {
      final Plant? occupant = _occupantOf(i);
      final PotDisturbance? disturbance =
          occupant == null ? _potDisturbances[i] : null;
      // 淡出识别（F155-B）：有植物盆按 plantId 精确匹配；空花盆按 potIndex 匹配。
      // 走 [_isFading]（集合查询）→ 多盆同时淡出互不覆盖。
      final Widget pot = occupant == null
          ? EmptyPot(
              // 🔴 F156-A：空盆格也必须挂本格的稳定 GlobalKey —— [_playCareEffect] /
              // [_showCollectGhost] 都靠 `_potKey(i).currentContext` 取落点 RenderBox。
              // 空盆不挂 key 时 `currentContext` 恒 null → 动效直接走「无动画无音效」
              // 早退分支（这正是 F155-B 当初跳过空盆动画的根因）。
              // 与 [GardenPot] **共用同一把** `_potKey(i)`：同一 potIndex 同一时刻只会
              // 有「空盆」或「有植物盆」其中一支在树上（[occupant] 互斥），不会重复挂载。
              key: _potKey(i),
              potIndex: i,
              onTap: () => _openPlantSheet(i),
              hasWeed: disturbance?.hasWeed ?? false,
              hasPest: disturbance?.hasPest ?? false,
              onClearWeed: () => _clearPest(null, i, weed: true),
              onClearPest: () => _clearPest(null, i, weed: false),
              weedFading: _isFading(potIndex: i, weed: true),
              pestFading: _isFading(potIndex: i, weed: false),
              perk: _perk,
            )
          : GardenPot(
              key: _potKey(i),
              plant: occupant,
              species: _speciesOf(occupant),
              perk: _perk,
              onTap: () => _openCareSheet(occupant.id, i),
              onClearWeed: () => _clearPest(occupant.id, i, weed: true),
              onClearPest: () => _clearPest(occupant.id, i, weed: false),
              weedFading:
                  _isFading(plantId: occupant.id, potIndex: i, weed: true),
              pestFading:
                  _isFading(plantId: occupant.id, potIndex: i, weed: false),
            );
      final List<PendingBloomReward> rewards = occupant == null
          ? const <PendingBloomReward>[]
          : (_collectibles[occupant.id] ?? const <PendingBloomReward>[]);
      // ⚠️ StackFit.expand：让花盆仍收到「紧约束」（与直接嵌入网格一致）——
      // GardenPot / EmptyPot 都用 LayoutBuilder 按格宽推导高度，收到松约束会缩成
      // 内容高度而错位。
      // 这里**常驻** Stack（不再只在有奖励时包）：干扰物浮标与清除提示都要叠在盆上，
      // 且两者都是 Positioned、不占布局高度 → 草地网格高度不受影响。
      cells.add(Stack(
        fit: StackFit.expand,
        children: <Widget>[
          pot,
          if (rewards.isNotEmpty)
            // 头顶奖励图标（玄参 2026-10-05 口径修订）：**叠在植物中间**（原「格顶
            // 一排」上移感太强）、整排**上下轻漂浮**（bob，±3px，有界 pump 纪律见
            // 组件注释）；`Positioned.fill` 叠加**不占布局高度**，其余区域命中穿透
            // 到花盆（只有图标 42×42 是 opaque 热区）。
            // C45：组件内部按列聚合（最多 3~4 图标），点击聚合收集。
            Positioned.fill(
              child: Center(
                child: BloomRewardIconsBar(
                  rewards: rewards,
                  availableAssets: _rewardAssets,
                  onCollect: (List<PendingBloomReward> covered,
                          RewardIconSpec spec) =>
                      _onCollectIconsTap(i, covered, spec, rewards),
                  isPremiumOf: _isPremiumSpecies,
                  bob: true,
                ),
              ),
            ),
          if (_clearHint?.potIndex == i)
            // 除草 / 除虫成功飘字（2026-10-03 玄参口径）：起始位置 = **格子垂直中心**
            // （≈花盆口上方一点 / 花的中部，玄参反馈「格顶太靠上」后下移），自下而
            // 上飘动 + 淡出（约 1.6s），走完经 onComplete 自行移除；文案数值取常量。
            // F155-B：空花盆走同一条飘字（`potIndex` 同格），奖励数字同源常量。
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: _RisingHint(
                  label: _clearHint!.label,
                  sunlight: _clearHint!.sunlight,
                  // 阳光图标与头顶奖励图标同源（玄参口径「就像之前那样显示」）；
                  // 资源缺失时 _RisingHint 内部回退内置 Icons.wb_sunny。
                  sunIconAsset:
                      _rewardAssets.contains('assets/rewards/sunlight.png')
                          ? 'assets/rewards/sunlight.png'
                          : null,
                  onComplete: () {
                    if (mounted) setState(() => _clearHint = null);
                  },
                ),
              ),
            ),
          if (_batchPulse.containsKey(i))
            // 一键操作的每盆轻量反馈（C29）：小图标短暂浮现淡出（约 1.1s 整批清除），
            // 不播 4s 完整动效（逐盆播完整动画 5 盆要 20s+，玄参拍板「每盆只加轻量反馈」）。
            Positioned.fill(
              child: Center(
                child: _PotPulse(type: _batchPulse[i]!),
              ),
            ),
        ],
      ));
    }
    if (_capacity < _potCapLimit) {
      cells.add(ExpandPotSlot(
        cost: _expandCost,
        shortfall: (_expandCost - _balance).ceil(),
        busy: _busy,
        onTap: _confirmAndExpand,
      ));
    }
    return cells;
  }

  /// 正常态花盆区：**锁 3 行高度 + 溢出时区域内纵向滚动**（C47e：2 行 → 3 行，
  /// 一屏可见 3×3 = 9 格，填满草地空白；行数仍由纯函数统一决定）。
  ///
  /// 可视高度的**唯一真源**是纯函数 [gardenGridVisibleHeight]（页面不再自己内联算行高/行数，
  /// 「改行数 → 测试必红」）。网格区顶部取自 `LayoutBuilder` 的剩余高度，底界取自背景图映射
  /// [gardenPotAreaBottom]，保证滚动时花盆永不压到背景植物。
  ///
  /// **C61 平板适配**：网格净宽改走 [gardenGridNetWidthOf]（平板钳到
  /// [kGardenGridMaxWidth] 并居中，两侧露出草地）；手机宽度下钳制不生效，**零变化**。
  Widget _buildGardenBody(Size size) {
    final double potAreaBottom = gardenPotAreaBottom(size);
    const double pagePadH = 12;
    const double gridSpacing = 6;
    // C61 平板适配：手机 = size.width − 24（不变）；平板钳到 kGardenGridMaxWidth
    // （800 → 480），网格水平居中、两侧露出草地。
    // ⚠️ 该值必须**同源**喂给 ① GardenGrid 的渲染宽度 ② 纯函数的 gridInnerWidth，
    // 否则「量出来的行高」与「画出来的行高」不一致 → 溢出或大片空白。
    final double gridInnerWidth =
        gardenGridNetWidthOf(size.width, pagePadH: pagePadH);

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
              //
              // ⚠️ 此处**不加任何额外顶栏**：花盆网格的可视高度由纯函数
              // [gardenGridVisibleHeight] 单独钉死（矮屏用例要求顶部无多余占位），
              // 故「精品碎片」入口改为根 Stack 的浮层（见 build 内 Positioned）。
              if (!widget.embedded) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SunlightPill(),
                ),
                const SizedBox(height: 10),
              ],
              // Flexible（loose）：网格区占据「网格顶部 → 底界」的剩余高度；用 LayoutBuilder
              // 量出该剩余高度 → 还原网格区顶部 y → 交给纯函数算「锁 3 行 + 不越菜地上沿」。
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
                      // 平板下限宽（gridInnerWidth ≤ size.width − 2×pagePadH，不会溢出）；
                      // topCenter 同时完成**水平居中**，两侧自然露出草地背景。
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: gridInnerWidth,
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
    // ref.listen 只能写在 build() 内（写在 initState 会触发框架断言）；且必须在
    // ConsumerWidget.build **顶层**调用 —— Riverpod 的 `debugDoingBuild` 断言
    // 不允许在嵌套 Builder 闭包内调用，故注册在进入页级 L10nScope 之前。
    ref.listen(economyRevisionProvider, (_, __) {
      if (mounted) _reload(silent: true);
    });
    // 🔴 页级 L10nScope（i18n B1）：全页文案经 AppLocalizations 解析；
    // Builder 的 context 参数遮蔽外层 context，位于 scope 之下，
    // 可安全 AppLocalizations.of(context) 并赋给 [_l10n] 供异步回调使用。
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          _l10n = AppLocalizations.of(context);
        // 经济修订号监听已上移至 build() 顶层（Riverpod 断言要求，见上方 ref.listen）。

        // 花园氛围音可见性（玄参 2026-09-28；F71 2026-10-05 修订；F138 2026-10-19 再修订）。
        // ⚠️ 原实现按 TickerMode 依赖重建判可见性，但 IndexedStack 更新隐藏子树的
        // 时机不保证本页立即重建 → 切 tab 后氛围音继续播完整曲（玄参实测）。
        // F138 追加「外壳在台前」判据：外壳被 `context.go('/parent')` 销毁重建后，
        // tab **记忆**仍是 2（花园），若只看索引，重建出来的本页会误判自己可见 →
        // 孩子在「今日」tab 上听到花园背景音每 30s 无限补播（玄参真机反馈）。
        final bool gardenVisible = !widget.embedded ||
            (ref.watch(childShellOnStageProvider) &&
                ref.watch(childShellTabIndexProvider) == kChildTabIndexOfGarden);
        if (gardenVisible != _ambientActive) {
          _ambientActive = gardenVisible;
          _syncAmbientTimer();
        }

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
              content = Center(child: Text(_t.garden_load_failed(_error!)));
            } else {
              content = _buildGardenBody(size);
            }

            // 整页叠放：背景铺满 → 内容区（锁 2 行 + 区域内滚动）→ 左下角木牌热区
            // → 养护成功的一次性动效叠加层（仅播放期间存在）。
            // 木牌在左下、花盆区在中上部，互不重叠，故不会挡住花盆点击。
            // ⚠️ `clipBehavior: Clip.none`（2026-09-29）：养护效果帧按玄参口径「略大于格宽、
            // 允许越界」，帧顶部会落在花盆格**上方**（水壶 / 肥料袋位置）。Stack 默认
            // `hardEdge` 会把越界部分裁掉 → 只看得到水柱看不到壶。
            return Stack(
              key: _pageStackKey,
              clipBehavior: Clip.none,
              children: <Widget>[
                background,
                Positioned.fill(child: content),
                Positioned.fromRect(
                  rect: gardenSignScreenRect(size),
                  child: GardenSignHotspot(onTap: _showGardenHelp),
                ),
                // 精品碎片入口（变更 B；2026-10-05 玄参口径修订：**移到花园背景图左上角**，
                // 原右下角与一键操作按钮挤在一起）。根 Stack 浮层——**不占布局高度**，避免
                // 改动花盆网格的可视高度（矮屏用例硬钉该高度）。内嵌 tab 时左上角无阳光胶囊
                // （在 shell AppBar）；独立路由 /garden 左上角有胶囊 → 下移到胶囊之下。
                if (!_loading && _error == null)
                  Positioned(
                    left: 12,
                    top: widget.embedded ? 12 : 60,
                    child: Row(
                      children: <Widget>[
                        _FragmentEntry(
                          balance: _fragmentBalance,
                          onTap: _openFragmentSheet,
                        ),
                        const SizedBox(width: 8),
                        // 种子计数（2026-10-05 玄参「碎片右边并列显示普通/精英种子个数」）：
                        // 分档种子素材图 + ×N；素材缺失回退 🌰。2026-10-06：点击也打开
                        // 「碎片与种子」说明卡（玄参「点击种子就不会弹出来，都需要弹出」）。
                        _SeedCountChip(
                          count: _commonSeedCount,
                          asset: 'assets/rewards/seed_common.png',
                          onTap: _openFragmentSheet,
                        ),
                        const SizedBox(width: 6),
                        _SeedCountChip(
                          count: _premiumSeedCount,
                          asset: 'assets/rewards/seed_premium.png',
                          onTap: _openFragmentSheet,
                        ),
                      ],
                    ),
                  ),
                // 一键操作悬浮按钮（C29；2026-10-05 玄参口径修订：移到右下角贴底——
                // 原上方碎片入口已移走）+ 点开/再点收拢的展开卡（宽度与胶囊一致）。
                // 存活株 ≥ kOneClickMinPlants 才出现（「花园植物大于 3 盆」，死亡残株不算）。
                if (!_loading && _error == null && _showOneClickFab)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _OneClickFab(onSelected: _onOneClick),
                  ),
                // 一键操作汇总提示（C29）已于 2026-10-07 改为**根 Overlay 全屏浮层**
                // （见 [_showBatchHint]）——不再挂在根 Stack 内，避免真机「贴底」问题。
                // 「花期调试」入口（**仅调试构建**）：同样为根 Stack 浮层——紧凑、不占布局
                // 高度（避免把矮屏用例顶出视口 / 触发 overflow），release 构建自动不渲染。
                // 摆在右上角（左上角是阳光胶囊、左下角木牌、右下角碎片入口）。
                //
                // F139（玄参 2026-10-20 截图清单）：**截图会入镜**——花园页是商店图的主场景，
                // 这个 bug 图标就在右上角。故与「我的」页 / 家长今日页 / 家长设置页统一走
                // [shouldShowDebugUi] 单点判据（截图构建加 `--dart-define=HIDE_DEBUG_UI=true`
                // 即可隐藏）；未加 define 时 `kHideDebugUi` 为 false → 行为**与修前逐位一致**，
                // 日常调试能力不衰减。
                if (shouldShowDebugUi(
                      debugMode: kDebugMode,
                      hideForScreenshots: kHideDebugUi,
                    ) &&
                    !_loading &&
                    _error == null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: BloomDebugEntry(onTap: _openDebugPanel),
                  ),
                // 养护成功动效：精确摆到对应花盆格之上（效果帧叠加 + 音频），有限时长，结束自移除。
                //
                // 🔴 C82 关键修复（玄参 2026-10-16 小米真机「盛开动画播两次」的真因）：本 Stack 的
                //    children 是按**位置**（index）做元素复用的，而上面几个浮层是**条件渲染**的。
                //    「养护动效 `_activeEffect` 结束置 null」会把它从 children 里移除 → 后面所有
                //    兄弟节点**整体前移一位** → [GrowthFxOverlay] 落到原先 [CareEffectOverlay] 的
                //    index 上。**若两处浮层都无 Key**：同为 `Positioned`、`canUpdate` 在
                //    `null==null` 下为 true → **原地复用**该元素、只换 child → 子类型不匹配 →
                //    旧 GrowthFxOverlay 元素被卸载、**新建 State** → 动画从第 0 帧**重放**（播两次）。
                //    修法：两处浮层各加**稳定 Key**（`_kCareEffectOverlayKey` / `_kGrowthFxOverlayKey`）。
                //    ⚠️ 实测边界（QA 复核 B）：**任一把 Key 在位即可断链**（顶对齐因 key 不匹配提前
                //    停止，改走自底向上匹配 → GrowthFx 元素被保住）；**两把都缺**才 remount。两把都留。
                if (_activeEffect != null)
                  Positioned(
                    key: _kCareEffectOverlayKey,
                    left: _activeEffect!.offset.dx,
                    top: _activeEffect!.offset.dy,
                    width: _activeEffect!.size.width,
                    height: _activeEffect!.size.height,
                    child: CareEffectOverlay(
                      type: _activeEffect!.type,
                      plant: _activeEffect!.plant,
                      species: _activeEffect!.species,
                      frames: _activeEffect!.frames,
                      durationMs: _activeEffect!.durationMs,
                      width: _activeEffect!.size.width,
                      height: _activeEffect!.size.height,
                      onComplete: () {
                        // 先取业务收尾回调（除草 / 除虫：渐变消失 → 刷新 → 飘字），
                        // 再移除叠加层 —— 置 null 后 spec 就取不到了。
                        final VoidCallback? finished = _activeEffect?.onFinished;
                        if (mounted) setState(() => _activeEffect = null);
                        finished?.call();
                      },
                    ),
                  ),
                // 成长过渡演出（玄参 2026-09-29 改口径）：**屏幕中央焦点卡片**内放大播放
                // 序列帧 + 成长音频，播完整卡淡出（组件内部处理），结束自移除。
                // 🔴 C82：稳定 Key（见上方养护动效处的说明）——防「养护动效进出导致本演出被 remount 重播」。
                if (_activeGrowth != null)
                  Positioned.fill(
                    key: _kGrowthFxOverlayKey,
                    child: GrowthFxOverlay(
                      frames: _activeGrowth!.frames,
                      durationMs: _activeGrowth!.transition.durationMs,
                      title: _activeGrowth!.title,
                      onComplete: () {
                        // 演出收尾：移除卡片 + 解除去重闸门（允许下一次跃迁演出）。
                        if (mounted) {
                          setState(() {
                            _activeGrowth = null;
                            _growthFxInFlight = false;
                          });
                        } else {
                          _growthFxInFlight = false;
                        }
                      },
                    ),
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
            title: Text(_t.garden_title),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: _t.garden_refresh_tooltip,
                onPressed: _busy ? null : _reload,
              ),
            ],
          ),
          body: page,
        );
        }, // builder 闭包
      ), // Builder
    ); // L10nScope
  }
}

/// 一键汇总提示**胶囊本体**的公开 Key（供 widget 测试精确度量其屏幕中心，
/// 验证「确定性居中」；见 [kOneClickBatchHintCenterTolerance]）。
const Key kOneClickBatchHintPillKey = Key('oneClickBatchHintPill');

/// 一键汇总提示「居中」判定的像素容差（widget 测试用）：胶囊中心与屏幕中心的偏差上限。
const double kOneClickBatchHintCenterTolerance = 20;

// ── 一键操作 FAB 的自适应宽度常量（F157-BUG-1）─────────────────────────────
//
// 玄参 2026-10-27 小米 14 Pro 真机：英文界面下展开卡右侧被裁、debug 报
// `RenderFlex overflowed by 4 pixels`。根因是宽度钉死 108 —— 中文够、英文不够。
// 现口径：宽度由「实测最宽那条」决定，下面这些常量既是**测量输入**也是
// **渲染输入**（同一份数值，测量与排版不可能漂移）。

/// 一键操作胶囊 / 展开卡的宽度**下限**（= 改造前的固定宽，中文侧逐像素零回归）。
const double kOneClickWidthFloor = 108;

/// 一键操作浮层与屏幕左右边缘的安全边距（与 `Positioned(right: 12)` 同值）：
/// 宽度上限 = 屏宽 − 2 × 本值，防极端长文案 / 极小屏把卡片顶出屏幕。
const double kOneClickSafeMargin = 12;

/// 一键操作行内图标边长（× `uiScaleOf`）；胶囊图标同值。
const double kOneClickIconSize = 16;

/// 操作行内「图标 → 文案」间距。
const double kOneClickIconGap = 6;

/// 操作行内左右内边距（单侧）。
const double kOneClickRowHPad = 10;

/// 胶囊内「图标 → 标题」间距。
const double kOneClickCapsuleIconGap = 4;

/// 一键操作**收拢态胶囊**的公开 Key（测试度量「胶囊与展开卡严格等宽」用）。
const Key kOneClickCapsuleKey = Key('gardenOneClickCapsule');

/// 一键操作**展开卡**的公开 Key（同上）。
const Key kOneClickCardKey = Key('gardenOneClickCard');

/// 除草 / 除虫成功飘字（2026-10-03 玄参口径）：半透明白胶囊，**自下而上飘动 +
/// 淡出**（总时长 [kClearHintRiseMs]）。前 10% 淡入、中段平稳上飘、后 30% 淡出，
/// 走完经 [onComplete] 通知花园页移除。有限时长动画（可被 pumpAndSettle 结束）。
///
/// 内容 = `[label] [阳光图标] [+N]`（玄参：「阳光+1」的阳光要用**图标**不是文字，
/// 与头顶奖励图标同源 `assets/rewards/sunlight.png`，缺失回退内置 `Icons.wb_sunny`）。
/// 胶囊外套 [FittedBox]：窄格里内容超宽时**等比缩小**而不是省略号截断
/// （玄参反馈「除草成功，阳光+1 显示不全」的修复，与头顶图标条同口径）。
class _RisingHint extends StatefulWidget {
  /// 「除草成功」/「除虫成功」。
  final String label;

  /// 奖励阳光数（渲染成「+N」跟在阳光图标后）。
  final int sunlight;

  /// 是否渲染尾段「[阳光图标] +N」（默认 true）。
  /// 「计划为空 / 不可执行」类**居中提示**只有文案、无阳光数值 → 传 false（玄参 2026-10-07）。
  final bool showSunlight;

  /// 阳光图标 asset（null 或加载失败 → 回退内置 `Icons.wb_sunny`）。
  final String? sunIconAsset;

  /// 动画走完回调（花园页在此清掉 [_clearHint] 移除本组件）。
  final VoidCallback? onComplete;

  /// **停留时长**（毫秒，可选）· 与 [fadeOutMs] 同时给出时启用**显式透明度包络**：
  /// 淡入 [kHintFadeInMs] → 停留 [holdMs] → 淡出 [fadeOutMs]，总时长 = 三者之和。
  /// 一键汇总提示用（玄参 2026-10-07「显示 1s 就可以了，然后淡出消失」）；
  /// 不给则走旧口径（总时长 [kClearHintRiseMs] + 比例包络，除草/除虫沿用）。
  final int? holdMs;

  /// **淡出时长**（毫秒，可选）· 见 [holdMs]。
  final int? fadeOutMs;

  /// 上飘距离（像素）；0 = 原地不动（居中提示模式）。
  /// 一键汇总提示传 0（玄参 2026-10-07「要在中间显示」），除草/除虫维持默认上飘。
  final double riseDistance;

  /// 胶囊本体的可选 Key（供 widget 测试**精确度量**其屏幕中心，验证「确定性居中」）。
  final Key? pillKey;

  /// **加大档**（玄参 2026-10-08「没有需要护理和操作的提醒卡片文字和提示框有点小」）：
  /// 居中的一键汇总/空提示用（文字 13→16、内边距与圆角同步放大）；
  /// 除草/除虫小飘字维持紧凑档不变。
  final bool large;

  const _RisingHint({
    required this.label,
    required this.sunlight,
    this.showSunlight = true,
    this.sunIconAsset,
    this.onComplete,
    this.holdMs,
    this.fadeOutMs,
    this.riseDistance = kClearHintRiseDistance,
    this.pillKey,
    this.large = false,
  });

  @override
  State<_RisingHint> createState() => _RisingHintState();
}

class _RisingHintState extends State<_RisingHint>
    with SingleTickerProviderStateMixin {
  /// 是否启用「显式包络」（淡入 / 停留 / 淡出分段时间给定）。
  bool get _explicitEnvelope => widget.holdMs != null && widget.fadeOutMs != null;

  /// 动画总时长：显式包络 = 淡入 + 停留 + 淡出；否则沿用 [kClearHintRiseMs]。
  late final int _totalMs = _explicitEnvelope
      ? kHintFadeInMs + widget.holdMs! + widget.fadeOutMs!
      : kClearHintRiseMs;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs),
  );

  /// 上飘位移：0 → -`widget.riseDistance`（easeOut，起快后缓；0 = 原地居中）。
  late final Animation<double> _rise = Tween<double>(
    begin: 0,
    end: -widget.riseDistance,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  /// 透明度包络（0..1 的动画进度 → 透明度）。
  ///
  /// · 显式包络：按**毫秒分段**——淡入 [kHintFadeInMs]、停留 [holdMs]、淡出 [fadeOutMs]；
  /// · 旧口径：按比例——前 10% 淡入、中段 1.0、后 30% 淡出。
  double _alpha(double t) {
    if (!_explicitEnvelope) {
      return t < 0.10
          ? t / 0.10
          : t > 0.70
              ? (1 - (t - 0.70) / 0.30).clamp(0.0, 1.0)
              : 1.0;
    }
    final double ms = t * _totalMs;
    final int fadeOutStart = _totalMs - widget.fadeOutMs!;
    if (ms < kHintFadeInMs) {
      return (ms / kHintFadeInMs).clamp(0.0, 1.0);
    }
    if (ms > fadeOutStart) {
      return ((_totalMs - ms) / widget.fadeOutMs!).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener(_onStatus);
    _ctrl.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onComplete?.call();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) {
        final double t = _ctrl.value;
        // 透明度包络：旧口径前 10% 淡入 → 中段 1.0 → 后 30% 淡出；显式包络见 [_alpha]。
        final double alpha = _alpha(t);
        return Transform.translate(
          offset: Offset(0, _rise.value),
          child: Opacity(
            opacity: alpha,
            // FittedBox：内容超宽时等比缩小（不截断）——窄格不再「显示不全」。
            child: FittedBox(
              fit: BoxFit.scaleDown,
            child: Container(
              key: widget.pillKey,
              padding: EdgeInsets.symmetric(
                horizontal: widget.large ? 18 : 10,
                vertical: widget.large ? 9 : 4,
              ),
                decoration: BoxDecoration(
                  color: const Color(0xEFFFFFFF),
                  borderRadius:
                      BorderRadius.circular(widget.large ? 16 : 12),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: widget.large ? 16 : 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF8D6E00),
                      ),
                    ),
                    // 无阳光数值的提示（计划为空 / 不可执行）只显示文案，不渲染尾段。
                    if (widget.showSunlight) ...<Widget>[
                      const SizedBox(width: 4),
                      _sunIcon(),
                      const SizedBox(width: 2),
                      Text(
                        // C29：一键操作汇总飘字带负数（扣费）→ 显示「-N」而非「+-N」。
                        widget.sunlight >= 0
                            ? '+${widget.sunlight}'
                            : '${widget.sunlight}',
                        style: TextStyle(
                          fontSize: widget.large ? 16 : 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE8A33D),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 阳光图标：美术图（16×16，显式宽高；加大档 20×20）优先，缺失/失败回退
  /// 内置 `Icons.wb_sunny`。
  Widget _sunIcon() {
    final double size = widget.large ? 20 : 16;
    final String? path = widget.sunIconAsset;
    if (path != null) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
            Icon(Icons.wb_sunny, size: size, color: const Color(0xFFE8A33D)),
      );
    }
    return Icon(Icons.wb_sunny, size: size, color: const Color(0xFFE8A33D));
  }
}

/// 一键操作的每盆**轻量反馈**（C29）：小图标短暂浮现 → 停留 → 淡出（总时长约
/// 1s，`TweenAnimationBuilder` 自驱、无外部控制器）。类型与养护动效共用
/// [CareEffectType]（water / fertilize / weed / pest），颜色按类型区分。
class _PotPulse extends StatelessWidget {
  const _PotPulse({required this.type});

  final CareEffectType type;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      CareEffectType.water => (Icons.water_drop, const Color(0xFF4FA3D9)),
      CareEffectType.fertilize => (Icons.eco, const Color(0xFF5FA854)),
      CareEffectType.weed => (Icons.grass, const Color(0xFF8BC34A)),
      CareEffectType.pest => (Icons.pest_control, const Color(0xFFE8A33D)),
    };
    // 显示时长与同播音效**等长**（玄参 2026-10-06「浇水的音效明显比统一显示的
    // 图标时间要长，图标显示时间需要增长」）：浇水 = care_water.mp3 2.90s、
    // 施肥 = care_fertilize.mp3 3.06s（常量单点 prd_params，与效果帧共用）；
    // 除草/除虫（一键护理）2026-10-07 玄参口径修订：播放除虫音效 care_pest.mp3（4.10s），
    // 故轻脉冲图标时长**对齐音效** = kCarePestDurationMs（原写死 1s 与音效不齐）。
    final int pulseMs = switch (type) {
      CareEffectType.water => kCareWaterDurationMs,
      CareEffectType.fertilize => kCareFertilizeDurationMs,
      CareEffectType.weed || CareEffectType.pest => kCarePestDurationMs,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: pulseMs),
      builder: (BuildContext context, double t, Widget? child) {
        // 前 25% 淡入放大 → 中段停留 → 后 35% 淡出缩小。
        final double alpha = t < 0.25
            ? t / 0.25
            : t > 0.65
                ? (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0)
                : 1.0;
        final double scale = 0.7 + 0.3 * (t < 0.25 ? t / 0.25 : 1.0);
        return Opacity(
          opacity: alpha,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

/// 花园「选择要种的植物」弹窗里某个支付方式按钮的展示模型。
class _PlantPaymentButton {
  const _PlantPaymentButton({
    required this.kind,
    required this.amount,
    required this.label,
    required this.enabled,
    this.disabledReason,
    this.seedIsPremium,
  });

  /// 支付方式（免费 / 阳光 / 碎片 / 种子）。
  final PlantCostKind kind;

  /// 数量（阳光片数 / 碎片片数）。
  final int amount;

  /// 按钮文案（如「免费」「400 阳光」「10 植物碎片」「种子」）。
  final String label;

  /// 是否可点击种下（false = 置灰，如已有存活植株 / 余额不足）。
  final bool enabled;

  /// 禁用原因（余额不足 / 成长中），仅 [enabled] 为 false 时有值。
  final String? disabledReason;

  /// 种子档位（仅 [PlantCostKind.seed] 有意义）：精英 → `seed_premium.png`、
  /// 普通 → `seed_common.png`；null → 通用 `seed.png`。
  final bool? seedIsPremium;
}

/// 稀有度 UI 文案（玄参 2026-09-27 物种表改版：**只显示两档**）。
///
/// `common → 普通`；其余（`rare` / `legendary`）一律 → `精英`（legendary 暂无物种，
/// 枚举保留不动，此处兜底归并到精英）。作为库级顶层函数，供 `_PlantTile` 等小组件复用。
String _rarityLabel(AppLocalizations l10n, Rarity r) =>
    r == Rarity.common ? l10n.garden_rarity_common : l10n.garden_rarity_premium;

/// 素材图标 + 兜底内置 Icon（玄参 2026-10-05「阳光和植物碎片使用素材替换，不要写文字」）。
class _AssetGlyph extends StatelessWidget {
  const _AssetGlyph({
    required this.asset,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.size = 20,
  });

  /// 素材路径（null = 缺失，走内置 Icon 兜底）。
  final String? asset;

  final IconData fallbackIcon;
  final Color fallbackColor;

  /// 视觉边长（**手机基准**；C65 平板由 [uiScaleOf] 等比放大）。
  final double size;

  @override
  Widget build(BuildContext context) {
    // C65：素材图不会跟 textScaler 走，必须显式乘倍率，否则「字大了图标还小」。
    final double s = size * uiScaleOf(context);
    if (asset == null) {
      return Icon(fallbackIcon, size: s, color: fallbackColor);
    }
    return Image.asset(
      asset!,
      width: s,
      height: s,
      fit: BoxFit.contain,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
          Icon(fallbackIcon, size: s, color: fallbackColor),
    );
  }
}

/// 选种卡基准高度（玄参 2026-10-05「植物卡片的高度最好是统一一个固定的高度」）。
///
/// ⚠️ C65：这是**手机基准值**。卡内文字会被 textScaler 放大 1.3× → 高度必须同步
/// 放大（`kPlantCardHeight * uiScaleOf(context)`），否则固定高会撑破。
/// ⚠️ F147：正面已改为 **minHeight 兜底**（见 `_frontFace` 注释）—— 大多数卡
/// 仍按本值等高，英文长名折行的卡向下自适应长高，不再溢出；背面（故事正文走
/// Expanded / ellipsis，内容弹性）保持本值固定高。
const double kPlantCardHeight = 116;

/// 单个物种的选种卡片（2026-10-05 三修 + F147 修订，玄参口径）：
///  · **基准高度**（[kPlantCardHeight]）：正面 minHeight 兜底、内容放不下向下
///    自适应（F147）；背面固定高；
///  · 左侧**放大版成株/开花美术图**（[SpeciesPreviewArt]，80）；
///  · 价格按钮**一行排布**（阳光 + 碎片并列，FittedBox 兜底缩放，不再折两行）；
///  · **点击卡片空白处翻面**：背面显示该物种的简短介绍 + 小故事
///    （[speciesLoreL10n]，F147 起 ARB 化）。
class _PlantTile extends StatefulWidget {
  const _PlantTile({
    required this.species,
    required this.buttons,
    required this.onPay,
    required this.rewardAssets,
  });

  final PlantSpecies species;
  final List<_PlantPaymentButton> buttons;
  final void Function(PlantCostKind kind) onPay;

  /// 可用美术资源集合（阳光/碎片/种子按钮图标用；空集 → 内置 Icon 兜底）。
  final Set<String> rewardAssets;

  @override
  State<_PlantTile> createState() => _PlantTileState();
}

class _PlantTileState extends State<_PlantTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// 当前是否翻到背面。
  bool _showBack = false;

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  /// 点击卡片空白处 → 翻到背面 / 翻回正面（支付按钮各自吃掉点击，不触发翻面）。
  void _toggleFlip() {
    setState(() {
      _showBack = !_showBack;
      if (_showBack) {
        _flipCtrl.forward();
      } else {
        _flipCtrl.reverse();
      }
    });
  }

  /// 档位强调色（普通绿 / 精英紫，卡片描边同色区分）。
  /// C63：色值已收口到 [rarityAccent]（单点），本处只做取用。
  Color get _accent => rarityAccent(widget.species.rarity);

  BoxDecoration _faceDecoration({required Color fill}) => BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.45), width: 1.5),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipCtrl,
      builder: (BuildContext context, Widget? _) {
        final double angle = math.pi * _flipCtrl.value;
        final bool backSide = angle > math.pi / 2;
        Widget face = backSide ? _backFace() : _frontFace();
        if (backSide) {
          // 背面镜像：把 π 角转回去，文字才可读。
          face = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(math.pi),
            child: face,
          );
        }
        return GestureDetector(
          onTap: _toggleFlip,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: face,
          ),
        );
      },
    );
  }

  /// 正面：放大植物图 + 名称/稀有度 + **一行**价格按钮。
  Widget _frontFace() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PlantSpecies species = widget.species;
    final bool premium = species.isPremium;
    final String seedAsset = premium
        ? 'assets/rewards/seed_premium.png'
        : 'assets/rewards/seed_common.png';
    final String? sunlightAsset =
        widget.rewardAssets.contains('assets/rewards/sunlight.png')
            ? 'assets/rewards/sunlight.png'
            : null;
    final String? fragmentAsset =
        widget.rewardAssets.contains('assets/rewards/fragment.png')
            ? 'assets/rewards/fragment.png'
            : null;
    // 禁用原因（如「植物碎片不足（当前 4 片）」）合并为一行小字，不撑高卡片。
    final String? disableReason = widget.buttons
        .where((_PlantPaymentButton b) => !b.enabled && b.disabledReason != null)
        .map((_PlantPaymentButton b) => b.disabledReason!)
        .join(' · ');
    // F147（玄参截图：手机档 Premium 卡 BOTTOM OVERFLOWED BY 8.0 PIXELS）：
    // 正面从「固定 height」改为「minHeight 兜底 + 内容自适应」。根因是 F144 的
    // 稀有度徽章挤占名称宽度后，手机档英文长名（Coral Ridge Orchid 等）折行，
    // 列高（名称行 + 价格按钮行）超过 116 固定卡的内容区 93pt。禁缩字号 /
    // 禁 FittedBox 缩内容 / 禁 maxLines 砍信息，故让容器兜底自适应：内容放得下
    // 时仍是 [kPlantCardHeight] × uiScaleOf 等高（绝大多数卡不受影响），放不下
    // 时向下长出恰好所需高度（弹窗本体是 SingleChildScrollView，可滚动）。
    return Container(
      constraints:
          BoxConstraints(minHeight: kPlantCardHeight * uiScaleOf(context)),
      padding: const EdgeInsets.all(10),
      decoration: _faceDecoration(fill: Colors.white),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 物种成株/开花美术图（玄参「左边植物放大一些」→ 60 → 80；C65 随卡片同比放大）。
          SpeciesPreviewArt(species: species, size: 80 * uiScaleOf(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                          speciesNameOr(species.id, species.name, l10n),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                    // 稀有度徽章：普通绿 / 精英紫（一眼区分档位）。
                    // F147（玄参 2026-10-22）：废除名称行右侧的持券种子徽章 ——
                    // 2026-10-07 起 Seed 已是第三支付方式（底部绿胶囊按钮），
                    // 徽章信息重复，玄参反馈「怎么多出了一个种子图标」。
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: rarityTint(species.rarity),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_rarityLabel(l10n, species.rarity),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _accent)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 价格一行（玄参「阳光和植物碎片，在1行就行」）：Row + FittedBox
                // 兜底缩放，绝不折两行。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < widget.buttons.length; i++) ...<Widget>[
                        _PayButtonWidget(
                          button: widget.buttons[i],
                          sunlightAsset: sunlightAsset,
                          fragmentAsset: fragmentAsset,
                          seedAsset: seedAsset,
                          onTap: widget.buttons[i].enabled
                              ? () => widget.onPay(widget.buttons[i].kind)
                              : null,
                        ),
                        if (i < widget.buttons.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                if (disableReason != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    disableReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 背面：物种简短介绍 + 小故事（玄参 2026-10-05「背面写着这个植物的简短介绍
  /// 和一个小故事」）。文案单点 [speciesLoreL10n]（F147 起 ARB 化，zh 硬编码已迁出），
  /// UI 不写死。
  Widget _backFace() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PlantSpecies species = widget.species;
    final SpeciesLore lore = speciesLoreL10n(species.id, l10n);
    return Container(
      height: kPlantCardHeight * uiScaleOf(context),
      padding: const EdgeInsets.all(12),
      decoration: _faceDecoration(fill: const Color(0xFFFFF9EC)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_stories, size: 14, color: _accent),
              const SizedBox(width: 4),
              Text(speciesNameOr(species.id, species.name, l10n),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(l10n.garden_flip_back,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFFB9AE97))),
            ],
          ),
          const SizedBox(height: 4),
          Text(lore.intro,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _accent)),
          const SizedBox(height: 3),
          Expanded(
            child: Text(
              lore.story,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, height: 1.3, color: Color(0xFF6B6252)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大圆角马卡龙风格支付按钮（儿童友好；素材图标 + 数字，不再写「N 阳光」文字；
/// 种子券按钮前置分档种子图；2026-10-05 起价格在卡片内**一行**排布，按钮更紧凑）。
class _PayButtonWidget extends StatelessWidget {
  const _PayButtonWidget({
    required this.button,
    required this.sunlightAsset,
    required this.fragmentAsset,
    required this.seedAsset,
    this.onTap,
  });

  final _PlantPaymentButton button;

  /// 阳光 / 碎片 / 种子素材路径（null = 缺失，内置 Icon 兜底）。
  final String? sunlightAsset;
  final String? fragmentAsset;
  final String? seedAsset;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final _PlantPaymentButton b = button;
    final Color bg = b.enabled ? const Color(0xFF8FCF74) : Colors.grey.shade300;
    final Widget child = switch (b.kind) {
      // 免费类保留文字（测试口径）：向日葵首株「免费」。
      PlantCostKind.free => Text(b.label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: b.enabled ? Colors.white : Colors.grey.shade600)),
      // 种子（第三支付方式，2026-10-07）：前置分档种子图 + 文字「种子」（玄参「精简」）。
      PlantCostKind.seed => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              switch (b.seedIsPremium) {
                true => seedAsset ?? 'assets/rewards/seed_premium.png',
                false => seedAsset ?? 'assets/rewards/seed_common.png',
                null => seedAsset ?? 'assets/rewards/seed.png',
              },
              width: 16 * uiScaleOf(context),
              height: 16 * uiScaleOf(context),
              fit: BoxFit.contain,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  const Text('🌰', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            Text(b.label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: b.enabled ? Colors.white : Colors.grey.shade600)),
          ],
        ),
      PlantCostKind.sunlight => _iconAmount(sunlightAsset, Icons.wb_sunny,
          const Color(0xFFE8A33D), b.amount, b.enabled),
      PlantCostKind.fragments => _iconAmount(fragmentAsset, Icons.extension,
          const Color(0xFF7E57C2), b.amount, b.enabled),
    };
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: b.enabled ? Colors.white : Colors.grey.shade600,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );
  }

  /// 「素材图标 + 数字」内芯（显式尺寸，防 loose 约束原图尺寸布局）。
  Widget _iconAmount(String? asset, IconData fallback, Color fallbackColor,
      int amount, bool enabled) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _AssetGlyph(
          asset: asset,
          fallbackIcon: fallback,
          fallbackColor: enabled ? Colors.white : fallbackColor,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          '$amount',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: enabled ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
/// 一键操作悬浮按钮（C29；玄参 2026-10-05 交互修订）：
///
/// · **收拢态**：胶囊「✋ 一键操作」；**展开态**：其上方一张三行操作卡（浇水/施肥/护理）。
/// · **宽度恒定**：胶囊与展开卡共用**同一个**算出来的宽度（[_OneClickFabState._sharedWidth]
///   的返回值，一次性算给两者），展开/收拢**不左右变形**（玄参「宽度要一致，不要来回变化」）。
/// · **点击切换**：点胶囊展开 → 再点胶囊收拢（toggle，不再是系统下拉菜单）；
///   点某操作行 → 收拢并回调 [onSelected]。
///
/// ## 🔴 F157-BUG-1（玄参 2026-10-27 小米 14 Pro 真机实测）
/// 旧实现把宽度钉死 `108 * uiScaleOf`：中文「一键浇水」够宽，英文 `Fertilize all`
/// 差 4px → 行内 `Row` 报 `RenderFlex overflowed by 4 pixels`（debug 黄黑条、
/// release 直接裁字），iPad 13″ 因屏宽足够而未复现。
///
/// 现口径（四条，缺一不可）：
///  ① **实测**：用 `TextPainter` 按**当前 `TextStyle` + `TextDirection` +
///     `MediaQuery.textScaler`** 量三行文案，取最宽那条（图标 + 间距 + 行内边距 +
///     文本），**不用 `IntrinsicWidth` 猜**（展开/收拢时会抖）；
///  ② **共用**：算出的宽度同时喂胶囊与展开卡（严格等宽）；
///  ③ **上限**：不得超过「屏宽 − 2 × [kOneClickSafeMargin]」，防极端长文案 / 极小屏
///     把卡片顶出屏幕；
///  ④ **下限**：[kOneClickWidthFloor]（= 既有 108）× `uiScaleOf`，中文侧逐像素零回归。
///     真顶到上限时标签走 `Flexible` + `TextOverflow.ellipsis`（`maxLines: 1`），
///     **不允许再出现溢出条**。
class _OneClickFab extends StatefulWidget {
  const _OneClickFab({required this.onSelected});

  /// 选中某项一键操作（选中即收拢）。
  final ValueChanged<PlantOneClickKind> onSelected;

  @override
  State<_OneClickFab> createState() => _OneClickFabState();
}

class _OneClickFabState extends State<_OneClickFab> {
  /// 三行操作项的标签样式（**必须**与 [_buildActionRow] 的 `Text` 完全同源：
  /// 测量用它与渲染用它是同一个常量，否则量出来的宽度与真实排版对不上）。
  static const TextStyle _kRowLabelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFF6B6252),
  );

  /// 收拢态胶囊的标题样式（同上：测量与渲染共用）。
  static const TextStyle _kCapsuleLabelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Color(0xFF6B6252),
  );

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 🔴 一次算出、两处共用（C29「宽度要一致，不要来回变化」）。
    final double width = _sharedWidth(l10n);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (_expanded) ...<Widget>[
          _buildActionCard(l10n, width),
          const SizedBox(height: 6),
        ],
        _buildCapsule(l10n, width),
      ],
    );
  }

  /// 胶囊与展开卡共用的宽度（F157-BUG-1 的自适应算法）。
  ///
  /// 每次 `build` 用**当前语言 / 当前字号**重算 —— 切语言（`L10nScope` 同帧重建）
  /// 后立刻跟上新文案长度，不会残留旧语言的宽度。
  ///
  /// 算法：`clamp(实测最宽, 下限 = 108 × uiScale, 上限 = 屏宽 − 2 × 安全边距)`。
  double _sharedWidth(AppLocalizations l10n) {
    final double uiScale = uiScaleOf(context);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);
    // 图标 + 图标间距在**行**与**胶囊**里同值（16 / 6 / 4 见下方常量），文字宽度
    // 才是随语言变化的量。
    final double iconWidth = kOneClickIconSize * uiScale;

    // ① 三行操作项（图标 + 间距 + 文本 + 行内左右内边距）取最宽。
    double widest = 0;
    for (final String label in <String>[
      l10n.garden_action_water,
      l10n.garden_action_fertilize,
      l10n.garden_action_care,
    ]) {
      final double rowWidth = iconWidth +
          kOneClickIconGap +
          _measureTextWidth(label, _kRowLabelStyle, direction, textScaler) +
          kOneClickRowHPad * 2;
      widest = math.max(widest, rowWidth);
    }
    // ② 胶囊自身内容（图标 + 间距 + 标题）也要装得下 —— 否则收拢态反过来被裁
    //    （英文 `One-tap care` 比中文「一键操作」长）。胶囊无水平内边距，
    //    居中留白由下面的下限保证。
    final double capsuleWidth = iconWidth +
        kOneClickCapsuleIconGap +
        _measureTextWidth(
            l10n.garden_oneclick_title, _kCapsuleLabelStyle, direction, textScaler);
    widest = math.max(widest, capsuleWidth);
    // 向上取整到整像素：`TextPainter` 给的是小数宽，父级按物理像素取整时可能
    // 少给 0.3px → 最宽那条反而被顶成省略号（“量够了却还是截断”的经典坑）。
    widest = widest.ceilToDouble();

    // ③ 下限 = 既有固定宽（中文侧逐像素零回归）；④ 上限 = 屏宽 − 两侧安全边距。
    final double floor = kOneClickWidthFloor * uiScale;
    final double ceiling =
        MediaQuery.sizeOf(context).width - kOneClickSafeMargin * 2;
    // `math.max(floor, ceiling)`：极小屏（< 2×边距 + 108）时 ceiling 会低于 floor，
    // 此时宁可让宽度停在 floor（屏再窄也不会出现负宽 / 塌成 0）。
    final double upperBound = math.max(floor, ceiling);
    return math.max(floor, math.min(widest, upperBound));
  }

  /// 用 `TextPainter` 量一段文本在「当前主题 `DefaultTextStyle` 合并 [style]」下的宽度。
  ///
  /// ⚠️ 必须经 `DefaultTextStyle.of(context).style.merge(style)`：`Text` 内部就是这样
  /// 合并的（字体族 / 字距 / 行高可能来自主题），直接用裸 [style] 量会得到偏窄的值。
  /// [maxLines] = 1 + 不换行 —— 与渲染侧的 `maxLines: 1, softWrap: false` 同口径。
  double _measureTextWidth(
    String text,
    TextStyle style,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final TextStyle effective =
        DefaultTextStyle.of(context).style.merge(style);
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    );
    painter.layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  /// 展开卡：三行操作项，与胶囊同宽（[width]；C65 平板随字号同比放大）。
  Widget _buildActionCard(AppLocalizations l10n, double width) {
    return SizedBox(
      key: kOneClickCardKey,
      width: width,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <_OneClickItem>[
            _OneClickItem(
              kind: PlantOneClickKind.water,
              icon: Icons.water_drop,
              color: const Color(0xFF4FA3D9),
              label: l10n.garden_action_water,
            ),
            _OneClickItem(
              kind: PlantOneClickKind.fertilize,
              icon: Icons.eco,
              color: const Color(0xFF5FA854),
              label: l10n.garden_action_fertilize,
            ),
            _OneClickItem(
              kind: PlantOneClickKind.care,
              icon: Icons.pest_control,
              color: const Color(0xFFE8A33D),
              label: l10n.garden_action_care,
            ),
          ].map(_buildActionRow).toList(),
        ),
      ),
    );
  }

  /// 单行操作项（文案走 [Flexible] + 省略号：真顶到宽度上限时**只截字、不溢出**）。
  Widget _buildActionRow(_OneClickItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => _expanded = false);
        widget.onSelected(item.kind);
      },
      child: Container(
        height: 36 * uiScaleOf(context),
        padding: const EdgeInsets.symmetric(horizontal: kOneClickRowHPad),
        child: Row(
          children: <Widget>[
            Icon(item.icon,
                size: kOneClickIconSize * uiScaleOf(context), color: item.color),
            const SizedBox(width: kOneClickIconGap),
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: _kRowLabelStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 收拢态胶囊（与展开卡同宽 [width]；C65 随字号同比放大）。
  Widget _buildCapsule(AppLocalizations l10n, double width) {
    return SizedBox(
      key: kOneClickCapsuleKey,
      width: width,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.touch_app,
                  size: kOneClickIconSize * uiScaleOf(context),
                  color: const Color(0xFF7CB342),
                ),
                const SizedBox(width: kOneClickCapsuleIconGap),
                // 同上：极端长标题时截字而不是溢出。
                Flexible(
                  child: Text(
                    l10n.garden_oneclick_title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: _kCapsuleLabelStyle,
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

/// 一键操作项的静态展示模型（图标 + 文案 + 主色 + 对应枚举）。
class _OneClickItem {
  const _OneClickItem({
    required this.kind,
    required this.icon,
    required this.color,
    required this.label,
  });

  final PlantOneClickKind kind;
  final IconData icon;
  final Color color;
  final String label;
}

/// 收集奖励的「向上飘动 + 淡出」幽灵（玄参 2026-10-05「用户点击之后，向上飘动，
/// 慢慢消失」）：复用 [BloomRewardIcon] 纯展示渲染（`onTap: null`），有限时长
/// （约 0.9s）自下而上飘 ~56px 并淡出，走完经 [onComplete] 自清。
///
/// ⚠️ 资源缺失（测试环境 AssetManifest 读不到）→ 图标无图可画 → 整体不渲染，
/// 不产生任何 findable 节点（不干扰既有收集断言）。
class CollectGhost extends StatelessWidget {
  const CollectGhost({
    super.key,
    required this.specs,
    required this.availableAssets,
    required this.onComplete,
  });

  /// 点击时捕获的图标规格（该条 pending 的全部图标一起飘走）。
  final List<RewardIconSpec> specs;

  /// 可用美术资源集合（空集 → 无图可画 → 不渲染）。
  final Set<String> availableAssets;

  /// 动画走完回调（调用方清状态）。
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    // 幽灵渲染规则：
    //  · 素材清单**完全不可用**（测试环境，availableAssets 空）→ 无图可画 →
    //    整体不渲染，不产生任何 findable 节点（不干扰既有收集断言）；
    //  · 清单可用但**个别素材缺失**（如 `sunlight.png` 未交付，F73）→ 该项用
    //    内置 Icons 兜底照样飘（否则纯阳光奖励的幽灵整个为空 =「点击直接消失」，
    //    玄参 2026-10-05 复测复现；真素材到位后自动替换，无需改码）。
    final bool manifestUsable = availableAssets.isNotEmpty;
    final List<BloomRewardIcon> icons = <BloomRewardIcon>[];
    for (final RewardIconSpec spec in specs) {
      final String? asset = resolveRewardAsset(spec, availableAssets);
      if (asset == null && !manifestUsable) continue; // 测试环境：全部跳过
      icons.add(BloomRewardIcon(
        spec: spec,
        assetPath: asset, // null → BloomRewardIcon 内置 Icon 兜底
        onTap: null, // 纯展示：幽灵不响应点击
      ));
    }
    if (icons.isEmpty) {
      return const SizedBox.shrink();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      onEnd: onComplete,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -56 * t),
            child: child,
          ),
        );
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: icons),
    );
  }
}


/// 花园左上角「种子计数」小 chip（2026-10-05 玄参需求：碎片入口右边并列显示
/// 普通 / 精英种子个数）。分档种子素材图 + 「×N」；素材缺失回退 🌰 emoji。
/// 2026-10-06：加 [onTap]（与碎片 chip 一样点开「碎片与种子」说明卡）。
class _SeedCountChip extends StatelessWidget {
  const _SeedCountChip({required this.count, required this.asset, this.onTap});

  /// 持有的该档种子数。
  final int count;

  /// 分档种子素材路径（seed_common / seed_premium）。
  final String asset;

  /// 点击回调（null = 纯展示不响应）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 种子计数：素材图 + 「×N」（C65：素材图显式乘平板倍率，
              // 文字由 textScaler 自动放大）。
              Image.asset(
                asset,
                width: 16 * uiScaleOf(context),
                height: 16 * uiScaleOf(context),
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    const Text('🌰', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 3),
              Text(
                '×$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B6252),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 花园页「精品碎片」入口（玄参 2026-09-27 物种表改版）。
///
/// 旧「N/阈值 + 满阈值高亮」已废弃（阈值体系删除）；点击打开只读信息页 [_FragmentSheet]。
/// 2026-10-05 玄参「3 个 chip 要保持一样」：去掉「植物碎片」文字，改与 [_SeedCountChip]
/// 同款「图标 ×N」白胶囊（仅多一层点击进说明页）。
class _FragmentEntry extends StatelessWidget {
  const _FragmentEntry({
    required this.balance,
    required this.onTap,
  });

  /// 当前碎片余额。
  final int balance;

  /// 点击回调（打开碎片信息页）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 碎片美术图（2026-10-03 玄参提供）；缺失回退拼图 Icon。
              // C65：素材图与兜底 Icon 都显式乘平板倍率。
              Image.asset(
                'assets/rewards/fragment.png',
                width: 16 * uiScaleOf(context),
                height: 16 * uiScaleOf(context),
                fit: BoxFit.contain,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    Icon(
                  Icons.extension,
                  size: 16 * uiScaleOf(context),
                  color: const Color(0xFF9C917C),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '×$balance',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B6252),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「碎片与种子」说明卡（玄参 2026-10-06 口径修订：**屏幕中间 Dialog** + 内容**只讲
/// 植物碎片 / 普通种子 / 精英种子**三类资源的用途与获得方法，**不再逐物种列碎片
/// 价目**——价目在选种弹窗里本来就有，说明卡不重复）。入口 = 碎片 chip 与两个
/// 种子 chip。图标缺失回退内置 Icon。
///
/// i18n B1：文案经 [AppLocalizations] 解析；弹窗上下文在页面 scope 之外，自包
/// [L10nScope]（B1 约定：自包含弹窗内建文案作用域）。
class _RewardCurrencyDialog extends StatelessWidget {
  const _RewardCurrencyDialog();

  /// 单条说明的美术资源（图标路径 + 兜底 Icon + 主色）；文案在 build 内经 l10n 解析。
  static const List<({String? asset, IconData fallbackIcon, Color color})>
      _items = <({String? asset, IconData fallbackIcon, Color color})>[
    (
      asset: 'assets/rewards/fragment.png',
      fallbackIcon: Icons.extension,
      color: Color(0xFF7E57C2),
    ),
    (
      asset: 'assets/rewards/seed_common.png',
      fallbackIcon: Icons.eco,
      color: Color(0xFF43A047),
    ),
    (
      asset: 'assets/rewards/seed_premium.png',
      fallbackIcon: Icons.eco,
      color: Color(0xFF7E57C2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          final List<({String title, String use, String how})> texts =
              <({String title, String use, String how})>[
            (
              title: l10n.garden_help_fragment_title,
              use: l10n.garden_help_fragment_use,
              how: l10n.garden_help_fragment_how,
            ),
            (
              title: l10n.garden_help_common_seed_title,
              use: l10n.garden_help_common_seed_use,
              how: l10n.garden_help_common_seed_how,
            ),
            (
              title: l10n.garden_help_premium_seed_title,
              use: l10n.garden_help_premium_seed_use,
              how: l10n.garden_help_premium_seed_how,
            ),
          ];
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF4E4), // 暖奶油底（与选种/养护卡同层语言）
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFE3B0), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Text(l10n.garden_help_sheet_title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  for (int i = 0; i < _items.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 30 * uiScaleOf(context),
                          height: 30 * uiScaleOf(context),
                          child: Center(
                            child: _items[i].asset != null
                                ? Image.asset(
                                    _items[i].asset!,
                                    width: 24 * uiScaleOf(context),
                                    height: 24 * uiScaleOf(context),
                                    fit: BoxFit.contain,
                                    errorBuilder: (BuildContext _,
                                            Object __, StackTrace? ___) =>
                                        Icon(_items[i].fallbackIcon,
                                            size: 22 * uiScaleOf(context),
                                            color: _items[i].color),
                                  )
                                : Icon(_items[i].fallbackIcon,
                                    size: 22 * uiScaleOf(context),
                                    color: _items[i].color),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(texts[i].title,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _items[i].color)),
                              const SizedBox(height: 2),
                              Text(
                                  l10n.garden_help_use_prefix(texts[i].use),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: Color(0xFF4A4436))),
                              const SizedBox(height: 2),
                              Text(
                                  l10n.garden_help_how_prefix(texts[i].how),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: Color(0xFF6B6252))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.shared_got_it),
                    ),
                  ),
                ],
              ),
            ),
          );
        }, // builder 闭包
      ), // Builder
    ); // L10nScope
  }
}
