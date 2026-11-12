// 宝箱开箱序列帧 + 开箱音效资产护栏（T02 素材管线批次，2026-11-11 玄参交付）。
//
// 为什么存在：本项目三次吃过「资产静默回退」的亏 —— ①AssetManifest.json 失效；
// ②序列帧目录名/帧数与代码常量漂移（2026-09-28 fx/grow 翻车：只登记父目录 →
// 帧根本没进包 → Image.asset errorBuilder 静默吞 → 真机「只剩音效没有动画」）；
// ③音频过短在 iOS 上 just_audio 抛 CoreAudio -11849 被静默吞 → 无声无日志。
// 本测试直读文件系统 + 用引擎真解码 WebP + 逐帧累加 mp3 时长，把「素材契约」钉死：
// 目录名、帧数、帧名（frame001..030 三位零填充）、每帧 512×512、静态展示帧存在、
// 音效存在且时长 ≥3s、pubspec 两个叶子目录都已登记 —— 任何一处漂移测试即红。
//
// 直读文件系统是刻意的（不走 AssetManifest）：这些契约是「磁盘上有什么文件」。
// 解码走 `dart:ui` 的 `instantiateImageCodec`（WebP 由引擎解码）而不是手写 WebP 头
// 解析：Canvas 真能画出来才算数 —— 头合法但 chunk 结构不被引擎支持的 WebP 也能被抓到。
//
// 口径来源 `docs/花园守卫_宝箱与结算演出_增量设计_v1.md` §6（素材管线）。
// 转换管线：`tools/convert_guard_chest.py`（512²，普通 q90 / 高级 q80，合计 ≤8MB）。
library guard_chest_assets_guard_test;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';

import '../helpers/mp3_probe.dart';

// ── 契约常量的唯一真源在 `lib/core/constants/prd_params.dart`（T03 落地）──
// 下面四个是**引用别名**（`const x = kGuardChest…`），不是字符串副本：
// 改常量即等于改本测试，不存在「测试里写着 30、代码里写着 29」的漂移。
// 具体字面量另有 A-00 用 `expect` 钉死（防「改了常量忘了移目录」）。

/// 普通宝箱帧目录（= `kGuardChestNormalDir`，与 `resolveFxFrames` 同一字符串）。
const String kChestNormalDir = kGuardChestNormalDir;

/// 高级宝箱帧目录（= `kGuardChestPremiumDir`）。
const String kChestPremiumDir = kGuardChestPremiumDir;

/// 每档帧数（= `kGuardChestFrameCount`；30 帧摊 5s ⇒ 6fps，§6.4）。
const int kChestFrameCount = kGuardChestFrameCount;

/// 帧扩展名（= `kGuardChestFrameExt`；WebP q90/q80 有损，保留 alpha）。
const String kChestFrameExt = kGuardChestFrameExt;

/// 每帧画布边长（源 720² → 统一 512²，**保方形不裁边**，§6.2）。
/// 素材属性、非代码常量，故只住在本护栏里。
const int kChestFrameEdge = 512;

/// 开箱音效（= `AudioCue.guardChestOpen` 的映射路径；原样拷贝，实测 5.198333s）。
final String kChestOpenSfx = AudioCue.guardChestOpen.assetPath;

/// 开箱音效实测时长（秒），容差见下方断言。
const double kChestOpenSfxSeconds = 5.198333;

/// 宝箱两目录体积预算（守卫素材单批 8MB，§6.2）。
const int kChestBudgetBytes = 8 * 1024 * 1024;

String _projectRoot() {
  // 测试从 <root>/test/m3/ 运行，工程根 = 当前目录向上两层。
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/m3') || cwd.endsWith('\\test\\m3')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  final String root = _projectRoot();

  /// 目录下**全部条目**的文件名（含非目标扩展名，用于「无多余文件」断言），升序。
  List<String> allEntries(String relDir) {
    final Directory dir = Directory('$root/$relDir');
    expect(dir.existsSync(), isTrue, reason: '目录缺失：$relDir');
    return dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
  }

  /// 契约帧名清单：frame001..frame030.webp（三位零填充，从 001 起）。
  List<String> expectedFrames() => <String>[
        for (int i = 1; i <= kChestFrameCount; i++)
          'frame${i.toString().padLeft(3, '0')}.$kChestFrameExt',
      ];

  group('A-00 契约常量钉子（lib 常量 / 磁盘目录 / 音效枚举 三者对齐）', () {
    test('帧目录名、帧数、扩展名的字面量未被静默改动', () {
      // 上层的四个别名是「引用」，所以常量被改了测试会跟着改（不红）——
      // 因此这里把**字面量**再钉一遍：改常量等于改素材契约，必须同时移目录/换素材。
      expect(kGuardChestNormalDir, 'assets/guard/chest_normal');
      expect(kGuardChestPremiumDir, 'assets/guard/chest_premium');
      expect(kGuardChestFrameCount, 30);
      expect(kGuardChestFrameExt, 'webp');
    });

    test('两个目录常量指向的目录真实存在（改常量却没移目录 = 静默白屏）', () {
      for (final String dir in <String>[kGuardChestNormalDir, kGuardChestPremiumDir]) {
        expect(Directory('$root/$dir').existsSync(), isTrue,
            reason: '常量指向的目录不存在：$dir —— '
                '改 kGuardChest*Dir 必须同时搬目录 + 改 pubspec');
      }
    });
  });

  group('A-01 帧数与命名契约（两档各 30 帧，frame001..030.webp，无多余文件）', () {
    for (final String dir in <String>[kChestNormalDir, kChestPremiumDir]) {
      test('$dir：恰好 $kChestFrameCount 张、命名连续、目录里没有多余文件', () {
        final List<String> entries = allEntries(dir);
        final List<String> expected = expectedFrames();
        // 整表相等：既抓「缺帧/断号」，也抓「多了别的文件」（比如误把 PNG 源丢进来，
        // 或换了素材忘了跑 tools/convert_guard_chest.py）。
        expect(entries, expected,
            reason: '$dir 目录内容与契约不符（应恰好 ${expected.first} .. '
                '${expected.last}，共 $kChestFrameCount 个文件）');
      });
    }
  });

  group('A-02 画布尺寸契约（引擎真解码，每帧恰好 512×512）', () {
    for (final String dir in <String>[kChestNormalDir, kChestPremiumDir]) {
      test('$dir：全部帧解码后均为 $kChestFrameEdge×$kChestFrameEdge', () async {
        final List<String> names = allEntries(dir);
        for (final String name in names) {
          final (int w, int h) = await _decodeSize(File('$root/$dir/$name'));
          expect(w, kChestFrameEdge, reason: '$dir/$name 宽漂移（应 $kChestFrameEdge）');
          expect(h, kChestFrameEdge, reason: '$dir/$name 高漂移（应 $kChestFrameEdge）');
        }
      });
    }
  });

  group('A-03 静态展示帧（frame001 = 合盖宝箱「掉落在地上」用图，§6.3）', () {
    for (final String dir in <String>[kChestNormalDir, kChestPremiumDir]) {
      test('$dir/frame001.$kChestFrameExt 存在且是字典序第一张（与取帧口径一致）',
          () async {
        final File first = File('$root/$dir/frame001.$kChestFrameExt');
        expect(first.existsSync(), isTrue,
            reason: '缺静态展示帧（掉落中的宝箱靠它渲染）：'
                '$dir/frame001.$kChestFrameExt');
        // `resolveFxFrames` 排序后取第 0 张当静图，所以「静图 == 动画首帧」
        // 的前提是 frame001 就是字典序第一 —— 这条防「静态帧与动画首帧不是同一张，
        // 点击切入动画时会跳变」。
        final List<String> entries = allEntries(dir);
        expect(entries.first, 'frame001.$kChestFrameExt',
            reason: '$dir 字典序第一张应为 frame001.$kChestFrameExt（静图零跳变前提）');
        expect(await _decodeSize(first), (kChestFrameEdge, kChestFrameEdge),
            reason: '静态展示帧尺寸须与动画帧一致（否则切入动画会缩放跳变）');
      });
    }
  });

  group('A-04 开箱音效（存在 + 逐帧累计时长 ≥3s 且 ≈5.198s）', () {
    test('$kChestOpenSfx 存在、实测时长 ≈ ${kChestOpenSfxSeconds}s 且过 ≥3s 红线', () {
      final File f = File('$root/$kChestOpenSfx');
      expect(f.existsSync(), isTrue, reason: '缺开箱音效：$kChestOpenSfx');

      late final double seconds;
      try {
        seconds = mp3DurationSeconds(f.readAsBytesSync());
      } on FormatException catch (e) {
        fail('MPEG 帧头解析失败（不静默跳过）：$kChestOpenSfx → ${e.message}');
      }
      final String shown = seconds.toStringAsFixed(3);
      // ignore: avoid_print
      print('  实测 $kChestOpenSfx = ${shown}s');
      // ≥3s 红线（F77 实证：过短 mp3 在 iOS 上 just_audio setAsset 抛 CoreAudio
      // -11849，异常被 AudioService 静默吞 → 无声无日志）。
      expect(seconds, greaterThanOrEqualTo(3.0),
          reason: '$kChestOpenSfx 实测 ${shown}s < 3.0s 红线（iOS CoreAudio -11849 风险）');
      // 与素材实测值对齐（容差 0.10s）：逐帧累计读数与容器读数有几十毫秒差异，
      // 只要能抓住「换错素材 / 误做 apad / 被重编码」即可。
      expect((seconds - kChestOpenSfxSeconds).abs(), lessThan(0.10),
          reason: '$kChestOpenSfx 实测 ${shown}s ≠ ${kChestOpenSfxSeconds}s —— '
              '素材被换了或被转码（本应是原样拷贝，不做 apad）');
    });
  });

  group('A-05 pubspec 资产登记（⚠️ 目录声明不递归，两个叶子目录各占一行）', () {
    test('chest_normal / chest_premium 都以「    - <dir>/」精确串登记', () {
      // 2026-09-28 实证翻车：只登记父目录（assets/fx/grow/）→ 帧全在更深一层子目录
      // → 帧根本没进包，真机「只剩音效没有动画」。`assets/guard/` 那一行**不覆盖**
      // 其子目录，故两档必须各有一行。
      final String pubspec = File('$root/pubspec.yaml').readAsStringSync();
      for (final String dir in <String>[kChestNormalDir, kChestPremiumDir]) {
        expect(pubspec.contains('    - $dir/'), isTrue,
            reason: 'pubspec 必须登记叶子目录「$dir/」——'
                'Flutter 目录声明不递归，漏登记 = 帧静默不进包');
      }
      // 音效目录已在册（B5b 之前就登记过），本批不重复登记；断言它确实在册，
      // 防「有人整理 pubspec 时把这行挪走」导致宝箱音效静默丢失。
      expect(pubspec.contains('    - assets/audio/sfx/'), isTrue,
          reason: 'pubspec 须登记 assets/audio/sfx/（开箱音效所在目录）');
    });
  });

  group('A-06 AudioCue 映射（枚举由 T03 落地，此处只钉映射与文件存在性）', () {
    test('AudioCue.guardChestOpen → assets/audio/sfx/guard_chest_open.mp3 且文件真实存在', () {
      // 依据 §9.3 第 4 条：headless 环境音频静默降级，**只查映射与资产存在性**，
      // 不查实际播放（播放由 T03 的演出用例 + 真机验收覆盖）。
      expect(AudioCue.guardChestOpen.assetPath,
          'assets/audio/sfx/guard_chest_open.mp3');
      expect(File('$root/${AudioCue.guardChestOpen.assetPath}').existsSync(), isTrue,
          reason: '缺音频文件：${AudioCue.guardChestOpen.assetPath}');
    });

    test('AudioCue.guardChestLand → assets/audio/sfx/guard_chest_land.mp3、'
        '存在且 ≥3s 红线、实测 ≈ 3.208s', () {
      // 落地音效（2026-11-12 玄参交付，源 1.358s ⇒ apad 补静音到 3.208s）：
      // 源本身过短，**必须**过 ≥3s 红线，否则 iOS 上无声无日志（同 F77 机理）。
      // 与开箱音效不同：这条**是** apad 过的（尾部 1.85s 静音），所以时长断言
      // 钉的是「补完后的 3.208」——若有人拿未补静音的 1.358s 原文件覆盖进来，
      // 本用例立即红。
      const String path = 'assets/audio/sfx/guard_chest_land.mp3';
      expect(AudioCue.guardChestLand.assetPath, path);
      final File f = File('$root/$path');
      expect(f.existsSync(), isTrue, reason: '缺落地音效：$path');

      late final double seconds;
      try {
        seconds = mp3DurationSeconds(f.readAsBytesSync());
      } on FormatException catch (e) {
        fail('MPEG 帧头解析失败（不静默跳过）：$path → ${e.message}');
      }
      final String shown = seconds.toStringAsFixed(3);
      // ignore: avoid_print
      print('  实测 $path = ${shown}s');
      expect(seconds, greaterThanOrEqualTo(3.0),
          reason: '$path 实测 ${shown}s < 3.0s 红线（iOS CoreAudio -11849 风险）');
      expect((seconds - 3.208).abs(), lessThan(0.10),
          reason: '$path 实测 ${shown}s ≠ ≈3.208s —— '
              '可能被换成了未 apad 的 1.358s 原文件（那样 iOS 上听不见）');
    });
  });

  group('A-07 两档一致性 + 体积预算（防「只补了普通没补高级」/ 忘了跑管线）', () {
    test('两档帧数一致且都等于 $kChestFrameCount', () {
      final int normal = allEntries(kChestNormalDir).length;
      final int premium = allEntries(kChestPremiumDir).length;
      expect(normal, kChestFrameCount, reason: '普通宝箱帧数应为 $kChestFrameCount');
      expect(premium, kChestFrameCount, reason: '高级宝箱帧数应为 $kChestFrameCount');
      expect(normal, premium, reason: '两档帧数必须一致（否则演出时长错位）');
    });

    test('跨目录逐帧对位：同名帧解码尺寸必须完全相同（防只重导其中一个档）', () async {
      // 为什么要有这条：两档共用同一个播放器、同一个 `durationMs`、同一套
      // 「30 帧摊 5s」的帧速推导 —— 帧数错位会让两档演出时长不同（上面那条已护住），
      // 而**尺寸错位**更阴：`BoxFit.contain` 下不同画布会让宝箱在屏幕上大小跳变，
      // 且只在「某次只重导了高级/只重导了普通」时出现，肉眼很难归因。
      // ⇒ 逐帧对位比对（不是只比 512 这个常量）：即便将来统一改成 480，
      //   只要两档一起改，本用例仍绿；只改一档即红。
      final List<String> normalNames = allEntries(kChestNormalDir);
      final List<String> premiumNames = allEntries(kChestPremiumDir);
      expect(normalNames, premiumNames,
          reason: '两档的帧文件清单必须完全一致（同名同序），否则对位比对无意义');
      for (final String name in normalNames) {
        final (int nw, int nh) = await _decodeSize(File('$root/$kChestNormalDir/$name'));
        final (int pw, int ph) = await _decodeSize(File('$root/$kChestPremiumDir/$name'));
        expect((nw, nh), (pw, ph),
            reason: '帧 $name 两档尺寸不一致（普通 $nw×$nh vs 高级 $pw×$ph）——'
                '只重导了其中一个档？重跑 tools/convert_guard_chest.py --apply');
      }
    });

    test('两目录合计体积 ≤ ${kChestBudgetBytes ~/ (1024 * 1024)}MB（§6.2 预算）', () {
      int total = 0;
      final Map<String, int> perDir = <String, int>{};
      for (final String dir in <String>[kChestNormalDir, kChestPremiumDir]) {
        int dirBytes = 0;
        for (final String name in allEntries(dir)) {
          dirBytes += File('$root/$dir/$name').lengthSync();
        }
        perDir[dir] = dirBytes;
        total += dirBytes;
      }
      // ignore: avoid_print
      print('  体积：${perDir[kChestNormalDir]! ~/ 1024}KB (normal) + '
          '${perDir[kChestPremiumDir]! ~/ 1024}KB (premium) = '
          '${(total / 1048576).toStringAsFixed(2)}MB');
      // 超预算的典型原因是「换了素材却忘了跑 tools/convert_guard_chest.py」
      // （720 q90 高级宝箱一组就 12MB）。降级方案见脚本头注释。
      expect(total, lessThanOrEqualTo(kChestBudgetBytes),
          reason: '宝箱两目录合计 ${(total / 1048576).toStringAsFixed(2)}MB 超 '
              '${kChestBudgetBytes ~/ (1024 * 1024)}MB 预算 —— 重跑 '
              'tools/convert_guard_chest.py（--normal-q / --edge 可降级）');
    });
  });
}

/// 用引擎解码一张图并返回 `(宽, 高)`；解码失败抛异常（不静默跳过）。
///
/// WebP 走 `dart:ui` 引擎解码（`instantiateImageCodec`），断言的是「Canvas 真能画出
/// 这个尺寸」而不是「头里的数字写着 512」—— 头合法但引擎不支持的封装也会在这里暴露。
Future<(int, int)> _decodeSize(File f) async {
  final Uint8List bytes = f.readAsBytesSync();
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final (int, int) size = (image.width, image.height);
  image.dispose();
  codec.dispose();
  return size;
}
