/// M0 参数单点（架构设计 §0 设计纪律：数值不孪生，集中定义 + 注释 PRD 节号）。
///
/// 说明：PRD 数值口径的最终真源是 `docs/口径裁定表_v1.md` 与 `docs/MVP执行规划_v2.md`。
/// 本文件承接 `prd_params.dart`（C3/C5 已落），补齐 M0 骨架所需的其余常量。
/// 任何页面/服务只引用此处，禁止字面量（§7 口径巡检清单）。
library app_constants;

// ── 专注节奏（PRD §4.1.5 / §4.1.6 / §6.2）────────────────────────────
/// 最短有效专注时长：< 5 分钟不计产出（§6.2）。
const int kMinFocusMinutes = 5;

/// 离席恢复线性回满时长（秒）：在场恢复 10 秒回满（§4.1.5）。
const int kResumeSeconds = 10;

/// 离席强判定阈值（秒）：L2 唤醒 90s / L3 唤醒 180s（§4.1.4）。
const int kL2ThresholdSeconds = 90;
const int kL3ThresholdSeconds = 180;

// ── 每日 / 应用上限（PRD §6.1 不变式 / §6.3）────────────────────────
/// 每日专注上限（分钟）：高年段 60 / 低年段 90（§6.1）。
const int kDailyFocusCapHigh = 60;
const int kDailyFocusCapLow = 90;

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

/// 月度池自动放行占月池比例：25%（C5）。
const double kAutoConfirmMonthlyPct = 0.25;

/// 货币换算系数（占位，§4.8）：K 仅作用于消耗侧，产出一律 1/min。
const double kCurrencyRate = 1.0;

// ── 夜间边界（PRD §6.1，Settings.nightBoundary 为唯一值）────────────
/// 夜间边界默认：21:00（§6.1 不变式；实际以 Settings 单例为准）。
const int kNightBoundaryHour = 21;
const int kNightBoundaryMinute = 0;

// ── 打盹屏方向策略（PRD §4.1.6 退出路径）──────────────────────────
/// 进入打盹屏后的方向宽限期（秒）。
///
/// 传感器订阅在建立瞬间会立刻回调一次当前物理方向；孩子竖握手机点进打盹屏时
/// 首帧即 portrait，若不加宽限期会立刻误弹「确定结束吗？」（真机实测 B18）。
const int kOrientationGraceSeconds = 3;

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

/// 家长 PIN 是否已在安全区落库的标记键（flutter_secure_storage）。
const String kSecurePinHash = 'parent_pin_hash';
const String kSecurePinSalt = 'parent_pin_salt';
