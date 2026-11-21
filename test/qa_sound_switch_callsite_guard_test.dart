/// QA 独立差分复验 · 静音开关「只管收集阳光」调用点守卫（严过关 / 独立编写）。
///
/// 🔴 为什么需要本文件（防假绿头号陷阱）：
/// `test/audio_service_test.dart` 的行为级用例是**直接**调用
/// `svc.playSfx(AudioCue.focusCollect, respectSoundSwitch: true)` —— 它验证了
/// 「服务层闸门正确」，但**完全不经过真实生产调用点 `focus_page.dart`**。
/// 若有人把 focus_page 里的 `respectSoundSwitch: true` 删掉（受控变异 M-B），
/// 那些用例会**全部照旧全绿**（假绿），而线上「关音效仍响收集阳光」随即复现。
///
/// 本文件用「源码结构守卫」钉死三件事（注释一律剥离后再断言，防注释字面量误伤）：
///  ① 服务层两个闸门必须是 `respectSoundSwitch && !_soundOn` 的 opt-in 形式，
///     绝不能回退成 `!_soundOn` 一刀切（受控变异 M-A → 本文件转红）；
///  ② 三个入口 `respectSoundSwitch` 默认值必须是 false（默认不受管）；
///  ③ 全 lib 目录里 `respectSoundSwitch: true` **有且仅有一处**，且就在
///     `focus_page.dart` 的 lvl2 收集阳光分支（受控变异 M-B → 本文件转红）。
///
/// 所有期望值独立写死为字面量，绝不 import 被测常量自证。
library qa_sound_switch_callsite_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _root() {
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test') || cwd.endsWith('\\test')
      ? Directory.current.parent.path
      : cwd;
}

String _src(String rel) => File('${_root()}/$rel').readAsStringSync();

/// 去掉 `//` 行注释与 `/* */` 块注释，只留代码（避免文档里的字面量让守卫假绿）。
String _codeOnly(String src) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < src.length) {
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

/// 截取 [from] 起到 [to] 之前的源码片段（找不到边界返回空串，便于断言失败定位）。
String _between(String src, String from, String to) {
  final int a = src.indexOf(from);
  if (a < 0) return '';
  final int b = to.isEmpty ? src.length : src.indexOf(to, a + from.length);
  return b < 0 ? src.substring(a) : src.substring(a, b);
}

void main() {
  final String audio = _codeOnly(_src('lib/platform/audio_service.dart'));
  final String focus = _codeOnly(
    _src('lib/presentation/child/pages/focus_page.dart'),
  );

  group('QA-静音 A · 服务层闸门 opt-in 语义（M-A 一刀切回退必转红）', () {
    test('playSfxPaths 闸门 = respectSoundSwitch && !_soundOn，且无 !_soundOn 一刀切', () {
      final String block = _between(
        audio,
        'void playSfxPaths(',
        'void playSfxOverlap(',
      );
      expect(block, isNotEmpty, reason: '必须定位到 playSfxPaths 实现');
      expect(
        block,
        contains('if ((respectSoundSwitch && !_soundOn) || paths.isEmpty) return;'),
        reason: '闸门必须保留 respectSoundSwitch 前置条件：只有 opt-in 才受管',
      );
      expect(
        block,
        isNot(contains('if (!_soundOn ||')),
        reason: 'M-A：改回 !_soundOn 一刀切会把所有 SFX 一起掐掉，必须转红',
      );
      expect(
        block,
        isNot(contains('_bgmOn')),
        reason: '音效开关不得引用 bgmOn（背景音开关只管背景类音频）',
      );
    });

    test('playSfxOverlap 闸门 = respectSoundSwitch && !_soundOn（战斗音默认不受管）', () {
      final String block = _between(
        audio,
        'void playSfxOverlap(',
        'static int pickSfxPoolSlot(',
      );
      expect(block, isNotEmpty, reason: '必须定位到 playSfxOverlap 实现');
      expect(
        block,
        contains('if (respectSoundSwitch && !_soundOn) return;'),
        reason: '叠加池通道同样只允许 opt-in 受管',
      );
      expect(
        block,
        isNot(contains('if (!_soundOn) return;')),
        reason: 'M-A 变体：叠加池改回一刀切必须转红',
      );
    });

    test('三个入口 respectSoundSwitch 默认值均为 false（默认不受管）', () {
      // 代码里默认形参写法固定为 `bool respectSoundSwitch = false,`。
      final int defaults =
          audio.split('bool respectSoundSwitch = false,').length - 1;
      expect(
        defaults,
        3,
        reason: 'playSfx / playSfxPaths / playSfxOverlap 三处默认 false，缺一即语义漂移',
      );
      expect(
        audio,
        isNot(contains('bool respectSoundSwitch = true')),
        reason: '绝不允许默认 opt-in',
      );
    });
  });

  group('QA-静音 B · 生产调用点 opt-in 唯一性（M-B 删 true 必转红）', () {
    test('focus_page lvl2 收集阳光分支显式传 respectSoundSwitch: true', () {
      final String lvl2 = _between(
        focus,
        'case FeedbackLevel.lvl2:',
        'case FeedbackLevel.lvl3:',
      );
      expect(lvl2, isNotEmpty, reason: '必须定位到 lvl2 收集阳光分支');
      expect(lvl2, contains('AudioCue.focusCollect'));
      expect(
        lvl2,
        contains('respectSoundSwitch: true'),
        reason: 'M-B：删掉这一行后，关音效时收集阳光音将照常播放（唯一受管点丢失）',
      );
    });

    test('全 lib 中 respectSoundSwitch: true 有且仅有一处，且位于 focus_page.dart', () {
      final List<File> hits = <File>[];
      final Directory libDir = Directory('${_root()}/lib');
      for (final FileSystemEntity e in libDir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String code = _codeOnly(e.readAsStringSync());
        if (code.contains('respectSoundSwitch: true')) hits.add(e);
      }
      expect(
        hits.length,
        1,
        reason: '唯一受管点必须是 focusCollect；多一处 opt-in 就会误静音其它音效',
      );
      expect(
        hits.single.path.replaceAll('\\', '/').endsWith(
          'lib/presentation/child/pages/focus_page.dart',
        ),
        isTrue,
        reason: '唯一 opt-in 必须在 focus_page.dart',
      );
    });

    test('focus_page 其它反馈档（lvl3 欢迎回来 / lvl4 唤醒）不得 opt-in', () {
      final String other = _between(
        focus,
        'case FeedbackLevel.lvl3:',
        'void _pulseParticle(',
      );
      expect(other, contains('AudioCue.welcomeBack'));
      expect(other, contains('AudioCue.wake'));
      expect(
        other,
        isNot(contains('respectSoundSwitch: true')),
        reason: '欢迎回来 / 唤醒属于「其余 SFX」，关闭音效后必须照常播放',
      );
    });
  });
}
