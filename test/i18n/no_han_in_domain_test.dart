/// `lib/domain/**` 注释外零 CJK 的常驻守卫（i18n B3 · T05 收口）。
///
/// ## 为什么这是硬门槛
/// 领域层里任何中文字符串都意味着「这个文案永远只有中文」—— 英文用户会看到混排，
/// 而编译器、单测、`flutter analyze` **全都不会报**。B3 批次把 domain 里的文案
/// （枚举 label / 属性摘要 / 时限模板 / 异常消息 / 种子名 / 权限名）逐条迁出后，
/// 这条门槛才第一次可以「零豁免」立起来。
///
/// ## 本文件守什么
/// ① **零豁免**：`tool/check_domain_cjk.py` 的白名单必须是空集（谁想加名字，先看下面 ③）；
/// ② **真扫全量**：逐文件扫 `lib/domain/**`，剥掉注释后不得残留 CJK；
/// ③ **变异验证（关键）**：把「中文 throw」写进临时样本 → 检测器**必须报红**。
///    没有这一步，②的通过只能证明「检测器可能坏了」。同理再用「只在注释里写中文」
///    的样本反向验证：不许把注释也算进去（否则守卫会拦下正常的文档）。
///
/// ⚠️ 扫描器在 Dart 侧**重现**了 Python 脚本的口径（`//` / `/* */` 剥离 + CJK 正则）。
/// 两份实现刻意独立：Python 脚本给人跑、本测试给 CI 跑，任何一边被改松都会在另一边
/// 露馅（测试里还断言了 Python 脚本的白名单为空，等于把两边钉在一起）。
library no_han_in_domain_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CJK 判定（统一表意文字 + 扩展 A + 兼容表意 + 全角标点）。
///
/// 与 `tool/check_domain_cjk.py` 的字符类一致：`\u3000-\u303F`（全角标点）、
/// `\u3400-\u4DBF`（扩展 A）、`\u4E00-\u9FFF`（基本区）、`\uF900-\uFAFF`（兼容）、
/// `\uFF00-\uFFEF`（全角 ASCII 变体，如「（）」）。
final RegExp _cjk = RegExp(
  r'[\u3000-\u303F\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]',
);

/// 剥掉 `//` 行注释与 `/* */` 块注释，返回「只剩代码」的文本（保留换行结构）。
///
/// 字符串字面量**不特殊处理**：字面量里的 `//` 会让本行后半被截掉，那只可能让
/// 检查更严（宁可误红，不可漏绿）—— 与 Python 脚本同口径。
String stripComments(String src) {
  final List<String> out = <String>[];
  bool inBlock = false;
  for (final String raw in src.split('\n')) {
    String line = raw;
    if (inBlock) {
      final int end = line.indexOf('*/');
      if (end < 0) {
        out.add('');
        continue;
      }
      line = line.substring(end + 2);
      inBlock = false;
    }
    final int lineComment = line.indexOf('//');
    final int blockComment = line.indexOf('/*');
    if (lineComment >= 0 && (blockComment < 0 || lineComment < blockComment)) {
      line = line.substring(0, lineComment);
    } else if (blockComment >= 0) {
      final int end = line.indexOf('*/', blockComment + 2);
      if (end < 0) {
        inBlock = true;
        line = line.substring(0, blockComment);
      } else {
        line = line.substring(0, blockComment) + line.substring(end + 2);
      }
    }
    out.add(line);
  }
  return out.join('\n');
}

/// 扫描一段源码，返回「非注释行里的 CJK 命中」（行号从 1 起 + 原文行）。
List<String> scanSource(String src) {
  final List<String> hits = <String>[];
  final List<String> lines = src.split('\n');
  final List<String> stripped = stripComments(src).split('\n');
  for (int i = 0; i < stripped.length && i < lines.length; i++) {
    if (_cjk.hasMatch(stripped[i])) {
      hits.add('${i + 1}: ${lines[i].trim()}');
    }
  }
  return hits;
}

void main() {
  // ─────────────────── ① 零豁免 ───────────────────
  test('① Python 自查脚本的白名单为空（不允许登记豁免）', () {
    final String script = File('tool/check_domain_cjk.py').readAsStringSync();
    expect(
      RegExp(r'EXEMPT_MSG_FILES\s*=\s*set\(\)').hasMatch(script),
      isTrue,
      reason: 'domain 零 CJK 是零豁免门槛；要加白名单请先推翻这条测试并说明理由',
    );
  });

  // ─────────────────── ② 真扫全量 ───────────────────
  test('② lib/domain/** 注释外零 CJK', () {
    final Directory domain = Directory('lib/domain');
    expect(domain.existsSync(), isTrue, reason: '测试 CWD 必须是仓库根');

    final List<File> files = domain
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    expect(files.length, greaterThan(30),
        reason: '文件数过少说明路径找错了（当前 ${files.length} 个）');

    final List<String> violations = <String>[];
    for (final File f in files) {
      for (final String hit in scanSource(f.readAsStringSync())) {
        violations.add('${f.path} → $hit');
      }
    }
    expect(
      violations,
      isEmpty,
      reason: '领域层注释外出现 CJK（文案必须迁 ARB / 走 core/i18n）：\n'
          '${violations.join('\n')}',
    );
  });

  // ─────────────────── ③ 变异验证（检测器不许失效）───────────────────
  group('③ 变异验证：检测器本身必须能报红', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('no_han_mutation');
      addTearDown(() => tmp.deleteSync(recursive: true));
    });

    test('往领域样本里塞中文 throw → 必须被检出（对应 `plant_growth_service` 场景）', () {
      final File f = File('${tmp.path}/plant_growth_service.dart')
        ..writeAsStringSync('''
/// 正常文档注释里可以写中文（说明「为什么」不算文案）。
String water() {
  throw StateError('浇水次数已用完');
}
''');
      final List<String> hits = scanSource(f.readAsStringSync());
      expect(hits, hasLength(1),
          reason: '中文 throw 必须被检出，否则「domain 零 CJK」的通过毫无意义');
      expect(hits.single.contains('浇水次数已用完'), isTrue);
    });

    test('多种写法都能抓到：单引号 / 双引号 / 插值 / 常量表', () {
      const String src = '''
const String a = '护眼';
const String b = "浇水";
String c(int n) => '还差 \$n 分钟';
const List<String> d = <String>['铲除'];
''';
      expect(scanSource(src), hasLength(4),
          reason: '字符串字面量的 4 种写法都要命中');
    });

    test('只在注释里的中文**不许**被误报（否则守卫会拦死正常文档）', () {
      const String src = '''
// 行注释：浇水
/// 文档注释：护眼 / 除虫
/* 块注释：施肥 */
String water() => 'water-proof';
''';
      expect(scanSource(src), isEmpty,
          reason: '注释不是文案；把注释算进去会让守卫变成噪音源');
    });

    test('全角标点也要命中（`（` / `，` 常混进中文串尾巴）', () {
      expect(scanSource("const String s = 'a（b';"), hasLength(1));
      expect(scanSource("const String s = 'a，b';"), hasLength(1));
    });

    test('纯 ASCII 代码零命中（反例：确认不是「永远报红」）', () {
      expect(
        scanSource("String f(int n) => 'level \$n done';"),
        isEmpty,
      );
    });
  });
}
