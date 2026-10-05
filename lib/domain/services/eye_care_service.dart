/// 少儿护眼休息判定 EyeCareService（口径 C28，玄参 2026-10-03 初稿 / 2026-10-04 收口）。
///
/// **纯 Dart、零 Flutter 依赖**（架构 §3 领域层纪律，可被 `dart test` 直接单测）。
/// 本服务只收口「什么时候该护眼 / 这一秒该说什么」，**不做任何 I/O**（不写库、不起
/// 定时器、不弹窗）——页面负责把判定接进计时 tick 与路由。
///
/// 全部数值 / 文案来自 `core/constants/prd_params.dart`，本文件**不出现裸字面量**。
///
/// 两条触发节奏（口径裁定表 v1 C28 §1）：
///  · **场内**：单场专注「累计注视」每满 `eyeCareIntervalMin` 分钟 → 触发一次护眼，
///    护眼期间**专注计时暂停**（页面调 `FocusEngine.pause()` / `resume()`），护眼
///    63 秒不计入专注时长、不产专注阳光；结束后从 0 重新累计下一个间隔；
///  · **场末**：单场结束时「距上次护眼之后的本段注视」≥ [kEyeCareSessionEndMinutes]
///    分钟 → 在**结算页之前**插入一次护眼卡（先护眼、后领奖励）；本段不足则不打断，
///    交给「每 2 场休 10 分钟」的大休息兜底。
///
/// 「累计注视」= 在场秒数（离席不累计），与 [FocusEngine.actualFocusMin] 同源；
/// 单位统一为**秒**（int），避免页面上出现「分钟 / 秒」两种口径打架。
///
/// 护眼**过程**（60→63 秒两段式占位 → 2026-10-05 素材定稿后为 5 段素材 7 槽位播放
/// 列表）由 `prd_params.dart` 的 `kEyeCarePlaylist` 单点定义、护眼卡页面执行——
/// 素材排布是 UI/资产口径，不进本服务。
library eye_care_service;

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/domain/entities/settings.dart';

/// 一次护眼的结果（完成 / 跳过）。
///
/// - `completed` → 写账本 +[kEyeCareRewardSunlight] 阳光（`refType='eye_care_break'`）；
/// - `skipped` → **不发奖励、不写账本**，且不回溯把护眼时长补算成专注时长。
enum EyeCareResultType {
  completed,
  skipped,
}

/// 护眼卡对外返回的结果（供专注页 / 结算页决定下一步）。
class EyeCareResult {
  final EyeCareResultType type;

  const EyeCareResult(this.type);

  /// 完整休息完（有奖励）。
  bool get completed => type == EyeCareResultType.completed;

  /// 被跳过（无奖励）。
  bool get skipped => type == EyeCareResultType.skipped;
}

/// 少儿护眼休息判定（纯函数集合，无状态、无副作用）。
class EyeCareService {
  const EyeCareService();

  /// 护眼提醒总开关是否打开（家长端 `eye_care_enabled`，默认开）。
  ///
  /// 关掉后场内 / 场末都不再插入护眼卡（C28 §4 第 ① 项）。
  static bool isEnabled(AppSettings settings) => settings.eyeCareEnabled;

  /// 是否**允许孩子跳过**护眼卡（家长端 `eye_care_skip_allowed`，默认允许）。
  ///
  /// 关掉后「跳过」按钮无效（点它只弹 [kEyeCareNotSkippableText]），流程不推进，
  /// 只留「完成休息」一条路（C28 §7）。
  static bool isSkipAllowed(AppSettings settings) =>
      settings.eyeCareSkipAllowed;

  /// 场内触发间隔（**秒**）：把设置的分钟数夹进 [kEyeCareIntervalMinMin,
  /// [kEyeCareIntervalMinMax] 合法区间后乘 60。
  ///
  /// 夹取而不是直接返回：家长端下拉档位与历史遗留值都可能越界，越界会让「每 0 分钟
  /// 触发一次」变成死循环弹卡（真机体验灾难），故在此单点收敛。
  static int intervalSeconds(AppSettings settings) {
    final int min = settings.eyeCareIntervalMin;
    final int clamped = min < kEyeCareIntervalMinMin
        ? kEyeCareIntervalMinMin
        : (min > kEyeCareIntervalMinMax ? kEyeCareIntervalMinMax : min);
    return clamped * 60;
  }

  /// 场内：距上次护眼之后的累计注视是否**又满了一个间隔** → 该触发护眼了。
  ///
  /// [focusElapsedSeconds] 为本场**累计注视秒数**（在场秒数，护眼期间由页面暂停计时，
  /// 因此天然不含护眼时长）；[lastEyeCareAtSecond] 为上次护眼触发时的累计注视秒数
  /// （从未护眼过传 null，视为 0）。
  ///
  /// [settings] 为 null 时按 [kEyeCareIntervalMinDefault] 兜底（未读到家长配置的默认
  /// 口径）；正常调用方（专注页）一律传真实设置，家长改间隔后当场生效。
  ///
  /// ⚠️ 幂等约定：本函数只回答「此刻是否已达阈值」，调用方在触发后**必须**把
  /// `lastEyeCareAtSecond` 回写为当前 [focusElapsedSeconds]（即「从 0 重新累计」），
  /// 否则下一秒仍然满足阈值、会连续弹卡。回写助手见 [baselineAfterTrigger]。
  static bool shouldTriggerInSession({
    required int focusElapsedSeconds,
    required int? lastEyeCareAtSecond,
    AppSettings? settings,
  }) {
    final int intervalSec = settings == null
        ? kEyeCareIntervalMinDefault * 60
        : intervalSeconds(settings);
    final int span = focusElapsedSeconds - (lastEyeCareAtSecond ?? 0);
    return span >= intervalSec;
  }

  /// 触发后应回写的「下次累计注视基准」（= 触发当下的累计注视秒数）。
  ///
  /// 单独抽出来的理由：调用方常常要在一行里同时「置基准 + 弹卡」，抽成命名函数
  /// 既能让单测直接断言这条幂等契约，也避免有人写成 `+1` 之类的错位。
  static int baselineAfterTrigger(int focusElapsedSeconds) =>
      focusElapsedSeconds;

  /// 场末：本段（距上次护眼之后的累计注视）是否 ≥ [kEyeCareSessionEndMinutes] 分钟
  /// → 应在**结算页之前**插入一次护眼卡。
  ///
  /// 与 [shouldTriggerInSession] 的区别：这里用固定门槛（10 分钟）而非家长配的间隔，
  /// 且判的是「本段」而不是「每满间隔」—— 场末只补一次，绝不因为超长专注连插多张。
  static bool shouldTriggerAtSessionEnd({
    required int focusElapsedSeconds,
    required int? lastEyeCareAtSecond,
  }) {
    final int span = focusElapsedSeconds - (lastEyeCareAtSecond ?? 0);
    return span >= kEyeCareSessionEndMinutes * 60;
  }

  /// 完整完成一次的护眼奖励阳光（= [kEyeCareRewardSunlight]）。
  static int rewardSunlight() => kEyeCareRewardSunlight;

  /// 护眼总时长（秒，固定 = [kEyeCareDurationSeconds]；家长端不设、不可调）。
  static int durationSeconds() => kEyeCareDurationSeconds;
}
