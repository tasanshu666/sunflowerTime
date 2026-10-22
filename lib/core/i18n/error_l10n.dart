/// 领域异常 → 用户文案（i18n B3 · T03）：**唯一**的异常文案装配点。
///
/// ## 为什么存在
/// T03 把 `PlantOperationException`（17 码）与 `TaskCheckInException`（9 码）
/// 从「中文串」改成「语义码 + 数值载荷」，于是「码 → 文案」的映射必须收敛到
/// 一处：散落回各 catch 点会让 26 条文案重新分裂，英文环境下又漏一半。
///
/// 🔴 兜底纪律：switch **必须穷举**（新增 code 时编译器报错）；末尾 `default`
/// 只为「运行期从旧序列化数据里读到未知枚举」这类不可能分支保命，返回
/// `code.name`（ASCII，不显示空白，便于定位）。
library error_l10n;

import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 植物操作失败 → 面向孩子的提示语（17 个语义码全覆盖）。
///
/// 载荷缺省按 0 处理（`a ?? 0`）—— 领域层只在该码需要载荷时填，缺了也不抛，
/// 避免「提示语构造本身把 App 打崩」。
String plantErrorMessage(PlantOperationException e, AppLocalizations t) {
  final int a = e.a ?? 0;
  final int b = e.b ?? 0;
  switch (e.code) {
    case PlantOperationError.speciesNotFound:
      return t.shared_plant_err_species_not_found;
    case PlantOperationError.potOutOfCapacity:
      return t.shared_plant_err_pot_out_of_capacity(a, b);
    case PlantOperationError.potOccupied:
      return t.shared_plant_err_pot_occupied(a);
    case PlantOperationError.premiumFragmentsOnly:
      return t.shared_plant_err_premium_fragments_only;
    case PlantOperationError.seedEmpty:
      return t.shared_plant_err_seed_empty;
    case PlantOperationError.sunlightNotEnough:
      return t.shared_plant_err_sunlight_not_enough(a);
    case PlantOperationError.fragmentsNotEnough:
      return t.shared_plant_err_fragments_not_enough(a);
    case PlantOperationError.careStateInvalid:
      return t.shared_plant_err_care_state_invalid;
    case PlantOperationError.waterDailyLimit:
      return t.shared_plant_err_water_daily_limit(a);
    case PlantOperationError.waterInterval:
      return t.shared_plant_err_water_interval(a, b);
    case PlantOperationError.fertilizeDailyLimit:
      return t.shared_plant_err_fertilize_daily_limit(a);
    case PlantOperationError.plantNotFound:
      return t.shared_plant_err_plant_not_found;
    case PlantOperationError.alreadyWilted:
      return t.shared_plant_err_already_wilted;
    case PlantOperationError.noWeed:
      return t.shared_plant_err_no_weed;
    case PlantOperationError.noPest:
      return t.shared_plant_err_no_pest;
    case PlantOperationError.gardenFull:
      return t.shared_plant_err_garden_full(a);
    case PlantOperationError.rewardNotMature:
      return t.shared_plant_err_reward_not_mature;
  }
}

/// 「不可养护」原因 → 卡片提示语（与 [plantErrorMessage] 同源，共用同一批 key）。
///
/// `careQuota` 的阻塞原因是**数据**而非异常，故单独一个入口；不要让 UI 为此
/// 构造一个假异常（那会把「正常态」写成异常流）。
String plantBlockReasonMessage(PlantBlockReason reason, AppLocalizations t) {
  final int a = reason.a ?? 0;
  final int b = reason.b ?? 0;
  switch (reason.code) {
    case PlantOperationError.careStateInvalid:
      return t.shared_plant_err_care_state_invalid;
    case PlantOperationError.waterDailyLimit:
      return t.shared_plant_err_water_daily_limit(a);
    case PlantOperationError.waterInterval:
      return t.shared_plant_err_water_interval(a, b);
    case PlantOperationError.fertilizeDailyLimit:
      return t.shared_plant_err_fertilize_daily_limit(a);
    default:
      // 不可达：careQuota 只会产出上面 4 种码。保留兜底以防未来放宽。
      return reason.code.name;
  }
}

/// 打卡失败 → 面向孩子 / 家长的提示语（9 个语义码全覆盖）。
String taskCheckInErrorMessage(TaskCheckInException e, AppLocalizations t) {
  switch (e.code) {
    case TaskCheckInError.linkedAuto:
      return t.shared_checkin_err_linked_auto;
    case TaskCheckInError.alreadyDone:
      return t.shared_checkin_err_already_done;
    case TaskCheckInError.notLinked:
      return t.shared_checkin_err_not_linked;
    case TaskCheckInError.sessionNotToday:
      return t.shared_checkin_err_session_not_today;
    case TaskCheckInError.sessionUsed:
      return t.shared_checkin_err_session_used;
    case TaskCheckInError.notFound:
      return t.shared_checkin_err_not_found;
    case TaskCheckInError.alreadyVerified:
      return t.shared_checkin_err_already_verified;
    case TaskCheckInError.alreadyRejected:
      return t.shared_checkin_err_already_rejected;
    case TaskCheckInError.race:
      return t.shared_checkin_err_race;
  }
}
