/// 植物「头顶奖励图标」（玄参 2026-09-27「奖励物图标化 + 掉落即定奖」）。
///
/// ## 背景
/// 玄参驳回了旧「点击气泡 → 一句『到手啦』」的模糊提示：**奖励是什么，就直接在向日葵
/// 头顶显示**——碎片显示碎片图标、阳光显示阳光图标，用户直接点击就回收；后续提供美术素材
/// 替换这些图标。故本组件按 `PendingBloomReward` 的**已定奖内容**（阳光 / 植物碎片 / 种子
/// 三列，见 `reward_sunlight / reward_fragments / reward_species_id`）派生**一排图标**，
/// 头顶展示、点击即收下该条 pending 的全部奖励。
///
/// ## 数据驱动（不 roll、不猜）
/// 图标数量与角标完全由库里三列派生：阳光 >0 → 阳光图标 + 角标 `+N`；碎片 >0 → 植物碎片
/// 图标 + 角标 `×N`；种子物种非 null → 种子图标；三列全零（**历史行零值哨兵** = 未预先定奖）
/// → 通用礼包图标 `Icons.card_giftcard`。数值从实际数据拼，**绝不写死**。
///
/// ## 美术资源契约（`assets/rewards/`）
/// · `sunlight.png` — 阳光；`fragment.png` — 植物碎片；`seed.png` — 种子（**通用，唯一**）。
///   种子现已**全物种通用**（见宪法 C20），不再有 `seed_{speciesId}.png` 物种专属种子图标。
/// · 判定资源是否存在用 `AssetManifest.loadFromAssetBundle` + `listAssets()`（由
///   `rewardAssetsProvider` 提供，**不用 `AssetManifest.json`**，Flutter 3.7+ 不再生成）。
/// · 资源缺失一律回退内置 `Icons`（阳光 [Icons.wb_sunny] / 碎片 [Icons.auto_awesome] /
///   种子 [Icons.eco] / 历史行礼包 [Icons.card_giftcard]），**接口不变、可平滑替换**。
///
/// ## 布局纪律
/// · 一排图标**不占布局高度**（由调用方用 `Positioned` 叠加在花盆上方）；本组件自身只负责
///   「排成一排 + 点击命中区 ≥40×40」。
/// · 入场做一次**有限时长**（≤400ms）缩放动画（`TweenAnimationBuilder` 只跑一遍）——
///   **禁止无限动画**，否则 widget 测试 `pumpAndSettle` 永不返回（同 `garden_sign_hotspot`
///   的既有陷阱）。
library bloom_reward_icons;

import 'package:flutter/material.dart';

import 'package:sunflower_time/domain/entities/pending_bloom_reward.dart';

/// 奖励图标类型（决定内置 `Icons` 回退与资源文件名）。
enum RewardIconKind {
  /// 阳光。
  sunlight,

  /// 植物碎片（对用户叫「植物碎片」，内部标识符沿用 premium fragment）。
  fragment,

  /// 掉落种子（一张免费种植券）。
  seed,

  /// 通用礼包（历史行「未预先定奖」哨兵 / 兜底）。
  gift,
}

/// 单个奖励图标的展示模型（类型 + 角标 + 种子物种 id + 物种档位）。
@immutable
class RewardIconSpec {
  const RewardIconSpec({
    required this.kind,
    this.badge,
    this.seedSpeciesId,
    this.seedIsPremium,
  });

  /// 图标类型。
  final RewardIconKind kind;

  /// 角标文案（如 `+10` / `×1`）；null = 不显示角标。
  final String? badge;

  /// 种子物种 id（仅 [RewardIconKind.seed] 有意义，用于派生档位种子图）。
  final String? seedSpeciesId;

  /// 物种档位（仅 [RewardIconKind.seed] 有意义）：精英 → `seed_premium.png`、
  /// 普通 → `seed_common.png`；null（拿不到档位）→ 通用 `seed.png`。
  final bool? seedIsPremium;

  @override
  bool operator ==(Object other) =>
      other is RewardIconSpec &&
      other.kind == kind &&
      other.badge == badge &&
      other.seedSpeciesId == seedSpeciesId &&
      other.seedIsPremium == seedIsPremium;

  @override
  int get hashCode => Object.hash(kind, badge, seedSpeciesId, seedIsPremium);
}

/// 从一条待收集奖励的三列（阳光 / 植物碎片 / 种子）**派生图标列表**。
///
/// · 三列全零（`0/0/null` = 历史行「未预先定奖」哨兵）→ 单个通用礼包图标；
/// · 否则按「阳光 → 碎片 → 种子」顺序派生（一条 instant 奖励可能同时有阳光 + 碎片 / 阳光 + 种子）；
/// · [isPremiumOf] 提供物种档位查询（speciesId → 是否精英）；不给则种子图标走通用图。
List<RewardIconSpec> rewardIconSpecsFor(
  PendingBloomReward reward, {
  bool Function(String speciesId)? isPremiumOf,
}) {
  if (!reward.hasPreAssignedReward) {
    return const <RewardIconSpec>[
      RewardIconSpec(kind: RewardIconKind.gift),
    ];
  }
  final List<RewardIconSpec> specs = <RewardIconSpec>[];
  if (reward.rewardSunlight > 0) {
    specs.add(RewardIconSpec(
      kind: RewardIconKind.sunlight,
      badge: '+${reward.rewardSunlight}',
    ));
  }
  if (reward.rewardFragments > 0) {
    specs.add(RewardIconSpec(
      kind: RewardIconKind.fragment,
      badge: '×${reward.rewardFragments}',
    ));
  }
  final String? seedId = reward.rewardSpeciesId;
  if (seedId != null) {
    specs.add(RewardIconSpec(
      kind: RewardIconKind.seed,
      seedSpeciesId: seedId,
      seedIsPremium: isPremiumOf?.call(seedId),
    ));
  }
  if (specs.isEmpty) {
    // 理论上不会走到（hasPreAssignedReward 已排除哨兵）；防御性兜底。
    specs.add(const RewardIconSpec(kind: RewardIconKind.gift));
  }
  return specs;
}

/// 内置 `Icons` 回退（资源缺失时）。
IconData rewardFallbackIcon(RewardIconKind kind) {
  switch (kind) {
    case RewardIconKind.sunlight:
      return Icons.wb_sunny;
    case RewardIconKind.fragment:
      return Icons.auto_awesome;
    case RewardIconKind.seed:
      return Icons.eco;
    case RewardIconKind.gift:
      return Icons.card_giftcard;
  }
}

/// 图标主色（与回退 Icons 配色一致；有美术资源时作角标 / 背景兜底色）。
Color rewardIconColor(RewardIconKind kind) {
  switch (kind) {
    case RewardIconKind.sunlight:
      return const Color(0xFFE8A33D);
    case RewardIconKind.fragment:
      return const Color(0xFF7E57C2);
    case RewardIconKind.seed:
      return const Color(0xFF43A047);
    case RewardIconKind.gift:
      return const Color(0xFF8A5A00);
  }
}

/// 解析出「实际可用的图片资源路径」；null = 用内置 `Icons` 回退。
///
/// [availableAssets] 为 `AssetManifest.listAssets()` 的字符串集合（见 `rewardAssetsProvider`）。
/// 种子图标（2026-10-03 玄参提供分档图，C20 口径修订）：按物种档位优先取
/// `seed_premium.png`（精英）/ `seed_common.png`（普通）；档位图缺失回退通用
/// `seed.png`；再缺失回退 `Icons.eco`。
String? resolveRewardAsset(RewardIconSpec spec, Set<String> availableAssets) {
  switch (spec.kind) {
    case RewardIconKind.gift:
      return null; // 礼包恒用内置 Icons.card_giftcard
    case RewardIconKind.sunlight:
      const String name = 'assets/rewards/sunlight.png';
      return availableAssets.contains(name) ? name : null;
    case RewardIconKind.fragment:
      const String name = 'assets/rewards/fragment.png';
      return availableAssets.contains(name) ? name : null;
    case RewardIconKind.seed:
      // 分档种子图：精英 / 普通各自优先；缺失回退通用 seed.png（C20 历史口径保留作兜底）。
      final String? tiered = switch (spec.seedIsPremium) {
        true => 'assets/rewards/seed_premium.png',
        false => 'assets/rewards/seed_common.png',
        null => null,
      };
      if (tiered != null && availableAssets.contains(tiered)) {
        return tiered;
      }
      const String general = 'assets/rewards/seed.png';
      return availableAssets.contains(general) ? general : null;
  }
}

/// 花朵「头顶奖励图标」一排（横向、居中）。
///
/// 每条 [rewards] 派生 1..N 个图标；**点击任一图标 = 收下该条 pending 的全部奖励**
/// （按条收集，见 [onCollect] 回调）。整体宽度超出可用宽度时用 [FittedBox] 缩放（窄屏不溢出）。
class BloomRewardIconsBar extends StatelessWidget {
  const BloomRewardIconsBar({
    super.key,
    required this.rewards,
    required this.availableAssets,
    required this.onCollect,
    this.isPremiumOf,
  });

  /// 当前可收集的待收集奖励（一条 pending = 一「条」，点击收下整条）。
  final List<PendingBloomReward> rewards;

  /// 可用美术资源集合（来自 `rewardAssetsProvider`；空集 → 全回退内置 Icons）。
  final Set<String> availableAssets;

  /// 收集回调：点击某图标 → 收下其**所属 pending 整条**奖励。
  final void Function(PendingBloomReward reward) onCollect;

  /// 物种档位查询（speciesId → 是否精英）；种子图标据此选分档图，不给则走通用图。
  final bool Function(String speciesId)? isPremiumOf;

  @override
  Widget build(BuildContext context) {
    final List<Widget> icons = <Widget>[];
    for (final PendingBloomReward reward in rewards) {
      for (final RewardIconSpec spec
          in rewardIconSpecsFor(reward, isPremiumOf: isPremiumOf)) {
        icons.add(BloomRewardIcon(
          spec: spec,
          assetPath: resolveRewardAsset(spec, availableAssets),
          // 点击任一图标 → 收下「该条 pending」全部奖励（按条收集，非按图标）。
          onTap: () => onCollect(reward),
        ));
      }
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: icons,
      ),
    );
  }
}

/// 单个奖励图标（圆形底 + 图标/图片 + 角标；命中区 ≥40×40，图标视觉 ~34）。
class BloomRewardIcon extends StatelessWidget {
  const BloomRewardIcon({
    super.key,
    required this.spec,
    required this.assetPath,
    required this.onTap,
  });

  /// 展示模型。
  final RewardIconSpec spec;

  /// 可用图片资源路径（null → 用内置 `Icons` 回退）。
  final String? assetPath;

  /// 点击回调（收集该条奖励）。
  final VoidCallback onTap;

  /// 命中区边长（≥40×40，满足触控目标下限）。
  static const double hitSize = 42;

  /// 图标视觉直径（~34）。
  static const double visualSize = 34;

  @override
  Widget build(BuildContext context) {
    final Color color = rewardIconColor(spec.kind);
    // 有限时长入场动画（弹性回弹，只跑一遍；≤400ms）——避免无限动画卡死 pumpAndSettle。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              _buildDisc(color),
              if (spec.badge != null)
                Positioned(bottom: 0, right: 0, child: _badge(color)),
            ],
          ),
        ),
      ),
    );
  }

  /// 圆形底盘 + 图标 / 图片。
  Widget _buildDisc(Color color) {
    return Container(
      width: visualSize,
      height: visualSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: _buildGlyph(color)),
    );
  }

  /// 图标本体：有美术资源用 `Image.asset`（**显式宽高**，避免布局异常），否则回退 `Icons`。
  Widget _buildGlyph(Color color) {
    const double glyph = 20;
    final String? path = assetPath;
    if (path != null) {
      return Image.asset(
        path,
        width: glyph,
        height: glyph,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
            Icon(rewardFallbackIcon(spec.kind), size: glyph, color: color),
      );
    }
    return Icon(rewardFallbackIcon(spec.kind), size: glyph, color: color);
  }

  /// 角标（如 `+10` / `×1`）。
  Widget _badge(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Text(
        spec.badge!,
        style: const TextStyle(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
