/// 激活码发码工具（**开发者本机 CLI，绝不进 App 包**）。
///
/// ## 它做什么
///
/// 用 **Ed25519 私钥**离线签发一枚「激活码」，用户凭码在 App 内离线验签解锁 premium
/// （格式与常量单点定义在 `lib/domain/services/redeem_code.dart`）。
///
/// ## 它绝不做什么
///
/// - **不被 `lib/` 里任何代码 import**（App 包里只有公钥，私钥只在开发机的这个脚本里
///   被使用；本文件的 import 方向是单向的：tool → lib）；
/// - **不做支付**：收款在官网完成（微信 / 支付宝收款码或第三方），本工具只负责「发码」；
/// - 不做联网 / 数据库对账：序号（serial）由你自己用 Excel / 记事本记账。
///
/// ## 用法
///
/// ```bash
/// # 1) 首次：生成密钥对（公钥填进 lib/core/constants/redeem_public_key.dart，
/// #    私钥离线保管：密码管理器 / 离线机器 / 纸质备份，绝不进仓库）
/// dart run tool/issue_redeem_code.dart --gen-keypair
///
/// # 2) 发一枚码（serial 建议从 1 开始递增，逐单记账）
/// dart run tool/issue_redeem_code.dart --serial 1 --private-key <私钥Base64>
///
/// # 3) 一次发一批（如补发 10 枚：serial 1..10）
/// dart run tool/issue_redeem_code.dart --serial 1 --count 10 --private-key <私钥Base64>
///
/// # 4) 码池补货：写机器可读 JSON（stdout 只留一行摘要，不打印码本身）
/// dart run tool/issue_redeem_code.dart --serial 1001 --count 1000 \
///   --private-key <私钥Base64> --out build/codes_1001.json
/// ```
///
/// 不带 `--out` 时，输出里的激活码按「每 23 字符一个**空格**」分组显示，
/// 方便人工抄写 / 复制；**粘贴到 App 时空格会被自动清理**（`normalizeRedeemCode`），
/// 带不带都行。带 `--out` 时写入 UTF-8 JSON 数组（`JsonEncoder.withIndent('  ')`）：
///
/// ```json
/// [
///   { "serial": 1001, "code": "AQAA...(92 字符 Base64URL 原码，无空格，保留 -)" }
/// ]
/// ```
///
/// 🔴 分组符**只能用空格，绝不能用 `-`**：`-` 是 Base64URL 的合法数据字符
/// （约三成码里自带），拿它当分组符会让「复制分组文本再粘贴」这条路静默废码。
/// JSON 里的 `code` 是**不带分组空格的 92 字符原码**，`-` 原样保留。
///
/// 退出码：成功 `0`；参数错误 `64`；签发失败 `1`；写文件失败 `2`。
library issue_redeem_code;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:sunflower_time/domain/services/redeem_code.dart';

/// 参数 / 用法错误退出码（对齐 BSD sysexits 的 EX_USAGE）。
const int _kExitUsage = 64;

/// 签发过程失败退出码。
const int _kExitFailure = 1;

/// 写 `--out` 文件失败退出码（与参数错误、签发失败区分，便于自动化补货脚本判断）。
const int _kExitOutput = 2;

Future<void> main(List<String> args) async {
  try {
    final _Options options = _Options.parse(args);
    if (options.showHelp) {
      stdout.writeln(_kUsage);
      exit(0);
    }
    if (options.generateKeyPair) {
      await _generateKeyPair();
      exit(0);
    }
    await _issueCodes(options);
    exit(0);
  } on _UsageException catch (e) {
    stderr.writeln('参数错误：${e.message}');
    stderr.writeln();
    stderr.writeln(_kUsage);
    exit(_kExitUsage);
  } on _OutputException catch (e) {
    stderr.writeln('写文件失败：${e.message}');
    exit(_kExitOutput);
  } catch (e) {
    stderr.writeln('签发失败：$e');
    exit(_kExitFailure);
  }
}

/// 生成一对 Ed25519 密钥：打印 Base64 公钥（进 App）与 Base64 私钥种子（自己保管）。
Future<void> _generateKeyPair() async {
  final Ed25519 algorithm = Ed25519();
  final SimpleKeyPair keyPair = await algorithm.newKeyPair();
  final SimplePublicKey publicKey = await keyPair.extractPublicKey();
  final List<int> privateSeed = await keyPair.extractPrivateKeyBytes();

  stdout.writeln('已生成一对 Ed25519 密钥（私钥 = 32 字节种子）。');
  stdout.writeln();
  stdout.writeln('公钥（Base64，粘进 lib/core/constants/redeem_public_key.dart）：');
  stdout.writeln('  ${base64.encode(publicKey.bytes)}');
  stdout.writeln();
  stdout.writeln('私钥（Base64 种子，**离线保管，绝不进仓库 / 绝不进 App**）：');
  stdout.writeln('  ${base64.encode(privateSeed)}');
  stdout.writeln();
  stdout.writeln('⚠️ 公钥一旦随 APK 发布，换公钥 = 老码全部失效，发版前务必确认。');
}

/// 用给定私钥签发 [count] 枚激活码（serial 从 [startSerial] 递增）。
Future<void> _issueCodes(_Options options) async {
  final int? serialArg = options.serial;
  if (serialArg == null) {
    throw const _UsageException('缺少 --serial（签发序号，建议从 1 递增）');
  }
  final int startSerial = serialArg;
  final String privateKeyArg = options.privateKey;
  if (privateKeyArg.isEmpty) {
    throw const _UsageException('缺少 --private-key（Base64 私钥种子，见 --gen-keypair 输出）');
  }

  final Uint8List seed;
  try {
    seed = Uint8List.fromList(base64.decode(base64.normalize(privateKeyArg.trim())));
  } catch (_) {
    throw const _UsageException('--private-key 不是合法 Base64');
  }
  if (seed.length != 32) {
    throw _UsageException('--private-key 必须是 32 字节种子（当前 ${seed.length} 字节）');
  }

  final Ed25519 algorithm = Ed25519();
  final SimpleKeyPair keyPair = await algorithm.newKeyPairFromSeed(seed);
  final SimplePublicKey publicKey = await keyPair.extractPublicKey();

  // 先签名、后分流输出：两条路径共用同一批码，避免逻辑漂移。
  final List<({int serial, String code})> issued =
      <({int serial, String code})>[];
  for (int i = 0; i < options.count; i++) {
    final int serial = startSerial + i;
    final Uint8List payload = buildRedeemCodePayload(serial: serial);
    final Signature signature = await algorithm.sign(payload, keyPair: keyPair);
    final Uint8List binary = assembleRedeemCode(
      payload: payload,
      signatureBytes: signature.bytes,
    );
    issued.add((serial: serial, code: encodeRedeemCode(binary)));
  }

  final String outPath = options.outPath;
  if (outPath.isNotEmpty) {
    await _writeJsonOutput(
      path: outPath,
      issued: issued,
      startSerial: startSerial,
    );
    return;
  }

  // 🔴 不带 --out 的 stdout 是玄参现用的签发方式，逐字节保持向后兼容。
  stdout.writeln('公钥（应与 redeem_public_key.dart 一致）：'
      '${base64.encode(publicKey.bytes)}');
  stdout.writeln('共签发 ${options.count} 枚（serial $startSerial .. '
      '${startSerial + options.count - 1}）：');
  stdout.writeln();
  for (final ({int serial, String code}) row in issued) {
    stdout.writeln('serial ${row.serial.toString().padLeft(6)}  '
        '${formatRedeemCodeForDisplay(row.code)}');
  }
  stdout.writeln();
  stdout.writeln('提示：以上分组里的空格只是给人看的；粘贴到 App 时会被自动清理，'
      '码本身固定 $kRedeemCodeEncodedLength 字符（其中 `-` 是数据字符，不能删）。');
}

/// 把签发结果写成机器可读 JSON 数组，终端只留一行摘要（码不进终端日志）。
Future<void> _writeJsonOutput({
  required String path,
  required List<({int serial, String code})> issued,
  required int startSerial,
}) async {
  final List<Map<String, Object>> rows = <Map<String, Object>>[
    for (final ({int serial, String code}) row in issued)
      <String, Object>{'serial': row.serial, 'code': row.code},
  ];
  final String content = '${const JsonEncoder.withIndent('  ').convert(rows)}\n';

  try {
    final File file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8);
  } catch (e) {
    throw _OutputException('无法写入「$path」：$e');
  }

  stdout.writeln('已签发 ${issued.length} 枚激活码（serial '
      '$startSerial .. ${startSerial + issued.length - 1}），JSON 已写入：$path');
}

/// 命令行参数（手写解析，零依赖 —— 本工具不该为几个 flag 引入 args 包）。
class _Options {
  _Options({
    required this.generateKeyPair,
    required this.showHelp,
    required this.count,
    this.serial,
    this.privateKey = '',
    this.outPath = '',
  });

  /// `--gen-keypair`：生成密钥对。
  final bool generateKeyPair;

  /// `--help` / `-h`：打印用法。
  final bool showHelp;

  /// `--serial N`：起始签发序号（uint32）。
  final int? serial;

  /// `--count N`：连发几枚（默认 1）。
  final int count;

  /// `--private-key <Base64 种子>`。
  final String privateKey;

  /// `--out <path>`：写机器可读 JSON；空字符串表示沿用 stdout 文本输出。
  final String outPath;

  /// 解析参数；非法输入抛 [_UsageException]。
  factory _Options.parse(List<String> args) {
    bool generateKeyPair = false;
    bool showHelp = false;
    int? serial;
    int count = 1;
    String privateKey = '';
    String outPath = '';

    for (int i = 0; i < args.length; i++) {
      final String arg = args[i];
      switch (arg) {
        case '--gen-keypair':
          generateKeyPair = true;
        case '--help' || '-h':
          showHelp = true;
        case '--serial':
          serial = _parseInt(_valueOf(args, ++i, '--serial'), '--serial');
        case '--count':
          count = _parseInt(_valueOf(args, ++i, '--count'), '--count');
        case '--private-key':
          privateKey = _valueOf(args, ++i, '--private-key');
        case '--out':
          outPath = _valueOf(args, ++i, '--out').trim();
          if (outPath.isEmpty) {
            throw const _UsageException('--out 后面缺少文件路径');
          }
        default:
          throw _UsageException('未知参数：$arg');
      }
    }

    if (!generateKeyPair && !showHelp) {
      if (serial == null) throw const _UsageException('缺少 --serial');
      if (serial < 0 || serial > 0xFFFFFFFF) {
        throw const _UsageException('--serial 必须是 0..4294967295 的整数（uint32）');
      }
      if (count < 1) throw const _UsageException('--count 必须 ≥ 1');
      if (serial + count - 1 > 0xFFFFFFFF) {
        throw const _UsageException('--serial + --count - 1 超出 uint32 上限');
      }
    }

    return _Options(
      generateKeyPair: generateKeyPair,
      showHelp: showHelp,
      serial: serial,
      count: count,
      privateKey: privateKey,
      outPath: outPath,
    );
  }

  /// 取 `--flag` 后面的值；缺值抛 [_UsageException]。
  static String _valueOf(List<String> args, int index, String flag) {
    if (index >= args.length) {
      throw _UsageException('$flag 后面缺少值');
    }
    return args[index];
  }

  /// 解析整数；非整数抛 [_UsageException]。
  static int _parseInt(String raw, String flag) {
    final int? value = int.tryParse(raw.trim());
    if (value == null) {
      throw _UsageException('$flag 必须是整数（收到「$raw」）');
    }
    return value;
  }
}

/// 参数用法错误（仅本工具内部使用）。
class _UsageException implements Exception {
  const _UsageException(this.message);

  /// 人类可读的原因。
  final String message;
}

/// `--out` 写文件失败（仅本工具内部使用，退出码 [_kExitOutput]）。
class _OutputException implements Exception {
  const _OutputException(this.message);

  /// 人类可读的原因。
  final String message;
}

/// 用法说明。
const String _kUsage = '''
激活码发码工具 —— 用法：

  dart run tool/issue_redeem_code.dart --gen-keypair
      生成一对 Ed25519 密钥：公钥填进 lib/core/constants/redeem_public_key.dart，
      私钥（Base64 种子）离线保管，绝不进仓库 / 绝不进 App 包。

  dart run tool/issue_redeem_code.dart --serial <uint32> [--count N] --private-key <Base64> [--out <path>]
      签发激活码。--serial 建议从 1 开始逐单递增并记账；--count 默认 1。
      不带 --out：分组文本打印到 stdout（人工抄写），逐字节兼容旧用法。
      带 --out：写 UTF-8 JSON 数组 [{"serial": 1001, "code": "..."}] 到指定文件
      （父目录自动创建、code 为 92 字符无空格原码），stdout 只留一行摘要。

输出的激活码固定 $kRedeemCodeEncodedLength 字符，stdout 分组文本按每 23 字符
插一个空格；粘贴到 App 时空格会被自动清理，带不带都行。JSON 里的 code 不带空格。''';
