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

// ── 构建期开关（截图 / 演示包）──────────────────────────────────────
/// 隐藏所有调试 UI 的**构建期开关**：`--dart-define=HIDE_DEBUG_UI=true` 时为 true。
///
/// 用途：用 debug 包截商店图 / 宣传图时，避免「DEBUG 加1000阳光」这类按钮入镜
/// （玄参 2026-10-19 要求：iPad「我的」页与家长端「今日」页的调试入口不得出现在截图里）。
///
/// 与 `kDebugMode` 的关系：调试 UI 本来的守卫是 `kDebugMode`（release 包天然不渲染），
/// 本开关是**给 debug 包再做一次显式关闭**。当前三个调用点（我的页 / 家长今日页 /
/// 家长设置页）统一走 [shouldShowDebugUi]。默认 `false` = 保留现有调试能力，
/// 只有截图 / 演示构建才加 define；**不改变任何业务行为**。
const bool kHideDebugUi = bool.fromEnvironment('HIDE_DEBUG_UI');

/// 调试 UI 是否显示 —— **唯一判定入口**（禁止页面里各写一份 `kDebugMode && ...`）。
///
/// 规则：release（`kDebugMode == false`）恒不显示；debug 下由 [kHideDebugUi] 决定。
///
/// 为什么参数必传、不在此读 `kDebugMode`：本文件是**纯 Dart 常量文件**（零 flutter
/// 依赖），且两个开关都是编译期常量、测试无法在运行时改。把判据抽成纯函数后，
/// 调用点显式传入 `kDebugMode` / [kHideDebugUi]，测试即可直接验证**完整真值表**
/// （release 恒 false / debug 默认 true / debug+截图开关 false），而不是只靠源码
/// 字符串守卫「看起来写了」。
bool shouldShowDebugUi({
  required bool debugMode,
  required bool hideForScreenshots,
}) =>
    debugMode && !hideForScreenshots;

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

/// 随光报信触发占比（玄参 2026-10-08 修订：每完成 **1/2** 进度收集一次阳光，
/// 只在半程触发 1 次——原 PRD 1/3 两次过于频繁）。
const List<double> kReportBoundaryFractions = [1 / 2];

/// 竖屏退出意图的「回前台再同步宽限」（秒，B33）。
///
/// 场景：首次进专注跳系统设置页授权勿扰 → 返回 App。退后台期间传感器残留的
/// 竖屏值会让退出确认框在回前台后反复弹出（小米 14 实测）。回前台后的该宽限
/// 窗口内忽略一切方向事件，并重新探测当前物理方向清掉残留状态。
const int kResumeResyncGraceSeconds = 2;

/// 专注到时结束 → 护眼卡之前的**过渡缓冲**（秒，玄参 2026-10-08）：
/// 「20 分钟一到就直接进护眼太突兀」，先给文字提示过渡（仍横屏），再进入护眼动画。
/// 2026-10-08 晚修订：3s → **5s**（玄参拍板），配交付的 5 秒倒计时音效
/// （`5s_countdown.mp3`，4.99s，[AudioCue.focusEndCountdown]）。
const int kFocusEndBufferSeconds = 5;

/// 进入专注前可选时长档位（分钟）（PRD §4.1.2 进入前选时长；数值口径见用户裁定）。
/// 玄参 2026-09-30 拍板：固定三排展示 15-20-25 / 30-45-60，另有「自由」与「自定义」档。
const List<int> kFocusDurationOptions = [15, 20, 25, 30, 45, 60];

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
///
/// 🔴 **v1 遗留键**：首启告知 2.0（口径 C110）起同意状态改由
/// [kPrefConsentPolicyVersion] 承载（带版本三要素）；本键只用于**旧版本迁移**
/// （true = 曾同意过 v1 政策 → 迁移口径见 `SettingsStore.consentedPolicyVersion`），
/// 新代码禁止再读写。
const String kPrefFirstLaunchConsented = 'first_launch_consented';

/// 已同意的隐私政策版本号键（shared_preferences；首启告知 2.0 / C110）。
/// 缺失 = 从未同意过（v1 旧键迁移除外，见 [kPrefFirstLaunchConsented]）。
const String kPrefConsentPolicyVersion = 'consent_policy_version';

/// 同意时刻键（shared_preferences，epoch 毫秒；政策版本三要素之一，仅审计用）。
const String kPrefConsentAcceptedAtMs = 'consent_accepted_at_ms';

/// 当前隐私政策版本号（对应底稿 `docs/隐私政策_向日葵专注_v1.md` 头部三要素）。
///
/// 🔴 **重大变更时 +1**，并在底稿头部更新版本/生效日期/更新记录三要素 ——
/// 路由守卫据此对老用户**重弹一次同意页**（§10.3 应用内重新确认机制）。
/// 历史：v1 = 旧布尔键时代；v2 = 2026-10-23 首启告知 2.0（不同意选项/条款入口/
/// 数据清单/重弹机制）。
const int kPrivacyPolicyVersion = 2;

/// 孩子端已读「家长核销成功」通知的申请 id 列表键 —— C90 期 2 第二批起**按孩子分键**
///（玄参拍板）：`acked_verify_ids_read_$childId`。历史全局键 `acked_verify_ids`
/// **不迁移**（切孩子后旧通知可能重弹一次，属拍板可接受范围）。
/// 🔴 键名生成走本 helper 单点，禁止散写字面量。
String ackedVerifyIdsKey(String childId) => 'acked_verify_ids_read_$childId';

/// 孩子端已读「家长拒绝」通知键（B4 对称通知去重；按孩子分键口径同上）。
String ackedRejectIdsKey(String childId) => 'acked_reject_ids_read_$childId';

/// 孩子端已读「家长审批成长任务」通知的**打卡 id**列表键（F126 补缺口；按孩子
/// 分键口径同上）。
///
/// 为什么单开一个键而不复用 [ackedVerifyIdsKey]：两个键装的是**不同实体**的主键
/// （兑换申请 id vs 打卡 id），且两套通知独立去重 —— 混用会让「已读兑换」把同
/// uuid 空间的打卡误判成已读（也可能相反）。
/// 🔴 键名生成走本 helper 单点，禁止散写字面量。
String ackedTaskCheckInIdsKey(String childId) =>
    'acked_task_checkin_ids_read_$childId';

/// 孩子端已读「家长赠予到账」通知键（F150；存**最近一条已读账本记录的 id**）。
///
/// 为什么是单值 id 而非列表：赠予通知只弹**最新一条**（余额对得上即可，历史
/// 累计金额在「我的-阳光来源」可查），拿最新记录 id 与本键比对即知有无未读。
/// 按孩子分键口径同上（阳光账本按 childId 隔离，跨孩子绝不互串）。
/// 🔴 键名生成走本 helper 单点，禁止散写字面量。
String ackedParentGiftIdKey(String childId) =>
    'acked_parent_gift_id_read_$childId';

/// 花园「孩子上次**看到**的植物阶段」快照键（按孩子分键口径同上）。
///
/// 值 = JSON 编码的 `{plantId: 'stage:status'}`。用途：孩子离开花园期间植物升级
/// （专注结算 / 隔天成长）后，回到花园时补播一次成长过渡演出 —— 纯内存快照活不过
/// 「外壳重建」（专注结束 `context.go('/')` 会重建整个 `ChildShellPage`），必须持久化。
/// 🔴 键名生成走本 helper 单点，禁止散写字面量。
String lastSeenPlantPhasesKey(String childId) => 'last_seen_plant_phases_$childId';

/// 「家长审批任务」确认卡的**展示时间窗**（F126）。
///
/// 为什么必须加窗：`verified` 状态里躺着**全部历史**打卡（老库升级默认即
/// verified），不限窗首次上线会一次弹几十条。只认「最近 24 小时内被处理」的，
/// 语义 = 「今天家长刚确认的那些」，与孩子的记忆对齐。
const Duration kTaskVerifiedNoticeWindow = Duration(hours: 24);

/// 「家长审批任务」确认卡单次最多列出的条目数（F126）。
///
/// 打卡量远大于兑换申请（一天可能十几条）→ 卡片超过 3 条会撑满屏幕且孩子根本
/// 读不进去；超出的条目仍留在未读快照外，下一次进入再逐批补弹（不丢通知）。
const int kTaskVerifiedNoticeMaxItems = 3;

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

// ── C74 · 专注等级（§5.24）────────────────────────────────────────────────

/// 「**已结算到的最高等级**」的 SharedPreferences 键（`int`，1..8）。
///
/// ⚠️ 语义不是「首用基线」而是「已结算到的最高等级」（**只增不减**），因为它同时
/// 承担两个职责：① 老用户首用**不补发**历史等级阳光；② 升级结算的**幂等锚点之一**
/// （另一锚点是阳光账本，二者取大，设计 §5.24.3）。
/// 与 C14 防沉迷（`kPrefAppUsageDate`）同款先例：**不升 schemaVersion**（仍 24）。
const String kPrefFocusLevelSettled = 'focus_level_settled';

// ── 单次使用限时（F99，玄参 2026-10-08）──────────────────────────────

/// **单次连续使用上限（分钟）**：娱乐 tab 连续前台满 N 分钟 → 锁定娱乐 tab。
///
/// 玄参 2026-10-08：「当前只有一个 30 分钟的使用时长，怕孩子单次使用太久，
/// 加一个 10 分钟的单次使用限时」。单次秒数只在锁定触发时归零（离开 tab /
/// 切后台**不**重置——否则切一下 tab 就能绕过），每日总时长仍 [kDailyAppCapMinutes]。
const int kSingleUseLimitMinutes = 10;

/// 单次触发锁定后的**解锁等待（分钟）**：锁满 N 分钟自动解锁，可继续玩
/// （消耗每日总时长）。
const int kSingleUseLockMinutes = 10;

/// 单次锁定解锁时刻的 SharedPreferences 键（epoch ms；null/过期 = 未锁定）。
///
/// 持久化的意义：杀 App 重启**绕不过**进行中的锁定（每日总量本身另有持久化兜底）。
const String kPrefAppUsageLockedUntilMs = 'app_usage_locked_until_ms';

/// 调试期「跳过 30 分钟防沉迷限时」的 SharedPreferences 键（仅 [kDebugMode] 生效）。
///
/// 玄参 2026-09-29：调试期间默认**打开**（true = 绕过限时，不进拦截状态）；
/// 家长端首页有临时开关可关掉恢复拦截。release 构建不读该键（照常防沉迷）。
const String kPrefDebugCapBypass = 'debug_cap_bypass';

/// 昵称/展示名默认回落值（孩子端「我的」页档案读取失败时的兜底展示；
/// 家长端 ChildProfileBar 无当前档案时同款回落）。
///
/// 历史：曾是「孩子端昵称 SP 键 `child_nickname`」的默认值（T4）；C90 期 2 第二批
/// 起昵称跟孩子档案走（家长天地维护），`kPrefChildNickname` 键已删除、孩子端停止
/// 读取（旧键留存但不迁移，玄参拍板）。
const String kDefaultChildNickname = '小朋友';

/// 家长端新建 / 编辑孩子时的名字最大字符数（玄参拍板 ≤12）。
const int kChildNicknameMaxLength = 12;

/// 当前活跃孩子档案 id 的 SharedPreferences 键（C90 期 1，玄参 2026-10-17 拍板）。
///
/// 键缺失 / 指向不存在的孩子 → `AccountService.initialize()` 回退第一个孩子
///（🔴 绝不因此删档案，C69）。
const String kPrefActiveChildId = 'active_child_id';

/// 家长端「每日 App 使用时长」可选档位（分钟）。
///
/// 家长设置页下拉档位与本常量**唯一真源**（页面引用本常量，不再写裸字面量）。
const List<int> kDailyAppCapOptions = <int>[20, 30, 45];

// ── i18n（B1 批次）────────────────────────────────────────────────────────

/// 界面语言选择的 SharedPreferences 键（i18n B1，架构设计定稿）。
///
/// 值 = `AppLanguage` 枚举的存档 key（'system' / 'zh' / 'en'，转换单点见
/// `core/i18n/app_language.dart`）。键缺失 / 脏值 → 回 `AppLanguage.system`。
///
/// ⚠️ 刻意走 SP 而不进 `AppSettings`/Drift：零 schema 迁移（同 C14 防沉迷
/// `kPrefAppUsageDate` 先例）。
const String kPrefAppLanguage = 'app_language';
