/// 孩子端外壳当前 tab 索引（F71，玄参 2026-10-05 反馈「切走花园 tab 氛围音还在播」）。
///
/// 背景：外壳用 IndexedStack 保活 5 个 tab，花园页原先靠 `TickerMode` 依赖重建来
/// 判「自己是否可见」并启停氛围音——但 IndexedStack 更新隐藏子树的时机不保证本页
/// 立即重建，导致切 tab 后背景音继续播完整曲。
///
/// 修法：外壳 `_onSelectTab` 切换时同步写入本 provider；花园页 build 里 `watch`
/// 本索引，**确定性**推导可见性（不再依赖 TickerMode 的重建时机）。
///
/// ⚠️ 独立文件避免 child_shell_page ↔ garden_page 循环导入。
library shell_tab;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 孩子端外壳当前选中的 tab 索引（0=今日 1=成长 2=花园 3=商店 4=我的）。
final StateProvider<int> childShellTabIndexProvider = StateProvider<int>((_) => 0);

/// 花园 tab 在外壳 `_tabs` 中的下标（与 `child_shell_page._tabs` 顺序一致）。
const int kChildTabIndexOfGarden = 2;
