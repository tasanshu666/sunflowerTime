/// Persistent guard-energy balance for one child (v0.3 Xuan-san feedback 3).
///
/// The balance lives in its own store, deliberately separate from
/// `GuardDayState`: `GuardService.expire()` clears the day-state key, but a
/// guard energy point is a long-lived balance and must survive that clear.
///
/// `creditedSessionIds` is the idempotency ledger: a focus session grants
/// energy at most once, no matter how many times `energyAvailable()` is called.
library guard_energy;

/// Immutable snapshot of a child's persistent guard energy.
class GuardEnergy {
  const GuardEnergy({
    this.balance = 0,
    this.creditedSessionIds = const <String>{},
  });

  /// Currently spendable points (never negative).
  final int balance;

  /// Ids of focus sessions that have already been credited.
  final Set<String> creditedSessionIds;

  /// Immutable copy with only the supplied fields replaced.
  GuardEnergy copyWith({
    int? balance,
    Set<String>? creditedSessionIds,
  }) {
    return GuardEnergy(
      balance: balance ?? this.balance,
      creditedSessionIds: creditedSessionIds ?? this.creditedSessionIds,
    );
  }

  /// Stable JSON form for prefs persistence.
  Map<String, Object?> toJson() => <String, Object?>{
        'balance': balance,
        'creditedSessionIds': creditedSessionIds.toList()..sort(),
      };

  /// Tolerant decoder: broken prefs degrade to an empty balance.
  factory GuardEnergy.fromJson(Map<String, Object?> json) {
    final Object? rawBalance = json['balance'];
    final int balance = rawBalance is int && rawBalance > 0 ? rawBalance : 0;
    final Object? rawIds = json['creditedSessionIds'];
    final Set<String> ids = <String>{
      if (rawIds is List)
        for (final Object? id in rawIds)
          if (id is String && id.isNotEmpty) id,
    };
    return GuardEnergy(balance: balance, creditedSessionIds: ids);
  }

  /// Empty snapshot (used by stores when no key exists yet).
  static const GuardEnergy empty = GuardEnergy();
}
