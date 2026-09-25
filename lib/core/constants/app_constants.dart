/// M0 参数单点（架构设计 §0 设计纪律：数值不孪生，集中定义 + 注释 PRD 节号）。
///
/// 说明：PRD 数值口径的最终真源是 `docs/口径裁定表_v1.md` 与 `docs/MVP执行规划_v2.md`。
/// 本文件承接 `prd_params.dart`（C3/C5 已落），补齐 M0 骨架所需的其余常量。
/// 任何页面/服务只引用此处，禁止字面量（§7 口径巡检清单）。
library app_constants;

// ── 专注节奏（PRD §4.1.5 / §4.1.6 / §6.2）────────────────────────────

/// 离席恢复线性回满时长（秒）：在场恢复 10 秒回满（§4.1.5）。
const int kResumeSeconds = 10;

/// 离席强判定阈值（秒）：L2 唤醒 90s / L3 唤醒 180s（§4.1.4）。
const int kL2ThresholdSeconds = 90;
const int kL3ThresholdSeconds = 180;

// ── 每日 / 应用上限（PRD §6.1 不变式 / §6.3）────────────────────────
/// 每日 App 使用时长上限（分钟）：30（§6.1）。
const int kDailyAppCapMinutes = 30;

/// 休息节奏：每专注 kRestAfter 个番茄后休息 kRestMin 分钟（§6.3）。
const int kRestAfterSessions = 2;
const int kRestMinutes = 10;

// ── 阳光经济（PRD §4.4 / §4.5 / §4.8 / C5）─────────────────────────
/// 单任务打卡阳光奖励（默认 12，区间 5–40，§4.4）。
const int kTaskSunlightReward = 12;

/// 完美日系数：同日同科「专注+打卡」×1.5（§4.5）。
const double kPerfectDayCoefficient = 1.5;

// 注：`currencyRate` 真源统一为 `AppSettings.currencyRate`（默认 0.25，§7.6），
// 此处不再另设裸值，杜绝双源（T-A 常量单点清理）。

// ── 夜间边界（PRD §6.1，Settings.nightBoundary 为唯一值）────────────
/// 夜间边界分钟（小时真源见 prd_params.kNightBoundaryDefaultHour，§6.1 不变式）。
const int kNightBoundaryMinute = 0;

// ── 打盹屏方向策略（PRD §4.1.6 退出路径）──────────────────────────
/// 进入打盹屏后的方向宽限期（秒）。
///
/// 传感器订阅在建立瞬间会立刻回调一次当前物理方向；孩子竖握手机点进打盹屏时
/// 首帧即 portrait，若不加宽限期会立刻误弹「确定结束吗？」（真机实测 B18）。
const int kOrientationGraceSeconds = 3;

/// 竖屏退出去抖时长（秒）：连续保持竖屏达该时长才判定为「中途退出意图」（B26），
/// 避免传感器极灵敏导致的轻微晃动即触发「确定结束吗？」确认框。
const double kPortraitExitDebounceSeconds = 1.5;

// ── M1 专注闭环（PRD §4.1.2 / §4.1.4 / §4.1.5）────────────────────
/// 打断时长（秒）：L3 唤醒（180s）后再持续 120s（累计 300s）→ 本次专注自然结束
/// （PRD §4.1.4 声量账表「打断」行）。
const int kInterruptSeconds = 120;

/// 唤醒语音每场上限（PRD §4.1.4 声量账：L2+L3 合计 ≤ 3 次/场）。
const int kWakeMaxPerSession = 3;

/// 唤醒「加重」每场上限（PRD §4.1.4 声量账：L3 单场至多 1 次）。
const int kWakeStrongMaxPerSession = 1;

/// 专注产出速率：1 阳光/分钟（PRD §4.1.5 / §4.5 产出表；产出侧不乘 K，§0）。
const double kSunlightPerFocusMinute = 1.0;

/// 随光报信触发占比（PRD §4.1.3 / §4.1.4：每完成 1/3 进度送一粒光，天然 2 次）。
const List<double> kReportBoundaryFractions = [1 / 3, 2 / 3];

/// 进入专注前可选时长档位（分钟）（PRD §4.1.2 进入前选时长；数值口径见用户裁定）。
const List<int> kFocusDurationOptions = [15, 20, 25, 30, 45];

/// 自定义时长的上限（分钟）：入口页「自定义」数字输入校验上界（PRD §4.1.2 自由时长）。
///
/// 约束取值上限，避免任意超大整数透传进 FocusPage；入口页自定义输入范围 [1, 本值]。
const int kFocusDurationMaxMinutes = 180;

/// 进入专注默认时长（分钟）（PRD §4.1.2「默认上次使用值」，首启默认 20）。
const int kFocusDurationDefaultMinutes = 20;

// ── 加密本地库（§10.4 C13）────────────────────────────────────────
/// 数据库文件名（SQLCipher 加密）。
const String kDatabaseFileName = 'sunfocus.sqlite';

/// 数据库加密口令。
///
/// ⚠️ 骨架阶段使用固定口令；生产应改为「设备级密钥派生 + flutter_secure_storage 保管」。
/// 见 `data/local/database/app_database.dart` 的 `openEncryptedDb()`。
const String kDatabasePassphrase = 'sunfocus-planb-dev-passphrase-2026';

// ── 合规 / 首启（G0 合规落地，T25）─────────────────────────────────
/// 首次启动同意流是否已完成的标记键（shared_preferences）。
const String kPrefFirstLaunchConsented = 'first_launch_consented';

/// 孩子端已读「家长核销成功」通知的申请 id 列表（shared_preferences）。
///
/// 家长核销后孩子端需要一次性弹窗提醒；已展示过的申请 id 记在此处，
/// 避免同一笔核销反复弹窗（M2 家长-孩子同步）。
const String kPrefAckedVerifyIds = 'acked_verify_ids';
const String kPrefAckedRejectIds = 'acked_reject_ids';

/// 家长 PIN 是否已在安全区落库的标记键（flutter_secure_storage）。
const String kSecurePinHash = 'parent_pin_hash';
const String kSecurePinSalt = 'parent_pin_salt';

// ── App 总时长防沉迷（P0 缺口 / §6.1；T01 单点收口）──────────────────

/// App 使用时长计时器 tick 间隔（秒）：外壳前台每 5 秒结算一次。
const int kAppUsageTickSeconds = 5;

/// **「哪些底部 tab 计入 App 总使用时长」的唯一开关（改这一行即可调整口径）**。
///
/// 集合内 = 计入计时（娱乐页）：花园(2) / 商店(3) / 我的(4)；
/// 不在集合内 = 不计入：今日(0) / 成长(1)（出发页与正向打卡，计入会与
/// 「成长页保持可用 / 学习时间不限」冲突）。
/// 玄参若要连「今日 / 成长」一起计，只改本行即可，无需动其它代码。
const Set<int> kAppUsageCountingTabs = <int>{2, 3, 4};

/// App 当日累计时长所属自然日的 SharedPreferences 键（yyyy-MM-dd）。
const String kPrefAppUsageDate = 'app_usage_date';

/// App 当日累计时长的 SharedPreferences 键（秒）。
const String kPrefAppUsageSeconds = 'app_usage_seconds';

/// 家长端「每日 App 使用时长」可选档位（分钟）。
///
/// 家长设置页下拉档位与本常量**唯一真源**（页面引用本常量，不再写裸字面量）。
const List<int> kDailyAppCapOptions = <int>[20, 30, 45];
