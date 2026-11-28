/// App 内支付宝（Android 官网直供版）的编译期常量——**唯一的地址 / 超时 / 轮询口径**。
///
/// 设计纪律（增量架构设计 §2.1 / §5）：
///  - `ALIPAY_API_BASE_URL` 走 `String.fromEnvironment`，由 `--dart-define` 编译期覆盖；
///    生产默认 `https://api.sunfocused.top`，沙盒联调只换 base URL，**服务端 APP_ENV 独立控制**；
///  - 服务端路径逐字实读 `server/app/main.py`（不存在 `/v1/alipay/create`，禁止编造）；
///  - 轮询 7s > 服务端限流 60s/10 次 = 6s，留 1s 抖动余量；上限 12 次 ≈ 84s；
///  - 本文件纯 Dart 常量，零 Flutter / 零平台依赖，可被任何层 import。
library alipay_endpoints;

/// API 根地址（编译期可覆盖；末尾不带 `/`）。
const String kAlipayApiBaseUrl = String.fromEnvironment(
  'ALIPAY_API_BASE_URL',
  defaultValue: 'https://api.sunfocused.top',
);

/// 下单路径（`POST /v1/order/create`，main.py 实读）。
const String kAlipayCreateOrderPath = '/v1/order/create';

/// 领取 / 状态查询路径（`GET /v1/order/redeem`，main.py 实读）。
const String kAlipayRedeemPath = '/v1/order/redeem';

/// 单次 HTTP 请求的总超时（连接 / 读取统一上限；网络异常内部码 NETWORK_ERROR）。
const Duration kAlipayRequestTimeout = Duration(seconds: 15);

/// 轮询间隔（服务端 `claim_token` 60s ≤10 次 ⇒ 必须 ≥6s，取 7s 留余量）。
const Duration kAlipayPollInterval = Duration(seconds: 7);

/// 单次补单最多轮询次数（首次立即 + 11 次间隔 ≈ 78s，不超过 84s）。
const int kAlipayMaxPollCount = 12;

/// 订单默认有效期（秒），与服务端 `config.py` 的 `order_ttl_seconds=900` 对齐。
/// 仅用于本地 `PendingOrder.isExpired` 兜底；真实 TTL 以下单返回的 `expires_in` 为准。
const int kAlipayOrderTtlSeconds = 900;

/// 下单固定平台值（服务端只接受 `"android"`，非 android → 400 BAD_REQUEST）。
const String kAlipayPlatformAndroid = 'android';

/// 上报给服务端的 App 版本号。
///
/// ⚠️ 与 `pubspec.yaml` 的 `version: 1.1.0+2107` 保持一致；发版改 version 时同步此处
/// （项目未引入 package_info_plus，避免为一个风控字段新增插件）。
const String kAlipayAppVersion = '1.1.0+2107';

/// 设备哈希盐（与 SharedPreferences 持久 UUID 拼接后 sha256 取前 32 位；仅风控，不绑权益）。
const String kAlipayDeviceHashSalt = 'sunflowertime.alipay.device.v1';
