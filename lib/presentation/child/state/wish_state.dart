/// Child-side wish state (A-T03).
///
/// All wish data is read through [WishOrchestrationService]; this layer only
/// derives view models and reads the entitlement tier as a plain `bool`
/// (A34.4 whitelist entry). `totalStats()` is called exactly once here and the
/// resulting focus level is reused by every wish-derived provider.
library child_wish_state;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/constants/app_constants.dart';
import 'package:sunflower_time/core/constants/tracking_event_names.dart';
import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/enums.dart';
import 'package:sunflower_time/domain/entities/tracking_event.dart';
import 'package:sunflower_time/domain/entities/wish.dart';
import 'package:sunflower_time/domain/services/focus_level_service.dart';

/// Event names that carry a wish cross-end event in `tracking_events`.
///
/// Six names cover the 11 first-release kinds because `_trackingNameOf` maps
/// several kinds onto `wish_parent_action` / `wish_tree_open`.
const Set<String> kWishCrossEndEventNames = <String>{
  TrackingEventNames.wishParentAction,
  TrackingEventNames.wishTaskVerified,
  TrackingEventNames.wishTaskRejected,
  TrackingEventNames.wishFulfilled,
  TrackingEventNames.wishAbandoned,
  TrackingEventNames.wishTreeOpen,
};

/// One unread cross-end event, reconstructed from an immutable tracking row.
class WishPendingEvent {
  final String eventId;
  final String wishId;
  final String kind;
  final DateTime at;

  const WishPendingEvent({
    required this.eventId,
    required this.wishId,
    required this.kind,
    required this.at,
  });

  @override
  String toString() => 'WishPendingEvent($eventId)';
}

/// Raw focus level derived from total focus minutes.
///
/// 🔴 `totalStats()` is invoked **once** per build (technical-debt guard): no
/// other wish provider calls it again; they all watch this provider instead.
/// Any failure degrades to level 0 so the shell never blocks on wish data.
final currentFocusLevelProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(economyRevisionProvider);
  try {
    final stats = await ref.read(focusRepositoryProvider).totalStats();
    return levelOfMinutes(stats.totalFocusMinutes);
  } catch (_) {
    return 0;
  }
});

/// Wishes currently mounted on the child's tree (slot order).
final wishTreeProvider = FutureProvider.autoDispose<List<Wish>>((ref) async {
  ref.watch(economyRevisionProvider);
  try {
    return await ref
        .read(wishOrchestrationServiceProvider)
        .mountedWishes();
  } catch (_) {
    return <Wish>[];
  }
});

/// Tree badge view model: mounted count + quota for the current tier.
class WishBadge {
  final int mounted;
  final int quota;
  final int focusLevel;

  const WishBadge({
    this.mounted = 0,
    this.quota = 0,
    this.focusLevel = 0,
  });
}

/// Badge data used by the tree entry point and the "N / M" copy.
///
/// The entitlement tier is read here (the only state-layer read point) and is
/// translated to the domain's `bool isPremium` via the orchestration service's
/// injected DI translation. No UI file reads `entitlementProvider` directly.
final wishBadgeProvider = FutureProvider.autoDispose<WishBadge>((ref) async {
  ref.watch(economyRevisionProvider);
  // The tier read is what the A34.4 whitelist registers; the value itself is
  // supplied to the domain through DI, never branched on in this file.
  ref.watch(entitlementProvider);
  final int level = await ref.watch(currentFocusLevelProvider.future);
  try {
    final service = ref.read(wishOrchestrationServiceProvider);
    return WishBadge(
      mounted: await service.mountedCount(),
      quota: await service.currentWishSlotQuota(),
      focusLevel: level,
    );
  } catch (_) {
    return WishBadge(focusLevel: level);
  }
});

/// All unread wish events, oldest first, with the ack set subtracted.
final pendingWishEventsProvider =
    FutureProvider.autoDispose<List<WishPendingEvent>>((ref) async {
  ref.watch(economyRevisionProvider);
  try {
    final String childId = ref.read(accountServiceProvider).childId;
    final List<TrackingEvent> events = await ref
        .read(trackingRepositoryProvider)
        .eventsOfType(TrackingType.metric);
    final Set<String> acked = (await ref
            .read(settingsStoreProvider)
            .acknowledgedWishEventIds(childId: childId))
        .toSet();

    final List<WishPendingEvent> pending = <WishPendingEvent>[];
    for (final TrackingEvent event in events) {
      if (!kWishCrossEndEventNames.contains(event.name)) continue;
      final Object? rawId = event.payload['event_id'];
      final Object? rawWish = event.payload['wish_id'];
      final Object? rawKind = event.payload['kind'];
      if (rawId is! String || rawWish is! String || rawKind is! String) {
        continue; // 老数据 / 脏 payload：跳过，绝不误弹。
      }
      if (acked.contains(rawId)) continue;
      pending.add(WishPendingEvent(
        eventId: rawId,
        wishId: rawWish,
        kind: rawKind,
        at: event.ts,
      ));
    }
    pending.sort((WishPendingEvent a, WishPendingEvent b) =>
        a.at.compareTo(b.at));
    return pending;
  } catch (_) {
    return <WishPendingEvent>[];
  }
});

/// Unread event ids (A-T03 acceptance surface). Ids are unique even when two
/// events share a kind, because each carries its own epoch millis.
final pendingWishEventIdsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final List<WishPendingEvent> events =
      await ref.watch(pendingWishEventsProvider.future);
  return events.map((WishPendingEvent e) => e.eventId).toList();
});

/// Acknowledge a batch of wish events in one write (childId-scoped key).
Future<void> acknowledgeWishEvents(
  Ref ref, {
  required String childId,
  required Set<String> eventIds,
}) async {
  if (eventIds.isEmpty) return;
  final SettingsStoreAccess store = SettingsStoreAccess(ref);
  final List<String> acked =
      await store.read(childId: childId); // via helper below
  await store.write(
    childId: childId,
    ids: <String>{...acked, ...eventIds}.toList(),
  );
}

/// Tiny indirection so tests can override only `settingsStoreProvider`.
class SettingsStoreAccess {
  SettingsStoreAccess(this._ref);

  final Ref _ref;

  Future<List<String>> read({required String childId}) =>
      _ref.read(settingsStoreProvider).acknowledgedWishEventIds(childId: childId);

  Future<void> write({required String childId, required List<String> ids}) =>
      _ref.read(settingsStoreProvider).setAcknowledgedWishEventIds(
            ids,
            childId: childId,
          );
}

/// Stable key helper re-export for the notice path (single source of truth).
String wishAckedKeyFor(String childId) => wishAckedEventIdsKey(childId);
