/// 愿望「树上三态」判据 —— **唯一实现点**（v0.3.0 / R3-P0-05 / D5）。
///
/// 玄参真机反馈 4/6：孩子许愿后愿望直接挂在树上，**不再有推送按钮**；树上不再
/// 无条件显示「N 个任务 / 等爸爸妈妈设定目标 / 进度条」，而是按**家长动作**分三态：
///
///  · **S1 [WishTreeFace.hanging] 家长未回应** —— 只显原文 + 日期 + 等待天数
///    + 一条**不可点击**的轻提示（「想让爸爸妈妈帮帮忙？让他们看看你的愿望吧」）。
///    明确**不显示**任务徽标、进度条、果实阶段文案。
///  · **S2 [WishTreeFace.parentResponded] 家长已回应（正在想办法 / 暂时做不到）**
///    —— 显示家长回信（空则兜底句），仍**不显示**徽标与进度条。
///  · **S3 [WishTreeFace.hasWays] 家长已布置「小办法」** —— 显示 S3 标题 +
///    小办法列表 + 进度。
///
/// ## 纪律（跨文件约定 S1）
///  · **零 Flutter / 零 drift / 零 CJK**：本层不得 import `package:flutter/**`
///    或 `package:sunflower_time/data/**`，也不得出现任何中文字面量（文案全在
///    ARB，见 `test/i18n/no_han_in_domain_test.dart` 守卫）。
///  · **互斥单出口**：同一 `(wish, wayCount)` 只可能命中一态，判定顺序即优先级
///    S3 → S2 → S1；UI 层**禁止**各自散写 `tagKey == null && ...` 这类条件。
///  · `wayCount` = 关联「小办法」条数 = `wishTasksFamilyProvider(wishId).length`
///    （复用既有 `tasks.wish_id`，**零 schema**）。
library wish_face_state;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';

/// 树上愿望的三态（S1 / S2 / S3）。
enum WishTreeFace {
  /// S1：刚挂上，家长还没回应 —— 只显原文 + 日期 + 等待天数 + 不可点击轻提示。
  hanging,

  /// S2：家长已回应（贴了标签或回了信），但还没布置任何「小办法」。
  parentResponded,

  /// S3：家长已布置「小办法」（关联任务 ≥ 1 条）—— 显小办法列表 + 进度。
  hasWays,
}

/// 三态判据（唯一实现点）。
///
/// 优先级：`wayCount >= 1` ⇒ S3；否则「家长已回应」⇒ S2；否则「仍在树上等
/// 回应」⇒ S1；其余（已承诺 / 已贴标签但字段暂空等极少数边界）兜底归 S2 ——
/// 按「已在处理」呈现，避免把已被家长处理过的愿望又挂回 S1 反复催促。
WishTreeFace wishTreeFaceOf({
  required Wish wish,
  required int wayCount,
}) {
  if (wayCount >= 1) return WishTreeFace.hasWays;

  final String? tagKey = wish.tagKey;
  final String? parentReply = wish.parentReply;
  final bool responded = (tagKey != null && tagKey.isNotEmpty) ||
      (parentReply != null && parentReply.isNotEmpty);
  if (responded) return WishTreeFace.parentResponded;

  if (wish.status == WishStatus.pending && wish.releasedAt == null) {
    return WishTreeFace.hanging;
  }
  return WishTreeFace.parentResponded;
}
