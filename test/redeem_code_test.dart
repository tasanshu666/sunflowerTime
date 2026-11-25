/// 激活码离线验签单测（Android 官网直供版）。
///
/// 覆盖「一枚码从生成到验签」的全部真实路径：正确码 / 篡改 / 空码 / 长度不对 /
/// 版本不支持 / 公钥未配置 / 随机乱码 —— 且每一条都必须**不抛异常**。
///
/// 测试用**固定测试密钥对**（由固定的 32 字节 seed 派生，同一份 seed ⇒ 同一对密钥 ⇒
/// 用例可复现），通过构造参数注入 `RedeemCodeVerifier`，与生产公钥常量
/// `kRedeemPublicKeyBase64` 完全解耦。
library redeem_code_test;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/domain/services/redeem_code.dart';

/// 测试用固定 seed（32 字节；**绝不是生产私钥**，且只存在于测试文件中）。
final Uint8List _kTestSeed = Uint8List.fromList(
  List<int>.generate(32, (int i) => (i * 7 + 3) & 0xFF),
);

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;
  late RedeemCodeVerifier verifier;

  /// 用测试私钥签一枚码（[version] 仅用于造「未来版本」样本）。
  Future<String> issue(int serial, {int version = kRedeemCodeVersion}) async {
    final Uint8List payload =
        buildRedeemCodePayload(serial: serial, version: version);
    final Signature signature = await algorithm.sign(payload, keyPair: keyPair);
    final Uint8List binary = assembleRedeemCode(
      payload: payload,
      signatureBytes: signature.bytes,
    );
    return encodeRedeemCode(binary);
  }

  setUpAll(() async {
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPairFromSeed(_kTestSeed);
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64.encode(publicKey.bytes);
    verifier = RedeemCodeVerifier(publicKeyBase64: publicKeyBase64);
  });

  group('格式常量（单点定义，防改动走样）', () {
    test('二进制 69 字节 / 编码 92 字符', () {
      expect(kRedeemCodePayloadLength, 5);
      expect(kRedeemCodeBinaryLength, 69);
      expect(kRedeemCodeEncodedLength, 92);
    });

    test('签出的码长度 == kRedeemCodeEncodedLength，且可 Base64URL 解码回 69 字节',
        () async {
      final String code = await issue(1);
      expect(code.length, kRedeemCodeEncodedLength);
      expect(code.contains('='), isFalse, reason: '69 字节恰好整除 3，不应有 padding');
      expect(base64Url.decode(base64Url.normalize(code)).length,
          kRedeemCodeBinaryLength);
    });
  });

  group('normalizeRedeemCode：只剥空白，保留 Base64URL 数据字符', () {
    test('空格 / 全角空格 / 制表 / 换行全部剥掉', () {
      const String raw = '  ab CD  ef\nGH\u3000ij\tkl  ';
      expect(normalizeRedeemCode(raw), 'abCDefGHijkl');
    });

    test('大小写原样保留（Base64URL 大小写敏感，转大小写会废码）', () {
      const String raw = 'AbC DeF';
      expect(normalizeRedeemCode(raw), 'AbCDeF');
    });

    test('🔴 `-` 是 Base64URL 的数据字符，绝不能被当分组符剥掉', () {
      // 这条守卫的由来：初稿「剥空白 + 剥连字符」会让约三成合法码解码失败。
      const String raw = 'ab-cd';
      expect(normalizeRedeemCode(raw), 'ab-cd');
    });

    test('redeemCodeCandidates：第一候选只剥空白，第二候选再剥连字符（去重）', () {
      expect(redeemCodeCandidates(' a b '), <String>['ab']);
      expect(redeemCodeCandidates('ab-cd'), <String>['ab-cd', 'abcd']);
    });
  });

  group('verify：成功路径', () {
    test('正确码 → RedeemCodeValid，且 serial 与签发时一致', () async {
      final String code = await issue(123456);
      final RedeemCodeResult result = await verifier.verify(code);
      expect(result, isA<RedeemCodeValid>());
      expect((result as RedeemCodeValid).serial, 123456);
    });

    test('serial 上界 0xFFFFFFFF / 下界 0 都能往返', () async {
      for (final int serial in <int>[0, 1, 0xFFFFFFFF]) {
        final RedeemCodeResult r = await verifier.verify(await issue(serial));
        expect((r as RedeemCodeValid).serial, serial);
      }
    });

    test('带分组空格 / 前后空格 / 中间换行的粘贴形态仍能通过', () async {
      final String code = await issue(42);
      final String formatted = formatRedeemCodeForDisplay(code);
      expect(formatted.contains(' '), isTrue, reason: '分组显示每 23 字符插一个空格');
      final RedeemCodeResult result =
          await verifier.verify('  $formatted\n  ');
      expect(result, isA<RedeemCodeValid>());
      expect((result as RedeemCodeValid).serial, 42);
    });

    test('用户手工在码里插了连字符 → 备选形态兜底，仍能通过', () async {
      // 选一枚**本身不含 `-`** 的码，插连字符后只剩「分组符」，应能被兜底剥掉。
      late String plain;
      for (int serial = 100; serial < 400; serial++) {
        final String candidate = await issue(serial);
        if (!candidate.contains('-')) {
          plain = candidate;
          break;
        }
      }
      final String dashed = formatRedeemCodeForDisplay(plain).replaceAll(' ', '-');
      final RedeemCodeResult result = await verifier.verify(dashed);
      expect(result, isA<RedeemCodeValid>());
    });

    test('🔴 码本身含 `-` 数据字符时也能通过（回归守卫：剥连字符=废码）', () async {
      late String withDash;
      late int serialWithDash;
      for (int serial = 1; serial < 2000; serial++) {
        final String candidate = await issue(serial);
        if (candidate.contains('-')) {
          withDash = candidate;
          serialWithDash = serial;
          break;
        }
      }
      expect(withDash.contains('-'), isTrue, reason: '样本必须真的含 `-` 数据字符');
      final RedeemCodeResult result = await verifier.verify(withDash);
      expect((result as RedeemCodeValid).serial, serialWithDash);
    });

    test('同一枚码重复验签结果稳定（幂等，无隐藏状态）', () async {
      final String code = await issue(7);
      for (int i = 0; i < 3; i++) {
        final RedeemCodeResult r = await verifier.verify(code);
        expect((r as RedeemCodeValid).serial, 7);
      }
    });
  });

  group('verify：失败路径（每一条都不得抛异常）', () {
    test('篡改 1 个字符（签名区）→ badSignature', () async {
      final String code = await issue(99);
      final String last = code[code.length - 1];
      final String tampered =
          '${code.substring(0, code.length - 1)}${last == 'A' ? 'B' : 'A'}';
      expect(tampered, isNot(code));
      final RedeemCodeResult result = await verifier.verify(tampered);
      expect(result, const RedeemCodeInvalid(RedeemCodeError.badSignature));
    });

    test('篡改 serial（改 1 个字节后重编码）→ badSignature，且不泄漏 serial', () async {
      final String code = await issue(11);
      final Uint8List binary =
          Uint8List.fromList(base64Url.decode(base64Url.normalize(code)));
      binary[kRedeemCodeSerialOffset] ^= 0x01; // 改 serial 高位
      final String tampered = encodeRedeemCode(binary);
      final RedeemCodeResult result = await verifier.verify(tampered);
      expect(result, const RedeemCodeInvalid(RedeemCodeError.badSignature));
    });

    test('空码 / 纯空格 → malformed，且不崩', () async {
      expect(await verifier.verify(''),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
      expect(await verifier.verify('     \n\t  '),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
      expect(await verifier.verify('-----'),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
    });

    test('长度不对（多 1 字符 / 少 1 字符）→ malformed', () async {
      final String code = await issue(5);
      expect(await verifier.verify('${code}A'),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
      expect(await verifier.verify(code.substring(1)),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
    });

    test('版本号改成 0x02 → unsupportedVersion（不进入验签）', () async {
      final String futureCode = await issue(1, version: 0x02);
      expect(await verifier.verify(futureCode),
          const RedeemCodeInvalid(RedeemCodeError.unsupportedVersion));
    });

    test('版本号改成 0x00 → unsupportedVersion', () async {
      final String code = await issue(1, version: 0x00);
      expect(await verifier.verify(code),
          const RedeemCodeInvalid(RedeemCodeError.unsupportedVersion));
    });

    test('公钥空串 → notConfigured（未配置时绝不误判为「码无效」）', () async {
      final String code = await issue(3);
      final RedeemCodeVerifier unconfigured =
          RedeemCodeVerifier(publicKeyBase64: '');
      expect(await unconfigured.verify(code),
          const RedeemCodeInvalid(RedeemCodeError.notConfigured));
    });

    test('公钥是非法 Base64 / 长度不对 → notConfigured（配置事故，不崩）', () async {
      final String code = await issue(3);
      for (final String badKey in <String>['!!!not-base64!!!', 'AAAA']) {
        final RedeemCodeVerifier broken =
            RedeemCodeVerifier(publicKeyBase64: badKey);
        expect(await broken.verify(code),
            const RedeemCodeInvalid(RedeemCodeError.notConfigured),
            reason: '公钥「$badKey」应判未配置');
      }
    });

    test('随机 Base64 乱码（含非法字符）→ malformed，且不崩', () async {
      final String garbage = List<String>.filled(92, '*').join();
      expect(await verifier.verify(garbage),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
      expect(await verifier.verify('hello-world'),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
    });

    test('长度正确但内容全零的码 → 返回失败结果（不崩，且不放行）', () async {
      final String zeros =
          List<String>.filled(kRedeemCodeEncodedLength, 'A').join(); // 69 个 0x00
      final RedeemCodeResult result = await verifier.verify(zeros);
      expect(result, isA<RedeemCodeInvalid>());
      // 版本字节为 0 → 具体原因是版本不支持（顺序：长度 → 解码 → 版本 → 验签）。
      expect(result, const RedeemCodeInvalid(RedeemCodeError.unsupportedVersion));
    });

    test('别的密钥签出的码 → badSignature（换私钥即废码）', () async {
      final SimpleKeyPair otherKeyPair = await Ed25519()
          .newKeyPairFromSeed(Uint8List.fromList(List<int>.filled(32, 9)));
      final Uint8List payload = buildRedeemCodePayload(serial: 1234);
      final Signature signature =
          await Ed25519().sign(payload, keyPair: otherKeyPair);
      final String alienCode = encodeRedeemCode(assembleRedeemCode(
        payload: payload,
        signatureBytes: signature.bytes,
      ));
      expect(await verifier.verify(alienCode),
          const RedeemCodeInvalid(RedeemCodeError.badSignature));
    });
  });

  group('结果对象语义', () {
    test('RedeemCodeInvalid 相等性按原因区分', () {
      expect(const RedeemCodeInvalid(RedeemCodeError.malformed),
          const RedeemCodeInvalid(RedeemCodeError.malformed));
      expect(
          const RedeemCodeInvalid(RedeemCodeError.malformed) ==
              const RedeemCodeInvalid(RedeemCodeError.badSignature),
          isFalse);
    });

    test('RedeemCodeValid 相等性按 serial 区分', () {
      expect(const RedeemCodeValid(7), const RedeemCodeValid(7));
      expect(const RedeemCodeValid(7) == const RedeemCodeValid(8), isFalse);
    });
  });

  group('开发期构造器守卫（不是用户输入路径，允许抛）', () {
    test('serial 超出 uint32 → ArgumentError', () {
      expect(() => buildRedeemCodePayload(serial: -1), throwsArgumentError);
      expect(() => buildRedeemCodePayload(serial: 0x100000000),
          throwsArgumentError);
    });

    test('assembleRedeemCode / encodeRedeemCode 长度不符 → ArgumentError', () {
      expect(
          () => assembleRedeemCode(
              payload: Uint8List(4), signatureBytes: Uint8List(64)),
          throwsArgumentError);
      expect(
          () => assembleRedeemCode(
              payload: Uint8List(5), signatureBytes: Uint8List(63)),
          throwsArgumentError);
      expect(() => encodeRedeemCode(Uint8List(68)), throwsArgumentError);
    });
  });
}
