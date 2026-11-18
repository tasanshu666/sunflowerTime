/// Wish value object and wish-domain enums (pure Dart, no Flutter / drift / CJK).
///
/// Field set follows architecture A15.3 (22 columns). `WishStatus` lives in
/// `domain/entities/enums.dart` and is intentionally not redefined here.
library wish;

import 'package:sunflower_time/domain/entities/enums.dart';

/// Wish category (stored as `wishes.category` index).
enum WishCategory {
  other,
  gift,
  experience,
  toy,
  growth,
  companionship,
}

/// Parent label attached to a wish (stored as `wishes.tag_key` name).
enum WishTag {
  needMoreTime,
  overBudget,
  notPossible,
  smallerWish,
  waitForMoment,
  parentsWorkingOnIt,
}

/// Preset parent reply suggested for a label.
enum WishReplyPreset {
  hardButLove,
  dinosaur,
  waitAndSee,
  tooExpensive,
  smallerWish,
  weSawIt,
  onOccasion,
  weWantItToo,
}

/// Optional occasion shown with a reply (UI never allows free text here).
enum WishOccasion {
  birthday,
  newYear,
  christmas,
  endOfTerm,
  tripDay,
}

/// Goal measurement mode. Index is frozen (persisted as `target_mode`).
enum WishGoalMode {
  focusMinutes, // 0
  taskCount, // 1
}

/// Purely visual fruit stage; never persisted and never a business status.
enum WishFruitStage {
  none,
  waiting,
  growing,
  ripe,
}

/// Parent desk mutually exclusive sections (v0.5.1).
enum WishWorkCategory {
  pendingVerify,
  needsSetup,
  selfProgressing,
  collapsed,
}

/// Cross-end event kinds. Frozen: append only, never re-order.
enum WishEventKind {
  taskAssigned,
  goalSet,
  fulfilled,
  tagged,
  untagged,
  taskVerified,
  taskRejected,
  released,
  restored,
  abandoned,
  selfFulfilled,
  committed,
  replaced,
}

/// Immutable wish value object (22 fields, A15.3).
class Wish {
  final String id;
  final String childId;
  final String text;
  final WishCategory category;
  final WishStatus status;
  final DateTime createdAt;
  final DateTime? committedAt;
  final DateTime? commitDueDate;
  final DateTime? fulfilledAt;
  final String? fulfillSource;
  final DateTime? abandonedAt;
  final DateTime? parentSeenAt;
  final DateTime? remindedAt;
  final String? parentReply;
  final String? replacedText;
  final int? treeSlot;
  final WishGoalMode targetMode;
  final int targetValue;
  final int progressValue;
  final String? tagKey;
  final DateTime? taggedAt;
  final DateTime? releasedAt;

  const Wish({
    required this.id,
    required this.childId,
    required this.text,
    this.category = WishCategory.other,
    this.status = WishStatus.pending,
    required this.createdAt,
    this.committedAt,
    this.commitDueDate,
    this.fulfilledAt,
    this.fulfillSource,
    this.abandonedAt,
    this.parentSeenAt,
    this.remindedAt,
    this.parentReply,
    this.replacedText,
    this.treeSlot,
    this.targetMode = WishGoalMode.focusMinutes,
    this.targetValue = 0,
    this.progressValue = 0,
    this.tagKey,
    this.taggedAt,
    this.releasedAt,
  });

  /// True when the wish occupies a tree slot on the current tree face.
  bool get isMounted => treeSlot != null && releasedAt == null;

  /// True when the wish reached the achievement pool.
  bool get isAchieved =>
      status == WishStatus.fulfilled || status == WishStatus.replaced;

  /// True when a parent label is attached.
  bool get isTagged => tagKey != null;

  /// True when the wish sits in the collection box.
  bool get isReleased => releasedAt != null;

  /// True for the three terminal wish states (linked tasks become closed).
  bool get isTerminal =>
      status == WishStatus.fulfilled ||
      status == WishStatus.replaced ||
      status == WishStatus.abandoned;

  /// Explicit null marker for nullable fields in [copyWith].
  static const Object kClear = _WishFieldClear();

  /// "Argument not supplied" marker for [copyWith].
  static const Object _unset = _WishCopyUnset();

  /// Immutable copy; pass [kClear] to explicitly null a nullable field.
  Wish copyWith({
    String? id,
    String? childId,
    String? text,
    WishCategory? category,
    WishStatus? status,
    DateTime? createdAt,
    Object? committedAt = _unset,
    Object? commitDueDate = _unset,
    Object? fulfilledAt = _unset,
    Object? fulfillSource = _unset,
    Object? abandonedAt = _unset,
    Object? parentSeenAt = _unset,
    Object? remindedAt = _unset,
    Object? parentReply = _unset,
    Object? replacedText = _unset,
    Object? treeSlot = _unset,
    WishGoalMode? targetMode,
    int? targetValue,
    int? progressValue,
    Object? tagKey = _unset,
    Object? taggedAt = _unset,
    Object? releasedAt = _unset,
  }) {
    return Wish(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      text: text ?? this.text,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      committedAt: _resolveDate(committedAt, this.committedAt),
      commitDueDate: _resolveDate(commitDueDate, this.commitDueDate),
      fulfilledAt: _resolveDate(fulfilledAt, this.fulfilledAt),
      fulfillSource: _resolveString(fulfillSource, this.fulfillSource),
      abandonedAt: _resolveDate(abandonedAt, this.abandonedAt),
      parentSeenAt: _resolveDate(parentSeenAt, this.parentSeenAt),
      remindedAt: _resolveDate(remindedAt, this.remindedAt),
      parentReply: _resolveString(parentReply, this.parentReply),
      replacedText: _resolveString(replacedText, this.replacedText),
      treeSlot: _resolveInt(treeSlot, this.treeSlot),
      targetMode: targetMode ?? this.targetMode,
      targetValue: targetValue ?? this.targetValue,
      progressValue: progressValue ?? this.progressValue,
      tagKey: _resolveString(tagKey, this.tagKey),
      taggedAt: _resolveDate(taggedAt, this.taggedAt),
      releasedAt: _resolveDate(releasedAt, this.releasedAt),
    );
  }

  static DateTime? _resolveDate(Object? arg, DateTime? current) {
    if (identical(arg, _unset)) return current;
    if (identical(arg, kClear)) return null;
    return arg as DateTime?;
  }

  static String? _resolveString(Object? arg, String? current) {
    if (identical(arg, _unset)) return current;
    if (identical(arg, kClear)) return null;
    return arg as String?;
  }

  static int? _resolveInt(Object? arg, int? current) {
    if (identical(arg, _unset)) return current;
    if (identical(arg, kClear)) return null;
    return arg as int?;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Wish &&
          other.id == id &&
          other.childId == childId &&
          other.text == text &&
          other.category == category &&
          other.status == status &&
          other.createdAt == createdAt &&
          other.committedAt == committedAt &&
          other.commitDueDate == commitDueDate &&
          other.fulfilledAt == fulfilledAt &&
          other.fulfillSource == fulfillSource &&
          other.abandonedAt == abandonedAt &&
          other.parentSeenAt == parentSeenAt &&
          other.remindedAt == remindedAt &&
          other.parentReply == parentReply &&
          other.replacedText == replacedText &&
          other.treeSlot == treeSlot &&
          other.targetMode == targetMode &&
          other.targetValue == targetValue &&
          other.progressValue == progressValue &&
          other.tagKey == tagKey &&
          other.taggedAt == taggedAt &&
          other.releasedAt == releasedAt;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        id,
        childId,
        text,
        category,
        status,
        createdAt,
        committedAt,
        commitDueDate,
        fulfilledAt,
        fulfillSource,
        abandonedAt,
        parentSeenAt,
        remindedAt,
        parentReply,
        replacedText,
        treeSlot,
        targetMode,
        targetValue,
        progressValue,
        tagKey,
        taggedAt,
        releasedAt,
      ]);

  @override
  String toString() => 'Wish(id: $id, status: $status, treeSlot: $treeSlot, '
      'target: $targetMode/$targetValue, progress: $progressValue)';
}

/// Sentinel carrier for [Wish.kClear].
class _WishFieldClear {
  const _WishFieldClear();
}

/// Sentinel carrier for [Wish._unset].
class _WishCopyUnset {
  const _WishCopyUnset();
}
