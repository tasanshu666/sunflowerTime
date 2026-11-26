/// 发码 CLI `--out` 参数的端到端测试。
///
/// 这里刻意用**子进程跑真实 CLI**（而不是 import 工具文件后调 `main`）：
/// - CLI 里用了 `exit()`，在 test zone 里会抛 `UnsupportedError`；
/// - `--out` 的价值就是「给补货脚本用」，必须验证真实进程的 stdout / stderr / 退出码。
///
/// 🔴 私钥只在**进程内存**里生成并通过命令行参数传入，绝不落盘到仓库；
/// 唯一落盘的是 `build/` 下的临时 JSON，tearDown 一律删除。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String privateKeyBase64;

  /// 本次测试创建的 `build/` 临时路径（文件 + 顶层目录），tearDown 统一清理。
  final List<String> tempPaths = <String>[];

  setUpAll(() async {
    final SimpleKeyPair keyPair = await Ed25519().newKeyPair();
    final List<int> seed = await keyPair.extractPrivateKeyBytes();
    privateKeyBase64 = base64.encode(seed);
  });

  tearDown(() async {
    for (final String path in tempPaths) {
      final Directory directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        continue;
      }
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    tempPaths.clear();
  });

  /// 找真正的 dart 可执行文件。
  ///
  /// 🔴 `flutter test` 里 `Platform.resolvedExecutable` 指向 **flutter_tester**，
  /// 拿它跑脚本会一直等测试协议、永不退出（实测卡到 timeout），必须用 dart SDK。
  String resolveDartExecutable() {
    final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final String candidate = '$flutterRoot/bin/cache/dart-sdk/bin/dart';
      if (File(candidate).existsSync()) return candidate;
    }
    final List<String> pathEntries =
        (Platform.environment['PATH'] ?? '').split(Platform.pathSeparator);
    for (final String directory in pathEntries) {
      final String candidate = '$directory${Platform.pathSeparator}dart';
      if (File(candidate).existsSync() && File(candidate).lengthSync() > 0) {
        return candidate;
      }
    }
    throw StateError('找不到 dart 可执行文件（FLUTTER_ROOT=${flutterRoot ?? "未设置"}）');
  }

  /// 跑一次真实 CLI；去掉代理变量，避免宿主机代理干扰任何 dart 启动流程。
  Future<ProcessResult> runCli(List<String> args) async {
    final Map<String, String> environment =
        Map<String, String>.from(Platform.environment);
    for (final String key in <String>[
      'HTTP_PROXY',
      'HTTPS_PROXY',
      'http_proxy',
      'https_proxy',
    ]) {
      environment.remove(key);
    }
    environment['NO_PROXY'] = '127.0.0.1,localhost';

    return Process.run(
      resolveDartExecutable(),
      <String>['tool/issue_redeem_code.dart', ...args],
      workingDirectory: Directory.current.path,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// 注册临时路径；顶层目录（第 2 参数）会被递归删除。
  void trackPath(String path, String topLevelDir) {
    tempPaths.add(path);
    tempPaths.add(topLevelDir);
  }

  test('--out 写出可解析的 JSON：serial 正确、code 为 92 字符无空格原码', () async {
    const String top = 'build/redeem_code_out_test';
    const String path = '$top/codes.json';
    trackPath(path, top);

    final ProcessResult result = await runCli(<String>[
      '--serial',
      '1001',
      '--count',
      '3',
      '--private-key',
      privateKeyBase64,
      '--out',
      path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr as String);

    final List<dynamic> rows =
        jsonDecode(await File(path).readAsString()) as List<dynamic>;
    expect(rows, hasLength(3));
    for (int i = 0; i < rows.length; i++) {
      final Map<String, dynamic> row = rows[i] as Map<String, dynamic>;
      expect(row.keys.toSet(), <String>{'serial', 'code'});
      expect(row['serial'], 1001 + i);

      final String code = row['code'] as String;
      expect(code, hasLength(92));
      expect(code, isNot(contains(' ')));
      // `-` 是 Base64URL 的数据字符，必须原样保留；其余字符集也一并锁住。
      expect(RegExp(r'^[A-Za-z0-9_-]{92}$').hasMatch(code), isTrue);

      // 92 字符解回 69 字节：5 字节 payload 里的 serial 应与 JSON 字段一致。
      final List<int> binary = base64Url.decode(base64Url.normalize(code));
      expect(binary, hasLength(69));
      expect(binary.first, 1); // 版本字节
      final int serial = row['serial'] as int;
      expect(
        binary.sublist(1, 5),
        <int>[
          (serial >> 24) & 0xFF,
          (serial >> 16) & 0xFF,
          (serial >> 8) & 0xFF,
          serial & 0xFF,
        ],
      );
    }
  });

  test('--out 自动创建父目录，stdout 只有一行摘要且不泄露码', () async {
    const String top = 'build/redeem_code_out_deep_test';
    const String path = '$top/a/b/codes.json';
    trackPath(path, top);
    // 上一次超时运行可能留下残留目录，先清干净再验证「自动创建」。
    if (Directory(top).existsSync()) {
      await Directory(top).delete(recursive: true);
    }
    expect(Directory(top).existsSync(), isFalse);

    final ProcessResult result = await runCli(<String>[
      '--serial',
      '1001',
      '--count',
      '2',
      '--private-key',
      privateKeyBase64,
      '--out',
      path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(File(path).existsSync(), isTrue);

    final String stdout = (result.stdout as String).trim();
    final List<String> lines =
        stdout.split('\n').where((String l) => l.trim().isNotEmpty).toList();
    expect(lines, hasLength(1));
    expect(lines.single, contains('已签发 2 枚激活码'));
    expect(lines.single, contains('serial 1001 .. 1002'));
    expect(lines.single, contains(path));

    final List<dynamic> rows =
        jsonDecode(await File(path).readAsString()) as List<dynamic>;
    for (final dynamic row in rows) {
      expect(stdout, isNot(contains((row as Map<String, dynamic>)['code'])));
    }
  });

  test('不带 --out 时 stdout 仍是人类可读分组文本（向后兼容）', () async {
    final ProcessResult result = await runCli(<String>[
      '--serial',
      '1',
      '--count',
      '2',
      '--private-key',
      privateKeyBase64,
    ]);
    expect(result.exitCode, 0, reason: result.stderr as String);

    final String stdout = result.stdout as String;
    expect(stdout, contains('公钥（应与 redeem_public_key.dart 一致）：'));
    expect(stdout, contains('共签发 2 枚（serial 1 .. 2）：'));
    // 92 字符按每 23 字符插一个空格 → 4 组，且分组符是空格而非 `-`。
    expect(
      RegExp(
        r'^serial\s+1\s{2}([A-Za-z0-9_-]{23} ){3}[A-Za-z0-9_-]{23}$',
        multiLine: true,
      ).hasMatch(stdout),
      isTrue,
      reason: stdout,
    );
    expect(stdout, contains('提示：以上分组里的空格只是给人看的'));
  });

  test('--out 写文件失败时退出码为 2，且给出清晰错误', () async {
    const String top = 'build/redeem_code_out_error_test';
    const String blocker = '$top/not-a-directory';
    const String path = '$blocker/codes.json';
    trackPath(blocker, top);
    if (Directory(top).existsSync()) {
      await Directory(top).delete(recursive: true);
    }
    await Directory(top).create(recursive: true);
    await File(blocker).writeAsString('我是文件，不是目录');

    final ProcessResult result = await runCli(<String>[
      '--serial',
      '1001',
      '--count',
      '1',
      '--private-key',
      privateKeyBase64,
      '--out',
      path,
    ]);
    expect(result.exitCode, 2, reason: result.stdout as String);
    expect(result.stderr, contains('写文件失败：'));
    expect(result.stderr, contains(path));
    expect(result.stdout, isNot(contains('已签发')));
  });

  test('--help 文档包含 --out', () async {
    final ProcessResult result = await runCli(<String>['--help']);
    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(result.stdout, contains('--out <path>'));
    expect(result.stdout, contains('写 UTF-8 JSON 数组'));
  });
}
