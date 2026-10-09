/// 护眼记录仓储测试（玄参 2026-10-09：家长报告护眼统计的数据口）。
///
/// 真实 Drift 内存库（sqlcipher 密钥路径不走 —— NativeDatabase.memory 直开）：
///  · append → countByResult / watchedSecondsByResult 聚合正确；
///  · completed 与 skipped 分开计数；
///  · id 冲突 insertOrIgnore：不覆盖旧事实。
library eye_care_log_repository_test;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/data/local/database/app_database.dart';
import 'package:sunflower_time/data/local/repositories/eye_care_log_local_repository.dart';
import 'package:sunflower_time/domain/entities/eye_care_log.dart';
import 'package:sunflower_time/domain/services/eye_care_service.dart';

EyeCareLog _log(
  String id, {
  EyeCareResultType result = EyeCareResultType.completed,
  int watched = 63,
}) {
  final DateTime ts = DateTime(2026, 10, 9, 10);
  return EyeCareLog(
    id: id,
    ts: ts,
    dayKey: '2026-10-09',
    result: result,
    watchedSeconds: watched,
    source: EyeCareSource.inSession,
  );
}

void main() {
  late AppDatabase database;
  late EyeCareLogLocalRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = EyeCareLogLocalRepository(database);
  });

  tearDown(() => database.close());

  test('append 后 countByResult 按结果分开计数', () async {
    await repo.append(_log('a1'));
    await repo.append(_log('a2'));
    await repo.append(_log('a3', result: EyeCareResultType.skipped, watched: 17));

    expect(await repo.countByResult(EyeCareResultType.completed), 2);
    expect(await repo.countByResult(EyeCareResultType.skipped), 1);
  });

  test('watchedSecondsByResult 只聚合指定结果的观看秒数', () async {
    await repo.append(_log('a1', watched: 63));
    await repo.append(_log('a2', watched: 63));
    await repo.append(_log('a3', result: EyeCareResultType.skipped, watched: 17));
    await repo.append(_log('a4', result: EyeCareResultType.skipped, watched: 5));

    expect(await repo.watchedSecondsByResult(EyeCareResultType.completed), 126);
    expect(await repo.watchedSecondsByResult(EyeCareResultType.skipped), 22);
  });

  test('id 冲突 insertOrIgnore：不覆盖旧事实（append-only 纪律）', () async {
    await repo.append(_log('dup', watched: 63));
    await repo.append(_log('dup', watched: 1));

    expect(await repo.countByResult(EyeCareResultType.completed), 1,
        reason: '重复 id 被忽略，只保留首行');
    expect(await repo.watchedSecondsByResult(EyeCareResultType.completed), 63,
        reason: '保留的是首行（63s），不是覆盖后的 1s');
  });

  test('空表聚合返回 0（升级后新表起步即空）', () async {
    expect(await repo.countByResult(EyeCareResultType.completed), 0);
    expect(await repo.countByResult(EyeCareResultType.skipped), 0);
    expect(await repo.watchedSecondsByResult(EyeCareResultType.skipped), 0);
  });
}
