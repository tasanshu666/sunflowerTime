/// 专注报告趋势桶标签守卫（i18n B3 · T04）。
///
/// ## 迁移动机
/// 迁移前 `PeriodBucket.label` 由 domain 派生三套中文（`周一`…`周日` / `第1周` /
/// `1月`），英文环境下报告图整排中文。T04 删掉了该字段，标签改由
/// `lib/core/i18n/report_l10n.dart` 在 UI 侧按当前语言装配。
///
/// ## 本文件守什么
/// ① **zh 逐字节等价**：新实现必须与迁移前输出完全一致（否则老用户看到「周一」变
///    `Monday` 或 `1月` 变 `Jan`，属于静默回归）；
/// ② **en 真英文且无 CJK**：这是本批的**目的**，不是附带效果；
/// ③ **周档按 `start.weekday` 派生，不按下标**：防未来切片起点变化时静默错位
///    （迁移前实现也是按 weekday 查表，本测试钉死这个语义）；
/// ④ **越界 weekday 返回空串而不崩**：报告页不许因一个脏日期整块白屏；
/// ⑤ **反向守卫**：`PeriodBucket` 不得再出现 `label`（防止有人「顺手加回来」，
///    一旦加回就会重新引入 domain CJK 通道）。
library report_l10n_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/i18n/report_l10n.dart';
import 'package:sunflower_time/domain/entities/report_period.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_en.dart';
import 'package:sunflower_time/l10n/generated/app_localizations_zh.dart';

/// 造一个只有 `start` 有意义的桶（标签只看 `start`）。
PeriodBucket _bucketOf(DateTime start) => PeriodBucket(
      start: start,
      end: start.add(const Duration(days: 1)),
      focusMinutes: 0,
    );

/// 造一个整月第 [day] 日的桶。
PeriodBucket _monthDayBucket(int year, int month, int day) =>
    _bucketOf(DateTime(year, month, day));

void main() {
  final AppLocalizations zh = AppLocalizationsZh();
  final AppLocalizations en = AppLocalizationsEn();

  // ───────────────────────── ① zh 逐字节等价 ─────────────────────────
  group('① zh 逐字节等价（迁移前输出必须一字不差）', () {
    test('周档 7 根日柱 = 周一…周日（按 start.weekday 派生）', () {
      // 2026-02-02 是周一（`DateTime.monday == 1`）。
      final DateTime monday = DateTime(2026, 2, 2);
      expect(monday.weekday, DateTime.monday, reason: '夹具日期必须真的是周一');

      const List<String> expected = <String>[
        '周一',
        '周二',
        '周三',
        '周四',
        '周五',
        '周六',
        '周日',
      ];
      for (int i = 0; i < 7; i++) {
        final PeriodBucket b = _bucketOf(monday.add(Duration(days: i)));
        expect(
          reportBucketLabel(ReportPeriod.week, b, i, zh),
          expected[i],
          reason: '第 ${i + 1} 根日柱（weekday=${b.start.weekday}）',
        );
      }
    });

    test('周档按 weekday 派生 —— 即使下标与 weekday 不同源也不错位', () {
      // 故意让「下标 0」对应周日：若实现按下标查表，会错出「周一」。
      final PeriodBucket sunday = _bucketOf(DateTime(2026, 2, 8));
      expect(sunday.start.weekday, DateTime.sunday);
      expect(
        reportBucketLabel(ReportPeriod.week, sunday, 0, zh),
        '周日',
        reason: '标签必须跟 start.weekday 走，不能被 index 带偏',
      );
    });

    test('月档 = 第1周…第5周（index + 1）', () {
      for (int i = 0; i < 5; i++) {
        final PeriodBucket b = _monthDayBucket(2026, 2, 1 + i * 7);
        expect(
          reportBucketLabel(ReportPeriod.month, b, i, zh),
          '第${i + 1}周',
          reason: '月档第 ${i + 1} 桶',
        );
      }
    });

    test('年档 = 1月…12月（DateFormat "M月"）', () {
      for (int m = 1; m <= 12; m++) {
        final PeriodBucket b = _monthDayBucket(2026, m, 1);
        expect(
          reportBucketLabel(ReportPeriod.year, b, m - 1, zh),
          '$m月',
          reason: '年档第 $m 根月柱',
        );
      }
    });

    test('日档无趋势桶 → 恒为空串（仅为 switch 穷举）', () {
      final PeriodBucket b = _bucketOf(DateTime(2026, 2, 2));
      expect(reportBucketLabel(ReportPeriod.day, b, 0, zh), '');
      expect(reportBucketLabel(ReportPeriod.day, b, 9, zh), '',
          reason: 'index 对日档无意义');
    });
  });

  // ───────────────────────── ② en 真英文 ─────────────────────────
  group('② en 生效（本批目的）', () {
    test('周档 = Mon…Sun', () {
      final DateTime monday = DateTime(2026, 2, 2);
      const List<String> expected = <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ];
      for (int i = 0; i < 7; i++) {
        final PeriodBucket b = _bucketOf(monday.add(Duration(days: i)));
        expect(reportBucketLabel(ReportPeriod.week, b, i, en), expected[i]);
      }
    });

    test('月档 = Wk 1…Wk 5', () {
      for (int i = 0; i < 5; i++) {
        final PeriodBucket b = _monthDayBucket(2026, 2, 1 + i * 7);
        expect(reportBucketLabel(ReportPeriod.month, b, i, en), 'Wk ${i + 1}');
      }
    });

    test('年档 = Jan…Dec（DateFormat "MMM"，不引 intl locale 数据）', () {
      const List<String> expected = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      for (int m = 1; m <= 12; m++) {
        final PeriodBucket b = _monthDayBucket(2026, m, 1);
        expect(
          reportBucketLabel(ReportPeriod.year, b, m - 1, en),
          expected[m - 1],
          reason: '年档第 $m 根月柱（en）',
        );
      }
    });

    test('en 下全部桶标签无 CJK（含中文数字 / 单位）', () {
      final RegExp cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');
      final DateTime monday = DateTime(2026, 2, 2);

      final List<String> labels = <String>[
        for (int i = 0; i < 7; i++)
          reportBucketLabel(ReportPeriod.week, _bucketOf(monday.add(Duration(days: i))), i, en),
        for (int i = 0; i < 5; i++)
          reportBucketLabel(ReportPeriod.month, _monthDayBucket(2026, 2, 1 + i * 7), i, en),
        for (int m = 1; m <= 12; m++)
          reportBucketLabel(ReportPeriod.year, _monthDayBucket(2026, m, 1), m - 1, en),
      ];

      expect(labels.length, 24, reason: '7 + 5 + 12');
      for (final String label in labels) {
        expect(label, isNotEmpty, reason: 'en 下不许有空标签');
        expect(cjk.hasMatch(label), isFalse, reason: 'en 标签含 CJK：$label');
      }
    });
  });

  // ───────────────────────── ③ 越界防御 ─────────────────────────
  group('③ weekdayFullLabel 越界不崩', () {
    test('0 / 8 / 负数 → 空串', () {
      expect(weekdayFullLabel(0, zh), '');
      expect(weekdayFullLabel(8, zh), '');
      expect(weekdayFullLabel(-3, zh), '');
      expect(weekdayFullLabel(0, en), '');
      expect(weekdayFullLabel(99, en), '');
    });

    test('1..7 与 DateTime 常量对齐', () {
      expect(weekdayFullLabel(DateTime.monday, zh), '周一');
      expect(weekdayFullLabel(DateTime.sunday, zh), '周日');
      expect(weekdayFullLabel(DateTime.monday, en), 'Mon');
      expect(weekdayFullLabel(DateTime.sunday, en), 'Sun');
    });
  });

  // ───────────────────────── ④ 反向守卫 ─────────────────────────
  group('④ 反向守卫（domain 不得再持有桶标签）', () {
    test('PeriodBucket 没有 label 字段（源码级求证）', () {
      // 值层面拿不到「字段不存在」的证据，故读源码文本（**先剥注释**：
      // 类文档里正当地写着「`label` 字段已删除」「`第${n}周`」这些解释，不能误判）。
      final String src =
          _stripComments(_readSource('lib/domain/services/focus_report_service.dart'));
      final int classStart = src.indexOf('class PeriodBucket');
      expect(classStart, greaterThan(0), reason: 'PeriodBucket 类必须还在');
      final int classEnd = src.indexOf('\n}', classStart);
      expect(classEnd, greaterThan(classStart), reason: '类块必须能闭合');
      final String block = src.substring(classStart, classEnd);

      expect(
        RegExp(r'^\s*final\s+String\s+label\s*;', multiLine: true).hasMatch(block),
        isFalse,
        reason: '`PeriodBucket.label` 已被删除，不许加回（会重新引入 domain CJK 通道）',
      );
      expect(RegExp(r'String\s+get\s+label').hasMatch(block), isFalse,
          reason: '也不许以 getter 形式加回');
      expect(
        _cjk.hasMatch(block),
        isFalse,
        reason: 'PeriodBucket 代码里不得有任何 CJK（标签已全部迁 UI）',
      );
    });

    test('整份 focus_report_service.dart 注释外零 CJK', () {
      // 迁移前这里有 7 条周名 + `第N周` + `$m月` 三套中文，是本批的重点。
      final String code =
          _stripComments(_readSource('lib/domain/services/focus_report_service.dart'));
      final Iterable<RegExpMatch> hits = _cjk.allMatches(code);
      expect(
        hits,
        isEmpty,
        reason: '残留：${hits.map((RegExpMatch m) => m.group(0)).join(', ')}',
      );
      expect(code.contains('_kWeekdayLabels'), isFalse,
          reason: '`_kWeekdayLabels` 中文表必须留在 UI 侧');
    });

    test('消费端确实调用了 reportBucketLabel（接线不得回退）', () {
      final String ui = _readSource(
        'lib/presentation/parent/widgets/focus_report_section.dart',
      );
      expect(ui.contains('reportBucketLabel('), isTrue,
          reason: '趋势柱标签必须走 report_l10n，不许就地拼中文');
      expect(ui.contains('weekdayFullLabel('), isFalse,
          reason: '周名由 reportBucketLabel 内部取，UI 不必再直调');
    });
  });
}

/// CJK 正则（CJK 统一表意文字 + 扩展 A）。
final RegExp _cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]');

/// 读仓库内源码文本（`flutter test` 的 CWD 是仓库根）。
///
/// 用 `dart:io` 直读磁盘而非 `rootBundle`：源码守卫不该依赖 assets 打包。
String _readSource(String relativePath) => File(relativePath).readAsStringSync();

/// 剥掉 `//` 行注释与 `/* */` 块注释（**字符串字面量不特殊处理**）。
///
/// 对本文件的守卫足够：我们只问「代码里还有没有某个标识符 / CJK」，
/// 若某行字符串里恰好含 `//`，截断只会让断言更严（宁可误红，不可漏绿）。
String _stripComments(String src) {
  final List<String> out = <String>[];
  bool inBlock = false;
  for (final String raw in src.split('\n')) {
    String line = raw;
    if (inBlock) {
      final int end = line.indexOf('*/');
      if (end < 0) {
        out.add('');
        continue;
      }
      line = line.substring(end + 2);
      inBlock = false;
    }
    final int lineComment = line.indexOf('//');
    final int blockComment = line.indexOf('/*');
    if (lineComment >= 0 && (blockComment < 0 || lineComment < blockComment)) {
      line = line.substring(0, lineComment);
    } else if (blockComment >= 0) {
      final int end = line.indexOf('*/', blockComment + 2);
      if (end < 0) {
        inBlock = true;
        line = line.substring(0, blockComment);
      } else {
        line = line.substring(0, blockComment) + line.substring(end + 2);
      }
    }
    out.add(line);
  }
  return out.join('\n');
}
