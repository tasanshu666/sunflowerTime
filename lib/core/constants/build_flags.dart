/// 编译期构建开关（由 `--dart-define` 注入，单点收口）。
///
/// 🔴 纪律：本文件**全部开关默认 `false`** —— 不传 `--dart-define` 时，
/// 构建行为与正式上架包**逐字一致**。任何开关都不得改变默认构建。
library build_flags;

/// 强制解锁全部付费能力（**仅供内部验收包 / 自家测试设备**）。
///
/// 用途：给自家平板 / 手机出一个「装上即永久会员」的包，不必逐个进购买页，
/// 直接验收月报、年报、近 4 周稳定性、全年热力图、称号专属属性等付费区。
///
/// 构建方式：
/// ```bash
/// flutter build apk --release --dart-define=FORCE_UNLOCK_ALL=true
/// ```
///
/// ⚠️ 不传该 define 时值为 `false` → 正式包（App Store / 各安卓商店）**不受影响**；
/// ⚠️ 只在冷启动回填阶段生效，**不写任何持久化票据** —— 是否会员由
///    「这个包构建时带没带该 define」决定，而不是由机器上残留的票据决定；
/// ⚠️ 与设置页那个「模拟已解锁（仅调试）」开关**互不相干**：后者 `kDebugMode`
///    门控、只写内存态、重启即失效；本开关在 release 包里也能生效。
const bool kForceUnlockAll = bool.fromEnvironment('FORCE_UNLOCK_ALL');
