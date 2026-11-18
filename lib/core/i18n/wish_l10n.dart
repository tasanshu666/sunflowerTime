/// Text outlet for the wish tree feature (core layer, ARB-backed in UI batches).
///
/// `lib/domain/**` must stay CJK-free, so every user-visible wish string is
/// named here. UI batches pass the corresponding AppLocalizations value into
/// [WishL10n]; the built-in zh strings below are the canonical source until
/// the ARB keys are added in A-T04 / A-T05.
library wish_l10n;

import 'package:sunflower_time/domain/entities/wish.dart';

/// Keys for all wish-tree UI strings.
enum WishTextKey {
  wishNoTargetYet,
  wishWaiting,
  wishGrowing,
  wishRipe,
  wishSelfFulfillLabel,
  wishSelfFulfillConfirm,
  wishUndoLabel,
  wishUndoConfirm,
  wishSlotFullHint,
  wishSoftGateHint,
  wishLabelTagged,
  wishCollectBox,
  wishRestore,
  wishPlanTogetherHint,
  wishGoalFocusMinutes,
  wishGoalTaskCount,
  wishProgressFocus,
  wishProgressCount,
  wishParentReplyEmpty,
}

/// Canonical Chinese strings, keyed by [WishTextKey].
const Map<WishTextKey, String> kWishZhTexts = <WishTextKey, String>{
  WishTextKey.wishNoTargetYet: '等爸爸妈妈设定目标',
  WishTextKey.wishWaiting: '等待开始',
  WishTextKey.wishGrowing: '愿望的果实正在成长',
  WishTextKey.wishRipe: '愿望成真啦',
  WishTextKey.wishSelfFulfillLabel: '我做到了',
  WishTextKey.wishSelfFulfillConfirm: '确定是你自己做到的吗？',
  WishTextKey.wishUndoLabel: '退回树上',
  WishTextKey.wishUndoConfirm: '确定要把这个愿望退回树上吗？',
  WishTextKey.wishSlotFullHint: '树上已经挂满啦，先实现一个再许愿吧',
  WishTextKey.wishSoftGateHint: '先在花园里种下一株植物吧',
  WishTextKey.wishLabelTagged: '爸爸妈妈说这个暂时做不到',
  WishTextKey.wishCollectBox: '放进愿望收藏箱',
  WishTextKey.wishRestore: '取回愿望',
  WishTextKey.wishPlanTogetherHint: '和孩子一起商量着填',
  WishTextKey.wishGoalFocusMinutes: '专注分钟',
  WishTextKey.wishGoalTaskCount: '任务条数',
  WishTextKey.wishProgressFocus: '已专注 {done} 分钟，还差 {left} 分钟',
  WishTextKey.wishProgressCount: '已完成 {done} 个任务，还差 {left} 个',
  WishTextKey.wishParentReplyEmpty: '爸爸妈妈还没回信',
};

/// Resolve a wish string with an optional ARB-backed override map.
String wishTextOf(
  WishTextKey key, {
  Map<WishTextKey, String> overrides = const <WishTextKey, String>{},
}) =>
    overrides[key] ?? kWishZhTexts[key] ?? '';

/// Label for a fruit stage.
String wishFruitStageTextOf(
  WishFruitStage stage, {
  Map<WishTextKey, String> overrides = const <WishTextKey, String>{},
}) =>
    wishTextOf(_fruitStageKey(stage), overrides: overrides);

WishTextKey _fruitStageKey(WishFruitStage stage) {
  switch (stage) {
    case WishFruitStage.none:
      return WishTextKey.wishNoTargetYet;
    case WishFruitStage.waiting:
      return WishTextKey.wishWaiting;
    case WishFruitStage.growing:
      return WishTextKey.wishGrowing;
    case WishFruitStage.ripe:
      return WishTextKey.wishRipe;
  }
}
