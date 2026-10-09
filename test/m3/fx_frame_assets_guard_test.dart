// 序列帧与音频资产护栏测试（玄参 2026-09-28 素材落地批；2026-09-29 增专注页向日葵帧）。
//
// 为什么存在：本项目两次吃过「资产静默回退」的亏（AssetManifest.json 失效、
// 序列帧目录名/帧数与代码常量漂移）。本测试直读文件系统与 PNG IHDR，
// 把「素材契约」钉死：目录名、帧数、帧名（frame001..N 三位零填充）、
// 音频文件存在性、植物图画布尺寸 —— 任何一处漂移测试即红。
//
// 直读文件系统是刻意的：这些契约是「磁盘上有什么文件」，不走 AssetManifest。
library fx_frame_assets_guard_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sunflower_time/core/constants/prd_params.dart';
import 'package:sunflower_time/platform/audio_service.dart';
import 'package:sunflower_time/presentation/child/widgets/frame_sequence_player.dart';

String _projectRoot() {
  // 测试从 <root>/test/m3/ 运行，工程根 = 当前目录向上两层。
  final String cwd = Directory.current.path;
  return cwd.endsWith('/test/m3') || cwd.endsWith('\\test\\m3')
      ? Directory.current.parent.parent.path
      : cwd;
}

void main() {
  final String root = _projectRoot();

  List<String> pngsOf(String relDir) {
    final Directory dir = Directory('$root/$relDir');
    expect(dir.existsSync(), isTrue, reason: '目录缺失：$relDir');
    return dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.path.split(Platform.pathSeparator).last)
        .where((String n) => n.endsWith('.png'))
        .toList()
      ..sort();
  }

  group('序列帧目录契约（frame001..N，三位零填充）', () {
    final List<String> dirs = <String>[
      growFxDir('sunflower', GrowTransition.seedToSprout),
      growFxDir('sunflower', GrowTransition.sproutToAdult),
      growFxDir('sunflower', GrowTransition.adultToBloomed),
      kCareWaterFxDir,
      kCareFertilizeFxDir,
    ];

    for (final String dir in dirs) {
      test('$dir：恰有 kFxFrameCount 张、文件名与 fxFrameAssets 契约一致', () {
        final List<String> files = pngsOf(dir);
        expect(files.length, kFxFrameCount,
            reason: '$dir 帧数应为 $kFxFrameCount，实际 ${files.length}');
        final List<String> expected = fxFrameAssets(dir, kFxFrameCount)
            .map((String p) => p.split('/').last)
            .toList();
        expect(files, expected, reason: '$dir 文件名与契约不符');
      });
    }

    test('fxFrameAssets：纯函数命名契约（三位零填充、从 001 起）', () {
      final List<String> got = fxFrameAssets('assets/fx/care/water', 3);
      expect(
        got,
        <String>[
          'assets/fx/care/water/frame001.png',
          'assets/fx/care/water/frame002.png',
          'assets/fx/care/water/frame003.png',
        ],
      );
    });

    test('frameIndexFor：进度→帧下标，含边界钳制', () {
      expect(frameIndexFor(0.0, 25), 0);
      expect(frameIndexFor(0.5, 25), 12);
      expect(frameIndexFor(0.999, 25), 24);
      expect(frameIndexFor(1.0, 25), 24); // 末帧钳制
      expect(frameIndexFor(0.0, 1), 0);
    });
  });

  group('除草 / 除虫序列帧契约（2026-10-03 玄参交付，各 27 帧 ≠ kFxFrameCount）', () {
    final Map<String, int> clearDirs = <String, int>{
      kCareWeedFxDir: kCareWeedFrameCount,
      kCarePestFxDir: kCarePestFrameCount,
    };

    clearDirs.forEach((String dir, int count) {
      test('$dir：恰有 $count 张、文件名与 fxFrameAssets 契约一致', () {
        final List<String> files = pngsOf(dir);
        expect(files.length, count,
            reason: '$dir 帧数应为 $count，实际 ${files.length}');
        final List<String> expected = fxFrameAssets(dir, count)
            .map((String p) => p.split('/').last)
            .toList();
        expect(files, expected, reason: '$dir 文件名与契约不符');
      });
    });
  });

  group('专注页向日葵序列帧契约（玄参 2026-09-29 交付，**各组帧数不同**）', () {
    final Map<String, int> focusDirs = <String, int>{
      kFocusIdleFxDir: kFocusIdleFrameCount,
      kFocusCollectFxDir: kFocusCollectFrameCount,
      kFocusSettleFxDir: kFocusSettleFrameCount,
      kFocusReturnFxDir: kFocusReturnFrameCount,
    };

    focusDirs.forEach((String dir, int count) {
      test('$dir：恰有 $count 张、文件名与 fxFrameAssets 契约一致', () {
        final List<String> files = pngsOf(dir);
        expect(files.length, count,
            reason: '$dir 帧数应为 $count，实际 ${files.length}');
        final List<String> expected = fxFrameAssets(dir, count)
            .map((String p) => p.split('/').last)
            .toList();
        expect(files, expected, reason: '$dir 文件名与契约不符');
      });
    });
  });

  group('护眼卡序列帧契约（2026-10-09 C43 玄参交付改版：单段 640 帧 WebP q95）', () {
    // C43：5 段素材已剪辑拼为 1 个视频再逐帧导出（过渡更丝滑），旧 5 套
    // （close/doitagain/lookTip/look/done）全部弃用删除。帧走 WebP q95
    // 压缩管线（284.4M PNG → 40.2M，PSNR≈44.8dB 视觉无损）。
    test('单段 640 帧：目录、帧数、命名契约（三位零填充 frame001..640.webp）', () {
      final Directory dir = Directory('$root/${kEyeCareSegment.dir}');
      expect(dir.existsSync(), isTrue,
          reason: '目录缺失：${kEyeCareSegment.dir}');
      final List<String> files = dir
          .listSync()
          .whereType<File>()
          .map((File f) => f.path.split(Platform.pathSeparator).last)
          .where((String n) => n.endsWith('.${kEyeCareSegment.frameExt}'))
          .toList()
        ..sort();
      expect(files.length, kEyeCareSegment.frameCount,
          reason: '帧数应为 ${kEyeCareSegment.frameCount}，实际 ${files.length}');
      final List<String> expected = fxFrameAssets(kEyeCareSegment.dir,
              kEyeCareSegment.frameCount, ext: kEyeCareSegment.frameExt)
          .map((String p) => p.split('/').last)
          .toList();
      expect(files, expected, reason: '文件名与契约不符（三位零填充 frame001..N.webp）');
      // 整幅画面带背景：全部帧统一 720×720（直读 WebP 头，逐张校验）。
      for (final String name in files) {
        final int wh = _webpSize(File('$root/${kEyeCareSegment.dir}/$name'));
        expect(wh, 720 * 720,
            reason: '${kEyeCareSegment.dir}/$name 尺寸漂移（应统一 720×720）');
      }
    });

    test('护眼单配音 eyecare.mp3 存在且 cue 映射齐全', () {
      expect(AudioCue.eyeCare.assetPath, 'assets/audio/sfx/eyecare.mp3');
      expect(File('$root/${AudioCue.eyeCare.assetPath}').existsSync(), isTrue,
          reason: '缺护眼配音：${AudioCue.eyeCare.assetPath}');
    });

    test('旧 5 套素材目录与旧配音已删除（C43 弃用，防误回收）', () {
      expect(Directory('$root/assets/fx/eyecare').existsSync(), isFalse,
          reason: '旧 eyecare 目录应已删除');
      for (final String name in <String>[
        'eyecare_close.mp3',
        'eyecare_doitagain.mp3',
        'eyecare_lookTip.mp3',
        'eyecare_look.mp3',
        'eyecare_done.mp3',
      ]) {
        expect(File('$root/assets/audio/sfx/$name').existsSync(), isFalse,
            reason: '旧配音 $name 应已删除');
      }
    });
  });

  group('音频资产存在性（新 cue + 专注页 cue + 花园氛围音）', () {
    test('AudioCue 新增 cue 的 mp3 文件真实存在', () {
      final List<AudioCue> newCues = <AudioCue>[
        AudioCue.growthSeedToSprout,
        AudioCue.growthSproutToAdult,
        AudioCue.growthAdultToBloomed,
        AudioCue.careWater,
        AudioCue.careFertilize,
        AudioCue.careWeed,
        AudioCue.carePest,
        AudioCue.collectReward,
        AudioCue.shovel,
        AudioCue.cultivate,
        AudioCue.focusCollect,
        AudioCue.focusSettle,
        AudioCue.focusEndCountdown,
        AudioCue.eyeCare,
      ];
      for (final AudioCue cue in newCues) {
        expect(cue.assetPath.endsWith('.mp3'), isTrue,
            reason: '新 cue 应为 mp3：${cue.assetPath}');
        expect(File('$root/${cue.assetPath}').existsSync(), isTrue,
            reason: '缺音频文件：${cue.assetPath}');
      }
    });

    test('专注页回来音 welcome_back.mp3 与 BGM focus_loop.mp3 存在', () {
      expect(AudioCue.welcomeBack.assetPath, endsWith('welcome_back.mp3'));
      expect(File('$root/${AudioCue.welcomeBack.assetPath}').existsSync(), isTrue,
          reason: '缺音频文件：${AudioCue.welcomeBack.assetPath}');
      const String bgm = 'assets/audio/bgm/focus_loop.mp3';
      expect(File('$root/$bgm').existsSync(), isTrue, reason: '缺 BGM：$bgm');
    });

    test('花园氛围音 background.mp3 在 bgm 目录且存在', () {
      expect(kGardenAmbientAsset, startsWith('assets/audio/bgm/'));
      expect(File('$root/$kGardenAmbientAsset').existsSync(), isTrue,
          reason: '缺氛围音文件：$kGardenAmbientAsset');
    });

    test('奖励物 4 张 PNG（阳光/碎片/分档种子）真实存在且为合法 PNG（2026-10-06 玄参交付齐）', () {
      const List<String> rewardPngs = <String>[
        'assets/rewards/sunlight.png',
        'assets/rewards/fragment.png',
        'assets/rewards/seed_common.png',
        'assets/rewards/seed_premium.png',
      ];
      for (final String p in rewardPngs) {
        final RandomAccessFile raf = File('$root/$p').openSync();
        final PngHead head = _readHead(raf);
        raf.closeSync();
        expect(head.w, greaterThan(0), reason: 'PNG 头非法（宽）：$p');
        expect(head.h, greaterThan(0), reason: 'PNG 头非法（高）：$p');
      }
    });
  });

  group('pubspec 资产登记护栏（⚠️ 目录声明不递归，叶子目录必须逐个列全）', () {
    // 2026-09-28 实证翻车：登记了 assets/fx/grow/ 与 assets/fx/care/ 两行，
    // 但帧全在更深一层子目录 → 帧根本没进包，Image.asset errorBuilder 静默吞，
    // 真机「只剩音效没有动画」。本用例钉死：每个序列帧叶子目录必须出现在 pubspec。
    test('fx 全部叶子目录都在 pubspec.yaml 的 assets 里登记', () {
      final String pubspec = File('$root/pubspec.yaml').readAsStringSync();
      final List<String> dirs = <String>[
        growFxDir('sunflower', GrowTransition.seedToSprout),
        growFxDir('sunflower', GrowTransition.sproutToAdult),
        growFxDir('sunflower', GrowTransition.adultToBloomed),
        kCareWaterFxDir,
        kCareFertilizeFxDir,
        kCareWeedFxDir,
        kCarePestFxDir,
        kFocusIdleFxDir,
        kFocusCollectFxDir,
        kFocusSettleFxDir,
        kFocusReturnFxDir,
        ...kEyeCarePlaylist.map((EyeCareSegment s) => s.dir).toSet(),
      ];
      for (final String dir in dirs) {
        expect(pubspec.contains('    - $dir/'), isTrue,
            reason: 'pubspec 必须登记叶子目录「$dir/」——'
                'Flutter 目录声明不递归，漏登记 = 帧静默不进包');
      }
    });
  });

  group('植物静态图画布护栏（C13：1720×2000 全局等盆）', () {
    test('全部 species_*_adult_bloomed.png 画布尺寸符合口径（直读 PNG IHDR）', () {
      final Directory plants = Directory('$root/assets/plants');
      // 2026-10-08 目录重组：植物图按物种分目录存放，改**递归**扫描。
      final List<File> blooms = plants
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('_adult_bloomed.png'))
          .toList();
      expect(blooms.length, 6,
          reason: '6 物种应各有 1 张盛开图（2026-10-08 删星辰花/虹影蕨后余 6：'
              '向日葵 + 番茄 + 草莓 + 月光兰 + 珊瑚岭兰 + 翡翠绣球），实际 ${blooms.length}');
      // 2026-10-09 全局等盆：新五物种统一 1720×2000（盆 800、盆心居中）；向日葵
      // 无 wilted/dead 原图备份、维持 1200×2000 定稿不动 —— contain 按高度绑定
      // 缩放，两种画布的盆显示大小一致（比例同为 800/画布宽 × 高 2000）。
      for (final File f in blooms) {
        final RandomAccessFile raf = f.openSync();
        final PngHead head = _readHead(raf);
        raf.closeSync();
        // PNG: 8 字节签名 + IHDR 长度/类型 8 字节 + 宽高各 4 字节（大端）。
        final int w = head.w;
        final int h = head.h;
        final bool isLegacySunflower =
            f.path.contains('sunflower') && w == 1200 && h == 2000;
        final bool isNewUniform = w == 1720 && h == 2000;
        expect(isLegacySunflower || isNewUniform, isTrue,
            reason: '${f.path.split('/').last} 画布 $w×$h 不符合口径：'
                '向日葵 1200×2000（legacy 定稿）/ 其它物种 1720×2000（全局等盆）');
      }
    });
  });

  group('sfx mp3 时长 ≥3s 红线（直读真实文件 · MPEG 帧头解析）', () {
    // 依据 `docs/美术资源_序列帧与音频命名规范_v1.md` §红线（F77 实证）：
    // 「今后所有 sfx mp3 时长不得 <3s」——过短的 mp3 在 iOS 上 just_audio `setAsset`
    // 会抛 CoreAudio `-11849 NotOptimized`（AudioFileStream 无法解析），且异常被
    // AudioService 静默吞掉 → **无声无日志极难排查**。
    // 本组直读真实文件字节、解析 MPEG 帧头累加时长，**只查常量不算数**（常量与实际
    // 素材可能漂移）；解析不到帧头即失败并打印路径（不静默跳过）。
    const List<AudioCue> sfxCues = <AudioCue>[
      AudioCue.cultivate, // 2026-10-07 apad 2.95s→3.25s
      AudioCue.shovel, // 2026-10-07 apad 0.52s→3.16s
      AudioCue.collectReward, // F77 首案（初版 1.04s → apad 3.58s）
      AudioCue.careWeed,
      AudioCue.carePest,
      AudioCue.careWater,
      AudioCue.careFertilize,
    ];

    for (final AudioCue cue in sfxCues) {
      test('${cue.assetPath} 实际时长 ≥ 3.0s', () {
        final String rel = cue.assetPath;
        final File f = File('$root/$rel');
        expect(f.existsSync(), isTrue, reason: '缺音频文件：$rel');

        late final double seconds;
        try {
          seconds = _mp3DurationSeconds(f.readAsBytesSync());
        } on FormatException catch (e) {
          fail('MPEG 帧头解析失败（不静默跳过）：$rel → ${e.message}');
        }
        final String shown = seconds.toStringAsFixed(3);
        // ignore: avoid_print
        print('  实测 $rel = ${shown}s');
        expect(seconds, greaterThanOrEqualTo(3.0),
            reason: '$rel 实测 ${shown}s < 3.0s 红线（iOS CoreAudio -11849 风险）');
      });
    }
  });

  group('sfx mp3 时长 ≥3s 红线（全目录扫描 assets/audio/sfx/*.mp3）', () {
    // 与上组互补：上组按 [AudioCue] 逐个点名（验证 cue→路径映射），本组**穷举目录**，
    // 防「未来新增 sfx 漏 apad」——目录里出现任何 <3s 的 mp3 即红。
    test('assets/audio/sfx/ 下全部 *.mp3 实际时长 ≥ 3.0s（穷举目录）', () {
      final Directory dir = Directory('$root/assets/audio/sfx');
      expect(dir.existsSync(), isTrue, reason: '缺目录：assets/audio/sfx/');
      final List<File> mp3s = dir
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.toLowerCase().endsWith('.mp3'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
      expect(mp3s, isNotEmpty, reason: 'assets/audio/sfx/ 下应至少有一个 mp3');

      final List<String> failures = <String>[];
      double shortest = double.infinity;
      String shortestName = '';
      for (final File f in mp3s) {
        final String name = f.path.split(Platform.pathSeparator).last;
        late final double seconds;
        try {
          seconds = _mp3DurationSeconds(f.readAsBytesSync());
        } on FormatException catch (e) {
          failures.add('$name → 帧头解析失败：${e.message}');
          continue;
        }
        if (seconds < shortest) {
          shortest = seconds;
          shortestName = name;
        }
        if (seconds < 3.0) {
          failures.add('$name → ${seconds.toStringAsFixed(3)}s (<3.0s 红线)');
        }
      }
      // ignore: avoid_print
      print('  sfx mp3 文件数=${mp3s.length}；最短=$shortestName '
          '${shortest.toStringAsFixed(3)}s');
      expect(failures, isEmpty,
          reason: '以下 sfx mp3 未过 ≥3s 红线（iOS CoreAudio -11849 风险）：\n'
              '${failures.join('\n')}');
    });
  });
}

/// 直读 mp3 字节、解析 MPEG 音频帧头并**逐帧累加**时长（CBR / VBR 均适用，无第三方依赖）。
///
/// 帧头格式（ISO/IEC 11172-3 / 13818-3），4 字节大端：
///   位 31..21 帧同步（11 个 1，字节级掩码 `0xFF 0xE0`）
///   位 20..19 MPEG 版本：3=MPEG1 / 2=MPEG2 / 0=MPEG2.5 / 1=保留
///   位 18..17 Layer：3=LayerI / 2=LayerII / 1=LayerIII / 0=保留
///   位 15..12 比特率索引；位 11..10 采样率索引；位 9 padding
/// 找不到合法帧头、或未累加到任何帧 → 抛 [FormatException]（调用方据此失败/报路径）。
double _mp3DurationSeconds(List<int> bytes) {
  int pos = _skipId3v2(bytes);
  // 先扫到第一个合法帧头（跳过 ID3 尾部 / 元数据里的伪同步字）。
  while (pos + 4 <= bytes.length && _parseMp3FrameHeader(bytes, pos) == null) {
    pos++;
  }
  if (pos + 4 > bytes.length) {
    throw const FormatException('整文件未找到合法 MPEG 帧头（0xFFEx）');
  }

  double totalSeconds = 0;
  int frames = 0;
  while (pos + 4 <= bytes.length) {
    final _Mp3FrameHeader? h = _parseMp3FrameHeader(bytes, pos);
    if (h == null) break; // 尾部非帧数据（如 ID3v1 的 'TAG'）→ 结束
    totalSeconds += h.samplesPerFrame / h.sampleRate;
    frames++;
    pos += h.frameLength;
  }
  if (frames == 0) {
    throw const FormatException('未累加到任何 MPEG 帧');
  }
  return totalSeconds;
}

/// 跳过 ID3v2 标签（若存在）：10 字节头 + syncsafe 尺寸 + 可选 footer（+10B）。
int _skipId3v2(List<int> b) {
  if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) {
    return 0; // 非 'ID3'
  }
  final int size = ((b[6] & 0x7F) << 21) |
      ((b[7] & 0x7F) << 14) |
      ((b[8] & 0x7F) << 7) |
      (b[9] & 0x7F);
  int skip = 10 + size;
  if ((b[5] & 0x10) != 0) skip += 10; // footer present
  return skip <= b.length ? skip : 0;
}

/// 解析 `pos` 处 4 字节帧头；非法（保留值 / free / bad 索引）返回 null。
_Mp3FrameHeader? _parseMp3FrameHeader(List<int> b, int pos) {
  if (pos + 4 > b.length) return null;
  if (b[pos] != 0xFF || (b[pos + 1] & 0xE0) != 0xE0) return null;

  final int hdr =
      (b[pos] << 24) | (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
  final int versionBits = (hdr >> 19) & 0x3;
  final int layerBits = (hdr >> 17) & 0x3;
  final int bitrateIdx = (hdr >> 12) & 0xF;
  final int sampleRateIdx = (hdr >> 10) & 0x3;
  final int padding = (hdr >> 9) & 0x1;

  if (versionBits == 1 || layerBits == 0) return null; // 保留
  if (bitrateIdx == 0 || bitrateIdx == 15) return null; // free / bad
  if (sampleRateIdx == 3) return null; // 保留

  final bool isV1 = versionBits == 3;
  final int samplesPerFrame = switch (layerBits) {
    3 => 384, // Layer I
    2 => 1152, // Layer II
    _ => isV1 ? 1152 : 576, // Layer III：MPEG1=1152 / MPEG2/2.5=576
  };
  final int sampleRate = switch (versionBits) {
    3 => _sampleRateV1[sampleRateIdx],
    2 => _sampleRateV2[sampleRateIdx],
    _ => _sampleRateV25[sampleRateIdx],
  };
  final int bitrateKbps = switch (layerBits) {
    3 => (isV1 ? _bitrateV1L1 : _bitrateV2L1)[bitrateIdx],
    2 => (isV1 ? _bitrateV1L2 : _bitrateV2L23)[bitrateIdx],
    _ => (isV1 ? _bitrateV1L3 : _bitrateV2L23)[bitrateIdx],
  };
  if (bitrateKbps <= 0) return null;

  final int bitrate = bitrateKbps * 1000;
  // Layer I：帧长按 4 字节槽对齐；Layer II/III：帧长 = 每帧采样数/8 × 码率 ÷ 采样率。
  final int frameLength = layerBits == 3
      ? ((12 * bitrate ~/ sampleRate) + padding) * 4
      : (samplesPerFrame ~/ 8) * bitrate ~/ sampleRate + padding;

  return _Mp3FrameHeader(
    sampleRate: sampleRate,
    samplesPerFrame: samplesPerFrame,
    frameLength: frameLength,
  );
}

// ── MPEG 比特率 / 采样率表（kbps / Hz）────────────────────────────────────────

const List<int> _bitrateV1L1 = <int>[
  0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0,
];
const List<int> _bitrateV1L2 = <int>[
  0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0,
];
const List<int> _bitrateV1L3 = <int>[
  0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
];
const List<int> _bitrateV2L1 = <int>[
  0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0,
];
const List<int> _bitrateV2L23 = <int>[
  0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
];
const List<int> _sampleRateV1 = <int>[44100, 48000, 32000, 0];
const List<int> _sampleRateV2 = <int>[22050, 24000, 16000, 0];
const List<int> _sampleRateV25 = <int>[11025, 12000, 8000, 0];

/// 单个 MPEG 帧的解析结果。
class _Mp3FrameHeader {
  const _Mp3FrameHeader({
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.frameLength,
  });

  final int sampleRate;
  final int samplesPerFrame;
  final int frameLength;
}

/// 只读 PNG 头 24 字节，解析 IHDR 宽高（避免引 image 包）。
class PngHead {
  PngHead(this.bytes);
  final List<int> bytes;

  int get w => (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  int get h => (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
}

PngHead _readHead(RandomAccessFile raf) {
  final List<int> bytes = <int>[];
  for (int i = 0; i < 24; i++) {
    bytes.add(raf.readByteSync());
  }
  return PngHead(bytes);
}

/// 直读 WebP 头 30 字节，解析画布宽高；返回 `w * h`（不匹配 720×720 即测试失败）。
///
/// 支持三种 chunk：`VP8 `（lossy 简单格式，C43 管线产物）、`VP8L`（无损）、
/// `VP8X`（扩展）。格式不符抛 [FormatException]。
int _webpSize(File f) {
  final RandomAccessFile raf = f.openSync();
  final List<int> b = <int>[];
  for (int i = 0; i < 30; i++) {
    b.add(raf.readByteSync());
  }
  raf.closeSync();
  // RIFF....WEBP（12 字节容器头）
  if (String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(b.sublist(8, 12)) != 'WEBP') {
    throw const FormatException('非 WebP 容器（RIFF/WEBP 头缺失）');
  }
  final String fourcc = String.fromCharCodes(b.sublist(12, 16));
  switch (fourcc) {
    case 'VP8 ': // lossy：帧 tag 3B（20..22）+ 同步码 9D 01 2A（23..25）+ 宽高 LE 14bit
      if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) {
        throw const FormatException('VP8 同步码缺失');
      }
      final int w = (b[26] | (b[27] << 8)) & 0x3FFF;
      final int h = (b[28] | (b[29] << 8)) & 0x3FFF;
      return w * h;
    case 'VP8L': // lossless：签名 0x2F（20）+ 14bit w-1 / 14bit h-1
      if (b[20] != 0x2F) throw const FormatException('VP8L 签名缺失');
      final int bits =
          b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1) * (((bits >> 14) & 0x3FFF) + 1);
    case 'VP8X': // 扩展：canvas w-1 / h-1 各 24bit LE（24..26 / 27..29）
      final int w = b[24] | (b[25] << 8) | (b[26] << 16);
      final int h = b[27] | (b[28] << 8) | (b[29] << 16);
      return (w + 1) * (h + 1);
    default:
      throw FormatException('未支持的 WebP chunk：$fourcc');
  }
}
