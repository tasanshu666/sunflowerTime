/// 激活码（Redeem Code）离线验签——**纯 Dart，零 Flutter / 插件依赖**。
///
/// ## 为什么需要它（背景）
///
/// iOS 1.0.0 的解锁方式是非消耗型 IAP（StoreKit 完成支付 → 票据落库）。Android 版
/// **不上任何应用商店**（国内买断制无法在国产应用商店上架），改为**官网直供 APK**：
/// 用户在官网付款 → 拿到一枚「激活码」→ 在 App 内输入 → **本地离线验签** → 解锁
/// premium。整条链路无后端、无账号、无网络请求，与项目「离线优先 / 无服务器」的
/// 既有铁律一致。
///
/// ## 二进制格式（共 69 字节，单点定义在本文件，发码工具与 App 共用同一份常量）
///
/// ```
/// [0]      version   = 0x01
/// [1..4]   serial    = uint32 大端序（签发序号，用于对账 / 防重 / 客服排查）
/// [5..68]  signature = Ed25519 对「前 5 字节」的签名（64 字节）
/// ```
///
/// 整体再做 **Base64URL（无 padding）** 编码 → 92 字符（69 字节 = 3 × 23，故编码后
/// **天然没有 `=` 补位**；编码时仍显式去掉 `=`，防将来改长度时静默变成 93 字符）。
///
/// 🔴 **签名只签「version + serial」这 5 字节**，不含签名自身（显然）。故任何对
/// version / serial 的改动都会让签名失配 —— 攻击者无法把 1 号码改成 999 号码。
///
/// ## ⚠️ 一个必须记住的坑：`-` 是 Base64URL 的**数据字符**
///
/// 设计初稿写的是「清理输入时去掉空白与 `-`，发码时每 23 字符插一个 `-` 分组」。
/// 这两条**互相冲突**：Base64URL 的字母表是 `A-Z a-z 0-9 - _`，`-` 是值 62 的合法
/// 数据字符（相当于标准 Base64 的 `+`）。92 个字符平均带约 1.4 个 `-`，但「至少含
/// 一个 `-`」的概率是 **76.4%**（实测 200 枚命中 144 枚 = 72.0%，因随机的 version/serial
/// 前缀并非均匀分布）。把它们当分组符剥掉会让**约七成半合法码**解码不完整 →
/// 判 malformed → 已付费用户永远激活不了。
///
/// 故本文件的口径（与初稿的唯一偏离，已在评审中说明）：
///  · 分组显示用**空格**（[formatRedeemCodeForDisplay]），空格一定不是数据字符；
///  · [normalizeRedeemCode] **只剥空白，保留 `-`**；
///  · 另外用 [redeemCodeCandidates] 提供「再剥一次 `-`」的**备选形态**，兜底
///    「用户自己插了连字符」的场景 —— 两个候选都必须通过验签，安全性不变。
///
/// ## 失败安全（本项目的红线）
///
/// [RedeemCodeVerifier.verify] **绝不抛异常**：格式错、编码错、签名错、算法实现里
/// 任何意外异常，一律收敛为 [RedeemCodeInvalid]（附 [RedeemCodeError] 原因）。
/// 调用方（域服务 / UI）因此永远不需要 try/catch 包住「用户随手粘贴一段乱码」这种
/// 日常操作 —— 一个错码绝不可能导致 App 崩溃。
///
/// ## 分层纪律
///
/// - 本文件位于 `lib/domain/`，**不得 import flutter**（只用 `dart:convert` /
///   `dart:typed_data` 与纯 Dart 包 `cryptography`），可被 `package:test` 直接单测；
/// - 依赖的 Ed25519 实现在 `cryptography` 包内是**纯 Dart**（`DartEd25519`），
///   故本类在 `flutter test` / `dart test` 下都能跑，无需任何平台通道；
/// - **签名动作**（需要私钥）不在 App 里发生：只有开发机上的
///   `tool/issue_redeem_code.dart` 会签，App 包里**只有公钥**。
library redeem_code;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 当前支持的激活码版本号（唯一受支持的版本）。
const int kRedeemCodeVersion = 0x01;

/// version 字节的偏移。
const int kRedeemCodeVersionOffset = 0;

/// serial（uint32 大端）起始偏移。
const int kRedeemCodeSerialOffset = 1;

/// serial 字节数。
const int kRedeemCodeSerialLength = 4;

/// 签名起始偏移。
const int kRedeemCodeSignatureOffset = 5;

/// Ed25519 签名长度（固定 64 字节）。
const int kRedeemCodeSignatureLength = 64;

/// 被签名载荷长度（version 1 字节 + serial 4 字节 = 5 字节）。
const int kRedeemCodePayloadLength =
    kRedeemCodeVersionOffset + 1 + kRedeemCodeSerialLength;

/// 激活码二进制总长度（5 + 64 = 69 字节）。
const int kRedeemCodeBinaryLength =
    kRedeemCodeSignatureOffset + kRedeemCodeSignatureLength;

/// Base64URL 编码后的字符数（69 字节 → 92 字符，无 padding）。
///
/// 计算口径：`(69 * 8 + 5) ~/ 6 = 92`；69 % 3 == 0 故不需要 `=` 补位。
const int kRedeemCodeEncodedLength = 92;

/// 激活码校验失败的原因（[RedeemCodeInvalid.error]）。
///
/// 刻意区分四类，因为 UI 的提示语必须不同：
///  · [malformed] → 「请完整复制激活码」（用户操作问题，可自助修复）；
///  · [badSignature] / [unsupportedVersion] → 「激活码无效」（码本身不对）；
///  · [notConfigured] → 客户端公钥未配置（**发布事故**，应提示联系客服，
///    绝不能含糊地说「激活码无效」，否则会冤枉已付费用户）。
enum RedeemCodeError {
  /// 格式 / 编码错误：长度不对、非 Base64URL、解码后长度不对。
  malformed,

  /// 签名不匹配（码被篡改、或不是本 App 的公钥签出的）。
  badSignature,

  /// 版本号不受支持（未来格式，或码不是本 App 的）。
  unsupportedVersion,

  /// 客户端未配置公钥（[kRedeemPublicKeyBase64] 为空 / 非法）。
  notConfigured,
}

/// 验签结果（**成功 / 失败二态**，失败再分原因）。
///
/// 用 `sealed class` 而非「bool + 出参」：调用方的 `switch` 由编译器保证穷尽，
/// 将来加一种失败原因时所有调用点编译期报红，不会漏处理。
sealed class RedeemCodeResult {
  const RedeemCodeResult();
}

/// 验签通过：激活码真实有效。
final class RedeemCodeValid extends RedeemCodeResult {
  /// 签发序号（uint32，无符号；用于售后对账 / 排查「这枚码什么时候发的」）。
  final int serial;

  const RedeemCodeValid(this.serial);

  @override
  String toString() => 'RedeemCodeValid(serial: $serial)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RedeemCodeValid && other.serial == serial;

  @override
  int get hashCode => serial.hashCode;
}

/// 验签失败（附带原因）。
final class RedeemCodeInvalid extends RedeemCodeResult {
  /// 失败原因。
  final RedeemCodeError error;

  const RedeemCodeInvalid(this.error);

  @override
  String toString() => 'RedeemCodeInvalid($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RedeemCodeInvalid && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// 输入清理时必须忽略的字符：**所有空白**（含全角空格 / NBSP / BOM / 换行）。
///
/// 用户从聊天软件 / 邮件里复制时，码的前后与中间常混进空白；这些一律先剥掉。
///
/// 🔴 **绝不改变大小写**：Base64URL 是大小写敏感的（`a` 与 `A` 是不同的 6 bit），
/// 任何 `toLowerCase()` / `toUpperCase()` 都会把有效码变成废码。
///
/// 🔴🔴 **绝不剥 `-`**（这是与最初设计稿的唯一偏离，理由必须记住）：
/// **`-` 是 Base64URL 字母表里的合法数据字符**（值 62，与标准 Base64 的 `+` 同位）。
/// 92 个字符里平均会出现约 1.4 个 `-`，若像处理分组符那样把它剥掉，
/// 大约三成**合法码**会被解码成长度不足 69 字节 → 直接判 malformed，
/// 用户已经付了钱却永远激活不了（而且是静默的、极难排查的）。
/// 因此：**分组显示改用空格**（空格一定不是数据字符，见 [formatRedeemCodeForDisplay]），
/// 而「用户自己插了连字符」的场景由 [redeemCodeCandidates] 的备选形态兜底。
final RegExp _kWhitespace = RegExp(r'\s');

/// 清理用户输入：去掉所有空白（**保持大小写、保留 `-`**）。
///
/// 抽成公开函数以便 UI / 测试复用同一份口径（避免「页面里再写一遍正则」）。
String normalizeRedeemCode(String code) => code.replaceAll(_kWhitespace, '');

/// 验签时按优先级尝试的**候选清理形态**（去重、保序）。
///
/// 1. **第一候选**：只剥空白 —— 正确处理「码里本来就带 `-` 数据字符」的多数情况；
/// 2. **第二候选**：再额外剥掉 `-` —— 兜底「用户手工在码里插了连字符 / 从旧版分组
///    文案里连字符复制过来」的场景。
///
/// 安全性：多试一种形态**不会**降低强度 —— 两个候选都必须通过 Ed25519 验签才算数；
/// 且 `-` 的数量无法伪造出另一个合法签名。故这只是「输入容错」，不是「放宽校验」。
List<String> redeemCodeCandidates(String code) {
  final String stripped = normalizeRedeemCode(code);
  final List<String> candidates = <String>[stripped];
  final String withoutDash = stripped.replaceAll('-', '');
  if (withoutDash != stripped) candidates.add(withoutDash);
  return candidates;
}

/// 构建待签名载荷（`version` + `serial` 大端 uint32），共 5 字节。
///
/// 发码工具与测试用；App 运行期不调用（只验签，不签）。
///
/// [version] 仅测试需要造「未来版本码」时才传非 1；[serial] 必须落在
/// `[0, 0xFFFFFFFF]`，否则抛 [ArgumentError]（这是**开发期**错误，
/// 不是用户输入，故允许抛）。
Uint8List buildRedeemCodePayload({required int serial, int version = kRedeemCodeVersion}) {
  if (serial < 0 || serial > 0xFFFFFFFF) {
    throw ArgumentError.value(serial, 'serial', 'must be a uint32');
  }
  if (version < 0 || version > 0xFF) {
    throw ArgumentError.value(version, 'version', 'must be a single byte');
  }
  final Uint8List out = Uint8List(kRedeemCodePayloadLength);
  out[kRedeemCodeVersionOffset] = version;
  ByteData.sublistView(out, kRedeemCodeSerialOffset, kRedeemCodeSignatureOffset)
      .setUint32(0, serial, Endian.big);
  return out;
}

/// 把「载荷 + 签名」拼成 69 字节二进制（**格式单点**，发码工具与测试用）。
///
/// 长度不符时抛 [ArgumentError]（同样是开发期错误，不是用户输入路径）。
Uint8List assembleRedeemCode({
  required List<int> payload,
  required List<int> signatureBytes,
}) {
  if (payload.length != kRedeemCodePayloadLength) {
    throw ArgumentError.value(
        payload.length, 'payload', 'must be $kRedeemCodePayloadLength bytes');
  }
  if (signatureBytes.length != kRedeemCodeSignatureLength) {
    throw ArgumentError.value(signatureBytes.length, 'signatureBytes',
        'must be $kRedeemCodeSignatureLength bytes');
  }
  final Uint8List out = Uint8List(kRedeemCodeBinaryLength);
  out.setRange(0, kRedeemCodePayloadLength, payload);
  out.setRange(kRedeemCodeSignatureOffset, kRedeemCodeBinaryLength, signatureBytes);
  return out;
}

/// 把 69 字节二进制编码为 92 字符的 Base64URL 激活码（**无 padding**）。
String encodeRedeemCode(List<int> binary) {
  if (binary.length != kRedeemCodeBinaryLength) {
    throw ArgumentError.value(
        binary.length, 'binary', 'must be $kRedeemCodeBinaryLength bytes');
  }
  return base64Url.encode(binary).replaceAll('=', '');
}

/// 把 92 字符的激活码格式化为「每 23 字符一个空格」的易读分组（**仅展示用**）。
///
/// 🔴 分隔符**必须是空格**，不能用 `-`：`-` 是 Base64URL 的合法数据字符
/// （见 [_kWhitespace] 的说明），用 `-` 分组会让「复制分组文本 → 粘贴」这条路径
/// 无法区分「分组符」与「数据」，从而毁掉约三成合法码。
/// 空格则由 [normalizeRedeemCode] 无条件剥掉，语义清晰无歧义。
String formatRedeemCodeForDisplay(String code) {
  final String cleaned = normalizeRedeemCode(code);
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < cleaned.length; i++) {
    if (i > 0 && i % 23 == 0) buffer.write(' ');
    buffer.write(cleaned[i]);
  }
  return buffer.toString();
}

/// 失败原因的「信息量」排序：数字越大，越能说明码本身的问题（越应优先展示）。
///
/// 多个候选形态都失败时，取信息量最大的那条——避免「码被改过」被降级成
/// 「格式不对」，让用户白折腾一遍复制。
int _errorPriority(RedeemCodeError error) => switch (error) {
      RedeemCodeError.malformed => 1,
      RedeemCodeError.unsupportedVersion => 2,
      RedeemCodeError.badSignature => 3,
      RedeemCodeError.notConfigured => 4,
    };

/// 激活码离线验签器（**App 包里唯一的验签入口**）。
///
/// 构造只接受**公钥**（Base64；Ed25519 原始 32 字节）。私钥永不出现在 App 内。
///
/// 用法：
/// ```dart
/// final RedeemCodeVerifier verifier =
///     RedeemCodeVerifier(publicKeyBase64: kRedeemPublicKeyBase64);
/// final RedeemCodeResult r = await verifier.verify(userInput);
/// ```
///
/// 公钥为空串（未配置）或非法 → [verify] 一律返回
/// [RedeemCodeError.notConfigured]（**不抛**，也不慌张地报「码无效」）。
class RedeemCodeVerifier {
  /// 构造：只注入 Base64 公钥串（可为空串 = 未配置）。
  RedeemCodeVerifier({required String publicKeyBase64})
      : _publicKeyBase64 = publicKeyBase64;

  /// 原始配置串（保留原样，便于排查「到底配了个啥」）。
  final String _publicKeyBase64;

  /// 纯 Dart Ed25519（`cryptography` 包在 Dart VM / 移动端默认走该实现，无平台通道）。
  final Ed25519 _algorithm = Ed25519();

  /// 惰性解析出的公钥（null = 未配置 / 非法）。
  SimplePublicKey? _cachedPublicKey;

  /// 是否已尝试解析过公钥（解析只做一次，之后走缓存）。
  bool _publicKeyResolved = false;

  /// 验签：**绝不抛异常**（失败只以 [RedeemCodeInvalid] 返回）。
  ///
  /// 对 [redeemCodeCandidates] 的每个候选形态依次尝试（最多两种，见该函数的说明），
  /// 每个候选走同一套流程：
  ///  1. 长度 ≠ [kRedeemCodeEncodedLength] → [RedeemCodeError.malformed]；
  ///  2. Base64URL 解码失败 / 解码后字节数 ≠ [kRedeemCodeBinaryLength]
  ///     → [RedeemCodeError.malformed]；
  ///  3. 版本号 ≠ [kRedeemCodeVersion] → [RedeemCodeError.unsupportedVersion]；
  ///  4. Ed25519 验签失败 → [RedeemCodeError.badSignature]；
  ///  5. 通过 → [RedeemCodeValid]（带 serial）。
  ///
  /// 🔴 格式不对时**不进入验签**：既省算力，也避免把「格式异常」伪装成「签名不对」
  /// （两者的用户提示语不同，混在一起会误导客服排查）。
  ///
  /// 全部候选都失败时，返回**信息量最大**的那条原因（见 [_errorPriority]）。
  Future<RedeemCodeResult> verify(String code) async {
    try {
      final SimplePublicKey? publicKey = _publicKey();
      if (publicKey == null) {
        return const RedeemCodeInvalid(RedeemCodeError.notConfigured);
      }

      RedeemCodeError? worst;
      for (final String candidate in redeemCodeCandidates(code)) {
        final RedeemCodeResult result = await _verifyCandidate(candidate, publicKey);
        if (result is RedeemCodeValid) return result;
        final RedeemCodeError error = (result as RedeemCodeInvalid).error;
        if (worst == null || _errorPriority(error) > _errorPriority(worst)) {
          worst = error;
        }
      }
      return RedeemCodeInvalid(worst ?? RedeemCodeError.malformed);
    } catch (_) {
      // 失败安全红线：任何意外（含密码学实现的边界异常）都收敛为格式错误，
      // 绝不把异常抛给 UI —— 用户粘贴一段乱码不该让 App 崩。
      return const RedeemCodeInvalid(RedeemCodeError.malformed);
    }
  }

  /// 对**单个**已清理候选串做「解码 + 版本 + 验签」（[verify] 的内部一步）。
  Future<RedeemCodeResult> _verifyCandidate(
    String candidate,
    SimplePublicKey publicKey,
  ) async {
    if (candidate.length != kRedeemCodeEncodedLength) {
      return const RedeemCodeInvalid(RedeemCodeError.malformed);
    }

    final Uint8List binary;
    try {
      // `base64Url.normalize` 只补 `=` 补位、不改大小写（长度 92 本就不需要补位）。
      binary = base64Url.decode(base64Url.normalize(candidate));
    } catch (_) {
      return const RedeemCodeInvalid(RedeemCodeError.malformed);
    }
    if (binary.length != kRedeemCodeBinaryLength) {
      return const RedeemCodeInvalid(RedeemCodeError.malformed);
    }

    if (binary[kRedeemCodeVersionOffset] != kRedeemCodeVersion) {
      return const RedeemCodeInvalid(RedeemCodeError.unsupportedVersion);
    }

    final List<int> payload = binary.sublist(0, kRedeemCodePayloadLength);
    final List<int> signatureBytes =
        binary.sublist(kRedeemCodeSignatureOffset, kRedeemCodeBinaryLength);

    final bool ok = await _algorithm.verify(
      payload,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    if (!ok) {
      return const RedeemCodeInvalid(RedeemCodeError.badSignature);
    }

    final int serial = ByteData.sublistView(
      binary,
      kRedeemCodeSerialOffset,
      kRedeemCodeSignatureOffset,
    ).getUint32(0, Endian.big);
    return RedeemCodeValid(serial);
  }

  /// 解析并缓存公钥；未配置 / 非法 → null（对应 [RedeemCodeError.notConfigured]）。
  ///
  /// 公钥是标准 Base64（可能带 `+` `/` 与 `=` 补位），与激活码自身的 Base64URL
  /// 编码不同 —— 两者不要混用。
  SimplePublicKey? _publicKey() {
    if (_publicKeyResolved) return _cachedPublicKey;
    _publicKeyResolved = true;
    final String raw = _publicKeyBase64.trim();
    if (raw.isEmpty) {
      _cachedPublicKey = null;
      return null;
    }
    try {
      final List<int> bytes = base64.decode(base64.normalize(raw));
      // Ed25519 公钥固定 32 字节；长度不对说明配置写错了 → 当未配置处理。
      if (bytes.length != 32) {
        _cachedPublicKey = null;
        return null;
      }
      _cachedPublicKey = SimplePublicKey(bytes, type: KeyPairType.ed25519);
    } catch (_) {
      _cachedPublicKey = null;
    }
    return _cachedPublicKey;
  }
}
