/// 专注报告「趋势桶」标签（i18n B3 · T04）。
///
/// ## 为什么存在
/// 迁移前 `PeriodBucket.label` 由 domain 的 `FocusReportService` 派生三套中文：
///  · 周档 `_kWeekdayLabels`（`周一`…`周日`）；
///  · 月档 `'第${n}周'`；
///  · 年档 `'$m月'`。
/// 领域层被迫持有 CJK，且英文环境下报告图整排中文。T04 把 `label` 字段整个删掉，
/// `PeriodBucket` 只留 `start / end / focusMinutes`（几何 + 数值），标签在 UI 侧
/// 由本文件按当前语言装配。
///
/// ## 口径（zh 逐字节保留现网）
///  · **周档** → `shared_weekday_mon…sun`（`周一`…`周日`），按 `bucket.start.weekday`
///    派生 —— 与原实现同源（原来也是 `_kWeekdayLabels[d.weekday - 1]`），
///    而不是靠下标巧合（防止未来切片起点变化时静默错位）；
///  · **月档** → `parent_report_bucket_week(index + 1)`（`第1周`…`第5周`，
///    index = 桶在列表中的下标，与原来 `monthBuckets.length + 1` 等价）；
///  · **年档** → `DateFormat(isEn ? 'MMM' : 'M月')`（zh = `1月`…`12月`，
///    en = `Jan`…`Dec`）。**模式**放 UI 侧、沿用 B2 的 `t.localeName == 'en'`
///    判别法（不引入 `intl` 的 locale 数据依赖）；
///  · **日档** → 空串（日档不画趋势桶，UI 用近 7 日序列）。
library report_l10n;

import 'package:intl/intl.dart';

import 'package:sunflower_time/domain/entities/report_period.dart';
import 'package:sunflower_time/domain/services/focus_report_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 周几 **full** 名（1 = 周一 … 7 = 周日，与 `DateTime.weekday` 同口径）。
///
/// 越界（`< 1` 或 `> 7`）返回空串而不抛 —— 报告页不许因为一个脏日期整块白屏。
String weekdayFullLabel(int weekday, AppLocalizations t) {
  switch (weekday) {
    case DateTime.monday:
      return t.shared_weekday_mon;
    case DateTime.tuesday:
      return t.shared_weekday_tue;
    case DateTime.wednesday:
      return t.shared_weekday_wed;
    case DateTime.thursday:
      return t.shared_weekday_thu;
    case DateTime.friday:
      return t.shared_weekday_fri;
    case DateTime.saturday:
      return t.shared_weekday_sat;
    case DateTime.sunday:
      return t.shared_weekday_sun;
    default:
      return '';
  }
}

/// 趋势桶标签（替代已删除的 `PeriodBucket.label`）。
///
/// [index] 是该桶在 `report.buckets` 里的**下标**（月档「第 N 周」用；
/// 其它档忽略）。[period] 必须是产出这批桶的那个周期。
String reportBucketLabel(
  ReportPeriod period,
  PeriodBucket bucket,
  int index,
  AppLocalizations t,
) {
  switch (period) {
    case ReportPeriod.day:
      // 日档没有趋势桶（`buildPeriodReport` 返回空列表），此处仅为穷举。
      return '';
    case ReportPeriod.week:
      return weekdayFullLabel(bucket.start.weekday, t);
    case ReportPeriod.month:
      return t.parent_report_bucket_week(index + 1);
    case ReportPeriod.year:
      final bool isEn = t.localeName == 'en';
      return DateFormat(isEn ? 'MMM' : 'M月').format(bucket.start);
  }
}
