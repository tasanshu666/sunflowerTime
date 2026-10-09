/// C44 卡片美术图标 + tab 背景 资源单点映射（2026-10-09 玄参素材交付）。
///
/// 口径（玄参 2026-10-09 拍板，四项 AskUserQuestion 全选推荐项；C46c 联动项
/// 改为优先用 focus 闹钟）：
///  · **按名称关键词匹配**（不改数据模型、家长无感）：任务名/奖励名含关键词 →
///    对应图标；联动专注项一律 focus（闹钟）→ 分类兜底 → 最后 default 图。
///  · 图标 512×512 透明 WebP（源 2048² 由 `tools/convert_ui_assets.py` 缩制），
///    显示 56px 逻辑像素，`errorBuilder` 回退原马卡龙色块 + 内置图标（美术永不阻塞）。
///  · ⚠️ **文件名即契约**：`assets/ui/{growth,store}/` 下文件名与本文件常量一一对应，
///    改名必须同步（护栏测试 `test/m4/ui_assets_guard_test.dart` 钉死）。
///
/// 背景：三张「上半场景 + 下半留白」整页底图，`BoxFit.cover` + topCenter 铺满；
/// store01/store03 为备选（未登记 pubspec），换背景 = 改 [kStoreBgAsset] + 登记。
library growth_icons;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/reward_template.dart';
import 'package:sunflower_time/domain/entities/task.dart';

// ── tab 整页背景 ─────────────────────────────────────────────────────

/// 「今日」tab 背景。
const String kTodayBgAsset = 'assets/backgrounds/today.webp';

/// 「成长」tab 背景。
const String kGrowthBgAsset = 'assets/backgrounds/growth.webp';

/// 「商店」tab 背景（玄参拍板：三张备选先用 02 试用看效果）。
const String kStoreBgAsset = 'assets/backgrounds/store02.webp';

// ── 成长项图标（assets/ui/growth/，9 张全用上）───────────────────────

/// 名字关键词 → 图标（顺序即优先级，**先命中先用**；先专后泛防误配）。
const List<(String, List<String>)> _growthKeywordIcons = <(String, List<String>)>[
  ('clean_up', <String>['整理', '打扫', '清洁', '收拾', '家务']),
  ('homework', <String>['作业', '写字', '练字', '口算']),
  ('listen', <String>['听']), // 先于 read_book：「听写」归 homework（写），「朗读」归 read_book（读）
  ('read_book', <String>['读', '阅', '书']),
  ('sports', <String>['运动', '球', '跳绳', '跑', '游泳', '泳', '骑', '操']),
  ('habit', <String>['习惯']),
];

/// 成长项卡片图标 asset（null = 无匹配，调用方回退马卡龙色块 + 状态图标）。
///
/// 匹配链（C46c 玄参 2026-10-09 改口径：**联动项一律 focus 闹钟**，孩子一眼
/// 分辨「这项要去专注」）：联动专注项 `focus` → 名字关键词 → 分类兜底
/// （运动/生活）→ `default_ui`。
String growthIconAssetFor(Task task) {
  // C46c：联动专注项**优先于一切**名字关键词（原「名字优先」口径废弃）。
  if (task.requiresFocus) return 'assets/ui/growth/focus.webp';
  final String name = task.name;
  for (final (String icon, List<String> words) in _growthKeywordIcons) {
    for (final String w in words) {
      if (name.contains(w)) return 'assets/ui/growth/$icon.webp';
    }
  }
  if (task.category == TaskCategory.sports) return 'assets/ui/growth/sports.webp';
  if (task.category == TaskCategory.life) return 'assets/ui/growth/life.webp';
  return 'assets/ui/growth/default_ui.webp';
}

// ── 奖励图标（assets/ui/store/，7 张全用上）──────────────────────────

const List<(String, List<String>)> _rewardKeywordIcons = <(String, List<String>)>[
  ('store_book', <String>['书', '阅读', '绘本']),
  ('store_sports', <String>['运动', '球']),
  ('store_toys', <String>['玩具', '积木', '乐高']),
  ('store_game', <String>['游戏', '电玩']),
  ('store_snack', <String>['零食', '糖', '冰淇淋', '蛋糕', '薯片', '饮料']),
  ('store_play', <String>['游玩', '公园', '电影', '动物园', '游乐']),
];

/// 奖励卡片图标 asset。
///
/// 匹配链：奖励名关键词 → 内容分类兜底（零食/游玩/娱乐）→ `store_default`。
String rewardIconAssetFor(RewardTemplate tpl) {
  final String name = tpl.name;
  for (final (String icon, List<String> words) in _rewardKeywordIcons) {
    for (final String w in words) {
      if (name.contains(w)) return 'assets/ui/store/$icon.webp';
    }
  }
  switch (tpl.contentCategory) {
    case RewardContentCategory.snacks:
      return 'assets/ui/store/store_snack.webp';
    case RewardContentCategory.play:
      return 'assets/ui/store/store_play.webp';
    case RewardContentCategory.entertainment:
      return 'assets/ui/store/store_game.webp';
    case RewardContentCategory.other:
      return 'assets/ui/store/store_default.webp';
  }
}
