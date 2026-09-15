/// Drift + SQLCipher 数据库入口（§3 / §10.4 C13 加密存储义务）。
///
/// opener 用 SQLCipher 打开本地库并设密钥（PRAGMA key）。MVP 口令来自
/// `app_constants.kDatabasePassphrase`（骨架阶段固定；生产应改为设备级密钥派生
/// + flutter_secure_storage 保管，见 T03 风险项）。
library app_database;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sunflower_time/core/constants/app_constants.dart';

import 'daos.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Settings,
    FocusSessions,
    SunlightLedgers,
    RewardTemplates,
    RedemptionRequests,
    MonthlyPools,
    Tasks,
    CheckIns,
    CooldownCounters,
    TrackingEvents,
  ],
  daos: [SettingsDao, SunlightLedgerDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openEncryptedDb());

  @override
  int get schemaVersion => 1;
}

/// SQLCipher 加密库打开器（Lazy：首次访问才建连）。
LazyDatabase openEncryptedDb() {
  return LazyDatabase(() async {
    // 注：sqlite3 3.x 已移除 open.overrideFor（改由原生资产 hook 决定加载哪个库）。
    // 本工程在 pubspec.yaml 的 hooks.user_defines 里配置：
    //   sqlite3: { source: system, name_android: sqlcipher }
    // —— Android 加载 sqlcipher_flutter_libs 经 Maven 提供的 libsqlcipher.so（ABI 兼容 sqlite3），
    //    `PRAGMA key` 因此生效；同时避免了从 GitHub 下载预编译库（本机被代理拦截）。
    // 旧 Android 上 SQLCipher 打开兼容处理（sqlcipher_flutter_libs 提供）。
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/$kDatabaseFileName');
    return NativeDatabase(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$kDatabasePassphrase'");
      },
    );
  });
}
