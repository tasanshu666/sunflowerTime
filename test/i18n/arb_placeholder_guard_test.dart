/// ARB 占位符**三方一致**守卫（i18n B3 · T01）。
///
/// ## 为什么需要它
/// Flutter 的 `gen-l10n` 对 `{x}` 占位符有两条**静默失败**路径：
///  ① 缺 `@key.placeholders` → 参数被推成 `Object`，**类型不校验、顺序按字母序**，
///     调用方传反了照样编译通过，只是文案把两个值换了个位置（B1 批次栽过 6 次）；
///  ② 有 `@key.placeholders` 但声明顺序与「生成签名里的参数顺序」不一致 → 同理静默错位。
///
/// 本守卫把「ARB 内部自洽」与「ARB ↔ 生成代码一致」两件事同时钉死：
///  · **a**：每条 message 的 `{x}` 集合 ≥ 1 个时，必须有 `@key.placeholders`，
///    且 key 集合**完全相等**；zh / en 同一 key 集合、同一占位符集合，每个
///    placeholder 必须写 `type`；
///  · **b**：解析 `lib/l10n/generated/app_localizations.dart` 里 `String <key>(...)`
///    的**参数名序列**，断言 == `@key.placeholders` 的声明顺序。
///
/// 🔴 允许例外：`type: Object` 的历史 key（B1/B2 遗留）不参与「类型」比对，
/// 但**必须**参与「name 与顺序」比对 —— 顺序错位才是真正的静默 bug。
library arb_placeholder_guard_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _zhPath = 'lib/l10n/app_zh.arb';
const String _enPath = 'lib/l10n/app_en.arb';
const String _genPath = 'lib/l10n/generated/app_localizations.dart';

/// 正则：ARB 消息体里的 ICU 占位符 `{name}`（不含 plural 的 `{count, plural, ...}`）。
final RegExp _placeholderRe = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 某条 ARB 消息里出现的占位符名字集合。
Set<String> _usedPlaceholders(String message) =>
    _placeholderRe.allMatches(message).map((RegExpMatch m) => m.group(1)!).toSet();

/// 某条消息的 `@key.placeholders` **声明顺序**（无声明 → 空列表）。
List<String> _declaredOrder(Map<String, dynamic> arb, String key) {
  final Object? meta = arb['@$key'];
  if (meta is! Map<String, dynamic>) return <String>[];
  final Object? holders = meta['placeholders'];
  if (holders is! Map<String, dynamic>) return <String>[];
  // jsonDecode 得到 LinkedHashMap：保持 ARB 文件里的字面顺序。
  return holders.keys.toList();
}

/// 某条消息每个占位符的 type（未写 type → null）。
Map<String, String?> _declaredTypes(Map<String, dynamic> arb, String key) {
  final Object? meta = arb['@$key'];
  if (meta is! Map<String, dynamic>) return <String, String?>{};
  final Object? holders = meta['placeholders'];
  if (holders is! Map<String, dynamic>) return <String, String?>{};
  return holders.map((String name, Object? spec) {
    final Object? type = spec is Map<String, dynamic> ? spec['type'] : null;
    return MapEntry<String, String?>(name, type is String ? type : null);
  });
}

/// 从生成代码里取 `String <key>(<params>)` 的**参数名序列**；getter / 不存在 → null。
List<String>? _generatedParamOrder(String src, String key) {
  final RegExp re = RegExp(
    r'String\s+' + RegExp.escape(key) + r'\s*\(([^)]*)\)\s*;',
  );
  final RegExpMatch? m = re.firstMatch(src);
  if (m == null) return null;
  final String raw = m.group(1)!.trim();
  if (raw.isEmpty) return <String>[];
  return raw.split(',').map((String part) {
    // `int minutes` / `String duration` → 取最后一个标识符段。
    final List<String> tokens = part.trim().split(RegExp(r'\s+'));
    return tokens.last;
  }).toList();
}

void main() {
  final Map<String, dynamic> zh = _load(_zhPath);
  final Map<String, dynamic> en = _load(_enPath);
  final String gen = File(_genPath).readAsStringSync();

  /// 全部 message key（去掉 `@@locale` 与所有 `@meta`）。
  final List<String> zhKeys = zh.keys
      .where((String k) => !k.startsWith('@'))
      .toList(growable: false);
  final List<String> enKeys = en.keys
      .where((String k) => !k.startsWith('@'))
      .toList(growable: false);

  group('a) ARB 内部自洽（zh / en 同键集 + 占位符必须声明）', () {
    test('zh / en message key 集合完全一致（对称，不缺不冗）', () {
      expect(zhKeys.toSet(), enKeys.toSet(),
          reason: 'zh 与 en 必须同 key 集合 —— 缺一条会在英文环境回落中文');
      expect(zhKeys.length, enKeys.length);
    });

    for (final String key in zhKeys) {
      test('$key：占位符与 @placeholders 完全对齐', () {
        final String zhMsg = zh[key] as String;
        final String enMsg = en[key] as String;
        final Set<String> zhUsed = _usedPlaceholders(zhMsg);
        final Set<String> enUsed = _usedPlaceholders(enMsg);
        final List<String> declared = _declaredOrder(zh, key);

        expect(enUsed, zhUsed,
            reason: '$key：zh / en 占位符集合必须一致（否则一面插值、一面死文）');

        if (zhUsed.isEmpty) {
          // 无占位符的 message：不要求 @meta；若写了就必须是空声明。
          if (declared.isNotEmpty) {
            fail('$key：无占位符却声明了 @placeholders $declared');
          }
          return;
        }

        // ① 有占位符 → 必须有 @key.placeholders。
        expect(declared, isNotEmpty,
            reason: '$key：消息含 $zhUsed，缺 @$key.placeholders '
                '→ gen-l10n 会把参数推成 Object，顺序/类型全不校验（静默错位）');

        // ② key 集合完全相等（不多不少）。
        expect(declared.toSet(), zhUsed,
            reason: '$key：@placeholders $declared 与消息 $zhUsed 必须一一对应');

        // ③ 每个占位符必须有 type。
        final Map<String, String?> types = _declaredTypes(zh, key);
        for (final String name in zhUsed) {
          expect(types[name], isNotNull,
              reason: '$key.$name：必须写 type（int/num/String），'
                  '否则生成签名落成 Object，静态类型检查全部失效');
        }

        // ④ en 侧同键集、同占位符集合（en 有自己的 @meta 时也要自洽）。
        final List<String> enDeclared = _declaredOrder(en, key);
        if (enDeclared.isNotEmpty) {
          expect(enDeclared.toSet(), enUsed,
              reason: '$key（en）：@placeholders 与消息占位符必须一一对应');
          final Map<String, String?> enTypes = _declaredTypes(en, key);
          for (final String name in enUsed) {
            expect(enTypes[name], isNotNull,
                reason: '$key.$name（en）：必须写 type');
          }
        }
      });
    }
  });

  group('b) ARB ↔ 生成签名（参数名顺序必须逐位相等）', () {
    for (final String key in zhKeys) {
      final Set<String> used = _usedPlaceholders(zh[key] as String);
      if (used.isEmpty) continue;

      test('$key：生成签名参数顺序 == @placeholders 声明顺序', () {
        final List<String>? generated = _generatedParamOrder(gen, key);
        expect(generated, isNotNull,
            reason: '$key 在 $_genPath 里找不到 String $key(...) —— '
                '要么 meta 缺失被推成 Object 且改名，要么 gen-l10n 未跑');
        final List<String> declared = _declaredOrder(zh, key);
        expect(generated, declared,
            reason: '$key：ARB 声明顺序 $declared ≠ 生成签名 $generated。'
                '🔴 类型全是 Object 时交换两个 Object 参数仍能编译，只输出错文案 —— '
                '这是 B1 栽过 6 次的坑，必须把 ARB 声明顺序改成生成顺序（字母序）');
      });
    }
  });

  group('c) 本批（B3）关键 key 的占位符类型硬断言', () {
    // 只钉「语义可错」的几条：int 与 String 混用处最容易静默传反。
    const Map<String, Map<String, String>> expectTypes = <String, Map<String, String>>{
      'child_settle_cap_orig_vs_net': <String, String>{
        'net': 'String',
        'raw': 'String',
      },
      'child_settle_task_done': <String, String>{
        'capped': 'String',
        'name': 'String',
        'sun': 'String',
      },
      'child_settle_cap_body_detail': <String, String>{
        'cheer': 'String',
        'detail': 'String',
      },
      'child_entry_remaining_today': <String, String>{
        'cap': 'int',
        'minutes': 'int',
      },
      'child_entry_remaining_snack': <String, String>{
        'minutes': 'int',
        'remaining': 'int',
      },
      'child_shell_task_footer_partial': <String, String>{
        'capped': 'int',
        'total': 'int',
      },
      'child_settle_min_sec': <String, String>{'min': 'int', 'sec': 'int'},
      'shared_level_gap_next': <String, String>{'n': 'int', 'duration': 'String'},
      'shared_level_gap_max': <String, String>{'title': 'String'},
      'shared_duration_hours_minutes': <String, String>{'h': 'int', 'm': 'int'},
      'shared_plant_err_water_interval': <String, String>{
        'interval': 'int',
        'wait': 'int',
      },
      'shared_plant_err_pot_out_of_capacity': <String, String>{
        'pot': 'int',
        'capacity': 'int',
      },
      'parent_report_bucket_week': <String, String>{'index': 'int'},
      'shared_perk_water_discount': <String, String>{'value': 'int'},
    };

    for (final MapEntry<String, Map<String, String>> entry in expectTypes.entries) {
      test('${entry.key}：占位符类型 = ${entry.value}', () {
        final Map<String, String?> actual = _declaredTypes(zh, entry.key);
        expect(actual, isNotEmpty, reason: '${entry.key} 缺 @placeholders');
        expect(actual, entry.value);
      });
    }
  });
}
