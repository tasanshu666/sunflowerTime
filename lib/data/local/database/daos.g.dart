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
