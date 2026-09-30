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

  group('音频资产存在性（新 cue + 专注页 cue + 花园氛围音）', () {
    test('AudioCue 新增 cue 的 mp3 文件真实存在', () {
      final List<AudioCue> newCues = <AudioCue>[
        AudioCue.growthSeedToSprout,
        AudioCue.growthSproutToAdult,
        AudioCue.growthAdultToBloomed,
        AudioCue.careWater,
        AudioCue.careFertilize,
        AudioCue.focusCollect,
        AudioCue.focusSettle,
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
        kFocusIdleFxDir,
        kFocusCollectFxDir,
        kFocusSettleFxDir,
        kFocusReturnFxDir,
      ];
      for (final String dir in dirs) {
        expect(pubspec.contains('    - $dir/'), isTrue,
            reason: 'pubspec 必须登记叶子目录「$dir/」——'
                'Flutter 目录声明不递归，漏登记 = 帧静默不进包');
      }
    });
  });

  group('植物静态图画布护栏（C13：1200×2000）', () {
    test('全部 species_*_adult_bloomed.png 均为 1200×2000（直读 PNG IHDR）', () {
      final Directory plants = Directory('$root/assets/plants');
      final List<File> blooms = plants
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('_adult_bloomed.png'))
          .toList();
      expect(blooms.length, 8,
          reason: '8 物种应各有 1 张盛开图（向日葵 + 7 新交付），实际 ${blooms.length}');
      for (final File f in blooms) {
        final RandomAccessFile raf = f.openSync();
        final PngHead head = _readHead(raf);
        raf.closeSync();
        // PNG: 8 字节签名 + IHDR 长度/类型 8 字节 + 宽高各 4 字节（大端）。
        final int w = head.w;
        final int h = head.h;
        expect('$w x $h', '1200 x 2000',
            reason: '${f.path.split('/').last} 未归一化到 1200×2000');
      }
    });
  });
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
