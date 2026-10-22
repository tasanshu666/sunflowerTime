/// 孩子端「我的」页头像（**C90-C**，玄参 2026-10-18 拍板；**C91 美化修订**）。
///
/// 口径：
///  · 默认头像 = **阳光 UI**（`assets/rewards/sunlight.png`）；点头像弹选择面板；
///  · 面板选项 = 阳光 + 全部植物物种；**当前孩子已种植过**的物种（plants 表按
///    当前 childId 的 distinct speciesId，由仓储层过滤）可选；未种植的物种
///    **置灰 + 小锁图标但可点** —— 点击提示 [kChildAvatarLockedHint]
///    （「种下这种植物后可以选它当头像」），绝不可静默无反应（C62 纪律）；
///  · 选择结果跟孩子档案存（`child_profiles.avatar`，v29 列），切孩子各用各的；
///  · 植物头像渲染用该物种代表性立绘（成株/盛开帧 → 商店卡图回退链，复用
///    [SpeciesPreviewArt] 的五级回退），缺失时回退内置花卉图标。
///
/// ## C91 修订（玄参平板真机反馈：底部抽屉 → 屏幕居中独立卡片）
///  · 弹层从 `showModalBottomSheet` 底部抽屉改为 **`showDialog` 屏幕居中卡片**；
///  · 视觉对齐 App 视觉语言：米色底 / 阳光金强调（`kChildAvatarGold`）/ 大圆角
///    24 / 柔阴影 / 孩子友好字号（标题 20、选项名 13）与更大触点（68pt 选项格）；
///  · 功能零变化：阳光 + 全物种网格、已种可选、未种置灰加锁可点提示；
///  · 稳定 Key 纪律照旧：卡片 `child_avatar_dialog`、选项
///    `avatar_option_<value>`（测试经 ValueKey 定位）。
///
/// ## C91 二轮修订（玄参 iOS 模拟器反馈：网格不对称）
///  · 折行策略从 `Wrap`（按屏宽自适应，平板 3+3+1、窄屏手机 2 列，行结构漂移）
///    改为**固定每行恰 3 个**的手工切块网格，每行（含不满一行的尾行）**水平居中**
///    （7 条 = 3+3+1，尾行 1 个居中）；平板与手机行结构、条目尺寸、间距完全一致；
///  · 条目格 84 → 72pt（间距 10）：320pt 最窄视口下 3×72+2×10=236 ≤ 可用
///    288（320 − 弹窗水平内边距 2×16），恰容纳一行 3 个；触点 ≥44pt 纪律照旧。
library child_avatar;

import 'package:flutter/material.dart';
import 'package:sunflower_time/core/i18n/l10n_scope.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/plant_species.dart';
import 'package:sunflower_time/presentation/child/widgets/plant_artwork.dart';
import 'package:sunflower_time/core/i18n/species_l10n.dart';

/// 头像圆形底色（奶油底，与 App 奶油/阳光风同源）。
const Color kChildAvatarBg = Color(0xFFFFF6DE);

/// 阳光金强调色（C91 卡片视觉主色：标题 / 选中描边 / 勾标，与商店卡同源）。
const Color kChildAvatarGold = Color(0xFFF6C445);

/// 阳光金的深色文字变体（标题文字用，保证米色底上对比度）。
const Color kChildAvatarGoldDeep = Color(0xFF8D6E00);

/// 头像选择卡片底色（米色，比纯白柔和、与奶油头像底同族）。
const Color kChildAvatarCardBg = Color(0xFFFFF9EC);

/// 圆形头像视图：[avatar] = [kChildAvatarSun] → 阳光图；否则视为物种 id →
/// 该物种代表性立绘（成株/盛开帧优先，[SpeciesPreviewArt] 五级回退）。
class ChildAvatarView extends StatelessWidget {
  const ChildAvatarView({super.key, required this.avatar, this.radius = 36});

  /// 头像取值：[kChildAvatarSun]（阳光）或植物物种 id。
  final String avatar;

  /// 圆半径。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bool isSun = avatar == kChildAvatarSun;
    return CircleAvatar(
      radius: radius,
      backgroundColor: kChildAvatarBg,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: isSun
              ? Image.asset(
                  // 阳光 UI（玄参指定用现有阳光图标素材）；缺图回退内置太阳。
                  'assets/rewards/sunlight.png',
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                      Icon(Icons.wb_sunny,
                          size: radius, color: kChildAvatarGold),
                )
              : SpeciesPreviewArt(
                  species: PlantSpecies(
                    id: avatar,
                    name: avatar,
                    rarity: Rarity.common,
                    baseCostHigh: 0,
                    baseCostLow: 0,
                    growthHoursPerStage: 0,
                  ),
                  size: radius * 2,
                ),
        ),
      ),
    );
  }
}

/// 头像选择卡片（点头像弹出，**C91：屏幕居中 Dialog 卡片**）：阳光 + 物种网格；
/// 已种植可选、未种植置灰加锁可点提示。
///
/// 卡片**只做收集**：点可选项 `pop` 回物种 id（或 [kChildAvatarSun]），
/// 落库与刷新由调用方（`child_profile_page`）完成；锁定项在卡片内提示后**留在卡片**。
Future<String?> showChildAvatarPickerDialog(
  BuildContext context, {
  required String currentAvatar,

  /// 当前孩子已种植过的物种 id 集合（仓储层按 childId 过滤后派生）。
  required Set<String> plantedSpeciesIds,

  /// 全部候选物种（静态物种表，决定展示顺序与名称）。
  required List<PlantSpecies> species,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    // i18n（B1）：弹窗 builder 上下文在页级 scope 之外 → 内容自带 L10nScope，
    // 页内文案经内部上下文取用（不依赖宿主挂 delegates）。
    builder: (BuildContext dialogCtx) {
      return L10nScope(
        child: Builder(builder: (BuildContext ctx) {
      final AppLocalizations l10n = AppLocalizations.of(ctx);
      // 🔴 C91 二轮：固定每行 3 个的对称网格 —— 全部候选（阳光 + 物种）先
      // 收集成一维列表，下方按 3 个一行切块渲染（每行居中，尾行不满也居中）。
      final List<Widget> options = <Widget>[
        _AvatarOption(
          key: const ValueKey<String>('avatar_option_$kChildAvatarSun'),
          value: kChildAvatarSun,
          label: l10n.shared_sunlight,
          selected: currentAvatar == kChildAvatarSun,
          locked: false,
          onTap: () => Navigator.of(dialogCtx).pop(kChildAvatarSun),
          child: Image.asset(
            'assets/rewards/sunlight.png',
            fit: BoxFit.contain,
            errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                const Icon(Icons.wb_sunny, size: 34, color: kChildAvatarGold),
          ),
        ),
        for (final PlantSpecies s in species)
          _AvatarOption(
            key: ValueKey<String>('avatar_option_${s.id}'),
            value: s.id,
            label: speciesNameOr(s.id, s.name, l10n),
            selected: currentAvatar == s.id,
            // 🔴 置灰 + 锁但**可点**：点了提示，不静默（C62 纪律）。
            locked: !plantedSpeciesIds.contains(s.id),
            onTap: () => Navigator.of(dialogCtx).pop(s.id),
            onLockedTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10nOf(context).prd_avatar_locked_hint),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: SpeciesPreviewArt(species: s, size: 46),
          ),
      ];
      return Dialog(
        backgroundColor: Colors.transparent,
        // C91 二轮：水平内边距 40 → 16 —— 320pt 最窄视口下给 3 列网格留足
        // 宽度（3×72 + 2×10 = 236 + 卡内边距 40 = 276 ≤ 288）。
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          // 🔴 稳定 Key：测试定位弹层子树（锁定图标数 / 打勾 / 收起断言）。
          key: const ValueKey<String>('child_avatar_dialog'),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: kChildAvatarCardBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x2E000000),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 卡头：阳光金圆徽 + 标题（庆祝感，仿结算卡头）。
                Center(
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: kChildAvatarGold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.emoji_emotions,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.child_avatar_pick,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kChildAvatarGoldDeep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.child_avatar_hint,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.brown.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 🔴 C91 二轮：固定每行恰 3 个 + 每行（含尾行）水平居中 ——
                // 行结构不再随屏宽漂移（旧 Wrap 平板 3+3+1、窄屏手机 2 列）。
                Column(
                  children: <Widget>[
                    for (int rowStart = 0;
                        rowStart < options.length;
                        rowStart += 3) ...<Widget>[
                      if (rowStart > 0) const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          for (
                              int i = rowStart;
                              i < rowStart + 3 && i < options.length;
                              i++)
                            Padding(
                              // 相邻条目间距 = 5 + 5 = 10（首尾各让 5，整行仍居中）。
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: options[i],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ); // Dialog（内层 return 收口）
        }), // Builder builder 闭包 + Builder
      ); // L10nScope
    },
  );
}

/// 卡片里的单个头像选项：圆图 + 名称；[locked] 时整格置灰 + 右下角小锁。
///
/// 点击路由：可选 → [onTap]（收卡片交宿主落库）；锁定 → [onLockedTap]
///（提示，留在卡片）。**onTap 恒非空**（锁定项也必须可点，绝不静默）。
class _AvatarOption extends StatelessWidget {
  const _AvatarOption({
    super.key,
    required this.value,
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
    this.onLockedTap,
    required this.child,
  });

  final String value;
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  /// 锁定项点击回调（可选时忽略）。
  final VoidCallback? onLockedTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: locked ? onLockedTap : onTap,
      child: SizedBox(
        // C91 二轮：84 → 72 —— 320pt 视口下保证一行恰容 3 个（触点仍 ≥44pt）。
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: kChildAvatarBg,
                    borderRadius: BorderRadius.circular(18),
                    // 选中 → 阳光金描边；未选 → 极浅描边让格子有边界感。
                    border: Border.all(
                      color: selected
                          ? kChildAvatarGold
                          : Colors.brown.withValues(alpha: 0.10),
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: Opacity(
                    opacity: locked ? 0.35 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: child,
                    ),
                  ),
                ),
                if (locked)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline,
                        size: 15,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle,
                          size: 19, color: kChildAvatarGold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: locked ? Colors.grey.shade400 : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
