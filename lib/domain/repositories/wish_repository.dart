/// Wish repository abstraction (pure Dart; child filtering happens in impl).
library wish_repository;

import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/wish.dart';

abstract class WishRepository {
  /// Wishes on the tree (`treeSlot != null`, `releasedAt == null`), slot asc.
  Future<List<Wish>> mounted();

  /// Achievement pool (`fulfilled` / `replaced`), fulfilledAt desc.
  Future<List<Wish>> pool();

  /// Collection box (`releasedAt != null`), createdAt desc.
  Future<List<Wish>> boxed();

  /// Replaced wishes, abandonedAt desc.
  Future<List<Wish>> abandoned();

  Future<List<Wish>> byStatuses(Set<WishStatus> statuses);

  Future<int> countByStatuses(Set<WishStatus> statuses);

  /// Milestone stamp count: count(status = fulfilled), including child source.
  Future<int> countStampedAchieved();

  /// Slots currently occupied on the tree.
  Future<Set<int>> occupiedSlots();

  /// Single wish or null when absent.
  Future<Wish?> byId(String id);

  Future<void> save(Wish wish);

  /// Compliance deletion helper (wishes only).
  Future<void> deleteAll();
}
