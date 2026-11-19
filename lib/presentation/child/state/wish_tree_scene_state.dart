/// 许愿树场景闸门（v0.2.0 R-P0-04，**v0.3.0 原样保留**）。
///
/// [wishTreeSceneActiveProvider] 是「`/wish-tree` 场景是否占据台前」的**唯一
/// 真源**：树页 `initState` 置 true、`dispose` 置 false；花园页把环境音局部
/// 判据折入 `gardenVisible && !wishTreeSceneActive`，复用既有成对启停
/// `_syncAmbientTimer()`（它会 cancel `Timer.periodic`，只 stop 播放器会被
/// 30s 定时器复发）。**树页零 AudioService 代码**，音频 API 冻结。
///
/// 🔴 v0.3.0：v0.2 的 `wishShareRevisionProvider` 已随推送机制整体删除
/// （PRD v0.3 §1.1 #7）；跨端刷新回归既有 `economyRevisionProvider`。
library wish_tree_scene_state;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 场景闸门：许愿树页在台前 ⇒ true，否则 false。
final StateProvider<bool> wishTreeSceneActiveProvider =
    StateProvider<bool>((Ref ref) => false);
