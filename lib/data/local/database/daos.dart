/// DAO：聚合 / 时间序列查询（§3.2 对账 SQL）。
library daos;

import 'package:drift/drift.dart';
import 'package:sunflower_time/domain/entities/enums.dart';

import 'app_database.dart';
import 'tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// 读取设置单行（单例行，id = 1）。
  Future<Setting?> getRow() => select(settings).getSingleOrNull();

  /// 插入或更新（按主键 id 冲突合并）。
  Future<void> upsert(SettingsCompanion row) =>
      into(settings).insertOnConflictUpdate(row);
}

@DriftAccessor(tables: [SunlightLedgers])
class SunlightLedgerDao extends DatabaseAccessor<AppDatabase>
    with _$SunlightLedgerDaoMixin {
  SunlightLedgerDao(super.db);

  /// 追加一条账本记录（append-only，§3.2）。
  Future<void> append(SunlightLedgersCompanion row) =>
      into(sunlightLedgers).insert(row);

  /// 当前余额（sum(net)）。
  Future<double> balance() async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 某日净产出（软顶校验用，§3.2）。
  Future<double> dayNet(String dayKey) async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.dayKey.equals(dayKey))
          ..addColumns([sum]))
        .getSingle();
    return row.read(sum) ?? 0.0;
  }

  /// 已核销总额对账（§3.2）。
  Future<double> verifiedRedeemTotal() async {
    final Expression<double> sum = sunlightLedgers.net.sum();
    final row = await (selectOnly(sunlightLedgers)
          ..where(sunlightLedgers.type.equals(SunlightType.redeem.index))
          ..addColumns([sum]))
        .getSingle();
    final value = row.read(sum);
    return (value ?? 0.0).abs();
  }
}
