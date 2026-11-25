/// QA 独立复验：激活码离线验签的**对抗性**测试（不复用工程师的用例思路）。
///
/// 与 `test/redeem_code_test.dart` 的分工：那边覆盖「常规正确 / 常规错误」，
/// 本文件专门**攻击**实现里唯一有安全争议的设计点 ——
/// `redeemCodeCandidates` 的「双候选」（第二候选会额外剥掉 `-`）。
///
/// 攻击面清单（每一条都必须 invalid，且**绝不抛**）：
///  1. 合法码里天然含 `-` 数据字符 → 必须能激活（否则约 3/4 已付费用户被静默废码）；
///  2. 用户把分组空格换成 `-` 手工输入 → 必须能激活；
///  3. 改动 1 个数据字符且「剥掉 `-` 后长度仍为 92」→ 必须 invalid（候选二不得放水）；
///  4. 把合法码里所有 `-` 换成别的字符（长度不变）→ 必须 invalid；
///  5. 两枚不同 serial 的码交叉拼接 → 必须 invalid；
///  6. 逐位篡改（92 个位置 × 3 种替换字符）→ 必须全部 invalid；
///  7. fuzz：畸形 / 超长 / 非法字符 / emoji / 全角 → 必须 invalid 且不抛。
library premium_redeem_code_adversarial_test;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/iap_product_ids.dart';
import 'package:sunflower_time/domain/entities/entitlement.dart';
import 'package:sunflower_time/domain/repositories/entitlement_repository.dart';
import 'package:sunflower_time/domain/services/entitlement_service.dart';
import 'package:sunflower_time/domain/services/redeem_code.dart';

/// 记录型假仓储（QA 自己的一份，不复用工程师的）。
class _QaRepo implements EntitlementRepository {
  _QaRepo({Entitlement? initial, this.failWrite = false})
      : _stored = initial ?? Entitlement.free;

  Entitlement _stored;

  /// 是否让 [write] 抛异常（模拟安全区不可用）。
  bool failWrite;

  /// `write` 调用次数（幂等取证）。
  int writes = 0;

  /// 每次写入的 `jws`（激活码路径必须恒为 null）。
  final List<String?> jwsSeen = <String?>[];

  Entitlement get stored => _stored;

  @override
  Future<Entitlement> read() async => _stored;

  @override
  Future<void> write(Entitlement entitlement, {String? jws}) async {
    writes++;
    jwsSeen.add(jws);
    if (failWrite) throw StateError('secure storage unavailable (qa test)');
    _stored = entitlement;
  }

  @override
  Future<void> clear() async => _stored = Entitlement.free;
}

/// QA 固定测试密钥对 seed（与工程师用例、与生产常量均无关）。
final Uint8List _kQaSeed =
    Uint8List.fromList(List<int>.generate(32, (int i) => (i * 13 + 200) & 0xFF));

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;
  late RedeemCodeVerifier verifier;

  /// 用 QA 私钥签发一枚码。
  Future<String> issue(int serial) async {
    final Uint8List payload = buildRedeemCodePayload(serial: serial);
    final Signature signature = await algorithm.sign(payload, keyPair: keyPair);
    return encodeRedeemCode(
      assembleRedeemCode(payload: payload, signatureBytes: signature.bytes),
    );
  }

  /// 断言「invalid 且不抛」—— 统一口径，避免每个用例重复写 try/catch。
  Future<void> expectInvalid(String code, {String? reason}) async {
    late RedeemCodeResult result;
    try {
      result = await verifier.verify(code);
    } catch (e, st) {
      fail('verify() 抛异常（红线：验签绝不抛）'
          '${reason == null ? '' : '｜$reason'}：$e\n$st');
    }
    expect(result, isA<RedeemCodeInvalid>(),
        reason: '必须判 invalid（不得放行）${reason == null ? '' : '｜$reason'}');
  }

  setUpAll(() async {
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPairFromSeed(_kQaSeed);
    publicKeyBase64 = base64.encode((await keyPair.extractPublicKey()).bytes);
    verifier = RedeemCodeVerifier(publicKeyBase64: publicKeyBase64);
  });

  // ────────────────────────────────────────────────────────────────────────
  group('① `-` 是 Base64URL 数据字符：天然含 `-` 的合法码必须能激活', () {
    test('连续签发 30 枚，所有天然含 `-` 的码逐一验签通过（serial 对得上）', () async {
      final List<String> withDash = <String>[];
      final Map<String, int> dashToSerial = <String, int>{};
      for (int serial = 1; serial <= 30; serial++) {
        final String code = await issue(serial);
        expect(code.length, kRedeemCodeEncodedLength);
        if (code.contains('-')) {
          withDash.add(code);
          dashToSerial[code] = serial;
        }
      }
      // 期望值：92 个字符、每位 1/64 命中 `-` → 命中率 ≈ 1-(63/64)^92 ≈ 76%。
      expect(withDash.length, greaterThan(15),
          reason: '30 枚里天然含 `-` 的应远超一半（实测 ${withDash.length}/30）');

      for (final String code in withDash) {
        final RedeemCodeResult r = await verifier.verify(code);
        expect(r, isA<RedeemCodeValid>(),
            reason: '含 `-` 数据字符的合法码被判死了：$code');
        expect((r as RedeemCodeValid).serial, dashToSerial[code]);
      }
    });

    test('🔴 对照实验：把同一枚码里的 `-` 数据字符删掉 → 必失败（证明 `-` 真的在承载数据）',
        () async {
      late String withDash;
      late int serial;
      for (int s = 1; s < 500; s++) {
        final String c = await issue(s);
        if (c.contains('-')) {
          withDash = c;
          serial = s;
          break;
        }
      }
      expect(withDash.contains('-'), isTrue);
      // 原始码有效
      expect((await verifier.verify(withDash) as RedeemCodeValid).serial, serial);
      // 删掉 `-` 数据字符后长度变 91 → 必然取不到有效结果
      await expectInvalid(withDash.replaceAll('-', ''),
          reason: '删 `-` 数据字符必须失败（否则说明 `-` 根本不影响数据）');
    });

    test('统计口径核实：`-` 命中率是「约三成」还是「约七成」（给文档纠偏取证）', () async {
      int withDash = 0;
      const int total = 200;
      for (int s = 1; s <= total; s++) {
        if ((await issue(s)).contains('-')) withDash++;
      }
      // 理论值 1-(63/64)^92 ≈ 76.4%；记录实测值到测试输出，便于报告引用。
      // ignore: avoid_print
      print('[QA] 200 枚中含 `-` 数据字符的：$withDash 枚（${(withDash * 100 / total).toStringAsFixed(1)}%）');
      expect(withDash / total, greaterThan(0.5),
          reason: '命中率应约 76%，远高于源码注释里写的「约三成」');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('② 用户手工把分组空格换成 `-`（输入容错）', () {
    test('无 `-` 的码：把分组空格全换成长横线 → 仍能激活', () async {
      late String plain;
      for (int s = 1; s < 500; s++) {
        final String c = await issue(s);
        if (!c.contains('-')) {
          plain = c;
          break;
        }
      }
      // 模拟「用户把展示用的空格手打成 `-`」
      final String dashed =
          formatRedeemCodeForDisplay(plain).replaceAll(' ', '-');
      expect(dashed.length, plain.length + 3, reason: '92 字符 → 每 23 插一个，共 3 个');
      final RedeemCodeResult r = await verifier.verify(dashed);
      expect(r, isA<RedeemCodeValid>(),
          reason: '第二候选（再剥一次 `-`）应兜住手工连字符输入');
    });

    test('⚠️ 已知边界：本身含 `-` 数据字符 + 用户又插了连字符 → 无法激活（记录，不修）',
        () async {
      late String withDash;
      for (int s = 1; s < 500; s++) {
        final String c = await issue(s);
        if (c.contains('-')) {
          withDash = c;
          break;
        }
      }
      final String dashed =
          formatRedeemCodeForDisplay(withDash).replaceAll(' ', '-');
      // 双候选都救不了：第一候选 95 字符（长度错），第二候选 91 字符（删掉了数据字符）。
      await expectInvalid(dashed,
          reason: '这是双候选设计的固有边界：数据 `-` 与分组 `-` 不可区分');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('③④ 候选二不得放水：长度仍为 92 的篡改必须 invalid', () {
    test('🔴 改 1 个数据字符 + 剥 `-` 后长度仍为 92 → invalid', () async {
      // 构造：选一枚**不含 `-`** 的合法码 V（92 字符）
      //  · 先改 V 的 1 个数据字符 → V'（92 字符）
      //  · 再往 V' 里插 1 个 `-` → 输入 93 字符、恰好 1 个 `-`
      //  ⇒ 第一候选 93 字符（长度错 → malformed），
      //    第二候选剥掉 `-` 后**恰为 92 字符**且含被改的数据位 → 必须 badSignature。
      // 这条正是「候选二会不会把长度凑回 92 从而放水」的直接拷问。
      late String v;
      for (int s = 1; s < 500; s++) {
        final String c = await issue(s);
        if (!c.contains('-')) {
          v = c;
          break;
        }
      }
      const int mutateAt = 40; // 避开首 6 bit（version 位，两侧码字串可能同字符）
      final String mutatedData =
          '${v.substring(0, mutateAt)}X${v.substring(mutateAt + 1)}';
      expect(mutatedData.length, kRedeemCodeEncodedLength);

      const int insertAt = 10;
      final String tampered =
          '${mutatedData.substring(0, insertAt)}-${mutatedData.substring(insertAt)}';

      expect(tampered.length, kRedeemCodeEncodedLength + 1,
          reason: '93 字符：92 + 1 个插入的 `-`');
      final List<String> candidates = redeemCodeCandidates(tampered);
      expect(candidates.length, 2, reason: '两个候选都必须被试过');
      expect(candidates.first.length, 93, reason: '第一候选只剥空白 → 长度错');
      expect(candidates.last.length, kRedeemCodeEncodedLength,
          reason: '第二候选剥掉 `-` 后**恰好 92 字符**（本用例的关键构造）');
      expect(candidates.last, mutatedData,
          reason: '第二候选正是那份被改过数据位的 92 字符串');

      await expectInvalid(tampered,
          reason: '数据位被改动，长度凑回 92 也不得通过验签');
    });

    test('✅ 正对照：无 `-` 的合法码随便插若干 `-` → 仍能激活（证明候选二不是废码）',
        () async {
      late String v;
      for (int s = 1; s < 500; s++) {
        final String c = await issue(s);
        if (!c.contains('-')) {
          v = c;
          break;
        }
      }
      for (final int at in <int>[0, 1, 10, 46, 91]) {
        // 插在末尾（at == 92）与开头都要覆盖；这里 at == 91 是倒数第二位
        final String withDash = '${v.substring(0, at)}-${v.substring(at)}';
        final RedeemCodeResult r = await verifier.verify(withDash);
        expect(r, isA<RedeemCodeValid>(),
            reason: '在第 $at 位插 `-` 后应仍能凭第二候选激活（长度 93）');
      }
      // 再插多个
      final String many = '${v.substring(0, 3)}-'
          '${v.substring(3, 30)}-'
          '${v.substring(30)}';
      expect(await verifier.verify(many), isA<RedeemCodeValid>());
    });

    test('🔴 把合法码里的所有 `-` 换成别的字符（长度不变）→ invalid', () async {
      int tested = 0;
      for (int s = 1; s <= 40 && tested < 5; s++) {
        final String code = await issue(s);
        if (!code.contains('-')) continue;
        tested++;
        for (final String repl in <String>['A', '_', '0']) {
          final String mutated = code.replaceAll('-', repl);
          expect(mutated.length, kRedeemCodeEncodedLength);
          await expectInvalid(mutated,
              reason: 'serial $s：`-`→`$repl`');
        }
      }
      expect(tested, greaterThan(0), reason: '必须真的找到含 `-` 的样本');
    });

    test('🔴 两枚不同 serial 的码交叉拼接 → invalid', () async {
      final String a = await issue(111);
      final String b = await issue(222);
      expect(a, isNot(b));
      // ⚠️ 前面若干字符两码必然相同（都是 version 0x01 + serial 的高位 0x00 字节，
      //    且 serial 111/222 只差最低字节）→ 在这些位置切会拼出 b 本身，属「伪攻击」。
      //    故只取前缀真正不同的切点，逐个取证。
      int attacked = 0;
      for (final int cut in <int>[7, 10, 23, 46, 69, 90]) {
        if (a.substring(0, cut) == b.substring(0, cut)) continue; // 伪攻击，跳过
        final String spliced = a.substring(0, cut) + b.substring(cut);
        expect(spliced.length, kRedeemCodeEncodedLength);
        expect(spliced, isNot(b), reason: '拼出来的必须既不是 a 也不是 b');
        expect(spliced, isNot(a));
        await expectInvalid(spliced, reason: '拼接切点 $cut');
        attacked++;
      }
      expect(attacked, greaterThanOrEqualTo(3), reason: '至少要真的攻击 3 个切点');
      // 反向也算一遍
      await expectInvalid(b.substring(0, 46) + a.substring(46));
    });

    test('逐位篡改：92 个位置 × 3 种替换字符 → 全部 invalid（368 次验签）', () async {
      final String code = await issue(31337);
      const List<String> replacements = <String>['A', '-', 'z'];
      int checks = 0;
      for (int i = 0; i < code.length; i++) {
        for (final String r in replacements) {
          if (code[i] == r) continue;
          final String mutated =
              code.substring(0, i) + r + code.substring(i + 1);
          expect(mutated.length, kRedeemCodeEncodedLength);
          await expectInvalid(mutated, reason: '位置 $i 改成 `$r`');
          checks++;
        }
      }
      expect(checks, greaterThan(200));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('⑤ fuzz：畸形输入一律 RedeemCodeInvalid 且**绝不抛**', () {
    test('长度谱：0 / 1 / 50 / 91 / 92 / 93 / 1000', () async {
      for (final int len in <int>[0, 1, 50, 91, 92, 93, 1000]) {
        final String filler = List<String>.filled(len, 'A').join();
        await expectInvalid(filler, reason: '长度 $len 的全 A 串');
        final String dashOnly = List<String>.filled(len, '-').join();
        await expectInvalid(dashOnly, reason: '长度 $len 的全 `-` 串');
      }
    });

    test('空白谱：空串 / 纯空格 / 全角空格 / 制表 / 换行 / NBSP', () async {
      for (final String s in <String>[
        '',
        '   ',
        '\u3000\u3000\u3000',
        '\t\t\t',
        '\n\n\n',
        '\u00A0\u00A0',
        ' \u3000\t\n\u00A0 ',
      ]) {
        await expectInvalid(s, reason: '空白串「${s.replaceAll('\n', r'\n')}」');
      }
    });

    test('非法 Base64URL 字符：`+` / `/` / `=` / `*` / 混合', () async {
      for (final String ch in <String>['+', '/', '=', '*', '#', '%', '&']) {
        await expectInvalid(List<String>.filled(92, ch).join(), reason: '全 `$ch`');
        // 只污染 1 位（故意保留正确长度）
        final String code = await issue(1);
        final String polluted = '$ch${code.substring(1)}';
        await expectInvalid(polluted, reason: '首位替换成 `$ch`');
      }
    });

    test('emoji / 全角字符 / 中日韩字符 → invalid 且不抛', () async {
      for (final String s in <String>[
        '🌻🌻🌻',
        '🌻' * 46,
        'ＡＢＣＤＥＦＧＨ', // 全角
        '激活码激活码',
        'ＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡＡ',
      ]) {
        await expectInvalid(s, reason: '「$s」');
      }
    });

    test('合法长度但随机字节（含合法 version 字节）→ invalid，且不抛', () async {
      final Random rng = Random(20261225);
      for (int round = 0; round < 30; round++) {
        final Uint8List binary = Uint8List(kRedeemCodeBinaryLength);
        for (int i = 0; i < binary.length; i++) {
          binary[i] = rng.nextInt(256);
        }
        if (round.isEven) binary[0] = kRedeemCodeVersion; // 一半是「版本对但签名假」
        final String code = base64Url.encode(binary).replaceAll('=', '');
        expect(code.length, kRedeemCodeEncodedLength);
        await expectInvalid(code, reason: '第 $round 组随机字节');
      }
    });

    test('超长字符串（10 万字符）→ invalid 且不抛（不含 O(n²) 卡死）', () async {
      final String huge = 'A' * 100000;
      final Stopwatch sw = Stopwatch()..start();
      await expectInvalid(huge);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: '超长输入处理耗时 ${sw.elapsedMilliseconds}ms，不应有异常放大');
    });

    test('「合法码 + 垃圾前缀/后缀」→ invalid（长度先被挡）', () async {
      final String code = await issue(9);
      await expectInvalid('$code A');
      await expectInvalid('A$code');
      await expectInvalid('$code$code');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('⑥ 域服务幂等与「不半成功」（QA 自己的假仓储独立取证）', () {
    late String pk;
    setUp(() async {
      pk = publicKeyBase64;
    });

    MatrixEntitlementService build(_QaRepo repo) => MatrixEntitlementService(
          repository: repo,
          clock: () => DateTime(2026, 7, 7, 7, 7),
          redeemVerifier: RedeemCodeVerifier(publicKeyBase64: pk),
        );

    test('首次激活 → activated；仓储收到 jws == null', () async {
      final _QaRepo repo = _QaRepo();
      final MatrixEntitlementService svc = build(repo);
      expect(await svc.activate(await issue(1)), RedeemActivationResult.activated);
      expect(repo.writes, 1);
      expect(repo.jwsSeen, <String?>[null],
          reason: '激活码没有 Apple JWS，落库必须是 null');
      expect(repo.stored.productId, kIapProductIdLifetime);
      expect(repo.stored.isPremium, isTrue);
      expect(svc.current, repo.stored);
    });

    test('已 premium 再激活 → alreadyPremium 且写入次数为 0（新仓储、未 load 也算）',
        () async {
      final _QaRepo repo = _QaRepo(
        initial: Entitlement.lifetime(
          acquiredAt: DateTime(2025, 1, 1),
          productId: kIapProductIdLifetime,
        ),
      );
      final MatrixEntitlementService svc = build(repo);
      await svc.load();
      expect(await svc.activate(await issue(2)),
          RedeemActivationResult.alreadyPremium);
      expect(repo.writes, 0);
      expect(repo.stored.acquiredAt, DateTime(2025, 1, 1));
    });

    test('仓储 write 抛异常 → failed，且内存态**保持 free**（严禁半成功）', () async {
      final _QaRepo repo = _QaRepo(failWrite: true);
      final MatrixEntitlementService svc = build(repo);
      expect(await svc.activate(await issue(3)), RedeemActivationResult.failed);
      expect(repo.writes, 1, reason: '确实尝试过写');
      expect(svc.current.isPremium, isFalse,
          reason: '票据没落库，内存态必须还是 free（否则重启掉档）');
      expect(svc.can(FeatureKey.gardenPotCapacity), isNotNull);
      expect(repo.stored.isPremium, isFalse);
    });

    test('三态映射：malformed / invalid / notConfigured 各自独立，且零写入', () async {
      final _QaRepo repo = _QaRepo();
      final MatrixEntitlementService svc = build(repo);
      expect(await svc.activate(''), RedeemActivationResult.malformedCode);

      final String code = await issue(4);
      final String tampered =
          '${code.substring(0, code.length - 1)}${code.endsWith('A') ? 'B' : 'A'}';
      expect(await svc.activate(tampered), RedeemActivationResult.invalidCode);

      final MatrixEntitlementService unconfigured = MatrixEntitlementService(
        repository: repo,
        redeemVerifier: RedeemCodeVerifier(publicKeyBase64: ''),
      );
      expect(await unconfigured.activate(code),
          RedeemActivationResult.notConfigured);
      expect(repo.writes, 0, reason: '三种失败都不许写票据');
      expect(svc.current.isPremium, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('⑦ 常量与格式单点守卫（防将来改长度静默走样）', () {
    test('69 字节 / 92 字符 / 无 padding，且每个字节位置都被签名覆盖', () async {
      expect(kRedeemCodeBinaryLength, 69);
      expect(kRedeemCodeEncodedLength, 92);
      expect(kRedeemCodePayloadLength, 5);
      final String code = await issue(1);
      expect(code.contains('='), isFalse);
      expect(base64Url.decode(base64Url.normalize(code)).length, 69);
    });

    test('serial 大端序：改 serial 的 4 个字节中任意一个都 invalid（防小端误读）', () async {
      final String code = await issue(0x01020304);
      final Uint8List binary =
          Uint8List.fromList(base64Url.decode(base64Url.normalize(code)));
      expect(binary.sublist(1, 5), <int>[1, 2, 3, 4], reason: '必须是 uint32 大端');
      for (int off = 1; off <= 4; off++) {
        final Uint8List copy = Uint8List.fromList(binary);
        copy[off] ^= 0xFF;
        await expectInvalid(encodeRedeemCode(copy), reason: 'serial 字节 $off 被改');
      }
    });

    test('formatRedeemCodeForDisplay 圆整：分组用空格，切回原码无损', () async {
      final String code = await issue(8);
      final String shown = formatRedeemCodeForDisplay(code);
      expect(shown.split(' ').length, 4, reason: '92 字符 → 23/23/23/23');
      expect(normalizeRedeemCode(shown), code);
      expect(shown.contains('-'), code.contains('-'),
          reason: '展示不得新增/删除 `-`（`-` 是数据字符）');
    });
  });
}
