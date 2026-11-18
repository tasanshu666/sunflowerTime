/// Parent-side wish desk state (A-T03).
///
/// The parent today page watches [parentWishDeskProvider]; the shared economy
/// revision provider is the single cross-end refresh bus. Entitlement is read
/// here only as a tier signal (A34.4 whitelist entry) and translated to the
/// domain's `bool isPremium` by DI — no UI file reads entitlement directly.
library parent_wish_state;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sunflower_time/core/di/providers.dart';
import 'package:sunflower_time/domain/entities/wish.dart';

/// Parent desk view model: wishes plus the slot quota for display.
class ParentWishDesk {
  final List<Wish> wishes;
  final int quota;

  const ParentWishDesk({
    this.wishes = const <Wish>[],
    this.quota = 0,
  });
}

/// Parent desk list (reminded first, then longest waiting first) + quota.
final parentWishDeskProvider =
    FutureProvider.autoDispose<ParentWishDesk>((ref) async {
  ref.watch(economyRevisionProvider);
  ref.watch(entitlementProvider);
  try {
    final service = ref.read(wishOrchestrationServiceProvider);
    return ParentWishDesk(
      wishes: await service.parentDeskList(DateTime.now()),
      quota: await service.currentWishSlotQuota(),
    );
  } catch (_) {
    return const ParentWishDesk();
  }
});
