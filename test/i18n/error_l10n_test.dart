/// 领域异常 → 文案映射守卫（i18n B3 · T03）。
///
/// ## 为什么需要它
/// T03 把 `PlantOperationException`（17 码）/ `TaskCheckInException`（9 码）从
/// 「中文串」改成「语义码 + 数值载荷」，26 条文案全部挪进 ARB。一旦某个 case 写错
/// （A 码返回 B 文案），领域逻辑零变化、单测若只断言 `throwsA(isA<...>())` 也全绿，
/// 只有**孩子看到错话**。故本测试把 26 条 zh 文案**逐字钉死**（含载荷插值位置），
/// 并对 en 断言「不含 CJK」—— 后者能立刻暴露「漏翻 / 复制中文占位」。
///
/// 载荷语义见 `PlantOperationError` 的文档表（a/b 随 code 而变）。
library error_l10n_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/error_l10n.dart';
import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// CJK 统一表意文字 + 中文标点（证明 en 文案真的被翻译了）。
final RegExp _cjkRe = RegExp(r'[\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]');

void main() {
  final AppLocalizationsZh zh = AppLocalizationsZh();
  final AppLocalizationsEn en = AppLocalizationsEn();

  /// 便捷构造：语义码 + 载荷。
  PlantOperationException plantErr(PlantOperationError code, {int? a, int? b}) =>
      PlantOperationException(code, a: a, b: b);

  group('植物操作错误：17 码 zh 逐字钉死', () {
    const Map<PlantOperationError, String> table = <PlantOperationError, String>{
      PlantOperationError.speciesNotFound: '未找到该植物物种',
      PlantOperationError.potOutOfCapacity: '花盆序号超出容量（3 / 4）',
      PlantOperationError.potOccupied: '花盆 #2 已被占用，请先清理',
      PlantOperationError.premiumFragmentsOnly: '精英植物只能用碎片兑换',
      PlantOperationError.seedEmpty: '种子已用完，去开花收集新的种子吧',
      PlantOperationError.sunlightNotEnough: '阳光不足，还差 20 阳光',
      PlantOperationError.fragmentsNotEnough: '碎片不足，还差 3 片',
      PlantOperationError.careStateInvalid: '仅成长中/开花/枯萎植物可养护',
      PlantOperationError.waterDailyLimit: '今日浇水已达 6 次上限',
      PlantOperationError.waterInterval: '浇水间隔需 30 分钟，还需 12 分钟',
      PlantOperationError.fertilizeDailyLimit: '今日施肥已达 2 次上限',
      PlantOperationError.plantNotFound: '植物不存在',
      PlantOperationError.alreadyWilted: '这株已经枯萎了，不用清理啦',
      PlantOperationError.noWeed: '这盆没有杂草哦',
      PlantOperationError.noPest: '这盆没有害虫哦',
      PlantOperationError.gardenFull: '花园已达当前档位容量上限（6 盆），解锁可扩容',
      PlantOperationError.rewardNotMature: '奖励还没成熟，或已经被领取啦',
    };

    /// 每个 code 对应的载荷（无载荷的给 null）。
    const Map<PlantOperationError, List<int?>> payloads =
        <PlantOperationError, List<int?>>{
      PlantOperationError.potOutOfCapacity: <int?>[3, 4],
      PlantOperationError.potOccupied: <int?>[2, null],
      PlantOperationError.sunlightNotEnough: <int?>[20, null],
      PlantOperationError.fragmentsNotEnough: <int?>[3, null],
      PlantOperationError.waterDailyLimit: <int?>[6, null],
      PlantOperationError.waterInterval: <int?>[30, 12],
      PlantOperationError.fertilizeDailyLimit: <int?>[2, null],
      PlantOperationError.gardenFull: <int?>[6, null],
    };

    test('枚举恰好 17 个语义码（新增/删除必须同步本测试与 error_l10n）', () {
      expect(PlantOperationError.values.length, 17);
      expect(table.keys.toSet(), PlantOperationError.values.toSet());
    });

    for (final PlantOperationError code in PlantOperationError.values) {
      test('${code.name} → 「${table[code]}」', () {
        final List<int?> p = payloads[code] ?? const <int?>[null, null];
        final PlantOperationException e = plantErr(code, a: p[0], b: p[1]);
        expect(plantErrorMessage(e, zh), table[code]);
        // en 必须真的翻译过（无 CJK），且非空。
        final String enText = plantErrorMessage(e, en);
        expect(enText, isNotEmpty);
        expect(_cjkRe.hasMatch(enText), isFalse,
            reason: '${code.name} 的 en 文案含 CJK —— 漏翻或复制了中文');
      });
    }

    test('载荷缺省按 0 渲染，不抛异常（提示语构造永不打崩 App）', () {
      expect(
        plantErrorMessage(plantErr(PlantOperationError.sunlightNotEnough), zh),
        '阳光不足，还差 0 阳光',
      );
      expect(
        plantErrorMessage(plantErr(PlantOperationError.waterInterval), zh),
        '浇水间隔需 0 分钟，还需 0 分钟',
      );
    });

    test('toString 只输出 ASCII 语义码 + 载荷（日志/断言友好，不含中文）', () {
      expect(
        plantErr(PlantOperationError.waterInterval, a: 30, b: 12).toString(),
        'PlantOperationException: waterInterval(30, 12)',
      );
      expect(plantErr(PlantOperationError.noWeed).toString(),
          'PlantOperationException: noWeed');
      expect(_cjkRe.hasMatch(plantErr(PlantOperationError.noWeed).toString()),
          isFalse);
    });
  });

  group('打卡错误：9 码 zh 逐字钉死', () {
    const Map<TaskCheckInError, String> table = <TaskCheckInError, String>{
      TaskCheckInError.linkedAuto: '这个成长项要在专注里自动完成哦',
      TaskCheckInError.alreadyDone: '这个成长项今天已经做到啦',
      TaskCheckInError.notLinked: '非联动成长项不能走专注结算',
      TaskCheckInError.sessionNotToday: '这次专注不在今天，不能结算今天的成长项',
      TaskCheckInError.sessionUsed: '这次专注已经结算过成长项啦',
      TaskCheckInError.notFound: '找不到这条记录，可能已被删除',
      TaskCheckInError.alreadyVerified: '这条记录已经处理过啦，不能重复核销',
      TaskCheckInError.alreadyRejected: '这条记录已经处理过啦，不能重复处理',
      TaskCheckInError.race: '这条记录刚刚已经被处理过了',
    };

    test('枚举恰好 9 个语义码（新增/删除必须同步本测试与 error_l10n）', () {
      expect(TaskCheckInError.values.length, 9);
      expect(table.keys.toSet(), TaskCheckInError.values.toSet());
    });

    for (final TaskCheckInError code in TaskCheckInError.values) {
      test('${code.name} → 「${table[code]}」', () {
        final TaskCheckInException e = TaskCheckInException(code);
        expect(taskCheckInErrorMessage(e, zh), table[code]);
        final String enText = taskCheckInErrorMessage(e, en);
        expect(enText, isNotEmpty);
        expect(_cjkRe.hasMatch(enText), isFalse,
            reason: '${code.name} 的 en 文案含 CJK —— 漏翻或复制了中文');
      });
    }

    test('toString 只输出 ASCII 语义码（不含中文）', () {
      expect(
        const TaskCheckInException(TaskCheckInError.race).toString(),
        'TaskCheckInException: race',
      );
      expect(
        _cjkRe.hasMatch(const TaskCheckInException(TaskCheckInError.race).toString()),
        isFalse,
      );
    });
  });

  group('额度阻塞原因（PlantBlockReason）→ 文案：与异常同源', () {
    test('careStateInvalid / waterDailyLimit / waterInterval / fertilizeDailyLimit', () {
      expect(
        plantBlockReasonMessage(
            const PlantBlockReason(PlantOperationError.careStateInvalid), zh),
        '仅成长中/开花/枯萎植物可养护',
      );
      expect(
        plantBlockReasonMessage(
            const PlantBlockReason(PlantOperationError.waterDailyLimit, a: 6), zh),
        '今日浇水已达 6 次上限',
      );
      expect(
        plantBlockReasonMessage(
            const PlantBlockReason(PlantOperationError.waterInterval, a: 30, b: 12),
            zh),
        '浇水间隔需 30 分钟，还需 12 分钟',
      );
      expect(
        plantBlockReasonMessage(
            const PlantBlockReason(PlantOperationError.fertilizeDailyLimit, a: 2), zh),
        '今日施肥已达 2 次上限',
      );
    });

    test('PlantBlockReason 值语义：同 code 同载荷相等，载荷不同不等', () {
      const PlantBlockReason x =
          PlantBlockReason(PlantOperationError.waterInterval, a: 30, b: 12);
      const PlantBlockReason y =
          PlantBlockReason(PlantOperationError.waterInterval, a: 30, b: 12);
      const PlantBlockReason z =
          PlantBlockReason(PlantOperationError.waterInterval, a: 30, b: 5);
      expect(x, y);
      expect(x.hashCode, y.hashCode);
      expect(x, isNot(z));
    });
  });
}
