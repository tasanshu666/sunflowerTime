/// 埋点事件名单点（§3.3 / §7.5 单点纪律）。
///
/// 9 个事件的 name 字符串唯一真源；领域服务只引用本类的常量，禁止在业务代码里
/// 写裸字符串。payload 字段名与《验证计划 §3.2》**一字不改**（见 tracking_test.dart）。
library tracking_event_names;

class TrackingEventNames {
  /// 专注会话开始（focus_page.initState → engine.start() 后）。
  static const focusSessionStart = 'focus_session_start';

  /// 专注会话结束（focus_page._handleOutcome 起点）。
  static const focusSessionEnd = 'focus_session_end';

  /// 阳光到账（settle 后 / sunlight_service.settle 返回处）。
  static const sunEarned = 'sun_earned';

  /// 有效专注日判定（settle 后）。
  static const validFocusDay = 'valid_focus_day';

  /// 兑换申请落库（submit 后）。
  static const rewardRedeemRequest = 'reward_redeem_request';

  /// 家长核销成功（verify 成功后）。
  static const rewardVerified = 'reward_verified';

  /// 进入排队（submit 判为 queued 时）。
  static const rewardQueue = 'reward_queue';

  /// 家长拒绝核销（reject 成功后）：不扣阳光，仅记拒办。
  static const rewardRejected = 'reward_rejected';

  /// 周阳光池跨周重置（WeeklyPoolService.ensureAndReset 发生跨周）。
  static const weeklyPoolReset = 'weekly_pool_reset';

  /// 家长日活（parent_login_page PIN 校验通过）。
  static const parentDau = 'parent_dau';
}
