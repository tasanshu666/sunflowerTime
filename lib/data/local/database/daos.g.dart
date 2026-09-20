// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daos.dart';

// ignore_for_file: type=lint
mixin _$SettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SettingsTable get settings => attachedDatabase.settings;
  SettingsDaoManager get managers => SettingsDaoManager(this);
}

class SettingsDaoManager {
  final _$SettingsDaoMixin _db;
  SettingsDaoManager(this._db);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db.attachedDatabase, _db.settings);
}

mixin _$SunlightLedgerDaoMixin on DatabaseAccessor<AppDatabase> {
  $SunlightLedgersTable get sunlightLedgers => attachedDatabase.sunlightLedgers;
  SunlightLedgerDaoManager get managers => SunlightLedgerDaoManager(this);
}

class SunlightLedgerDaoManager {
  final _$SunlightLedgerDaoMixin _db;
  SunlightLedgerDaoManager(this._db);
  $$SunlightLedgersTableTableManager get sunlightLedgers =>
      $$SunlightLedgersTableTableManager(
          _db.attachedDatabase, _db.sunlightLedgers);
}

mixin _$RewardTemplateDaoMixin on DatabaseAccessor<AppDatabase> {
  $RewardTemplatesTable get rewardTemplates => attachedDatabase.rewardTemplates;
  RewardTemplateDaoManager get managers => RewardTemplateDaoManager(this);
}

class RewardTemplateDaoManager {
  final _$RewardTemplateDaoMixin _db;
  RewardTemplateDaoManager(this._db);
  $$RewardTemplatesTableTableManager get rewardTemplates =>
      $$RewardTemplatesTableTableManager(
          _db.attachedDatabase, _db.rewardTemplates);
}

mixin _$RedemptionRequestDaoMixin on DatabaseAccessor<AppDatabase> {
  $RedemptionRequestsTable get redemptionRequests =>
      attachedDatabase.redemptionRequests;
  RedemptionRequestDaoManager get managers => RedemptionRequestDaoManager(this);
}

class RedemptionRequestDaoManager {
  final _$RedemptionRequestDaoMixin _db;
  RedemptionRequestDaoManager(this._db);
  $$RedemptionRequestsTableTableManager get redemptionRequests =>
      $$RedemptionRequestsTableTableManager(
          _db.attachedDatabase, _db.redemptionRequests);
}

mixin _$MonthlyPoolDaoMixin on DatabaseAccessor<AppDatabase> {
  $MonthlyPoolsTable get monthlyPools => attachedDatabase.monthlyPools;
  MonthlyPoolDaoManager get managers => MonthlyPoolDaoManager(this);
}

class MonthlyPoolDaoManager {
  final _$MonthlyPoolDaoMixin _db;
  MonthlyPoolDaoManager(this._db);
  $$MonthlyPoolsTableTableManager get monthlyPools =>
      $$MonthlyPoolsTableTableManager(_db.attachedDatabase, _db.monthlyPools);
}

mixin _$CooldownCounterDaoMixin on DatabaseAccessor<AppDatabase> {
  $CooldownCountersTable get cooldownCounters =>
      attachedDatabase.cooldownCounters;
  CooldownCounterDaoManager get managers => CooldownCounterDaoManager(this);
}

class CooldownCounterDaoManager {
  final _$CooldownCounterDaoMixin _db;
  CooldownCounterDaoManager(this._db);
  $$CooldownCountersTableTableManager get cooldownCounters =>
      $$CooldownCountersTableTableManager(
          _db.attachedDatabase, _db.cooldownCounters);
}

mixin _$TrackingEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $TrackingEventsTable get trackingEvents => attachedDatabase.trackingEvents;
  TrackingEventDaoManager get managers => TrackingEventDaoManager(this);
}

class TrackingEventDaoManager {
  final _$TrackingEventDaoMixin _db;
  TrackingEventDaoManager(this._db);
  $$TrackingEventsTableTableManager get trackingEvents =>
      $$TrackingEventsTableTableManager(
          _db.attachedDatabase, _db.trackingEvents);
}
