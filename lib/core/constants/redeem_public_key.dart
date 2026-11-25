/// 激活码验签公钥（**单点常量**，Android 官网直供版的唯一信任根）。
///
/// ## 这是什么
///
/// Ed25519 **公钥**的 Base64 串（原始 32 字节，标准 Base64、含 `=` 补位）。
/// App 只用它**验签**（`RedeemCodeVerifier`），私钥永不出现在 App 包里 ——
/// 私钥的保管与发码流程由发码工具 `tool/issue_redeem_code.dart` 在开发机完成。
///
/// ## 当前状态：生产公钥已配置（2026-11-25）
///
/// 私钥由负责人**离线保管**（密码管理器 + 离线备份），不在本仓库、不在 App 包内。
/// 公钥本身不是秘密（它随 APK 分发给所有人），故写入源码不构成泄漏 —— 真正需要
/// 保密的是私钥。
///
/// ## 为什么仍然使用 `String.fromEnvironment`
///
/// `defaultValue` 就是**生产公钥**，因此正式构建**无需传任何参数**即可得到正确的包；
/// 而测试包可用 `--dart-define` 临时覆盖成测试公钥，不必改源码，也就不会把测试密钥
/// 误发出去。
///
/// ```bash
/// # 正式包（不传参数 → 用 defaultValue 的生产公钥）
/// flutter build apk --release --split-per-abi
///
/// # 测试包（覆盖成测试公钥，仅真机验通路用）
/// flutter build apk --debug --dart-define=REDEEM_PUBLIC_KEY=<测试公钥>
/// ```
///
/// ## 🔴 出包纪律（两条，务必遵守）
///
/// 1. **正式包不得传 `--dart-define=REDEEM_PUBLIC_KEY`**。一旦误传测试公钥并发出去，
///    所有用生产私钥签发的激活码在用户机器上都验不过（App 只认包里那把公钥），
///    而用户已经付了钱。
/// 2. **首次发布前确认 `defaultValue` 就是最终生产公钥**。一旦发布过带某公钥的 APK，
///    换公钥 = 已发出的老码在新包上全部失效（老版本 App 又只认老公钥），
///    等于两代包都出问题。
///
/// 测试不走本常量：测试用固定测试密钥对，通过 `RedeemCodeVerifier(publicKeyBase64: ...)`
/// 构造参数注入，与本常量完全解耦。
library redeem_public_key;

/// Ed25519 公钥（Base64）。
///
/// 默认值 = **生产公钥**（2026-11-25 配置）；`--dart-define=REDEEM_PUBLIC_KEY=...`
/// 可在编译期覆盖（**仅用于测试包**）。
///
/// 若被显式覆盖为空串，验签一律返回 `notConfigured`（不误放、不崩）。
const String kRedeemPublicKeyBase64 = String.fromEnvironment(
  'REDEEM_PUBLIC_KEY',
  defaultValue: 'YdBRMQLrL8VB3w+pbl7yQfQ6xxsW/RfzaKvcz4gzR5k=',
);
