/// Text outlet for the wish tree feature (core layer, ARB-backed in UI batches).
///
/// `lib/domain/**` must stay CJK-free, so every user-visible wish string is
/// named here. UI batches pass the corresponding AppLocalizations value into
/// [WishL10n]; the built-in zh strings below are the canonical source until
/// the ARB keys are added in A-T04 / A-T05.
library wish_l10n;

import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// Keys for all wish-tree UI strings.
enum WishTextKey {
  wishNoTargetYet,
  /// S3（已有小办法）单句成长引导（v0.4：合并原两行文案）。
  wishGoGrowthHint,
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
  WishTextKey.wishGoGrowthHint: '去成长里面实现你的愿望吧',
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

/// 孩子端「爸爸妈妈回应你啦」通知卡的副标题 —— **kind → 文案的唯一映射点**
/// （C136 需求 1，玄参 2026-11-25 真机反馈）。
///
/// ## 为什么只保留两类
/// 玄参原话：「愿望处理了之后，不管是放入愿望池还是收藏箱，这个卡片是干啥的？
/// 不需要吧，把这个卡片提醒机制删除吧」。原先孩子端把**全部 13 种**
/// [WishEventKind] 都弹成一张卡，且副标题直接打印英文枚举名
/// （`fulfilled` / `selfFulfilled` / `released` …），孩子看不懂也不知道要做什么。
///
/// 裁剪后只保留家长**回应**类（需要孩子做出反应的两条）：
///  · [WishEventKind.taskVerified] → 「爸爸妈妈确认你做到啦」；
///  · [WishEventKind.taskRejected] → 「爸爸妈妈说这个再试试」（须体现要重做）。
/// 其余 11 种状态类事件（fulfilled / selfFulfilled / released / restored /
/// abandoned / committed / replaced / tagged / untagged / taskAssigned / goalSet）
/// 一律**不再打扰**孩子 —— 它们的结果孩子在自己操作的那一侧已经看到了。
///
/// ## 为什么「过滤」和「文案」必须是同一个函数
/// 过滤口径与文案口径如果分成两处（一处 `if (kind != …) continue`、一处 switch），
/// 加一个新 kind 时极易只改一处：要么弹出一张没有文案的空行卡，要么该弹的卡被
/// 静默吞掉。故此处**返回 null 即代表不弹卡**，调用方只判断 null，不再自写条件。
///
/// ⚠️ 被过滤的事件**仍必须写入已读**（调用方负责）：否则它们永远停在未读集合里，
/// 每次孩子端外壳首帧都要全表扫描 tracking events，事件越多越慢。
String? wishReplyNoticeSubtitleOf(String kind, AppLocalizations t) {
  if (kind == WishEventKind.taskVerified.name) {
    return t.wishNoticeTaskVerified;
  }
  if (kind == WishEventKind.taskRejected.name) {
    return t.wishNoticeTaskRejected;
  }
  return null;
}

/// A24.2 文案出口：标签枚举 → ARB 文案（`shared_wish_tag_*`）。
///
/// 标签落库用枚举 `name`（text 列，不落 index），展示名一律经本函数取。
String wishTagText(WishTag tag, AppLocalizations t) {
  switch (tag) {
    case WishTag.needMoreTime:
      return t.shared_wish_tag_need_more_time;
    case WishTag.overBudget:
      return t.shared_wish_tag_over_budget;
    case WishTag.notPossible:
      return t.shared_wish_tag_not_possible;
    case WishTag.smallerWish:
      return t.shared_wish_tag_smaller_wish;
    case WishTag.waitForMoment:
      return t.shared_wish_tag_wait_for_moment;
    case WishTag.parentsWorkingOnIt:
      return t.shared_wish_tag_parents_working_on_it;
  }
}

/// A24.2 文案出口：预设回复枚举 → ARB 文案（`shared_wish_reply_*`）。
///
/// [occasion] 仅 `WishReplyPreset.onOccasion` 需要（5 选 1 的时机文案），
/// 其余预设忽略该参数。8 条中文原文由 PRD W19.2 定稿，逐字采用。
String wishReplyPresetText(
  WishReplyPreset preset,
  AppLocalizations t, {
  String occasion = '',
}) {
  switch (preset) {
    case WishReplyPreset.hardButLove:
      return t.shared_wish_reply_hard_but_love;
    case WishReplyPreset.dinosaur:
      return t.shared_wish_reply_dinosaur;
    case WishReplyPreset.waitAndSee:
      return t.shared_wish_reply_wait_and_see;
    case WishReplyPreset.tooExpensive:
      return t.shared_wish_reply_too_expensive;
    case WishReplyPreset.smallerWish:
      return t.shared_wish_reply_smaller_wish;
    case WishReplyPreset.weSawIt:
      return t.shared_wish_reply_we_saw_it;
    case WishReplyPreset.onOccasion:
      return t.shared_wish_reply_on_occasion(occasion);
    case WishReplyPreset.weWantItToo:
      return t.shared_wish_reply_we_want_it_too;
  }
}

/// A24.2 文案出口：时机枚举 → ARB 文案（`shared_wish_occasion_*`）。
String wishOccasionText(WishOccasion occasion, AppLocalizations t) {
  switch (occasion) {
    case WishOccasion.birthday:
      return t.shared_wish_occasion_birthday;
    case WishOccasion.newYear:
      return t.shared_wish_occasion_new_year;
    case WishOccasion.christmas:
      return t.shared_wish_occasion_christmas;
    case WishOccasion.endOfTerm:
      return t.shared_wish_occasion_end_of_term;
    case WishOccasion.tripDay:
      return t.shared_wish_occasion_trip_day;
  }
}

/// A24.3.1 每个预设回复的「推荐标签」—— 用于弹层按所选标签过滤并重排预设词。
///
/// 返回空集表示**通用**（`weSawIt`），任何标签下都保留且排在首位附近。
const Map<WishReplyPreset, Set<WishTag>> kWishPresetRecommendedTags =
    <WishReplyPreset, Set<WishTag>>{
  WishReplyPreset.hardButLove: <WishTag>{
    WishTag.needMoreTime,
    WishTag.parentsWorkingOnIt,
  },
  WishReplyPreset.dinosaur: <WishTag>{WishTag.notPossible},
  WishReplyPreset.waitAndSee: <WishTag>{
    WishTag.needMoreTime,
    WishTag.waitForMoment,
  },
  WishReplyPreset.tooExpensive: <WishTag>{WishTag.overBudget},
  WishReplyPreset.smallerWish: <WishTag>{WishTag.smallerWish},
  WishReplyPreset.weSawIt: <WishTag>{},
  WishReplyPreset.onOccasion: <WishTag>{WishTag.waitForMoment},
  WishReplyPreset.weWantItToo: <WishTag>{WishTag.parentsWorkingOnIt},
};

/// 按所选标签过滤并重排 8 条预设词：命中推荐标签的排前（推荐词首位），
/// 通用词（`weSawIt`）保留，其余仍可见（家长自由选择，不隐藏任何一条）。
List<WishReplyPreset> wishPresetsForTag(WishTag? tag) {
  final List<WishReplyPreset> matched = <WishReplyPreset>[];
  final List<WishReplyPreset> general = <WishReplyPreset>[];
  final List<WishReplyPreset> rest = <WishReplyPreset>[];
  for (final WishReplyPreset preset in WishReplyPreset.values) {
    final Set<WishTag> tags = kWishPresetRecommendedTags[preset]!;
    if (tags.isEmpty) {
      general.add(preset);
    } else if (tag != null && tags.contains(tag)) {
      matched.add(preset);
    } else {
      rest.add(preset);
    }
  }
  return <WishReplyPreset>[...matched, ...general, ...rest];
}
