/// 领域异常 → 用户文案（i18n B3 · T03）：**唯一**的异常文案装配点。
///
/// ## 为什么存在
/// T03 把 `PlantOperationException`（17 码；A4 扩到 **19** 码）与
/// `TaskCheckInException`（9 码）从「中文串」改成「语义码 + 数值载荷」，于是「码 → 文案」的映射必须收敛到
/// 一处：散落回各 catch 点会让 26 条文案重新分裂，英文环境下又漏一半。
///
/// 🔴 兜底纪律：switch **必须穷举**（新增 code 时编译器报错）；末尾 `default`
/// 只为「运行期从旧序列化数据里读到未知枚举」这类不可能分支保命，返回
/// `code.name`（ASCII，不显示空白，便于定位）。
library error_l10n;

import 'package:sunflower_time/domain/services/plant_growth_service.dart';
import 'package:sunflower_time/domain/services/task_checkin_service.dart';
import 'package:sunflower_time/domain/services/weather_system.dart';
import 'package:sunflower_time/l10n/generated/app_localizations.dart';

/// 植物操作失败 → 面向孩子的提示语（**19** 个语义码全覆盖；A4 新增 2 码）。
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
    case PlantOperationError.waterRainstorm:
      // A4：暴雨日浇水额度为 0（雨水代劳）。异常路径与卡片常驻原因共用同一句
      // 孩子话术 —— 这两个码**只会**在「绕过 UI 直接调领域」时出现（正常路径已被
      // `careQuota` 拦在按钮层），文案一致才不会出现两套说法。
      return t.garden_care_water_disabled_rainstorm;
    case PlantOperationError.waterLightRain:
      // A4：小雨日额度 1 次且已用掉。
      return t.garden_care_water_disabled_light_rain;
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

/// 「不可养护」原因 → 卡片提示语。
///
/// `careQuota` 的阻塞原因是**数据**而非异常，故单独一个入口；不要让 UI 为此
/// 构造一个假异常（那会把「正常态」写成异常流）。
///
/// 🔴 **与 [plantErrorMessage] 的口径差异（A4 起）**：三个「额度类」原因走
/// `garden_care_*_disabled_*` 这组**孩子话术**（「今天已经浇够啦，明天再来～」），
/// 而异常路径仍保留 `shared_plant_err_*` 的账本口吻（「今日浇水已达 N 次上限」）。
/// 原因是两者受众不同：卡片上的是常驻说明，读它的是 5~9 岁的孩子；异常文案只在
/// 「绕过 UI 直接调领域」时出现，属于防御性日志/兜底，保留系统口径便于定位。
String plantBlockReasonMessage(PlantBlockReason reason, AppLocalizations t) {
  final int a = reason.a ?? 0;
  final int b = reason.b ?? 0;
  switch (reason.code) {
    case PlantOperationError.careStateInvalid:
      return t.shared_plant_err_care_state_invalid;
    case PlantOperationError.waterRainstorm:
      // A4：暴雨日额度 0 —— 卡片常驻原因就是这句（孩子先看到它，再看到灰按钮）。
      return t.garden_care_water_disabled_rainstorm;
    case PlantOperationError.waterLightRain:
      // A4：小雨日额度 1 次已用掉。
      return t.garden_care_water_disabled_light_rain;
    case PlantOperationError.waterDailyLimit:
      // A4：额度用尽改说**孩子话术**（不再是「已达 N 次上限」的账本口吻）。
      // 「上限次数」这种系统语言对 5~9 岁没有意义，方案 §6.2 要求常驻原因说人话；
      // 后端口径的旧文案仍保留在 [plantErrorMessage]（异常兜底路径）。
      return t.garden_care_water_disabled_quota;
    case PlantOperationError.waterInterval:
      return t.shared_plant_err_water_interval(a, b);
    case PlantOperationError.fertilizeDailyLimit:
      return t.garden_care_fertilize_disabled_quota;
    default:
      // 不可达：careQuota 只会产出上面 4 种码。保留兜底以防未来放宽。
      return reason.code.name;
  }
}

/// 一键浇水「无盆可浇」的原因 → 文案（A4 · §5.3-④ / §12.1-Q2）。
///
/// ## 为什么要抽成纯函数
/// 判定条件只有一句（`day.kind == rainstorm`），但它**藏在页面里就读不出**：
/// 花园页的时间源是 `DateTime.now()`，没有任何注入点，widget 测试碰不到暴雨日
/// （暴雨日只有 3 天/年）。抽出来后，9 种日型的映射可在零 widget、零时钟的纯单测
/// 里穷举，页面只负责把 `WeatherSystem.ofDay(now)` 递进来（天气仍只有那一个入口）。
///
/// ## 与卡片文案的关系（Q2 硬约束）
/// 暴雨日卡片上已有 `garden_care_water_disabled_rainstorm`（「雨水帮你浇好啦」），
/// 这里**故意换一句话说同一件事**（「雨已经把花浇过啦，今天不用一键浇水」）——
/// 同屏两处逐字重复会让孩子以为是同一个控件在报同一句错。两者文案不同源是本键
/// 存在的意义，**不要**为了「统一口径」把它们合并。
String batchNoneWaterMessage({
  required WeatherDay day,
  required AppLocalizations t,
}) =>
    day.kind == WeatherKind.rainstorm
        ? t.garden_batch_none_water_rainstorm
        : t.garden_batch_none_water;

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
